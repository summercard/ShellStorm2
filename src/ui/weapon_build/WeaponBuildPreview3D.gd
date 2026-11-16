extends "res://src/ui/ItemModelIcon3D.gd"

## 专用构建预览：保留 Marker3D 下的真实挂枪，不改变背包图标剥离规则。
var _yaw := 0.0

func _strip_preview_runtime_nodes(root: Node) -> void:
	_quiet_model(root)

func _quiet_model(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
		body.input_ray_pickable = false
	if node is Area3D:
		(node as Area3D).monitoring = false
		(node as Area3D).monitorable = false
	for child in node.get_children():
		_quiet_model(child)

func present_item(item: Dictionary) -> void:
	if item.is_empty():
		clear_model()
		return
	var frozen := item.duplicate(true)
	var factory := func() -> Node3D:
		return ItemModelFactory3D.create_model(frozen, Color.WHITE, ItemModelFactory3D.MODEL_ROLE_PREVIEW)
	configure_custom_model(factory, "weapon")
	_yaw = 18.0

func rotate_preview(delta_x: float) -> void:
	if not is_instance_valid(_model):
		return
	_yaw += delta_x * 0.35
	_model.rotation_degrees.y = _yaw
	_fit_frame_to_model()
	_request_render()
