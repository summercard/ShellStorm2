@tool
extends Node

signal thumbnail_ready(path: String, texture: Texture2D)
signal thumbnail_failed(path: String)
signal page_progress(ready: int, total: int)
const STAGE := preload("res://tools/scene_builder/preview_stage.gd")
const LOADER := preload("res://tools/scene_builder/asset_loader.gd")
const CACHE_DIR := "res://.godot/editor/scene_builder_thumbnails"
var stage: STAGE
var cache: Dictionary = {}
var pending: Array[String] = []
var failures: Dictionary = {}
var _working := false
var _revision := 0
var _loader: LOADER
var _load_finished := false
var _loaded_resource: PackedScene
var _page_paths: Array[String] = []
var _stopped := false

func stop() -> void:
	_stopped = true
	pending.clear()
	_load_finished = true
	if is_instance_valid(_loader):
		_loader.cancel("thumbnail")
	if is_instance_valid(stage):
		stage.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _ready() -> void:
	stage = STAGE.new()
	add_child(stage)
	_loader = LOADER.new()
	add_child(_loader)
	_loader.completed.connect(func(_channel, _path, resource):
		_loaded_resource = resource as PackedScene
		_load_finished = true)
	_loader.failed.connect(func(_channel, _path, _reason):
		_loaded_resource = null
		_load_finished = true)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)

func request(path: String) -> void:
	if _stopped:
		return
	if cache.has(path):
		thumbnail_ready.emit(path, cache[path])
		return
	if path in pending or failures.has(path) or DisplayServer.get_name() == "headless":
		return
	pending.append(path)
	if not _working:
		_work.call_deferred()

func request_page(paths: Array[String]) -> void:
	# A new filter or scroll position supersedes work for cards that are no longer visible.
	pending.clear()
	_page_paths = paths.duplicate()
	for path in paths:
		if failures.has(path):
			thumbnail_failed.emit(path)
		else:
			request(path)
	_report_progress()

func _report_progress() -> void:
	var ready := 0
	for path in _page_paths:
		if cache.has(path) or failures.has(path):
			ready += 1
	page_progress.emit(ready, _page_paths.size())

func invalidate() -> void:
	_revision += 1
	cache.clear()
	failures.clear()
	# Dependency timestamps in the filename also invalidate on the next editor launch.

func _fingerprint(path: String, seen: Dictionary, depth: int = 0) -> String:
	if seen.has(path) or depth > 4:
		return ""
	seen[path] = true
	var stamp := path + ":" + str(FileAccess.get_modified_time(path))
	for dependency in ResourceLoader.get_dependencies(path):
		var resolved := dependency.get_slice("::", dependency.get_slice_count("::") - 1)
		if resolved.begins_with("res://"):
			stamp += _fingerprint(resolved, seen, depth + 1)
	return stamp

func _work() -> void:
	if _working:
		return
	_working = true
	while not pending.is_empty():
		await get_tree().process_frame
		if _stopped or pending.is_empty():
			break
		var path: String = pending.pop_front()
		var revision := _revision
		var fingerprint := _fingerprint(path, {}).sha256_text()
		var file := CACHE_DIR.path_join(fingerprint + "_r1.png")
		var picture: Image
		if FileAccess.file_exists(file):
			picture = Image.load_from_file(file)
		else:
			_loaded_resource = null
			_load_finished = false
			_loader.request("thumbnail", path)
			while not _load_finished:
				await get_tree().process_frame
			if _stopped:
				break
			if _loaded_resource == null or not stage.show_asset(path, _loaded_resource):
				failures[path] = true
				thumbnail_failed.emit(path)
				_report_progress()
				continue
			stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			# The editor can stop drawing when idle/occluded. Do not wait on a signal
			# that requires unrelated mouse movement to wake the next render frame.
			for frame in range(2):
				await get_tree().process_frame
				if _stopped:
					break
				RenderingServer.force_draw(false)
			if _stopped:
				break
			picture = stage.get_texture().get_image()
			stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
			if picture != null and not picture.is_empty():
				picture.resize(128, 128, Image.INTERPOLATE_LANCZOS)
				picture.save_png(file)
		if revision != _revision:
			pending.append(path)
			continue
		if picture != null and not picture.is_empty():
			var texture := ImageTexture.create_from_image(picture)
			cache[path] = texture
			thumbnail_ready.emit(path, texture)
		_report_progress()
	_working = false
