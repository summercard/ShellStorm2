extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AudioManager.CATALOG_PATH))
	var report: Dictionary = AudioManager.validate_sound_library()
	_verify_world_style_policy(catalog, failures)
	if report.asset_count != 166 or report.sound_set_count != 108 or not report.missing.is_empty():
		failures.append("Library coverage or resource presence failed")
	for asset in catalog.assets:
		var stream := load(str(asset.runtime_path)) as AudioStreamOggVorbis
		if stream == null or absf(stream.get_length() - float(asset.duration_sec)) > 0.025:
			failures.append("OGG decode/duration failed: %s" % asset.runtime_path)
	for legacy in AudioManager.SFX:
		if str(AudioManager.SFX[legacy]) != str(AudioManager.get_sound_set(str(legacy)).paths[0]):
			failures.append("Legacy first variant mismatch: %s" % legacy)
	for key in ["pistol_fire", "melee_swing", "enemy_hit"]:
		var paths: Array[String] = []
		for i in range(4):
			AudioManager.play_sfx(key)
			paths.append(str(AudioManager.get_feedback_debug_snapshot().last_request.path))
		if paths[0] == paths[1] or paths[1] == paths[2] or paths[0] != paths[3]:
			failures.append("Deterministic variant rotation failed: %s" % key)
	AudioManager.emit_event("combat.weapon.fire", {"weapon_audio_profile": "laser"})
	if AudioManager.get_feedback_debug_snapshot().last_request.event != "laser_fire":
		failures.append("Explicit energy weapon identity failed")
	await get_tree().process_frame
	await _verify_gun_identity_routes(catalog, failures)
	AudioManager.stop_all_sfx()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await _verify_gunfire_mix(catalog, failures)
		var source := Node3D.new()
		add_child(source)
		var loop := AudioManager.emit_event("amb.expedition_room", {"source_node": source})
		if loop == null or not loop.stream.loop or loop.get_parent() != source:
			failures.append("Loop stream or scene ownership failed")
		if AudioManager.emit_event("amb.expedition_room", {"source_node": source}) != loop:
			failures.append("Loop deduplication failed")
		var shot := AudioManager.emit_event("combat.weapon.fire", {"weapon_audio_profile": "pistol", "source_node": source})
		if not shot is AudioStreamPlayer3D:
			failures.append("World point source did not use 3D playback")
		elif shot.bus != "Gunfire":
			failures.append("Gunshot bypassed independent mix control")
		get_tree().paused = true
		var ui := AudioManager.emit_event("ui.action.confirm")
		if ui == null or ui.process_mode != Node.PROCESS_MODE_ALWAYS:
			failures.append("Paused UI playback not enabled")
		get_tree().paused = false
		for i in range(60):
			AudioManager.play_sfx("rifle_fire")
		if AudioManager._voices.size() > AudioManager.MAX_TOTAL_VOICES:
			failures.append("Concurrency budget exceeded")
		source.queue_free()
		await get_tree().process_frame
		if is_instance_valid(loop) or is_instance_valid(shot):
			failures.append("Scene-owned sounds survived source teardown")
		AudioManager.stop_all_sfx()
		await get_tree().process_frame
		if not AudioManager._voices.is_empty():
			failures.append("Playback nodes leaked after explicit stop")
	AudioManager.reset_feedback_debug()
	if failures.is_empty():
		print("AUDIO_LIBRARY_FLOW_OK: 166 OGGs, 108 sets, 9 gun IDs / 7 families, 51 natural world sets, 9 ambient loops, preserved system/weapon hashes; mode=", DisplayServer.get_name())
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_gunfire_mix(catalog: Dictionary, failures: Array[String]) -> void:
	var gun_bus := AudioServer.get_bus_index("Gunfire")
	if AudioServer.get_bus_send(gun_bus) != "WorldSFX" or AudioServer.get_bus_volume_db(gun_bus) > -5.9:
		failures.append("Gunfire mix lost gain or room acoustics routing")
	for profile in catalog.weapon_profiles.values():
		if str(catalog.sound_sets[profile.fire].bus) != "Gunfire":
			failures.append("Gun family bypasses gunfire mix")
	var world_bus := AudioServer.get_bus_index("WorldSFX")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(world_bus, capture)
	var cursor_state: Dictionary = AudioManager._variant_cursors.duplicate()
	var peaks: Array[float] = []
	for adjusted in [false, true]:
		AudioServer.set_bus_volume_db(gun_bus, AudioManager.GUNFIRE_GAIN_DB if adjusted else 0.0)
		AudioServer.set_bus_effect_enabled(gun_bus, 0, adjusted)
		AudioManager._variant_cursors = cursor_state.duplicate()
		AudioManager.stop_all_sfx()
		await get_tree().create_timer(.2).timeout
		capture.clear_buffer()
		for _burst in range(6):
			for key in ["pistol_fire", "rifle_fire", "smg_fire", "shotgun_fire", "sniper_fire", "launcher_fire", "laser_fire"]:
				AudioManager.play_sfx(key)
			await get_tree().create_timer(.06).timeout
		await get_tree().create_timer(.9).timeout
		var samples := capture.get_buffer(capture.get_frames_available())
		var peak := 0.0
		for sample in samples:
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		peaks.append(peak)
	AudioServer.remove_bus_effect(world_bus, AudioServer.get_bus_effect_count(world_bus) - 1)
	AudioManager.stop_all_sfx()
	print("GUNFIRE_MIX_PEAK: previous=", peaks[0], " adjusted=", peaks[1])
	if peaks[0] <= 0.0 or peaks[1] <= 0.0 or peaks[1] >= peaks[0] * .6 or peaks[1] >= .9:
		failures.append("Actual stacked gunfire output was not reduced safely")
	await get_tree().process_frame


