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

## 开场页展示灯的冷白色，光柱与地面光斑都取同一个值。
## 三处必须同色，否则会看出「光柱是一层、角色是另一层」。
const INTRO_LIGHT_COLOR := Color(0.82, 0.91, 1.0)

## —— 舞台光柱与地面光斑 ——
## 已有的 SpotLight3D 把 light_cull_mask 限死在 PLAYER 层（见 _install_intro_spotlight），
## 地板完全不参与受光，所以地面**永远不会**出现光斑，也没有可看见的光柱。
## 这里补的两件都是「画出来的」，不新增任何 Light3D，因此不会污染基地既有布光：
##   1) StageBeam 圆锥：叠加混合、自上而下渐隐，补出可见光柱
##   2) StagePool 圆盘：叠加混合的径向渐变，补出地面光斑
## 与 WastelandLight3D 的 LightPool 同一套做法（unshaded + 叠加 + 不投影）。
##
## 尺寸口径：角色高 1.5m，光斑半径取 1.55m ⇒ 直径 3.1m ≈ 2× 角色高。
## 光柱底半径取同一个 1.55m，锥面正好收在光斑边缘，两者不会错位。
const STAGE_POOL_RADIUS_M := 1.40
## 光斑抬离地面 2cm：既避免与地板 Z-fighting，又不会在脚下穿帮。
const STAGE_POOL_LIFT_M := 0.02
## 光柱顶端收到 9cm，锥顶正好落在展示灯位置（高 5.2m），不会戳穿天花板。
const STAGE_BEAM_APEX_RADIUS_M := 0.09
## 强度刻意压低：这是「看得见的光」，不是照明。拉高会盖掉角色自身的布光。
const STAGE_BEAM_STRENGTH := 0.13
const STAGE_POOL_STRENGTH := 0.42

## 光柱：沿局部高度做双向渐隐（顶端大面积消失，看起来像从黑暗里打下来），
## 中心给出亮芯、边缘削软 —— 只做均匀叠加会变成一块「灰色塑料片」，
## 有芯才有体积光的层次。越靠下越浓，模拟贴近地面时的散射。
## blend_add 是这套假体积光的核心：它只「加亮」背景，不需要任何真实光源照亮地板。
const STAGE_BEAM_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(0.82, 0.91, 1.0, 1.0);
uniform float beam_strength : hint_range(0.0, 1.0) = 0.14;
uniform float beam_height = 5.2;
uniform float top_fade : hint_range(0.0, 1.0) = 0.55;
uniform float bottom_fade : hint_range(0.0, 0.5) = 0.22;

varying float height_ratio;

void vertex() {
	height_ratio = clamp(VERTEX.y / beam_height + 0.5, 0.0, 1.0);
}

void fragment() {
	// 上下都要化掉：底部硬切会在地面留下一条直边，整根光柱看着像纸片。
	// 底部提前消散，由地面光斑接手"被照亮"的观感。
	float vertical = smoothstep(0.0, bottom_fade, height_ratio)
		* (1.0 - smoothstep(1.0 - top_fade, 1.0, height_ratio));
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	// 边缘压到 15%：锥面是真实网格，正对视线处若不衰减，轮廓会画出一条硬边，
	// 看起来像半透明塑料壳而不是光。
	float edge = 1.0 - smoothstep(0.35, 1.0, rim) * 0.85;
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(vertical * edge * beam_strength, 0.0, 1.0);
}
"""

## 地面光斑：径向渐变，中心实、边缘完全化掉。用 PlaneMesh 的 0..1 UV 算半径，
## 不用圆柱端盖 —— 端盖 UV 的映射口径不稳定，换网格就会错位。
## 中心保留一段近实心区（pool_core），这样脚下一圈是明确的"被照亮"，
## 而不是一团糊开的亮雾。
const STAGE_POOL_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 pool_color : source_color = vec4(0.82, 0.91, 1.0, 1.0);
uniform float pool_strength : hint_range(0.0, 1.0) = 0.30;
uniform float pool_core : hint_range(0.0, 0.9) = 0.06;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float radius = clamp(length(centered), 0.0, 1.0);
	float falloff = 1.0 - smoothstep(pool_core, 1.0, radius);
	ALBEDO = pool_color.rgb;
	ALPHA = falloff * pool_strength;
}
"""

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
## 舞台光柱与地面光斑的容器：只在这个界面存在，进游戏时随展示灯一起释放。
var _intro_stage: Node3D = null

