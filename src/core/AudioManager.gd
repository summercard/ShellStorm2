extends Node

var master_bus: int = 0
var sfx_bus: int = 1
var music_bus: int = 2

var sfx_volume: float = 1.0
var music_volume: float = 0.8

# 正式音效资产。OGG Vorbis 是桌面与移动端共同的运行时主格式；WAV 只保留母版。
const SFX: Dictionary = {
	# 现有战斗/流程事件
	"pistol_fire": "res://src/assets/audio/sfx/pistol_fire_v004.ogg",
	"rifle_fire": "res://src/assets/audio/sfx/rifle_fire_v004.ogg",
	"shotgun_fire": "res://src/assets/audio/sfx/shotgun_fire_v004.ogg",
	"smg_fire": "res://src/assets/audio/sfx/smg_fire_v003.ogg",
	"sniper_fire": "res://src/assets/audio/sfx/sniper_fire_v004.ogg",
	"laser_fire": "res://src/assets/audio/sfx/laser_fire_v004.ogg",
	"enemy_hit": "res://src/assets/audio/sfx/enemy_hit_v003.ogg",
	"enemy_die": "res://src/assets/audio/sfx/enemy_die_v003.ogg",
	"player_hit": "res://src/assets/audio/sfx/player_hit_v003.ogg",
	"player_dash": "res://src/assets/audio/sfx/player_dash_v003.ogg",
	"reload": "res://src/assets/audio/sfx/reload_v003.ogg",
	"crit_hit": "res://src/assets/audio/sfx/crit_hit_v003.ogg",
	"melee_swing": "res://src/assets/audio/sfx/melee_swing_v003.ogg",
	"melee_impact": "res://src/assets/audio/sfx/melee_impact_v003.ogg",
	"fate_card": "res://src/assets/audio/sfx/fate_card_v002.ogg",
	"extraction_start": "res://src/assets/audio/sfx/extraction_start_v002.ogg",
	"extraction_done": "res://src/assets/audio/sfx/extraction_done_v002.ogg",
	"extraction_abort": "res://src/assets/audio/sfx/extraction_abort_v002.ogg",

	# 已正式接入的扩展事件（所有权见《音效接入说明.md》）
	"ui_hover": "res://src/assets/audio/sfx/ui_hover_v002.ogg",
	"ui_click": "res://src/assets/audio/sfx/ui_click_v002.ogg",
	"ui_error": "res://src/assets/audio/sfx/ui_error_v002.ogg",
	"ammo_empty": "res://src/assets/audio/sfx/ammo_empty_v003.ogg",
	"item_pickup": "res://src/assets/audio/sfx/item_pickup_v003.ogg",
	"soul_pickup": "res://src/assets/audio/sfx/soul_pickup_v002.ogg",
	"door_open": "res://src/assets/audio/sfx/door_open_v003.ogg",
	"door_locked": "res://src/assets/audio/sfx/door_locked_v003.ogg",
	"container_open": "res://src/assets/audio/sfx/container_open_v003.ogg",
	"wave_start": "res://src/assets/audio/sfx/wave_start_v002.ogg",
	"wave_clear": "res://src/assets/audio/sfx/wave_clear_v002.ogg",
	"boss_intro": "res://src/assets/audio/sfx/boss_intro_v002.ogg",
	"boss_phase": "res://src/assets/audio/sfx/boss_phase_v002.ogg",
	"boss_defeat": "res://src/assets/audio/sfx/boss_defeat_v002.ogg",
	"merchant_purchase": "res://src/assets/audio/sfx/merchant_purchase_v002.ogg",

	# 手电筒电量事件：44.1kHz OGG 运行资产，WAV仅保留为可追溯母版。
	"flashlight_charge_up": "res://src/assets/audio/sfx/flashlight_charge_up_v002.ogg",
	"flashlight_low_battery": "res://src/assets/audio/sfx/flashlight_low_battery_v002.ogg",
	"flashlight_depleted": "res://src/assets/audio/sfx/flashlight_depleted_v002.ogg",
}

