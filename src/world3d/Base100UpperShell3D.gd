class_name Base100UpperShell3D
extends Node3D
## 100层上层围护与18米封顶的组合Prefab。子节点位置完全由tscn持有；
## 本脚本只提供连续结构碰撞和统一投影策略；墙体与封顶均参与真实遮光。

const ROOM_SIZE := 30.0
const WALL_BASE_Y := 9.0
const WALL_HEIGHT := 9.0
const WALL_THICKNESS := 0.30
const ROOF_Y := 18.0
const ROOF_THICKNESS := 0.30
const EAST_DOOR_CENTER_Z := -7.5
const DOOR_MODULE_WIDTH := 5.0
const DOOR_CLEAR_WIDTH := 2.2
const DOOR_CLEAR_HEIGHT := 2.5


func _ready() -> void:
	_set_shadow_casting(self, true)
	set_meta("shadow_policy", "cast_and_receive")
	_build_structure_collision()


func _build_structure_collision() -> void:
	if get_node_or_null("UpperShellStructureCollision") != null:
		return
	var body := StaticBody3D.new()
	body.name = "UpperShellStructureCollision"
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("base100_upper_shell_collision", true)
	add_child(body)
	var wall_center_y := WALL_BASE_Y + WALL_HEIGHT * 0.5
	_add_box(body, "NorthWallCollision", Vector3(0.0, wall_center_y, -15.0), Vector3(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), "wall")
	_add_box(body, "SouthWallCollision", Vector3(0.0, wall_center_y, 15.0), Vector3(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), "wall")
	_add_box(body, "WestWallCollision", Vector3(-15.0, wall_center_y, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), "wall")
	# 东墙在Blender母版z=-7.5位置保留5米门墙槽，连续墙碰撞在此拆分。
	_add_box(body, "EastWallNorthRunCollision", Vector3(15.0, wall_center_y, -12.5), Vector3(WALL_THICKNESS, WALL_HEIGHT, 5.0), "wall")
	_add_box(body, "EastWallSouthRunCollision", Vector3(15.0, wall_center_y, 5.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, 20.0), "wall")
	var side_width := (DOOR_MODULE_WIDTH - DOOR_CLEAR_WIDTH) * 0.5
	var side_offset := DOOR_CLEAR_WIDTH * 0.5 + side_width * 0.5
	for side in [-1.0, 1.0]:
		_add_box(
			body,
			"EastDoorSideCollision_%s" % ("N" if side < 0.0 else "S"),
			Vector3(15.0, wall_center_y, EAST_DOOR_CENTER_Z + side * side_offset),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, side_width),
			"door_frame"
		)
	_add_box(
		body,
		"EastDoorLintelCollision",
		Vector3(15.0, WALL_BASE_Y + DOOR_CLEAR_HEIGHT + (WALL_HEIGHT - DOOR_CLEAR_HEIGHT) * 0.5, EAST_DOOR_CENTER_Z),
		Vector3(WALL_THICKNESS, WALL_HEIGHT - DOOR_CLEAR_HEIGHT, DOOR_CLEAR_WIDTH),
		"door_frame"
	)
	_add_box(body, "RoofCollision", Vector3(0.0, ROOF_Y + ROOF_THICKNESS * 0.5, 0.0), Vector3(ROOM_SIZE, ROOF_THICKNESS, ROOM_SIZE), "roof")


func _add_box(body: StaticBody3D, node_name: String, center: Vector3, size: Vector3, role: String) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = node_name
	collision.position = center
	collision.shape = shape
	collision.set_meta("base100_structure_role", role)
	body.add_child(collision)


func _set_shadow_casting(root: Node, enabled: bool) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in root.get_children():
		_set_shadow_casting(child, enabled)
