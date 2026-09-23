class_name MainEntryScreen3D
extends CanvasLayer
## 启动页覆盖在真实游戏场景上：先用玩家当前外观做近景，点击开始后把
## 同一台 Camera3D 插值回玩法姿态，不切换场景、不复制角色。

signal start_requested()
signal transition_finished()
signal camera_override_changed(active: bool)

const Persistence = preload("res://src/player3d/customization/AvatarCustomizationPersistence.gd")
const CLOSEUP_HEIGHT_M := 0.30
const CLOSEUP_DISTANCE_M := 3.05
const CLOSEUP_FOV := 52.0
const CLOSEUP_CAMERA_ROLL_DEG := -7.0
## 开场页专用景深：只改「近景虚化距离」这一个值。
## 玩家相机共用的 cam_attrs_player3d_practical_v001.tres 把近景虚化设在 5.0m
## （全虚化阈值 5.0 − 2.0 = 3.0m），而开场页角色距相机仅约 3.06m，
## 恰好落进虚化区 ⇒ 角色发糊。展示期间改用本地副本改这一个值，
## 共享资源不动，玩法态视觉一字不变。
const PRESENTATION_DOF_NEAR_DISTANCE_M := 2.5
const TRANSITION_DURATION_S := 1.15
const INTRO_SPOTLIGHT_HEIGHT_M := 5.2
const INTRO_FACE_FILL_ENERGY := 2.0
const INTRO_FACE_FILL_RANGE_M := 2.6
const PRESENTATION_SOUTH_DIRECTION := Vector3(0.0, 0.0, 1.0)

@export var auto_present_when_player_found := true

@onready var screen: Control = $Screen
@onready var title: Label = $Screen/MenuPanel/Margin/Content/Title
@onready var player_status: Label = $Screen/MenuPanel/Margin/Content/PlayerStatus
@onready var outfit_status: Label = $Screen/MenuPanel/Margin/Content/OutfitStatus
@onready var start_button: Button = $Screen/MenuPanel/Margin/Content/StartButton
@onready var settings_button: Button = $Screen/MenuPanel/Margin/Content/SettingsButton
@onready var transition_hint: Label = $Screen/TransitionHint

var _player: Player3D = null
var _camera: Camera3D = null
var _gameplay_camera_transform := Transform3D.IDENTITY
var _gameplay_fov := 43.0
var _closeup_transform := Transform3D.IDENTITY
var _transition_start_transform := Transform3D.IDENTITY
var _transition_start_fov := CLOSEUP_FOV
var _previous_input_locked := false
var _saved_aim_yaw := 0.0
var _saved_visual_root_rotation := Vector3.ZERO
var _presenting := false
var _transitioning := false
var _transition_elapsed := 0.0
var _gameplay_hud: CanvasLayer = null
var _gameplay_hud_previous_visible := true
var _gameplay_hud_prepared := false
var _intro_spotlight: SpotLight3D = null
var _intro_face_fill: OmniLight3D = null
var _saved_camera_attributes: CameraAttributes = null
var _presentation_attributes: CameraAttributesPractical = null
var _settings: PauseMenu3D = null
var _settings_original_parent: Node = null
var _settings_original_index := -1
var _settings_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	screen.visible = false
	start_button.pressed.connect(start_game)
	settings_button.pressed.connect(_open_settings)
	# 启动页的标题、六边形霓虹按钮与菜单壳全部自绘：声明豁免，避免被战术皮肤
	# 重新套上矩形描边与底色（会在按钮/面板背后露出一圈多余边框）。
	set_meta("ui_style_exempt", true)
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
	# 叙事接管相机期间启动页不抢镜头：两个系统都写同一台 Camera3D，
	# 互不查询就会逐帧互相覆盖（运行时零报错，只表现为画面跳/抖）。
	if _narrative_holds_presentation():
		return
	_set_player_presentation_facing()
	_camera.transform = _closeup_transform
	_camera.fov = CLOSEUP_FOV


func present(player: Player3D, gameplay_transform: Transform3D = Transform3D.IDENTITY, gameplay_fov := -1.0) -> bool:
	if player == null or not is_instance_valid(player) or player.camera == null:
		return false
	# 同一展示会话重复 present 必须幂等；否则会把近景镜头误记成玩法镜头，
	# 结束时无法回到原视角。
	if _presenting:
		return _player == player
	_player = player
	_camera = player.camera
	_prepare_gameplay_hud_if_needed()
	Persistence.apply_saved_to_player(_player)
	_gameplay_camera_transform = gameplay_transform if gameplay_transform != Transform3D.IDENTITY else _camera.transform
	_gameplay_fov = gameplay_fov if gameplay_fov > 0.0 else _camera.fov
	_previous_input_locked = _player.input_locked
	_saved_aim_yaw = _player.aim_yaw
	_saved_visual_root_rotation = _player.avatar.visual_root.rotation
	_player.set_input_locked(true)
	_set_player_presentation_facing()
	_place_camera_in_front_of_player()
	_camera.fov = CLOSEUP_FOV
	_closeup_transform = _camera.transform
	_apply_presentation_camera_attributes()
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


