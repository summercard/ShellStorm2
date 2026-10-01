extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const MASK_SCENE: PackedScene = preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/runtime/chr_bunny01_electronic_mask_root.tscn")
const SAVE_PATH := "user://electronic_mask_probe.json"
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _ready() -> void:
	var independent := MASK_SCENE.instantiate() as Node3D
	check(independent.scale.is_equal_approx(Vector3.ONE), "mask wrapper must have unit scale")
	check(independent.find_children("*", "CollisionObject3D", true, false).is_empty(), "mask contains gameplay collision")
	check(independent.find_children("*", "Skeleton3D", true, false).is_empty(), "static accessory contains a duplicate skeleton")
	check(independent.find_children("*", "MeshInstance3D", true, false).size() == 2, "mask must contain only shell and pixels")
	independent.free()
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.expression_random_enabled = false
	add_child(player)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.get_node("Camera3D").current = false
	await get_tree().process_frame
	var avatar := player.avatar
	var socket := avatar.head.get_node("FaceAccessorySocket") as Marker3D
	var mask := socket.get_node("ElectronicMask") as Node3D
	var expression := mask.get_node("ExpressionPlayer") as AnimationPlayer
	check(expression.is_playing() and expression.current_animation == "mask_idle", "equipped mask did not automatically start its ambient animation")
	expression.stop()
	expression.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check(mask.get_meta("asset_version") == "v005", "mask version differs from authored masters")
	var capsule := player.virtual_collision_capsule.shape as CapsuleShape3D
	var collision_before := Vector2(capsule.radius, capsule.height)
	var original_head := avatar.bunny_head_model
	var weapon_before := avatar.weapon_socket.transform
	check(player.get_avatar_customization()["glasses"] == "electronic_mask", "fresh avatar does not equip default mask")
	check(mask.is_visible_in_tree(), "default mask is hidden")
	check(mask.transform.is_equal_approx(Transform3D.IDENTITY), "mask uses a per-item compensation transform")
	check(socket.transform.is_equal_approx(Transform3D.IDENTITY), "face socket does not use the original HeadJoint rest origin")
	check(original_head.is_visible_in_tree(), "mask replaced or hid the original head")
	check(avatar.bunny_ears.is_visible_in_tree(), "default mask hid bunny ears")
	var meshes := mask.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		var mesh := node as MeshInstance3D
		check(mesh.layers == 2, "mask render layer differs from avatar")
		check(mesh.scale.is_equal_approx(Vector3.ONE), "exported mask mesh is not unit scale")
		var mat := mesh.get_active_material(0) as StandardMaterial3D
		check(mat != null, "mask material is missing")
		if mesh.name == "MaskShell":
			check(mat.albedo_color.srgb_to_linear().r < .04 and mat.roughness < .3, "shell is not glossy black")
		else:
			check(mat.emission_enabled and mat.emission.b > .5, "square eye pixels are not blue emissive")
			check(mesh.mesh.surface_get_array_len(0) >= 140 * 8, "enlarged square pixels lost their individual cell geometry")
			check(mesh.mesh.get_blend_shape_count() == 1, "authored blink morph is missing")
	verify_expression(mask, expression)
	for option in AvatarCustomizationCatalog.get_options("glasses"):
		player.set_avatar_customization("glasses", option)
		check(mask.visible == (option == "electronic_mask"), "mask visibility does not match glasses selection: " + option)
		check(Vector2(capsule.radius, capsule.height) == collision_before, "changing face accessory changed collision")
		check(avatar.bunny_head_model == original_head, "changing face accessory replaced original head")
		check(avatar.weapon_socket.transform.is_equal_approx(weapon_before), "changing face accessory moved weapon socket")
	for repeat in range(8):
		player.set_avatar_customization("glasses", "electronic_mask")
	check(socket.get_child_count() == 1, "repeated selections duplicated mask instances")
	player.set_avatar_customization("head", "visor_cyan")
	for node in meshes:
		if node.name == "MaskShell":
			check((node as MeshInstance3D).get_active_material(0).albedo_color.srgb_to_linear().r < .04, "head color recolored black mask")
	player.set_avatar_customization("head", "chibi_anime")
	check(not mask.visible, "mask clips through incompatible chibi head")
	player.set_avatar_customization("head", "bunny_white")
	check(mask.visible, "mask selection did not return after changing back to bunny head")
	player.set_avatar_customization("hat", "field_cap")
	check(mask.visible, "changing hat incorrectly removed face accessory")
	player.set_avatar_customization("hat", "bunny_ears")
	var head_before := avatar.head.transform
	avatar.head.rotation.x += .2
	avatar.head.position.y += .035
	check(mask.global_transform.is_equal_approx(avatar.head.global_transform), "mask does not inherit animated head pose")
	avatar.head.transform = head_before
	var driver := CharacterMotionLibrary3D.new()
	driver.bind(avatar)
	for state in ["idle", "moving", "hurt", "dead"]:
		avatar.set("_state", state)
		driver.apply(avatar, .15)
		check(mask.global_transform.is_equal_approx(avatar.head.global_transform), "imported head animation detached mask: " + state)
	avatar.set("_state", "idle")
	driver.apply(avatar, 0.0)
	check(AvatarCustomizationPersistence.normalize_loadout({})["glasses"] == "electronic_mask", "missing old slot does not default to mask")
	check(AvatarCustomizationPersistence.normalize_loadout({"glasses": "bad_id"})["glasses"] == "electronic_mask", "invalid slot does not fall back to mask")
	check(AvatarCustomizationPersistence.normalize_loadout({"glasses": "none"})["glasses"] == "none", "explicit saved no-accessory choice was overwritten")
	var old_path: String = BaseManager.save_path
	var old_data: BaseData = BaseManager.data
	BaseManager.save_path = SAVE_PATH
	BaseManager.data = BaseData.new()
	check(AvatarCustomizationPersistence.persist_from_player(player), "mask loadout failed to save through existing profile service")
	BaseManager.data = BaseData.new()
	BaseManager.load_base()
	check(AvatarCustomizationPersistence.get_saved_loadout()["glasses"] == "electronic_mask", "mask did not survive real profile reload")
	player.set_avatar_customization("glasses", "none")
	AvatarCustomizationPersistence.apply_saved_to_player(player)
	check(mask.visible, "saved mask did not reapply to existing player")
	BaseManager.save_path = old_path
	BaseManager.data = old_data
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = SAVE_PATH + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not DisplayServer.get_name() == "headless":
		await render_preview(player)
	player.queue_free()
	if failures.is_empty():
		print("ELECTRONIC_MASK_FLOW_OK checks=", checks)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

