extends Node

const STOOL := preload("res://assets/art/props/base_world_3d/runtime/workshop_stool/prp_base_workshop_stool_root_top3d.tscn")
const CHAIR := preload("res://assets/art/props/base_world_3d/runtime/mission_command_chair/prp_base_mission_command_chair_root_top3d.tscn")
const PLAYER := preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	BaseManager.save_path = "user://verify_pushable_base_chairs_%d.json" % Time.get_ticks_usec()
	BaseManager.data = BaseData.new()
	_add_static_box("Floor", Vector3(0.0, -0.1, 0.0), Vector3(12.0, 0.2, 12.0))
	_add_static_box("StopWall", Vector3(1.5, 0.75, 0.0), Vector3(0.2, 1.5, 4.0))
	await _verify_chair(STOOL, "维修圆凳", Vector3(1.28, 0.26, 1.24), failures)
	await _verify_chair(CHAIR, "战术指挥椅", Vector3(1.26, 0.23, 1.24), failures)
	await _verify_blocker_tracks_chair(STOOL, "维修圆凳", failures)
	await _verify_blocker_tracks_chair(CHAIR, "战术指挥椅", failures)
	await _verify_player_pushes_chair(failures)
	await _verify_seated_chair(STOOL, "维修圆凳", failures)
	await _verify_seated_chair(CHAIR, "战术指挥椅", failures)
	await _verify_tip_recovery(STOOL, "维修圆凳", failures)
	await _verify_tip_recovery(CHAIR, "战术指挥椅", failures)
	await _verify_dismount_motion_profile(failures)
	if failures.is_empty():
		print("PUSHABLE_BASE_CHAIRS_OK: 两把椅子分体旋转/滑行，乘坐1.3倍步速，松手惯性与离座防弹射通过")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_chair(scene: PackedScene, label: String, expected_shape_size: Vector3, failures: Array[String]) -> void:
	var chair := scene.instantiate() as RigidBody3D
	_check(chair != null, "%s不是RigidBody3D" % label, failures)
	if chair == null:
		return
	chair.position = Vector3.ZERO
	add_child(chair)
	await _settle(4)
	var collider := chair.get_node_or_null("WorldCollision") as CollisionShape3D
	_check(collider != null and collider.shape is BoxShape3D, "%s缺少实体碰撞盒" % label, failures)
	if collider != null and collider.shape is BoxShape3D:
		_check((collider.shape as BoxShape3D).size.is_equal_approx(expected_shape_size), "%s碰撞尺寸不符合契约" % label, failures)
	_check(chair.collision_layer == 1 and chair.collision_mask == 1, "%s未接入场景碰撞层" % label, failures)
	_check(chair.is_in_group("pushable_furniture"), "%s未登记为可推动家具" % label, failures)
	_check(chair.get_node_or_null("SwivelPivot") != null, "%s缺少独立旋转上部" % label, failures)
	var start_x := chair.global_position.x
	# 以远高于实际角色推力的冲量验证连续碰撞：即使高速撞墙也不能穿透。
	chair.apply_central_impulse(Vector3(chair.mass * 10.0, 0.0, 0.0))
	await _settle(5)
	var pushed_x := chair.global_position.x
	await _settle(55)
	_check(pushed_x > start_x + 0.02, "%s未响应平面推力" % label, failures)
	_check(chair.global_position.x < 1.15, "%s穿过了场景阻挡墙" % label, failures)
	_check(absf(chair.global_position.y) < 0.08, "%s没有被场景地面承托" % label, failures)
	chair.queue_free()
	await get_tree().physics_frame


