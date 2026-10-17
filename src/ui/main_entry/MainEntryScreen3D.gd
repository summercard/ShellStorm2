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

## 舞台灯颜色 —— 与靶场（TrainingRangeEnvironment3D._build_lighting）的暖光灯**同值**。
## 靶场那盏是 WastelandLight3D 的暖光档：Color(1.0, 0.58, 0.24)，能量 2.5、射程 8.5。
## 取这个值不是"随便一个橙色"：冷白叠加在冷蓝暗底上必然泛灰，
## 而靶场这盏的橙是暖色偏红，叠加后会明确读成"灯光"而不是"灰雾"。
const STAGE_LIGHT_WARM_COLOR := Color(1.0, 0.58, 0.24)

## 地面光斑的**贴片颜色**，刻意比舞台暖橙更亮。
##
## 为什么必须单独一个值：光斑材质是 unshaded，屏幕上的颜色几乎就等于 albedo 本身。
## 直接用 (1.0, 0.58, 0.24) 渲出来是 sRGB 约 (140, 87, 44) —— 一块暗棕橙，
## 看着就是"淡"。提亮只能改这个色值，改不了照明。
const STAGE_POOL_COLOR := Color(1.0, 0.82, 0.56)

## 展示用主灯颜色：**也取舞台暖色**，而不是原来的冷白。
## 原来冷白照角色、暖橙画光柱，结果是角色偏灰、只有脚下是暖的，冷暖割裂 ——
## 「光打在角色身上」在观感上不成立。改成同一色系后角色才真正站在那束光里。
## 但不用 1.0/0.58/0.24 那么纯的橙（那是发光体色，直接当照明会把角色染成橘色），
## 而是同色相提亮：保留橙的暖调，同时把 G 拉高让肤色和布料不发暗。
const INTRO_LIGHT_COLOR := Color(1.0, 0.80, 0.62)

## —— 舞台光柱与地面光斑 ——
## 已有的 SpotLight3D 把 light_cull_mask 限死在 PLAYER 层（见 _install_intro_spotlight），
## 地板完全不参与受光，所以地面**永远不会**出现光斑，也没有可看见的光柱。
## 这里补的两件都是「画出来的」，不新增任何 Light3D，因此不会污染基地既有布光。
##
## 两者刻意用**不同**的材质类型，因为它们要解决的事不一样：
##   · StageBeam 走自定义 shader 的 blend_add：需要体积感、双向渐隐，加色混合才像光。
##   · StagePool 照抄 WastelandLight3D._build_light_pool()：StandardMaterial3D
##     + unshaded + emission 0.72 + alpha 0.18。这是靶场地面光斑的**原始做法**，
##     换任何别的写法都会和靶场对不上。
##
## 尺寸口径：角色高 1.5m，光斑半径 1.40m ⇒ 直径 2.8m ≈ 1.9× 角色高。
## 光柱底半径取同一个值，锥面正好收在光斑边缘，两者不会错位。
## 地面光斑半径。光斑范围要够大才不会"看着淡" —— 之前只加亮度，中心已经很亮（峰值 113）
## 但范围窄、边缘衰减快，整体感受仍是淡。扩大范围比继续提亮有效，也不会让中心过曝。
const STAGE_POOL_RADIUS_M := 1.75
## 光柱底半径**与光斑分开**。共用同一个值会把锥体一起撑宽 —— 锥底一旦到 2.3m，
## 5.2m 高的锥在近景里会糊满整个上半屏，变成一片棕色渐变而不是一束光。
const STAGE_BEAM_BOTTOM_RADIUS_M := 1.45
## 光斑抬离地面 2cm：既避免与地板 Z-fighting，又不会在脚下穿帮。
const STAGE_POOL_LIFT_M := 0.02
## 光柱顶端收到 9cm，锥顶正好落在展示灯位置（高 5.2m），不会戳穿天花板。
const STAGE_BEAM_APEX_RADIUS_M := 0.09
## 光柱浓度。单层锥，不做多层叠加 —— 叠层会在圆柱分段处露出弧形接缝。
const STAGE_BEAM_STRENGTH := 0.230
## 光柱是否绘制。
## ⚠️ 靶场那套灯**只有地面光斑、没有光柱**（见 WastelandLight3D._build_light_pool）。
## 要跟靶场完全一致就置 false；要保留「舞台灯打下来」的锥形观感就保持 true。
const STAGE_BEAM_ENABLED := true
## 地面光斑 alpha。接近不透明：光斑的颜色几乎完全由 STAGE_POOL_COLOR 决定，
## 底层地砖只透出 4%，这样"亮"才不会被暗地板拉下去。
const STAGE_POOL_ALPHA := 0.96
## 舞台主光：真正照亮地砖的那盏 OmniLight3D（对应靶场 WastelandLight3D 的灯珠）。
## 射程比靶场 8.5m 收窄到 3.6m —— 这里是近景聚光，不是房间照明。
const STAGE_KEY_LIGHT_ENERGY := 13.0
const STAGE_KEY_LIGHT_RANGE_M := 5.0
## 灯的高度。放低到 1.1m 才有「从下往上打亮地面和小腿」的聚光感；
## 放高会变成一片均匀的环境光，舞台感全无。
const STAGE_KEY_LIGHT_HEIGHT_M := 2.15

