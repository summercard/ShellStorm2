class_name InteractionDot3D
extends MeshInstance3D
## 统一的 3D 交互提示「圆点」。
##
## 设计契约（2026-10-02 主人指定）：
## - **常驻**：可交互对象始终挂着这个圆点，不依赖玩家是否靠近。
## - **接近变清晰**：距离越近，圆点越大、越不透明；近处叠加缓慢的「放大呼吸」。
## - **进度用圆环**：需要读条的交互（搜索容器）在圆点外圈画一圈，圈满即完成。
## - **完成/触发有反馈**：圈满或交互成功时播放一次「放大脉冲」。
##
## 位置由 PlayerInteractionController3D 每帧写入锚点世界坐标；本组件只负责表现。
## `top_level = true`：脱离 provider 的缩放（BaseFacility3D 会整体缩到 0.7），
## 否则圆点尺寸会随宿主缩放漂移。

const DOT_SEGMENTS := 40
const RING_SEGMENTS := 48

## 圆盘几何半径（米）。缩放倍率 1.0 即此尺寸。
##
## 尺寸标定依据（别凭手感改）：本作窗口 1280x720，塔内相机高 10.719m、后拉 4.038m、
## FOV 65°（见 TowerDescent3D 的 CAMERA_* 常量）。交互物常挂在地面上方 ~1.5m，
## 镜头到它的**视轴深度**约 10.7m，于是屏幕比例 ≈ 52.6 px/m。
## 直径 0.38m → 几何 20px，实测渲染 20.5px、带呼吸时 22px、`FAR_SCALE` 下 11.6px。
## 这个尺寸在真实机位下读得清、又不至于盖住它旁边的货箱和门。改之前先拍
## tests/verification/probe_interaction_dot_visual.tscn 复核。
const DOT_RADIUS_M := 0.19
## 圆环比圆盘外扩一档，留出干净的缝隙；环带本身 0.07m ≈ 3.7px。
const RING_OUTER_RADIUS_M := 0.315
const RING_INNER_RADIUS_M := 0.245
## 圆盘径向剖面：中心实心核 → 两档柔和收边。
## 不写成「中心 → 边缘」一根线插值：那样整块都是半透明，看起来像雾不像点。
## 收边必须留：本项目图形档位最低一档 MSAA 是关的，硬边会出锯齿。
const DISC_CORE_ALPHA := 1.0
const DISC_RING_RATIOS := [0.62, 0.88, 1.0]
const DISC_RING_ALPHAS := [1.0, 0.72, 0.0]
## 圆环起点：从 12 点方向开始，顺时针推进。
const RING_START_ANGLE := PI * 0.5

## 距离 → 清晰度映射：<= NEAR 全清晰，>= FAR 只剩 FAR_SCALE / FAR_ALPHA。
const NEAR_DISTANCE_M := 3.2
const FAR_DISTANCE_M := 16.0
const FAR_SCALE := 0.5
const FAR_ALPHA := 0.22
const NEAR_ALPHA := 0.95

## 放大呼吸：2.4 秒一个周期，幅度 ±12%；只在清晰度够高（也就是玩家确实靠近）时启用。
const BREATH_PERIOD_S := 2.4
const BREATH_AMPLITUDE := 0.12
const BREATH_MIN_CLARITY := 0.35

## 聚焦（当前优先级最高的可交互对象）额外放大。
const FOCUS_SCALE_MULT := 1.16

## 完成/触发的一次性放大脉冲。
const PULSE_DURATION_S := 0.34
const PULSE_PEAK_SCALE := 1.65

const VISIBLE_FADE_SPEED := 6.0
const CLARITY_SMOOTH_SPEED := 9.0
const FOCUS_SMOOTH_SPEED := 12.0
const RING_REBUILD_EPSILON := 0.004

## 聚焦时在圆点下方显示按键符。不想要键位提示就把这里关掉。
const SHOW_KEY_HINT := true
const KEY_HINT_TEXT := "E"
const KEY_HINT_FONT_SIZE := 34
const KEY_HINT_PIXEL_SIZE := 0.0105
## 压到圆盘下方：半径 0.19 之外再留 0.26 的呼吸位。
const KEY_HINT_OFFSET_Y := -0.45

var accent_color: Color = UIPalette.NEON_CYAN

var _dot_material: StandardMaterial3D
var _key_label: Label3D
var _ring_instance: MeshInstance3D

var _breath_time := 0.0
var _clarity := 0.0
var _focus_amount := 0.0
## 从 0 起：圆点随第一次 update_state 淡入，不会在生成那一帧闪一下。
var _visible_amount := 0.0
var _visible_target := 1.0
var _pulse_time := 0.0

