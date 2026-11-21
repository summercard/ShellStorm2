extends Node3D

const FOCUS := Vector3(-1.9, 0.7, -2.1)
const EROSION_SCENE := preload("res://assets/art/vfx/environment_3d/void_erosion/runtime/vfx_env_void_erosion_root_top3d.tscn")

@onready var _camera: Camera3D = $Camera
@onready var _erosion = $VoidErosion
var _azimuth := 0.58
var _elevation := 0.65
var _reveal: Tween
var _movie_time := 0.0


func _ready() -> void:
	_place_camera()
	set_process(false)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--void-captures="):
			_capture.call_deferred(argument.trim_prefix("--void-captures="))
		elif argument == "--void-orbit":
			$Controls.hide()
			if RenderingServer.get_current_rendering_method() == &"forward_plus":
				get_viewport().use_taa = false
			get_viewport().msaa_3d = Viewport.MSAA_4X
			_erosion.drift_speed = 0.66
			_movie_camera(0.0)
			set_process(true)


func _process(delta: float) -> void:
	_movie_time += delta
	_movie_camera(_movie_time)
	if _movie_time >= 15.0:
		print("VOID_EROSION_MOVIE seconds=15.0")
		get_tree().quit()


func _movie_camera(time: float) -> void:
	_erosion.progress = lerpf(0.52, 1.0, smoothstep(0.5, 4.0, time))
	# A high establishing orbit, followed by a lower pass along the voxel cut.
	var wide := smoothstep(0.0, 6.2, time)
	var close := smoothstep(5.7, 10.6, time)
	var return_to_wide := smoothstep(12.2, 15.0, time)
	var heading := 0.39 + wide * 0.38 + close * 0.23 + return_to_wide * 0.24
	var elevation := 0.76 - wide * 0.07 - close * 0.23 + return_to_wide * 0.21
	var distance := lerpf(35.5, 32.0, wide) - close * 12.8 + return_to_wide * 11.2
	var focus := FOCUS.lerp(Vector3(-5.6, 0.60, -3.7), close * (1.0 - return_to_wide * 0.8))
	var radial := Vector3(sin(heading), 0.0, cos(heading))
	_camera.position = focus + (radial * cos(elevation) + Vector3.UP * sin(elevation)) * distance
	_camera.look_at(focus, Vector3.UP)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_1:
			_set_progress(0.0)
		KEY_2:
			_set_progress(0.55)
		KEY_3:
			_set_progress(1.0)
		KEY_SPACE:
			if event.echo:
				return
			var goal := 1.0 if _erosion.progress < 0.5 else 0.0
			if _reveal != null:
				_reveal.kill()
			_reveal = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			_reveal.tween_property(_erosion, "progress", goal, 2.2)
		KEY_LEFT:
			_azimuth -= 0.06
		KEY_RIGHT:
			_azimuth += 0.06
		KEY_UP:
			_elevation = minf(_elevation + 0.04, 1.34)
		KEY_DOWN:
			_elevation = maxf(_elevation - 0.04, 0.22)
		KEY_P:
			if not event.echo:
				_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE else Camera3D.PROJECTION_PERSPECTIVE
	_place_camera()


func _set_progress(value: float) -> void:
	if _reveal != null:
		_reveal.kill()
	_erosion.progress = value


func _place_camera() -> void:
	var heading := Vector3(sin(_azimuth), 0.0, cos(_azimuth))
	_camera.position = FOCUS + (heading * cos(_elevation) + Vector3.UP * sin(_elevation)) * 32.2
	_camera.size = 24.0
	_camera.look_at(FOCUS, Vector3.UP)