func _verify_gun_identity_routes(catalog: Dictionary, failures: Array[String]) -> void:
	# These are the actual shipped gun bodies, including starter aliases.
	var expected := {
		"bp_pistol": "pistol", "bp_rifle": "rifle", "bp_starter_rifle": "rifle",
		"bp_machinegun": "machinegun", "bp_sprinkler": "machinegun",
		"bp_shotgun": "shotgun", "bp_sniper": "sniper",
		"bp_launcher": "launcher", "bp_charge": "charge",
	}
	var fire_keys := {"pistol": "pistol_fire", "rifle": "rifle_fire", "machinegun": "smg_fire", "shotgun": "shotgun_fire", "sniper": "sniper_fire", "launcher": "launcher_fire", "charge": "laser_fire"}
	var actor := Node3D.new()
	add_child(actor)
	var weapon := WeaponModel3D.new()
	actor.add_child(weapon)
	weapon.set_process(false)
	var projectiles: Array[Node] = []
	weapon.projectile_spawned.connect(func(projectile): projectiles.append(projectile))
	for gun in expected:
		var family: String = expected[gun]
		weapon.gun_id = gun
		# Every gun receives an extreme fire-rate and multi-pellet build. Audio must
		# still follow body identity, covering the former SMG/shotgun misrouting.
		weapon.fire_rate = 30.0
		weapon.projectile_count = 6
		weapon.current_ammo = 12
		weapon.magazine_size = 12
		weapon._cooldown = 0.0
		if not weapon._fire_now(Vector3.FORWARD, actor, 1.0):
			failures.append("Test gun could not fire: " + gun)
		if str(AudioManager.get_feedback_debug_snapshot().last_request.event) != fire_keys[family]:
			failures.append("Combat stats overrode gun identity: " + gun)
		if not weapon.request_reload():
			failures.append("Test gun could not reload: " + gun)
		if str(AudioManager.get_feedback_debug_snapshot().last_request.event) != "reload_" + family:
			failures.append("Reload identity mismatch: " + gun)
		weapon.cancel_reload()
		# Exercise the accepted world-pickup owner, not just a direct audio call.
		var pickup := GroundLootPickup3D.new()
		pickup.item_data = {"type": "weapon", "assembly_id": gun}
		add_child(pickup)
		pickup.accept_pickup(actor)
		if str(AudioManager.get_feedback_debug_snapshot().last_request.event) != "pickup_" + family:
			failures.append("World pickup identity mismatch: " + gun)
		pickup.queue_free()
		weapon.set_process(false)
	# Alternate fire can emit only the mounted gun. The primary must stay silent.
	weapon.gun_id = "bp_pistol"
	weapon._cooldown = 0.0
	weapon.current_ammo = 12
	weapon._fire_sequence = 1
	weapon._projectile_behavior = {"alternate_fire": true}
	weapon._secondary_guns = [{"mount_id": "absent", "follow_probability": 1.0}]
	AudioManager.reset_feedback_debug()
	weapon._fire_now(Vector3.FORWARD, actor, 1.0)
	if not (AudioManager.get_feedback_debug_snapshot().request_counts as Dictionary).is_empty():
		failures.append("Alternate fire emitted a phantom primary gun sound")
	for action in ["fire", "reload", "pickup"]:
		var event_id: String = {"fire": "combat.weapon.fire", "reload": "combat.weapon.reload_start", "pickup": "world.pickup.item"}[action]
		AudioManager.emit_event(event_id, {"gun_id": "bp_launcher"})
		if str(AudioManager.get_feedback_debug_snapshot().last_request.event) != ("launcher_fire" if action == "fire" else action + "_launcher"):
			failures.append("Semantic event ignored explicit gun identity: " + action)
	# Class families must have distinct recordings, not just renamed paths.
	for action in ["fire", "reload", "pickup"]:
		var seen: Array[String] = []
		for family in fire_keys:
			var key: String = fire_keys[family] if action == "fire" else action + "_" + family
			var paths: Array = AudioManager.get_sound_set(key).get("paths", [])
			if paths.is_empty():
				failures.append("Missing family sound set: " + key)
				continue
			for asset in catalog.assets:
				if asset.runtime_path == paths[0]:
					if str(asset.sha256) in seen:
						failures.append("Families share identical audio: " + key)
					seen.append(str(asset.sha256))
	AudioManager.play_pickup_sfx({"type": "weapon", "id": "weapon_sniper"})
	if str(AudioManager.get_feedback_debug_snapshot().last_request.event) != "pickup_sniper":
		failures.append("Content-ID-only pickup did not resolve canonical gun")
	AudioManager.play_pickup_sfx({"type": "consumable"})
	if str(AudioManager.get_feedback_debug_snapshot().last_request.event) != "item_pickup":
		failures.append("Ordinary pickup routing changed")
	if not AudioManager.get_weapon_sound_set("unknown_gun", "fire").is_empty():
		failures.append("Unknown gun silently inferred a class")
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	actor.queue_free()
	AudioManager.stop_all_sfx()
	await get_tree().process_frame


