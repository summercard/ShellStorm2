extends Control

const CARD_VIEW := preload("res://src/weapons/FateCardView.gd")
# 仅构建板空巢使用暗色卡背；不改全局卡背贴图或已刻印卡面。
const INACTIVE_BACK_INK := Color(0.24, 0.28, 0.34, 1.0)
const INACTIVE_BACK_BASE := Color(0.022, 0.030, 0.043, 1.0)
const INACTIVE_BACK_SHADER := """
shader_type canvas_item;
uniform vec4 ink_color : source_color;
uniform vec4 base_color : source_color;
varying vec4 canvas_tint;
void vertex() {
    canvas_tint = COLOR;
}
void fragment() {
    vec4 source = texture(TEXTURE, UV);
    float ink = clamp(dot(source.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.72, 0.0, 1.0);
    COLOR = vec4(mix(base_color.rgb, ink_color.rgb, ink), source.a) * canvas_tint;
}
"""
static var _inactive_material: ShaderMaterial
signal inspected(slot_index: int)
var slot_index := 0
var record: Dictionary = {}
var pending := false
var occupied := false
var next_slot := false
var compact_display := false
var _art: Control
var _face: TextureRect
var _number: Label
var _effect_brief: Label
var _branch: Label
var _hover := false

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		inspected.emit(slot_index))
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	focus_entered.connect(func() -> void:
		queue_redraw()
		inspected.emit(slot_index))
	focus_exited.connect(queue_redraw)
	resized.connect(_layout)

func configure(index: int, entry: Dictionary, card: FateCard, is_pending: bool, is_next: bool, branches: Array, compact_brief: String = "") -> void:
	slot_index = index
	record = entry.duplicate(true)
	pending = is_pending
	occupied = not entry.is_empty() and not pending
	next_slot = is_next
	tooltip_text = "%s · %s\n%s" % [card.card_name, card.orientation_name(), card.description] if occupied and card != null else ""
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_number = Label.new()
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number.text = "%02d / %s" % [index, "同步中" if pending else ("已刻印" if occupied else ("下一槽" if next_slot else "未激活"))]
	if compact_display:
		_number.text = "%02d · %s" % [index, card.orientation_name() if occupied and card != null else ("可用" if next_slot else "空槽")]
		_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		accessibility_name = "%s · %s" % [_number.text, card.card_name] if card != null else _number.text
		accessibility_description = card.description if card != null else ""
	_number.clip_text = true
	_number.add_theme_font_size_override("font_size", 11)
	_number.add_theme_color_override("font_color", UIPalette.PRISM_ACCENT if next_slot else UIPalette.PRISM_LABEL)
	add_child(_number)
	_face = null
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	if occupied and card != null:
		var texture := CARD_VIEW.art_for(card)
		var face := CARD_VIEW.build_art_layer(_art, texture, card.is_reversed(), "SocketFace")
		face.material = null
		_face = face
		CARD_VIEW.build_scope_badge(_art, card.scope, face)
		if texture == null:
			var fallback := Label.new()
			fallback.text = "%s\n%s\n牌面缺图" % [card.card_name, "逆位" if card.is_reversed() else "正位"]
			fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			fallback.add_theme_font_size_override("font_size", 11)
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_art.add_child(fallback)
	else:
		var back := CARD_VIEW.build_back_layer(_art)
		if back != null:
			back.material = _get_inactive_back_material()
	# 压暗来自去色后的灰蓝墨色，而非只把亮绿卡背变透明。
	_art.modulate.a = 0.66 if compact_display and not occupied else (1.0 if occupied or pending or next_slot else 0.72)
	_effect_brief = Label.new()
	_effect_brief.name = "EffectBrief"
	_effect_brief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effect_brief.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_effect_brief.autowrap_mode = TextServer.AUTOWRAP_OFF
	_effect_brief.max_lines_visible = 1
	_effect_brief.clip_text = true
	_effect_brief.add_theme_font_size_override("font_size", 11 if compact_display else 13)
	_effect_brief.add_theme_color_override("font_color", Color(0.95, 0.97, 0.99))
	if occupied:
		var brief := GameText.fate_effect_brief(card.get_stable_card_id(), card.is_reversed()) if card != null else ""
		_effect_brief.text = compact_brief if not compact_brief.is_empty() else brief
	_effect_brief.visible = not _effect_brief.text.is_empty()
	add_child(_effect_brief)
	_branch = Label.new()
	_branch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_branch.add_theme_font_size_override("font_size", 11)
	_branch.add_theme_color_override("font_color", Color(0.91, 0.76, 0.47))
	_branch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_branch.clip_text = true
	_branch.text = ""
	if not branches.is_empty() and occupied:
		var names: Array[String] = []
		for branch: Dictionary in branches:
			names.append(str(branch.get("display_name", "来源枪")))
		_branch.text = "来源模块 ×%d" % branches.size()
		_branch.tooltip_text = "同类共享来源 · 无逐槽映射\n" + "\n".join(names)
		_branch.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_branch)
	_layout()
	queue_redraw()

