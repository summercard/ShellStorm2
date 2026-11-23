extends Node3D

const PRESETS: Array[PackedScene] = [
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_green_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_blue_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_pure_white_space_root_top3d.tscn"),
]

@onready var _room: Node3D = $Room
@onready var _void = $Room/VoidErosion
var _palettes: Array[Node3D] = []
var _active: Node3D
var _mode := 1
var _transition: Tween


func _ready() -> void:
	_room.get_node("Controls").hide()
	_room.set_process_unhandled_key_input(false)
	for preset in PRESETS:
		var space := preset.instantiate() as Node3D
		space.enabled = false
		_room.add_child(space)
		_palettes.append(space)
	_show_mode(_mode)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--space-captures="):
			_capture.call_deferred(argument.trim_prefix("--space-captures="))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode >= KEY_0 and event.keycode <= KEY_5:
		_show_mode(event.keycode - KEY_0)
	elif event.keycode == KEY_SPACE and _active != null:
		_show_mode(_mode)
		_active.progress = 0.0
		_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
		_transition.tween_property(_active, "progress", 1.0, 2.5)
		if _mode == 5:
			_void.progress = 0.0
			_transition.tween_property(_void, "progress", 1.0, 2.4).set_delay(0.65)


func _show_mode(mode: int) -> void:
	if _transition != null:
		_transition.kill()
	_mode = mode
	_active = null
	for i in range(_palettes.size()):
		var space = _palettes[i]
		space.enabled = (mode >= 1 and mode <= 4 and mode == i + 1) or (mode == 5 and i == 2)
		if space.enabled:
			_active = space
			space.position = Vector3(0.0, 0.0, -3.2) if mode == 5 else Vector3.ZERO
			space.box_size = Vector3(13.0, 16.0, 18.0) if mode == 5 else Vector3(36.0, 14.0, 36.0)
			if mode == 5 and i == 2:
				space.grid_origin_offset = _void.position - space.position
			space.progress = 1.0
	_void.enabled = mode == 5
	_void.progress = 1.0


