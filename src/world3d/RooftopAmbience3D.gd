class_name RooftopAmbience3D
extends Node3D
## Replay the authored Blender environment tracks together; no physics transforms.

var _animation_player: AnimationPlayer
var _practical_lights: Array[OmniLight3D] = []
var _track_count := 0

func _ready() -> void:
	_animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player != null:
		var combined := Animation.new()
		combined.length = 0.1
		for animation_name in _animation_player.get_animation_list():
			if animation_name == "RESET":
				continue
			var authored := _animation_player.get_animation(animation_name)
			combined.length = maxf(combined.length, authored.length)
			for track in range(authored.get_track_count()):
				authored.copy_track(track, combined)
		combined.loop_mode = Animation.LOOP_LINEAR
		_track_count = combined.get_track_count()
		if _track_count > 0:
			var library := AnimationLibrary.new()
			library.add_animation("living_rooftop", combined)
			_animation_player.add_animation_library("ambience", library)
			_animation_player.play("ambience/living_rooftop")
	# Real warm pools are attached to three existing bulbs. No new mesh or collider.
	for bulb_index in [1, 4, 7]:
		var bulb := find_child("聚落串灯_%d_自发光" % bulb_index, true, false) as Node3D
		if bulb == null:
			continue
		var light := OmniLight3D.new()
		light.name = "WarmPracticalLight"
		light.light_color = Color(1.0, 0.70, 0.39)
		light.omni_range = 9.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.light_cull_mask = 1
		light.distance_fade_enabled = true
		light.distance_fade_begin = 28.0
		light.distance_fade_length = 8.0
		bulb.add_child(light)
		_practical_lights.append(light)
	if GameTimeManager != null:
		GameTimeManager.minute_changed.connect(_refresh_practicals)
		_refresh_practicals(GameTimeManager.get_time_snapshot())
	visibility_changed.connect(_sync_activity)
	_sync_activity()

func _refresh_practicals(snapshot: Dictionary) -> void:
	var solar := snapshot.get("solar", {}) as Dictionary
	var daylight := float(solar.get("daylight_factor", 1.0))
	for light in _practical_lights:
		light.light_energy = lerpf(4.2, 0.12, daylight)

func _sync_activity() -> void:
	if _animation_player != null:
		_animation_player.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED

func get_presentation_snapshot() -> Dictionary:
	return {"authored_tracks": _track_count, "practical_lights": _practical_lights.size(), "active": is_visible_in_tree()}
