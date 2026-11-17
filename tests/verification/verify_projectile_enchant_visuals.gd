extends Node3D
## 启动前隔离APPDATA；截图仅写入工程外的显式证据目录。

signal motion_stepped

const ORIGIN := Vector3(23.0, -1175.28, -17.0)
const MODULES := ["standard", "sticky", "bounce", "piercing", "explosive", "homing", "blackhole", "balloon"]
const ELEMENTS := ["fire", "ice", "poison", "lightning"]
const EXPECTED_LIFETIMES := {"fire": 0.28, "ice": 0.34, "poison": 0.38, "lightning": 0.16, "bounce": 0.23, "homing": 0.25, "return": 0.30}
const ENCHANT_VISUALS = preload("res://src/vfx/projectile_enchant/ProjectileEnchantmentVisuals3D.gd")
const EXPECTED_TINTS := {
	"fire": Color(1.0, 0.22, 0.06), "ice": Color(0.52, 0.86, 1.0),
	"poison": Color(0.42, 0.90, 0.26), "lightning": Color(0.52, 0.78, 1.0),
	"bounce": Color(1.0, 0.66, 0.30), "homing": Color(0.36, 1.0, 0.78),
	"return": Color(0.78, 0.56, 1.0),
}
const EXPECTED_QUADS := {
	"fire": Vector2(0.32, 0.44), "ice": Vector2(0.28, 0.38),
	"poison": Vector2(0.38, 0.38), "lightning": Vector2(0.34, 0.46),
	"bounce": Vector2(0.30, 0.34), "homing": Vector2(0.30, 0.40),
	"return": Vector2(0.34, 0.38),
}
const RENDER_SCALE := 2.0
var _checks := 0
var _failures: Array[String] = []
var _pool: ProjectilePool3D
var _moving_shots: Array[Projectile3D] = []
var _motion_elapsed := 0.0
var _motion_distance := 0.0


func _process(delta: float) -> void:
	if _moving_shots.is_empty():
		return
	_motion_elapsed += delta
	_motion_distance += 2.0 * delta
	for shot in _moving_shots:
		# 仅宿主按真实渲染delta手动平移；GPU继续用自身delta，绝不手工推进粒子。
		shot.global_position += Vector3.RIGHT * 2.0 * delta
	motion_stepped.emit()


func _ready() -> void:
	if OS.get_environment("PROJECTILE_ENCHANT_VERIFY_ISOLATED") != "1":
		push_error("主代理必须在启动Godot前隔离APPDATA并设置PROJECTILE_ENCHANT_VERIFY_ISOLATED=1")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	_pool = ProjectilePool3D.new()
	add_child(_pool)
	_check_prefabs_and_textures()
	_check_light_prefabs()
	_check_light_cache_switching()
	_check_light_scale_and_growth()
	_check_counts_and_module_identity()
	_check_behavior_routing()
	_check_body_tints_and_restore()
	_check_axial_material_isolation()
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
		"projectile_collision_mask": 0, "billboard": false,
		"color": WeaponModel3D.BULLET_COLORS["mod_bullet_" + module]}


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
		_check(fx.get_meta("asset_version") == "v002" and fx.scene_file_path == path, "v002元信息和稳定路径：" + key)
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
		_check_wrap_and_tail(sustained, particles, key)
		_check(sustained.emitting and not fx.is_queued_for_deletion(), "附件长于基类寿命仍由宿主持有：" + key)
		fx.call("deactivate")
		_check(not particles.emitting and not particles.visible and not fx.visible, "停用立即隐藏并停止真实发射器：" + key)
		fx.free()


func _check_light_prefabs() -> void:
	var scripts: Dictionary = {}
	for key in EXPECTED_TINTS:
		var path := "res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_%s_root_top3d.tscn" % key
		var packed := load(path) as PackedScene
		_check(packed != null, "七种独立灯Prefab真实可加载：" + key)
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		_check(instance != null, "独立灯Prefab根为Node3D：" + key)
		if instance == null:
			continue
		add_child(instance)
		_check(instance.get_script() == load("res://src/vfx/projectile_enchant/ProjectileEnchantLight3D.gd"), "独立灯使用当前灯管理脚本：" + key)
		var lights := instance.find_children("*", "Light3D", true, false)
		_check(lights.size() == 1 and lights[0] is OmniLight3D, "每种灯Prefab恰好一盏真实OmniLight3D：" + key)
		_check(instance.find_children("*", "GPUParticles3D", true, false).is_empty() and instance.find_children("*", "CollisionObject3D", true, false).is_empty() and instance.find_children("*", "CollisionShape3D", true, false).is_empty(), "独立灯不复制粒子或引入碰撞：" + key)
		if lights.size() == 1 and lights[0] is OmniLight3D:
			var light := lights[0] as OmniLight3D
			_check(light.light_color.is_equal_approx(EXPECTED_TINTS[key]), "灯Prefab预设为对应附魔色：" + key)
			_check(light.visible and is_equal_approx(light.light_energy, 1.15) and is_equal_approx(light.omni_range, 1.75), "灯Prefab默认启用且energy=1.15/range=1.75：" + key)
			_check(not light.shadow_enabled and light.light_cull_mask == 3 and light.shadow_caster_mask == 3, "灯Prefab无影且双mask=3：" + key)
			_check(light.is_scale_disabled(), "灯Prefab入树禁用世界缩放继承：" + key)
		var snapshot: Dictionary = instance.call("get_light_snapshot")
		_check(snapshot.preset_key == key and snapshot.scene_path == path and snapshot.asset_id == "VFX-PROJECTILE-ENCHANT-LIGHT-%s-3D" % key.to_upper(), "独立灯路径与AssetID稳定：" + key)
		_check(snapshot.asset_version == "v001" and snapshot.lifecycle_owner == "Projectile3D", "独立灯版本与宿主持有契约：" + key)
		scripts[key] = instance.get_script()
		instance.call("reset")
		snapshot = instance.call("get_light_snapshot")
		_check(not snapshot.active and not snapshot.visible and not snapshot.visible_in_tree and is_zero_approx(snapshot.energy), "独立灯reset立即归零隐藏：" + key)
		instance.free()
	_check(scripts.size() == 7, "七种独立灯Prefab均完成实例验证")