## 收灯动画时长。要"很快但看得出来"——0.3 秒左右刚好在读成"收束"而不是"闪掉"。
const STAGE_DISMISS_DURATION_S := 0.30
## 收缩终点的缩放。不用 0：完全归零的那一帧会有跳变，留 4% 再释放更顺。
const STAGE_DISMISS_END_SCALE := 0.04

## 光柱：沿局部高度做双向渐隐（顶端大面积消失，看起来像从黑暗里打下来），
## 中心给出亮芯、边缘削软 —— 只做均匀叠加会变成一块「灰色塑料片」，
## 有芯才有体积光的层次。越靠下越浓，模拟贴近地面时的散射。
## blend_add 是这套假体积光的核心：它只「加亮」背景，不需要任何真实光源照亮地板。
const STAGE_BEAM_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.58, 0.24, 1.0);
uniform float beam_strength : hint_range(0.0, 1.0) = 0.20;
uniform float beam_height = 5.2;
uniform float top_fade : hint_range(0.0, 1.0) = 0.18;
uniform float bottom_fade : hint_range(0.0, 1.0) = 0.78;

varying float height_ratio;

void vertex() {
	height_ratio = clamp(VERTEX.y / beam_height + 0.5, 0.0, 1.0);
}

void fragment() {
	// 垂直强度：下淡上亮。
	// bottom_fade 覆盖到 55% 高度 —— 角色高 1.5m、光柱 5.2m，人物完全落在这一段里，
	// 所以人物所在区域是渐暗的，光柱不会在角色身上糊成一块。
	// top_fade 只留 18%，顶端柔和收尾但不提前衰减，视觉重心因此上移。
	float vertical = smoothstep(0.0, bottom_fade, height_ratio)
		* (1.0 - smoothstep(1.0 - top_fade, 1.0, height_ratio));
	// 伪体积散射：越靠中心越亮。用视线角做幂次衰减，
	// 掠射（画面上锥体的左右两侧）收得比正视更快，轮廓因此自然化掉。
	float cosine = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float core = pow(cosine, 1.6);
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(vertical * core * beam_strength, 0.0, 1.0);
}
"""

## 地面光斑不用着色器：直接照抄 WastelandLight3D._build_light_pool() 的做法
## （StandardMaterial3D + unshaded + emission 0.72 + alpha 0.18）。靶场那圈橙光
## 就是这么来的，换任何别的写法都会跟靶场对不上。
## 网格也用 CylinderMesh 薄片而不是 PlaneMesh —— 与靶场同一种几何。

## 开场页压暗：**中心透、四边暗**的径向渐变，而不是原来那种整块均匀压暗。
##
## 原来是一整块 alpha 0.46 的深蓝盖住全屏，等于给画面蒙一层灰 —— 实测平均饱和度
## 只有 0.226、34.4% 的像素近乎无彩，这就是"灰蒙蒙"的主要来源。
## 改成暗角后：画面中心（角色与标题所在处）几乎不压暗，四边保留压暗收边。
##
## 距离口径：把 UV 拉到 -1..1 求椭圆半径，所以四角约 1.41、四边中点约 1.0。
## inner/outer 两个半径决定"从哪儿开始暗、暗到哪儿为止"。
## 中心 0.06 / 边缘 0.46 这两个值是在真机截图上反推验证过的：
## 平均饱和度 0.226 → 0.269，无彩像素 34.4% → 27.8%。
const ENTRY_VIGNETTE_CENTER_ALPHA := 0.06
const ENTRY_VIGNETTE_EDGE_ALPHA := 0.46
const ENTRY_VIGNETTE_INNER_RADIUS := 0.25
const ENTRY_VIGNETTE_OUTER_RADIUS := 0.80

const ENTRY_VIGNETTE_SHADER_CODE := """
shader_type canvas_item;

