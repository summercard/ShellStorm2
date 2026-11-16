extends Node3D
## 启动前隔离APPDATA；截图仅写入工程外的显式证据目录。

const ORIGIN := Vector3(23.0, -1175.28, -17.0)
const MODULES := ["standard", "sticky", "bounce", "piercing", "explosive", "homing", "blackhole", "balloon"]
const ELEMENTS := ["fire", "ice", "poison", "lightning"]
const EXPECTED_LIFETIMES := {"fire": 0.28, "ice": 0.34, "poison": 0.38, "lightning": 0.16, "bounce": 0.23, "homing": 0.25, "return": 0.30}
var _checks := 0
var _failures: Array[String] = []
var _pool: ProjectilePool3D


func _ready() -> void:
	if OS.get_environment("PROJECTILE_ENCHANT_VERIFY_ISOLATED") != "1":
		push_error("主代理必须在启动Godot前隔离APPDATA并设置PROJECTILE_ENCHANT_VERIFY_ISOLATED=1")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	_pool = ProjectilePool3D.new()
	add_child(_pool)
	_check_prefabs_and_textures()
	_check_counts_and_module_identity()
	_check_behavior_routing()
	_check_pool_reuse_and_follow()
	_check_configure_before_tree()
	await _check_live_particle_reuse()
	if OS.get_cmdline_user_args().has("--render-grid"):
		await _render_grid()
	print("PROJECTILE_ENCHANT_VISUALS_RESULT ", JSON.stringify({
		"checks": _checks, "failures": _failures,
		"passed": _failures.is_empty(), "render_reviewed": false,
	}))
	_pool.free()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _config(behavior: Dictionary, module: String = "standard") -> Dictionary:
	return {"visual_id": "mod_bullet_" + module, "speed": 23.0, "damage": 17,
		"direction": Vector3.FORWARD, "behavior": behavior, "tags": [],
		"projectile_collision_mask": 0, "billboard": false}


func _spawn(behavior: Dictionary, module: String = "standard") -> Projectile3D:
	var projectile := _pool.acquire(_config(behavior, module), ORIGIN)
	projectile.set_physics_process(false)
	return projectile


func _check_prefabs_and_textures() -> void:
	for key in EXPECTED_LIFETIMES:
		var path := "res://assets/art/vfx/combat_3d/vfx_projectile_enchant_%s_root_top3d.tscn" % key
		var packed := load(path) as PackedScene
		_check(packed != null, "独立Prefab可加载：" + key)
		if packed == null:
			continue
		var fx := packed.instantiate() as VfxEffectBase3D
		add_child(fx)
		_check(fx != null, "Prefab继承VfxEffectBase3D：" + key)
		_check(fx.get_meta("asset_id") == "VFX-PROJECTILE-ENCHANT-%s-3D" % key.to_upper(), "独立AssetID：" + key)
		_check(fx.get_meta("asset_version") == "v001" and fx.scene_file_path == path, "v001元信息和稳定路径：" + key)
		_check(fx.lifetime == 0.0, "持续附件没有自动到期计时：" + key)
		_check(fx.find_children("*", "CollisionObject3D", true, false).is_empty(), "附件无物理体：" + key)
		_check(fx.find_children("*", "CollisionShape3D", true, false).is_empty(), "附件无碰撞形状：" + key)
		_check(fx.find_children("*", "Light3D", true, false).is_empty(), "附件无灯：" + key)
		var emitters := fx.find_children("*", "GPUParticles3D", true, false)
		_check(emitters.size() == 1, "每件恰好一个真实GPU发射器：" + key)
		var particles := emitters[0] as GPUParticles3D
		var mesh := particles.draw_pass_1 as QuadMesh
		_check(mesh != null, "使用贴图QuadMesh而非纯色球：" + key)
		var material := mesh.material as StandardMaterial3D
		_check(material != null and material.albedo_texture != null, "实际粒子材质挂载纹理：" + key)
		_check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "粒子不受光：" + key)
		_check(material.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES, "粒子公告板：" + key)
		_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.vertex_color_use_as_albedo, "真实alpha及寿命渐隐：" + key)
		_check(particles.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "粒子无阴影：" + key)
		_check((particles.process_material as ParticleProcessMaterial).collision_mode == ParticleProcessMaterial.COLLISION_DISABLED, "GPU粒子无碰撞：" + key)
		_check(particles.local_coords and not particles.trail_enabled, "局部空间跟随且无持久尾迹：" + key)
		var texture_path := "res://assets/art/vfx/textures/projectile_enchant_%s.png" % key
		_check(material.albedo_texture.resource_path == texture_path, "纹理稳定路径：" + key)
		# 从PNG源字节解码，避免headless纹理回读阻塞渲染线程。
		var image := Image.load_from_file(texture_path)
		_check(image != null and image.get_format() == Image.FORMAT_RGBA8 and image.get_size() == Vector2i(256, 256), "真实256平方RGBA PNG：" + key)
		_check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(255, 0).a == 0.0 and image.get_pixel(0, 255).a == 0.0 and image.get_pixel(255, 255).a == 0.0, "贴图四角透明：" + key)
		var content := 0
		var transparent := 0
		var colors: Dictionary = {}
		for y in range(0, 256, 8):
			for x in range(0, 256, 8):
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.1:
					content += 1
					colors[pixel.to_rgba32()] = true
				else:
					transparent += 1
		_check(content > 12 and transparent > 80 and colors.size() > 8, "非空且有内部层次的透明图形：" + key)
		fx.configure(Color.WHITE, 1.0, {"attribute_count": 1})
		fx.call("set_emitting", true)
		fx._process(2.0)
		var sustained: Dictionary = fx.call("get_enchantment_snapshot")
		_check(sustained.emitting and not fx.is_queued_for_deletion(), "附件长于基类寿命仍由宿主持有：" + key)
		fx.call("deactivate")
		_check(not particles.emitting and not particles.visible and not fx.visible, "停用立即隐藏并停止真实发射器：" + key)
		fx.free()


