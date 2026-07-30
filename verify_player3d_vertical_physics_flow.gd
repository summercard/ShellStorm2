extends Node
## PH43 角色真实重力、下落/落地八态、斜坡静止与胶囊碰撞专项。

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var floor_body := _make_support(
		"LandingFloor",
		Vector3(0.0, -0.15, 0.0),
		Vector3(18.0, 0.30, 18.0),
		Vector3.ZERO
	)
	add_child(floor_body)
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(0.0, 4.0, 0.0)
	var observed_states: Array[String] = []
	player.presentation_state_changed.connect(
		func(state_id: String, _context: Dictionary):
			if state_id not in observed_states:
				observed_states.append(state_id)
	)
	add_child(player)
	await get_tree().process_frame

	var falling_snapshot: Dictionary = {}
	var landing_snapshot: Dictionary = {}
	for _frame in range(300):
		await get_tree().physics_frame
		await get_tree().process_frame
		var state := player.get_state_machine_state()
		if state == "falling" and falling_snapshot.is_empty():
			player.avatar.call("_process", 0.05)
			falling_snapshot = player.avatar.get_component_snapshot()
		if state == "landing" and landing_snapshot.is_empty():
			player.avatar.call("_process", 0.05)
			landing_snapshot = player.avatar.get_component_snapshot()
		if (
			"falling" in observed_states
			and "landing" in observed_states
			and state == "idle"
		):
			break
	if "falling" not in observed_states:
		failures.append("真实离地没有进入 falling 状态")
	if "landing" not in observed_states:
		failures.append("重新接触地面没有进入 landing 状态")
	if not bool(falling_snapshot.get("fall_animation_active", false)):
		failures.append("falling 状态没有驱动角色下落动作")
	if not bool(landing_snapshot.get("landing_animation_active", false)):
		failures.append("landing 状态没有驱动落地压缩动作")
	if absf(player.global_position.y) > 0.08 or not player.is_on_floor():
		failures.append("角色落地后没有稳定停在承重面")
	var vertical_snapshot := player.get_vertical_physics_snapshot()
	if (
		float(vertical_snapshot.get("impact_speed_mps", 0.0)) <= 2.0
		or float(vertical_snapshot.get("landing_duration_s", 0.0)) < 0.12
	):
		failures.append("落地冲击速度没有映射到合法停顿时长")
	if not is_zero_approx(player.get_grounded_velocity(Vector3.ZERO).y):
		failures.append("地面状态仍持续写入强制向下速度")

	# 20度坡面静止：没有输入时角色不得自行沿坡滑落。
	var slope := _make_support(
		"IdleSlope",
		Vector3(14.0, 1.0, 0.0),
		Vector3(8.0, 0.30, 4.0),
		Vector3(0.0, 0.0, deg_to_rad(20.0))
	)
	add_child(slope)
	await get_tree().physics_frame
	var slope_top := slope.global_position + slope.global_basis * Vector3.UP * 0.16
	player.global_position = slope_top + Vector3.UP * 0.04
	player.velocity = Vector3.ZERO
	player.set_test_move_direction(Vector3.ZERO)
	(player.get("_state_machine") as StateMachine).transition_to("idle", true)
	for _frame in range(12):
		await get_tree().physics_frame
	var settled_position := player.global_position
	for _frame in range(90):
		await get_tree().physics_frame
	var planar_drift := Vector2(
		player.global_position.x - settled_position.x,
		player.global_position.z - settled_position.z
	).length()
	if planar_drift > 0.08:
		failures.append("角色无输入站在斜坡上仍自动移动 %.3fm" % planar_drift)

	player.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PLAYER3D_VERTICAL_PHYSICS_OK: capsule support, falling, landing pause, animation and slope stop pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _make_support(
	node_name: String,
	position: Vector3,
	size: Vector3,
	rotation: Vector3
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation = rotation
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body
