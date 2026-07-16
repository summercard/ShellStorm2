extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var player_scene := load("res://scenes/Player.tscn") as PackedScene
	var ui_scene := load("res://scenes/GameUIManager.tscn") as PackedScene
	if player_scene == null or ui_scene == null:
		_finish(["Player or GameUIManager scene does not load"])
		return

	var player := player_scene.instantiate() as Player
	var ui := ui_scene.instantiate() as GameUIManager
	add_child(player)
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	player.set_physics_process(false)
	ui.set_player(player)

	var low_health_events: Array[bool] = []
	var presentation_events: Array[String] = []
	player.low_health_changed.connect(func(active: bool, _ratio: float) -> void: low_health_events.append(active))
	player.presentation_state_changed.connect(func(state_id: String, _context: Dictionary) -> void: presentation_events.append(state_id))

	var registered := player.get_registered_player_states()
	for required_state in ["idle", "moving", "dashing", "hurt", "locked", "dead"]:
		if not registered.has(required_state):
			failures.append("Player state machine does not register %s" % required_state)
	_expect_state(player, ui, "idle", failures)

	var state_machine := player.get("_state_machine") as StateMachine
	state_machine.transition_to("moving")
	await get_tree().process_frame
	_expect_state(player, ui, "moving", failures)
	_expect_renderer_state(player, "moving", failures)

	player.set_input_locked(true)
	await get_tree().process_frame
	_expect_state(player, ui, "locked", failures)
	if player.velocity != Vector2.ZERO:
		failures.append("Locked state does not stop player movement")
	player.set_input_locked(false)
	await get_tree().process_frame
	_expect_state(player, ui, "idle", failures)

	player.set_physics_process(true)
	player.dash_cooldown_timer = 0.0
	if not bool(player.call("_begin_dash")):
		failures.append("Ready player cannot enter dash state")
	else:
		_expect_state(player, ui, "dashing", failures)
		if not player.is_invincible or not player.is_dashing:
			failures.append("Dash does not enable movement and invincibility flags")
	for _i in 11:
		await get_tree().physics_frame
	if player.get_state_machine_state() != "idle" or player.is_dashing:
		failures.append("Dash does not resolve back to locomotion after its duration")
	if not player.is_invincible:
		failures.append("Dash exit clears invincibility before InvincibleTimer expires")
	for _i in 5:
		await get_tree().physics_frame
	if player.is_invincible:
		failures.append("Dash invincibility does not end after its independent timer")

	var hp_before := player.current_hp
	player.take_damage(10, Vector2.LEFT)
	if player.current_hp != hp_before - 10:
		failures.append("First valid hit does not change player HP")
	_expect_state(player, ui, "hurt", failures)
	var hp_after_first_hit := player.current_hp
	player.take_damage(10, Vector2.RIGHT)
	if player.current_hp != hp_after_first_hit:
		failures.append("Hurt invincibility does not reject an immediate second hit")
	await get_tree().create_timer(0.16).timeout
	if player.get_state_machine_state() == "hurt":
		failures.append("Hurt state does not recover after its 0.14 second presentation window")
	if not player.is_invincible:
		failures.append("Hurt recovery clears invincibility before the damage timer expires")
	await get_tree().create_timer(0.09).timeout
	if player.is_invincible:
		failures.append("Damage invincibility remains active beyond its contract")
	player.set_physics_process(false)

	player.take_damage(65)
	await get_tree().process_frame
	if not player.is_low_health() or low_health_events != [true]:
		failures.append("Crossing 30 percent HP does not emit one low-health entry")
	var low_snapshot := ui.get_player_state_widget_snapshot()
	if not bool(low_snapshot.get("low_health", false)) or not str(low_snapshot.get("status_text", "")).contains("CRITICAL"):
		failures.append("Low health is not represented by the semantic HUD panel")
	player.heal(20)
	await get_tree().process_frame
	if player.is_low_health() or low_health_events != [true, false]:
		failures.append("Healing above 30 percent does not emit one low-health exit")

	player.apply_silence(0.30)
	await get_tree().process_frame
	var jammed_snapshot := ui.get_player_state_widget_snapshot()
	if not bool(jammed_snapshot.get("silenced", false)) or not str(jammed_snapshot.get("status_text", "")).contains("JAMMED"):
		failures.append("Silence does not drive character/HUD jammed presentation")
	_expect_renderer_overlay(player, "silenced", true, failures)
	player.call("_handle_silence", 0.31)
	await get_tree().process_frame
	if bool(ui.get_player_state_widget_snapshot().get("silenced", true)):
		failures.append("Silence expiry does not clear the HUD overlay")

	player.current_hp = 10
	player.is_invincible = false
	player.take_damage(20)
	await get_tree().process_frame
	_expect_state(player, ui, "dead", failures)
	_expect_renderer_state(player, "dead", failures)
	if player.combat_enabled or player.get_node("Aim").visible or player.get_node("WeaponAnchor").visible:
		failures.append("Death does not immediately disable aim and weapon presentation")

	var state_rect: Rect2 = ui.get_player_state_widget_snapshot().get("rect", Rect2())
	var ammo_rect := (ui.get_node("GameHUD/AmmoPanel") as Control).get_global_rect()
	var minimap_rect := (ui.get_node("GameHUD/MiniMapPanel") as Control).get_global_rect()
	if state_rect.intersects(ammo_rect) or state_rect.intersects(minimap_rect):
		failures.append("Player state panel overlaps ammo or minimap HUD regions")
	var top_right := ui.get_node("GameHUD/TopRightPanel") as Control
	var top_right_vbox := ui.get_node("GameHUD/TopRightPanel/VBox") as VBoxContainer
	var hp_panel := ui.get_node("GameHUD/HPBarBG") as Control
	var wave_label := ui.get_node("GameHUD/TopRightPanel/VBox/WaveLabel") as Label
	if top_right_vbox.get_child_count() != 2:
		failures.append("Legacy outline duplicates still participate in the top-right HUD layout")
	if top_right.get_global_rect().intersects(hp_panel.get_global_rect()):
		failures.append("Top-right command panel overlaps the HP panel")
	if not top_right.get_global_rect().encloses(wave_label.get_global_rect()):
		failures.append("Depth readout is pushed outside the top-right command panel")
	for expected_event in ["moving", "locked", "idle", "dashing", "hurt", "dead"]:
		if not presentation_events.has(expected_event):
			failures.append("Presentation signal chain never exposed %s" % expected_event)

	ui.queue_free()
	player.queue_free()
	for flash in get_tree().root.find_children("DamageRedFlash", "ColorRect", true, false):
		flash.queue_free()
	var synth = AudioManager.get("_synth") if AudioManager != null else null
	if synth != null:
		var stream_player = synth.get("_stream_player")
		if stream_player is AudioStreamPlayer:
			stream_player.stop()
			stream_player.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	_finish(failures)