func _check_enchantment_light(projectile: Projectile3D, keys: Array) -> void:
	var snapshot := projectile.get_enchantment_snapshot()
	var entry: Dictionary = snapshot.enchantment_light
	var context := "%s/%s" % [snapshot.visual_id, str(keys)]
	_check(snapshot.active_light_count == 1 and not entry.is_empty(), "单/多属性始终只有一盏活跃附魔灯：" + context)
	if entry.is_empty():
		return
	var key: String = keys[0]
	var attachment := projectile.get_node("ProjectileEnchantments/Enchant_" + key)
	var object := attachment.get_node_or_null("EnchantLight_" + key) as Node3D
	_check(object != null and object.get_instance_id() == entry.instance_id, "独立灯对象实际挂在首属性Enchant_key下：" + context)
	if object == null:
		return
	_check(object.scene_file_path == "res://assets/art/vfx/combat_3d/vfx_projectile_enchant_light_%s_root_top3d.tscn" % key and entry.scene_path == object.scene_file_path and entry.preset_key == key, "实际复用对应独立灯Prefab而非主体灯：" + context)
	_check(entry.parent_attachment == "Enchant_" + key and entry.parent_attachment_instance_id == attachment.get_instance_id() and object.get_parent() == attachment, "灯快照父对象与真实粒子附件一致：" + context)
	_check(entry.color.is_equal_approx(_expected_average(keys)) and entry.color.is_equal_approx(snapshot.body_tint), "独立灯色为去重属性tint的RGB平均：" + context)
	var light := object.get_node("EnchantmentLight") as OmniLight3D
	_check(object.find_children("*", "Light3D", true, false).size() == 1 and light != null, "独立对象内恰好一盏真实灯：" + context)
	if light == null:
		return
	_check(light.light_color.is_equal_approx(entry.color) and entry.active and entry.visible and entry.visible_in_tree and light.visible and light.is_visible_in_tree(), "新灯真实颜色及入树可见状态等于快照：" + context)
	_check(is_equal_approx(entry.energy, 1.15) and is_equal_approx(light.light_energy, 1.15) and is_equal_approx(entry.range, 1.75) and is_equal_approx(light.omni_range, 1.75), "附魔灯真实能量及范围固定1.15/1.75：" + context)
	_check(not entry.shadow_enabled and not light.shadow_enabled and entry.light_cull_mask == 3 and light.light_cull_mask == 3 and entry.shadow_caster_mask == 3 and light.shadow_caster_mask == 3, "附魔灯真实无影且mask=3：" + context)
	var world: Transform3D = entry.world_transform
	_check(entry.scale_disabled and light.is_scale_disabled() and world.is_equal_approx(light.global_transform) and world.basis.get_scale().is_equal_approx(Vector3.ONE), "附魔灯世界basis不继承尺寸缩放：" + context)
	_check(world.origin.distance_to(projectile.global_position) < 0.001, "附魔灯世界位置跟随弹心：" + context)
	var active_count := 0
	for cached in snapshot.cached_lights:
		var cached_object := projectile.get_node("ProjectileEnchantments/" + cached.parent_attachment + "/EnchantLight_" + cached.preset_key) as Node3D
		var cached_light := cached_object.get_node("EnchantmentLight") as OmniLight3D
		if cached.active:
			active_count += 1
			_check(cached.instance_id == entry.instance_id, "活跃缓存就是当前唯一灯对象：" + context)
		else:
			_check(not cached.visible and not cached.visible_in_tree and is_zero_approx(cached.energy) and not cached_object.visible and not cached_light.visible and is_zero_approx(cached_light.light_energy), "非当前属性的缓存灯无残留：" + context)
	_check(active_count == 1, "遍历全部灯缓存仍仅一盏活跃：" + context)
	var actual_count := 0
	for candidate in projectile.find_children("*", "Light3D", true, false):
		var actual := candidate as Light3D
		if actual.is_visible_in_tree() and actual.light_energy > 0.0:
			actual_count += 1
	_check(actual_count == 1, "整发真实层级仅附魔灯投光，无主体或缓存重复光：" + context)


func _check_light_cache_switching() -> void:
	var host_id := 0
	var ids: Dictionary = {}
	for cycle in 3:
		for key in EXPECTED_TINTS:
			var shot := _spawn(_render_behavior(key))
			if host_id == 0:
				host_id = shot.get_instance_id()
			_check(shot.get_instance_id() == host_id, "七属性切换始终复借同一宿主：%d/%s" % [cycle, key])
			_check_enchantment_light(shot, [key])
			var snapshot := shot.get_enchantment_snapshot()
			var entry: Dictionary = snapshot.enchantment_light
			if not entry.is_empty():
				if ids.has(key):
					_check(entry.instance_id == ids[key], "七灯跨轮切换复借原独立对象：%d/%s" % [cycle, key])
				else:
					ids[key] = entry.instance_id
			_check(snapshot.cached_lights.size() == ids.size(), "灯缓存仅按已见单属性增长，无逐发新增：%d/%s" % [cycle, key])
			shot._retire()
			_check_clean(shot)
		var plain := _spawn({})
		_check(plain.get_instance_id() == host_id and plain.get_enchantment_snapshot().cached_lights.size() == 7, "每轮无附魔复借保留七灯缓存")
		_check_clean(plain)
		plain._retire()
	_check(ids.size() == 7, "七个单属性灯缓存齐备")
	var unique_ids: Dictionary = {}
	for id in ids.values():
		unique_ids[id] = true
	_check(unique_ids.size() == 7, "七属性拥有七个不同灯对象，不共享实例")


