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
## 打字机速度（字/秒）。与底栏 `DialogueUI.DEFAULT_CHARS_PER_SEC` 同值，
## 于是"头顶气泡"和"底栏对话"读起来是同一个语速（业主 2026-11-08：对话文字要打字机一样顺序出现）。
const DEFAULT_CHARS_PER_SEC := 30.0

@export var bubble_scale := 1.0
@export var hold_seconds := 3.4
## 打字机开关与速度。`chars_per_sec <= 0` 也等于关掉（一次性全出）。
## 关掉只影响"逐字出现的节奏"，不影响气泡尺寸/停留/淡出。
@export var typewriter_enabled := true
@export_range(0.0, 200.0, 1.0) var chars_per_sec := DEFAULT_CHARS_PER_SEC
@export var max_lines := 3
@export_range(40, 120) var wrap_width_px := 620
## 填充色。**半透明黑**（2026-11-02 业主「黑色背景半透明」）。
##
## 原来是 `Color(0.010, 0.032, 0.045, 1.0)` —— 不透明深青，压住角色时像一块死板。
## 现在 alpha 0.55：能看清身后是谁，字仍然读得清（文字走透明队列、画在底板之上，
## 见 `_build_nodes` 与 `_make_material` 的注释）。
@export var fill_color := Color(0.012, 0.018, 0.026, 0.55)
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
## 打字机进度。`_typed_chars` 是浮点：每帧按 `delta * chars_per_sec` 累加再取整，
## 否则低速档（如 12 字/秒）在低帧率下每次 `int(delta*speed)` 都舍成 0，永远打不完。
##
## ⚠️ **不能用 `Label3D.visible_characters`**（那是 2D `Label` 的属性，Label3D 没有）：
## Godot 4 的 Label3D 不支持"部分可见"，只能重写 `text` 本身。所以这里保存整句
## 与逐字前缀，每帧把前缀写回 `_label.text`，并补偿垂直居中造成的上移，
## 让文字始终从**气泡顶部**开始往下长，而不是在框中间上下对涨。
var _typing := false
var _typed_chars := 0.0
var _total_chars := 0
## 整句原文。`get_bubble_text()` 返回它（不是当前前缀）——
## "说的是哪一句"是身份，打字进度另由 `get_visible_char_count()` 表达。
var _full_text := ""
## 整句排版后的像素尺寸与每像素的世界尺寸，用于算垂直补偿。
var _full_text_px := Vector2.ZERO
var _layout_unit := 0.0055


func _ready() -> void:
	_build_nodes()
	set_visible_state(false, true)


func _process(delta: float) -> void:
	_face_camera()
	if not _active:
		return
	# 打字机：边打边停住停留计时 —— 否则长句还没打完就开始倒计时，
	# 玩家读到一半气泡自己消失。
	if _typing:
		_advance_typing(delta)
		return
	_hold_left -= delta
	if _hold_left <= 0.0:
		hide_bubble()


## 逐字推进。
func _advance_typing(delta: float) -> void:
	if _label == null:
		_typing = false
		return
	var speed := chars_per_sec if typewriter_enabled else 0.0
	if speed <= 0.0:
		_finish_typing()
		return
	var next := minf(float(_total_chars), _typed_chars + delta * speed)
	if int(next) == int(_typed_chars):
		_typed_chars = next
		return
	_typed_chars = next
	_apply_prefix()
	if _typed_chars >= float(_total_chars):
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	_typed_chars = float(_total_chars)
	_apply_prefix()


## 把"已显示的部分"写回 Label3D，并补偿垂直居中。
##
## 补偿的来历：`_relayout()` 是按**整句**定的底板高度，Label3D 又垂直居中，
## 于是只显示第一行时文字会贴在框的中间、后面几行像从中间往外涨。
## 这里把文字整体上移 `(整句高 - 当前高) / 2`，等价于"顶对齐"，
## 打完时位移归零 —— 终态与改动前完全一致。
func _apply_prefix() -> void:
	if _label == null:
		return
	var count := clampi(int(_typed_chars), 0, _full_text.length())
	if count >= _full_text.length():
		_label.text = _full_text
		_label.position = Vector3.ZERO
		return
	_label.text = _full_text.substr(0, count)
	var font: Font = _label.font
	if font == null:
		font = ThemeDB.fallback_font
	var current_px := font.get_multiline_string_size(
		_label.text, HORIZONTAL_ALIGNMENT_CENTER, float(wrap_width_px), _label.font_size
	)
	var shift_px := maxf(0.0, (_full_text_px.y - current_px.y) * 0.5)
	_label.position = Vector3(0.0, shift_px * _layout_unit, 0.0)


## 立刻显示整句（玩家按 E 跳过、或验收要读全文时用）。
func reveal_all() -> void:
	if not _typing:
		return
	_finish_typing()


func is_typing() -> bool:
	return _typing


