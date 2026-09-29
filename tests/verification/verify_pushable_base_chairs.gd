extends Node

const STOOL := preload("res://assets/art/props/base_world_3d/runtime/workshop_stool/prp_base_workshop_stool_root_top3d.tscn")
const CHAIR := preload("res://assets/art/props/base_world_3d/runtime/mission_command_chair/prp_base_mission_command_chair_root_top3d.tscn")
const PLAYER := preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	_add_static_box("Floor", Vector3(0.0, -0.1, 0.0), Vector3(12.0, 0.2, 12.0))
	_add_static_box("StopWall", Vector3(1.5, 0.75, 0.0), Vector3(0.2, 1.5, 4.0))
	await _verify_chair(STOOL, "维修圆凳", Vector3(0.72, 0.72, 0.72), failures)
	await _verify_chair(CHAIR, "战术指挥椅", Vector3(0.78, 1.08, 0.82), failures)
	await _verify_player_pushes_chair(failures)
	if failures.is_empty():
		print("PUSHABLE_BASE_CHAIRS_OK: 两把椅子可受推力滑行，并被地面和场景墙体阻挡")
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
	var start_x := chair.global_position.x
	# 以远高于实际角色推力的冲量验证连续碰撞：即使高速撞墙也不能穿透。
	chair.apply_central_impulse(Vector3(chair.mass * 10.0, 0.0, 0.0))
	await _settle(5)
	var pushed_x := chair.global_position.x
	await _settle(55)
	_check(pushed_x > start_x + 0.02, "%s未响应平面推力" % label, failures)
	_check(chair.global_position.x < 1.35, "%s穿过了场景阻挡墙" % label, failures)
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
	_check(chair.global_position.x < 1.1, "角色推动的维修圆凳穿过了场景墙", failures)
	player.queue_free()
	chair.queue_free()
	await get_tree().physics_frame


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().physics_frame


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