func _capture(output: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cyber Space captures require a real renderer.")
		get_tree().quit(1)
		return
	$Controls.hide()
	if RenderingServer.get_current_rendering_method() == &"forward_plus":
		get_viewport().use_taa = false
	_void.drift_speed = 0.0
	for i in range(_palettes.size()):
		if i < 3:
			_palettes[i].scan_speed = 0.0
	var frames: Dictionary[String, Image] = {}
	var captured := true
	var mixed_counts := Vector2i.ZERO
	for name in ["original", "purple", "green", "blue", "white", "space_only", "void_only", "mixed", "transition", "restored"]:
		var mode := ["original", "purple", "green", "blue", "white"].find(name)
		if mode == -1:
			mode = 0 if name == "restored" else 5
		_show_mode(mode)
		if name == "space_only":
			_void.enabled = false
		elif name == "void_only":
			_active.enabled = false
		elif name == "transition":
			_active.progress = 0.57
			_void.progress = 0.69
		elif name == "mixed":
			mixed_counts = Vector2i(_active.refresh_targets(), _void.refresh_targets())
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var frame := get_viewport().get_texture().get_image()
		captured = frame.save_png(output.path_join(name + ".png")) == OK and captured
		frames[name] = frame
	var purple := _changed_fraction(frames.original, frames.purple)
	var green := _changed_fraction(frames.purple, frames.green)
	var blue := _changed_fraction(frames.green, frames.blue)
	var white := _changed_fraction(frames.blue, frames.white)
	var void_present := _changed_fraction(frames.space_only, frames.mixed)
	var space_present := _changed_fraction(frames.void_only, frames.mixed)
	var transition := _changed_fraction(frames.mixed, frames.transition)
	var restored := _changed_fraction(frames.original, frames.restored)
	var strict_boxes_passed := await _verify_strict_boxes(output)
	var passed := (captured and strict_boxes_passed and mixed_counts.x > 0 and mixed_counts.y > 0
		and purple > 0.08 and green > 0.08 and blue > 0.08 and white > 0.08
		and void_present > 0.035 and space_present > 0.025 and transition > 0.025 and restored < 0.004)
	print("CYBER_SPACE_CAPTURE passed=%s space_targets=%d void_targets=%d" % [passed, mixed_counts.x, mixed_counts.y])
	print("CYBER_SPACE_PIXELS purple=%.4f green=%.4f blue=%.4f white=%.4f void=%.4f space=%.4f transition=%.4f restored=%.4f" %
		[purple, green, blue, white, void_present, space_present, transition, restored])
	get_tree().quit(0 if passed else 1)


func _verify_strict_boxes(output: String) -> bool:
	# A long receiver crosses both sides of the box. A second receiver sits inside
	# the box but is deliberately excluded. Sample each independently from above.
	_room.hide()
	var fixture := Node3D.new()
	fixture.name = "RangeProbe"
	add_child(fixture)
	var receivers := Node3D.new()
	receivers.name = "Receivers"
	fixture.add_child(receivers)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(0.55, 0.32, 0.21)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(20.0, 0.18, 4.0)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = paint
	receivers.add_child(floor_node)
	var excluded := MeshInstance3D.new()
	excluded.name = "Excluded"
	var excluded_mesh := BoxMesh.new()
	excluded_mesh.size = Vector3(2.0, 0.18, 1.4)
	excluded.mesh = excluded_mesh
	excluded.material_override = paint
	excluded.position = Vector3(-4, 0, 3.5)
	receivers.add_child(excluded)
	# A spawned actor lives outside the room-layout subtree, but in the same 3D world.
	var actor := Node3D.new()
	actor.add_to_group(&"base_npc_3d")
	add_child(actor)
	var actor_mesh := MeshInstance3D.new()
	actor_mesh.mesh = excluded_mesh
	actor_mesh.material_override = paint
	actor_mesh.position = Vector3(-4, 0, -3.5)
	actor.add_child(actor_mesh)
	var camera := Camera3D.new()
	fixture.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Measure the receiver pixels, not glow bleeding from the room's environment.
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0.04, 0.04, 0.04)
	camera.size = 16.0
	camera.position = Vector3(0, 16, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.make_current()
	var left := camera.unproject_position(Vector3(-4, 0.09, 0))
	var right := camera.unproject_position(Vector3(4, 0.09, 0))
	var excluded_pixel := camera.unproject_position(Vector3(-4, 0.09, 3.5))
	var actor_pixel := camera.unproject_position(Vector3(-4, 0.09, -3.5))
	var baseline := await _range_frame()
	var effects: Array[PackedScene] = [PRESETS[2], PRESETS[3], preload("res://assets/art/vfx/environment_3d/void_erosion/runtime/vfx_env_void_erosion_root_top3d.tscn")]
	var labels := ["blue", "white", "void"]
	var passed := true
	for i in range(effects.size()):
		var volume = effects[i].instantiate()
		volume.strict_box_bounds = true
		volume.require_explicit_targets = true
		var exclusions: Array[NodePath] = [NodePath("../Receivers/Excluded")]
		volume.excluded_roots = exclusions
		volume.box_size = Vector3(7, 6, 9)
		volume.position = Vector3(-4, 0, 0)
		if i == 0:
			volume.scan_speed = 0.0
		elif i == 2:
			volume.drift_speed = 0.0
		fixture.add_child(volume)
		var initial := await _range_frame()
		var inside := _patch_change(baseline, initial, left)
		var outside := _patch_change(baseline, initial, right)
		var rejected := _patch_change(baseline, initial, excluded_pixel)
		var actor_default := _patch_change(baseline, initial, actor_pixel)
		volume.affected_categories = 1
		var scene_only := await _range_frame()
		var actor_unchecked := _patch_change(baseline, scene_only, actor_pixel)
		var scene_checked := _patch_change(baseline, scene_only, left)
		volume.affected_categories = 2
		var actors_only := await _range_frame()
		var scene_unchecked := _patch_change(baseline, actors_only, left)
		var actor_checked := _patch_change(baseline, actors_only, actor_pixel)
		volume.affected_categories = 3
		volume.position.x = 4.0
		volume.box_size.x = 5.0
		var moved := await _range_frame()
		var moved_inside := _patch_change(baseline, moved, right)
		var moved_outside := _patch_change(baseline, moved, left)
		var category_ok := actor_default > 0.2 and actor_unchecked < 0.01 and scene_checked > 0.2 and scene_unchecked < 0.01 and actor_checked > 0.2
		print("CYBER_SPACE_CATEGORIES %s passed=%s actor_default=%.3f actor_off=%.3f scene_on=%.3f scene_off=%.3f actor_on=%.3f" % [labels[i], category_ok, actor_default, actor_unchecked, scene_checked, scene_unchecked, actor_checked])
		var ok := category_ok and inside > 0.2 and moved_inside > 0.2 and outside < 0.01 and rejected < 0.01 and moved_outside < 0.01
		ok = initial.save_png(output.path_join("range_" + labels[i] + ".png")) == OK and ok
		ok = moved.save_png(output.path_join("range_" + labels[i] + "_moved.png")) == OK and ok
		print("CYBER_SPACE_RANGE %s passed=%s inside=%.3f outside=%.3f excluded=%.3f moved_inside=%.3f moved_outside=%.3f" % [labels[i], ok, inside, outside, rejected, moved_inside, moved_outside])
		passed = ok and passed
		fixture.remove_child(volume)
		volume.queue_free()
	fixture.queue_free()
	return passed


func _range_frame() -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _patch_change(before: Image, after: Image, point: Vector2) -> float:
	var center := Vector2i(point)
	var hits := 0
	for y in range(center.y - 10, center.y + 11):
		for x in range(center.x - 10, center.x + 11):
			var delta := before.get_pixel(x, y) - after.get_pixel(x, y)
			hits += int(Vector3(delta.r, delta.g, delta.b).length() > 0.06)
	return float(hits) / 441.0


func _changed_fraction(before: Image, after: Image) -> float:
	var samples := 0
	var changed := 0
	for y in range(0, before.get_height(), 4):
		for x in range(0, before.get_width(), 4):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			changed += int(maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.06)
			samples += 1
	return float(changed) / float(samples)