func _capture(output: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Void erosion captures require a graphics device.")
		get_tree().quit(1)
		return
	$Controls.hide()
	if RenderingServer.get_current_rendering_method() == &"forward_plus":
		get_viewport().use_taa = false
	_erosion.drift_speed = 0.0
	var count: int = _erosion.refresh_targets()
	var collider: CollisionShape3D = $Stage/Support/CollisionShape3D
	var shape := collider.shape
	var claimant := EROSION_SCENE.instantiate()
	claimant.target_roots = _erosion.target_roots
	claimant.excluded_roots = _erosion.seam_fill_planes
	add_child(claimant)
	var exclusive: bool = claimant.refresh_targets() == 0
	claimant.queue_free()
	var all_original := true
	for mesh in find_children("*", "MeshInstance3D", true, false):
		all_original = all_original and mesh.material_overlay == null
	var default_targets: Array[NodePath] = _erosion.target_roots
	var stage_targets: Array[NodePath] = [NodePath("../Stage")]
	_erosion.target_roots = stage_targets
	var stage_count: int = _erosion.refresh_targets()
	_erosion.target_roots = default_targets
	var expanded_scope: bool = stage_count > 0 and count > stage_count and _erosion.refresh_targets() == count
	var previous_exclusions: Array[NodePath] = _erosion.excluded_roots
	var exclusions: Array[NodePath] = [NodePath("../Stage/Floor00")]
	_erosion.excluded_roots = exclusions
	var excluded: bool = _erosion.refresh_targets() < count
	_erosion.excluded_roots = previous_exclusions
	var restored_targets: bool = _erosion.refresh_targets() == count
	var rim_depth: float = _erosion.rim_depth
	var far_cubes: int = _erosion.far_cube_count
	var star_density: float = _erosion.star_density
	var wall_panel: Node3D = $Stage/LeftWall1
	var wall_points := PackedVector2Array()
	var samples := [
		["off", 0.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["partial", 0.68, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["full", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["no_cubes", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 0],
		["no_far_cubes", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["no_stars", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["orbit", 1.0, 0.78, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["orthographic", 1.0, 0.58, Camera3D.PROJECTION_ORTHOGONAL, 12],
		["wall_close_off", 0.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["wall_close", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["wall_close_stage_only", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["wall_close_no_depth", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["wall_close_no_panel", 1.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
		["off_restored", 0.0, 0.58, Camera3D.PROJECTION_PERSPECTIVE, 12],
	]
	var captures_ok := true
	var frames: Dictionary[String, Image] = {}
	for sample in samples:
		_erosion.progress = sample[1]
		_azimuth = sample[2]
		_camera.projection = sample[3]
		_erosion.cube_count = sample[4]
		_erosion.rim_depth = 0.0 if sample[0] == "wall_close_no_depth" else rim_depth
		_erosion.far_cube_count = 0 if sample[0] == "no_far_cubes" else far_cubes
		_erosion.star_density = 0.0 if sample[0] == "no_stars" else star_density
		var targets := stage_targets if sample[0] == "wall_close_stage_only" else default_targets
		if _erosion.target_roots != targets:
			_erosion.target_roots = targets
		wall_panel.visible = sample[0] != "wall_close_no_panel"
		_place_camera()
		if String(sample[0]).begins_with("wall_close"):
			_movie_camera(10.70)
			_erosion.progress = sample[1]
		if sample[0] == "wall_close":
			# Sample the actual masked wall face, including the groove near its bottom.
			for row in range(36):
				for column in range(42):
					var position_on_panel := Vector3(-12.55, 0.14 + float(row) * 0.13, -4.94 + float(column) * 0.117)
					wall_points.append(_camera.unproject_position(position_on_panel))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := output.path_join("%s.png" % sample[0])
		var frame := get_viewport().get_texture().get_image()
		captures_ok = (frame.save_png(path) == OK) and captures_ok
		frames[sample[0]] = frame
	_erosion.progress = 1.0
	var rebound: bool = _erosion.refresh_targets() == count
	_erosion.queue_free()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var removed := get_viewport().get_texture().get_image()
	captures_ok = (removed.save_png(output.path_join("removed.png")) == OK) and captures_ok

	var partial_delta := _changed_fraction(frames.off, frames.partial)
	var full_delta := _changed_fraction(frames.off, frames.full)
	var cube_delta := _changed_fraction(frames.full, frames.no_cubes)
	var far_delta := _changed_fraction(frames.full, frames.no_far_cubes)
	var stars_delta := _changed_fraction(frames.full, frames.no_stars)
	# The close view tests the visible cut faces without counting discarded wall lines.
	var depth_delta := _changed_fraction(frames.wall_close, frames.wall_close_no_depth)
	var wall_delta := _wall_change_fraction(frames.wall_close, frames.wall_close_no_panel, wall_points)
	var component_delta := _changed_fraction(frames.wall_close, frames.wall_close_stage_only)
	var restored_delta := _changed_fraction(frames.off, frames.off_restored)
	var removed_delta := _changed_fraction(frames.off, removed)
	var visual_ok := partial_delta > 0.02 and full_delta > partial_delta * 1.3 and cube_delta > 0.005 and depth_delta > 0.003
	visual_ok = visual_ok and far_delta > 0.00025 and stars_delta > 0.0008
	visual_ok = visual_ok and restored_delta < 0.006 and removed_delta < 0.006
	visual_ok = visual_ok and wall_delta < 0.012
	visual_ok = visual_ok and component_delta > 0.0006
	var scene_preserved := all_original and collider.shape == shape
	var passed := (
		count > 0 and exclusive and expanded_scope and excluded and restored_targets and rebound
		and scene_preserved and captures_ok and visual_ok
	)
	print("VOID_EROSION_CAPTURE targets=%d exclusive=%s exclusion=%s rebound=%s scene_properties_preserved=%s passed=%s" %
		[count, exclusive, excluded and restored_targets, rebound, scene_preserved, passed])
	print("VOID_EROSION_PIXELS partial=%.4f full=%.4f cubes=%.4f rim_depth=%.4f off_restored=%.4f removed=%.4f" %
		[partial_delta, full_delta, cube_delta, depth_delta, restored_delta, removed_delta])
	print("VOID_EROSION_DEPTH far_cubes=%.5f spatial_stars=%.5f" % [far_delta, stars_delta])
	print("VOID_EROSION_WALL interior_differences=%.5f samples=%d" % [wall_delta, wall_points.size()])
	print("VOID_EROSION_COMPONENTS host=%d explicit=%d changed_fraction=%.5f" % [count, stage_count, component_delta])
	get_tree().quit(0 if passed else 1)


func _changed_fraction(before: Image, after: Image) -> float:
	# Sample the real rendered frame with tolerance for subpixel/shadow variance.
	var changed := 0
	var samples := 0
	for y in range(0, before.get_height(), 4):
		for x in range(0, before.get_width(), 4):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.05:
				changed += 1
			samples += 1
	return float(changed) / float(samples)


func _wall_change_fraction(before: Image, after: Image, points: PackedVector2Array) -> float:
	var samples := 0
	var changed := 0
	var bounds := Rect2i(Vector2i.ZERO, before.get_size())
	for point in points:
		var pixel := Vector2i(point)
		if bounds.has_point(pixel):
			var a := before.get_pixelv(pixel)
			var b := after.get_pixelv(pixel)
			changed += int(maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.05)
			samples += 1
	return 1.0 if samples == 0 else float(changed) / float(samples)