uniform vec4 dim_color : source_color = vec4(0.031, 0.055, 0.086, 1.0);
uniform float center_alpha : hint_range(0.0, 1.0) = 0.06;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.46;
uniform float inner_radius : hint_range(0.0, 1.5) = 0.25;
uniform float outer_radius : hint_range(0.0, 1.6) = 0.80;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float radius = length(centered);
	float t = smoothstep(inner_radius, outer_radius, radius);
	COLOR = vec4(dim_color.rgb, mix(center_alpha, edge_alpha, t));
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
## 正在播放收灯动画的那个容器。它已从 _intro_stage 摘出，但仍留在树上直到动画结束；
## 单独持有引用是为了「动画中途被强制取消」时还能把它正确释放，避免泄漏一个孤儿节点。
var _dismissing_stage: Node3D = null
var _stage_dismiss_tween: Tween = null

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
		# 保留 ColorRect 本体（节点路径不变），但用它承载径向渐变材质：
		# 中心几乎不压暗、四边压到原来的 0.46，形成暗角。
		# 原来是一整块均匀 0.46 的深蓝，等于给全画面蒙一层灰，是「灰蒙蒙」的主要来源。
		backdrop.color = Color.WHITE
		backdrop.material = _make_entry_vignette_material()
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


## 开场页压暗层的径向渐变材质。中心 0.06（几乎不压暗）、四边 0.46（保持收边）。
## 颜色沿用 PRISM_DIM 的冷蓝——它现在是"边缘颜色"，不再是整屏蒙层，
## 所以既保留冷调又不会给画面灌灰。
func _make_entry_vignette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = ENTRY_VIGNETTE_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("dim_color", Color(
		UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 1.0
	))
	material.set_shader_parameter("center_alpha", ENTRY_VIGNETTE_CENTER_ALPHA)
	material.set_shader_parameter("edge_alpha", ENTRY_VIGNETTE_EDGE_ALPHA)
	material.set_shader_parameter("inner_radius", ENTRY_VIGNETTE_INNER_RADIUS)
	material.set_shader_parameter("outer_radius", ENTRY_VIGNETTE_OUTER_RADIUS)
	return material


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
	# 照角色的展示灯立刻灭（它们本来就不该进玩法），舞台光柱/光斑走收束动画。
	# 不能在这里直接 queue_free：那会在画面上变成一次硬切。
	_remove_intro_lights()
	_dismiss_intro_stage_animated()
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
	# 收灯动画可能还在演（skip_to_gameplay 会立刻走到这里）——让动画自己演完，
	# 只在没有动画时兜底硬删，保证这一步结束时一定没有残留。
	_remove_intro_lights()
	_remove_intro_stage_if_idle()
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
	_build_stage_beam_shells()
	_build_stage_pool()
	return true


## 光柱：多层嵌套锥，逐层缩小半径、共用同一浓度。
## 每层都 cull_disabled（正反面都参与叠加），加上层数叠加，
## 从侧面看就是「中心亮、边缘淡」的软柱，而不是一块均匀的三角形色块。
func _build_stage_beam_shells() -> void:
	if not STAGE_BEAM_ENABLED:
		return
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = STAGE_BEAM_APEX_RADIUS_M
	beam_mesh.bottom_radius = STAGE_BEAM_BOTTOM_RADIUS_M
	beam_mesh.height = INTRO_SPOTLIGHT_HEIGHT_M
	beam_mesh.radial_segments = 48
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
	# 玩家节点原点即脚底，锥体竖直居中。
	beam.position = Vector3(0.0, INTRO_SPOTLIGHT_HEIGHT_M * 0.5, 0.0)


