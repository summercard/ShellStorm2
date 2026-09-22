class_name SpeechBubble3D
extends Node3D
## 3D 头顶对话气泡：程序生成几何、随文字自适应大小、硬边倒角（漫画风），
## 始终正对摄像机且**不随角色转动**。
##
## 为什么程序生成而不是美术资源：
##   本工程不使用自定义 shader，材质统一走 StandardMaterial3D（全仓 .gdshader 与
##   ShaderMaterial 零命中）。气泡尺寸必须随文字变化，固定贴图会把圆角拉变形；
##   而圆角矩形是**凸多边形**，用三角扇即可精确构建，零贴图、零拉伸。
##
## 为什么不需要每帧 look_at：
##   底板两个 surface 与文字都使用 BaseMaterial3D.BILLBOARD_ENABLED，
##   朝向由渲染层按摄像机求解，**不继承父节点旋转** —— 角色转身气泡不会跟着转。
##   挂载点时只使用纯垂直偏移（0, h, 0），绕 Y 轴旋转不改变位置，因此同样零每帧代码。

signal bubble_shown(text: String)
signal bubble_hidden()

const DEFAULT_FONT_SIZE := 48
const DEFAULT_PIXEL_SIZE := 0.0055
const TEXT_PAD_X := 34.0
const TEXT_PAD_Y := 24.0
const CORNER_RADIUS := 22.0
## 描边宽度（像素）。取值要小 —— 描边是"硬边轮廓"，不是色块；
## 过粗会在短句气泡上把深色填充整块吃掉，看起来是一团青色而不是气泡。
const BORDER_WIDTH := 2.5
const CORNER_SEGMENTS := 6
const POP_FROM_SCALE := 0.88
const POP_SECONDS := 0.16
const FADE_SECONDS := 0.14

@export var bubble_scale := 1.0
@export var hold_seconds := 3.4
@export var max_lines := 3
@export_range(40, 120) var wrap_width_px := 620
@export var fill_color := Color(0.010, 0.032, 0.045, 1.0)
@export var border_color := Color(0.12, 0.66, 0.76, 1.0)
@export var text_color := Color(0.88, 0.95, 0.98, 1.0)
@export var always_on_top := false

var _panel: MeshInstance3D
var _label: Label3D
var _panel_material: StandardMaterial3D
var _fill_material: StandardMaterial3D
var _hold_left := 0.0
var _active := false
var _tween: Tween


func _ready() -> void:
	_build_nodes()
	set_visible_state(false, true)


func _process(delta: float) -> void:
	_face_camera()
	if not _active:
		return
	_hold_left -= delta
	if _hold_left <= 0.0:
		hide_bubble()


## 朝向：整体复制相机的全局 basis，底板与文字由**同一个节点变换**驱动。
##
## 为什么不用 BILLBOARD_ENABLED（实拍踩坑，2026-09-21）：
##   Label3D 的内置 billboard 与 StandardMaterial3D 的 billboard 在**不同阶段**求解，
##   物体移动时两者会差一帧 —— 玩家看到的现象是"走路时文字和底板重影"。
##   改由节点统一驱动后二者必然同步；依然全程正对摄像机，且因为这里直接覆盖为
##   相机 basis，不会继承角色旋转。
func _face_camera() -> void:
	if not visible or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(camera):
		return
	var wanted := camera.global_transform.basis
	var parent := get_parent() as Node3D
	if parent != null:
		# 折算成局部基：全局朝向 = 父基 × 局部基。
		wanted = parent.global_transform.basis.inverse() * wanted
	if transform.basis.is_equal_approx(wanted):
		return
	# ⛔ 只覆盖**局部**基（朝向），origin 绝不动 —— 位置完全交给父节点驱动。
	#
	# 这里若写成 `global_transform = Transform3D(basis, global_position)` 就会出事：
	# 读 global_position 的时机早于父节点变换刷新，于是每帧把气泡反算回**旧位置**，
	# 等于自己把父节点的位移抵消掉。实拍表现：气泡钉在原地不跟角色走，看起来一条拖尾。
	transform = Transform3D(wanted, transform.origin)


