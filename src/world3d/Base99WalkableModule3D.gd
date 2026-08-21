class_name Base99WalkableModule3D
extends Node3D
## 基地99层可编辑结构组件。模型位置由美术布置.tscn持有；本脚本只在组件
## 局部空间生成简化行走面，因此移动/旋转组件时表现与碰撞会保持同步。

@export_enum("mezzanine", "l_stair", "exterior_stair") var collision_role := "mezzanine"
@export_range(0.5, 12.0, 0.1, "or_greater") var target_walkable_height_m := 5.0

const COLLISION_THICKNESS := 0.18
const GUARD_COLLISION_THICKNESS := 0.16
const GUARD_COLLISION_HEIGHT := 1.12


func _ready() -> void:
	_set_shadow_casting(self, true)
	set_meta("shadow_policy", "cast_and_receive")
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
			_add_box_surface(
				root,
				"MezzanineDeck",
				Vector3(0.0, target_walkable_height_m - 0.15, 0.0),
				Vector3(20.0, 0.30, 10.0),
				"mezzanine"
			)
			# 与Blender母版的可见栏杆严格对齐。西缘仅在L梯顶部保留
			# 2.95m入口；南缘连续封闭，角色不能从平台边缘直接跌落。
			_add_guard_box(
				root, "MezzanineGuardSouth", Vector3(0.0, target_walkable_height_m, 5.02),
				Vector3(20.0, GUARD_COLLISION_HEIGHT, GUARD_COLLISION_THICKNESS),
				"mezzanine_south"
			)
			_add_guard_box(
				root, "MezzanineGuardWestSouth", Vector3(-10.02, target_walkable_height_m, 1.68),
				Vector3(GUARD_COLLISION_THICKNESS, GUARD_COLLISION_HEIGHT, 6.40),
				"mezzanine_west_south"
			)
			_add_guard_box(
				root, "MezzanineGuardWestNorth", Vector3(-10.02, target_walkable_height_m, -4.80),
				Vector3(GUARD_COLLISION_THICKNESS, GUARD_COLLISION_HEIGHT, 0.65),
				"mezzanine_west_north"
			)
		"l_stair":
			# Blender母版：下跑沿-Z升高，转角后上跑沿+X升高。
			# 整段楼梯只使用一个StaticBody；两块斜坡和平台是它的三个形状。
			# 坡脚向地面内延伸并略微下沉，避免CharacterBody先撞到斜盒端面。
			var half_height := target_walkable_height_m * 0.5
			var lower_start := Vector3(-2.90, -0.04, 5.35)
			# 下跑末端和上跑起点分别伸入平台4cm，顶面均精确等于2.5m。
			# 不再保留旧版0.45m断口，也不制造平台边缘竖向台阶。
			var lower_end := Vector3(-2.90, half_height, -1.76)
			var upper_start := Vector3(-1.34, half_height, -3.72)
			var upper_end := Vector3(4.55, target_walkable_height_m + 0.02, -3.72)
			var unified_walkable := _new_walkable_body(
				"LStairUnifiedWalkable", "l_stair_unified"
			)
			unified_walkable.set_meta(
				"collision_model", "single_body_ramp_landing_ramp"
			)
			root.add_child(unified_walkable)
			_add_ramp_shape(
				unified_walkable, "LStairLowerRamp", lower_start, lower_end, 2.72
			)
			# 斜坡顶面与平台顶面同高并轻微重叠，避免出现CharacterBody不可跨越的竖边。
			_add_box_shape(
				unified_walkable, "LStairLanding",
				Vector3(-2.90, half_height - 0.16, -3.40),
				Vector3(3.20, 0.32, 3.20)
			)
			_add_ramp_shape(
				unified_walkable, "LStairUpperRamp", upper_start, upper_end, 2.72
			)
			# 扶手只作为独立边缘阻挡；角色脚下始终只接触三块连续的
			# 坡面/平台，杜绝逐级碰撞和扶手柱将胶囊体卡住。
			_add_ramp_guards(root, "LStairLower", lower_start, lower_end, 1.46)
			_add_guard_box(
				root, "LStairLandingGuardWest",
				Vector3(-4.52, half_height, -3.62),
				Vector3(GUARD_COLLISION_THICKNESS, GUARD_COLLISION_HEIGHT, 3.20),
				"l_stair_landing_west"
			)
			_add_guard_box(
				root, "LStairLandingGuardNorth",
				Vector3(-2.92, half_height, -5.22),
				Vector3(3.20, GUARD_COLLISION_HEIGHT, GUARD_COLLISION_THICKNESS),
				"l_stair_landing_north"
			)
			_add_ramp_guards(root, "LStairUpper", upper_start, upper_end, 1.46)
		"exterior_stair":
			# H4视觉由两段H2资产首尾连接，实际水平包络为8.515m；玩法坡面
			# 必须覆盖完整包络，不能沿用单段4.5m长度形成过陡坡和半段空气踏步。
			var exterior_start := Vector3(-4.22, -0.04, 0.0)
			var exterior_end := Vector3(4.22, target_walkable_height_m + 0.02, 0.0)
			_add_ramp_surface(
				root, "ExteriorStairRamp", exterior_start, exterior_end, 2.72,
				"exterior_stair"
			)
			_add_ramp_guards(
				root, "ExteriorStair", exterior_start, exterior_end, 1.46
			)