func verify_expression(mask: Node3D, expression: AnimationPlayer) -> void:
	var pixels := mask.get_node("Visual/ExpressionPixels") as MeshInstance3D
	var shell := mask.get_node("Visual/MaskShell") as MeshInstance3D
	var shell_before := shell.transform
	var pixels_before := pixels.transform
	var mat := pixels.get_active_material(0) as StandardMaterial3D
	var full_emission := mat.emission_energy_multiplier
	for clip in ["mask_idle", "mask_blink", "mask_flicker"]:
		check(expression.has_animation(clip), "missing authored expression clip: " + clip)
	check(expression.get_animation("mask_idle").loop_mode == Animation.LOOP_LINEAR, "ambient expression must loop")
	check(is_equal_approx(expression.get_animation("mask_idle").length, 12.0), "ambient clip duration differs from source")
	expression.play("mask_blink")
	expression.seek(.12, true)
	check(pixels.get_blend_shape_value(0) > .99, "blink did not close eyes")
	expression.seek(.26, true)
	check(pixels.get_blend_shape_value(0) < .01, "blink did not reopen eyes")
	expression.play("mask_flicker")
	expression.seek(.04, true)
	check(is_equal_approx(mat.emission_energy_multiplier, full_emission * .18), "flicker is not sampling authored brightness")
	expression.seek(.42, true)
	check(is_equal_approx(mat.emission_energy_multiplier, full_emission), "flicker did not restore emission")
	expression.play("mask_idle")
	for time in [2.92, 7.32]:
		expression.seek(time, true)
		check(pixels.get_blend_shape_value(0) > .99, "ambient timeline did not blink")
	expression.seek(5.14, true)
	# PackedFloat32Array time keys have sub-microsecond rounding at t=5.14.
	check(absf(mat.emission_energy_multiplier / full_emission - .18) < .0001, "ambient timeline did not flicker")
	expression.seek(12, true)
	check(pixels.get_blend_shape_value(0) < .01 and is_equal_approx(mat.emission_energy_multiplier, full_emission), "loop endpoint leaves a stuck expression")
	check(shell.transform == shell_before and pixels.transform == pixels_before, "expression animation moved component meshes")
	var other := MASK_SCENE.instantiate() as Node3D
	add_child(other)
	other.get_node("ExpressionPlayer").stop()
	var other_mat := (other.get_node("Visual/ExpressionPixels") as MeshInstance3D).get_active_material(0)
	check(other_mat != mat, "face emission material is shared between avatars")
	other.queue_free()
	expression.play("mask_idle")
	expression.seek(0, true)