func _add_static_box(label: String, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	add_child(body)


func _verify_blocker_tracks_chair(scene: PackedScene, label: String, failures: Array[String]) -> void:
	var chair := scene.instantiate() as PushableSeat3D
	chair.max_push_speed = 8.0
	chair.position = Vector3(-2.0, 0.0, -2.0)
	add_child(chair)
	await _settle(5)
	var old_position := chair.global_position
	chair.apply_central_impulse(Vector3(chair.mass * 9.0, 0.0, 0.0))
	await _settle(22)
	_check(chair.global_position.distance_to(old_position) > 1.5, "%s碰撞同步测试中没有离开原位: %s -> %s" % [label, old_position, chair.global_position], failures)
	var old_ray := PhysicsRayQueryParameters3D.create(old_position + Vector3.UP * 1.5, old_position + Vector3.UP * 0.05, 16)
	var new_ray := PhysicsRayQueryParameters3D.create(chair.global_position + Vector3.UP * 1.5, chair.global_position + Vector3.UP * 0.05, 16)
	var old_hit := chair.get_world_3d().direct_space_state.intersect_ray(old_ray)
	var new_hit := chair.get_world_3d().direct_space_state.intersect_ray(new_ray)
	_check(old_hit.is_empty(), "%s角色用碰撞体仍留在旧位置: %s" % [label, old_hit], failures)
	_check(new_hit.get("collider") == chair.get_node("PlayerBlocker"), "%s角色用碰撞体没有跟上移动后的椅子: %s" % [label, new_hit], failures)
	chair.queue_free()
	await get_tree().physics_frame


func _verify_player_pushes_chair(failures: Array[String]) -> void:
	var chair := CHAIR.instantiate() as RigidBody3D
	var player := PLAYER.instantiate() as Player3D
	_check(chair != null and player != null, "角色推椅验证场景未能实例化", failures)
	if chair == null or player == null:
		return
	chair.position = Vector3.ZERO
	player.position = Vector3(-1.8, 0.0, 0.0)
	add_child(chair)
	add_child(player)
	await _settle(6)
	var start_x := chair.global_position.x
	for _frame in 36:
		player.move_grounded(Vector3.RIGHT * player.get_move_speed(), 1.0 / 60.0, false)
		await get_tree().physics_frame
	_check(chair.global_position.x > start_x + 0.03, "角色碰撞没有推动维修圆凳", failures)
	_check(chair.global_position.x < 1.1, "角色推动的战术指挥椅穿过了场景墙", failures)
	player.queue_free()
	chair.queue_free()
	await get_tree().physics_frame


func _verify_seated_chair(scene: PackedScene, label: String, failures: Array[String]) -> void:
	var chair := scene.instantiate() as PushableSeat3D
	var player := PLAYER.instantiate() as Player3D
	chair.position = Vector3.ZERO
	player.position = Vector3(-1.0, 0.0, 0.0)
	add_child(chair)
	add_child(player)
	await _settle(8)
	var standing_camera_y := player.camera.global_position.y
	var standing_camera_local := player.camera.position
	var standing_layer := player.collision_layer
	var standing_mask := player.collision_mask
	var candidate := chair.get_interaction_candidate(player)
	_check(not candidate.is_empty(), "%s没有上座交互候选" % label, failures)
	_check(chair.perform_interaction(player, candidate), "%s无法乘坐" % label, failures)
	await _settle(10)
	_check(absf(player.camera.global_position.y - standing_camera_y) < 0.08, "%s上座后相机高度抬升" % label, failures)
	_check(player.get_state_machine_state() == "seated", "%s没有进入seated状态" % label, failures)
	_check(chair.rider == player, "%s未绑定乘客" % label, failures)
	_check(player.avatar.get_component_snapshot().get("authored_motion_clip", "") == "seated", "%s没有播放Blender坐姿" % label, failures)
	var left_foot := player.to_local(player.avatar.foot_l.global_position)
	var right_foot := player.to_local(player.avatar.foot_r.global_position)
	_check(left_foot.z < -0.2 and right_foot.z < -0.2, "%s坐姿双脚没有向前伸出" % label, failures)
	_check(player.equip_weapon("bp_pistol", "mod_bullet_standard"), "%s坐姿测试无法装备手枪" % label, failures)
	player.set_combat_enabled(true)
	var ammo_before := int(player.get_weapon_snapshot().get("current_ammo", 0))
	Input.action_press("shoot")
	await _settle(3)
	Input.action_release("shoot")
	_check(int(player.get_weapon_snapshot().get("current_ammo", 0)) < ammo_before, "%s坐姿时不能开枪" % label, failures)
	var initial_swivel_yaw := chair.swivel_pivot.rotation.y
	player._mobile_input_available = true
	player._mobile_face_active = true
	player._mobile_face_direction = Vector2.RIGHT
	await _settle(14)
	_check(absf(angle_difference(initial_swivel_yaw, chair.swivel_pivot.rotation.y)) > 0.4, "%s座面没有独立旋转" % label, failures)
	_check(absf(chair.rotation.y) < 0.2, "%s底座随座面一起转动" % label, failures)
	_check(absf(angle_difference(chair.global_rotation.y + chair.swivel_pivot.rotation.y, player.aim_yaw)) < 0.2, "%s座面没有跟随角色朝向" % label, failures)
	player._test_move_direction = Vector3.RIGHT
	await _settle(90)
	player._test_move_direction = null
	_check(chair.global_position.x > 0.08, "%s乘坐后未滑行" % label, failures)
	_check(chair.global_position.x < 1.15, "%s乘坐后穿过墙体" % label, failures)
	_check(player.global_position.distance_to(chair.get_seat_position()) < 0.15, "%s乘客没有跟随座椅" % label, failures)
	_check(chair.perform_interaction(player, chair.get_interaction_candidate(player)), "%s无法安全离开" % label, failures)
	_check(player.get_state_machine_state() != "seated" and chair.rider == null, "%s下座后状态未恢复" % label, failures)
	_check(player.collision_layer == standing_layer and player.collision_mask == standing_mask, "%s下座后玩家碰撞层未恢复" % label, failures)
	_check(player.virtual_collision_capsule != null and not player.virtual_collision_capsule.disabled, "%s下座后碰撞胶囊失效" % label, failures)
	_check(player.camera.position.is_equal_approx(standing_camera_local), "%s下座后相机局部位置未恢复" % label, failures)
	# Check the physical outcome, not only the collision bitmasks.
	for _frame in 40:
		player.move_grounded(Vector3.RIGHT * player.get_move_speed(), 1.0 / 60.0, false)
		await get_tree().physics_frame
	_check(player.global_position.x < 1.25, "%s下座后穿过场景阻挡墙" % label, failures)
	player.queue_free()
	chair.queue_free()
	await get_tree().physics_frame


func _verify_dismount_motion_profile(failures: Array[String]) -> void:
	var chair := CHAIR.instantiate() as PushableSeat3D
	var player := PLAYER.instantiate() as Player3D
	chair.scale = Vector3.ONE * 0.7 # 99F 实景实例比例
	chair.position = Vector3(0.0, 0.0, 3.0)
	player.position = Vector3(-1.0, 0.0, 3.0)
	add_child(chair)
	add_child(player)
	await _settle(8)
	_check(player.try_mount_chair(chair), "0.7比例座椅无法上座", failures)
	_check(is_equal_approx(chair.get_ride_speed(), player.get_move_speed() * 1.3), "乘坐速度不是步速1.3倍", failures)
	player._test_move_direction = Vector3.RIGHT
	await _settle(32)
	var powered_speed := Vector2(chair.linear_velocity.x, chair.linear_velocity.z).length()
	_check(powered_speed > player.get_move_speed(), "乘坐加速后没有快过步行", failures)
	_check(powered_speed <= chair.get_ride_speed() + 0.12, "乘坐超过1.3倍限速", failures)
	player._test_move_direction = Vector3.ZERO
	var coast_start := chair.global_position.x
	await _settle(15)
	var coast_speed := Vector2(chair.linear_velocity.x, chair.linear_velocity.z).length()
	_check(chair.global_position.x > coast_start + 0.15, "松开输入后没有惯性滑行", failures)
	_check(coast_speed < powered_speed * 0.7, "松开输入后没有减速", failures)
	_check(player.try_dismount_chair(), "滑行后无法下座", failures)
	_check(Vector2(chair.linear_velocity.x, chair.linear_velocity.z).length() <= 0.36, "下座瞬间椅子没有刹住", failures)
	player._test_move_direction = Vector3.LEFT
	var peak_speed := 0.0
	var peak_height := 0.0
	for _frame in 45:
		await get_tree().physics_frame
		peak_speed = maxf(peak_speed, Vector2(chair.linear_velocity.x, chair.linear_velocity.z).length())
		peak_height = maxf(peak_height, chair.global_position.y)
	_check(peak_speed <= chair.max_push_speed + 0.1, "下座后椅子被弹飞", failures)
	_check(peak_height < 0.2, "下座后椅子向上弹飞", failures)
	player.queue_free()
	chair.queue_free()
	await get_tree().physics_frame


func _verify_tip_recovery(scene: PackedScene, label: String, failures: Array[String]) -> void:
	var chair := scene.instantiate() as PushableSeat3D
	var player := PLAYER.instantiate() as Player3D
	chair.position = Vector3(-2.0, 0.0, 2.0)
	player.position = Vector3(-3.0, 0.0, 2.0)
	add_child(chair)
	add_child(player)
	await _settle(8)
	var standing_layer := player.collision_layer
	var standing_mask := player.collision_mask
	_check(player.try_mount_chair(chair), "%s倾斜测试无法上座" % label, failures)
	chair.rotation.x = deg_to_rad(44.0)
	_check(not chair.is_tipped(), "%s不足45度时过早判定倾斜" % label, failures)
	chair.rotation.x = deg_to_rad(46.0)
	_check(chair.is_tipped(), "%s超过45度仍未判定倾斜" % label, failures)
	player._tick_seated(1.0 / 60.0)
	_check(chair.rider == null and player.get_state_machine_state() != "seated", "%s倾斜后没有主动离座" % label, failures)
	_check(player.collision_layer == standing_layer and player.collision_mask == standing_mask, "%s倾斜离座后角色碰撞未恢复" % label, failures)
	_check(not player.try_mount_chair(chair), "%s倾斜状态仍允许直接坐上" % label, failures)
	player.global_position = chair.global_position + Vector3(-1.1, 0.0, 0.0)
	var candidate := chair.get_interaction_candidate(player)
	_check(candidate.get("interaction_id") == "right_seat", "%s倾斜后没有扶正交互" % label, failures)
	_check(chair.perform_interaction(player, candidate), "%s再次交互未能扶正" % label, failures)
	await _settle(3)
	_check(not chair.is_tipped(), "%s扶正后仍然倾斜" % label, failures)
	_check(chair.get_interaction_candidate(player).get("interaction_id") == "sit_on_seat", "%s扶正后不能重新坐上" % label, failures)
	player.queue_free()
	chair.queue_free()
	await get_tree().physics_frame


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().physics_frame


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