## 地面光斑：照抄靶场 LightPool —— CylinderMesh 薄圆片（略带喇叭口），
## 高度只有 1.8cm，从角色视角看就是贴着地面的一块圆。
##
## ⚠️ 但 LightPool 只是靶场那圈光的**第二层**。第一层是 WastelandLight3D 里的真实
## OmniLight3D（能量 2.5、射程 8.5）真正照亮了地砖。只画 LightPool 不点灯，
## 结果是「一块贴在地上的半透明圆片」，怎么调都发灰 —— 因为它没有照亮任何东西。
## 所以下面另外补一盏 STAGE_KEY_LIGHT，两件一起才是靶场那套效果。
func _build_stage_pool() -> void:
	var pool_mesh := CylinderMesh.new()
	pool_mesh.top_radius = STAGE_POOL_RADIUS_M * 0.92
	pool_mesh.bottom_radius = STAGE_POOL_RADIUS_M
	pool_mesh.height = 0.018
	pool_mesh.radial_segments = 32
	pool_mesh.material = _make_stage_pool_material()
	var pool := MeshInstance3D.new()
	pool.name = "StagePool"
	pool.mesh = pool_mesh
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_intro_stage.add_child(pool)
	pool.position = Vector3(0.0, STAGE_POOL_LIFT_M, 0.0)
	_build_stage_key_light()


## 舞台主光：**真正照亮地面**的那一层，对应靶场 WastelandLight3D 里的 OmniLight3D。
## 这是「光斑」与「贴片」的分界线 —— 没有它，地砖的受光不会变，看起来就是一张圆纸。
##
## 它照 WORLD + PLAYER 两层：要照亮地砖就必须放开 WORLD。
## 这不会污染基地，因为本节点只在展示期存在，进游戏（三处释放点）即被销毁。
func _build_stage_key_light() -> void:
	var key_light := OmniLight3D.new()
	key_light.name = "StageKeyLight"
	key_light.light_color = STAGE_LIGHT_WARM_COLOR
	key_light.light_energy = STAGE_KEY_LIGHT_ENERGY
	key_light.light_indirect_energy = 0.0
	key_light.omni_range = STAGE_KEY_LIGHT_RANGE_M
	key_light.omni_attenuation = 1.2
	key_light.shadow_enabled = false
	key_light.light_cull_mask = (
		GameDesignConfig.RENDER_LAYER_WORLD | GameDesignConfig.RENDER_LAYER_PLAYER
	)
	key_light.set_meta("main_entry_only", true)
	_intro_stage.add_child(key_light)
	# 贴地一点：太高会变成环境光洒满全场，失去「一束打下来」的聚光感。
	key_light.position = Vector3(0.0, STAGE_KEY_LIGHT_HEIGHT_M, 0.0)


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
	material.set_shader_parameter("beam_color", STAGE_LIGHT_WARM_COLOR)
	material.set_shader_parameter("beam_strength", STAGE_BEAM_STRENGTH)
	material.set_shader_parameter("beam_height", INTRO_SPOTLIGHT_HEIGHT_M)
	return material


## 地面光斑材质。与靶场 WastelandLight3D 的 LightPool 同构：unshaded + alpha 透明。
##
## ⚠️ 不要在这里配 emission —— unshaded 材质会跳过光照阶段，而 emission 正是在
## 光照阶段累加的，所以 emission_energy_multiplier 对最终画面**毫无影响**。
## 实测把倍率从 2.7 拉到 10.0，同一区域 RGB 一个像素都没变。
## 想调亮只能改 albedo 颜色（见 STAGE_POOL_COLOR），这是唯一有效的杠杆。
func _make_stage_pool_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(
		STAGE_POOL_COLOR.r, STAGE_POOL_COLOR.g,
		STAGE_POOL_COLOR.b, STAGE_POOL_ALPHA
	)
	material.metallic = 0.0
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	_remove_intro_lights()


## 只清那两盏照角色的真实展示灯（聚光 + 面部补光），不动舞台光柱/光斑。
## 拆出来是因为「进游戏」时两者的退场方式不同：灯要立刻灭，舞台灯要收缩。
func _remove_intro_lights() -> void:
	if _intro_spotlight != null and is_instance_valid(_intro_spotlight):
		_intro_spotlight.queue_free()
		_intro_spotlight = null
	if _intro_face_fill != null and is_instance_valid(_intro_face_fill):
		_intro_face_fill.queue_free()
		_intro_face_fill = null


