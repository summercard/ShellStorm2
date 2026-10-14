extends Node
## 端到端探针的截图器。挂在 SceneTree.root 下，跨场景切换存活。
## 阶段：startup（loading 页）→ movie（开场影片）→ gameplay（98F 办公室）。

const OUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2-work/probes/opening_movie_e2e"
const SHOT_INTERVAL_S := 4.0
const HARD_TIMEOUT_S := 150.0

var _elapsed := 0.0
var _next_shot := 0.0
var _phase := "startup"
var _shot_index := 0
var _saw_movie := false
var _movie_finished_at := -1.0
var _saw_tower := false
var _tower_ready_at := -1.0
var _reported := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _process(delta: float) -> void:
	_elapsed += delta
	_detect_phase()
	if _elapsed >= HARD_TIMEOUT_S:
		print("E2E_TIMEOUT phase=", _phase, " saw_movie=", _saw_movie, " saw_tower=", _saw_tower)
		get_tree().quit(2)
		return
	if _elapsed >= _next_shot:
		_next_shot += SHOT_INTERVAL_S
		_capture()


func _detect_phase() -> void:
	var movie := _find_movie()
	if movie != null and not _saw_movie:
		_saw_movie = true
		_phase = "movie"
		print("E2E_MOVIE_APPEARED t=%.2f" % _elapsed)
	if _saw_movie and movie == null and _movie_finished_at < 0.0:
		# 影片层把自己移除 = 交接完成。
		_movie_finished_at = _elapsed
		_phase = "gameplay"
		print("E2E_MOVIE_GONE t=%.2f" % _elapsed)
	var tower := _find_tower()
	if tower != null and not _saw_tower:
		_saw_tower = true
		_tower_ready_at = _elapsed
		print("E2E_TOWER_PRESENT t=%.2f" % _elapsed)
	if _movie_finished_at > 0.0 and _elapsed >= _movie_finished_at + 3.0:
		print("E2E_DONE movie_appeared=%s movie_gone=%.2f tower=%s" % [_saw_movie, _movie_finished_at, _saw_tower])
		get_tree().quit(0)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var shot_name := "%02d_%s_t%.1f" % [_shot_index, _phase, _elapsed]
	_shot_index += 1
	var error := get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("E2E_SHOT ", shot_name, " save=", error_string(error))


func _find_movie() -> OpeningMovieScreen3D:
	for node in get_tree().root.find_children("*", "", true, false):
		if node is OpeningMovieScreen3D:
			return node as OpeningMovieScreen3D
	return null


func _find_tower() -> TowerDescent3D:
	for node in get_tree().root.find_children("*", "", true, false):
		if node is TowerDescent3D:
			return node as TowerDescent3D
	return null