func render_preview(player: Player3D) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.055, .065, .09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.6, .7, .9)
	env.ambient_light_energy = .55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = .65
	environment.environment = env
	add_child(environment)
	for position in [Vector3(-1.1, 2, -1.8), Vector3(1, 1.5, -1.2)]:
		var light := OmniLight3D.new()
		light.position = position
		light.light_energy = 2.0
		light.omni_range = 5
		light.light_cull_mask = 2
		add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.6
	camera.cull_mask = 2
	camera.current = true
	var target := player.avatar.head.global_position + Vector3(0, .22, 0)
	camera.position = Vector3(0, .72, -3)
	camera.look_at(Vector3(0, .60, 0))
	for index in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_front.png")
	camera.size = .76
	camera.position = target + Vector3(.20, .13, -3)
	camera.look_at(target)
	for index in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_face_closeup.png")
	var blue_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.b > .9 and color.b > color.r * 2.0 and color.g > .35:
				blue_pixels += 1
	check(blue_pixels > 150, "real renderer did not show blue pixel eyes")
	print("ELECTRONIC_MASK_RENDER blue_pixels=", blue_pixels)
	var mask := player.avatar.head.get_node("FaceAccessorySocket/ElectronicMask") as Node3D
	var expression := mask.get_node("ExpressionPlayer") as AnimationPlayer
	var open_height := blue_bounds(image).size.y
	expression.play("mask_blink")
	expression.seek(.12, true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var closed := get_viewport().get_texture().get_image()
	closed.save_png("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_blink_closed.png")
	check(blue_bounds(closed).size.y < open_height * .3, "rendered blink did not visibly close eyes")
	expression.play("mask_flicker")
	expression.seek(.04, true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dimmed := get_viewport().get_texture().get_image()
	dimmed.save_png("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_flicker_dim.png")
	check(blue_energy(dimmed) < blue_energy(image) * .95, "rendered flicker did not visibly dim eyes")
	expression.play("mask_idle")
	expression.seek(0, true)
	if "--capture-expression" in OS.get_cmdline_user_args():
		var frame_dir := "res://outputs/electronic_mask/animation_frames"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frame_dir))
		for frame in range(120):
			expression.seek(float(frame) / 10.0, true)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(frame_dir + "/%03d.png" % frame)

func blue_bounds(image: Image) -> Rect2i:
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i.ZERO
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.b > .9 and color.b > color.r * 2.0 and color.g > .35:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	return Rect2i(minimum, maximum - minimum)

func blue_energy(image: Image) -> float:
	var result := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			result += maxf(0.0, color.b - color.r * 1.5)
	return result
