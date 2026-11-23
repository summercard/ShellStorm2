@tool
extends EditorNode3DGizmoPlugin

const CYBER := preload("res://src/vfx/VfxCyberSpace3D.gd")
const WHITE := preload("res://src/vfx/VfxPureWhiteSpace3D.gd")
const VOID := preload("res://src/vfx/VfxVoidErosion3D.gd")
const EDGES := [0, 1, 0, 2, 0, 4, 1, 3, 1, 5, 2, 3, 2, 6, 3, 7, 4, 5, 4, 6, 5, 7, 6, 7]
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
var _undo: EditorUndoRedoManager


func _init(undo: EditorUndoRedoManager) -> void:
	_undo = undo
	create_material("bounds", Color(0.43, 0.85, 1.0, 0.85))
	create_handle_material("size")


static func is_volume(node: Node) -> bool:
	return node is CYBER or node is WHITE or node is VOID


func _has_gizmo(node: Node3D) -> bool:
	return is_volume(node) and node.get("strict_box_bounds") == true


func _get_gizmo_name() -> String:
	return "Shader 范围盒"


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var half: Vector3 = gizmo.get_node_3d().get("box_size") * 0.5
	var box := AABB(-half, half * 2.0)
	var lines := PackedVector3Array()
	for index in EDGES:
		lines.append(box.get_endpoint(index))
	gizmo.add_lines(lines, get_material("bounds", gizmo))
	gizmo.add_collision_segments(lines)
	gizmo.add_handles(PackedVector3Array([Vector3.RIGHT * half.x, Vector3.UP * half.y, Vector3.BACK * half.z]), get_material("size", gizmo), PackedInt32Array([0, 1, 2]))


func _get_handle_name(_gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return ["宽度 X", "高度 Y", "深度 Z"][id]


func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().get("box_size")


func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	if absf(node.global_basis.determinant()) < 0.000001:
		return
	var world_to_box := node.global_transform.affine_inverse()
	var ray_origin := camera.project_ray_origin(screen_pos)
	var from := world_to_box * ray_origin
	var to := world_to_box * (ray_origin + camera.project_ray_normal(screen_pos) * camera.far)
	var axis: Vector3 = AXES[id]
	var length_limit := maxf(10000.0, (to - from).length())
	var closest := Geometry3D.get_closest_points_between_segments(Vector3.ZERO, axis * length_limit, from, to)
	var size: Vector3 = node.get("box_size")
	size[id] = maxf(0.05, closest[0].dot(axis) * 2.0)
	node.set("box_size", size)


func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	if cancel:
		node.set("box_size", restore)
		return
	var size: Vector3 = node.get("box_size")
	if size == restore:
		return
	_undo.create_action("调整 Shader 范围盒", UndoRedo.MERGE_DISABLE, node)
	_undo.add_do_property(node, "box_size", size)
	_undo.add_undo_property(node, "box_size", restore)
	_undo.commit_action(false)
