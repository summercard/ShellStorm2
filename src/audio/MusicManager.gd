extends Node
## 全局音乐触发中枢。autoload 单例，挂在 /root/MusicManager。
## 场景代码不直接 new AudioStreamPlayer，全部走 MusicManager.play("music_id")。
##
## 设计原则：
## 1. 解耦：场景只发"我要播什么"，不管音频播放器 / 音量 / 淡入淡出。
## 2. 可管理：所有曲目在 MusicCatalog 里登记，新增曲目不动本类。
## 3. 跨场景持久：autoload，切换 scene 不重置。
## 4. 栈式历史：play_boss() / stop_boss() 在进入 Boss 房前压栈，离开后弹出。

const Catalog = preload("res://src/audio/MusicCatalog.gd")

signal music_changed(music_id: String, track_path: String)
signal music_finished(music_id: String)
signal music_paused(music_id: String)
signal music_resumed(music_id: String)

var _stream_player: AudioStreamPlayer
var _bus_volume_tween: Tween
var _current_music_id: String = ""
var _current_track_path: String = ""
var _previous_stack: Array[String] = []
var _paused: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_stream_player = AudioStreamPlayer.new()
	_stream_player.name = "MusicStreamPlayer"
	_stream_player.bus = "Music"
	add_child(_stream_player)
	_stream_player.finished.connect(_on_stream_finished)
	_ensure_music_bus()


func _ensure_music_bus() -> void:
	# 简易兜底：项目应配 AudioBusLayout 含 Music 总线。
	# 本函数确保 Music 总线存在并跟随 master。
	if AudioServer.get_bus_index("Music") < 0:
		var master_idx := AudioServer.get_bus_index("Master")
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, "Music")
		AudioServer.set_bus_send(1, "Master")


## 播放一首注册曲目。已注册曲目会淡入淡出切换；未注册的 music_id 直接报错。
func play(music_id: String) -> bool:
	if not Catalog.has_music_id(music_id):
		push_error("[MusicManager] music_id 未注册: %s" % music_id)
		return false
	if _current_music_id == music_id and not _paused and _stream_player != null and _stream_player.playing:
		return true
	var entry := Catalog.get_entry(music_id)
	var track_path := _pick_track(entry)
	_play_track(music_id, track_path, entry)
	return true


## 在不切断当前音乐的情况下，把 music_id 压栈；后续 restore() 弹出。
## 典型用法：进入 Boss 房 → push_and_play("boss_intense")；离开 → restore()。
func push_and_play(music_id: String) -> bool:
	if _current_music_id != "":
		_previous_stack.append(_current_music_id)
	return play(music_id)


## 弹出栈顶音乐。无栈则静音。
func restore() -> bool:
	if _previous_stack.is_empty():
		stop()
		return false
	var previous_id: String = _previous_stack.pop_back()
	return play(previous_id)


func stop() -> void:
	_fade_out_current(0.8)
	_current_music_id = ""
	_previous_stack.clear()


func hard_reset() -> void:
	# 场景切换或调试用。立刻停所有 tween，清栈，重设静音。
	if _bus_volume_tween != null and _bus_volume_tween.is_valid():
		_bus_volume_tween.kill()
	if _stream_player != null:
		_stream_player.stop()
		_stream_player.volume_db = 0.0
	_current_music_id = ""
	_current_track_path = ""
	_previous_stack.clear()
	_paused = false


func pause() -> void:
	if _paused or _stream_player == null:
		return
	_paused = true
	_stream_player.stream_paused = true
	if _current_music_id != "":
		music_paused.emit(_current_music_id)


func resume() -> void:
	if not _paused or _stream_player == null:
		return
	_paused = false
	_stream_player.stream_paused = false
	if _current_music_id != "":
		music_resumed.emit(_current_music_id)


func set_volume_db(value: float) -> void:
	if _stream_player != null:
		_stream_player.volume_db = value


func get_current_music_id() -> String:
	return _current_music_id


func get_current_track_path() -> String:
	return _current_track_path


func is_playing(music_id: String = "") -> bool:
	if _stream_player == null or not _stream_player.playing:
		return false
	if music_id == "":
		return true
	return _current_music_id == music_id


# ---------------- 内部 ----------------

func _pick_track(entry: Dictionary) -> String:
	var tracks: Array = entry.get("tracks", [])
	if tracks.is_empty():
		return ""
	var mode := str(entry.get("selection_mode", "first"))
	match mode:
		"random":
			return str(tracks[_rng.randi_range(0, tracks.size() - 1)])
		"sequential":
			var idx := _previous_track_index(entry)
			idx = (idx + 1) % tracks.size()
			return str(tracks[idx])
		_:
			return str(tracks[0])


var _sequential_index_cache: Dictionary = {}

func _previous_track_index(entry: Dictionary) -> int:
	var music_id := str(entry.get("music_id", ""))
	if _sequential_index_cache.has(music_id):
		return int(_sequential_index_cache[music_id])
	return -1


func _play_track(music_id: String, track_path: String, entry: Dictionary) -> void:
	var stream := load(track_path) as AudioStream
	if stream == null:
		push_error("[MusicManager] 无法加载音频: %s" % track_path)
		return

	# 关键：kill 所有在跑的 tween（包括 fade_out），否则旧的 fade out 还会继续把新曲的音量拉低
	if _bus_volume_tween != null and _bus_volume_tween.is_valid():
		_bus_volume_tween.kill()

	# 避免重复相同曲时切新 A/B：直接设新 stream + 淡入即可
	_stream_player.stream = stream
	_stream_player.volume_db = -80.0
	_stream_player.bus = str(entry.get("bus", "Music"))
	if not _stream_player.playing:
		_stream_player.play()
	_current_music_id = music_id
	_current_track_path = track_path
	music_changed.emit(music_id, track_path)

	var fade_in := float(entry.get("fade_in_seconds", 1.0))
	var target_db := float(entry.get("default_volume_db", 0.0))
	_tween_volume_to(target_db, fade_in)


func _fade_out_current(seconds: float) -> void:
	if _stream_player == null or not _stream_player.playing:
		return
	if _bus_volume_tween != null and _bus_volume_tween.is_valid():
		_bus_volume_tween.kill()
	var start_db := _stream_player.volume_db
	_bus_volume_tween = create_tween()
	_bus_volume_tween.tween_method(_set_volume_db_no_bus, start_db, -80.0, seconds)
	_bus_volume_tween.tween_callback(func() -> void:
		if _stream_player != null and _stream_player.playing:
			_stream_player.stop()
	)


func _set_volume_db_no_bus(value: float) -> void:
	if _stream_player != null:
		_stream_player.volume_db = value


func _tween_volume_to(target_db: float, seconds: float) -> void:
	if _bus_volume_tween != null and _bus_volume_tween.is_valid():
		_bus_volume_tween.kill()
	_bus_volume_tween = create_tween()
	_bus_volume_tween.tween_method(_set_volume_db_no_bus, _stream_player.volume_db, target_db, seconds)


func _on_stream_finished() -> void:
	if _current_music_id == "":
		return
	var finished_id := _current_music_id
	var entry := Catalog.get_entry(finished_id)
	var should_loop := bool(entry.get("loop", true))
	music_finished.emit(finished_id)
	if should_loop:
		var track_path := _pick_track(entry)
		if track_path != "":
			_play_track(finished_id, track_path, entry)