func _check_counts_and_module_identity() -> void:
	for module in MODULES:
		var plain := _spawn({}, module)
		var baseline := plain.get_orientation_snapshot()
		var visual_instance := plain._visual.get_instance_id()
		_check(plain.get_enchantment_snapshot().attachments.is_empty(), "空属性无附件：" + module)
		_check(not plain.get_enchantment_snapshot().emitting, "空属性无发射：" + module)
		plain._retire()
		for count in range(1, 5):
			var elements: Dictionary = {}
			for index in count:
				elements[ELEMENTS[index]] = {"dot_duration": 3.0, "dot_damage_per_sec": 0.05}
			var behavior := {"fate_elements": elements}
			if count == 4:
				behavior["chain_lightning"] = true
				behavior["chain_count"] = 3
			var original := behavior.duplicate(true)
			var projectile := _spawn(behavior, module)
			var snapshot := projectile.get_enchantment_snapshot()
			_check(snapshot.visual_id == "mod_bullet_" + module, "模块visual_id不被元素替换：%s/%d" % [module, count])
			_check(projectile._visual.get_instance_id() == visual_instance, "模块主体实例未重建：%s/%d" % [module, count])
			_check(projectile.get_orientation_snapshot().visual_profile == baseline.visual_profile, "模块形状profile保持：%s/%d" % [module, count])
			_check(is_equal_approx(projectile.get_orientation_snapshot().collision_radius, baseline.collision_radius), "附魔不改碰撞球：%s/%d" % [module, count])
			_check(projectile.damage == 17 and projectile.speed == 23.0 and projectile.direction == Vector3.FORWARD, "不改伤害速度方向")
			_check(projectile.fate_behavior == original and behavior == original, "不改行为或原持续伤害数据")
			_check(snapshot.attribute_count == count and snapshot.attachments.size() == count, "属性数去重")
			_check(snapshot.total_amount == 24, "1/2/3/4总粒子预算24")
			for entry in snapshot.attachments:
				_check(entry.amount == [24, 12, 8, 6][count - 1], "每种粒子准确24/12/8/6")
				_check(entry.emitting and entry.visible, "启用属性真实发射可见")
				_check(is_equal_approx(entry.particle_lifetime, EXPECTED_LIFETIMES[entry.attribute]), "分摊数量不缩短粒子寿命")
				var fx := projectile.get_node("ProjectileEnchantments/Enchant_" + entry.attribute)
				_check((fx.get_node("Particles") as GPUParticles3D).amount == entry.amount, "快照数量等于真实发射器")
			projectile._retire()


