extends Node3D

const PLAYER := preload("res://scenes/Player3D.tscn")
const CONTROLLER := preload("res://src/audio/WorldAudioEnvironment3D.gd")
const CONTEXT := preload("res://src/audio/WorldAudioContext3D.gd")
const FAN := preload("res://assets/art/environments/rooftop_courtyard_3d/runtime/desk_fan/prp_desk_fan_root_top3d.tscn")
const VENT := preload("res://assets/art/environments/tower_zones/rooftop/runtime/hvac_vent.tscn")
var failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	var floor_body := _box("Floor", Vector3(30, 0.2, 30), Vector3(0, -0.1, 0))
	floor_body.set_meta("audio_environment", "rooftop")
	var player := PLAYER.instantiate() as Player3D
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.03, 0)
	var controller := CONTROLLER.new()
	add_child(controller)
	controller.configure(self, player)
	controller.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rooftop: Dictionary = CONTEXT.resolve(player, controller.profiles)
	_check(rooftop.environment == "rooftop", "Open rooftop did not select wind/outdoor context")
	controller.apply_context(rooftop)
	controller._wind_remaining = 0.0
	controller._update_wind(3.0)
	_check(controller.get_snapshot().outside and is_equal_approx(controller.get_snapshot().wind_level_db, -10.0), "Rooftop gust did not use reduced gain")
	if DisplayServer.get_name() != "headless":
		_check(controller._wind.bus == "OutdoorWind", "Wind bypassed softened outdoor mix")
	controller._wind_remaining = 0.0
	controller._update_wind(3.0)
	_check(controller.get_snapshot().wind_level_db <= -79.0 and not controller._wind_active, "Outdoor wind has no quiet interval")
	controller.play_outdoor_bird()
	_check(controller.get_snapshot().birds == 1, "Outdoor birds not emitted")
	var roof := _box("IndoorRoof", Vector3(20, 0.2, 20), Vector3(0, 4, 0))
	await get_tree().physics_frame
	var indoor: Dictionary = CONTEXT.resolve(player, controller.profiles)
	_check(indoor.environment == "indoor", "Actual roof did not suppress outdoor audio")
	controller.apply_context(indoor)
	controller._update_wind(3.0)
	controller.play_outdoor_bird()
	_check(not controller.get_snapshot().outside and controller.get_snapshot().wind_level_db <= -79, "Indoor wind did not fade out")
	_check(controller.get_snapshot().birds == 1, "Birds played indoors")
	roof.collision_layer = 0
	floor_body.set_meta("audio_environment", "indoor")
	await get_tree().physics_frame
	_check(CONTEXT.resolve(player, controller.profiles).environment == "indoor", "Roofless indoor declaration leaked wind/birds")
	floor_body.remove_meta("audio_environment")
	_check(CONTEXT.resolve(player, controller.profiles).environment == "indoor", "Unknown cutaway interior was inferred outdoors")
	roof.collision_layer = 1
	floor_body.set_meta("audio_environment", "rooftop")
	await get_tree().physics_frame
	for surface in ["concrete", "metal", "debris", "wood"]:
		floor_body.set_meta("audio_surface", surface)
		var support: Dictionary = CONTEXT.resolve(player, controller.profiles)
		controller.play_footstep(support)
		_check(str(AudioManager.get_feedback_debug_snapshot().last_request.event) == "footstep_" + surface, "Wrong physical support material: " + surface)
		if DisplayServer.get_name() != "headless":
			var voice: Node = AudioManager._voices[-1]
			_check(voice is AudioStreamPlayer3D and voice.bus == "WorldSFX", "Footstep did not use physical 3D audio bus")
	# Exercise actual locomotion trigger, including its standing/airborne gates.
	for _i in range(4):
		player.velocity = Vector3.DOWN * 2
		player.move_and_slide()
	var count := int(controller.get_snapshot().footsteps)
	player.velocity = Vector3.ZERO
	player._tick_footstep_sound(1.0)
	_check(int(controller.get_snapshot().footsteps) == count, "Standing emitted a footstep")
	player.velocity = Vector3(3, 0, 0)
	player._tick_footstep_sound(0.56)
	_check(int(controller.get_snapshot().footsteps) == count + 1, "Grounded player movement did not emit audible footstep")
	player.is_dashing = true
	player._tick_footstep_sound(1.0)
	_check(int(controller.get_snapshot().footsteps) == count + 1, "Dash also emitted an ordinary footstep")
	player.is_dashing = false
	player.global_position.y = 3.0
	player.velocity = Vector3.UP
	player.move_and_slide()
	player.velocity = Vector3(3, 0, 0)
	player._tick_footstep_sound(1.0)
	_check(int(controller.get_snapshot().footsteps) == count + 1, "Airborne player emitted a footstep")
	player.global_position = Vector3(0, .03, 0)
	floor_body.set_meta("audio_acoustics", "stairwell")
	var stairs: Dictionary = CONTEXT.resolve(player, controller.profiles)
	controller.apply_context(stairs)
	AudioManager._process(1.0)
	_check(AudioManager.get_world_acoustic_snapshot().profile == "stairwell" and AudioManager.get_world_acoustic_snapshot().wet >= .23, "Stairwell reverb not applied")
	AudioManager.play_sfx("ui_click")
	if DisplayServer.get_name() != "headless":
		_check(AudioManager._voices[-1].bus == "UI", "UI was routed through the stairwell echo")
	var fan := FAN.instantiate() as Node3D
	fan.position = Vector3(2, 0, 0)
	add_child(fan)
	var vent := VENT.instantiate() as Node3D
	vent.position = Vector3(-2, 0, 0)
	add_child(vent)
	controller.update_devices()
	_check(controller.get_snapshot().devices_active == 2, "Actual fan/vent prefabs did not register positional loops")
	if DisplayServer.get_name() != "headless":
		_check(fan.find_children("*", "AudioStreamPlayer3D", false, false).size() == 1, "Fan loop is not owned by real device")
	var obstruction := _box("EquipmentOccluder", Vector3(.2, 2, 2), Vector3(1, .8, 0))
	await get_tree().physics_frame
	controller.update_devices()
	if DisplayServer.get_name() != "headless":
		var fan_voice := fan.find_children("*", "AudioStreamPlayer3D", false, false)[0] as AudioStreamPlayer3D
		_check(fan_voice.attenuation_filter_cutoff_hz <= 1500 and fan_voice.volume_db <= -15, "Equipment wall did not attenuate/filter sound")
	obstruction.queue_free()
	await get_tree().physics_frame
	player.global_position.y = 10
	controller.update_devices()
	_check(controller.get_snapshot().devices_active == 0, "Equipment bled into another floor")
	player.global_position.y = .03
	player.global_position.x = 60
	controller.update_devices()
	_check(controller.get_snapshot().devices_active == 0, "Distant equipment still running in listener budget")
	player.global_position.x = 0
	fan.hide()
	controller.update_devices()
	_check(controller.get_snapshot().devices_active == 1, "Hidden/streamed-out fan retained sound")
	fan.show()
	fan.set_meta("audio_enabled", false)
	controller.update_devices()
	_check(controller.get_snapshot().devices_active == 1, "Disabled equipment retained sound")
	fan.queue_free()
	await get_tree().process_frame
	controller.update_devices()
	_check(controller.get_snapshot().devices_registered == 1, "Freed device remained registered")
	await _verify_switch()
	vent.hide()
	controller.update_devices()
	AudioManager.stop_all_sfx()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await _verify_echo_capture(controller)
	controller.apply_context({"environment": "indoor", "reverb": "dry"})
	AudioManager._process(1.0)
	_check(AudioManager.get_world_acoustic_snapshot().wet == 0.0, "Leaving stairs retained reverb")
	controller.queue_free()
	player.queue_free()
	vent.queue_free()
	floor_body.queue_free()
	roof.queue_free()
	await get_tree().process_frame
	AudioManager.stop_all_sfx()
	AudioManager.reset_feedback_debug()
	_check(AudioManager.get_world_acoustic_snapshot().profile == "dry", "Scene teardown retained room acoustics")
	await _verify_formal_tower()
	if failures.is_empty():
		print("WORLD_ENVIRONMENT_AUDIO_OK: rooftop/indoor, 4 floor surfaces, actual player step gates, bird intervals, real fan/blower props, switch ownership, stair echo/UI separation, unload cleanup; mode=", DisplayServer.get_name())
	else:
		for message in failures:
			push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_formal_tower() -> void:
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var controller := tower.get_node_or_null("WorldAudioEnvironment") as WorldAudioEnvironment3D
	_check(controller != null, "Formal tower did not install world audio controller")
	if controller != null:
		var context := CONTEXT.resolve(tower.player, controller.profiles)
		print("WORLD_AUDIO_FORMAL_TOWER: ", context, " devices=", controller.get_snapshot().devices_registered)
		_check(str(context.environment) != "void", "Formal player has no audio support collider")
		_check(controller.actor == tower.player, "Formal audio listener does not follow actual player")
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all_sfx()
	_check(AudioManager.get_world_acoustic_snapshot().profile == "dry", "Formal tower unload retained echo")


