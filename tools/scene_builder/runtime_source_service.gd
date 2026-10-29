@tool
extends Node
signal changed(rows: Array)
signal status(label: String, busy: bool, failed: bool)
const CACHE := "res://.godot/editor/scene_builder_runtime/latest.json"
var rows: Array = []
var seed_value := 77003244
var scene_path := "res://scenes/ExpeditionLevel03_3D.tscn"
var busy := false
var _job := ""
var _started := 0
var _last_label := ""

func _ready() -> void:
	if FileAccess.file_exists(CACHE):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
		if data is Dictionary:
			rows = data.get("rows", [])
			seed_value = int(data.get("seed", seed_value))
			scene_path = str(data.get("scene", scene_path))
	changed.emit(rows)
	set_process(true)

func refresh(scene: String, seed: int) -> void:
	if busy:
		return
	scene_path = scene
	seed_value = seed
	var output: Array = []
	var python := OS.get_environment("SHELLSTORM_PYTHON")
	if python.is_empty():
		python = "python"
	var launcher := ProjectSettings.globalize_path("res://tools/scene_builder/runtime_capture.py")
	var result := OS.execute(python, PackedStringArray(["-X", "utf8", launcher, "--locate"]), output, false, false)
	var paths: Variant = JSON.parse_string("".join(output).strip_edges())
	if result != 0 or not paths is Dictionary:
		status.emit("无法启动Python读取器，请检查Python路径。", false, true)
		return
	var job_name := "capture_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_job = str(paths["root"]).path_join(job_name)
	_started = Time.get_ticks_msec()
	var engine := OS.get_executable_path()
	var console := engine.trim_suffix(".exe") + "_console.exe"
	if not engine.ends_with("_console.exe") and FileAccess.file_exists(console):
		engine = console
	var pid := OS.create_process(python, PackedStringArray(["-X", "utf8", launcher, "--engine", engine,
		"--scene", scene_path, "--seed", str(seed_value), "--job", job_name]), false)
	if pid <= 0:
		status.emit("隔离关卡进程启动失败，可重试。", false, true)
		return
	busy = true
	rows = []
	changed.emit(rows)
	status.emit("正在读取真实关卡…", true, false)

func cancel() -> void:
	if not busy:
		return
	DirAccess.make_dir_recursive_absolute(_job)
	var file := FileAccess.open(_job.path_join("cancel.request"), FileAccess.WRITE)
	if file != null:
		file.store_string("cancel")

func _process(_delta: float) -> void:
	if not busy:
		return
	var status_file := _job.path_join("status.json")
	if FileAccess.file_exists(status_file):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(status_file))
		if data is Dictionary:
			var state := str(data.get("state", "running"))
			var label := str(data.get("label", "正在读取真实关卡…"))
			if state == "complete":
				var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(data["index"])))
				busy = false
				if index is Dictionary:
					rows = index.get("rows", [])
					changed.emit(rows)
				status.emit(label, false, false)
				return
			if state == "failed":
				busy = false
				status.emit(label + "\n日志：" + str(data.get("log", "")), false, true)
				return
			_last_label = label
	status.emit(("正在读取真实关卡…" if _last_label.is_empty() else _last_label) + " %.1fs" % ((Time.get_ticks_msec() - _started) / 1000.0), true, false)
	if Time.get_ticks_msec() - _started > 130000:
		cancel()
		busy = false
		status.emit("读取器超时，请重试。", false, true)

func _exit_tree() -> void:
	cancel()
