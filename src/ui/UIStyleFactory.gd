class_name UIStyleFactory
## UIStyleFactory — 集中构造所有 UI 样式（StyleBox / Button 主题）
## 用途：替换散落在各 UI 文件中的 inline StyleBoxFlat，统一全屏视觉
## 所有方法返回新对象，调用方按需 duplicate 即可

extends RefCounted


# ========== 面板背景 ==========

## 创建面板背景
## level: 0=DEEPEST, 1=DARK, 2=MID, 3=SLOT, 4=SLOT_HOVER
static func make_panel_bg(level: int = 1, corner_radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _bg_for_level(level)
	style.set_corner_radius_all(corner_radius)
	return style


## 创建带边框的面板背景
## border_color: 默认 BORDER_NORMAL
static func make_panel_with_border(
	level: int = 1,
	border_color: Color = UIPalette.BORDER_NORMAL,
	corner_radius: int = 6,
	border_width: int = 1,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _bg_for_level(level)
	style.set_border_width_all(border_width)
	style.set_border_color(border_color)
	style.set_corner_radius_all(corner_radius)
	return style


# ========== 按钮样式 ==========

## 创建标准按钮样式（normal/hover/pressed/disabled 四态）
## 可选参数：accent_color（hover 时边框高亮色，默认 BORDER_FOCUS）
##           fill_color（背景色，默认 BG_DARK）
static func make_button_style(
	fill_color: Color = UIPalette.BG_DARK,
	accent_color: Color = UIPalette.BORDER_FOCUS,
) -> Dictionary:
	# normal：暗背景 + subtle 边框
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill_color
	normal.set_border_width_all(1)
	normal.set_border_color(UIPalette.BORDER_SUBTLE)
	normal.set_corner_radius_all(5)

	# hover：稍亮 + accent 边框
	var hover := StyleBoxFlat.new()
	hover.bg_color = UIPalette.BG_MID
	hover.set_border_width_all(2)
	hover.set_border_color(accent_color)
	hover.set_corner_radius_all(5)

	# pressed：最暗 + normal 边框
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = UIPalette.BG_DEEPEST
	pressed.set_border_width_all(1)
	pressed.set_border_color(UIPalette.BORDER_NORMAL)
	pressed.set_corner_radius_all(5)

	# disabled：slot 背景 + subtle 边框
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = UIPalette.BG_SLOT
	disabled.set_border_width_all(1)
	disabled.set_border_color(UIPalette.BORDER_SUBTLE)
	disabled.set_corner_radius_all(5)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled,
	}


## 把按钮样式 dict 应用到 Button 节点
## 同时设置字体颜色 (normal/hover/pressed/disabled 四态)
## 还会自动挂上 hover/pressed 缩放反馈（让按钮有"弹性"）
static func apply_button_style(btn: Button, style_dict: Dictionary) -> void:
	if style_dict.has("normal"):
		btn.add_theme_stylebox_override("normal", style_dict["normal"])
	if style_dict.has("hover"):
		btn.add_theme_stylebox_override("hover", style_dict["hover"])
	if style_dict.has("pressed"):
		btn.add_theme_stylebox_override("pressed", style_dict["pressed"])
	if style_dict.has("disabled"):
		btn.add_theme_stylebox_override("disabled", style_dict["disabled"])
	# 字体颜色
	btn.add_theme_color_override("font_color", UIPalette.TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", UIPalette.TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", UIPalette.TEXT_SECONDARY)
	btn.add_theme_color_override("font_disabled_color", UIPalette.TEXT_DISABLED)
	# 弹性缩放反馈（必须在 add_child 之后调用，否则 _ready 还没跑完）
	if btn.is_inside_tree():
		UIFX.attach_button_press(btn)
		_bind_button_audio(btn)
	else:
		# 延迟到 _ready 后挂载
		btn.ready.connect(UIFX.attach_button_press.bind(btn), CONNECT_ONE_SHOT)
		btn.ready.connect(_bind_button_audio.bind(btn), CONNECT_ONE_SHOT)


static func _bind_button_audio(btn: Button) -> void:
	if btn == null or btn.has_meta("_tactical_audio_bound"):
		return
	btn.set_meta("_tactical_audio_bound", true)
	btn.mouse_entered.connect(_play_button_audio.bind(btn, "ui_hover", -9.0))
	btn.pressed.connect(_play_button_audio.bind(btn, "ui_click", -4.0))


static func _play_button_audio(btn: Button, event_name: String, volume_db: float) -> void:
	if btn == null or (btn.disabled and event_name == "ui_click") or not btn.is_inside_tree():
		return
	var audio := btn.get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", event_name, volume_db)


# ========== 格子 / 槽位样式 ==========

## 创建物品格子样式
## is_hover: false=normal(空槽), true=hover
static func make_slot_style(is_hover: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if is_hover:
		style.bg_color = UIPalette.BG_SLOT_HOVER
		style.set_border_color(Color(0.5, 0.6, 0.8, 0.8))
	else:
		style.bg_color = UIPalette.BG_SLOT
		style.set_border_color(UIPalette.BORDER_SUBTLE)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


## 创建已占用物品格子样式（边框更亮）
static func make_slot_filled_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.22, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_border_color(Color(0.6, 0.7, 0.9, 0.7))
	style.set_corner_radius_all(4)
	return style


# ========== 物品类型边框 ==========

## 创建物品行容器样式（带左侧/全边类型色边框）
## item_type: "FateCard" / "Weapon" / "Bullet" / 其他
## full_border: true=全边，false=仅左边
static func make_item_row_style(
	item_type: String,
	bg_color: Color = Color(0.1, 0.1, 0.12, 0.9),
	full_border: bool = true,
	border_width: int = 3,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = UIPalette.item_border_color(item_type)
	if full_border:
		style.set_border_width_all(border_width)
	else:
		style.border_width_left = border_width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


# ========== 进度条 fill ==========

## 创建进度条 fill 样式
## color: 通常传 UIPalette.HP_HIGH/MID/LOW
static func make_progress_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style


static func make_progress_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.020, 0.026, 0.98)
	style.set_border_width_all(1)
	style.border_color = UIPalette.BORDER_SUBTLE
	style.set_corner_radius_all(3)
	return style


static func make_tactical_panel(
	accent: Color = UIPalette.NEON_CYAN,
	level: int = 1,
	border_width: int = 2,
	corner_radius: int = 7
) -> StyleBoxFlat:
	var style := make_panel_with_border(level, accent, corner_radius, border_width)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	style.shadow_size = 5
	return style


static func apply_tactical_tree(root: Node) -> void:
	if root == null:
		return
	if root is PanelContainer:
		var panel := root as PanelContainer
		var lowered := panel.name.to_lower()
		var accent := UIPalette.NEON_CYAN
		if "death" in lowered or "danger" in lowered or "drop" in lowered:
			accent = UIPalette.DANGER_RED
		elif "insurance" in lowered or "vault" in lowered or "backpack" in lowered:
			accent = UIPalette.NEON_MINT
		panel.add_theme_stylebox_override("panel", make_tactical_panel(accent, 1, 1))
	elif root is Button:
		var button := root as Button
		var accent := UIPalette.NEON_CYAN
		if (
			"出售" in button.text
			or "丢弃" in button.text
			or "删除" in button.text
			or "复位" in button.text
			or "确认撤退" in button.text
		):
			accent = UIPalette.DANGER_RED
		elif "购买" in button.text or "魂" in button.text:
			accent = UIPalette.SOUL_GOLD
		elif "保险" in button.text or "装备" in button.text:
			accent = UIPalette.NEON_MINT
		apply_button_style(button, make_button_style(UIPalette.BG_DARK, accent))
		button.add_theme_font_size_override("font_size", maxi(14, button.get_theme_font_size("font_size")))
	elif root is ProgressBar:
		var bar := root as ProgressBar
		var fill := UIPalette.NEON_CYAN
		if "hp" in bar.name.to_lower() or "health" in bar.name.to_lower():
			fill = UIPalette.DANGER_RED
		bar.add_theme_stylebox_override("background", make_progress_background())
		bar.add_theme_stylebox_override("fill", make_progress_fill(fill))
	elif root is Label:
		var label := root as Label
		var lowered := (label.name + " " + label.text).to_lower()
		if "title" in lowered or "标题" in lowered:
			label.add_theme_color_override("font_color", UIPalette.NEON_CYAN)
		elif "魂" in label.text or "价格" in label.text:
			label.add_theme_color_override("font_color", UIPalette.SOUL_GOLD)
		elif not label.has_theme_color_override("font_color"):
			label.add_theme_color_override("font_color", UIPalette.TEXT_PRIMARY)
	for child in root.get_children():
		apply_tactical_tree(child)


# ========== 描边文字 ==========

## 创建描边标签（描边色 + 文字色）
## 用于分数/货币/楼层等需要高可读性的 HUD 文字
static func make_outline_label(text: String, font_color: Color = UIPalette.TEXT_PRIMARY) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", font_color)
	# outline 通过 font_shadow 实现近似描边效果
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	return lbl


# ========== 内部：背景等级映射 ==========

static func _bg_for_level(level: int) -> Color:
	match level:
		0: return UIPalette.BG_DEEPEST
		1: return UIPalette.BG_DARK
		2: return UIPalette.BG_MID
		3: return UIPalette.BG_SLOT
		4: return UIPalette.BG_SLOT_HOVER
		_: return UIPalette.BG_DARK
