extends Node
## FX01-19: imported structure, timed playback, lit rendering and real death routing.
const GOO := preload("res://assets/art/vfx/combat_3d/vfx_zombie_goo_death_root_top3d.tscn")
const RAW_BURST := preload("res://assets/art/vfx/combat_3d/zombie_goo_death/vfx_zombie_goo_burst_source_top3d.tscn")
const RAW_POOL := preload("res://assets/art/vfx/combat_3d/zombie_goo_death/vfx_zombie_goo_pool_source_top3d.tscn")
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const ORIGIN := Vector3(2.0, -1176.0, -3.0)
var failures: Array[String] = []
var killed := 0

func _ready() -> void:
	call_deferred("run")

func check(valid: bool, detail: String) -> void:
	if not valid:
		failures.append(detail)

func source_emitters(root: Node3D) -> Array[Node]:
	return root.find_children("Particle_1", "Node3D", true, false)

func check_source(instance: Node3D, raw_scene: PackedScene, expected: int) -> void:
	var raw := raw_scene.instantiate() as Node3D
	var original_emitters := source_emitters(raw)
	var game_emitters := source_emitters(instance)
	check(game_emitters.size() == expected and original_emitters.size() == expected, "源发射器数量不符")
	for i in mini(game_emitters.size(), original_emitters.size()):
		var node := game_emitters[i]
		var reference := original_emitters[i]
		check(instance.get_path_to(node) == raw.get_path_to(reference), "实例不得重排源层级")
		var instance_data: Dictionary = node.get("source").duplicate(false)
		var original_data: Dictionary = reference.get("source")
		var instance_render: Dictionary = instance_data.renderer.duplicate(true)
		var original_render: Dictionary = original_data.renderer
		check(bool(instance_render.receive_shadows), "源粒子实例应接收阴影")
		instance_render.receive_shadows = original_render.receive_shadows
		for slot in instance_render.materials.size():
			var settings: Dictionary = instance_render.materials[slot]
			check(is_equal_approx(float(settings.get("_LightingEnabled", 0.0)), 1.0), "源贴图实例须受光")
			if original_render.materials[slot].has("_LightingEnabled"):
				settings["_LightingEnabled"] = original_render.materials[slot]["_LightingEnabled"]
			else:
				settings.erase("_LightingEnabled")
			if expected == 1:
				var tint: Array = settings["_Color"]
				check(is_equal_approx(float(tint[0]), 0.64) and is_equal_approx(float(tint[1]), 0.64) and is_equal_approx(float(tint[2]), 0.64) and tint[3] == 1.0, "地面绿浆仅压低颜色亮度，不改变透明度")
				settings["_Color"] = original_render.materials[slot]["_Color"]
		instance_data.renderer = instance_render
		if expected == 1:
			var growth: Dictionary = instance_data.size_over_lifetime
			var original_growth: Dictionary = original_data.size_over_lifetime
			for pair: Array in [[growth.size["keys"], original_growth.size["keys"]], [growth.size.curve["keys"], original_growth.size.curve["keys"]]]:
				for k in pair[0].size():
					var key: Dictionary = pair[0][k]
					var source_key: Dictionary = pair[1][k]
					check(key.t == source_key.t and is_equal_approx(float(key.v), 0.70 + 0.30 * float(source_key.v)), "绿浆曲线应从峰值 70% 开始，保持原关键帧时间")
			instance_data.size_over_lifetime = original_growth
		else:
			var is_droplet: bool = node.get("component_key") == "0#1"
			var main: Dictionary = instance_data.main.duplicate(false)
			for param in [&"start_size", &"start_lifetime"]:
				var scaled: Dictionary = main[param]
				var original: Dictionary = original_data.main[param]
				var gain := (2.0 / 1.30) * (2.0 if is_droplet else 1.0) if param == &"start_size" else (1.30 if is_droplet else 1.0)
				for field in ["constant", "min", "max"]:
					if original.has(field):
						check(is_equal_approx(float(scaled[field]), float(original[field]) * gain), "%s %s 调参不符" % [node.get("component_key"), param])
				main[param] = original
			instance_data.main = main
		check(instance_data == original_data and node.get("main_texture") == reference.get("main_texture"), "只允许实例级尺寸、寿命、亮度与受光调整")
	raw.free()

func check_lit_draw(root: Node3D) -> void:
	var verified := 0
	for child in root.find_children("*", "GeometryInstance3D", true, false):
		var draw := child as GeometryInstance3D
		var material := draw.material_override as ShaderMaterial
		if material == null or not draw.visible:
			continue
		verified += 1
		var code := material.shader.code
		check(code.contains("#define VFX_LIT 1") and not code.contains("unshaded") and not code.contains("shadows_disabled"), "渲染材质必须实际走受光/阴影分支")
	check(verified > 0, "未产生材质可核验的绘制实例")

