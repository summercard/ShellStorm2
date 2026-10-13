extends Node

var master_bus: int = 0
var sfx_bus: int = 1
var music_bus: int = 2

var sfx_volume: float = 1.0
var music_volume: float = 0.8

# 正式音效资产。OGG Vorbis 是桌面与移动端共同的运行时主格式；WAV 只保留母版。
const SFX: Dictionary = {
	# 现有战斗/流程事件
	"pistol_fire": "res://src/assets/audio/sfx/pistol_fire_v002.ogg",
	"rifle_fire": "res://src/assets/audio/sfx/rifle_fire_v002.ogg",
	"shotgun_fire": "res://src/assets/audio/sfx/shotgun_fire_v002.ogg",
	"smg_fire": "res://src/assets/audio/sfx/smg_fire_v002.ogg",
	"sniper_fire": "res://src/assets/audio/sfx/sniper_fire_v002.ogg",
	"laser_fire": "res://src/assets/audio/sfx/laser_fire_v002.ogg",
	"enemy_hit": "res://src/assets/audio/sfx/enemy_hit_v002.ogg",
	"enemy_die": "res://src/assets/audio/sfx/enemy_die_v002.ogg",
	"player_hit": "res://src/assets/audio/sfx/player_hit_v002.ogg",
	"player_dash": "res://src/assets/audio/sfx/player_dash_v002.ogg",
	"reload": "res://src/assets/audio/sfx/reload_v002.ogg",
	"crit_hit": "res://src/assets/audio/sfx/crit_hit_v002.ogg",
	"melee_swing": "res://src/assets/audio/sfx/melee_swing_v002.ogg",
	"melee_impact": "res://src/assets/audio/sfx/melee_impact_v002.ogg",
	"fate_card": "res://src/assets/audio/sfx/fate_card_v002.ogg",
	"extraction_start": "res://src/assets/audio/sfx/extraction_start_v002.ogg",
	"extraction_done": "res://src/assets/audio/sfx/extraction_done_v002.ogg",
	"extraction_abort": "res://src/assets/audio/sfx/extraction_abort_v002.ogg",

	# 已正式接入的扩展事件（所有权见《音效接入说明.md》）
	"ui_hover": "res://src/assets/audio/sfx/ui_hover_v002.ogg",
	"ui_click": "res://src/assets/audio/sfx/ui_click_v002.ogg",
	"ui_error": "res://src/assets/audio/sfx/ui_error_v002.ogg",
	"ammo_empty": "res://src/assets/audio/sfx/ammo_empty_v002.ogg",
	"item_pickup": "res://src/assets/audio/sfx/item_pickup_v002.ogg",
	"soul_pickup": "res://src/assets/audio/sfx/soul_pickup_v002.ogg",
	"door_open": "res://src/assets/audio/sfx/door_open_v002.ogg",
	"door_locked": "res://src/assets/audio/sfx/door_locked_v002.ogg",
	"container_open": "res://src/assets/audio/sfx/container_open_v002.ogg",
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

const CATALOG_PATH := "res://src/assets/audio/sfx/sfx_catalog.json"
const MAX_TOTAL_VOICES := 40

func _ready() -> void:
	load_audio_settings()
	_load_catalog()
	# New buses inherit SFX so existing SFX volume/mute remains effective.
	for bus_name in ["UI", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master")


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
	if event_id == "combat.weapon.fire":
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
		var spatial := str(sound_set.get("spatial_mode", "ui_2d")) == "world_3d" and (is_instance_valid(source) or context.has("source_position"))
		var player: Node = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
		if looping and stream is AudioStreamOggVorbis:
			stream = stream.duplicate() as AudioStream
			(stream as AudioStreamOggVorbis).loop = true
		player.stream = stream
		player.volume_db = volume_db + linear_to_db(maxf(sfx_volume, 0.0001))
		player.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
		player.bus = str(sound_set.get("bus", "SFX"))
		if player.bus == "UI":
			player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.set_meta("sound_set", sfx_name)
		player.set_meta("priority", str(sound_set.get("priority", "P2")))
		var lifetime_owner: Node = source if is_instance_valid(source) else get_tree().current_scene
		if lifetime_owner == null:
			lifetime_owner = self
		lifetime_owner.add_child(player)
		if spatial:
			(player as AudioStreamPlayer3D).global_position = source.global_position if is_instance_valid(source) else context["source_position"]
			(player as AudioStreamPlayer3D).max_distance = 30.0
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

## 射击音效（根据武器 fire_rate 推算类型）
func play_fire_sfx(fire_rate: float, projectile_count: int) -> void:
	var sfx_key: String
	if projectile_count >= 5:
		sfx_key = "shotgun_fire"
	elif fire_rate >= 10.0:
		sfx_key = "smg_fire"
	elif fire_rate >= 5.0:
		sfx_key = "rifle_fire"
	elif fire_rate >= 2.0:
		sfx_key = "pistol_fire"
	else:
		sfx_key = "sniper_fire"
	play_sfx(sfx_key)

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
func play_reload_sfx() -> void:
	play_sfx("reload")

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