func _verify_switch() -> void:
	var light := WastelandLight3D.new()
	add_child(light)
	var control := RoomLightSwitch3D.new()
	add_child(control)
	AudioManager.reset_feedback_debug()
	control.configure(light, false)
	control.set_light_on(true)
	_check((AudioManager.get_feedback_debug_snapshot().request_counts as Dictionary).is_empty(), "Light initialization/save restore made switch sounds")
	control.toggle_light()
	_check(str(AudioManager.get_feedback_debug_snapshot().last_request.event) == "light_off", "Successful switch-off lacked mechanical click")
	control.toggle_light()
	_check(str(AudioManager.get_feedback_debug_snapshot().last_request.event) == "light_on", "Successful switch-on lacked mechanical click")
	control.configure(null)
	AudioManager.reset_feedback_debug()
	_check(not control.toggle_light(), "Unbound light switch accepted operation")
	_check((AudioManager.get_feedback_debug_snapshot().request_counts as Dictionary).is_empty(), "Failed switch operation produced click")
	control.queue_free()
	light.queue_free()
	await get_tree().process_frame


func _verify_echo_capture(controller: Node3D) -> void:
	var bus := AudioServer.get_bus_index("WorldSFX")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(bus, capture)
	var energies: Array[float] = []
	for profile in ["dry", "stairwell"]:
		controller.apply_context({"environment": "indoor", "reverb": profile})
		AudioManager._process(1.0)
		capture.clear_buffer()
		AudioManager.play_sfx("footstep_concrete")
		await get_tree().create_timer(1.0).timeout
		var frames := capture.get_frames_available()
		_check(frames > 10000, "Audio device produced no frames for native echo verification")
		var data := capture.get_buffer(frames)
		var energy := 0.0
		for i in range(int(data.size() * .75), data.size()):
			energy += data[i].length_squared()
		energies.append(energy)
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	print("WORLD_AUDIO_ECHO_TAIL_ENERGY: dry=", energies[0], " stairs=", energies[1])
	_check(energies[1] > maxf(energies[0] * 2.0, 0.000000001), "Native stairwell playback has no reverb tail")


func _box(label: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = pos
	return body


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
