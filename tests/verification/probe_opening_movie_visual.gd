extends Node
## 一次性探针：真实窗口下验证开场影片层能真的解码播放并交接（headless 做不到）。
## 用完即弃，不属于验收套件（`check_verification_registry.py` 只查 `verify_*`）。

const OUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2-work/probes/opening_movie_visual"
const SCREEN_SCENE := preload("res://scenes/ui/OpeningMovieScreen3D.tscn")
const SHOT_TIMES := [0.8, 3.0, 8.0, 15.0, 20.5]
const HARD_TIMEOUT_S := 40.0

var _screen: OpeningMovieScreen3D
var _shot_index := 0
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_screen = SCREEN_SCENE.instantiate() as OpeningMovieScreen3D
	_screen.transition_finished.connect(_on_finished)
	add_child(_screen)
	print("PROBE_READY headless_abort=", _screen.get_entry_snapshot().get("aborted_in_headless"))


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _shot_index < SHOT_TIMES.size() and _elapsed >= float(SHOT_TIMES[_shot_index]):
		_capture(_shot_index)
		_shot_index += 1
	if _elapsed >= HARD_TIMEOUT_S:
		print("PROBE_TIMEOUT: 影片层没有在 %.1fs 内交接" % HARD_TIMEOUT_S)
		get_tree().quit(2)


func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var image := get_viewport().get_texture().get_image()
	var path := "%s/frame_%02d.png" % [OUT_DIR, index]
	var error := image.save_png(path)
	var snapshot: Dictionary = (
		_screen.get_entry_snapshot() if is_instance_valid(_screen) else {}
	)
	print(
		"PROBE_SHOT %d t=%.2f save=%s started=%s ended=%s"
		% [index, _elapsed, error_string(error), snapshot.get("started"), snapshot.get("movie_ended")]
	)


func _on_finished() -> void:
	_done = true
	print("PROBE_TRANSITION_FINISHED at t=%.2f" % _elapsed)
	await RenderingServer.frame_post_draw
	if is_inside_tree():
		get_viewport().get_texture().get_image().save_png("%s/frame_99_after.png" % OUT_DIR)
	get_tree().quit(0)


func _exit_tree() -> void:
	pass
