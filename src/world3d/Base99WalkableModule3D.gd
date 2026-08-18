class_name Base99WalkableModule3D
extends Node3D
## 基地99层可编辑结构组件。模型位置由美术布置.tscn持有；本脚本只在组件
## 局部空间生成简化行走面，因此移动/旋转组件时表现与碰撞会保持同步。

@export_enum("mezzanine", "l_stair", "exterior_stair") var collision_role := "mezzanine"

const COLLISION_THICKNESS := 0.18


func _ready() -> void:
	_set_shadow_casting(self, false)
	set_meta("shadow_policy", "receive_light_no_cast")
	_build_walkable_collision()


func _build_walkable_collision() -> void:
	if get_node_or_null("WalkableCollision") != null:
		return
	var root := Node3D.new()
	root.name = "WalkableCollision"
	root.set_meta("base99_editable_collision_root", true)
	add_child(root)
	match collision_role:
		"mezzanine":
			_add_box_surface(root, "MezzanineDeck", Vector3(0.0, 6.85, 0.0), Vector3(20.0, 0.30, 10.0), "mezzanine")
		"l_stair":
			# Blender母版：下跑沿-Z升高，转角后上跑沿+X升高。
			# 坡脚向地面内延伸并略微下沉，避免CharacterBody先撞到斜盒端面。
			_add_ramp_surface(root, "LStairLowerRamp", Vector3(-2.90, -0.04, 5.35), Vector3(-2.90, 3.48, -1.35), 2.72, "l_stair_lower")
			# 斜坡顶面与平台顶面同高并轻微重叠，避免出现CharacterBody不可跨越的竖边。
			_add_box_surface(root, "LStairLanding", Vector3(-2.90, 3.32, -3.40), Vector3(3.20, 0.32, 3.20), "l_stair_landing")
			_add_ramp_surface(root, "LStairUpperRamp", Vector3(-2.18, 3.46, -3.72), Vector3(4.55, 7.02, -3.72), 2.72, "l_stair_upper")
		"exterior_stair":
			_add_ramp_surface(root, "ExteriorStairRamp", Vector3(-2.25, -0.04, 0.0), Vector3(2.18, 2.02, 0.0), 2.72, "exterior_stair")


func _add_box_surface(parent: Node3D, node_name: String, center: Vector3, size: Vector3, camera_role: String) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var body := _new_walkable_body(node_name, camera_role)
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "%sShape" % node_name
	collision.position = center
	collision.shape = shape
	collision.set_meta("persistent_stair_support", true)
	body.add_child(collision)


func _add_ramp_surface(parent: Node3D, node_name: String, start_top: Vector3, end_top: Vector3, width: float, camera_role: String) -> void:
	var direction := end_top - start_top
	var forward := direction.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var surface_up := right.cross(forward).normalized()
	if surface_up.y < 0.0:
		right = -right
		surface_up = -surface_up
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, COLLISION_THICKNESS, direction.length())
	var body := _new_walkable_body(node_name, camera_role)
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "%sShape" % node_name
	collision.basis = Basis(right, surface_up, forward)
	collision.position = (start_top + end_top) * 0.5 - surface_up * COLLISION_THICKNESS * 0.5
	collision.shape = shape
	collision.set_meta("persistent_stair_support", true)
	body.add_child(collision)


func _new_walkable_body(node_name: String, camera_role: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("base99_walkable_collision", true)
	body.set_meta("camera_stair_slab", true)
	body.set_meta("camera_stair_slab_role", camera_role)
	body.set_meta("collision_mode", "editable_prefab_simplified_walkable_surface")
	return body


func _set_shadow_casting(root: Node, enabled: bool) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in root.get_children():
		_set_shadow_casting(child, enabled)