var _progress_active := false
var _progress := 0.0
var _ring_built_progress := -1.0
var _ring_hold := false

var _last_applied_scale := 1.0
var _last_applied_alpha := 1.0


func _ready() -> void:
	_build()
	set_process(true)


func configure(color: Color) -> void:
	accent_color = color
	if _dot_material != null:
		_apply_tint()
	if _key_label != null:
		_key_label.modulate = accent_color.lightened(0.25)


## 由控制器每帧驱动。clarity 0..1（远→近），focused 表示当前被选中的交互目标。
func update_state(clarity: float, focused: bool, delta: float) -> void:
	var target_clarity := clampf(clarity, 0.0, 1.0)
	_clarity = lerpf(_clarity, target_clarity, minf(1.0, delta * CLARITY_SMOOTH_SPEED))
	_focus_amount = lerpf(
		_focus_amount,
		1.0 if focused else 0.0,
		minf(1.0, delta * FOCUS_SMOOTH_SPEED)
	)
	_breath_time += maxf(0.0, delta)
	_visible_amount = lerpf(
		_visible_amount, _visible_target, minf(1.0, delta * VISIBLE_FADE_SPEED)
	)
	if _pulse_time > 0.0:
		_pulse_time = maxf(0.0, _pulse_time - delta)
		# 脉冲期间即使 provider 已判定「不再可交互」，也要先把反馈播完。
		_visible_amount = maxf(_visible_amount, 0.88)
	_apply_visuals()
	_sync_key_hint()


## 常驻可见性开关（淡入淡出）。已搜索完的容器、已激活的撤离信标会关掉它。
func set_visible_state(visible_state: bool) -> void:
	_visible_target = 1.0 if visible_state else 0.0


## 读条进度。active 期间圆点外圈显示进度环；progress 首次触到 1.0 时自动播一次脉冲。
func set_progress(active: bool, progress: float) -> void:
	var clamped := clampf(progress, 0.0, 1.0)
	if active and _progress_active and clamped >= 1.0 and _progress < 1.0:
		play_confirm_pulse()
	_progress_active = active
	_progress = clamped
	if not active:
		_ring_hold = false
	elif clamped >= 1.0:
		_ring_hold = true
	_refresh_ring()


## 交互成功或读条完成时调用，播放一次「放大脉冲」。
func play_confirm_pulse() -> void:
	_pulse_time = PULSE_DURATION_S


func get_snapshot() -> Dictionary:
	return {
		"is_3d": true,
		"visible_amount": _visible_amount,
		"clarity": _clarity,
		"focus_amount": _focus_amount,
		"scale_multiplier": _last_applied_scale,
		"alpha": _last_applied_alpha,
		"pulsing": _pulse_time > 0.0,
		"ring_visible": _ring_instance != null and is_instance_valid(_ring_instance) and _ring_instance.visible,
		"ring_progress": _progress,
		"world_position": global_position,
		"dot_radius_m": DOT_RADIUS_M,
	}


func _apply_visuals() -> void:
	var base_scale := lerpf(FAR_SCALE, 1.0, _clarity)
	var breath := 1.0
	if _clarity > BREATH_MIN_CLARITY:
		var amount := (_clarity - BREATH_MIN_CLARITY) / (1.0 - BREATH_MIN_CLARITY)
		breath = 1.0 + sin(_breath_time * TAU / BREATH_PERIOD_S) * BREATH_AMPLITUDE * amount
	var focus_scale := lerpf(1.0, FOCUS_SCALE_MULT, _focus_amount)
	var pulse_scale := 1.0
	if _pulse_time > 0.0:
		var progress_norm := 1.0 - (_pulse_time / PULSE_DURATION_S)
		pulse_scale = 1.0 + (PULSE_PEAK_SCALE - 1.0) * sin(progress_norm * PI)
	var multiplier := base_scale * breath * focus_scale * pulse_scale
	_last_applied_scale = multiplier
	_apply_placement(multiplier)
	var alpha := lerpf(FAR_ALPHA, NEAR_ALPHA, _clarity)
	alpha = maxf(alpha, lerpf(alpha, 1.0, _focus_amount))
	if _pulse_time > 0.0:
		alpha = maxf(alpha, 1.0)
	alpha *= _visible_amount
	_last_applied_alpha = alpha
	_apply_tint()
	if _visible_amount <= 0.001 and _pulse_time <= 0.0:
		visible = false
	else:
		visible = true