## 显示一句台词；hold < 0 时使用 hold_seconds。
func say(text: String, hold := -1.0) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		hide_bubble()
		return
	if _panel == null or _label == null:
		_build_nodes()
	_label.text = clean
	_relayout(clean)
	_hold_left = hold if hold >= 0.0 else hold_seconds
	if not _active:
		_active = true
		_play_pop_in()
	else:
		_kill_tween()
		_apply_alpha(1.0)
	set_visible_state(true, false)
	bubble_shown.emit(clean)


func hide_bubble() -> void:
	if not _active:
		return
	_active = false
	_hold_left = 0.0
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_apply_alpha, 1.0, 0.0, FADE_SECONDS)
	_tween.tween_callback(func() -> void:
		set_visible_state(false, true)
		bubble_hidden.emit()
	)


func is_bubble_active() -> bool:
	return _active


func get_bubble_text() -> String:
	return _label.text if _label != null else ""


## 供验收读取：气泡底板的实际世界宽度（米）。
func get_bubble_width_m() -> float:
	if _panel == null or _panel.mesh == null:
		return 0.0
	var aabb := _panel.mesh.get_aabb()
	return aabb.size.x * _panel.scale.x


func set_visible_state(shown: bool, immediate: bool) -> void:
	visible = shown
	if immediate:
		_apply_alpha(1.0)
		scale = Vector3.ONE * bubble_scale


func _build_nodes() -> void:
	if _panel != null:
		return
	_panel_material = _make_material(border_color, always_on_top)
	_fill_material = _make_material(fill_color, always_on_top)
	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	# 面向摄像机：材质层求解，不依赖父节点旋转。
	_panel.material_override = null
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 气泡是**贴在角色头上的 UI**，不该在世界里落投影（2026-09-22 主人要求）。
	# ⚠️ 元凶只有**底板**：`MeshInstance3D.cast_shadow` 默认 ON；
	# `Label3D` 的默认值**实测就是 OFF**（`_scratch/nar_fix/probe_default_shadow.gd`，
	# Label3D=0 / MeshInstance3D=1），所以文字那件不需要（写了也是死代码）。
	add_child(_panel)

	_label = Label3D.new()
	_label.name = "Text"
	_label.font = ThemeDB.fallback_font
	_label.font_size = DEFAULT_FONT_SIZE
	_label.outline_size = 4
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.modulate = text_color
	_label.pixel_size = DEFAULT_PIXEL_SIZE
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# alpha **裁剪**而不是 alpha 混合：同样是为了让文字走不透明管线、拿到正确的
	# 运动矢量，否则移动时 TAA 会在文字上拖出残影。
	_label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.no_depth_test = always_on_top
	_label.render_priority = 2
	_label.double_sided = true
	add_child(_label)


## 按文字实际度量重算气泡大小 —— “可大可小，按照文字缩放”。
func _relayout(text: String) -> void:
	var font: Font = _label.font
	if font == null:
		font = ThemeDB.fallback_font
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = wrap_width_px
	var text_px := font.get_multiline_string_size(
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		float(wrap_width_px),
		_label.font_size
	)
	text_px.x = minf(text_px.x, float(wrap_width_px))
	var inner_px := Vector2(
		maxf(text_px.x + TEXT_PAD_X * 2.0, TEXT_PAD_Y * 2.0 + 40.0),
		text_px.y + TEXT_PAD_Y * 2.0
	)
	var unit := _label.pixel_size * bubble_scale
	var inner := inner_px * unit
	var border := BORDER_WIDTH * unit
	var half := inner * 0.5
	var radius := minf(CORNER_RADIUS * unit, minf(half.x, half.y) * 0.9)

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		_border_band_arrays(half, border, radius)
	)
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		_fill_arrays(half, radius)
	)
	_panel.mesh = mesh
	_panel.set_surface_override_material(0, _panel_material)
	_panel.set_surface_override_material(1, _fill_material)
	_panel.scale = Vector3.ONE


