class_name PushableSeat3D
extends RigidBody3D
## 可推、可乘坐的基地家具。驾驶始终通过刚体受力，场景碰撞不被绕过。

@export var seat_height := 0.83
@export var drive_acceleration := 19.0
@export var ride_speed_multiplier := 1.3
@export var coast_damp := 5.0
@export var drive_damp := 1.0
@export var max_push_speed := 2.2
const TIP_ANGLE_RADIANS := PI / 4.0

var rider: Player3D = null
var _drive_input := Vector3.ZERO
var _target_swivel_yaw := 0.0
var _dismount_brake_timer := 0.0
var _registered_player_ids: Dictionary = {}
@onready var swivel_pivot: Node3D = $SwivelPivot
@onready var player_blocker: AnimatableBody3D = $PlayerBlocker


func _ready() -> void:
	# 物理刚体下嵌套的第二个 PhysicsBody 不会可靠地更新服务器中的碰撞位置。
	# 保留节点归属，但让角色专用阻挡体独立使用世界坐标，并逐物理帧跟随底座。
	player_blocker.top_level = true
	player_blocker.sync_to_physics = false
	player_blocker.global_transform = global_transform


func _register_player_collision_proxy() -> void:
	for value in get_tree().get_nodes_in_group("player_3d"):
		var player := value as Player3D
		if player == null or _registered_player_ids.has(player.get_instance_id()):
			continue
		# 角色碰 PlayerBlocker（layer 16）；与主刚体互相豁免，避免求解器弹射。
		add_collision_exception_with(player)
		player.add_collision_exception_with(self)
		player.collision_mask |= 16
		_registered_player_ids[player.get_instance_id()] = true


func get_seat_position() -> Vector3:
	return to_global(Vector3(0.0, seat_height, 0.0))


func get_ride_speed() -> float:
	return rider.get_move_speed() * ride_speed_multiplier if rider != null and is_instance_valid(rider) else 0.0


func is_tipped() -> bool:
	return global_basis.y.normalized().dot(Vector3.UP) <= cos(TIP_ANGLE_RADIANS)


func right_seat(player: Player3D = null) -> bool:
	if rider != null or not is_tipped():
		return false
	var excluded: Array[RID] = [get_rid(), player_blocker.get_rid()]
	if player != null:
		excluded.append(player.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, global_position + Vector3.DOWN * 2.5, 1, excluded)
	var ground := get_world_3d().direct_space_state.intersect_ray(ray)
	if ground.is_empty():
		return false
	var yaw := global_rotation.y
	var scale_factor := global_basis.get_scale()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(scale_factor), Vector3(global_position.x, (ground["position"] as Vector3).y + 0.02, global_position.z))
	player_blocker.global_transform = global_transform
	sleeping = false
	return true


func set_swivel_yaw(world_yaw: float) -> void:
	_target_swivel_yaw = wrapf(world_yaw - global_rotation.y, -PI, PI)


func finish_ride() -> void:
	rider = null
	_drive_input = Vector3.ZERO
	_dismount_brake_timer = 0.35
	# 离座时刹住大部分动量，避免胶囊恢复碰撞时把刚体弹射。
	var planar := Vector2(linear_velocity.x, linear_velocity.z)
	if planar.length() > 0.35:
		planar = planar.normalized() * 0.35
		linear_velocity.x = planar.x
		linear_velocity.z = planar.y
	angular_velocity = Vector3.ZERO


func get_interaction_candidate(player: Player3D) -> Dictionary:
	if rider == player:
		return {"available": true, "interaction_id": "leave_seat", "prompt": "E 离开座椅", "priority": 120, "position": get_seat_position()}
	if rider != null or player.get_state_machine_state() not in ["idle", "moving"]:
		return {}
	var delta := player.global_position - global_position
	delta.y = 0.0
	if delta.length() > 1.35 or absf(player.global_position.y - global_position.y) > 1.0:
		return {}
	if Vector2(linear_velocity.x, linear_velocity.z).length() > 0.55:
		return {}
	if is_tipped():
		return {"available": true, "interaction_id": "right_seat", "prompt": "E 扶正座椅", "priority": 90, "position": global_position}
	return {"available": true, "interaction_id": "sit_on_seat", "prompt": "E 坐上座椅", "priority": 70, "position": get_seat_position()}


## 常驻圆点锚点：座位上沿，跟随椅子移动/翻倒。
func get_interaction_dot_anchor() -> Vector3:
	if is_tipped():
		return global_position + Vector3.UP * 0.45
	return get_seat_position() + Vector3.UP * 0.95


func get_interaction_dot_accent() -> Color:
	return Color(1.0, 0.82, 0.34)


func perform_interaction(player: Player3D, candidate: Dictionary) -> bool:
	match str(candidate.get("interaction_id", "")):
		"sit_on_seat":
			return player.try_mount_chair(self)
		"leave_seat":
			return player.try_dismount_chair()
		"right_seat":
			return right_seat(player)
	return false


func drive(input_direction: Vector3) -> void:
	if rider == null or not is_instance_valid(rider):
		return
	_drive_input = Vector3(input_direction.x, 0.0, input_direction.z).normalized()


func _physics_process(delta: float) -> void:
	player_blocker.global_transform = global_transform
	_register_player_collision_proxy()
	if rider != null and not is_instance_valid(rider):
		finish_ride()
	if rider != null:
		linear_damp = drive_damp if _drive_input.length_squared() > 0.001 else coast_damp
		var speed_cap := get_ride_speed()
		var planar_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if _drive_input.length_squared() > 0.001 and planar_velocity.dot(_drive_input) < speed_cap:
			apply_central_force(_drive_input * mass * drive_acceleration)
	else:
		_dismount_brake_timer = maxf(0.0, _dismount_brake_timer - delta)
		linear_damp = coast_damp if _dismount_brake_timer > 0.0 else 0.8
	var speed_cap := get_ride_speed() if rider != null else max_push_speed
	var planar := Vector2(linear_velocity.x, linear_velocity.z)
	if planar.length() > speed_cap:
		planar = planar.normalized() * speed_cap
		linear_velocity.x = planar.x
		linear_velocity.z = planar.y
	var current_yaw := swivel_pivot.rotation.y
	swivel_pivot.rotation.y = lerp_angle(current_yaw, _target_swivel_yaw, minf(1.0, delta * 16.0))
