class_name PauseMenu3D
extends Control
## 三张 3D 游戏地图共用的暂停覆盖层。只有本节点在暂停时继续接收输入；
## 世界、AI、射弹和计时器继续遵守 Pausable，不会暗中推进。

signal pause_changed(paused: bool)

@onready var resume_button: Button = $Center/Panel/Margin/VBox/ResumeButton
@onready var dim: ColorRect = $Dim
@onready var center: CenterContainer = $Center


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	add_to_group("pause_input_guard")
	if Global != null and not Global.game_paused.is_connected(_on_global_pause_changed):
		Global.game_paused.connect(_on_global_pause_changed)
	_apply_pause_visual(Global != null and Global.has_pause_reason("manual"))
	resume_button.pressed.connect(resume_game)


func try_consume_pause_input() -> bool:
	if Global != null and Global.has_pause_reason("manual"):
		return false
	var game_root := get_parent().get_parent()
	return (
		game_root != null
		and game_root.has_method("try_close_modal_for_pause")
		and bool(game_root.call("try_close_modal_for_pause"))
	)


func set_paused(paused: bool) -> void:
	if Global != null:
		if paused:
			Global.acquire_pause("manual")
		else:
			Global.release_pause("manual")
	else:
		get_tree().paused = paused
		_on_global_pause_changed(paused)


func resume_game() -> void:
	set_paused(false)


func is_pause_open() -> bool:
	return center.visible and Global != null and Global.has_pause_reason("manual")


func _on_global_pause_changed(_paused: bool) -> void:
	var manual_paused := Global != null and Global.has_pause_reason("manual")
	_apply_pause_visual(manual_paused)
	if manual_paused:
		resume_button.grab_focus()
	pause_changed.emit(manual_paused)


func _apply_pause_visual(paused: bool) -> void:
	dim.visible = paused
	center.visible = paused
	mouse_filter = Control.MOUSE_FILTER_STOP if paused else Control.MOUSE_FILTER_IGNORE