## 圆角矩形轮廓点（凸多边形），顺序：右上 → 左上 → 左下 → 右下，各角逆时针扫过。
static func _rounded_rect_outline(half_size: Vector2, radius: float) -> PackedVector2Array:
	var hw := maxf(half_size.x, 0.0005)
	var hh := maxf(half_size.y, 0.0005)
	var r := clampf(radius, 0.0, minf(hw, hh))
	var corners := [
		[Vector2(hw - r, hh - r), 0.0],
		[Vector2(-hw + r, hh - r), PI * 0.5],
		[Vector2(-hw + r, -hh + r), PI],
		[Vector2(hw - r, -hh + r), PI * 1.5],
	]
	var points := PackedVector2Array()
	for corner in corners:
		var center: Vector2 = corner[0]
		var start: float = corner[1]
		for index in range(CORNER_SEGMENTS + 1):
			var angle := start + (PI * 0.5) * float(index) / float(CORNER_SEGMENTS)
			points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


## 描边环带 = 外轮廓与内轮廓之间的带状区域。
##
## 为什么是"环带"而不是"大矩形垫在下面"：
##   两种做法共用同一 mesh、同一 AABB，而透明材质的 surface 渲染顺序在
##   距离相等时并不可靠 —— 实拍过：青色描边整块盖住深色填充，气泡变成一团色块。
##   环带与填充**在几何上互不重叠**，于是任何渲染顺序都得到正确结果。
static func _border_band_arrays(inner_half: Vector2, border: float, inner_radius: float) -> Array:
	var outer := _rounded_rect_outline(inner_half + Vector2(border, border), inner_radius + border)
	var inner := _rounded_rect_outline(inner_half, inner_radius)
	var vertices := PackedVector3Array()
	for point in outer:
		vertices.append(Vector3(point.x, point.y, 0.0))
	for point in inner:
		vertices.append(Vector3(point.x, point.y, 0.0))
	var count := outer.size()
	var indices := PackedInt32Array()
	for index in range(count):
		var next := (index + 1) % count
		indices.append(index)
		indices.append(next)
		indices.append(count + next)
		indices.append(index)
		indices.append(count + next)
		indices.append(count + index)
	return _arrays(vertices, indices)


## 填充 = 内轮廓的三角扇（凸多边形从中心扇三角化）。内轮廓与环带内边界逐点同源。
static func _fill_arrays(inner_half: Vector2, inner_radius: float) -> Array:
	var inner := _rounded_rect_outline(inner_half, inner_radius)
	var vertices := PackedVector3Array()
	vertices.append(Vector3.ZERO)
	for point in inner:
		vertices.append(Vector3(point.x, point.y, 0.0))
	var count := inner.size()
	var indices := PackedInt32Array()
	for index in range(count):
		indices.append(0)
		indices.append(1 + index)
		indices.append(1 + ((index + 1) % count))
	return _arrays(vertices, indices)


static func _arrays(vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _make_material(color: Color, on_top: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# 不受光照影响：气泡是叙事 UI，不该随房间灯光明暗。
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# **不透明**渲染：透明物体不写运动矢量，TAA 会把它当静止物体、把历史帧混进来，
	# 移动时拖出一串原地淡影（2026-09-21 主人实测"每帧都在原地刷新 + 拖尾"）。
	# 气泡是盖在场景上的实心 UI，本来就不需要 alpha 混合。
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 朝向由气泡节点统一驱动（见 _face_camera），**不用材质级 billboard**：
	# 材质 billboard 与 Label3D 的内置 billboard 更新时机不同步，移动时会差一帧。
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.albedo_color = color
	material.no_depth_test = on_top
	return material


func _play_pop_in() -> void:
	_kill_tween()
	_apply_alpha(0.0)
	scale = Vector3.ONE * (bubble_scale * POP_FROM_SCALE)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector3.ONE * bubble_scale, POP_SECONDS)
	_tween.tween_method(_apply_alpha, 0.0, 1.0, POP_SECONDS)


func _apply_alpha(value: float) -> void:
	if _fill_material != null:
		var fill := fill_color
		fill.a = fill_color.a * value
		_fill_material.albedo_color = fill
	if _panel_material != null:
		var border := border_color
		border.a = border_color.a * value
		_panel_material.albedo_color = border
	if _label != null:
		var text := text_color
		text.a = text_color.a * value
		_label.modulate = text


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