func _open_settings() -> void:
	if not _presenting or _settings_open:
		return
	if _settings == null or not is_instance_valid(_settings):
		if _gameplay_hud != null:
			_settings = _gameplay_hud.get_node_or_null("PauseOverlay") as PauseMenu3D
	if _settings == null:
		push_warning("[MainEntryScreen3D] PauseOverlay not found for entry settings")
		return
	_settings_original_parent = _settings.get_parent()
	_settings_original_index = _settings.get_index()
	if not _settings.pause_changed.is_connected(_on_settings_pause_changed):
		_settings.pause_changed.connect(_on_settings_pause_changed)
	_settings.reparent(self, true)
	_settings_open = true
	_settings.open_entry_settings()


func _on_settings_pause_changed(paused: bool) -> void:
	if not _settings_open or paused:
		return
	_settings_open = false
	if _settings != null and is_instance_valid(_settings):
		_settings.close_entry_settings()
	_restore_settings_parent()
	if settings_button != null and is_instance_valid(settings_button):
		settings_button.grab_focus()


func _close_settings_if_needed() -> void:
	if _settings_open:
		_settings_open = false
		if _settings != null and is_instance_valid(_settings):
			_settings.close_entry_settings()
	_restore_settings_parent()


func _restore_settings_parent() -> void:
	if (
		_settings == null
		or not is_instance_valid(_settings)
		or _settings_original_parent == null
		or not is_instance_valid(_settings_original_parent)
	):
		return
	if _settings.get_parent() != _settings_original_parent:
		_settings.reparent(_settings_original_parent, true)
	if _settings_original_index >= 0:
		_settings_original_parent.move_child(
			_settings,
			mini(_settings_original_index, _settings_original_parent.get_child_count() - 1)
		)


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


## 叙事系统是否持有本帧的相机/输入。两个系统都要写同一台 Camera3D 与同一个
## input_locked，互不查询就会互相覆盖 —— 运行时零报错，只表现为画面错乱或
## 剧情期间玩家仍能操控。
func _narrative_holds_presentation() -> bool:
	if NarrativeDirector == null:
		return false
	var holds_camera := (
		NarrativeDirector.has_method("is_camera_override_active")
		and bool(NarrativeDirector.is_camera_override_active())
	)
	var holds_input := (
		NarrativeDirector.has_method("is_player_input_locked")
		and bool(NarrativeDirector.is_player_input_locked())
	)
	return holds_camera or holds_input


## 开场页景深：在玩家相机共用的属性资源上做一份本地副本，只改「近景虚化距离」，
## 因此玩法态使用的原资源完全不受影响。展示结束由 _restore_camera_attributes() 归还。
func _apply_presentation_camera_attributes() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _saved_camera_attributes == null:
		_saved_camera_attributes = _camera.attributes
	var source := _saved_camera_attributes as CameraAttributesPractical
	var attrs: CameraAttributesPractical
	if source != null:
		attrs = source.duplicate() as CameraAttributesPractical
	else:
		attrs = CameraAttributesPractical.new()
	attrs.dof_blur_near_distance = PRESENTATION_DOF_NEAR_DISTANCE_M
	_presentation_attributes = attrs
	_camera.attributes = attrs


func _restore_camera_attributes() -> void:
	if _camera != null and is_instance_valid(_camera) and _saved_camera_attributes != null:
		_camera.attributes = _saved_camera_attributes
	_saved_camera_attributes = null
	_presentation_attributes = null


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
		"intro_spotlight_player_only": _intro_spotlight != null \
			and is_instance_valid(_intro_spotlight) \
			and _intro_spotlight.light_cull_mask == GameDesignConfig.RENDER_LAYER_PLAYER,
		"intro_spotlight_shadow_enabled": _intro_spotlight != null \
			and is_instance_valid(_intro_spotlight) \
			and _intro_spotlight.shadow_enabled,
		"intro_face_fill_active": _intro_face_fill != null and is_instance_valid(_intro_face_fill),
		"intro_face_fill_player_only": _intro_face_fill != null \
			and is_instance_valid(_intro_face_fill) \
			and _intro_face_fill.light_cull_mask == GameDesignConfig.RENDER_LAYER_PLAYER,
		"intro_face_fill_energy": _intro_face_fill.light_energy if _intro_face_fill != null and is_instance_valid(_intro_face_fill) else 0.0,
		"camera_on_avatar_front": _is_camera_on_avatar_front(),
		"presentation_facing_south": _is_player_facing_south(),
		"camera_on_south_side": _is_camera_on_south_side(),
		"avatar_follows_mouse": false,
		"presentation_dof_near_distance": (
			_presentation_attributes.dof_blur_near_distance
			if _presentation_attributes != null and is_instance_valid(_presentation_attributes)
			else -1.0
		),
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
	_close_settings_if_needed()
	if _camera != null and is_instance_valid(_camera):
		_camera.transform = _gameplay_camera_transform
		_camera.fov = _gameplay_fov
	if _player != null and is_instance_valid(_player) and not _narrative_holds_presentation():
		# 叙事持有输入/朝向时不得顶掉：写回 _previous_input_locked 会把剧情刚拿到的锁
		# 还原成"可操控"，写回 aim_yaw/rotation 会把剧情刚摆好的朝向抹掉。
		_player.set_input_locked(_previous_input_locked)
		_player.aim_yaw = _saved_aim_yaw
		if _player.avatar != null and _player.avatar.visual_root != null:
			_player.avatar.visual_root.rotation = _saved_visual_root_rotation
	_presenting = false
	_transitioning = false
	_remove_intro_spotlight()
	_restore_camera_attributes()
	_restore_gameplay_hud()
	screen.visible = false
	screen.modulate = Color.WHITE
	camera_override_changed.emit(false)
	transition_finished.emit()


