class_name MainEntryScreen3D
extends CanvasLayer
## 启动页覆盖在真实游戏场景上：先用玩家当前外观做近景，点击开始后把
## 同一台 Camera3D 插值回玩法姿态，不切换场景、不复制角色。

signal start_requested()
signal transition_finished()
signal camera_override_changed(active: bool)

const Persistence = preload("res://src/player3d/customization/AvatarCustomizationPersistence.gd")
const CLOSEUP_LOCAL_POSITION := Vector3(0.0, 1.42, -3.10)
const CLOSEUP_FOV := 33.0
const TRANSITION_DURATION_S := 1.15

@export var auto_present_when_player_found := true

@onready var screen: Control = $Screen
@onready var title: Label = $Screen/MenuPanel/Margin/Content/Title
@onready var player_status: Label = $Screen/MenuPanel/Margin/Content/PlayerStatus
@onready var outfit_status: Label = $Screen/MenuPanel/Margin/Content/OutfitStatus
@onready var start_button: Button = $Screen/MenuPanel/Margin/Content/StartButton
@onready var transition_hint: Label = $Screen/TransitionHint

var _player: Player3D = null
var _camera: Camera3D = null
var _gameplay_camera_transform := Transform3D.IDENTITY
var _gameplay_fov := 43.0
var _closeup_transform := Transform3D.IDENTITY
var _transition_start_transform := Transform3D.IDENTITY
var _transition_start_fov := CLOSEUP_FOV
var _previous_input_locked := false
var _presenting := false
var _transitioning := false
var _transition_elapsed := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	screen.visible = false
	start_button.pressed.connect(start_game)
	UIStyleFactory.apply_tactical_tree(self)
	if auto_present_when_player_found:
		call_deferred("_auto_present")


func _process(delta: float) -> void:
	if not _presenting or _camera == null or not is_instance_valid(_camera):
		return
	if _transitioning:
		_transition_elapsed += delta
		var ratio := clampf(_transition_elapsed / TRANSITION_DURATION_S, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - ratio, 3.0)
		_camera.transform = _transition_start_transform.interpolate_with(_gameplay_camera_transform, eased)
		_camera.fov = lerpf(_transition_start_fov, _gameplay_fov, eased)
		screen.modulate.a = 1.0 - smoothstep(0.10, 0.82, ratio)
		if ratio >= 1.0:
			_finish_transition()
		return
	_camera.transform = _closeup_transform
	_camera.fov = CLOSEUP_FOV


func present(player: Player3D, gameplay_transform: Transform3D = Transform3D.IDENTITY, gameplay_fov := -1.0) -> bool:
	if player == null or not is_instance_valid(player) or player.camera == null:
		return false
	_player = player
	_camera = player.camera
	Persistence.apply_saved_to_player(_player)
	_gameplay_camera_transform = gameplay_transform if gameplay_transform != Transform3D.IDENTITY else _camera.transform
	_gameplay_fov = gameplay_fov if gameplay_fov > 0.0 else _camera.fov
	_previous_input_locked = _player.input_locked
	_player.set_input_locked(true)
	_camera.position = CLOSEUP_LOCAL_POSITION
	_camera.fov = CLOSEUP_FOV
	_camera.look_at(_player.global_position + Vector3.UP * 0.70, Vector3.UP)
	_closeup_transform = _camera.transform
	_presenting = true
	_transitioning = false
	_transition_elapsed = 0.0
	screen.visible = true
	screen.modulate = Color.WHITE
	transition_hint.visible = false
	_refresh_player_status()
	start_button.disabled = false
	start_button.grab_focus()
	camera_override_changed.emit(true)
	return true


func start_game() -> void:
	if not _presenting or _transitioning:
		return
	_transitioning = true
	_transition_elapsed = 0.0
	_transition_start_transform = _camera.transform
	_transition_start_fov = _camera.fov
	start_button.disabled = true
	transition_hint.visible = true
	start_requested.emit()


func skip_to_gameplay() -> void:
	if not _presenting:
		return
	_camera.transform = _gameplay_camera_transform
	_camera.fov = _gameplay_fov
	_finish_transition()


func is_camera_override_active() -> bool:
	return _presenting


func get_entry_snapshot() -> Dictionary:
	return {
		"presenting": _presenting,
		"transitioning": _transitioning,
		"uses_live_player": _player != null,
		"uses_gameplay_camera": _camera != null and _player != null and _camera == _player.camera,
		"transition_duration_s": TRANSITION_DURATION_S,
		"seamless_scene_change": true,
	}


func _auto_present() -> void:
	var player := get_tree().get_first_node_in_group("player_3d") as Player3D
	if player != null:
		present(player)


func _finish_transition() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.transform = _gameplay_camera_transform
		_camera.fov = _gameplay_fov
	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(_previous_input_locked)
	_presenting = false
	_transitioning = false
	screen.visible = false
	screen.modulate = Color.WHITE
	camera_override_changed.emit(false)
	transition_finished.emit()


func _refresh_player_status() -> void:
	if _player == null:
		return
	player_status.text = "角色状态  HP %d / %d" % [_player.current_hp, _player.max_hp]
	var loadout := _player.get_avatar_customization()
	outfit_status.text = "当前外观\n身体 %s · 头部 %s\n手部 %s · 脚部 %s\n帽子 %s · 眼镜 %s" % [
		str(loadout.get("body", "")), str(loadout.get("head", "")),
		str(loadout.get("hand", "")), str(loadout.get("feet", "")),
		str(loadout.get("hat", "")), str(loadout.get("glasses", "")),
	]
