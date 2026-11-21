extends Node3D

const PRESETS: Array[PackedScene] = [
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_green_root_top3d.tscn"),
	preload("res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_blue_root_top3d.tscn"),
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
	if event.keycode >= KEY_0 and event.keycode <= KEY_4:
		_show_mode(event.keycode - KEY_0)
	elif event.keycode == KEY_SPACE and _active != null:
		_show_mode(_mode)
		_active.progress = 0.0
		_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
		_transition.tween_property(_active, "progress", 1.0, 2.5)
		if _mode == 4:
			_void.progress = 0.0
			_transition.tween_property(_void, "progress", 1.0, 2.4).set_delay(0.65)


func _show_mode(mode: int) -> void:
	if _transition != null:
		_transition.kill()
	_mode = mode
	_active = null
	for i in range(_palettes.size()):
		var space = _palettes[i]
		space.enabled = mode == i + 1 or (mode == 4 and i == 0)
		if space.enabled:
			_active = space
			space.position = Vector3(0.0, 0.0, -3.2) if mode == 4 else Vector3.ZERO
			space.box_size = Vector3(13.0, 16.0, 18.0) if mode == 4 else Vector3(36.0, 14.0, 36.0)
			space.grid_origin_offset = _void.position - space.position if mode == 4 else Vector3.ZERO
			space.progress = 1.0
	_void.enabled = mode == 4
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
	for space in _palettes:
		space.scan_speed = 0.0
	var frames: Dictionary[String, Image] = {}
	var captured := true
	var mixed_counts := Vector2i.ZERO
	for name in ["original", "purple", "green", "blue", "space_only", "void_only", "mixed", "transition", "restored"]:
		var mode := ["original", "purple", "green", "blue"].find(name)
		if mode == -1:
			mode = 0 if name == "restored" else 4
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
	var void_present := _changed_fraction(frames.space_only, frames.mixed)
	var space_present := _changed_fraction(frames.void_only, frames.mixed)
	var transition := _changed_fraction(frames.mixed, frames.transition)
	var restored := _changed_fraction(frames.original, frames.restored)
	var passed := (captured and mixed_counts.x > 0 and mixed_counts.y > 0
		and purple > 0.08 and green > 0.08 and blue > 0.08 and void_present > 0.035
		and space_present > 0.025 and transition > 0.025 and restored < 0.004)
	print("CYBER_SPACE_CAPTURE passed=%s space_targets=%d void_targets=%d" % [passed, mixed_counts.x, mixed_counts.y])
	print("CYBER_SPACE_PIXELS purple=%.4f green=%.4f blue=%.4f void=%.4f space=%.4f transition=%.4f restored=%.4f" %
		[purple, green, blue, void_present, space_present, transition, restored])
	get_tree().quit(0 if passed else 1)


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
