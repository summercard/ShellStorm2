extends Node

const GALLERY_SCENE: PackedScene = preload("res://scenes/Player3DStateGallery.tscn")
const REQUIRED_CONTROLS := [
	"StateIdle", "StateMoving", "StateDashing", "StateHurt", "StateLocked", "StateDead",
	"Reload", "LowHealth", "Invincible", "Silenced", "WeaponPistol", "WeaponShotgun", "WeaponRifle",
	"FireShot", "StartCharge", "ReleaseCharge", "Knockback",
	"SpawnEnemy", "SpawnBoss", "ToggleEnemyAI", "DamageEnemy", "EnemyIdle", "EnemyPatrol",
	"EnemyTelegraph", "EnemyAttack", "AdvanceBossPhase", "InteractNPC", "ResetPlayer",
]


func _ready() -> void:
	var failures: Array[String] = []
	var gallery := GALLERY_SCENE.instantiate() as Player3DStateGallery
	add_child(gallery)
	await get_tree().physics_frame
	await get_tree().process_frame

	var control_ids := gallery.get_control_ids()
	for control_id in REQUIRED_CONTROLS:
		if control_id not in control_ids:
			failures.append("Missing gallery control: %s" % control_id)
	var player_snapshot := gallery.get_preview_snapshot().get("player", {}) as Dictionary
	if int((player_snapshot.get("states", []) as Array).size()) != 6:
		failures.append("Gallery player does not expose exactly six top-level states")
	if str(player_snapshot.get("current", "")) != "idle":
		failures.append("Gallery player does not start in idle")

	gallery.run_player_action("moving")
	await get_tree().physics_frame
	player_snapshot = gallery.get_preview_snapshot().get("player", {}) as Dictionary
	if str(player_snapshot.get("current", "")) != "moving":
		failures.append("Moving button did not drive the real Player3D state machine")
	if not gallery.request_preview_reload():
		failures.append("Reload button cannot start the real weapon reload")
	await get_tree().process_frame
	player_snapshot = gallery.get_preview_snapshot().get("player", {}) as Dictionary
	var overlays := player_snapshot.get("overlays", {}) as Dictionary
	if not bool(overlays.get("reloading", false)) or int((player_snapshot.get("states", []) as Array).size()) != 6:
		failures.append("Reload is not a Player3D overlay in the gallery")
	if not gallery.request_preview_fire():
		failures.append("Fire button cannot drive the real weapon shot event")
	await get_tree().physics_frame
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	player_snapshot = gallery.get_preview_snapshot().get("player", {}) as Dictionary
	overlays = player_snapshot.get("overlays", {}) as Dictionary
	var firing_components := gallery.player.avatar.get_component_snapshot()
	if not bool(overlays.get("firing", false)) or not bool(firing_components.get("firing_animation_active", false)):
		failures.append("Weapon shot does not activate the player firing overlay")
	if (firing_components.get("action_rotation", Vector3.ZERO) as Vector3).length() <= 0.001:
		failures.append("Firing overlay does not produce a component recoil transform")
	if (
		str(firing_components.get("weapon_pose_state", "")) != "sidearm_fire"
		or int(firing_components.get("active_grip_hand_count", 0)) != 1
		or float(firing_components.get("hand_r_to_socket_global_distance", 999.0)) > 0.36
	):
		failures.append("Firing overlay does not preserve the pistol's single right grip")
	var charge_started := gallery.begin_preview_charge()
	if not charge_started:
		failures.append("Charge button cannot start the real charge weapon")
	await get_tree().physics_frame
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	player_snapshot = gallery.get_preview_snapshot().get("player", {}) as Dictionary
	overlays = player_snapshot.get("overlays", {}) as Dictionary
	if not bool(overlays.get("charging", false)) or not bool(gallery.player.avatar.get_component_snapshot().get("charging_animation_active", false)):
		failures.append("Charge weapon does not activate the player charging overlay")
	await get_tree().create_timer(0.18).timeout
	if not gallery.release_preview_charge():
		failures.append("Release charge button cannot complete the real charge weapon shot")
	if not gallery.request_preview_knockback():
		failures.append("Knockback button cannot activate player hurt response")
	await get_tree().physics_frame
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	player_snapshot = gallery.get_preview_snapshot().get("player", {}) as Dictionary
	overlays = player_snapshot.get("overlays", {}) as Dictionary
	var knockback_components := gallery.player.avatar.get_component_snapshot()
	if gallery.player.get_state_machine_state() != "hurt" or not bool(overlays.get("knockback", false)):
		failures.append("Knockback does not drive the real hurt state plus overlay")
	if not bool(knockback_components.get("knockback_animation_active", false)):
		failures.append("Knockback overlay does not reach the modular avatar")

	var enemy := gallery.spawn_enemy("ambusher")
	await get_tree().process_frame
	if enemy == null or enemy.enemy_kind != "ambusher" or not bool(enemy.get_state_snapshot().get("is_3d", false)):
		failures.append("Enemy selector did not create the real 3D enemy")
	if not gallery.set_enemy_state("telegraph") or enemy.ai_state != "telegraph":
		failures.append("Enemy state control did not drive Enemy3D")
	var boss := gallery.spawn_boss()
	await get_tree().process_frame
	if boss == null or boss.enemy_kind != "boss" or boss.max_hp < 500:
		failures.append("Boss control did not create the configured Boss Enemy3D")
	gallery.advance_boss_phase()
	if boss.boss_phase < 2:
		failures.append("Boss phase button did not use the real boss health-phase logic")

	var before_npc := gallery.active_npc.get_snapshot()
	gallery.select_npc(1)
	await get_tree().process_frame
	var npc_snapshot := gallery.active_npc.get_snapshot()
	if not bool(npc_snapshot.get("is_3d", false)) or str(npc_snapshot.get("npc_id", "")) == str(before_npc.get("npc_id", "")):
		failures.append("NPC selector did not configure a 3D NPC adapter")
	gallery.interact_with_npc()
	if not bool(gallery.active_npc.get_snapshot().get("dialogue_visible", false)):
		failures.append("NPC interaction button did not toggle dialogue")

	gallery.run_player_action("dead")
	await get_tree().physics_frame
	if gallery.player.get_state_machine_state() != "dead":
		failures.append("Dead button did not use Player3D terminal state")
	gallery.run_player_action("reset")
	await get_tree().process_frame
	if gallery.player.get_state_machine_state() != "idle" or gallery.player.current_hp != gallery.player.max_hp:
		failures.append("Reset player did not replace the terminal Player3D instance")

	gallery.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PLAYER3D_STATE_GALLERY_FLOW_OK: real six-state player, weapon action overlays, knockback, Enemy3D/Boss and NPC3D controls pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
