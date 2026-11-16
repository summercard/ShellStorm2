extends Control

## 仅改变渲染变换，不写 position / offsets / size，结束恢复宿主最终布局。
const SELF_SCRIPT := "res://src/ui/weapon_build/WeaponHologramTransition.gd"
const STATE_KEY := "weapon_hologram_rest_pose"
const TWEEN_KEY := "weapon_hologram_tween"
var progress := 0.0
var anchor := Vector2.ZERO
var closing := false

static func open(target: Control, owner: Node) -> Tween:
	return _animate(target, owner, false)

static func close(target: Control, owner: Node) -> Tween:
	return _animate(target, owner, true)

static func _animate(target: Control, owner: Node, closing: bool) -> Tween:
	var previous: Variant = target.get_meta(TWEEN_KEY) if target.has_meta(TWEEN_KEY) else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	var rest: Dictionary = target.get_meta(STATE_KEY, {})
	if rest.is_empty():
		rest = {"scale": target.scale, "pivot": target.pivot_offset, "modulate": target.modulate}
		target.set_meta(STATE_KEY, rest)
	# 中断时归一后重新展开，避免缩放累计、布局漂移或并发生成视图。
	target.scale = rest["scale"]
	target.pivot_offset = rest["pivot"]
	target.modulate = rest["modulate"]
	for child in target.get_children():
		if child.has_meta("weapon_hologram_overlay"):
			target.remove_child(child)
			child.queue_free()
	var anchor := _project_anchor(target, owner)
	target.pivot_offset = anchor
	var reduced := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	var duration := 0.07 if reduced else (0.23 if closing else 0.32)
	var overlay: Control = load(SELF_SCRIPT).new()
	overlay.set_meta("weapon_hologram_overlay", true)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set("anchor", anchor)
	overlay.set("closing", closing)
	overlay.z_index = 30
	target.add_child(overlay)
	overlay.size = target.size
	var base_scale: Vector2 = rest["scale"]
	var base_color: Color = rest["modulate"]
	if not closing:
		target.scale = base_scale if reduced else base_scale * 0.025
		target.modulate.a = 0.0
		target.show()
	var tween := target.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if closing else Tween.EASE_OUT)
	tween.tween_property(target, "scale", base_scale * (1.0 if reduced or not closing else 0.025), duration)
	tween.tween_property(target, "modulate:a", 0.0 if closing else base_color.a, duration)
	tween.tween_method(Callable(overlay, "set_progress"), 0.0, 1.0, duration)
	target.set_meta(TWEEN_KEY, tween)
	tween.finished.connect(func() -> void:
		if not is_instance_valid(target):
			return
		if closing:
			target.hide()
		target.scale = rest["scale"]
		target.pivot_offset = rest["pivot"]
		target.modulate = rest["modulate"]
		target.remove_meta(TWEEN_KEY)
		target.remove_meta(STATE_KEY)
		if is_instance_valid(overlay):
			overlay.queue_free())
	return tween

static func _project_anchor(target: Control, owner: Node) -> Vector2:
	var fallback := Vector2(target.size.x * 0.22, target.size.y * 0.65)
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return fallback
	var camera := owner.get_viewport().get_camera_3d()
	if camera == null:
		return fallback
	var model: Node3D
	for property: Dictionary in owner.get_property_list():
		if str(property.get("name", "")) == "weapon":
			model = owner.get("weapon") as Node3D
			break
	if not is_instance_valid(model) or not model.is_inside_tree():
		return fallback
	var world_position := model.global_position
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh != null and mesh.is_visible_in_tree():
			world_position = mesh.global_transform * mesh.mesh.get_aabb().get_center()
			break
	if camera.is_position_behind(world_position):
		return fallback
	var projected := camera.unproject_position(world_position)
	if not camera.get_viewport().get_visible_rect().has_point(projected):
		return fallback
	# 投影为视口坐标，经父 CanvasItem 变换回父坐标，再回目标局部锚点。
	var parent := target.get_parent() as CanvasItem
	if parent == null:
		return target.get_global_transform_with_canvas().affine_inverse() * projected
	var in_parent := parent.get_global_transform_with_canvas().affine_inverse() * projected
	return target.get_transform().affine_inverse() * in_parent

func set_progress(value: float) -> void:
	progress = value
	queue_redraw()

func _draw() -> void:
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	var spread := 1.0 - progress if closing else progress
	var alpha := sin(progress * PI) * 0.48
	# 投影块的前后平面与四条深度边；仅在过渡期间出现，不给静止UI加厚框。
	var bounds := Rect2(Vector2(4, 4), (size - Vector2(8, 8)).max(Vector2.ONE))
	var depth := Vector2(18, -12) * (1.0 - spread)
	var wire := Color(0.65, 0.87, 1.0, alpha)
	draw_rect(bounds, wire, false, 1.5)
	draw_rect(Rect2(bounds.position + depth, bounds.size), Color(wire, alpha * 0.55), false, 1.0)
	for corner in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		draw_line(corner, corner + depth, wire, 1.0)
	for i in 22:
		var final := Vector2(float((i * 7) % 11) / 10.0 * size.x, float((i * 3) % 7) / 6.0 * size.y)
		var point := anchor.lerp(final, spread)
		var width := lerpf(12.0, 3.0, spread)
		draw_rect(Rect2(point - Vector2.ONE * width * 0.5, Vector2.ONE * width), Color(0.65, 0.85, 1.0, alpha), false, 1.0)
