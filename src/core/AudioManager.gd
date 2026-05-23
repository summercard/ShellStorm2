extends Node

var master_bus: int = 0
var sfx_bus: int = 1
var music_bus: int = 2

var sfx_volume: float = 1.0
var music_volume: float = 0.8

# 音效映射（骨架，后续替换真实音频文件）
const SFX: Dictionary = {
	"pistol_fire":    "res://assets/audio/sfx/pistol_fire.wav",
	"rifle_fire":     "res://assets/audio/sfx/rifle_fire.wav",
	"shotgun_fire":   "res://assets/audio/sfx/shotgun_fire.wav",
	"smg_fire":       "res://assets/audio/sfx/smg_fire.wav",
	"sniper_fire":    "res://assets/audio/sfx/sniper_fire.wav",
	"laser_fire":     "res://assets/audio/sfx/laser_fire.wav",
	"enemy_hit":      "res://assets/audio/sfx/enemy_hit.wav",
	"enemy_die":      "res://assets/audio/sfx/enemy_die.wav",
	"player_hit":     "res://assets/audio/sfx/player_hit.wav",
	"player_dash":    "res://assets/audio/sfx/player_dash.wav",
	"reload":         "res://assets/audio/sfx/reload.wav",
	"crit_hit":       "res://assets/audio/sfx/crit_hit.wav",
	"extraction_start": "res://assets/audio/sfx/extraction_start.wav",
	"extraction_done":  "res://assets/audio/sfx/extraction_done.wav",
}

func _ready() -> void:
	load_audio_settings()

func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var path: String = SFX.get(sfx_name, "")
	if path.is_empty():
		return
	if not FileAccess.file_exists(path):
		# 音效文件不存在，跳过
		return
	var stream: AudioStream = load(path)
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = volume_db
		player.pitch_scale = pitch_scale
		player.bus = "SFX"
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

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