func _check_light_scale_and_growth() -> void:
	var config := _config(_render_behavior("fire"))
	config["visual_scale"] = 2.0
	config["gun_bullet_geometry"] = {"scale": 1.5, "axial": 3.0, "grow_from": 0.5, "grow_duration": 0.3}
	var shot := _pool.acquire(config, ORIGIN)
	shot.set_physics_process(false)
	var fx := shot.get_node("ProjectileEnchantments/Enchant_fire") as Node3D
	var first := shot.get_enchantment_snapshot()
	var world: Transform3D = first.enchantment_light.world_transform
	_check(fx.scale.is_equal_approx(Vector3.ONE * 1.5), "光缩放验证确实使用出生1.5倍的粒子父对象")
	_check_enchantment_light(shot, ["fire"])
	fx._process(0.3)
	var grown := shot.get_enchantment_snapshot()
	var grown_world: Transform3D = grown.enchantment_light.world_transform
	_check(fx.scale.is_equal_approx(Vector3.ONE * 3.0), "光缩放验证确实推进到父对象3倍生长")
	_check(grown_world.basis.is_equal_approx(world.basis) and grown_world.basis.get_scale().is_equal_approx(Vector3.ONE), "父对象scale/growth改变时光世界basis保持不变且单位缩放")
	_check_enchantment_light(shot, ["fire"])
	shot.global_position += Vector3(3.0, -9.0, 2.0)
	shot.direction = Vector3.RIGHT
	shot._sync_visual_orientation()
	var moved := shot.get_enchantment_snapshot()
	var moved_world: Transform3D = moved.enchantment_light.world_transform
	_check(moved_world.basis.is_equal_approx(shot.global_basis.orthonormalized()) and not moved_world.basis.is_equal_approx(world.basis), "禁缩放仍继承宿主实际朝向，不钉死世界旋转")
	_check_enchantment_light(shot, ["fire"])
	shot._retire()
	_check_clean(shot)
	var reused := _spawn(_render_behavior("fire"))
	var restored := reused.get_enchantment_snapshot()
	_check(restored.enchantment_light.instance_id == first.enchantment_light.instance_id and restored.attachments[0].visual_scale.is_equal_approx(Vector3.ONE), "生长后复借原灯对象并恢复中性父尺寸")
	_check_enchantment_light(reused, ["fire"])
	reused._retire()
	_check_clean(reused)


func _check_wrap_and_tail(snapshot: Dictionary, particles: GPUParticles3D, key: String) -> void:
	var material := particles.process_material as ParticleProcessMaterial
	_check(snapshot.emitter_position.is_equal_approx(Vector3.ZERO) and particles.position.is_equal_approx(Vector3.ZERO), "发射器中心offset=0：" + key)
	_check(snapshot.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX and material.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX, "使用中心box体积分布而非点或外环：" + key)
	var extents: Vector3 = snapshot.emission_box_extents
	_check(extents.x + 0.000001 >= 0.075 and extents.y + 0.000001 >= 0.075 and extents.z + 0.000001 >= 0.12, "box半径及轴长覆盖标准弹身：" + key)
	_check(snapshot.quad_size.is_equal_approx(EXPECTED_QUADS[key]), "v002粗粒子Quad尺寸：" + key)
	_check(is_equal_approx(snapshot.scale_min, 1.1) and is_equal_approx(snapshot.scale_max, 1.25), "粗粒子最小缩放1.1而非细碎火星：" + key)
	var curve := (material.scale_curve as CurveTexture).curve
	for age in [0.0, 0.25, 0.5, 0.75, 1.0]:
		_check(is_equal_approx(curve.sample(age), 1.0), "寿命中不缩成细点：%s/%.2f" % [key, age])
	_check(is_equal_approx(snapshot.birth_scale, 1.0) and is_equal_approx(snapshot.end_scale, 1.0), "快照出生到结束保持粗尺寸：" + key)
	var gradient := (material.color_ramp as GradientTexture1D).gradient
	var previous_alpha := 1.0
	for age in [0.0, 0.12, 0.4, 0.65, 0.85, 1.0]:
		var tint := gradient.sample(age)
		_check(Color(tint.r, tint.g, tint.b).is_equal_approx(EXPECTED_TINTS[key]), "粒子整个寿命RGB保持属性色：%s/%.2f" % [key, age])
		_check(tint.a <= previous_alpha and tint.a >= 0.0, "alpha随寿命单调渐隐：%s/%.2f" % [key, age])
		previous_alpha = tint.a
	_check(snapshot.birth_tint.a > 0.4 and is_zero_approx(snapshot.end_tint.a) and gradient.sample(0.85).a > 0.0 and gradient.sample(0.85).a < snapshot.birth_tint.a, "不是突然消失：出生可见、中后段变淡、末尾透明：" + key)
	_check(snapshot.direction.is_equal_approx(Vector3.BACK) and material.direction.is_equal_approx(Vector3.BACK), "沿local +Z向弹后漂移：" + key)
	_check(snapshot.gravity.is_equal_approx(Vector3.ZERO), "无重力拉离弹心：" + key)
	_check(snapshot.velocity_min > 0.0 and snapshot.velocity_max >= snapshot.velocity_min and snapshot.velocity_max <= 0.42, "低速漂移形成短尾：" + key)
	_check(snapshot.spread > 0.0 and snapshot.spread <= 26.0, "短尾方向集中而非球形爆散：" + key)
	_check(is_equal_approx(snapshot.short_tail_max_distance, snapshot.velocity_max * EXPECTED_LIFETIMES[key]) and snapshot.short_tail_max_distance > 0.0 and snapshot.short_tail_max_distance <= 0.12, "寿命乘速度的短尾距离不超过0.12m：" + key)
	var bounds: AABB = snapshot.visibility_aabb
	_check(bounds.encloses(AABB(-extents, extents * 2.0 + Vector3.BACK * snapshot.short_tail_max_distance)), "可见AABB包含包裹范围及短尾：" + key)