func run() -> void:
	var fx := GOO.instantiate() as VfxEffectBase3D
	add_child(fx)
	var burst := fx.get_node("LibraryBurst") as Node3D
	var pool := fx.get_node("LibraryPool") as Node3D
	check(fx.get_meta("asset_version") == "v004" and fx.get_child_count() == 2, "正式 Prefab 版本或结构错误")
	fx.activate(ORIGIN + Vector3.UP * 0.65, Color.WHITE, 1.0, {"floor_y": ORIGIN.y})
	check_source(burst, RAW_BURST, 2)
	check_source(pool, RAW_POOL, 1)
	fx.set_process(false)
	burst.set_physics_process(false)
	burst.call("advance_exact", 1.0 / 60.0)
	var burst_state: Dictionary = burst.call("debug_exact")
	var births := 0
	for value: Dictionary in burst_state.layers.values():
		births += int(value.burst_births)
	check(births == 13 and burst_state.source_id == "GreenBloodExplosionRound2", "致死立即播放原版 1 主爆点 + 12 飞溅")
	check_lit_draw(burst)
	check_droplet_playback(fx, burst)
	check(burst.scale.is_equal_approx(Vector3.ONE * 1.105), "爆散轨迹整体放大30%")
	check(pool.global_position.is_equal_approx(ORIGIN + Vector3.UP * 0.025) and pool.scale.is_equal_approx(Vector3.ONE * 2.405), "地面池定位深层地面，铺展范围放大30%")
	fx.call("_on_tick", 0.159, 1.35)
	check(not pool.visible, "地面池不得早于0.16秒出现")
	fx.call("_on_tick", 0.16, 1.35)
	var pool_state: Dictionary = pool.call("debug_exact", true)
	var particles: Array = pool_state.layers["#1"].particles
	check(pool.visible and pool_state.source_id == "GreenBloodPoolGrowing" and particles.size() == 6, "地面池应保留原六份贴图粒子")
	for p: Dictionary in particles:
		var ratio := float(p.size.x) / float(p.initial_size.x)
		check(ratio >= 0.699 and ratio <= 0.71, "实播首帧绿浆须在峰值的七成，实测比值 %.4f" % ratio)
	check_lit_draw(pool)
	fx.call("_on_tick", 1.34, 1.35)
	pool_state = pool.call("debug_exact")
	check(pool_state.layers["#1"].burst_births == 6 and float(pool_state.elapsed) > 6.5, "原曲线必须完成且不能循环重生")
	fx.retired.connect(func(_effect: VfxEffectBase3D) -> void: pass)
	fx.finish()
	check(not burst.visible and not pool.visible and not burst.is_physics_processing() and not pool.is_physics_processing(), "回收时两段均隐藏且停止")
	fx.activate(ORIGIN + Vector3.UP * 0.65, Color.WHITE, 0.5)
	check(burst.scale.is_equal_approx(Vector3.ONE * 0.5525) and not pool.visible, "复借应复位尺寸及时序")
	fx.finish()
	fx.queue_free()
	await check_real_death("melee_chaser")
	await check_real_death("ranged_caster")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("ZOMBIE_GOO_DEATH_VFX_OK: source structure, lighting, timing, pool and melee/police routing")
	get_tree().quit(0 if failures.is_empty() else 1)

func check_droplet_playback(tuned: VfxEffectBase3D, burst: Node3D) -> void:
	var baseline := GOO.instantiate() as VfxZombieGooDeath3D
	baseline.droplet_size_gain = 1.0
	baseline.droplet_lifetime_gain = 1.0
	add_child(baseline)
	baseline.activate(tuned.global_position, Color.WHITE, 1.0, {"floor_y": ORIGIN.y})
	baseline.set_process(false)
	var old_burst := baseline.get_node("LibraryBurst") as Node3D
	old_burst.set_physics_process(false)
	old_burst.call("advance_exact", 1.0 / 60.0)
	var before: Dictionary = old_burst.call("debug_exact", true)
	var after: Dictionary = burst.call("debug_exact", true)
	var old_drops: Array = before.layers["0#1"].particles
	var new_drops: Array = after.layers["0#1"].particles
	check(old_drops.size() == 12 and new_drops.size() == 12 and after.sub_trigger_calls == 0, "原飞滴为同帧发出的 12 颗，不是后续子发射")
	check(before.layers["#1"].particles == after.layers["#1"].particles, "中心爆花实播不得变化")
	for i in mini(old_drops.size(), new_drops.size()):
		var p: Dictionary = old_drops[i]
		var q: Dictionary = new_drops[i]
		check((p.initial_size as Vector3).is_equal_approx(q.initial_size / 2.0), "飞滴初始尺寸须翻倍")
		check(is_equal_approx(float(q.life), float(p.life) * 1.30), "飞滴寿命须增加 30%")
		check((p.world_velocity as Vector3).is_equal_approx(q.world_velocity), "飞滴初速度不应改变")
	for scene in [old_burst, burst]:
		scene.call("advance_exact", 0.61 - 1.0 / 60.0)
	before = old_burst.call("debug_exact")
	after = burst.call("debug_exact")
	check(before.layers["0#1"].live == 0 and after.layers["0#1"].live > 0 and after.layers["0#1"].drawn > 0, "0.61 秒时旧版已消失，新版应仍有飞滴可绘制")
	check(after.layers["0#1"].burst_births == 12, "后段不得补发额外粒子")
	print("GOO_DROPLETS_AT_0_61S: old=%d new=%d drawn=%d" % [before.layers["0#1"].live, after.layers["0#1"].live, after.layers["0#1"].drawn])
	baseline.free()

func check_real_death(kind: String) -> void:
	var pool := get_node("/root/VfxPool") as VfxPool3D
	var before := pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH)
	var enemy := ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	enemy.configure_from_enemy_data({"enemy_type": kind, "loot_table": ""})
	enemy.global_position = ORIGIN
	enemy.set_physics_process(false)
	var killed_before := killed
	enemy.killed.connect(func(_enemy: Enemy3D, _data: Dictionary) -> void: killed += 1)
	enemy.take_damage(enemy.current_hp + 1)
	check(pool.active_count(VfxPool3D.FX01_ZOMBIE_GOO_DEATH) == before + 1, kind + " 须走正式特效池")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(enemy) and killed == killed_before + 1, kind + " 不得留下尸体或重复结算")
