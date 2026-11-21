extends Node3D
## Optional render evidence for verify_hit_routing_vfx -- --enchant-reel (run with --fixed-fps 60).

const KEYS := ["fire", "ice", "poison", "lightning", "bounce", "homing", "return"]
const LABELS := ["火焰", "寒冰", "毒雾", "雷电", "弹跳", "追踪", "返航"]
const MODULES := ["sticky", "bounce", "piercing", "explosive", "homing", "blackhole", "balloon"]
const MODULE_LABELS := ["黏黏弹", "回旋镖弹", "穿透弹", "爆炸弹", "蜂卵弹", "黑洞弹", "气球弹"]
const BEHAVIORS := [{"fate_elements":{"fire":{}}}, {"fate_elements":{"ice":{}}},
	{"fate_elements":{"poison":{}}}, {"chain_lightning":true}, {"bounce_count":1},
	{"homing":true}, {"return_on_hit":true}]

class Target extends StaticBody3D:
	var hits := 0
	func take_damage(_amount: int, _critical: bool, _direction: Vector3, _knockback: float = 0.0) -> void:
		hits += 1


func _ready() -> void:
	var output := OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	if output.is_empty() or OS.get_environment("PROJECTILE_ENCHANT_VERIFY_ISOLATED") != "1":
		get_tree().quit(2)
		return
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.6
	add_child(camera)
	camera.position = Vector3(0,14,4)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#101823")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	camera.environment = environment
	var rounds := ProjectilePool3D.new()
	add_child(rounds)
	var targets: Array[Target] = []
	var groups: Array[Array] = []
	var pairs := "--pairs" in OS.get_cmdline_user_args()
	var modules := "--modules" in OS.get_cmdline_user_args()
	for i in KEYS.size():
		if pairs:
			for j in range(i + 1, KEYS.size()):
				groups.append([i, j])
		else:
			groups.append([] if modules else [i])
	for i in groups.size():
		var x := (i % 7 - 3) * 2.25
		var target := Target.new()
		add_child(target)
		target.position = Vector3(x, 0, -2.9 + floori(i / 7.0) * 3.15 if pairs else -2.5)
		target.collision_layer = 1 << (i + 2)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.35, 0.48, 0.48)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		target.add_child(collision)
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#354354")
		box.material = mat
		marker.mesh = box
		target.add_child(marker)
		targets.append(target)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.006
		var names := PackedStringArray()
		for index in groups[i]:
			names.append(LABELS[index])
		label.text = " · ".join(names)
		if modules:
			label.text = MODULE_LABELS[i % 7] + ("\n" + label.text if pairs else "")
		add_child(label)
		label.position = target.position + Vector3(0, 0.15, -0.85)
	for warmup in 5:
		await get_tree().physics_frame
	for i in groups.size():
		var behavior: Dictionary = {}
		var elements := {}
		for index in groups[i]:
			behavior.merge(BEHAVIORS[index])
			elements.merge(BEHAVIORS[index].get("fate_elements", {}))
		behavior["fate_elements"] = elements
		var id := "mod_bullet_" + (String(MODULES[i % 7]) if modules else "standard")
		var shot := rounds.acquire({"behavior":behavior, "direction":Vector3.FORWARD, "speed":23.0,
			"damage":10, "visual_id":id, "color": WeaponModel3D.BULLET_COLORS[id],
			"tags":ItemRegistry.get_instance().get_item(id).get("tags", []), "range":15.0, "projectile_collision_mask":targets[i].collision_layer,
			"gun_bullet_geometry":{"scale":1.8}}, targets[i].position + Vector3(0, 0.15, 1.8 if pairs else 5.7))
		var state := shot.get_enchantment_snapshot()
		var expected: Array[String] = []
		for index in groups[i]:
			expected.append(KEYS[index])
		if state.attributes != expected or state.active_light_count != int(not expected.is_empty()) or state.total_amount > 10:
			push_error("飞行属性或预算错误 %s" % str(expected))
			get_tree().quit(1)
			return
		for attachment in state.attachments:
			if not attachment.emitting or not attachment.visible or attachment.amount < 1:
				push_error("飞行时缺少粒子 %s" % attachment.attribute)
				get_tree().quit(1)
				return
	var seen_rows := {}
	var vfx := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	for frame in 54:
		await RenderingServer.frame_post_draw
		for hit in vfx._active[VfxPool3D.FX01_METAL_SPARK_HIT]:
			var sprite := hit.get_node("EnchantImpact") as Sprite3D
			var second := hit.get_node("SecondEnchantImpact") as Sprite3D
			var base := hit.get_node("ModuleImpact") as Sprite3D
			if modules and not base.is_visible_in_tree():
				continue
			if modules and not pairs:
				seen_rows[base.frame_coords.y] = true
			if sprite.is_visible_in_tree():
				if not pairs or second.is_visible_in_tree() and sprite.frame_coords.y != second.frame_coords.y:
					seen_rows[Vector2i(sprite.frame_coords.y, second.frame_coords.y if pairs else -1)] = true
		if frame % 2 == 0:
			var error := get_viewport().get_texture().get_image().save_png(output.path_join("shot_%02d.png" % frame))
			if error != OK:
				get_tree().quit(2)
				return
	for target in targets:
		if target.hits != 1:
			push_error("失去实际投射物命中记录")
			get_tree().quit(1)
			return
	print("ENCHANT_IMPACT_REEL combinations=", seen_rows.size(), " hits=", targets.size())
	await _measure_impacts(vfx, modules)
	get_tree().quit(0 if seen_rows.size() == groups.size() else 1)


func _measure_impacts(vfx: VfxPool3D, modules: bool) -> void:
	# Same camera, positions, scale and normalized age in both samples.
	for attributes_per_hit in 3:
		var samples: Array[VfxEffectBase3D] = []
		for i in 56:
			var context := {"normal":Vector3.UP}
			if modules:
				context["bullet_visual_id"] = "mod_bullet_" + String(MODULES[i % 7])
			var attributes: Array = []
			for j in attributes_per_hit:
				attributes.append(KEYS[(i + j) % KEYS.size()])
			context["impact_attributes"] = attributes
			var location := Vector3((i % 8 - 3.5) * 1.7, 0.6, (floori(i / 8.0) - 3) * 1.0)
			var effect := vfx.acquire(VfxPool3D.FX01_METAL_SPARK_HIT, location, Color.WHITE, 0.55, context)
			effect.set_process(false)
			effect._on_tick(0.4 * effect.lifetime, effect.lifetime)
			samples.append(effect)
		for settle in 4:
			await RenderingServer.frame_post_draw
		print("ENCHANT_IMPACT_BUDGET attributes=", attributes_per_hit, " count=56 viewport_draws=",
			get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" viewport_primitives=", get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		for effect in samples:
			effect.set_process(true)
			effect._retire()