## 立即硬删，连收灯动画一起取消。用于「安装前清场」和「节点卸载」两条路径 ——
## 那两种情况没有下一帧可等，动画没有意义。
## 先从父节点摘除再 queue_free：queue_free 是帧末才真正释放，
## 同一帧内重新开灯会出现两个同名节点并存，摘除能保证视觉上不闪、也不重名。
func _remove_intro_stage() -> void:
	_kill_stage_dismiss_tween()
	if _intro_stage != null and is_instance_valid(_intro_stage):
		var parent := _intro_stage.get_parent()
		if parent != null:
			parent.remove_child(_intro_stage)
		_intro_stage.queue_free()
	_intro_stage = null
	if _dismissing_stage != null and is_instance_valid(_dismissing_stage):
		var dismissing_parent := _dismissing_stage.get_parent()
		if dismissing_parent != null:
			dismissing_parent.remove_child(_dismissing_stage)
		_dismissing_stage.queue_free()
	_dismissing_stage = null


## 收灯动画：锥体与地面光斑同时往中心收缩、同时变淡，然后一起消失。
##
## 为什么是「缩小 + 淡出」而不是直接删：直接删在画面上是一次硬切，
## 光柱会在一帧内凭空不见，读起来像 bug。缩到中心再淡掉才像一个动作收尾。
##
## 锥体用 XZ 缩放而不是改网格半径：CylinderMesh 是共享资源，
## 改它会影响所有实例；缩放是每个实例自己的属性。
## 缩放原点在锥体中心（本地原点是母线中点），所以底端收得比顶端快 ——
## 顶端本来就只有 9cm，视觉上就是「底下的范围收起来」。
func _dismiss_intro_stage_animated() -> bool:
	if _intro_stage == null or not is_instance_valid(_intro_stage):
		return false
	_kill_stage_dismiss_tween()
	_dismissing_stage = _intro_stage
	_intro_stage = null
	var stage := _dismissing_stage
	_stage_dismiss_tween = create_tween()
	_stage_dismiss_tween.set_parallel(true)
	_stage_dismiss_tween.set_trans(Tween.TRANS_CUBIC)
	_stage_dismiss_tween.set_ease(Tween.EASE_IN)
	_stage_dismiss_tween.tween_method(
		_apply_stage_dismiss_progress.bind(stage),
		1.0,
		0.0,
		STAGE_DISMISS_DURATION_S
	)
	_stage_dismiss_tween.chain().tween_callback(_finish_stage_dismiss.bind(stage))
	return true


## 收灯进度 t：1.0 = 完整可见，0.0 = 已收到中心。
## 缩放与亮度同步推进 —— 只缩不淡会留下一个细亮条，只淡不缩会像雾散。
func _apply_stage_dismiss_progress(t: float, stage: Node3D) -> void:
	if not is_instance_valid(stage):
		return
	var shrink := lerpf(STAGE_DISMISS_END_SCALE, 1.0, t)
	var beam := stage.get_node_or_null("StageBeam") as MeshInstance3D
	if beam != null:
		beam.scale = Vector3(shrink, 1.0, shrink)
		var beam_material := beam.material_override as ShaderMaterial
		if beam_material != null:
			beam_material.set_shader_parameter("beam_strength", STAGE_BEAM_STRENGTH * t)
	var pool := stage.get_node_or_null("StagePool") as MeshInstance3D
	if pool != null:
		pool.scale = Vector3(shrink, 1.0, shrink)
		var pool_material := pool.get_active_material(0) as StandardMaterial3D
		if pool_material != null:
			pool_material.albedo_color.a = STAGE_POOL_ALPHA * t
	var key_light := stage.get_node_or_null("StageKeyLight") as OmniLight3D
	if key_light != null:
		key_light.light_energy = STAGE_KEY_LIGHT_ENERGY * t


func _finish_stage_dismiss(stage: Node3D) -> void:
	if is_instance_valid(stage):
		stage.queue_free()
	if _dismissing_stage == stage:
		_dismissing_stage = null
	_stage_dismiss_tween = null


func _kill_stage_dismiss_tween() -> void:
	if _stage_dismiss_tween != null and _stage_dismiss_tween.is_valid():
		_stage_dismiss_tween.kill()
	_stage_dismiss_tween = null


## 动画进行中就让它演完，已经在演的时候不要硬切 ——
## 这个函数给 _finish_transition 用：那一步必须保证最终干净，但不该把动画掐掉。
func _remove_intro_stage_if_idle() -> void:
	if _dismissing_stage != null and is_instance_valid(_dismissing_stage):
		return
	_remove_intro_stage()


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
