extends Node3D
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const ASSET_PATH := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask"
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _ready() -> void:
	var service := CharacterExpressionSystem.new()
	service.random_seed = 123
	add_child(service)
	service.set_process(false)
	check(service.current_expression == "neutral", "standalone service must start neutral")
	check(CharacterExpressionCatalog.get_ids().size() == 8, "exactly eight expressions required")
	var seen: Dictionary = {}
	for index in range(300):
		var previous := service.current_expression
		check(service.request_random(0), "random selection rejected")
		check(service.current_expression != previous, "random repeated current expression")
		seen[service.current_expression] = true
	check(seen.size() == 8, "random cannot reach all eight expressions")
	var before := service.get_snapshot()
	check(not service.request_expression("unknown"), "unknown expression accepted")
	check(not service.request_expression("angry", -1), "negative hold accepted")
	check(not service.request_expression("angry", INF), "infinite hold accepted")
	check(not service.request_random(NAN), "nonfinite random hold accepted")
	check(service.get_snapshot() == before, "invalid commands changed expression state")
	service.request_expression("angry", 5)
	service.advance(4)
	check(service.current_expression == "angry", "random interrupted requested hold")
	service.advance(1)
	check(service.current_expression == "angry", "random fired immediately at hold boundary")
	service.advance(7)
	check(service.current_expression != "angry", "background random failed to resume")
	service.set_random_enabled(false)
	before = service.get_snapshot()
	service.advance(100)
	check(service.current_expression == before.expression_id, "disabled background random changed expression")
	var second := CharacterExpressionSystem.new()
	add_child(second)
	second.set_process(false)
	second.set_random_enabled(false)
	before = service.get_snapshot()
	second.request_expression("love", 0)
	check(service.get_snapshot() == before, "independent instances share selection state")
	for id in CharacterExpressionCatalog.get_ids():
		var definition := CharacterExpressionCatalog.get_definition(id)
		var visual := (definition.scene as PackedScene).instantiate() as Node3D
		check(visual.scale == Vector3.ONE, "expression root scale invalid: " + id)
		check(visual.get_meta("expression_id") == id, "expression metadata differs from catalog: " + id)
		check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "expression contains gameplay collision")
		var meshes := visual.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() == 1, "expression must use one real cell mesh: " + id)
		var mesh := meshes[0] as MeshInstance3D
		check(mesh.mesh.get_blend_shape_count() == 1, "expression blink morph missing: " + id)
		if definition.kind == "emotion":
			var mouth_free := true
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				if absf(vertex.x) < .03:
					mouth_free = false
			check(mouth_free, "emotion contains central mouth geometry: " + id)
		if id == "angry":
			var mat := mesh.get_active_material(0) as StandardMaterial3D
			check(mat.emission.r > .9 and mat.emission.r > mat.emission.g * 4, "angry mesh is not red")
		if id in ["question", "alert"]:
			check(not definition.blink_enabled and definition.kind == "symbol", "symbols must stay readable during blinks")
		visual.free()
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.expression_random_enabled = false
	player.expression_random_seed = 321
	add_child(player)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.expression_system.set_process(false)
	player.camera.current = false
	await get_tree().process_frame
	var display := player.avatar.head.get_node("FaceAccessorySocket/ElectronicMask") as Node3D
	var animation := display.get_node("ExpressionPlayer") as AnimationPlayer
	animation.stop()
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var collision_before := (player.virtual_collision_capsule.shape as CapsuleShape3D).height
	var weapon_before := player.avatar.weapon_socket.transform
	var hp_before := player.current_hp
	var fsm := player.get("_state_machine") as StateMachine
	var selection_before := player.expression_system.current_expression
	fsm.transition_to("moving", true)
	check(player.expression_system.current_expression != selection_before, "real player state transition did not call expression service")
	check(display.current_expression == player.expression_system.current_expression, "event did not update face renderer")
	var count_before: int = player.expression_system.get_snapshot().change_count
	player.call("_set_presentation_state", "moving", {"progress": .5})
	check(player.expression_system.get_snapshot().change_count == count_before, "repeated state progress randomized again")
	for id in CharacterExpressionCatalog.get_ids():
		check(player.expression_system.request_expression(id, 2), "explicit expression request rejected: " + id)
		check(display.current_expression == id, "renderer did not follow explicit command: " + id)
		check(player.get_state_machine_state() == "moving" and player.current_hp == hp_before, "expression altered gameplay")
	check(is_equal_approx((player.virtual_collision_capsule.shape as CapsuleShape3D).height, collision_before), "expression changed collision")
	check(player.avatar.weapon_socket.transform == weapon_before, "expression changed weapon socket")
	var pixels := display.get_node("Visual/ExpressionPixels") as MeshInstance3D
	var mesh_before := pixels.mesh
	check(not display.apply_expression("bad"), "renderer accepted invalid expression")
	check(pixels.mesh == mesh_before, "failed render command replaced valid mesh")
	player.expression_system.request_expression("question", 0)
	display.blink_amount = 1.0
	check(pixels.get_blend_shape_value(0) == 0, "question symbol collapsed during blink")
	display.blink_amount = 0.0
	player.set_avatar_customization("glasses", "none")
	player.expression_system.request_expression("angry", 0)
	check(not display.visible, "expression command equipped an unequipped mask")
	player.set_avatar_customization("glasses", "electronic_mask")
	check(display.visible and display.current_expression == "angry", "latest expression not restored with mask")
	if DisplayServer.get_name() != "headless":
		await render_expressions(player, display)
	service.queue_free()
	second.queue_free()
	player.queue_free()
	if failures.is_empty():
		print("CHARACTER_EXPRESSION_FLOW_OK checks=", checks)
		get_tree().quit(0)
	else:
		for message in failures:
			push_error(message)
		get_tree().quit(1)