## 当前活着的入口界面实例。进游戏后本节点不会被释放（只隐藏 screen），
## 所以游戏内仍能通过 get_active_entry() 拿到它、随时把舞台灯开回来。
static var _active_entry: MainEntryScreen3D = null
var _saved_camera_attributes: CameraAttributes = null
var _presentation_attributes: CameraAttributesPractical = null
var _settings: PauseMenu3D = null
var _settings_original_parent: Node = null
var _settings_original_index := -1
var _settings_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_active_entry = self
	screen.visible = false
	start_button.pressed.connect(start_game)
	settings_button.pressed.connect(_open_settings)
	# 启动页的标题、按钮与菜单壳全部自绘：声明豁免，避免被任何批量皮肤
	# 重新套上矩形描边与底色（会在按钮/面板背后露出一圈多余边框）。
	set_meta("ui_style_exempt", true)
	_apply_prism_entry_style()
	if auto_present_when_player_found:
		call_deferred("_auto_present")


## 启动页棱镜化：品牌字标与两个按钮走 Control._draw 自绘（见 EntryBrand / EntryNeonButton），
## 这里只负责把文字件、分隔线与压暗层收进「棱镜线框」口径。
## 节点路径与 signal 一字未动（verify_expedition_resume_entry 断言 StartButton / SettingsButton 存在）。
func _apply_prism_entry_style() -> void:
	var backdrop := screen.get_node_or_null("Backdrop") as ColorRect
	if backdrop != null:
		# 冷蓝压暗而非纯黑：保留右侧 3D 角色与天台云海的冷调。
		backdrop.color = Color(
			UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 0.46
		)
	# 菜单壳保持 StyleBoxEmpty（只承担布局）：棱镜语言不画卡片。
	var eyebrow := screen.get_node_or_null("MenuPanel/Margin/Content/Eyebrow") as Label
	if eyebrow != null:
		UIStyleFactory.apply_prism_label(eyebrow, "label", 4, 15)
	var subtitle := screen.get_node_or_null("MenuPanel/Margin/Content/Subtitle") as Label
	if subtitle != null:
		UIStyleFactory.apply_prism_label(subtitle, "faint", 3, 16)
	var hint := screen.get_node_or_null("MenuPanel/Margin/Content/Hint") as Label
	if hint != null:
		UIStyleFactory.apply_prism_label(hint, "faint", 1, 13)
	var rule := screen.get_node_or_null("MenuPanel/Margin/Content/Rule") as HSeparator
	if rule != null:
		rule.add_theme_stylebox_override("separator", UIStyleFactory.make_prism_separator_style(0.24))
	if transition_hint != null:
		UIStyleFactory.apply_prism_label(transition_hint, "value", 2, 17)


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
		"intro_stage_active": _intro_stage != null and is_instance_valid(_intro_stage),
		"intro_stage_beam_active": _intro_stage != null and is_instance_valid(_intro_stage) \
			and _intro_stage.get_node_or_null("StageBeam") != null,
		"intro_stage_pool_active": _intro_stage != null and is_instance_valid(_intro_stage) \
			and _intro_stage.get_node_or_null("StagePool") != null,
		"intro_stage_pool_radius_m": STAGE_POOL_RADIUS_M,
		# 光柱/光斑都是可见几何，容器里不允许出现 Light3D —— 否则会真的照亮基地。
		"intro_stage_light_count": _count_stage_lights(),
		# 开关状态：登录页展示期为 true；进游戏默认 false，之后可随时再开。
		"stage_light_enabled": is_stage_light_enabled(),
		"stage_light_toggleable": true,
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
	if _active_entry == self:
		_active_entry = null


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
	_intro_spotlight.light_color = INTRO_LIGHT_COLOR
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
	_build_intro_stage()


