extends Node

var master_bus: int = 0
var sfx_bus: int = 1
var music_bus: int = 2

var sfx_volume: float = 1.0
var music_volume: float = 0.8

## 程序化音效降级（无音频文件时的备选）
var _synth = null  # SynthSfx, typed lazily

# 正式音效资产。键名保持原有调用契约不变；新增键可通过 play_sfx() 直接接入。
const SFX: Dictionary = {
	# 现有战斗/流程事件
	"pistol_fire": "res://src/assets/audio/sfx/pistol_fire.wav",
	"rifle_fire": "res://src/assets/audio/sfx/rifle_fire.wav",
	"shotgun_fire": "res://src/assets/audio/sfx/shotgun_fire.wav",
	"smg_fire": "res://src/assets/audio/sfx/smg_fire.wav",
	"sniper_fire": "res://src/assets/audio/sfx/sniper_fire.wav",
	"laser_fire": "res://src/assets/audio/sfx/laser_fire.wav",
	"enemy_hit": "res://src/assets/audio/sfx/enemy_hit.wav",
	"enemy_die": "res://src/assets/audio/sfx/enemy_die.wav",
	"player_hit": "res://src/assets/audio/sfx/player_hit.wav",
	"player_dash": "res://src/assets/audio/sfx/player_dash.wav",
	"reload": "res://src/assets/audio/sfx/reload.wav",
	"crit_hit": "res://src/assets/audio/sfx/crit_hit.wav",
	"fate_card": "res://src/assets/audio/sfx/fate_card.wav",
	"extraction_start": "res://src/assets/audio/sfx/extraction_start.wav",
	"extraction_done": "res://src/assets/audio/sfx/extraction_done.wav",
	"extraction_abort": "res://src/assets/audio/sfx/extraction_abort.wav",

	# 新增建议事件（接入点见《音效接入说明.md》）
	"ui_hover": "res://src/assets/audio/sfx/ui_hover.wav",
	"ui_click": "res://src/assets/audio/sfx/ui_click.wav",
	"ui_error": "res://src/assets/audio/sfx/ui_error.wav",
	"ammo_empty": "res://src/assets/audio/sfx/ammo_empty.wav",
	"item_pickup": "res://src/assets/audio/sfx/item_pickup.wav",
	"soul_pickup": "res://src/assets/audio/sfx/soul_pickup.wav",
	"door_open": "res://src/assets/audio/sfx/door_open.wav",
	"door_locked": "res://src/assets/audio/sfx/door_locked.wav",
	"container_open": "res://src/assets/audio/sfx/container_open.wav",
	"wave_start": "res://src/assets/audio/sfx/wave_start.wav",
	"wave_clear": "res://src/assets/audio/sfx/wave_clear.wav",
	"boss_intro": "res://src/assets/audio/sfx/boss_intro.wav",
	"boss_phase": "res://src/assets/audio/sfx/boss_phase.wav",
	"boss_defeat": "res://src/assets/audio/sfx/boss_defeat.wav",
	"merchant_purchase": "res://src/assets/audio/sfx/merchant_purchase.wav",
}

# 缓存已加载的 AudioStream，避免自动武器连续射击时重复加载资源。
var _stream_cache: Dictionary = {}

func _ready() -> void:
	load_audio_settings()
	_init_synth()

func _init_synth() -> void:
	if _synth != null:
		return
	var synth_node := Node.new()
	synth_node.set_script(load("res://src/core/SynthSfx.gd"))
	add_child(synth_node)
	_synth = synth_node

func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	# Headless validation has no audible consumer. Avoid transient WAV/playback
	# resources outliving an intentionally short verification scene.
	if DisplayServer.get_name() == "headless":
		var synth_script := _synth.get_script() as Script if _synth != null else null
		if synth_script == null or synth_script.resource_path == "res://src/core/SynthSfx.gd":
			return
	var path: String = SFX.get(sfx_name, "")
	if path.is_empty():
		_play_fallback_sfx(sfx_name)
		return
	if not FileAccess.file_exists(path):
		# 音效文件不存在 → 降级到程序化合成
		_play_fallback_sfx(sfx_name)
		return
	var stream: AudioStream = _stream_cache.get(path) as AudioStream
	if stream == null:
		stream = load(path) as AudioStream
		if stream != null:
			_stream_cache[path] = stream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = volume_db + linear_to_db(maxf(sfx_volume, 0.0001))
		player.pitch_scale = pitch_scale
		player.bus = "SFX"
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

## 音效文件缺失时，按名称路由到程序化合成
func _play_fallback_sfx(sfx_name: String) -> void:
	if _synth == null:
		return
	match sfx_name:
		"pistol_fire", "rifle_fire", "shotgun_fire", "smg_fire", "sniper_fire", "laser_fire":
			_synth.play_shoot(5.0, 1)
		"enemy_hit":
			_synth.play_hit()
		"enemy_die":
			_synth.play_enemy_die()
		"player_hit":
			_synth.play_player_hit()
		"player_dash":
			_synth.play_dash()
		"reload":
			_synth.play_reload()
		"crit_hit":
			_synth.play_crit()
		"fate_card":
			_synth.play_fate_card()
		"extraction_start":
			_synth.play_extraction_start()
		"extraction_done":
			_synth.play_extraction_done()
		"extraction_abort", "ui_error", "door_locked":
			_synth.play_extraction_abort()
		"ui_hover", "ui_click", "item_pickup", "soul_pickup", "wave_clear", "merchant_purchase":
			_synth.play_fate_card()
		"ammo_empty", "container_open", "door_open":
			_synth.play_reload()
		"wave_start", "boss_intro", "boss_phase":
			_synth.play_extraction_start()
		"boss_defeat":
			_synth.play_enemy_die()

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
