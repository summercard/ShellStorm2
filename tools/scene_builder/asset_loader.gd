@tool
extends Node
## Bounded background loading. Cancellation ignores stale results; it does not kill engine jobs.

signal progress(channel: String, path: String, ratio: float, elapsed: float)
signal completed(channel: String, path: String, resource: Resource)
signal failed(channel: String, path: String, reason: String)
const TIMEOUT_SECONDS := 120.0
var _latest: Dictionary = {}
var _active: Dictionary = {}
var _queue: Array[Dictionary] = []
var _serial := 0

func request(channel: String, path: String) -> int:
	_serial += 1
	_latest[channel] = _serial
	_queue = _queue.filter(func(job): return job["channel"] != channel)
	_queue.append({"channel": channel, "path": path, "serial": _serial, "start": Time.get_ticks_msec()})
	return _serial

func cancel(channel: String) -> void:
	_latest.erase(channel)
	_queue = _queue.filter(func(job): return job["channel"] != channel)

func has_request(channel: String) -> bool:
	return _latest.has(channel)

func _current(job: Dictionary) -> bool:
	return _latest.get(job["channel"], -1) == job["serial"]

func _process(_delta: float) -> void:
	for path in _active.keys():
		var job: Dictionary = _active[path]
		var value: Array = []
		var state := ResourceLoader.load_threaded_get_status(path, value)
		var elapsed := (Time.get_ticks_msec() - int(job["start"])) / 1000.0
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if _current(job):
				progress.emit(job["channel"], path, float(value[0]) if not value.is_empty() else -1.0, elapsed)
				if elapsed >= TIMEOUT_SECONDS:
					_latest.erase(job["channel"])
					failed.emit(job["channel"], path, "读取超过120秒；可以重试或选择其他场景。")
			continue
		_active.erase(path)
		# Always collect finished engine jobs, including results cancelled by the UI.
		var result: Resource = ResourceLoader.load_threaded_get(path) if state == ResourceLoader.THREAD_LOAD_LOADED else null
		if not _current(job):
			continue
		_latest.erase(job["channel"])
		if result != null:
			completed.emit(job["channel"], path, result)
		else:
			failed.emit(job["channel"], path, "资源读取失败；请检查文件及其依赖。")
	for job in _queue.duplicate():
		if _active.size() >= 2:
			break
		var path := str(job["path"])
		if _active.has(path):
			continue
		_queue.erase(job)
		if not _current(job):
			continue
		if not FileAccess.file_exists(path):
			_latest.erase(job["channel"])
			failed.emit(job["channel"], path, "找不到文件：" + path.get_file())
			continue
		var error := ResourceLoader.load_threaded_request(path, "PackedScene", false)
		if error != OK:
			_latest.erase(job["channel"])
			failed.emit(job["channel"], path, "无法开始读取：" + error_string(error))
			continue
		_active[path] = job
		progress.emit(job["channel"], path, 0.0, 0.0)
