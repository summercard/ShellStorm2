extends Node

var master_bus: int = 0
var sfx_bus: int = 1
var music_bus: int = 2

var sfx_volume: float = 1.0
var music_volume: float = 0.8

func _ready() -> void:
	load_audio_settings()

func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	# Placeholder for SFX playback
	# Will be implemented with actual audio files
	pass

func play_music(music_name: String, volume_db: float = -6.0) -> void:
	# Placeholder for music playback
	pass

func set_sfx_volume(volume: float) -> void:
	sfx_volume = clamp(volume, 0.0, 1.0)

func set_music_volume(volume: float) -> void:
	music_volume = clamp(volume, 0.0, 1.0)

func load_audio_settings() -> void:
	# Load from saved settings
	pass

func save_audio_settings() -> void:
	# Save to settings file
	pass