## 舞台光柱 + 地面光斑。两者都是可见几何而非光照，只在本界面存在。
## 直接挂在角色节点下：落地校正、站上台面都由父子关系自动跟随，不需要每帧同步。
##
## 返回是否建成。可反复调用（内部先清旧的），因此它同时是「开关」的开的那一半：
## 登录页展示期自动开一次，进游戏时关闭销毁，之后任何时候都能再调它开回来。
func _build_intro_stage() -> bool:
	var owner_player := _resolve_stage_light_owner()
	if owner_player == null:
		return false
	_remove_intro_stage()
	_intro_stage = Node3D.new()
	_intro_stage.name = "MainEntryStageLight"
	_intro_stage.set_meta("main_entry_only", true)
	owner_player.add_child(_intro_stage)
	# 光柱：底半径 = 光斑半径，锥顶收在 9cm 并落在展示灯的高度上。
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = STAGE_BEAM_APEX_RADIUS_M
	beam_mesh.bottom_radius = STAGE_POOL_RADIUS_M
	beam_mesh.height = INTRO_SPOTLIGHT_HEIGHT_M
	beam_mesh.radial_segments = 32
	beam_mesh.rings = 1
	# 去掉两端封盖：加了盖会在锥底铺出一整块实心圆，光斑就变成叠了两层。
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.name = "StageBeam"
	beam.mesh = beam_mesh
	beam.material_override = _make_stage_beam_material()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_intro_stage.add_child(beam)
	# 玩家节点原点即脚底，光柱竖直居中立在脚下。
	beam.position = Vector3(0.0, INTRO_SPOTLIGHT_HEIGHT_M * 0.5, 0.0)
	# 光斑：PlaneMesh 默认就躺在 XZ 平面、法线朝上，不需要旋转。
	var pool_mesh := PlaneMesh.new()
	pool_mesh.size = Vector2(STAGE_POOL_RADIUS_M, STAGE_POOL_RADIUS_M) * 2.0
	var pool := MeshInstance3D.new()
	pool.name = "StagePool"
	pool.mesh = pool_mesh
	pool.material_override = _make_stage_pool_material()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_intro_stage.add_child(pool)
	pool.position = Vector3(0.0, STAGE_POOL_LIFT_M, 0.0)
	return true


## 舞台灯挂在谁身上。优先用展示期记下的玩家；进游戏后那个引用可能已随场景重建失效，
## 就回退到当前在树的 player_3d —— 这样「游戏内随时开」也能挂到活着的角色上。
func _resolve_stage_light_owner() -> Player3D:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	if not is_inside_tree():
		return null
	var fallback := get_tree().get_first_node_in_group("player_3d") as Player3D
	return fallback if fallback != null and is_instance_valid(fallback) else null


## ——— 舞台灯开关（供登录页与游戏内共用） ———
## 开：立即重建光柱与光斑，挂在当前角色身上。
## 关：立即从树上摘除并释放，不留任何可能漏光的残留节点。
## 这两个方法是本功能的唯一入口，不在 _process 里做任何状态轮询。
func set_stage_light_enabled(enabled: bool) -> bool:
	if not enabled:
		_remove_intro_stage()
		return true
	return _build_intro_stage()


func is_stage_light_enabled() -> bool:
	return _intro_stage != null and is_instance_valid(_intro_stage)


func toggle_stage_light() -> bool:
	return set_stage_light_enabled(not is_stage_light_enabled())


## 供游戏内调用：拿到当前活着的那个主界面实例。
## MainEntryScreen3D 在进入游戏后不会被释放（只把 screen 隐藏），所以这个句柄一直有效；
## 真正的入口界面不存在时返回 null，调用方据此判定「本局没有可用的舞台灯宿主」。
static func get_active_entry() -> MainEntryScreen3D:
	if _active_entry != null and is_instance_valid(_active_entry):
		return _active_entry
	return null


func _make_stage_beam_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = STAGE_BEAM_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("beam_color", INTRO_LIGHT_COLOR)
	material.set_shader_parameter("beam_strength", STAGE_BEAM_STRENGTH)
	material.set_shader_parameter("beam_height", INTRO_SPOTLIGHT_HEIGHT_M)
	return material


func _make_stage_pool_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = STAGE_POOL_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("pool_color", INTRO_LIGHT_COLOR)
	material.set_shader_parameter("pool_strength", STAGE_POOL_STRENGTH)
	return material


## 光柱/光斑容器里应有的真实光源数量永远是 0：它们靠叠加混合自发光，
## 一旦容器里混进 Light3D，就会开始真的照亮基地 —— 这条是给验收用的判据。
func _count_stage_lights() -> int:
	if _intro_stage == null or not is_instance_valid(_intro_stage):
		return 0
	var count := 0
	for node in _intro_stage.find_children("*", "Light3D", true, false):
		count += 1
	return count


func _remove_intro_spotlight() -> void:
	_remove_intro_stage()
	if _intro_spotlight != null and is_instance_valid(_intro_spotlight):
		_intro_spotlight.queue_free()
		_intro_spotlight = null
	if _intro_face_fill != null and is_instance_valid(_intro_face_fill):
		_intro_face_fill.queue_free()
		_intro_face_fill = null


## 只清舞台光柱/光斑，不动那两盏展示用真实灯。
## 先从父节点摘除再 queue_free：queue_free 是帧末才真正释放，
## 同一帧内重新开灯会出现两个同名节点并存，摘除能保证视觉上不闪、也不重名。
func _remove_intro_stage() -> void:
	if _intro_stage != null and is_instance_valid(_intro_stage):
		var parent := _intro_stage.get_parent()
		if parent != null:
			parent.remove_child(_intro_stage)
		_intro_stage.queue_free()
	_intro_stage = null


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