func _verify_world_style_policy(catalog: Dictionary, failures: Array[String]) -> void:
	var policy: Dictionary = catalog.get("world_style_policy", {})
	if int(policy.get("changed_assets", 0)) != 93:
		failures.append("Natural world replacement coverage missing")
	var world: Array = policy.get("natural_world_sets", [])
	var systems: Array = policy.get("system_sets", [])
	var weapons: Array = policy.get("weapon_sets", [])
	if world.size() != 51 or systems.size() != 29 or weapons.size() != 28:
		failures.append("World/system/weapon style coverage changed")
	var seen: Array[String] = []
	for group in [world, systems, weapons]:
		for key in group:
			if str(key) in seen or not catalog.sound_sets.has(key):
				failures.append("Style policy overlap or unregistered set: " + str(key))
			seen.append(str(key))
	if seen.size() != catalog.sound_sets.size():
		failures.append("Unclassified sound set bypasses style policy")
	var changed := 0
	var loops := 0
	for asset in catalog.assets:
		if str(asset.key) in world:
			changed += 1
			if str(asset.get("production_revision", "")) not in ["natural-world-r5", "world-environment-r6"] or not str(asset.get("source_method", "")).begins_with("Sourced recordings"):
				failures.append("World sound still uses legacy tone synthesis: " + str(asset.asset_id))
			if str(asset.key).begins_with("amb_"):
				loops += 1
				if not bool(asset.loop) or not bool(catalog.sound_sets[asset.key].loop):
					failures.append("Ambient asset lost loop ownership: " + str(asset.key))
		else:
			var original := str((policy.get("preserved_asset_hashes", {}) as Dictionary).get(asset.asset_id, ""))
			if original.is_empty() or original != str(asset.sha256):
				failures.append("Preserved system or weapon sound changed: " + str(asset.asset_id))
	if changed != 93 or loops != 9:
		failures.append("Natural recordings or ambient beds are incomplete")
