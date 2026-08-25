extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const FULL_VISUAL_HEIGHT_M := 1.05
const COLLISION_HEIGHT_M := 1.05
const EXPECTED_FIRE_STYLES := {
	"bp_pistol": "sidearm_snap",
	"bp_shotgun": "shotgun_heavy_pump",
	"bp_rifle": "rifle_braced_burst",
	"bp_machinegun": "machinegun_rattle",
	"bp_sniper": "sniper_long_recoil",
	"bp_launcher": "launcher_body_push",
	"bp_charge": "charge_release",
}


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.get_node("Camera3D").current = false

	var collision := player.get_node_or_null("VirtualCollisionCapsule") as CollisionShape3D
	if collision == null or not collision.shape is CapsuleShape3D:
		failures.append("Player gameplay collision is not the required invisible CapsuleShape3D")
	else:
		var capsule := collision.shape as CapsuleShape3D
		var collision_top := collision.position.y + capsule.height * 0.5
		if not is_equal_approx(capsule.height, COLLISION_HEIGHT_M):
			failures.append("Virtual collision capsule height is not the new 1.05 m base")
		if not is_equal_approx(collision_top, FULL_VISUAL_HEIGHT_M):
			failures.append("Virtual collision capsule top does not match the full 1.05 m visual height")
		if capsule.radius * 2.0 >= 0.75:
			failures.append("Virtual collision capsule is not tighter than the visible head silhouette")
	var avatar_snapshot := player.avatar.get_component_snapshot()
	if (
		int(avatar_snapshot.get("model_collision_shape_count", -1)) != 0
		or int(avatar_snapshot.get("model_collision_object_count", -1)) != 0
	):
		failures.append("A collision node was found inside the visual/model hierarchy")
	if collision != null and not collision.find_children("*", "MeshInstance3D", true, false).is_empty():
		failures.append("Virtual collision capsule unexpectedly contains visible render geometry")

	var wall := StaticBody3D.new()
	wall.name = "CollisionProbeWall"
	wall.position = Vector3(0.0, 0.5, -1.2)
	var wall_shape_node := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2.0, 2.0, 0.2)
	wall_shape_node.shape = wall_shape
	wall.add_child(wall_shape_node)
	add_child(wall)
	await get_tree().physics_frame
	var wall_contact := player.move_and_collide(Vector3(0.0, 0.0, -1.5))
	if wall_contact == null or wall_contact.get_collider() != wall:
		failures.append("Invisible virtual capsule did not produce a real gameplay wall collision")
	player.global_position = Vector3.ZERO

	_set_presentation_state(player, "idle")
	_advance_avatar(player, 0.10, 3)
	var sidearm_hold := player.avatar.get_component_snapshot()
	if str(sidearm_hold.get("weapon_pose_state", "")) != "sidearm_hold":
		failures.append("Default pistol did not enter sidearm_hold")
	if int(sidearm_hold.get("active_grip_hand_count", 0)) != 1:
		failures.append("Pistol pose does not use exactly one gripping hand")
	if float(sidearm_hold.get("weapon_socket_position", Vector3.ZERO).x) < 0.060:
		failures.append("Pistol socket is not staged on the rabbit's right side")
	var sidearm_socket_position := sidearm_hold.get("weapon_socket_position", Vector3.ZERO) as Vector3
	if sidearm_socket_position.y > 0.27 or sidearm_socket_position.z > -0.33:
		failures.append("Pistol idle hold is not lowered and extended clear of the rabbit's face")
	var sidearm_socket_rotation := sidearm_hold.get("weapon_socket_rotation", Vector3.ZERO) as Vector3
	if sidearm_socket_rotation.length() > 0.03:
		failures.append("Pistol idle barrel is not aligned to the real aim direction")
	_check_muzzle_alignment(player, "idle", failures)
	var sidearm_left_position := sidearm_hold.get("hand_l_position", Vector3.ZERO) as Vector3
	if sidearm_left_position.z > -0.24:
		failures.append("Free left hand is not extended into the sidearm ready silhouette")
	if float(sidearm_hold.get("hand_r_to_socket_global_distance", 999.0)) > 0.001:
		failures.append("Pistol HandJointR is not exactly seated on GripSocket")
	if float(sidearm_hold.get("right_hand_ring_to_joint_global_distance", 999.0)) > 0.001:
		failures.append("Right cuff-ring center is not seated on HandJointR")
	if float(sidearm_hold.get("right_hand_ring_to_grip_global_distance", 999.0)) > 0.001:
		failures.append("Right cuff-ring center is not seated on GripSocket")
	if (
		float(sidearm_hold.get("hand_r_to_socket_global_distance", 999.0))
		>= float(sidearm_hold.get("hand_l_to_socket_global_distance", 0.0))
	):
		failures.append("Pistol right hand is not closer to the weapon than the free left hand")
	var sidearm_right_rotation := sidearm_hold.get("hand_r_rotation", Vector3.ZERO) as Vector3
	if sidearm_right_rotation.y < 1.0 or str(sidearm_hold.get("right_hand_pivot_contract", "")) != "cuff_ring_center_is_HandJointR_and_GripSocket":
		failures.append("Right hand does not use the cuff-ring/HandJointR/GripSocket pivot contract")

	_set_presentation_state(player, "moving")
	_advance_avatar(player, 0.10, 2)
	var sidearm_run := player.avatar.get_component_snapshot()
	if str(sidearm_run.get("weapon_pose_state", "")) != "sidearm_run":
		failures.append("Pistol locomotion did not enter the independent sidearm_run state")
	if (
		(sidearm_run.get("hand_l_position", Vector3.ZERO) as Vector3)
		.distance_to(sidearm_hold.get("hand_l_position", Vector3.ZERO) as Vector3) < 0.016
	):
		failures.append("Free left hand lacks the sidearm running counter-swing")

	player.call("_on_weapon_shot_fired", 1)
	player.call("_tick_action_overlays", 0.04)
	_advance_avatar(player, 0.04, 1)
	var sidearm_fire := player.avatar.get_component_snapshot()
	if str(sidearm_fire.get("weapon_pose_state", "")) != "sidearm_fire":
		failures.append("Pistol fire did not override running with sidearm_fire")
	if str(sidearm_fire.get("weapon_fire_style", "")) != "sidearm_snap":
		failures.append("Pistol did not select its weapon-specific fire style")
	var sidearm_fire_rotation := sidearm_fire.get("action_rotation", Vector3.ZERO) as Vector3
	player.weapon.set("_recoil", 0.09)
	player.weapon.call("_process", 0.001)
	_check_muzzle_alignment(player, "firing recoil", failures)

	player.call("_clear_action_overlays")
	_set_presentation_state(player, "idle")
	if not player.equip_weapon("bp_rifle", "mod_bullet_standard"):
		failures.append("Could not equip rifle for two-hand pose verification")
	await get_tree().process_frame
	_advance_avatar(player, 0.10, 3)
	var longgun_hold := player.avatar.get_component_snapshot()
	if str(longgun_hold.get("weapon_pose_state", "")) != "longgun_hold":
		failures.append("Rifle did not enter longgun_hold")
	if int(longgun_hold.get("active_grip_hand_count", 0)) != 2:
		failures.append("Rifle pose does not use right grip plus left support")
	if float(longgun_hold.get("hand_r_to_socket_global_distance", 999.0)) > 0.001:
		failures.append("Rifle HandJointR is not exactly seated on GripSocket")
	var longgun_left_rotation := longgun_hold.get("hand_l_rotation", Vector3.ZERO) as Vector3
	var longgun_right_rotation := longgun_hold.get("hand_r_rotation", Vector3.ZERO) as Vector3
	if longgun_left_rotation.y > -1.0 or longgun_right_rotation.y < 1.0:
		failures.append("Longgun hand rotations do not face both palms toward -Z")

	_set_presentation_state(player, "moving")
	_advance_avatar(player, 0.10, 2)
	var longgun_run := player.avatar.get_component_snapshot()
	if str(longgun_run.get("weapon_pose_state", "")) != "longgun_run":
		failures.append("Rifle locomotion did not enter the independent longgun_run state")

	player.call("_on_weapon_shot_fired", 1)
	player.call("_tick_action_overlays", 0.04)
	_advance_avatar(player, 0.04, 1)
	var longgun_fire := player.avatar.get_component_snapshot()
	if str(longgun_fire.get("weapon_pose_state", "")) != "longgun_fire":
		failures.append("Rifle fire did not override running with longgun_fire")
	if str(longgun_fire.get("weapon_fire_style", "")) != "rifle_braced_burst":
		failures.append("Rifle did not select its weapon-specific fire style")
	var longgun_fire_rotation := longgun_fire.get("action_rotation", Vector3.ZERO) as Vector3
	if sidearm_fire_rotation.distance_to(longgun_fire_rotation) < 0.08:
		failures.append("Pistol and rifle fire key poses are not sufficiently distinct")
	if int(longgun_fire.get("weapon_pose_transition_count", 0)) < 6:
		failures.append("Weapon pose state transitions were not recorded by the state machine")

	var fire_styles_seen: Dictionary = {}
	var fire_signatures_seen: Dictionary = {}
	for gun_id in EXPECTED_FIRE_STYLES:
		player.call("_clear_action_overlays")
		_set_presentation_state(player, "idle")
		if not player.equip_weapon(gun_id, "mod_bullet_standard"):
			failures.append("Could not equip %s for the seven-gun animation profile check" % gun_id)
			continue
		await get_tree().process_frame
		_advance_avatar(player, 0.10, 1)
		var hold_snapshot := player.avatar.get_component_snapshot()
		var expected_grip_count := 1 if gun_id == "bp_pistol" else 2
		if int(hold_snapshot.get("active_grip_hand_count", 0)) != expected_grip_count:
			failures.append("%s selected the wrong one/two-hand grip class" % gun_id)
		player.call("_on_weapon_shot_fired", 1)
		player.call("_tick_action_overlays", 0.04)
		_advance_avatar(player, 0.04, 1)
		var fire_snapshot := player.avatar.get_component_snapshot()
		var fire_style := str(fire_snapshot.get("weapon_fire_style", ""))
		if fire_style != str(EXPECTED_FIRE_STYLES[gun_id]):
			failures.append("%s selected the wrong fire style" % gun_id)
		fire_styles_seen[fire_style] = true
		var fire_rotation := fire_snapshot.get("action_rotation", Vector3.ZERO) as Vector3
		var fire_offset := fire_snapshot.get("action_offset", Vector3.ZERO) as Vector3
		fire_signatures_seen["%.3f/%.3f/%.3f" % [fire_rotation.x, fire_rotation.z, fire_offset.z]] = true
	if fire_styles_seen.size() != EXPECTED_FIRE_STYLES.size() or fire_signatures_seen.size() != EXPECTED_FIRE_STYLES.size():
		failures.append("The seven gun bodies do not all resolve to distinct named and keyed fire actions")

	player.queue_free()
	wall.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BUNNY_WEAPON_POSE_COLLISION_OK: cuff-ring/HandJointR/GripSocket alignment, one/two-hand FSM, distinct gun fire, and unified 1.05 m runtime visual/collision contract pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _set_presentation_state(player: Player3D, state_id: String) -> void:
	player.call("_set_presentation_state", state_id)


func _advance_avatar(player: Player3D, delta: float, steps: int) -> void:
	for _index in range(steps):
		player.avatar.call("_process", delta)


func _check_muzzle_alignment(player: Player3D, context: String, failures: Array[String]) -> void:
	var muzzle := player.weapon.find_child("MuzzleSocket", true, false) as Node3D
	if muzzle == null:
		failures.append("Pistol %s has no MuzzleSocket" % context)
		return
	var muzzle_forward := -muzzle.global_basis.z
	muzzle_forward.y = 0.0
	var projectile_direction := player.aim_direction
	projectile_direction.y = 0.0
	if muzzle_forward.length_squared() <= 0.000001 or projectile_direction.length_squared() <= 0.000001:
		failures.append("Pistol %s has an invalid muzzle/aim vector" % context)
		return
	var angle_degrees := rad_to_deg(muzzle_forward.normalized().angle_to(projectile_direction.normalized()))
	if angle_degrees > 0.5:
		failures.append("Pistol %s muzzle differs from projectile direction by %.3f degrees" % [context, angle_degrees])