func _exit_tree() -> void:
	_close_settings_if_needed()
	# queue_free / 场景异常卸载也必须恢复玩法所有权；正常交接已把
	# _presenting 置 false，因此不会在之后重复覆盖真实玩法状态。
	if _presenting or _transitioning:
		if _camera != null and is_instance_valid(_camera):
			_camera.transform = _gameplay_camera_transform
			_camera.fov = _gameplay_fov
		if _player != null and is_instance_valid(_player):
			_player.set_input_locked(_previous_input_locked)
			_player.aim_yaw = _saved_aim_yaw
			if _player.avatar != null and _player.avatar.visual_root != null:
				_player.avatar.visual_root.rotation = _saved_visual_root_rotation
	_remove_intro_spotlight()
	_restore_camera_attributes()
	_restore_gameplay_hud()


func _place_camera_in_front_of_player() -> void:
	if _player == null or _camera == null:
		return
	_camera.global_position = (
		_player.global_position
		+ Vector3.UP * CLOSEUP_HEIGHT_M
		+ PRESENTATION_SOUTH_DIRECTION * CLOSEUP_DISTANCE_M
	)
	_camera.look_at(_player.global_position + Vector3.UP * 0.92, Vector3.UP)
	_camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(CLOSEUP_CAMERA_ROLL_DEG))


func _get_avatar_front_direction() -> Vector3:
	return PRESENTATION_SOUTH_DIRECTION


func _set_player_presentation_facing() -> void:
	if _player == null or _player.avatar == null or _player.avatar.visual_root == null:
		return
	var yaw := atan2(-PRESENTATION_SOUTH_DIRECTION.x, -PRESENTATION_SOUTH_DIRECTION.z)
	_player.aim_yaw = yaw
	_player.avatar.visual_root.rotation.y = yaw


func _is_player_facing_south() -> bool:
	if _player == null or _player.avatar == null or _player.avatar.visual_root == null:
		return false
	var facing := -_player.avatar.visual_root.global_basis.z
	facing.y = 0.0
	return facing.length_squared() > 0.0001 and facing.normalized().dot(PRESENTATION_SOUTH_DIRECTION) >= 0.98


func _is_camera_on_south_side() -> bool:
	if _player == null or _camera == null:
		return false
	var offset := _camera.global_position - _player.global_position
	offset.y = 0.0
	return offset.length_squared() > 0.0001 and offset.normalized().dot(PRESENTATION_SOUTH_DIRECTION) >= 0.98


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
	# 开场页的补光是展示专用：只照角色层，不污染基地/关卡，也不产生额外阴影。
	_intro_spotlight.light_cull_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_intro_spotlight.shadow_caster_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_intro_spotlight.shadow_enabled = false
	_intro_spotlight.set_meta("main_entry_only", true)
	get_parent().add_child(_intro_spotlight)
	_intro_spotlight.global_position = _player.global_position + Vector3.UP * INTRO_SPOTLIGHT_HEIGHT_M
	_intro_spotlight.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_intro_face_fill = OmniLight3D.new()
	_intro_face_fill.name = "MainEntryCharacterFaceFill"
	_intro_face_fill.light_color = Color(1.0, 0.86, 0.72)
	_intro_face_fill.light_energy = INTRO_FACE_FILL_ENERGY
	_intro_face_fill.light_indirect_energy = 0.0
	_intro_face_fill.omni_range = INTRO_FACE_FILL_RANGE_M
	_intro_face_fill.shadow_enabled = false
	_intro_face_fill.light_cull_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_intro_face_fill.shadow_caster_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_intro_face_fill.set_meta("main_entry_face_only", true)
	get_parent().add_child(_intro_face_fill)
	_intro_face_fill.global_position = _player.global_position + Vector3.UP * 0.84 + PRESENTATION_SOUTH_DIRECTION * 0.72


func _remove_intro_spotlight() -> void:
	if _intro_spotlight != null and is_instance_valid(_intro_spotlight):
		_intro_spotlight.queue_free()
		_intro_spotlight = null
	if _intro_face_fill != null and is_instance_valid(_intro_face_fill):
		_intro_face_fill.queue_free()
		_intro_face_fill = null


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