func _check_behavior_routing() -> void:
	var cases := [
		{"behavior": {"chain_lightning": true}, "expected": ["lightning"]},
		{"behavior": {"chain_lightning": true, "chain_count": 0}, "expected": []},
		{"behavior": {"chain_count": 3}, "expected": []},
		{"behavior": {"fate_elements": {"lightning": {}}, "chain_lightning": true, "chain_count": 4}, "expected": ["lightning"]},
		{"behavior": {"bounce_count": 3}, "expected": ["bounce"]},
		{"behavior": {"bounce_count": 0, "bounce": true}, "expected": []},
		{"behavior": {"homing": true}, "expected": ["homing"]},
		{"behavior": {"return_on_hit": true}, "expected": ["return"]},
		{"behavior": {"return_to_player": true}, "expected": ["return"]},
		{"behavior": {"home_on_land": true, "return_on_hit": true, "return_to_player": true}, "expected": ["return"]},
		{"behavior": {"description": "火焰冰霜剧毒闪电追踪反弹返航", "fate_elements": {"unknown": {}}}, "expected": []},
	]
	for sample in cases:
		var projectile := _spawn(sample.behavior)
		_check(projectile.get_enchantment_snapshot().attributes == sample.expected, "只按实际行为键路由：" + str(sample.behavior))
		projectile._retire()
	var all_behavior := {"fate_elements": {"fire": {}, "ice": {}, "poison": {}, "lightning": {}}, "chain_lightning": true, "chain_count": 3, "bounce_count": 2, "homing": true, "return_on_hit": true}
	var all := _spawn(all_behavior)
	var snapshot := all.get_enchantment_snapshot()
	_check(snapshot.attribute_count == 7 and snapshot.total_amount == 21, "非元素也计入N：7种各floor(24/7)=3")
	for entry in snapshot.attachments:
		_check(entry.amount == 3, "所有属性共享预算")
	all._retire()


func _check_pool_reuse_and_follow() -> void:
	var projectile := _spawn({"fate_elements": {"fire": {}, "ice": {}, "poison": {}}, "chain_lightning": true, "chain_count": 3})
	var id := projectile.get_instance_id()
	var first := projectile.get_enchantment_snapshot()
	var ids: Dictionary = {}
	for entry in first.attachments:
		ids[entry.attribute] = entry.instance_id
		_check(entry.world_position.distance_to(ORIGIN) < 0.001, "深楼层附件出生点跟随宿主")
	projectile.global_position += Vector3(4.0, -12.0, 3.0)
	projectile.direction = Vector3.RIGHT
	projectile._sync_visual_orientation()
	for entry in projectile.get_enchantment_snapshot().attachments:
		_check(entry.world_position.distance_to(projectile.global_position) < 0.001, "移动旋转后附件不钉世界零高度")
	var detached := projectile.get_enchantment_snapshot()
	detached.attributes.clear()
	detached.attachments[0]["amount"] = 999
	_check(projectile.get_enchantment_snapshot().attribute_count == 4 and projectile.get_enchantment_snapshot().attachments[0].amount == 6, "快照是副本而非可写内部状态")
	projectile._retire()
	_check_clean(projectile)
	var reused := _spawn({})
	_check(reused.get_instance_id() == id, "真实ProjectilePool3D回收复借同一实例")
	_check_clean(reused)
	reused._retire()
	reused = _spawn({"fate_elements": {"fire": {}}})
	var next := reused.get_enchantment_snapshot()
	_check(next.attributes == ["fire"] and next.attachments[0].amount == 24, "复借清空旧属性并恢复单属性24")
	_check(next.attachments[0].instance_id == ids.fire, "发射器缓存复用而非逐发重建")
	for entry in next.cached_attachments:
		if entry.attribute != "fire":
			_check(not entry.emitting and not entry.visible and not entry.configured and entry.amount == 0, "旧属性缓存彻底停用")
	var emitters := reused.find_children("*", "GPUParticles3D", true, false).size()
	for index in 20:
		reused._physics_process(0.0)
	_check(reused.find_children("*", "GPUParticles3D", true, false).size() == emitters, "运动帧不创建新发射器")
	reused._retire()
	_check_clean(reused)
	var config := _config({"fate_elements": {"fire": {}}})
	config["visual_scale"] = 2.0
	config["gun_bullet_geometry"] = {"scale": 1.5, "grow_from": 0.5, "grow_duration": 0.3}
	reused = _pool.acquire(config, ORIGIN)
	reused.set_physics_process(false)
	var fx := reused.get_node("ProjectileEnchantments/Enchant_fire") as Node3D
	_check(fx.scale.is_equal_approx(Vector3.ONE * 1.5), "附件尺寸适配弹体出生生长倍率")
	fx._process(0.3)
	_check(fx.scale.is_equal_approx(Vector3.ONE * 3.0), "附件跟随弹体既有生长而非改变碰撞")
	reused._retire()
	reused = _spawn({"fate_elements": {"fire": {}}})
	_check(reused.get_enchantment_snapshot().attachments[0].visual_scale.is_equal_approx(Vector3.ONE), "复借尺寸与生长时钟复位")
	reused._retire()


