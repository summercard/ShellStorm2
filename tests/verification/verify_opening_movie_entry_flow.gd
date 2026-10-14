extends Node
## 开场影片入口分流验收（headless 安全）。
##
## ⚠️ 本文件**绝不允许** `load()` 那个 `.ogv`：实测 Godot 4.6 headless 下加载
## `.ogv` 会让整个进程挂死（不报错、不返回，只能被超时杀掉）。所以这里只验证
## 三件在无视频驱动时仍然成立的事：
##   1. 影片运行资产存在且非空；
##   2. 入口分流判定（新档→影片层 / 老档→主页菜单）在 headless 下可判、可断言；
##   3. 覆盖层在 headless 下**自我交接**，不遗留半接管状态。
## 真实播放与画面无缝性属于真实渲染验收，不在本用例范围内。
##
## ⚠️ 存档隔离（与 `verify_new_save_handoff` 同一口径）：本用例要构造「教程已完成」
## 的存档形态，绝不能落在开发者真实档上。所以全程把 `BaseManager.save_path` 指向
## 探针路径、`data` 换成全新 `BaseData`，结束时原样归还并删掉探针文件。

const MOVIE_PATH := "res://assets/movie/opening_mv.ogv"
const MOVIE_SCENE_PATH := "res://scenes/ui/OpeningMovieScreen3D.tscn"
const MAIN_ENTRY_SCENE_PATH := "res://scenes/ui/MainEntryScreen3D.tscn"
const PROBE_SAVE_PATH := "user://opening_movie_entry_probe.json"

var _failures: Array[String] = []
var _original_save_path := ""
var _original_data: BaseData = null


func _ready() -> void:
	_begin_isolated_profile()
	_verify_movie_asset()
	await _verify_overlay_self_aborts_in_headless()
	_verify_entry_routing()
	_verify_headless_install_early_return()
	_end_isolated_profile()
	_report()


func _begin_isolated_profile() -> void:
	_original_save_path = BaseManager.save_path
	_original_data = BaseManager.data
	_cleanup_probe_files()
	BaseManager.save_path = PROBE_SAVE_PATH
	BaseManager.data = BaseData.new()


func _end_isolated_profile() -> void:
	BaseManager.save_path = _original_save_path
	BaseManager.data = _original_data
	_cleanup_probe_files()