func render_expressions(player: Player3D, display: Node3D) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.055, .065, .09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.6, .7, .9)
	env.ambient_light_energy = .55
	env.glow_enabled = true
	env.glow_intensity = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	for position in [Vector3(-1.1, 2, -1.8), Vector3(1, 1.5, -1.2)]:
		var light := OmniLight3D.new()
		light.position = position
		light.light_energy = 2
		light.omni_range = 5
		light.light_cull_mask = 2
		add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .78
	camera.cull_mask = 2
	camera.current = true
	var target := player.avatar.head.global_position + Vector3(0, .22, 0)
	camera.position = target + Vector3(.12, .10, -3)
	camera.look_at(target)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var label := Label.new()
	label.position = Vector2(25, 25)
	label.add_theme_font_size_override("font_size", 36)
	canvas.add_child(label)
	var atlas := Image.create(1280, 782, false, Image.FORMAT_RGBA8)
	var hashes: Dictionary = {}
	var index := 0
	for id in CharacterExpressionCatalog.get_ids():
		player.expression_system.request_expression(id, 0)
		label.text = CharacterExpressionCatalog.get_definition(id).name + " / " + id
		for frame in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame_image := get_viewport().get_texture().get_image()
		var directory: String = ASSET_PATH + "/expressions/chr_bunny01_expression_" + id + "/previews"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		frame_image.save_png(directory + "/expression_front.png")
		var luminous := 0
		var red := 0
		for y in range(300, frame_image.get_height() - 100):
			for x in range(100, frame_image.get_width() - 100):
				var color := frame_image.get_pixel(x, y)
				var brightest := maxf(color.r, maxf(color.g, color.b))
				var darkest := minf(color.r, minf(color.g, color.b))
				if brightest > .9 and brightest - darkest > .1:
					luminous += 1
				if color.r > .9 and color.r > color.g * 3 and color.r > color.b * 3:
					red += 1
		check(luminous > 150, "rendered expression is missing: " + id)
		if id == "angry":
			check(red > 100, "actual angry expression is not red")
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		# Hash the face region, excluding the changing caption.
		hasher.update(frame_image.get_region(Rect2i(100, 300, 700, 600)).get_data())
		hashes[hasher.finish().hex_encode()] = true
		frame_image.resize(320, 391, Image.INTERPOLATE_LANCZOS)
		frame_image.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(frame_image, Rect2i(0, 0, 320, 391), Vector2i((index % 4) * 320, (index / 4) * 391))
		index += 1
	check(hashes.size() == 8, "expression renders are not distinct")
	atlas.save_png(ASSET_PATH + "/previews/expressions_overview.png")
	print("CHARACTER_EXPRESSION_RENDER_OK distinct=", hashes.size())