func _check_clean(projectile: Projectile3D) -> void:
	var snapshot := projectile.get_enchantment_snapshot()
	_check(snapshot.attributes.is_empty() and snapshot.attachments.is_empty() and not snapshot.emitting and snapshot.total_amount == 0, "空属性或回收快照全清")
	for entry in snapshot.cached_attachments:
		_check(not entry.emitting and not entry.visible and not entry.configured and entry.amount == 0 and entry.flight_time == 0.0, "缓存粒子及属性时钟全清")
		var fx := projectile.get_node("ProjectileEnchantments/Enchant_" + entry.attribute)
		var particles := fx.get_node("Particles") as GPUParticles3D
		_check(not particles.emitting and not particles.visible and particles.speed_scale == 0.0, "真实GPU发射器停止并冻结隐藏")


func _check_configure_before_tree() -> void:
	var projectile := Projectile3D.new()
	projectile.configure(_config({"fate_elements": {"fire": {}}}, "piercing"))
	add_child(projectile)
	projectile.set_physics_process(false)
	projectile.global_position = ORIGIN
	_check(projectile.get_enchantment_snapshot().visual_id == "mod_bullet_piercing", "configure先于入树保持模块路由")
	_check(projectile.get_enchantment_snapshot().attachments[0].emitting, "旧非池化configure→入树路径也激活附件")
	projectile.free()


func _check_live_particle_reuse() -> void:
	var projectile := _spawn({"fate_elements": {"fire": {}, "poison": {}}})
	var id := projectile.get_instance_id()
	# 留出真实渲染帧，让粒子先存在，再检测回收及新位置复借。
	await get_tree().create_timer(0.20).timeout
	projectile._retire()
	_check_clean(projectile)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_clean(projectile)
	var reused := _pool.acquire(_config({"fate_elements": {"ice": {}}}), ORIGIN + Vector3(9, -12, 0))
	reused.set_physics_process(false)
	_check(reused.get_instance_id() == id, "真实渲染帧后仍复借同一宿主")
	await get_tree().process_frame
	var snapshot := reused.get_enchantment_snapshot()
	_check(snapshot.attributes == ["ice"] and snapshot.total_amount == 24, "真实跨帧复借只显示新属性")
	for entry in snapshot.cached_attachments:
		if entry.attribute != "ice":
			_check(not entry.emitting and not entry.visible, "已发射过的旧GPU粒子跨帧保持隐藏")
	reused._retire()
	_check_clean(reused)


