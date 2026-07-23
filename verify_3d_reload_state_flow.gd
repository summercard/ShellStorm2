extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.combat_enabled = true
	add_child(player)
	await get_tree().process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.weapon.set_process(false)

	var progress_samples: Array[float] = []
	var ended_results: Array[bool] = []
	player.reload_progress_changed.connect(func(progress: float, _remaining: float): progress_samples.append(progress))
	player.reload_ended.connect(func(completed: bool): ended_results.append(completed))

	player.avatar.call("_process", 0.2)
	var base_avatar := player.avatar.get_component_snapshot()
	var base_hand_socket_offset := base_avatar.get("hand_socket_offset", Vector3.ZERO) as Vector3
	var magazine_size := player.weapon.magazine_size
	player.weapon.current_ammo = maxi(0, magazine_size - 4)
	if not player.weapon.request_reload():
		failures.append("A non-full 3D weapon cannot enter reload")
	player.avatar.call("_process", 0.05)
	var state_snapshot := player.get_state_machine_snapshot()
	var reload_snapshot := player.get_reload_snapshot()
	var avatar_snapshot := player.avatar.get_component_snapshot()
	if not bool((state_snapshot.get("overlays", {}) as Dictionary).get("reloading", false)):
		failures.append("Reload is not exposed as a state-machine overlay")
	if str(state_snapshot.get("current", "")) != "idle" or int((state_snapshot.get("states", []) as Array).size()) != 6:
		failures.append("Reload replaced or expanded the six top-level player states")
	if not bool(avatar_snapshot.get("reload_bar_visible", false)) or float(avatar_snapshot.get("reload_fill_scale_x", -1.0)) != 0.0:
		failures.append("Head-top reload bar is not visible at zero progress")
	if (
		not bool(avatar_snapshot.get("reload_bar_outside_visual_root", false))
		or not bool(avatar_snapshot.get("reload_bar_billboarded", false))
	):
		failures.append("Reload bar rotates with the aim VisualRoot instead of remaining camera-facing")

	var machine := player.get("_state_machine") as StateMachine
	machine.transition_to("moving")
	player.velocity = Vector3(4.0, 0.0, 0.0)
	var reload_duration := float(reload_snapshot.get("duration", player.weapon.reload_time))
	var ammo_before_blocked_fire := player.weapon.current_ammo
	if player.weapon.try_fire(Vector3.FORWARD, player) or player.weapon.current_ammo != ammo_before_blocked_fire:
		failures.append("Reloading weapon can still fire")
	player.weapon.call("_process", reload_duration * 0.5)
	player.avatar.call("_process", 0.2)
	state_snapshot = player.get_state_machine_snapshot()
	reload_snapshot = player.get_reload_snapshot()
	avatar_snapshot = player.avatar.get_component_snapshot()
	var mid_progress := float(reload_snapshot.get("progress", 0.0))
	if str(state_snapshot.get("current", "")) != "moving" or not bool((state_snapshot.get("overlays", {}) as Dictionary).get("reloading", false)):
		failures.append("Reload overlay does not coexist with moving")
	if mid_progress < 0.48 or mid_progress > 0.52:
		failures.append("Reload progress is not driven by the real weapon timer: %.3f" % mid_progress)
	if absf(float(avatar_snapshot.get("reload_fill_scale_x", 0.0)) - mid_progress) > 0.01:
		failures.append("Head-top bar fill does not match weapon reload progress")
	if (avatar_snapshot.get("reload_offset", Vector3.ZERO) as Vector3).length() < 0.08:
		failures.append("Reload overlay has no readable hand/weapon displacement")
	if (avatar_snapshot.get("reload_rotation", Vector3.ZERO) as Vector3).length() < 0.12:
		failures.append("Reload overlay has no readable hand/weapon rotation")
	var mid_hand_socket_offset := avatar_snapshot.get("hand_socket_offset", Vector3.ZERO) as Vector3
	if mid_hand_socket_offset.distance_to(base_hand_socket_offset) > 0.001:
		failures.append("Reload animation detached the one hand from the weapon socket")

	player.weapon.call("_process", reload_duration)
	player.avatar.call("_process", 0.2)
	state_snapshot = player.get_state_machine_snapshot()
	avatar_snapshot = player.avatar.get_component_snapshot()
	if bool((state_snapshot.get("overlays", {}) as Dictionary).get("reloading", true)):
		failures.append("Completed reload left the state-machine overlay active")
	if bool(avatar_snapshot.get("reload_bar_visible", true)):
		failures.append("Completed reload left the head-top bar visible")
	if player.weapon.current_ammo != magazine_size:
		failures.append("Completed reload did not refill the magazine")
	if ended_results != [true]:
		failures.append("Normal reload did not emit exactly one completed lifecycle event")
	if progress_samples.is_empty() or progress_samples.front() != 0.0 or progress_samples.back() != 1.0:
		failures.append("Reload progress lifecycle does not run from zero to one")
	else:
		for index in range(1, progress_samples.size()):
			if progress_samples[index] + 0.0001 < progress_samples[index - 1]:
				failures.append("Reload progress regressed before normal completion")
				break

	progress_samples.clear()
	player.weapon.current_ammo = maxi(0, magazine_size - 2)
	player.weapon.request_reload()
	player.weapon.call("_process", reload_duration * 0.25)
	if not player.refill_ammo():
		failures.append("Instant ammo refill failed during reload")
	player.avatar.call("_process", 0.2)
	if player.is_reloading() or bool(player.avatar.get_component_snapshot().get("reload_bar_visible", true)):
		failures.append("Ammo refill did not cancel the reload overlay and bar")
	if ended_results != [true, false]:
		failures.append("Cancelled reload did not publish a distinct incomplete lifecycle event")

	player.weapon.current_ammo = maxi(0, magazine_size - 3)
	player.weapon.request_reload()
	if not player.equip_weapon("bp_shotgun", "mod_bullet_standard"):
		failures.append("Cannot swap gun body during reload acceptance")
	player.avatar.call("_process", 0.2)
	var swapped_weapon := player.get_weapon_snapshot()
	if (
		player.is_reloading()
		or str(swapped_weapon.get("gun_id", "")) != "bp_shotgun"
		or int(swapped_weapon.get("current_ammo", 0)) != int(swapped_weapon.get("magazine_size", -1))
		or bool(player.avatar.get_component_snapshot().get("reload_bar_visible", true))
	):
		failures.append("Weapon swap did not atomically cancel old reload state and initialize the new gun")
	if ended_results != [true, false, false]:
		failures.append("Weapon swap did not close the previous reload lifecycle exactly once")

	player.weapon.current_ammo = maxi(0, player.weapon.magazine_size - 1)
	player.weapon.request_reload()
	player.take_damage(player.max_hp + 1)
	player.avatar.call("_process", 0.2)
	if (
		player.get_state_machine_state() != "dead"
		or player.is_reloading()
		or bool(player.avatar.get_component_snapshot().get("reload_bar_visible", true))
	):
		failures.append("Death did not cancel reload and hide the head-top bar")
	if ended_results != [true, false, false, false]:
		failures.append("Death did not close the reload lifecycle exactly once")

	player.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("3D_RELOAD_STATE_FLOW_OK: reload overlay, real timer, one-hand animation, head-top progress bar, completion and cancellation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