static func _get_inactive_back_material() -> ShaderMaterial:
	if _inactive_material == null:
		var shader := Shader.new()
		shader.code = INACTIVE_BACK_SHADER
		_inactive_material = ShaderMaterial.new()
		_inactive_material.shader = shader
		_inactive_material.set_shader_parameter("ink_color", INACTIVE_BACK_INK)
		_inactive_material.set_shader_parameter("base_color", INACTIVE_BACK_BASE)
	return _inactive_material

func _layout() -> void:
	if _art == null:
		return
	_number.position = Vector2(0, 0)
	_number.size = Vector2(size.x, 18)
	if compact_display:
		_art.position = Vector2(5, 19)
		_art.size = Vector2(maxf(1, size.x - 10), maxf(1, size.y - 36))
		_effect_brief.position = Vector2(0, _art.position.y + _art.size.y + 1)
		_effect_brief.size = Vector2(size.x, 16)
		return
	_art.position = Vector2(6, 22)
	var module_space := 22.0 if _branch != null and not _branch.text.is_empty() else 0.0
	# 20px 独立页脚留给作用短句，暖色分支计数再接在下面。
	_art.size = Vector2(maxf(1, size.x - 12), maxf(1, size.y - 22 - 20 - module_space - 6))
	var actual := CARD_VIEW.contained_texture_rect(_art.size, _face.texture if _face != null else CARD_VIEW.back_texture())
	_effect_brief.position = Vector2(0, _art.position.y + actual.end.y + 2)
	_effect_brief.size = Vector2(size.x, 20)
	_branch.position = Vector2(0, _effect_brief.position.y + 20)
	_branch.size = Vector2(size.x, module_space)
	_branch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_branch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func get_art_global_rect() -> Rect2:
	return _art.get_global_rect() if _art != null else get_global_rect()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		inspected.emit(slot_index)
	if event.is_action_pressed("ui_accept"):
		inspected.emit(slot_index)
		accept_event()

func _draw() -> void:
	if _art == null:
		return
	var box := Rect2(_art.position - Vector2(3, 3), _art.size + Vector2(6, 6))
	var color := UIPalette.PRISM_LINE_SOFT
	if _hover or has_focus():
		color = UIPalette.PRISM_LINE
	elif next_slot or pending:
		color = UIPalette.PRISM_ACCENT
	# 仅当前焦点使用完整四角；其余槽以短焊盘线界定。
	var arm := 10.0 if _hover or has_focus() else 5.0
	for corner in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
		var sx := 1.0 if corner.x == box.position.x else -1.0
		var sy := 1.0 if corner.y == box.position.y else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0), color, 1.5)
		draw_line(corner, corner + Vector2(0, arm * sy), color, 1.5)
	if not _branch.text.is_empty():
		var y := _branch.position.y
		var module_color := Color(0.91, 0.76, 0.47, 0.70)
		var branch_box := Rect2(Vector2(-2, y), Vector2(size.x + 4, 22))
		draw_rect(branch_box, Color(0.16, 0.13, 0.08, 0.55))
		draw_line(branch_box.position, Vector2(branch_box.end.x, y), module_color, 1.0)
		draw_line(branch_box.position, branch_box.position + Vector2(0, 9), module_color, 1.5)
		draw_line(Vector2(branch_box.end.x, y), Vector2(branch_box.end.x, y + 9), module_color, 1.5)
