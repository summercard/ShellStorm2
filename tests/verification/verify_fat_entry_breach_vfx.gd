extends Node3D

const ID := &"VFX-FAT-ENTRY-BREACH-3D"
const PREFAB := preload("res://assets/art/vfx/combat_3d/vfx_fat_entry_breach_root_top3d.tscn")
var failures: Array[String] = []
var checks := 0
var samples: Array = []
const FLOOR_Y := -1176.0
const ORIGIN := Vector3(23, FLOOR_Y, -17)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("2026-11-16_exp01_combat/vfx_followup/"):
		push_error("必须在Autoload前隔离APPDATA")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	_setup_stage()
	await _units()
	if OS.get_cmdline_user_args().has("--render"):
		await _render_sequence()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "samples": samples}
	var file := FileAccess.open(OS.get_environment("FAT_BREACH_EVIDENCE").path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FAT_ENTRY_BREACH_RESULT ", JSON.stringify(report))
	VfxPool.clear_kind(ID)
	get_tree().quit(0 if failures.is_empty() else 1)

func _setup_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.028, 0.036, 0.055)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.8, 1.0)
	environment.environment.ambient_light_energy = 0.75
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = ORIGIN + Vector3(10, 9, 12)
	camera.look_at(ORIGIN + Vector3(0, 1.0, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	camera.current = true
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-52, -28, 0)
	light.light_energy = 1.1
	light.shadow_enabled = false
	var floor := MeshInstance3D.new()
	floor.mesh = BoxMesh.new()
	(floor.mesh as BoxMesh).size = Vector3(15, 0.1, 15)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.15, 0.20)
	material.roughness = 0.9
	floor.material_override = material
	add_child(floor)
	floor.global_position = ORIGIN - Vector3(0, 0.05, 0)

func _spawn(context: Dictionary = {}) -> Node3D:
	var fx := VfxPool.acquire(ID, ORIGIN, Color.WHITE, 1.0, context)
	fx.set_process(false)
	return fx