func _expect_state(player: Player, ui: GameUIManager, expected: String, failures: Array[String]) -> void:
	if player.get_state_machine_state() != expected or player.get_presentation_state() != expected:
		failures.append("Player logic/presentation state is not synchronized at %s" % expected)
	var snapshot := ui.get_player_state_widget_snapshot()
	if str(snapshot.get("state", "")) != expected:
		failures.append("HUD state panel did not synchronize to %s" % expected)


func _expect_renderer_state(player: Player, expected: String, failures: Array[String]) -> void:
	var renderer := player.get_node_or_null("Components/Body/AvatarRenderer") as PlayerAvatarRenderer
	if renderer == null:
		failures.append("Player has no semantic AvatarRenderer")
		return
	var snapshot := renderer.get_visual_state_snapshot()
	if str(snapshot.get("state", "")) != expected:
		failures.append("Player renderer did not synchronize to %s" % expected)


func _expect_renderer_overlay(player: Player, key: String, expected: bool, failures: Array[String]) -> void:
	var renderer := player.get_node_or_null("Components/Body/AvatarRenderer") as PlayerAvatarRenderer
	if renderer == null or bool(renderer.get_visual_state_snapshot().get(key, not expected)) != expected:
		failures.append("Player renderer overlay %s did not synchronize" % key)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PLAYER_PRESENTATION_FLOW_OK: six-state logic, independent invincibility, low-HP/silence overlays, death lockout, and semantic HUD synchronization")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