## 已显示的字数 —— 验收用它断言"确实是一字一字出来的"，不是一次全出。
func get_visible_char_count() -> int:
	if _label == null or not _active:
		return 0
	return clampi(int(_typed_chars), 0, _total_chars)


func get_total_char_count() -> int:
	return _total_chars


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


## 改换行宽度并**按整句重排**。
##
## 直接写 `wrap_width_px` 只改了属性，底板与 `_full_text_px` 还是旧值 ——
## 打字机算垂直补偿时用的是旧整句高度，文字会偏。两者必须一起更新。
func set_wrap_width(px: int) -> void:
	wrap_width_px = maxi(40, px)
	if _full_text.is_empty():
		return
	_relayout(_full_text)
	_apply_prefix()


## 显示一句台词；hold < 0 时使用 hold_seconds。
func say(text: String, hold := -1.0) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		hide_bubble()
		return
	if _panel == null or _label == null:
		_build_nodes()
	_label.text = clean
	# 尺寸按**整句**算（`_relayout` 拿的是全文）：底板一次到位，打字过程中不再变宽。
	# 反过来做（按可见字符算）会让气泡每打一个字就跳一下尺寸，非常晃。
	_relayout(clean)
	_start_typing(clean)
	_hold_left = hold if hold >= 0.0 else hold_seconds
	if not _active:
		_active = true
		_play_pop_in()
	else:
		_kill_tween()
		_apply_alpha(1.0)
	set_visible_state(true, false)
	bubble_shown.emit(clean)


## 开始逐字显示。空串/关闭打字机/速度为 0 ⇒ 直接全显。
func _start_typing(text: String) -> void:
	_full_text = text
	_total_chars = text.length()
	_typed_chars = 0.0
	_typing = typewriter_enabled and chars_per_sec > 0.0 and _total_chars > 0
	if _label == null:
		_typing = false
		return
	if _typing:
		_apply_prefix()
	else:
		_finish_typing()


func hide_bubble() -> void:
	if not _active:
		return
	_active = false
	_hold_left = 0.0
	_typing = false
	_typed_chars = 0.0
	if _label != null:
		_label.position = Vector3.ZERO
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_apply_alpha, 1.0, 0.0, FADE_SECONDS)
	_tween.tween_callback(func() -> void:
		set_visible_state(false, true)
		bubble_hidden.emit()
	)


func is_bubble_active() -> bool:
	return _active


## 气泡里**正在说的那句**（全文，不是已显示的部分）。
##
## 刻意不返回"已显示的部分"：这是"说哪一句"的身份，被 NPC 的台词指针、
## 剧情节拍判定和既有验收（`verify_speech_bubble_3d` / `verify_base_npc_*`）
## 当作整句比对；打字进度另有 `get_visible_char_count()`。
func get_bubble_text() -> String:
	if not _full_text.is_empty():
		return _full_text
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
	_panel_material = _make_material(border_color, always_on_top, true)
	_fill_material = _make_material(fill_color, always_on_top, true)
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
	# **必须走透明队列**（2026-11-02 改）。
	#
	# 原设计用 `ALPHA_CUT_DISCARD` 让文字进不透明管线、拿正确的运动矢量，代价是
	# **不透明永远先渲染、透明永远后渲染** —— 半透明底板会把文字盖住压暗
	# （0.55 的黑叠在白字上，白字只剩 45% 亮度）。
	#
	# 现在底板是半透明，文字必须排在它之后：`ALPHA_CUT_DISABLED` 让 Label3D 进透明池，
	# 再靠 `render_priority = 2 > 底板材质的 0` 保证「先底板、后文字」。
	# TAA 拖影风险：气泡位移来自父节点、速度极低，`_face_camera` 每帧把朝向对齐相机
	# 不产生位移，实测（含 `capture_base99_npc` 走动帧）未见可辨拖影。
	_label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
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
	_full_text_px = text_px
	var inner_px := Vector2(
		maxf(text_px.x + TEXT_PAD_X * 2.0, TEXT_PAD_Y * 2.0 + 40.0),
		text_px.y + TEXT_PAD_Y * 2.0
	)
	var unit := _label.pixel_size * bubble_scale
	_layout_unit = unit
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


static func _make_material(color: Color, on_top: bool, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# 不受光照影响：气泡是叙事 UI，不该随房间灯光明暗。
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		# 半透明底板（2026-11-02 业主「黑色背景半透明」）。
		# ⚠️ 透明物体**不写运动矢量**，TAA 会把它们当静止几何混历史帧 ⇒ 移动时可能拖影。
		# 这里底板的位移来自父节点、速度很低，且文字单独在上层渲染
		# （见 `_build_nodes` 的 `ALPHA_CUT_DISABLED`），实测未出现可辨拖影。
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# 环带与内填充互不重叠，但会和文字同池排序 ⇒ 优先级压到 0，
		# 文字固定 priority 2，保证「先底板、后文字」。
		material.render_priority = 0
	else:
		# 不透明：透明物体不写运动矢量，TAA 会把它当静止物体、把历史帧混进来。
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
