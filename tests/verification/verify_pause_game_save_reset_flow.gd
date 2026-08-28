extends Node
## ESC暂停页的全档复位专项。全部磁盘操作只使用测试路径。

const TEST_PATH := "user://pause_game_save_reset_probe.json"
const PAUSE_SCENE: PackedScene = preload(
	"res://assets/art/ui/pause_3d/ui_pause_overlay_screen_v001.tscn"
)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	var original_force_failure: bool = BaseManager.force_save_failure_for_test
	_cleanup_test_files()
	BaseManager.save_path = TEST_PATH
	BaseManager.force_save_failure_for_test = false
	BaseManager.data = BaseData.new()
	BaseManager.data.total_runs = 9
	BaseManager.data.tutorial_completed = true
	BaseManager.data.extraction_points = 777
	BaseManager.data.avatar_customization = {"body": "suit_cobalt", "hat": "hard_hat"}
	BaseManager.data.active_run_snapshot = {
		"valid": true,
		"checkpoint_id": "reset_probe",
	}
	if not BaseManager.save_base("reset_probe_seed"):
		failures.append("不能建立复位专项测试档")
	BaseManager.data.total_runs = 10
	BaseManager.save_base("reset_probe_backup")
	var revision_before_reset := BaseManager.data.save_revision
	var reset_result := BaseManager.reset_game_save()
	if not bool(reset_result.get("success", false)):
		failures.append("BaseManager拒绝复位合法测试档：%s" % reset_result)
	if (
		BaseManager.data.total_runs != 0
		or BaseManager.data.tutorial_completed
		or BaseManager.data.extraction_points != 0
		or not BaseManager.data.avatar_customization.is_empty()
		or not BaseManager.data.active_run_snapshot.is_empty()
		or not is_zero_approx(BaseManager.data.world_time_elapsed_game_seconds)
		or not is_equal_approx(BaseManager.data.base_energy_current, 100.0)
		or BaseManager.data.save_revision <= revision_before_reset
	):
		failures.append("复位后内存BaseData不是全新默认值，或修订号发生回退")
	if not FileAccess.file_exists(TEST_PATH) or FileAccess.file_exists(TEST_PATH + ".bak"):
		failures.append("复位后主档不存在或旧备份仍可回滚")
	var persisted: Variant = AtomicJsonStore.load_dictionary(TEST_PATH)
	var unpacked: Dictionary = (
		ProfileSaveService.unpack(persisted as Dictionary)
		if persisted is Dictionary else {}
	)
	var payload := unpacked.get("payload", {}) as Dictionary
	if (
		not bool(unpacked.get("success", false))
		or str(unpacked.get("reason", "")) != "game_save_reset"
		or int(payload.get("total_runs", -1)) != 0
		or bool(payload.get("tutorial_completed", true))
		or not (payload.get("active_run_snapshot", {}) as Dictionary).is_empty()
		or int(unpacked.get("revision", -1)) <= revision_before_reset
	):
		failures.append("磁盘中的新封套不是可回读且修订号单调递增的全新档案")

	BaseManager.data.total_runs = 4
	BaseManager.force_save_failure_for_test = true
	var failed_reset := BaseManager.reset_game_save()
	if bool(failed_reset.get("success", true)) or BaseManager.data.total_runs != 4:
		failures.append("强制写盘失败时没有保留复位前内存档案")
	BaseManager.force_save_failure_for_test = false

	var pause := PAUSE_SCENE.instantiate() as PauseMenu3D
	add_child(pause)
	await get_tree().process_frame
	var reset_button := pause.get_node_or_null(
		"Center/Panel/Margin/MainPage/ResetGameSaveButton"
	) as Button
	var confirm_dialog := pause.get_node_or_null("ResetGameSaveDialog") as ConfirmationDialog
	if reset_button == null or confirm_dialog == null:
		failures.append("ESC暂停Prefab缺少复位按钮或二次确认框")
	else:
		pause.set_paused(true)
		reset_button.pressed.emit()
		if not confirm_dialog.visible:
			failures.append("点击复位按钮没有打开二次确认")
		if not pause.try_consume_pause_input() or confirm_dialog.visible:
			failures.append("确认框打开时Esc没有先取消确认")
		pause.set_paused(false)
	pause.queue_free()
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	BaseManager.force_save_failure_for_test = original_force_failure
	_cleanup_test_files()
	await get_tree().process_frame
	if failures.is_empty():
		print("PAUSE_GAME_SAVE_RESET_OK: reusable ESC button, confirmation gate, fresh validated profile, no stale backup, graphics preserved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("PAUSE_GAME_SAVE_RESET_FAIL: %s" % failure)
	get_tree().quit(1)


func _cleanup_test_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