func _render_grid() -> void:
	var output := OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	var project_dir := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var output_dir := ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var safe_output := output.is_absolute_path() and output_dir != project_dir and not output_dir.begins_with(project_dir + "/")
	_check(safe_output, "截图目录必须显式指定且在工程外")
	_check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus", "截图必须使用真实Forward+渲染")
	if not safe_output or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "工程外截图目录可用")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.012, 0.025, 0.065)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.32, 0.43, 0.65)
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	light.light_energy = 1.1
	add_child(light)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.025, 0.05, 0.10)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 18)
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	floor_mesh.position = ORIGIN + Vector3(0, -0.45, 0)
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.055, 0.12, 0.20)
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for line in range(-12, 13):
		grid.surface_add_vertex(Vector3(line, 0, -9))
		grid.surface_add_vertex(Vector3(line, 0, 9))
	for line in range(-9, 10):
		grid.surface_add_vertex(Vector3(-12, 0, line))
		grid.surface_add_vertex(Vector3(12, 0, line))
	grid.surface_end()
	var grid_mesh := MeshInstance3D.new()
	grid_mesh.mesh = grid
	add_child(grid_mesh)
	grid_mesh.position = ORIGIN + Vector3(0, -0.44, 0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = ORIGIN + Vector3(0, 12, 8)
	camera.look_at(ORIGIN)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.4
	camera.current = true
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var heading := Label.new()
	heading.position = Vector2(24, 16)
	heading.add_theme_font_size_override("font_size", 24)
	overlay.add_child(heading)
	heading.text = "七种单附魔 + 四元素混合 / 八模块原形对照\n左：无附魔　右：真实GPU附件　|　展示倍率×2　|　楼层 y=%.2f" % ORIGIN.y
	var samples := Node3D.new()
	add_child(samples)
	var shots: Array[Projectile3D] = []
	var keys: Array = EXPECTED_LIFETIMES.keys()
	keys.append("fire+ice+poison+lightning")
	for index in MODULES.size():
		var center := ORIGIN + Vector3((index % 4 - 1.5) * 3.15, 0, (floori(index / 4.0) - 0.5) * 3.2)
		var key: String = keys[index]
		var behavior := _render_behavior(key) if index < 7 else {"fate_elements": {"fire": {}, "ice": {}, "poison": {}, "lightning": {}}}
		shots.append(_render_shot({}, MODULES[index], center + Vector3(-0.65, 0, 0)))
		shots.append(_render_shot(behavior, MODULES[index], center + Vector3(0.65, 0, 0)))
		_render_label(samples, center + Vector3(0, 0, 0.85), "%s\n%s / amount=%d" % [MODULES[index], key, 24 if index < 7 else 6])
	await get_tree().create_timer(1.0).timeout
	await _capture_render(output, "projectile_enchant_grid", shots)
	for shot in shots:
		shot._retire()
	shots.clear()
	samples.free()
	samples = Node3D.new()
	add_child(samples)
	camera.size = 6.4
	heading.text = "单 / 双 / 三 / 四元素真实GPU发射对照\n每种 amount=24 / 12 / 8 / 6　|　总预算24　|　主体与附件统一展示倍率×2"
	for row in 2:
		var module: String = "standard" if row == 0 else "piercing"
		for count in range(1, 5):
			var elements: Dictionary = {}
			var names := PackedStringArray()
			for index in count:
				elements[ELEMENTS[index]] = {}
				names.append(ELEMENTS[index])
			var center := ORIGIN + Vector3((count - 2.5) * 2.7, 0, (row - 0.5) * 3.0)
			shots.append(_render_shot({"fate_elements": elements}, module, center))
			_render_label(samples, center + Vector3(0, 0, 0.85), "%s / N=%d / amount=%d\n%s" % [module, count, 24 / count, "+".join(names)])
	await get_tree().create_timer(1.0).timeout
	await _capture_render(output, "projectile_enchant_mix", shots)
	for shot in shots:
		shot._retire()
	samples.free()


func _render_behavior(key: String) -> Dictionary:
	if key == "bounce":
		return {"bounce_count": 2}
	if key == "homing":
		return {"homing": true}
	if key == "return":
		return {"return_on_hit": true}
	return {"fate_elements": {key: {}}}


func _render_shot(behavior: Dictionary, module: String, world_position: Vector3) -> Projectile3D:
	var config := _config(behavior, module)
	config["visual_scale"] = 2.0
	var projectile := _pool.acquire(config, world_position)
	# 仅停宿主位移；子节点处理和GPU模拟照常运行，不改Prefab或粒子预算。
	projectile.set_physics_process(false)
	return projectile


func _render_label(parent: Node3D, world_position: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 28
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.74, 0.87, 1.0)
	parent.add_child(label)
	label.global_position = world_position


func _capture_render(output: String, label: String, shots: Array[Projectile3D]) -> void:
	for shot in shots:
		var snapshot := shot.get_enchantment_snapshot()
		for entry in snapshot.attachments:
			var particles := shot.get_node("ProjectileEnchantments/Enchant_" + entry.attribute + "/Particles") as GPUParticles3D
			_check(particles.emitting and particles.visible and particles.speed_scale == 1.0 and particles.amount == floori(24.0 / snapshot.attribute_count), "截图时真实发射器持续运行：" + label + "/" + entry.attribute)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "真实viewport截图非空：" + label)
	if image != null and not image.is_empty():
		var path := output.path_join(label + ".png")
		_check(image.save_png(path) == OK, "截图保存：" + label)
		print("CAPTURE ", path)
