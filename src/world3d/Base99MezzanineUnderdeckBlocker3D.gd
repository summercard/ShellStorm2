class_name Base99MezzanineUnderdeckBlocker3D
extends Node3D
## Permanent three-sided collision enclosure for the Base99 mezzanine underside.

const COLLISION_HEIGHT_M := 4.95
const COLLISION_THICKNESS_M := 0.44
const SOUTH_WIDTH_M := 19.20
const SIDE_DEPTH_M := 9.16
const INSET_M := 0.55


func _ready() -> void:
	_set_shadow_casting(self)
	set_meta("permanent_base99_collision", true)
	set_meta("collision_policy", "underdeck_perimeter_blocker")
	if get_node_or_null("UnderdeckBlockerCollision") == null:
		_build_collision()


func _build_collision() -> void:
	var root := Node3D.new()
	root.name = "UnderdeckBlockerCollision"
	root.set_meta("base99_underdeck_collision_root", true)
	add_child(root)
	# These three boxes deliberately sit inside the visible mezzanine frame.
	# The north side is already closed by the facility's exterior wall.
	_add_blocker(root, "SouthWarehouseBlocker", Vector3(0.0, COLLISION_HEIGHT_M * 0.5, -4.45), Vector3(SOUTH_WIDTH_M, COLLISION_HEIGHT_M, COLLISION_THICKNESS_M))
	_add_blocker(root, "WestWarehouseBlocker", Vector3(-9.45, COLLISION_HEIGHT_M * 0.5, 0.0), Vector3(COLLISION_THICKNESS_M, COLLISION_HEIGHT_M, SIDE_DEPTH_M))
	_add_blocker(root, "EastWarehouseBlocker", Vector3(9.45, COLLISION_HEIGHT_M * 0.5, 0.0), Vector3(COLLISION_THICKNESS_M, COLLISION_HEIGHT_M, SIDE_DEPTH_M))


func _add_blocker(parent: Node3D, node_name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("base99_underdeck_permanent_blocker", true)
	body.set_meta("collision_mode", "permanent_solid_warehouse_panel")
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = node_name + "Shape"
	collision.position = center
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)


func _set_shadow_casting(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in root.get_children():
		_set_shadow_casting(child)
