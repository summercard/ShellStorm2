extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const EPSILON := 0.0001


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	add_child(player)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.camera.current = false
	await get_tree().process_frame

	var base_avatar_scale := player.avatar.scale
	var base_collision_position := player.virtual_collision_capsule.position
	var capsule := player.virtual_collision_capsule.shape as CapsuleShape3D
	var base_radius := capsule.radius
	var base_height := capsule.height
	var base_camera_transform := player.camera.transform
	var base_root_scale := player.scale
	if not base_avatar_scale.is_equal_approx(Vector3.ONE * Player3D.DEFAULT_BASE_SIZE_MULTIPLIER):
		failures.append("Player default 100% is not based on the new 70% authored size")
	if not is_equal_approx(float(player.get_debug_scale_snapshot().get("base_size_multiplier", 0.0)), 0.70):
		failures.append("Player debug snapshot does not expose the 70% base-size contract")
	var emitted_snapshots: Array[Dictionary] = []
	player.debug_scale_changed.connect(func(snapshot: Dictionary) -> void:
		emitted_snapshots.append(snapshot)
	)

	player.adjust_debug_scale(1)
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 1.10, failures)
	player.adjust_debug_scale(1)
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 1.20, failures)
	if not is_equal_approx(float(player.get_debug_scale_snapshot().get("scale_ratio", 0.0)), 1.20):
		failures.append("Two + presses were not additive from base (expected 120%, not 121%)")

	var minus_event := InputEventKey.new()
	minus_event.pressed = true
	minus_event.unicode = 45
	player._unhandled_input(minus_event)
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 1.10, failures)

	var plus_event := InputEventKey.new()
	plus_event.pressed = true
	plus_event.unicode = 43
	player._unhandled_input(plus_event)
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 1.20, failures)

	var echo_event := InputEventKey.new()
	echo_event.pressed = true
	echo_event.echo = true
	echo_event.unicode = 43
	player._unhandled_input(echo_event)
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 1.20, failures)

	player.set_debug_scale_step(-99)
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 0.10, failures)
	player.set_debug_scale_step(99)
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 3.00, failures)
	player.reset_debug_scale()
	_assert_scale(player, base_avatar_scale, base_collision_position, base_radius, base_height, 1.00, failures)

	if not player.camera.transform.is_equal_approx(base_camera_transform):
		failures.append("Camera transform changed with debug character size")
	if not player.scale.is_equal_approx(base_root_scale):
		failures.append("Player root scale changed; camera/flashlight would be scaled accidentally")
	if emitted_snapshots.size() != 7:
		failures.append("Expected 7 non-echo scale change signals, got %d" % emitted_snapshots.size())

	if failures.is_empty():
		print("PLAYER3D_DEBUG_SCALE_FLOW_OK: base=70% additive=100/110/120 collision_synced=true bounds=10..300 camera_unchanged=true")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _assert_scale(
	player: Player3D,
	base_avatar_scale: Vector3,
	base_collision_position: Vector3,
	base_radius: float,
	base_height: float,
	expected_ratio: float,
	failures: Array[String]
) -> void:
	var capsule := player.virtual_collision_capsule.shape as CapsuleShape3D
	if not player.avatar.scale.is_equal_approx(base_avatar_scale * expected_ratio):
		failures.append("Avatar scale mismatch at %.0f%%" % (expected_ratio * 100.0))
	if not player.virtual_collision_capsule.position.is_equal_approx(base_collision_position * expected_ratio):
		failures.append("Collision center mismatch at %.0f%%" % (expected_ratio * 100.0))
	if absf(capsule.radius - base_radius * expected_ratio) > EPSILON:
		failures.append("Collision radius mismatch at %.0f%%" % (expected_ratio * 100.0))
	if absf(capsule.height - base_height * expected_ratio) > EPSILON:
		failures.append("Collision height mismatch at %.0f%%" % (expected_ratio * 100.0))