func _cleanup_probe_files() -> void:
	for path in [PROBE_SAVE_PATH, PROBE_SAVE_PATH + ".tmp", PROBE_SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 1. 运行资产存在且非空。只做存在性与体积检查 —— 不触发解码。
func _verify_movie_asset() -> void:
	if not ResourceLoader.exists(MOVIE_PATH):
		_failures.append("开场影片运行资产不存在：%s" % MOVIE_PATH)
		return
	var file := FileAccess.open(MOVIE_PATH, FileAccess.READ)
	if file == null:
		_failures.append("开场影片运行资产打不开：%s" % MOVIE_PATH)
		return
	if file.get_length() <= 0:
		_failures.append("开场影片运行资产为空文件：%s" % MOVIE_PATH)
	file.close()


## 2. 入口分流判定。用裸脚本实例（`TowerDescent3D.new()`）避免启动整个主场景。
func _verify_entry_routing() -> void:
	_check(
		BaseManager.save_path == PROBE_SAVE_PATH,
		"存档隔离未生效，本用例会写到开发者真实档上",
	)
	var tower := TowerDescent3D.new()
	tower.return_scene_path = GameDesignConfig.MAIN_SCENE

	# 新档冷启动：教程未完成、无运行时快照 → 走开场影片。
	BaseManager.data.tutorial_completed = false
	tower.force_new_game_opening_for_test = true
	tower.set("_entry_context", _main_entry_context())
	_check(
		bool(tower.call("_should_play_opening_movie")),
		"全新存档的冷启动判定没有选择开场影片",
	)
	_check(
		_overlay_path(tower) == MOVIE_SCENE_PATH,
		"全新存档安装的不是开场影片层，而是：%s" % _overlay_path(tower),
	)

	# 已有存档（教程已完成）：照旧进主页菜单。
	# 先把强制新档的验收钩子关掉，让判定真的落到存档进度上。
	tower.force_new_game_opening_for_test = false
	BaseManager.data.tutorial_completed = false
	_check(
		bool(tower.call("_should_play_opening_movie")),
		"教程未完成且无快照时应判为新档，实测没走开场影片",
	)
	BaseManager.data.tutorial_completed = true
	_check(
		not bool(tower.call("_should_play_opening_movie")),
		"已有存档仍被判定为需要播放开场影片",
	)
	_check(
		_overlay_path(tower) == MAIN_ENTRY_SCENE_PATH,
		"已有存档没有回到主页菜单，而是：%s" % _overlay_path(tower),
	)

	# 死亡返城：入口是 main_entry 但显式承诺落 99F，不得播开场影片。
	tower.force_new_game_opening_for_test = true
	var death := _main_entry_context()
	death["spawn_target"] = GameEntryFlow.SPAWN_BASE_99F
	tower.set("_entry_context", death)
	_check(
		not bool(tower.call("_should_play_opening_movie")),
		"死亡返城（显式落 99F）被错误判成播开场影片",
	)

	# 局内重入：入口 kind 不是 main_entry，任何覆盖层都不该出现。
	var gameplay := _main_entry_context()
	gameplay["kind"] = GameEntryFlow.KIND_GAMEPLAY
	gameplay["show_main_entry"] = false
	gameplay["reason"] = GameEntryFlow.REASON_SCENE_REENTRY
	tower.set("_entry_context", gameplay)
	_check(
		not bool(tower.call("_should_play_opening_movie")),
		"局内重入被错误判成播开场影片",
	)

	# 远征关卡：没有 98F 主人办公室，永远不播开场影片。
	tower.expedition_mode = true
	tower.set("_entry_context", _main_entry_context())
	_check(
		not bool(tower.call("_should_play_opening_movie")),
		"远征关卡被错误判成播开场影片",
	)
	tower.free()


## 3. headless 下 `_install_main_entry_screen()` 必须整体早退，
##    一个覆盖层都不装 —— 否则视频层会在无驱动环境里被创建。
func _verify_headless_install_early_return() -> void:
	var tower := TowerDescent3D.new()
	tower.force_new_game_opening_for_test = true
	tower.set("_entry_context", _main_entry_context())
	tower.call("_install_main_entry_screen")
	_check(
		tower.get("_main_entry_screen") == null,
		"headless 下塔楼仍安装了入口覆盖层",
	)
	_check(
		not bool(tower.call("is_opening_movie_active")),
		"headless 下被判定为正在放开场影片",
	)
	tower.free()


## 4. 覆盖层自身的 headless 守卫：立即交接、不启动视频、不留输入锁。
func _verify_overlay_self_aborts_in_headless() -> void:
	var scene := load(MOVIE_SCENE_PATH) as PackedScene
	if scene == null:
		_failures.append("开场影片层场景加载失败：%s" % MOVIE_SCENE_PATH)
		return
	var screen := scene.instantiate() as OpeningMovieScreen3D
	if screen == null:
		_failures.append("开场影片层不是 OpeningMovieScreen3D")
		return
	var finished_count := [0]
	screen.transition_finished.connect(func() -> void: finished_count[0] += 1)
	add_child(screen)
	# `_ready()` 是同步的：headless 下 `_abort_in_headless()` 在 add_child 期间
	# 就走完交接并 queue_free，所以快照必须**立刻**取 —— 等一帧对象已经释放了。
	var snapshot := screen.get_entry_snapshot()
	_check(finished_count[0] == 1, "headless 下开场影片层没有（或重复）发出交接信号")
	_check(bool(snapshot.get("finished", false)), "headless 下开场影片层没有结束")
	_check(not bool(snapshot.get("started", false)), "headless 下开场影片层竟然启动了视频播放")
	_check(not bool(snapshot.get("player_input_locked", false)), "headless 交接后仍锁着玩家输入")
	_check(
		not bool(snapshot.get("skip_hint_visible", false)),
		"headless 交接后仍显示跳过提示",
	)
	# 再等一帧让 queue_free 真正落地，确认层没有留在树里。
	await get_tree().process_frame
	_check(not is_instance_valid(screen) or not screen.is_inside_tree(), "headless 交接后开场影片层没有移除自己")


func _main_entry_context() -> Dictionary:
	return {
		"request_id": 0,
		"kind": GameEntryFlow.KIND_MAIN_ENTRY,
		"reason": GameEntryFlow.REASON_COLD_START,
		"spawn_target": GameEntryFlow.SPAWN_SAVED_PROGRESS,
		"show_main_entry": true,
	}


func _overlay_path(tower: TowerDescent3D) -> String:
	var scene := tower.call("_main_entry_overlay_scene") as PackedScene
	return "" if scene == null else scene.resource_path


func _report() -> void:
	if _failures.is_empty():
		print("OPENING_MOVIE_ENTRY_OK: new save plays the opening movie and lands in gameplay; existing saves keep the main menu")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
