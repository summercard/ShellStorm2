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
	check(fx.get_meta("asset_version") == "v005" and fx.get_child_count() == 2, "正式 Prefab 版本或结构错误")
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
	check_pool_recession(fx, pool)
	check(not burst.visible and not pool.visible and not burst.is_physics_processing() and not pool.is_physics_processing(), "回收时两段均隐藏且停止")
	fx.activate(ORIGIN + Vector3.UP * 0.65, Color.WHITE, 0.5)
	check(burst.scale.is_equal_approx(Vector3.ONE * 0.5525) and not pool.visible, "复借应复位尺寸及时序")
	fx.call("_on_tick", 0.16, fx.lifetime)
	check(pool.visible and is_equal_approx(pool.scale.x, 1.2025) and absf(pool.global_position.y - (ORIGIN.y + 0.025)) < 0.0002, "复借不得保留缩小或下沉")
	check(is_equal_approx(pool_material_alpha(pool), 1.0), "复借不得保留淡出透明度")
	fx.finish()
	fx.queue_free()
	await check_real_death("melee_chaser")
	await check_real_death("ranged_caster")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("ZOMBIE_GOO_DEATH_VFX_OK: source structure, lighting, timing, pool and melee/police routing")
	get_tree().quit(0 if failures.is_empty() else 1)

func pool_material_alpha(pool: Node3D) -> float:
	for child in pool.find_children("*", "GeometryInstance3D", true, false):
		var draw := child as GeometryInstance3D
		var material := draw.material_override as ShaderMaterial
		if draw.visible and material != null:
			var tint: Variant = material.get_shader_parameter("tint")
			if tint is Color:
				return tint.a
	return -1.0

func pool_draw_transforms(pool: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for child in pool.find_children("*", "GeometryInstance3D", true, false):
		var draw := child as GeometryInstance3D
		if not draw.visible:
			continue
		if draw is MultiMeshInstance3D:
			for i in draw.multimesh.visible_instance_count:
				result.append(draw.global_transform * draw.multimesh.get_instance_transform(i))
		elif draw is MeshInstance3D:
			result.append(draw.global_transform)
	return result

func check_pool_recession(fx: VfxEffectBase3D, pool: Node3D) -> void:
	check(is_equal_approx(fx.lifetime, 2.55), "正式生命周期须追加 1.20 秒")
	var start_scale := pool.scale
	var start_pos := pool.global_position
	fx.call("_on_tick", 1.35, fx.lifetime)
	var start: Dictionary = pool.call("debug_exact", true)
	check(pool.visible and start.layers["#1"].live == 6 and start.layers["#1"].drawn == 6, "收尾必须从原六份绿浆无缝接上")
	check(pool.scale.is_equal_approx(start_scale) and pool.global_position.is_equal_approx(start_pos) and is_equal_approx(pool_material_alpha(pool), 1.0), "收尾起点不得跳尺寸、位置或亮度")
	# Dummy rendering does not retain MultiMesh instance transforms for readback.
	var can_read_draws := DisplayServer.get_name() != "headless"
	# 显式声明成无类型 Array：三元表达式会从另一个分支推出 Array[Transform3D]，
	# 而 headless 走 `[]` 这一支是普通 Array，运行期报
	# "Trying to assign an array of type Array to a variable of type Array[Transform3D]"
	# 并被算作 UNEXPECTED_ENGINE_ERROR，整条门禁在 headless 下必红。
	var start_draws: Array = pool_draw_transforms(pool) if can_read_draws else []
	fx.call("_on_tick", 1.95, fx.lifetime)
	check(pool.scale.is_equal_approx(start_scale), "收尾不许缩放根节点")
	if can_read_draws:
		var middle_draws := pool_draw_transforms(pool)
		check(start_draws.size() == 6 and middle_draws.size() == 6, "必须保留六个独立绘制中心")
		var distinct_centers := false
		for i in mini(start_draws.size(), middle_draws.size()):
			var before: Transform3D = start_draws[i]
			var after := middle_draws[i]
			var first: Vector3 = start_draws[0].origin
			distinct_centers = distinct_centers or Vector2(before.origin.x, before.origin.z).distance_to(Vector2(first.x, first.z)) > 0.001
			check(absf(after.origin.x - before.origin.x) < 0.0001 and absf(after.origin.z - before.origin.z) < 0.0001, "绿浆片 %d 须以自身中心收缩" % i)
			check(absf(after.origin.y - (before.origin.y - 0.012)) < 0.0002 and after.basis.get_scale().is_equal_approx(before.basis.get_scale() * 0.56), "绿浆片 %d 应原地缩至 56%% 并下沉 12mm" % i)
		check(distinct_centers, "验收样本必须包含不重合的绿浆中心")
		if distinct_centers and start_draws.size() == 6 and middle_draws.size() == 6:
			print("GOO_INDIVIDUAL_PIVOTS_CHECKED: 6 original draw centers")
	check(absf(pool.global_position.y - (start_pos.y - 0.012)) < 0.0002 and is_equal_approx(pool_material_alpha(pool), 0.5), "尾段中点应下沉 12mm、透明度减半")
	var middle: Dictionary = pool.call("debug_exact")
	check(middle.elapsed == start.elapsed and middle.layers["#1"].burst_births == 6, "收尾不得重播、增发或继续推进原曲线")
	fx.call("_on_tick", 2.55, fx.lifetime)
	check(is_zero_approx(pool_material_alpha(pool)) and absf(pool.global_position.y - (ORIGIN.y + 0.001)) < 0.0002, "回收前须完全淡出，不能被地板深度硬切")
	fx.retired.connect(func(_effect: VfxEffectBase3D) -> void: pass)
	fx.call("_process", 2.55)

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
