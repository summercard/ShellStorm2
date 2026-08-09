extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.get_node("Camera3D").current = false

	var socket := player.avatar.get_lower_body_socket()
	var expected_path := "VisualRoot/BunnyRig/BodyJoint/LowerBodySocket"
	if socket == null:
		failures.append("LowerBodySocket is missing")
	elif str(player.avatar.get_path_to(socket)) != expected_path:
		failures.append("LowerBodySocket is not parented under the Bunny BodyJoint")
	else:
		if socket.position.distance_to(Vector3(0.0, 0.14, 0.0)) > 0.0001:
			failures.append("LowerBodySocket is not at the approved lower-waist pivot")
		if str(socket.get_meta("attachment_slot", "")) != "lower_body":
			failures.append("LowerBodySocket lacks its semantic attachment metadata")
		var skirt_probe := Node3D.new()
		skirt_probe.name = "SkirtAttachmentProbe"
		socket.add_child(skirt_probe)
		var baseline := skirt_probe.global_transform
		player.call("_set_presentation_state", "moving")
		player.velocity = Vector3(player.get_move_speed(), 0.0, 0.0)
		player.avatar.call("_process", 0.16)
		if skirt_probe.global_transform.is_equal_approx(baseline):
			failures.append("A lower-body attachment does not inherit BodyJoint motion")
		if skirt_probe.get_parent() != socket:
			failures.append("Lower-body attachment escaped its socket")

	var snapshot := player.avatar.get_component_snapshot()
	if not bool(snapshot.get("has_lower_body_socket", false)):
		failures.append("Component diagnostics do not expose LowerBodySocket")
	if not bool(snapshot.get("lower_body_socket_parent_is_body", false)):
		failures.append("Component diagnostics do not confirm the body-local socket contract")

	player.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PLAYER3D_LOWER_BODY_SOCKET_OK: body-local lower-waist socket and skirt attachment inheritance pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