func _expected_average(keys: Array) -> Color:
	var seen: Dictionary = {}
	var rgb := Vector3.ZERO
	for key in keys:
		if not seen.has(key) and EXPECTED_TINTS.has(key):
			seen[key] = true
			var tint: Color = EXPECTED_TINTS[key]
			rgb += Vector3(tint.r, tint.g, tint.b)
	if seen.is_empty():
		return Color.WHITE
	rgb /= float(seen.size())
	return Color(rgb.x, rgb.y, rgb.z)


func _check_body_tints_and_restore() -> void:
	for module in MODULES:
		var plain := _spawn({}, module)
		var baseline := plain.get_enchantment_snapshot()
		var body: Dictionary = baseline.body_presentation
		var host_id := plain.get_instance_id()
		var visual_id := plain._visual.get_instance_id()
		_check(body.light_visible and body.light_energy > 0.0, "八模块无附魔主体灯原始可见且有能量：" + module)
		_check_clean(plain)
		plain._retire()
		for key in EXPECTED_TINTS:
			var shot := _spawn(_render_behavior(key), module)
			var snapshot := shot.get_enchantment_snapshot()
			var presentation: Dictionary = snapshot.body_presentation
			var standard: bool = module == "standard"
			var expected: Color = EXPECTED_TINTS[key] if standard else baseline.bullet_color
			_check(shot.get_instance_id() == host_id and shot._visual.get_instance_id() == visual_id, "七色复借不换宿主或弹种Prefab：%s/%s" % [module, key])
			_check(snapshot.bullet_color.is_equal_approx(baseline.bullet_color) and shot.bullet_color.is_equal_approx(baseline.bullet_color), "染色只作用呈现，不改原bullet_color：%s/%s" % [module, key])
			_check(snapshot.body_tint.is_equal_approx(EXPECTED_TINTS[key]), "路由七种单属性各自的颜色：%s/%s" % [module, key])
			_check(snapshot.body_tint_applied == standard and snapshot.tint_core == standard and presentation.enchantment_body_tint == standard, "仅标准弹启用弹身与芯染色：%s/%s" % [module, key])
			_check(snapshot.resolved_visual_color.is_equal_approx(expected) and snapshot.shell_tint.is_equal_approx(expected) and presentation.shell_emission_tint.is_equal_approx(expected), "标准七色/特殊弹壳与自发光保色：%s/%s" % [module, key])
			var expected_core: Color = expected.lightened(0.22) if standard else body.core_tint
			_check(snapshot.core_tint.is_equal_approx(expected_core) and presentation.core_emission_tint.is_equal_approx(expected_core), "标准芯随属性变亮，特殊芯保持profile：%s/%s" % [module, key])
			_check_enchantment_light(shot, [key])
			_check(is_zero_approx(presentation.light_energy) and not presentation.light_visible, "八模块有附魔时主体灯energy=0且off：%s/%s" % [module, key])
			for candidate in shot._visual.find_children("*", "Light3D", true, false):
				var body_light := candidate as Light3D
				_check(is_zero_approx(body_light.light_energy) and not body_light.visible, "八模块真实主体灯归零且隐藏：%s/%s" % [module, key])
			if standard:
				_check(not snapshot.core_tint.is_equal_approx(Color.WHITE) and not snapshot.core_tint.is_equal_approx(body.core_tint), "标准七色弹芯不留原白芯：" + key)
				for entry in snapshot.attachments:
					var extents: Vector3 = entry.emission_box_extents
					for piece_name in ["Core", "Shell"]:
						var piece := shot._visual.get_node("BulletRoot/" + piece_name) as MeshInstance3D
						var body_bounds: AABB = piece.transform * piece.get_aabb()
						_check(AABB(-extents, extents * 2.0).grow(0.000001).encloses(body_bounds), "中心box实测覆盖原弹芯及弹壳几何：%s/%s" % [key, piece_name])
				if key == "fire":
					_check(snapshot.shell_tint.r > 0.95 and snapshot.shell_tint.g < 0.3 and snapshot.shell_tint.b < 0.1 and snapshot.core_tint.g < 0.5 and snapshot.core_tint.b < 0.4, "火焰弹身橙红且芯不是白/淡黄")
			shot._retire()
			_check_clean(shot)
			var restored := _spawn({}, module)
			var clean := restored.get_enchantment_snapshot()
			_check(restored.get_instance_id() == host_id and restored._visual.get_instance_id() == visual_id, "无附魔复借仍为同一宿主和弹身：%s/%s" % [module, key])
			_check(not clean.body_tint_applied and not clean.tint_core and clean.resolved_visual_color.is_equal_approx(baseline.bullet_color), "无附魔复借关闭染色并恢复原色：%s/%s" % [module, key])
			_check(clean.shell_tint.is_equal_approx(body.shell_tint) and clean.core_tint.is_equal_approx(body.core_tint) and clean.body_presentation.core_emission_tint.is_equal_approx(body.core_emission_tint), "无附魔复借弹壳、芯及自发光完整恢复：%s/%s" % [module, key])
			_check(clean.body_presentation.light_visible == body.light_visible and clean.body_presentation.light_tint.is_equal_approx(body.light_tint) and is_equal_approx(clean.body_presentation.light_energy, body.light_energy) and is_equal_approx(clean.body_presentation.light_range, body.light_range), "八模块无附魔复借主体灯颜色/能量/范围/开关恢复：%s/%s" % [module, key])
			for candidate in restored._visual.find_children("*", "Light3D", true, false):
				var body_light := candidate as Light3D
				_check(body_light.visible and body_light.is_visible_in_tree() and is_equal_approx(body_light.light_energy, body.light_energy) and body_light.light_color.is_equal_approx(body.light_tint), "八模块真实主体灯复借恢复投光：%s/%s" % [module, key])
			_check_clean(restored)
			restored._retire()
	var fire := _spawn(_render_behavior("fire"))
	var ice := _spawn(_render_behavior("ice"))
	for piece_name in ["Core", "Shell"]:
		var fire_piece := fire._visual.get_node("BulletRoot/" + piece_name) as MeshInstance3D
		var ice_piece := ice._visual.get_node("BulletRoot/" + piece_name) as MeshInstance3D
		_check(fire_piece.material_override.get_instance_id() != ice_piece.material_override.get_instance_id(), "同时存活火冰弹身材质独立：" + piece_name)
	_check(fire.get_enchantment_snapshot().shell_tint.is_equal_approx(EXPECTED_TINTS.fire) and ice.get_enchantment_snapshot().shell_tint.is_equal_approx(EXPECTED_TINTS.ice), "同时存活标准火冰弹不会互相串色")
	_check_enchantment_light(fire, ["fire"])
	_check_enchantment_light(ice, ["ice"])
	_check(fire.get_enchantment_snapshot().enchantment_light.instance_id != ice.get_enchantment_snapshot().enchantment_light.instance_id, "同时存活火冰独立灯不共享对象")
	ice._retire()
	_check_enchantment_light(fire, ["fire"])
	_check(fire.get_enchantment_snapshot().core_tint.is_equal_approx(EXPECTED_TINTS.fire.lightened(0.22)), "回收另一发不改变存活火弹芯色")
	fire._retire()
	var all_behavior := {"fate_elements": {"fire": {}, "ice": {}, "poison": {}, "lightning": {}}, "chain_lightning": true, "chain_count": 3, "bounce_count": 2, "homing": true, "return_on_hit": true, "return_to_player": true, "home_on_land": true}
	for count in range(2, 8):
		var behavior: Dictionary = {}
		var keys: Array = EXPECTED_TINTS.keys().slice(0, count)
		for key in keys:
			if not ELEMENTS.has(key):
				behavior.merge(_render_behavior(key), true)
		var elements: Dictionary = {}
		for key in keys:
			if ELEMENTS.has(key):
				elements[key] = {}
		behavior["fate_elements"] = elements
		if count >= 4:
			behavior["chain_lightning"] = true
			behavior["chain_count"] = 3
		if count == 7:
			behavior = all_behavior.duplicate(true)
		var mixed := _spawn(behavior)
		var snapshot := mixed.get_enchantment_snapshot()
		var expected := _expected_average(keys)
		_check_enchantment_light(mixed, keys)
		_check(is_zero_approx(snapshot.body_presentation.light_energy) and not snapshot.body_presentation.light_visible, "混合N=2至7主体灯仍关闭：N=%d" % count)
		_check(snapshot.attribute_count == count and snapshot.total_amount == count * floori(24.0 / count), "混合N=2至7仍按floor(24/N)共享预算：%d" % count)
		_check(snapshot.body_tint.is_equal_approx(expected) and snapshot.shell_tint.is_equal_approx(expected) and snapshot.core_tint.is_equal_approx(expected.lightened(0.22)), "混合色按去重RGB算术平均、芯同步：N=%d" % count)
		for entry in snapshot.attachments:
			_check(entry.amount == floori(24.0 / count), "混合每种数量不扩预算：N=%d/%s" % [count, entry.attribute])
		mixed._retire()
	var duplicated: Array[String] = ["fire", "fire", "lightning", "lightning", "return", "return", "unknown"]
	_check(ENCHANT_VISUALS.body_tint(duplicated).is_equal_approx(_expected_average(["fire", "lightning", "return"])), "body_tint输入去重且忽略未知键，不做加权或线性空间混色")
	var rock := _spawn({"rock_projectile": true})
	var rock_visual_id := rock._visual.get_instance_id()
	var rock_mesh := rock._visual.get_node("Rock") as MeshInstance3D
	var rock_material := rock_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var rock_color := rock_material.albedo_color
	rock._retire()
	var enchanted_rock := _spawn({"rock_projectile": true, "fate_elements": {"fire": {}}})
	var rock_snapshot := enchanted_rock.get_enchantment_snapshot()
	_check(rock_snapshot.visual_id == "fate_rock" and enchanted_rock._visual.get_meta("asset_id") == "VFX-FATE-ROCK-3D" and enchanted_rock._visual.get_instance_id() == rock_visual_id, "力量滚石优先路由，不替换成染色标准弹")
	_check(not rock_snapshot.body_tint_applied and not rock_snapshot.tint_core and rock_snapshot.resolved_visual_color.is_equal_approx(enchanted_rock.bullet_color), "力量滚石不启用标准弹染色")
	var enchanted_mesh := enchanted_rock._visual.get_node("Rock") as MeshInstance3D
	var enchanted_material := enchanted_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	_check(enchanted_material.albedo_color.is_equal_approx(rock_color) and rock_color.is_equal_approx(Color(0.42, 0.35, 0.27)), "力量滚石真实石材保持原棕色")
	_check(rock_snapshot.attributes == ["fire"] and rock_snapshot.total_amount == 24, "力量滚石保色但仍携带正确独立附魔附件")
	_check_enchantment_light(enchanted_rock, ["fire"])
	enchanted_rock._retire()
	_check_clean(enchanted_rock)


