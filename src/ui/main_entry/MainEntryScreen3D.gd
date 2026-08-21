class_name MainEntryScreen3D
extends CanvasLayer
## 启动页覆盖在真实游戏场景上：先用玩家当前外观做近景，点击开始后把
## 同一台 Camera3D 插值回玩法姿态，不切换场景、不复制角色。

signal start_requested()
signal transition_finished()
signal camera_override_changed(active: bool)

const Persistence = preload("res://src/player3d/customization/AvatarCustomizationPersistence.gd")
const CLOSEUP_HEIGHT_M := 1.42
const CLOSEUP_DISTANCE_M := 3.10
const CLOSEUP_FOV := 33.0
const TRANSITION_DURATION_S := 1.15
const INTRO_SPOTLIGHT_HEIGHT_M := 5.2

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
var _gameplay_hud: CanvasLayer = null
var _gameplay_hud_previous_visible := true
var _gameplay_hud_prepared := false
var _intro_spotlight: SpotLight3D = null


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
	_prepare_gameplay_hud_if_needed()
	Persistence.apply_saved_to_player(_player)
	_gameplay_camera_transform = gameplay_transform if gameplay_transform != Transform3D.IDENTITY else _camera.transform
	_gameplay_fov = gameplay_fov if gameplay_fov > 0.0 else _camera.fov
	_previous_input_locked = _player.input_locked
	# 输入锁只禁止移动、战斗和交互；Player3D仍按视口鼠标位置刷新aim_yaw，
	# 让开场近景中的真实角色继续跟随鼠标转向。
	_player.set_input_locked(true)
	_place_camera_in_front_of_player()
	_camera.fov = CLOSEUP_FOV
	_closeup_transform = _camera.transform
	_presenting = true
	_transitioning = false
	_transition_elapsed = 0.0
	screen.visible = true
	screen.modulate = Color.WHITE
	transition_hint.visible = false
	_install_intro_spotlight()
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
	_remove_intro_spotlight()
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
		"gameplay_hud_hidden": _gameplay_hud != null and not _gameplay_hud.visible,
		"intro_spotlight_active": _intro_spotlight != null and is_instance_valid(_intro_spotlight),
		"camera_on_avatar_front": _is_camera_on_avatar_front(),
		"avatar_follows_mouse": true,
	}


func prepare_gameplay_hud(gameplay_hud: CanvasLayer) -> void:
	if gameplay_hud == null or not is_instance_valid(gameplay_hud):
		return
	_gameplay_hud = gameplay_hud
	if not _gameplay_hud_prepared:
		_gameplay_hud_previous_visible = gameplay_hud.visible
		_gameplay_hud_prepared = true
	gameplay_hud.visible = false


func _auto_present() -> void:
	var player := get_tree().get_first_node_in_group("player_3d") as Player3D
	if player == null or not present(player):
		_restore_gameplay_hud()


func _finish_transition() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.transform = _gameplay_camera_transform
		_camera.fov = _gameplay_fov
	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(_previous_input_locked)
	_presenting = false
	_transitioning = false
	_remove_intro_spotlight()
	_restore_gameplay_hud()
	screen.visible = false
	screen.modulate = Color.WHITE
	camera_override_changed.emit(false)
	transition_finished.emit()


func _exit_tree() -> void:
	_remove_intro_spotlight()
	_restore_gameplay_hud()


func _place_camera_in_front_of_player() -> void:
	if _player == null or _camera == null:
		return
	var front := _get_avatar_front_direction()
	_camera.global_position = (
		_player.global_position
		+ Vector3.UP * CLOSEUP_HEIGHT_M
		+ front * CLOSEUP_DISTANCE_M
	)
	_camera.look_at(_player.global_position + Vector3.UP * 0.70, Vector3.UP)


func _get_avatar_front_direction() -> Vector3:
	var front := Vector3(0.0, 0.0, -1.0)
	if _player != null and _player.avatar != null and _player.avatar.visual_root != null:
		front = -_player.avatar.visual_root.global_basis.z
	front.y = 0.0
	return front.normalized() if front.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)


func _is_camera_on_avatar_front() -> bool:
	if _player == null or _camera == null:
		return false
	var player_to_camera := _camera.global_position - _player.global_position
	player_to_camera.y = 0.0
	if player_to_camera.length_squared() <= 0.0001:
		return false
	return player_to_camera.normalized().dot(_get_avatar_front_direction()) >= 0.98


func _prepare_gameplay_hud_if_needed() -> void:
	if _gameplay_hud == null and get_parent() != null:
		_gameplay_hud = get_parent().get_node_or_null("HUD") as CanvasLayer
	if _gameplay_hud != null and not _gameplay_hud_prepared:
		prepare_gameplay_hud(_gameplay_hud)


func _restore_gameplay_hud() -> void:
	if _gameplay_hud != null and is_instance_valid(_gameplay_hud) and _gameplay_hud_prepared:
		_gameplay_hud.visible = _gameplay_hud_previous_visible
	_gameplay_hud_prepared = false


func _install_intro_spotlight() -> void:
	_remove_intro_spotlight()
	if _player == null or not is_instance_valid(_player) or get_parent() == null:
		return
	_intro_spotlight = SpotLight3D.new()
	_intro_spotlight.name = "MainEntryCharacterSpotlight"
	_intro_spotlight.light_color = Color(0.82, 0.91, 1.0)
	_intro_spotlight.light_energy = 7.0
	_intro_spotlight.light_indirect_energy = 0.0
	_intro_spotlight.spot_range = 8.0
	_intro_spotlight.spot_angle = 34.0
	_intro_spotlight.spot_angle_attenuation = 1.4
	_intro_spotlight.shadow_enabled = true
	_intro_spotlight.set_meta("main_entry_only", true)
	get_parent().add_child(_intro_spotlight)
	_intro_spotlight.global_position = _player.global_position + Vector3.UP * INTRO_SPOTLIGHT_HEIGHT_M
	_intro_spotlight.rotation_degrees = Vector3(-90.0, 0.0, 0.0)


func _remove_intro_spotlight() -> void:
	if _intro_spotlight != null and is_instance_valid(_intro_spotlight):
		_intro_spotlight.queue_free()
	_intro_spotlight = null


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