func _units() -> void:
	check(VfxPool.has_effect(ID), "AssetID已注册")
	check(ID in VfxPool.COMBAT_PREWARM, "本件进入战斗预热列表")
	for name_suffix in ["flame_a", "flame_b", "smoke", "dust"]:
		var image := Image.load_from_file("res://assets/art/vfx/textures/vfx_fat_entry_breach_" + name_suffix + ".png")
		check(image != null and image.get_format() == Image.FORMAT_RGBA8, "运行贴图真实RGBA：" + name_suffix)
		check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(image.get_width()-1, image.get_height()-1).a == 0.0, "运行贴图角落真实透明：" + name_suffix)
		var opaque := 0
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				if image.get_pixel(x, y).a > 0.4:
					opaque += 1
		check(opaque > 30, "运行贴图不是空alpha：" + name_suffix)
	VfxPool.prewarm([ID])
	while VfxPool.has_pending_prewarm():
		await get_tree().process_frame
	check(VfxPool.active_count(ID) == 1, "真实默认预热创建活跃样本")
	var warm: Node3D = VfxPool._active[ID][0]
	var warm_snapshot: Dictionary = warm.get_presentation_snapshot()
	check(warm_snapshot.piece_count == 5 and warm_snapshot.particle_budget == 80, "无context预热完整装配家具与80个原拖尾/落尘粒子")
	check(warm.find_children("*", "MeshInstance3D", true, false).size() >= 8, "预热不是家具空壳")
	warm.finish()
	check(not warm.visible and VfxPool.inactive_count(ID) == 1, "提前取消正常回池")
	var context := {"seed":77123, "floor_y":FLOOR_Y, "forward":Vector3.RIGHT, "landing_distance_m":4.0}
	var fx := _spawn(context)
	check(fx == warm, "预热样本被正式复借")
	check(fx.get_meta("asset_id") == String(ID) and fx.get_meta("asset_version") == "v002", "资产身份v002")
	check(fx.find_children("*", "CollisionObject3D", true, false).is_empty(), "无碰撞及伤害承载节点")
	check(fx.find_children("*", "CollisionShape3D", true, false).is_empty(), "无碰撞形状")
	check(fx.find_children("*", "Light3D", true, false).size() == 1, "最多一盏短灯")
	for geometry in fx.find_children("*", "GeometryInstance3D", true, false):
		check(geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "几何与粒子均不投影")
	for particles in fx.find_children("*", "GPUParticles3D", true, false):
		var material: StandardMaterial3D = particles.draw_pass_1.material
		check(particles.draw_pass_1 is QuadMesh and material.albedo_texture != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "真实透明Quad粒子材质")
		check(not particles.local_coords and particles.use_fixed_seed, "粒子世界拖尾与固定seed")
	var initial: Dictionary = fx.get_presentation_snapshot()
	var heights := [1.244, .865, 1.741, 1.244, .865]
	for index in 5:
		check(absf(initial.bounds[index].size.y - heights[index]) < 0.025, "家具真实尺寸双向校验%d" % index)
	var library := fx.get_node("LibraryBurst") as Node3D
	fx._on_tick(0.30, 3.65)
	check(not library.visible, "库爆点不在家具推挤阶段提前播放")
	var pushed: Dictionary = fx.get_presentation_snapshot()
	fx._on_tick(0.40, 3.65)
	var burst_state: Dictionary = library.call("debug_exact")
	check(library.visible and burst_state.running and burst_state.source_id == "ExplosionRoundFire" and burst_state.audio_play_calls == 0, "0.40秒触发库爆点，保留宿主音效")
	check(pushed.transforms[0].origin.distance_to(initial.transforms[0].origin) > 0.1, "爆破前有短推挤")
	fx._on_tick(0.95, 3.65)
	var flying: Dictionary = fx.get_presentation_snapshot()
	check(flying.lowest_y > FLOOR_Y + 1.0, "家具明确离地上抛")
	check(flying.transforms[0].basis != pushed.transforms[0].basis, "飞行多轴翻滚")
	check(fx.get_node("BreachLight").light_energy == 0.0, "短灯0.63秒前熄灭")
	fx._on_tick(2.35, 3.65)
	var landed: Dictionary = fx.get_presentation_snapshot()
	check(landed.landed_count == 5, "全部家具已砸边落地")
	check(landed.lowest_y >= FLOOR_Y - 0.002 and landed.lowest_y <= FLOOR_Y + 0.03, "非零深层floor_y精确贴地不穿地")
	for transform in landed.transforms:
		var distance: float = Vector2(transform.origin.x-ORIGIN.x, transform.origin.z-ORIGIN.z).length()
		check(distance >= 3.249 and distance <= 3.251, "Host约4m净空内实际落点中心收紧至3.25m")
	fx._elapsed = 3.64
	fx._process(0.02)
	check(not fx.visible and VfxPool.active_count(ID) == 0 and VfxPool.inactive_count(ID) == 1, "真实生命周期到期回收")
	for particles in fx.find_children("*", "GPUParticles3D", true, false):
		check(not particles.emitting and not particles.visible, "回收清空粒子显示与发射")
	var reused := _spawn(context)
	check(reused == fx and reused.visible, "完整回收后同实例再次可见")
	reused._on_tick(0.95, 3.65)
	check(reused.get_presentation_snapshot().transforms == flying.transforms, "同seed复借确定性变换逐位相同")
	for mesh in reused.get_node("Furniture").find_children("*", "MeshInstance3D", true, false):
		check(mesh.transparency == 0.0 and mesh.is_visible_in_tree(), "复借恢复家具alpha和可见性")
	reused.finish()
	var changed := context.duplicate()
	changed.seed = 99111
	var other := _spawn(changed)
	other._on_tick(0.95, 3.65)
	check(other.get_presentation_snapshot().transforms != flying.transforms, "不同seed改变散布翻滚")
	other.finish()
	changed = context.duplicate()
	changed.forward = Vector3.FORWARD
	var rotated := _spawn(changed)
	rotated._on_tick(0.95, 3.65)
	var forward_snapshot: Dictionary = rotated.get_presentation_snapshot()
	var a: Vector3 = flying.transforms[0].origin - ORIGIN
	var b: Vector3 = forward_snapshot.transforms[0].origin - ORIGIN
	check(absf(a.x + b.z) < .002 and absf(a.z - b.x) < .002, "forward旋转整个表演")
	rotated.finish()
	changed.landing_distance_m = 2.1
	var near := _spawn(changed)
	near._on_tick(2.35, 3.65)
	for transform in near.get_presentation_snapshot().transforms:
		check(Vector2(transform.origin.x-ORIGIN.x, transform.origin.z-ORIGIN.z).length() <= 2.101, "窄边界距离由Host收紧")
	near.finish()
	# 最紧Host契约也必须保留明显爆后飞出；全yaw实测初始十对AABB。
	for seed_value in [77123, 99111]:
		for yaw_index in 72:
			var tight_context := {"seed":seed_value, "floor_y":FLOOR_Y, "forward":Vector3.FORWARD.rotated(Vector3.UP, yaw_index * TAU / 72.0), "landing_distance_m":3.5}
			var tight := _spawn(tight_context)
			var start: Dictionary = tight.get_presentation_snapshot()
			for i in 5:
				for j in i:
					check(not (start.transforms[i] * start.bounds[i]).intersects(start.transforms[j] * start.bounds[j]), "最紧净空全yaw初始AABB不相交")
			tight._on_tick(0.40, 3.65)
			var push: Dictionary = tight.get_presentation_snapshot()
			tight._on_tick(2.35, 3.65)
			var rest: Dictionary = tight.get_presentation_snapshot()
			for i in 5:
				var delta: Vector3 = rest.transforms[i].origin - push.transforms[i].origin
				check(Vector2(delta.x, delta.z).length() >= 1.49999, "最紧3.5m净空爆后水平飞出至少1.5m")
			tight.finish()
	var default_fx := _spawn()
	check(default_fx.get_presentation_snapshot().floor_y == FLOOR_Y, "未传floor_y回落出生高度而非世界0")
	default_fx.finish()
	var standalone := PREFAB.instantiate()
	add_child(standalone)
	standalone.activate(ORIGIN, Color.WHITE, 1.0, context)
	standalone._process(3.66)
	check(standalone.is_queued_for_deletion(), "无池独立Prefab到期自释放")
	await get_tree().process_frame

func _render_sequence() -> void:
	var fx := VfxPool.acquire(ID, ORIGIN, Color.WHITE, 1.0, {"seed":20261116,"floor_y":FLOOR_Y,"forward":Vector3.FORWARD})
	fx.set_process(true)
	var markers := [[0.28,"push"],[0.62,"burst"],[1.12,"flight"],[1.95,"landing"],[2.70,"tail_dust"]]
	for marker in markers:
		while fx._elapsed < float(marker[0]):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := OS.get_environment("FAT_BREACH_EVIDENCE").path_join("fat_entry_" + marker[1] + ".png")
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "保存真实渲染"+marker[1])
		samples.append({"stage":marker[1],"elapsed":fx._elapsed,"snapshot":fx.get_presentation_snapshot(),"image":path})
		print("FAT_BREACH_CAPTURE ", path)
	while VfxPool.active_count(ID) > 0:
		await get_tree().process_frame
	check(not fx.visible, "真实渲染播放后自然回收")