# 缓存已加载的 AudioStream，避免自动武器连续射击时重复加载资源。
var _stream_cache: Dictionary = {}
var _reported_missing_assets: Dictionary = {}
var _feedback_request_counts: Dictionary = {}
var _last_feedback_request: Dictionary = {}
var _catalog: Dictionary = {}
var _variant_cursors: Dictionary = {}
var _voices: Array[Node] = []
var _world_reverb: AudioEffectReverb
var _world_delay: AudioEffectDelay
var _world_acoustic_owner := 0
var _world_acoustic_profile := "dry"
var _world_wet_target := 0.0

const CATALOG_PATH := "res://src/assets/audio/sfx/sfx_catalog.json"
const MAX_TOTAL_VOICES := 40
const GUNFIRE_GAIN_DB := -6.0

func _ready() -> void:
	load_audio_settings()
	_load_catalog()
	# New buses inherit SFX so existing SFX volume/mute remains effective.
	for bus_name in ["SFX", "UI", "Ambience", "WorldSFX", "Gunfire", "OutdoorWind"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master" if bus_name == "SFX" else "SFX")
	# Keep gun identity intact while reducing the initial blast and stacked fire.
	var gunfire_bus := AudioServer.get_bus_index("Gunfire")
	AudioServer.set_bus_send(gunfire_bus, "WorldSFX")
	AudioServer.set_bus_volume_db(gunfire_bus, GUNFIRE_GAIN_DB)
	var gunfire_compressor := AudioEffectCompressor.new()
	gunfire_compressor.threshold = -14.0
	gunfire_compressor.ratio = 3.0
	gunfire_compressor.attack_us = 200.0
	gunfire_compressor.release_ms = 80.0
	gunfire_compressor.gain = 0.0
	AudioServer.add_bus_effect(gunfire_bus, gunfire_compressor)
	var wind_bus := AudioServer.get_bus_index("OutdoorWind")
	AudioServer.set_bus_send(wind_bus, "Ambience")
	var wind_highpass := AudioEffectHighPassFilter.new()
	wind_highpass.cutoff_hz = 120.0
	wind_highpass.resonance = 0.5
	AudioServer.add_bus_effect(wind_bus, wind_highpass)
	var wind_lowpass := AudioEffectLowPassFilter.new()
	wind_lowpass.cutoff_hz = 1800.0
	wind_lowpass.resonance = 0.5
	AudioServer.add_bus_effect(wind_bus, wind_lowpass)
	var world_bus := AudioServer.get_bus_index("WorldSFX")
	_world_reverb = AudioEffectReverb.new()
	_world_reverb.room_size = 0.72
	_world_reverb.damping = 0.55
	_world_reverb.predelay_msec = 35.0
	_world_reverb.wet = 0.0
	_world_reverb.dry = 1.0
	AudioServer.add_bus_effect(world_bus, _world_reverb)
	_world_delay = AudioEffectDelay.new()
	_world_delay.tap1_delay_ms = 125.0
	_world_delay.tap1_level_db = -60.0
	_world_delay.tap1_active = false
	_world_delay.tap2_active = false
	_world_delay.feedback_active = false
	AudioServer.add_bus_effect(world_bus, _world_delay)


func _process(delta: float) -> void:
	if _world_reverb == null:
		return
	_world_reverb.wet = move_toward(_world_reverb.wet, _world_wet_target, delta * 0.6)
	_world_delay.tap1_active = _world_reverb.wet > 0.001
	_world_delay.tap1_level_db = lerpf(-60.0, -18.0, clampf(_world_reverb.wet / 0.24, 0.0, 1.0))


func set_world_acoustics(profile: String, owner: Node) -> void:
	_world_acoustic_owner = owner.get_instance_id()
	_world_acoustic_profile = "stairwell" if profile == "stairwell" else "dry"
	_world_wet_target = 0.24 if _world_acoustic_profile == "stairwell" else 0.0


func release_world_acoustics(owner: Node) -> void:
	if owner.get_instance_id() != _world_acoustic_owner:
		return
	_world_acoustic_owner = 0
	_world_acoustic_profile = "dry"
	_world_wet_target = 0.0
	if _world_reverb != null:
		_world_reverb.wet = 0.0
		_world_delay.tap1_active = false


func get_world_acoustic_snapshot() -> Dictionary:
	return {"profile": _world_acoustic_profile, "wet": _world_reverb.wet if _world_reverb != null else 0.0, "target_wet": _world_wet_target, "world_bus": "WorldSFX", "ui_bus": "UI"}


func play_world_loop(key: String, source: Node3D, context: Dictionary = {}) -> Node:
	var request := context.duplicate()
	request.source_node = source
	return _play_sound_set(key, float(request.get("volume_db", 0.0)), 1.0, request)


func play_world_one_shot(key: String, source: Node3D, context: Dictionary = {}) -> Node:
	var request := context.duplicate()
	request.source_node = source
	return _play_sound_set(key, float(request.get("volume_db", 0.0)), 1.0, request)


func _load_catalog() -> void:
	if not _catalog.is_empty():
		return
	if FileAccess.file_exists(CATALOG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary:
			_catalog = parsed


func get_sound_set(sfx_name: String) -> Dictionary:
	_load_catalog()
	return (_catalog.get("sound_sets", {}) as Dictionary).get(sfx_name, {}) as Dictionary


func _next_path(sfx_name: String) -> String:
	var sound_set := get_sound_set(sfx_name)
	var paths: Array = sound_set.get("paths", [])
	if paths.is_empty():
		return ""
	var cursor := int(_variant_cursors.get(sfx_name, 0))
	_variant_cursors[sfx_name] = cursor + 1
	return str(paths[cursor % paths.size()])

func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	_play_sound_set(sfx_name, volume_db, pitch_scale)


## Semantic entry for authored cues. AI stimulation remains owned by domain systems.
## World loops require a source_node so scene teardown owns their lifetime.
func emit_event(event_id: String, context: Dictionary = {}) -> Node:
	_load_catalog()
	var event: Dictionary = (_catalog.get("events", {}) as Dictionary).get(event_id, {})
	if context.has("gun_id") and event_id in ["combat.weapon.reload_start", "world.pickup.item"]:
		return _play_weapon_sound(str(context["gun_id"]), "reload" if event_id == "combat.weapon.reload_start" else "pickup", float(context.get("volume_db", 0.0)), 1.0, context)
	if event_id == "combat.weapon.fire":
		if context.has("gun_id"):
			return _play_weapon_sound(str(context["gun_id"]), "fire", float(context.get("volume_db", 0.0)), 1.0, context)
		var profile := str(context.get("weapon_audio_profile", ""))
		if profile in ["pistol", "rifle", "shotgun", "smg", "sniper", "laser"]:
			return _play_sound_set(profile + "_fire", float(context.get("volume_db", 0.0)), 1.0, context)
	if event.is_empty():
		_report_missing_asset(event_id, "未登记语义事件或缺少明确武器音频配置")
		return null
	return _play_sound_set(str(event["sound_set"]), float(context.get("volume_db", 0.0)), 1.0, context)


func _play_sound_set(sfx_name: String, volume_db: float, pitch_scale: float, context: Dictionary = {}) -> Node:
	_feedback_request_counts[sfx_name] = int(_feedback_request_counts.get(sfx_name, 0)) + 1
	var path := _next_path(sfx_name)
	_last_feedback_request = {
		"event": sfx_name,
		"volume_db": volume_db,
		"pitch_scale": pitch_scale,
		"path": path,
		"context": context.duplicate(),
	}
	if path.is_empty():
		_report_missing_asset(sfx_name, "未登记事件")
		return null
	if not FileAccess.file_exists(path):
		_report_missing_asset(sfx_name, path)
		return null
	# Headless validates routing without allocating playback nodes.
	if DisplayServer.get_name() == "headless":
		return null
	var stream: AudioStream = _stream_cache.get(path) as AudioStream
	if stream == null:
		stream = load(path) as AudioStream
		if stream != null:
			_stream_cache[path] = stream
	if stream:
		var sound_set := get_sound_set(sfx_name)
		var source := context.get("source_node") as Node3D
		var looping := bool(sound_set.get("loop", false))
		if looping and not is_instance_valid(source):
			_report_missing_asset(sfx_name, "循环声缺少生命周期所有者 source_node")
			return null
		_voices = _voices.filter(func(voice): return is_instance_valid(voice) and not voice.is_queued_for_deletion())
		var matching: Array[Node] = []
		for voice in _voices:
			if str(voice.get_meta("sound_set", "")) == sfx_name:
				if looping and voice.get_parent() == source:
					return voice
				matching.append(voice)
		if matching.size() >= int(sound_set.get("max_voices", 4)):
			stop_voice(matching[0])
		if _voices.size() >= MAX_TOTAL_VOICES:
			var victim: Node = null
			var rank := str(sound_set.get("priority", "P2"))
			for voice in _voices:
				if str(voice.get_meta("priority", "P2")) >= rank:
					victim = voice
					break
			if victim == null:
				return null
			stop_voice(victim)
		var spatial := str(context.get("spatial_mode", sound_set.get("spatial_mode", "ui_2d"))) == "world_3d" and (is_instance_valid(source) or context.has("source_position"))
		var player: Node = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
		if looping and stream is AudioStreamOggVorbis:
			stream = stream.duplicate() as AudioStream
			(stream as AudioStreamOggVorbis).loop = true
		player.stream = stream
		player.volume_db = volume_db + linear_to_db(maxf(sfx_volume, 0.0001))
		player.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
		player.bus = str(sound_set.get("bus", "SFX"))
		if str(context.get("mix_role", "")) == "outdoor_wind":
			player.bus = "OutdoorWind"
		var style: Dictionary = _catalog.get("world_style_policy", {})
		if player.bus == "SFX" and (sfx_name in style.get("natural_world_sets", []) or sfx_name in style.get("weapon_sets", [])):
			player.bus = "WorldSFX"
		if player.bus == "UI":
			player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.set_meta("sound_set", sfx_name)
		player.set_meta("priority", str(sound_set.get("priority", "P2")))
		var lifetime_owner: Node = source if is_instance_valid(source) else get_tree().current_scene
		if lifetime_owner == null:
			lifetime_owner = self
		lifetime_owner.add_child(player)
		if spatial:
			(player as AudioStreamPlayer3D).global_position = context.get("source_position", source.global_position if is_instance_valid(source) else Vector3.ZERO)
			(player as AudioStreamPlayer3D).max_distance = float(context.get("max_distance", 30.0))
			(player as AudioStreamPlayer3D).unit_size = float(context.get("unit_size", 1.0))
		_voices.append(player)
		player.play()
		player.finished.connect(player.queue_free)
		return player
	else:
		_report_missing_asset(sfx_name, "资源无法载入：%s" % path)
	return null


func stop_voice(player: Node) -> void:
	if is_instance_valid(player):
		player.stop()
		player.queue_free()
	_voices.erase(player)


func stop_all_sfx() -> void:
	for voice in _voices.duplicate():
		if is_instance_valid(voice):
			stop_voice(voice)
	_voices.clear()


func validate_sound_library() -> Dictionary:
	_load_catalog()
	var missing: Array[String] = []
	var count := 0
	for key in _catalog.get("sound_sets", {}):
		for path in get_sound_set(str(key)).get("paths", []):
			count += 1
			if not str(path).ends_with(".ogg") or not FileAccess.file_exists(str(path)):
				missing.append(str(path))
	var profiles: Dictionary = _catalog.get("weapon_profiles", {})
	for gun_id in profiles:
		for action in ["fire", "reload", "pickup"]:
			var key := get_weapon_sound_set(str(gun_id), action)
			if key.is_empty() or get_sound_set(key).get("paths", []).is_empty():
				missing.append("weapon_profiles.%s.%s" % [gun_id, action])
	return {"asset_count": count, "sound_set_count": (_catalog.get("sound_sets", {}) as Dictionary).size(), "missing": missing}


func _report_missing_asset(sfx_name: String, detail: String) -> void:
	if _reported_missing_assets.has(sfx_name):
		return
	_reported_missing_assets[sfx_name] = detail
	push_error("[AudioManager] 正式音效不可用：%s（%s）。已禁止回退旧合成音。" % [sfx_name, detail])


func validate_runtime_assets() -> Dictionary:
	var missing: Array[String] = []
	var non_ogg: Array[String] = []
	for event_name in SFX:
		var path := str(SFX[event_name])
		if not FileAccess.file_exists(path):
			missing.append(str(event_name))
		elif not path.ends_with(".ogg"):
			non_ogg.append(str(event_name))
	return {
		"event_count": SFX.size(),
		"missing": missing,
		"non_ogg": non_ogg,
		"mobile_safe": missing.is_empty() and non_ogg.is_empty(),
	}

func play_music(music_name: String, volume_db: float = -6.0) -> void:
	# 占位：后续接入背景音乐
	pass

func set_sfx_volume(volume: float) -> void:
	sfx_volume = clamp(volume, 0.0, 1.0)

func set_music_volume(volume: float) -> void:
	music_volume = clamp(volume, 0.0, 1.0)

func load_audio_settings() -> void:
	# 从已保存设置中读取音量
	pass

func save_audio_settings() -> void:
	# 保存音量到设置文件
	pass

## ========== 战斗音效辅助 ==========

## 枪身身份唯一决定音色；射速、弹丸数与命运配件不能改变枪种。
func get_weapon_sound_set(gun_id: String, action: String) -> String:
	_load_catalog()
	var profiles: Dictionary = _catalog.get("weapon_profiles", {})
	var profile: Dictionary = profiles.get(gun_id, {})
	return str(profile.get(action, ""))


func _play_weapon_sound(gun_id: String, action: String, volume_db: float = 0.0, pitch: float = 1.0, context: Dictionary = {}) -> Node:
	var key := get_weapon_sound_set(gun_id, action)
	if key.is_empty():
		_report_missing_asset("%s.%s" % [gun_id, action], "未登记枪身音频配置")
		return null
	return _play_sound_set(key, volume_db, pitch, context)


func play_fire_sfx(gun_id: String) -> void:
	_play_weapon_sound(gun_id, "fire")


func play_pickup_sfx(item: Dictionary, volume_db: float = -4.0) -> void:
	if bool(item.get("is_currency", false)):
		play_sfx("soul_pickup", volume_db)
		return
	if str(item.get("type", "")) == "weapon":
		var nested: Dictionary = item.get("weapon_instance", {})
		var gun_id := str(item.get("assembly_id", nested.get("assembly_id", "")))
		if gun_id.is_empty():
			var content_id := str(item.get("weapon_content_id", nested.get("weapon_content_id", item.get("id", ""))))
			gun_id = str(ItemRegistry.get_instance().get_item(content_id).get("assembly_id", ""))
		if not get_weapon_sound_set(gun_id, "pickup").is_empty():
			_play_weapon_sound(gun_id, "pickup", volume_db)
			return
	play_sfx("item_pickup", volume_db)

## 暴击命中音效
func play_crit_sfx() -> void:
	play_sfx("crit_hit")

## 命运卡片应用音效
func play_fate_card_sfx() -> void:
	play_sfx("fate_card")

## 玩家受伤音效
func play_player_hit_sfx() -> void:
	play_sfx("player_hit")

## 玩家闪避音效
func play_dash_sfx() -> void:
	play_sfx("player_dash")

## 换弹音效
func play_reload_sfx(gun_id: String) -> void:
	_play_weapon_sound(gun_id, "reload")

## 怪物死亡音效
func play_enemy_die_sfx() -> void:
	play_sfx("enemy_die")

## 怪物受伤音效（非暴击）
func play_enemy_hit_sfx() -> void:
	play_sfx("enemy_hit")


## 近战挥空层：每段 active 只播放一次，连段与武器类型只改变播放参数。
func play_melee_swing_sfx(weapon_content_id: String, combo_step: int) -> void:
	var pitch: float = float([0.94, 1.03, 0.86][clampi(combo_step - 1, 0, 2)])
	var volume_db: float = float([-1.0, 0.0, 1.8][clampi(combo_step - 1, 0, 2)])
	if weapon_content_id == "weapon_waraxe":
		pitch -= 0.08
		volume_db += 0.8
	play_sfx("melee_swing", volume_db, pitch)


## 近战接触主层：一次挥砍命中多目标仍只播放一次，目标各自受击声由目标逻辑负责。
func play_melee_impact_sfx(weapon_content_id: String, combo_step: int) -> void:
	var pitch: float = float([0.98, 1.04, 0.88][clampi(combo_step - 1, 0, 2)])
	var volume_db: float = float([0.0, 0.8, 2.4][clampi(combo_step - 1, 0, 2)])
	if weapon_content_id == "weapon_waraxe":
		pitch -= 0.10
		volume_db += 1.0
	play_sfx("melee_impact", volume_db, pitch)


func reset_feedback_debug() -> void:
	_feedback_request_counts.clear()
	_last_feedback_request.clear()


func get_feedback_debug_snapshot() -> Dictionary:
	return {
		"request_counts": _feedback_request_counts.duplicate(true),
		"last_request": _last_feedback_request.duplicate(true),
	}