func _check_axial_material_isolation() -> void:
	var behavior := {"fate_elements": {"fire": {}, "ice": {}, "poison": {}, "lightning": {}}, "bounce_count": 2, "homing": true, "return_on_hit": true}
	var config := _config(behavior)
	config["gun_bullet_geometry"] = {"axial": 3.0}
	var stretched := _pool.acquire(config, ORIGIN)
	stretched.set_physics_process(false)
	var neutral := _spawn(behavior)
	var first := stretched.get_enchantment_snapshot()
	var other := neutral.get_enchantment_snapshot()
	var materials: Dictionary = {}
	var cached_ids: Dictionary = {}
	for snapshot in [first, other]:
		for entry in snapshot.attachments:
			_check(not materials.has(entry.process_material_instance_id), "同时存活两发的七类process材质全部实例独立：" + entry.attribute)
			materials[entry.process_material_instance_id] = true
			var base: Vector3 = entry.base_emission_box_extents
			var factor := 3.0 if snapshot == first else 1.0
			_check(is_equal_approx(entry.axial_scale, factor) and entry.emission_box_extents.is_equal_approx(Vector3(base.x, base.y, base.z * factor)), "轴向仅伸缩box的Z半长，不串改另一发：" + entry.attribute)
			_check(entry.visual_scale.is_equal_approx(Vector3.ONE) and entry.emitter_position.is_equal_approx(Vector3.ZERO), "轴向包裹不整体非均匀拉伸或偏离弹心：" + entry.attribute)
			if factor == 3.0:
				cached_ids[entry.attribute] = {"instance": entry.instance_id, "material": entry.process_material_instance_id}
	_check(first.body_presentation.axial_scale == 3.0 and first.body_presentation.core_axis_scale == 3.0 and other.body_presentation.core_axis_scale == 1.0, "主体轴向同源且另一发仍中性")
	var id := stretched.get_instance_id()
	neutral._retire()
	stretched._retire()
	_check_clean(stretched)
	var reused := _spawn(behavior)
	_check(reused.get_instance_id() == id, "轴向用真实池复借同一实例")
	for entry in reused.get_enchantment_snapshot().attachments:
		_check(entry.instance_id == cached_ids[entry.attribute].instance and entry.process_material_instance_id == cached_ids[entry.attribute].material, "轴向复借保留附件与私有材质缓存：" + entry.attribute)
		_check(entry.axial_scale == 1.0 and entry.emission_box_extents.is_equal_approx(entry.base_emission_box_extents), "轴向复借恢复原box范围：" + entry.attribute)
	_check(reused.get_enchantment_snapshot().body_presentation.core_axis_scale == 1.0, "弹芯轴向复借一并复位")
	reused._retire()
	_check(_pool.get_snapshot().active == 0, "新增染色与轴向检查不泄漏活跃池对象")


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
	_check(snapshot.active_light_count == 0 and snapshot.enchantment_light.is_empty(), "空属性或回收无活跃附魔灯")
	for entry in snapshot.cached_lights:
		_check(not entry.active and not entry.visible and not entry.visible_in_tree and is_zero_approx(entry.energy), "缓存灯全部energy=0且off：" + entry.preset_key)
		_check(entry.color.is_equal_approx(EXPECTED_TINTS[entry.preset_key]) and entry.local_transform.is_equal_approx(Transform3D.IDENTITY), "缓存灯颜色与局部变换回到对应预设：" + entry.preset_key)
		var object := projectile.get_node("ProjectileEnchantments/" + entry.parent_attachment + "/EnchantLight_" + entry.preset_key) as Node3D
		var light := object.get_node("EnchantmentLight") as OmniLight3D
		_check(object.get_instance_id() == entry.instance_id and not object.visible and not light.visible and not light.is_visible_in_tree() and is_zero_approx(light.light_energy), "真实缓存灯对象仍持有但归零隐藏：" + entry.preset_key)
	for entry in snapshot.cached_attachments:
		_check(not entry.emitting and not entry.visible and not entry.configured and entry.amount == 0 and entry.flight_time == 0.0, "缓存粒子及属性时钟全清")
		_check(entry.axial_scale == 1.0 and entry.emission_box_extents.is_equal_approx(entry.base_emission_box_extents) and entry.emitter_position.is_equal_approx(Vector3.ZERO), "回收/无附魔缓存轴向box和中心偏移复位")
		_check(entry.visual_scale.is_equal_approx(Vector3.ONE) and entry.grow_from == 1.0 and entry.grow_duration == 0.0, "回收/无附魔尺寸及生长包络复位")
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
	_check_enchantment_light(projectile, ["fire"])
	_check(is_zero_approx(projectile.get_enchantment_snapshot().body_presentation.light_energy) and not projectile.get_enchantment_snapshot().body_presentation.light_visible, "旧configure→入树路径主体灯也关闭")
	projectile.free()
	for module in MODULES:
		for key in EXPECTED_TINTS:
			var pending := Projectile3D.new()
			pending.configure(_config(_render_behavior(key), module))
			var before := pending.get_enchantment_snapshot()
			_check(not pending.is_inside_tree() and not before.enchantment_light.is_empty(), "八模块七属性入树前configure已持有独立灯：%s/%s" % [module, key])
			if not before.enchantment_light.is_empty():
				_check(before.active_light_count == 0 and not before.enchantment_light.active and not before.enchantment_light.visible and is_zero_approx(before.enchantment_light.energy), "入树前灯不提前投光：%s/%s" % [module, key])
			add_child(pending)
			pending.set_physics_process(false)
			pending.global_position = ORIGIN
			_check_enchantment_light(pending, [key])
			var after := pending.get_enchantment_snapshot()
			_check(after.enchantment_light.instance_id == before.enchantment_light.instance_id and after.cached_lights.size() == 1, "入树沿用configure阶段独立灯，不重复创建：%s/%s" % [module, key])
			_check(is_zero_approx(after.body_presentation.light_energy) and not after.body_presentation.light_visible, "入树后八模块主体灯保持关闭：%s/%s" % [module, key])
			pending.free()


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
	_check_enchantment_light(reused, ["ice"])
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
	heading.size.x = get_viewport().get_visible_rect().size.x - 48.0
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 24)
	overlay.add_child(heading)
	heading.text = "七种单附魔 + 四元素混合 / 八模块原形对照\n左：无附魔　右：真实GPU附件　|　配置倍率×2，主体保留原生脉动　|　楼层 y=%.2f" % ORIGIN.y
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
	heading.text = "单 / 双 / 三 / 四元素真实GPU发射对照\n每种 amount=24 / 12 / 8 / 6　|　总预算24　|　主体与附件配置倍率×2，保留原生脉动；标准弹去重RGB平均/穿透弹保色"
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
	shots.clear()
	samples.free()

	samples = Node3D.new()
	add_child(samples)
	camera.size = 7.4
	heading.text = "标准弹：原色 + 七种单附魔（不是八模块各配一种）\n真实GPU中心包裹/短尾　|　主体和附件配置倍率×2，主体保留原生±4%脉动　|　amount=24"
	var standard_keys: Array = ["plain"]
	standard_keys.append_array(EXPECTED_LIFETIMES.keys())
	for index in standard_keys.size():
		var center := ORIGIN + Vector3((index % 4 - 1.5) * 3.15, 0, (floori(index / 4.0) - 0.5) * 3.2)
		var key: String = standard_keys[index]
		shots.append(_render_shot({} if key == "plain" else _render_behavior(key), "standard", center))
		_render_label(samples, center + Vector3(0, 0, 0.85), "standard / %s\n原色" % key if key == "plain" else "standard / %s\namount=24 / N=1" % key)
	await get_tree().create_timer(0.6).timeout
	await _capture_render(output, "projectile_enchant_standard_seven", shots)
	for shot in shots:
		shot._retire()
	shots.clear()
	samples.free()

	samples = Node3D.new()
	add_child(samples)
	heading.text = "特殊弹七模块 + 力量滚石保色：左原色 / 右火焰附魔\n真实原Prefab和材质　|　配置倍率×2，主体保留原生脉动　|　右侧amount=24，滚石保留棕色"
	for index in 8:
		var center := ORIGIN + Vector3((index % 4 - 1.5) * 3.15, 0, (floori(index / 4.0) - 0.5) * 3.2)
		var module: String = MODULES[index + 1] if index < 7 else "standard"
		var plain_behavior: Dictionary = {} if index < 7 else {"rock_projectile": true}
		var fire_behavior := plain_behavior.duplicate(true)
		fire_behavior["fate_elements"] = {"fire": {}}
		shots.append(_render_shot(plain_behavior, module, center + Vector3(-0.65, 0, 0)))
		shots.append(_render_shot(fire_behavior, module, center + Vector3(0.65, 0, 0)))
		_render_label(samples, center + Vector3(0, 0, 0.85), "%s\n原色 / +fire（保色）" % (module if index < 7 else "fate_rock"))
	await get_tree().create_timer(0.6).timeout
	await _capture_render(output, "projectile_enchant_special_preserve", shots)
	for shot in shots:
		shot._retire()
	shots.clear()
	samples.free()

	samples = Node3D.new()
	add_child(samples)
	for index in 8:
		var center := ORIGIN + Vector3((index % 4 - 1.5) * 3.15 - 0.5, 0, (floori(index / 4.0) - 0.5) * 3.2)
		var key: String = EXPECTED_LIFETIMES.keys()[index] if index < 7 else "multi7"
		var behavior := _render_behavior(key) if index < 7 else {"fate_elements": {"fire": {}, "ice": {}, "poison": {}, "lightning": {}}, "bounce_count": 2, "homing": true, "return_on_hit": true}
		var shot := _render_shot(behavior, "standard", center)
		shot.direction = Vector3.RIGHT
		shot._sync_visual_orientation()
		shots.append(shot)
		_render_label(samples, center + Vector3(0, 0, 0.85), "%s / amount=%d\n出生X=%.2f，向右移动→" % [key, 24 if index < 7 else 3, center.x])
	# 先让真实GPU建立稳定包裹，再连续移动同一批样品，绝不重启发射器伪造时间帧。
	await get_tree().create_timer(0.6).timeout
	_motion_elapsed = 0.0
	_motion_distance = 0.0
	_moving_shots.assign(shots)
	var previous_time := -1.0
	var previous_distance := -1.0
	for frame in 3:
		if frame > 0:
			await get_tree().create_timer(0.12).timeout
		await motion_stepped
		heading.text = "移动包裹/短尾，同一批标准弹连续三帧：%d/3\n真实GPU delta，宿主向右2m/s；t=%.3fs，位移=%.3fm　|　配置倍率×2，原生脉动保留\n固定相机/网格/出生标签；local +Z在右行弹身后（左侧）；非持久世界空间拖尾" % [frame + 1, _motion_elapsed, _motion_distance]
		_check(_motion_elapsed > previous_time and _motion_distance > previous_distance, "移动证据时间和位移逐帧推进：%d" % frame)
		_check(is_equal_approx(_motion_distance, _motion_elapsed * 2.0), "移动证据按真实delta积分而非伪造固定GPU步长")
		for shot in shots:
			var snapshot := shot.get_enchantment_snapshot()
			_check(shot.get_orientation_snapshot().alignment > 0.999, "移动截图主体前向与实际平移方向一致")
			for entry in snapshot.attachments:
				_check(entry.world_position.distance_to(shot.global_position) < 0.001 and entry.emitter_position.is_equal_approx(Vector3.ZERO), "移动截图中心持续包裹且没有钉在出生点：" + entry.attribute)
			print("MOVING_WRAP_FRAME ", JSON.stringify({"frame": frame, "elapsed": _motion_elapsed, "distance": _motion_distance, "world_position": shot.global_position, "attributes": snapshot.attributes, "total_amount": snapshot.total_amount, "configured_scale": RENDER_SCALE}))
		await _capture_render(output, "projectile_enchant_moving_wrap_trail_%02d" % frame, shots)
		previous_time = _motion_elapsed
		previous_distance = _motion_distance
	_moving_shots.clear()
	for shot in shots:
		shot._retire()
	shots.clear()
	samples.free()

	# 真实受光表面专场：禁用原方向光/网格，不能用弹身emission冒充地面和墙面投光。
	light.light_energy = 0.0
	light.visible = false
	floor_mesh.visible = false
	grid_mesh.visible = false
	environment.environment.background_color = Color(0.006, 0.006, 0.008)
	environment.environment.ambient_light_color = Color(0.2, 0.2, 0.2)
	environment.environment.ambient_light_energy = 0.02
	environment.environment.glow_enabled = false
	environment.environment.sdfgi_enabled = false
	environment.environment.ssil_enabled = false
	environment.environment.fog_enabled = false
	environment.environment.volumetric_fog_enabled = false
	camera.position = ORIGIN + Vector3(0, 12, 14)
	camera.look_at(ORIGIN)
	camera.size = 9.0
	heading.text = "附魔灯真实投光：七单属性 + 七属性RGB平均色 / 全部标准弹\n暗色受光地板(mask1) / 背板(mask2)；ambient=0.02、方向光关闭、无GI/辉光\n仅独立附魔灯energy=1.15 / range=1.75 / mask3照亮表面，不以弹身emission代替"
	samples = Node3D.new()
	add_child(samples)
	var receiver_material := StandardMaterial3D.new()
	receiver_material.albedo_color = Color(0.18, 0.18, 0.18)
	receiver_material.roughness = 1.0
	receiver_material.metallic = 0.0
	receiver_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	receiver_material.emission_enabled = false
	for index in 8:
		var center := ORIGIN + Vector3((index % 4 - 1.5) * 3.8, 0, (floori(index / 4.0) - 0.5) * 4.2)
		var key: String = EXPECTED_TINTS.keys()[index] if index < 7 else "multi7"
		var behavior := _render_behavior(key) if index < 7 else {"fate_elements": {"fire": {}, "ice": {}, "poison": {}, "lightning": {}}, "bounce_count": 2, "homing": true, "return_on_hit": true}
		var receiver_floor := MeshInstance3D.new()
		var receiver_plane := PlaneMesh.new()
		receiver_plane.size = Vector2(3.3, 3.0)
		receiver_floor.mesh = receiver_plane
		receiver_floor.material_override = receiver_material
		receiver_floor.layers = 1
		samples.add_child(receiver_floor)
		receiver_floor.global_position = center + Vector3(0, -0.55, 0.15)
		var receiver_back := MeshInstance3D.new()
		var receiver_box := BoxMesh.new()
		receiver_box.size = Vector3(3.3, 1.6, 0.1)
		receiver_back.mesh = receiver_box
		receiver_back.material_override = receiver_material
		receiver_back.layers = 2
		samples.add_child(receiver_back)
		receiver_back.global_position = center + Vector3(0, 0.2, -0.85)
		var shot := _render_shot(behavior, "standard", center)
		shots.append(shot)
		var attributes: Array = [key] if index < 7 else EXPECTED_TINTS.keys()
		_check_enchantment_light(shot, attributes)
		_check(receiver_floor.layers == 1 and receiver_back.layers == 2 and receiver_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not receiver_material.emission_enabled, "投光截图使用真实受光非自发光地板/背板：" + key)
		_check(shot.global_position.distance_to(receiver_floor.global_position) < 1.75 and shot.global_position.distance_to(receiver_back.global_position) < 1.75 and camera.global_position.distance_to(shot.global_position) < 55.0, "投光截图接收面在灯范围内且未触发距离渐隐：" + key)
		_render_label(samples, center + Vector3(0, -0.45, 1.3), "standard / %s\n%s" % [key, "七属性平均 / 仅一灯" if index == 7 else "单属性 / 仅一灯"])
	_check(not light.visible and is_zero_approx(light.light_energy) and is_equal_approx(environment.environment.ambient_light_energy, 0.02) and not grid_mesh.visible, "投光专场关闭方向光及发光网格，仅低ambient")
	await get_tree().create_timer(0.6).timeout
	await _capture_render(output, "projectile_enchant_light_cast", shots)
	for shot in shots:
		shot._retire()
		_check_clean(shot)
	samples.free()
	_check(_pool.get_snapshot().active == 0, "全部截图结束归还真实池样品")


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
	config["visual_scale"] = RENDER_SCALE
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
		if not snapshot.attributes.is_empty():
			_check_enchantment_light(shot, snapshot.attributes)
		else:
			_check_clean(shot)
		for entry in snapshot.attachments:
			var particles := shot.get_node("ProjectileEnchantments/Enchant_" + entry.attribute + "/Particles") as GPUParticles3D
			_check(particles.emitting and particles.visible and particles.speed_scale == 1.0 and particles.amount == floori(24.0 / snapshot.attribute_count), "截图时真实发射器持续运行：" + label + "/" + entry.attribute)
			_check(entry.asset_version == "v002" and entry.prefab_path == "res://assets/art/vfx/combat_3d/vfx_projectile_enchant_%s_root_top3d.tscn" % entry.attribute, "截图不替换原v002附件Prefab：" + label + "/" + entry.attribute)
			_check(is_equal_approx(entry.visual_size, RENDER_SCALE) and entry.visual_scale.is_equal_approx(Vector3.ONE * RENDER_SCALE) and is_equal_approx(shot.visual_scale, RENDER_SCALE), "截图主体与附件配置倍率如实为×2：" + label + "/" + entry.attribute)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "真实viewport截图非空：" + label)
	if image != null and not image.is_empty():
		var path := output.path_join(label + ".png")
		_check(image.save_png(path) == OK, "截图保存：" + label)
		print("CAPTURE ", path)