## 朝向相机的朝向 + 缩放，一起写进节点 transform。
##
## ⚠️ 不要把这件事交回 `BaseMaterial3D.billboard_mode`：着色器里的 billboard 会把模型基
## 向量**归一化**，于是 node.scale 被整个丢掉 —— 实测 scale_multiplier 从 1.071 掉到 0.500
## （2.1 倍），画面上圆点的渲染面积却纹丝不动（136 → 144 像素），也就是说「放大呼吸」和
## 「完成脉冲」两个动画等于不存在，而日志、AABB、visible 全都正常。
## 自己转节点则缩放照常生效。这条约束由 verify_interaction_dot_presentation 的
## 材质断言 + 缩放通道断言盯着，画面则由 probe_interaction_dot_visual 每帧复核。
##
## 顺带说明：本节点 `top_level = true`，所以 transform 就是全局 transform，
## 不受 provider 缩放（BaseFacility3D 会整体缩到 0.7）影响。
func _apply_placement(multiplier: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		# headless / 无相机时退化成不朝向相机，缩放照旧 —— 契约测试跑的就是这条路径。
		scale = Vector3.ONE * multiplier
		return
	# 相机基向量的 +Z 指向观察者，正好与圆盘正面（+Z）一致。
	var facing := camera.global_transform.basis.orthonormalized()
	transform = Transform3D(facing.scaled(Vector3.ONE * multiplier), global_position)


func _apply_tint() -> void:
	var alpha := _last_applied_alpha
	if _dot_material != null:
		var color := accent_color
		color.a = alpha
		# 聚焦时向白偏一点，让「当前目标」在多个圆点里跳出来。
		if _focus_amount > 0.0:
			color = color.lerp(Color(1.0, 1.0, 1.0, alpha), _focus_amount * 0.35)
			color.a = alpha
		_dot_material.albedo_color = color
		_dot_material.emission = color
	if _ring_instance != null and is_instance_valid(_ring_instance):
		var ring_material := _ring_instance.material_override as StandardMaterial3D
		if ring_material != null:
			var ring_color := accent_color.lightened(0.2)
			ring_color.a = alpha
			ring_material.albedo_color = ring_color
			ring_material.emission = ring_color


func _sync_key_hint() -> void:
	if not SHOW_KEY_HINT:
		return
	# 读条期间不显示按键牌：玩家已经在按了，而且它会压到进度环上（实测重叠 6px）。
	var ring_showing := _progress_active or _ring_hold
	var want := _focus_amount > 0.35 and _visible_amount > 0.35 and not ring_showing
	if not want and _key_label == null:
		return
	var label := _ensure_key_label()
	label.visible = want
	if want:
		var color := accent_color.lightened(0.3)
		color.a = clampf(_focus_amount, 0.0, 1.0)
		label.modulate = color


func _refresh_ring() -> void:
	var show_ring := (_progress_active or _ring_hold) and _progress > 0.0001
	if not show_ring:
		if _ring_instance != null:
			_ring_instance.visible = false
		_ring_built_progress = -1.0
		return
	var ring := _ensure_ring()
	if ring == null:
		return
	ring.visible = true
	if absf(_ring_built_progress - _progress) < RING_REBUILD_EPSILON:
		return
	_ring_built_progress = _progress
	ring.mesh = _build_ring_mesh(_progress)


## 进度环按需创建：绝大多数圆点整局都不会读条，没必要让它们常驻一个 MeshInstance3D。
func _ensure_ring() -> MeshInstance3D:
	if _ring_instance != null and is_instance_valid(_ring_instance):
		return _ring_instance
	_ring_instance = MeshInstance3D.new()
	_ring_instance.name = "RingProgress"
	_ring_instance.material_override = _make_material()
	_ring_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_instance.visible = false
	add_child(_ring_instance)
	# 材质随 accent 上色（_apply_tint 会读 _ring_instance）。
	_apply_tint()
	return _ring_instance


func _build() -> void:
	top_level = true
	_dot_material = _make_material()
	# 自身就是圆盘：不再套一层 Node3D，每个圆点省一个节点。
	mesh = _build_disc_mesh()
	material_override = _dot_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_apply_tint()
	# 首帧由控制器调用 update_state 决定显隐，避免未定位时在原点闪一下。
	visible = false


## 按键牌懒创建：绝大多数圆点整局都不会被聚焦，没必要让它们常驻一个 Label3D。
func _ensure_key_label() -> Label3D:
	if _key_label != null and is_instance_valid(_key_label):
		return _key_label
	_key_label = Label3D.new()
	_key_label.name = "KeyHint"
	_key_label.text = KEY_HINT_TEXT
	_key_label.font_size = KEY_HINT_FONT_SIZE
	_key_label.pixel_size = KEY_HINT_PIXEL_SIZE
	_key_label.position = Vector3(0.0, KEY_HINT_OFFSET_Y, 0.0)
	_key_label.outline_size = 6
	# 父节点已经摆成正对相机了，这里再开 billboard 只会重复劳动（还可能丢缩放）。
	_key_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_key_label.no_depth_test = true
	_key_label.visible = false
	add_child(_key_label)
	return _key_label


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	material.emission_enabled = true
	material.emission_energy_multiplier = 1.35
	material.render_priority = 3
	# 朝向由 _apply_placement() 手动摆正，**不能**用 material 的 billboard：
	# 那会把模型基向量归一化，连带吃掉 node.scale（呼吸/脉冲就没了）。
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	# 圆点是导航信息，不该被距离雾吃掉，否则「常驻」在远房间就失效了。
	# 属性名以 ClassDB 实测为准：Godot 4.6 是 disable_fog（不是 Godot 3 的 fog_enabled）。
	material.disable_fog = true
	return material


## 圆盘：中心实心核 + 同心环柔和收边，得到不依赖贴图的干净「点」。
##
## ⚠️ 绕序约定：Godot 的**正面 = 从 +Z 看顺时针**（与引擎自带 QuadMesh 一致）。
## 曾经写成逆时针，结果整块被 CULL_BACK 剔除 —— 圆点完全不渲染，屏幕上只剩按键牌。
## 这条约定由 `verify_interaction_dot_presentation` 里的绕序对齐断言盯着，别再翻回去。
func _build_disc_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	colors.append(Color(1.0, 1.0, 1.0, DISC_CORE_ALPHA))
	var ring_starts := PackedInt32Array()
	for ring_index in range(DISC_RING_RATIOS.size()):
		ring_starts.append(vertices.size())
		var radius := DOT_RADIUS_M * float(DISC_RING_RATIOS[ring_index])
		var alpha := float(DISC_RING_ALPHAS[ring_index])
		for segment in range(DOT_SEGMENTS + 1):
			var angle := TAU * float(segment) / float(DOT_SEGMENTS)
			vertices.append(Vector3(cos(angle), sin(angle), 0.0) * radius)
			colors.append(Color(1.0, 1.0, 1.0, alpha))
	var first_ring := int(ring_starts[0])
	for segment in range(DOT_SEGMENTS):
		indices.append(0)
		indices.append(first_ring + segment + 1)
		indices.append(first_ring + segment)
	for ring_index in range(DISC_RING_RATIOS.size() - 1):
		var inner := int(ring_starts[ring_index])
		var outer := int(ring_starts[ring_index + 1])
		for segment in range(DOT_SEGMENTS):
			var inner_a := inner + segment
			var inner_b := inner + segment + 1
			var outer_a := outer + segment
			var outer_b := outer + segment + 1
			# 与扇面同向（从 +Z 看顺时针）。环带绕反过一次：扇面翻正了、环带没翻，
			# 结果占 2/3 面积的环带整块被剔除，圆点只剩 0.62R 的内核 —— 直径凭空少一半，
			# 而 visible / AABB / surfaces 全都正常。
			indices.append(outer_a)
			indices.append(inner_a)
			indices.append(inner_b)
			indices.append(outer_a)
			indices.append(inner_b)
			indices.append(outer_b)
	return _make_mesh(vertices, colors, indices)


## 环形进度：从 12 点起顺时针扫过 progress 比例的圆弧，末端封口。
## 绕序同上（+Z 看顺时针）。
func _build_ring_mesh(progress: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var swept := clampf(progress, 0.0, 1.0)
	if swept <= 0.0:
		return _make_mesh(vertices, colors, indices)
	var drawn := maxf(1.0, ceil(float(RING_SEGMENTS) * swept))
	for index in range(int(drawn) + 1):
		var ratio := float(index) / drawn
		var angle := RING_START_ANGLE - TAU * swept * ratio
		# 起点与终点收一下 alpha，让圆环首尾自然淡出。
		var alpha := 1.0
		if ratio < 0.06:
			alpha = ratio / 0.06
		elif ratio > 0.94:
			alpha = (1.0 - ratio) / 0.06
		var outer := Vector3(cos(angle), sin(angle), 0.0) * RING_OUTER_RADIUS_M
		var inner := Vector3(cos(angle), sin(angle), 0.0) * RING_INNER_RADIUS_M
		vertices.append(outer)
		colors.append(Color(1.0, 1.0, 1.0, alpha))
		vertices.append(inner)
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	var segments := int(drawn)
	for index in range(segments):
		var base := index * 2
		indices.append(base)
		indices.append(base + 3)
		indices.append(base + 1)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 3)
	return _make_mesh(vertices, colors, indices)


func _make_mesh(
	vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array
) -> ArrayMesh:
	var normals := PackedVector3Array()
	for _index in range(vertices.size()):
		normals.append(Vector3(0.0, 0.0, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
