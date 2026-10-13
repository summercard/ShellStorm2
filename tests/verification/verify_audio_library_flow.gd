extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AudioManager.CATALOG_PATH))
	var report: Dictionary = AudioManager.validate_sound_library()
	if report.asset_count != 140 or report.sound_set_count != 89 or not report.missing.is_empty():
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
	AudioManager.stop_all_sfx()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
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
		print("AUDIO_LIBRARY_FLOW_OK: 140 OGGs, 89 sets, legacy replacement, variants, explicit weapon profile; mode=", DisplayServer.get_name())
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