func _add_box_surface(parent: Node3D, node_name: String, center: Vector3, size: Vector3, camera_role: String) -> void:
	var body := _new_walkable_body(node_name, camera_role)
	parent.add_child(body)
	_add_box_shape(body, node_name, center, size)


func _add_box_shape(body: StaticBody3D, node_name: String, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "%sShape" % node_name
	collision.position = center
	collision.shape = shape
	collision.set_meta("persistent_stair_support", true)
	body.add_child(collision)


func _add_ramp_surface(parent: Node3D, node_name: String, start_top: Vector3, end_top: Vector3, width: float, camera_role: String) -> void:
	var body := _new_walkable_body(node_name, camera_role)
	parent.add_child(body)
	_add_ramp_shape(body, node_name, start_top, end_top, width)


func _add_ramp_shape(body: StaticBody3D, node_name: String, start_top: Vector3, end_top: Vector3, width: float) -> void:
	var direction := end_top - start_top
	var forward := direction.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var surface_up := right.cross(forward).normalized()
	if surface_up.y < 0.0:
		right = -right
		surface_up = -surface_up
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, COLLISION_THICKNESS, direction.length())
	var collision := CollisionShape3D.new()
	collision.name = "%sShape" % node_name
	collision.basis = Basis(right, surface_up, forward)
	collision.position = (start_top + end_top) * 0.5 - surface_up * COLLISION_THICKNESS * 0.5
	collision.shape = shape
	collision.set_meta("persistent_stair_support", true)
	body.add_child(collision)


func _add_ramp_guards(
	parent: Node3D,
	name_prefix: String,
	start_top: Vector3,
	end_top: Vector3,
	side_offset: float
) -> void:
	var direction := end_top - start_top
	var forward := direction.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var surface_up := right.cross(forward).normalized()
	if surface_up.y < 0.0:
		right = -right
		surface_up = -surface_up
	for side_sign in [-1.0, 1.0]:
		var side_name := "A" if side_sign < 0.0 else "B"
		var shape := BoxShape3D.new()
		shape.size = Vector3(
			GUARD_COLLISION_THICKNESS,
			GUARD_COLLISION_HEIGHT,
			direction.length()
		)
		var body := _new_guard_body(
			"%sGuard%s" % [name_prefix, side_name],
			"%s_%s" % [name_prefix.to_snake_case(), side_name.to_lower()]
		)
		parent.add_child(body)
		var collision := CollisionShape3D.new()
		collision.name = "%sShape" % body.name
		collision.basis = Basis(right, surface_up, forward)
		collision.position = (
			(start_top + end_top) * 0.5
			+ right * side_offset * side_sign
			+ surface_up * GUARD_COLLISION_HEIGHT * 0.5
		)
		collision.shape = shape
		body.add_child(collision)


func _add_guard_box(
	parent: Node3D,
	node_name: String,
	floor_center: Vector3,
	size: Vector3,
	guard_role: String
) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var body := _new_guard_body(node_name, guard_role)
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "%sShape" % node_name
	collision.position = floor_center + Vector3.UP * size.y * 0.5
	collision.shape = shape
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


func _new_guard_body(node_name: String, guard_role: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("base99_guard_collision", true)
	body.set_meta("base99_guard_role", guard_role)
	body.set_meta("collision_mode", "editable_prefab_continuous_guard_blocker")
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
