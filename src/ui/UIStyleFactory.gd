class_name UIStyleFactory
## UIStyleFactory — 集中构造所有 UI 样式（StyleBox / Button 主题）
## 用途：替换散落在各 UI 文件中的 inline StyleBoxFlat，统一全屏视觉
## 所有方法返回新对象，调用方按需 duplicate 即可

extends RefCounted


## 塔罗卡框保留逆位，文字层反向补偿；装饰层再跟随卡框倒置。
## 居中枢轴随布局尺寸刷新，避免翻牌后或窗口缩放时文字偏出卡框。
static func apply_tarot_orientation(
	button: Button, face: Control, is_reversed: bool, ornament: Control = null,
) -> void:
	button.pivot_offset = button.size * 0.5
	button.rotation = PI if is_reversed else 0.0
	face.pivot_offset = face.size * 0.5
	face.rotation = -button.rotation
	if not face.has_meta("tarot_pivot_bound"):
		face.set_meta("tarot_pivot_bound", true)
		face.resized.connect(func() -> void:
			face.pivot_offset = face.size * 0.5
			face.rotation = -button.rotation
		)
	# 减少动效在首帧即揭面，初次容器排序会重置变换；排版后再同步一次。
	(func() -> void:
		if not is_instance_valid(button) or not is_instance_valid(face):
			return
		button.pivot_offset = button.size * 0.5
		face.pivot_offset = face.size * 0.5
		face.rotation = -button.rotation
		if is_instance_valid(ornament):
			ornament.pivot_offset = ornament.size * 0.5
			ornament.rotation = button.rotation
	).call_deferred()
	if not button.has_meta("tarot_pivot_bound"):
		button.set_meta("tarot_pivot_bound", true)
		button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	if ornament != null:
		ornament.pivot_offset = ornament.size * 0.5
		ornament.rotation = button.rotation
		if not ornament.has_meta("tarot_pivot_bound"):
			ornament.set_meta("tarot_pivot_bound", true)
			ornament.resized.connect(func() -> void: ornament.pivot_offset = ornament.size * 0.5)


## 简式选卡按钮把内置文字移到独立层，避免文字随 Button 倒置。
static func make_tarot_button_text(button: Button) -> Label:
	var label := Label.new()
	label.name = "TarotFaceText"
	label.text = button.text
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", button.get_theme_color("font_color"))
	label.add_theme_font_size_override("font_size", button.get_theme_font_size("font_size"))
	label.visible = false
	button.add_child(label)
	button.set_meta("tarot_face_node", label)
	return label


# ========== 面板背景 ==========
#
# ⚠️ 契约（2026-10 棱镜线框改造）：下面这些"旧名"工厂**保留原签名**，但一律产出
# 棱镜线框外观。原因：它们被 20+ 处调用，且**大部分在运行时**才创建样式
# （拖拽高亮、悬停框、提示卡、失败弹窗……）。逐调用点改写既无法穷尽运行时路径，
# 又容易在"包裹 / 装备 / 仓库"这类**只准改外观**的界面上误伤布局。
# 收口到工厂这一层，改一处即全站生效，且调用点一行不用动。
#
# content_margin 刻意**不设**（保持 StyleBoxFlat 默认 -1 ⇒ 生效值 = 边框宽度），
# 与旧实现同规格 —— 换皮不挪内容。

## 创建面板背景
## level: 0=DEEPEST, 1=DARK, 2=MID, 3=SLOT, 4=SLOT_HOVER
static func make_panel_bg(level: int = 1, corner_radius: int = 6) -> StyleBoxFlat:
	return make_prism_surface(level >= 3)


## 创建带边框的面板背景
## border_color: 默认 BORDER_NORMAL
static func make_panel_with_border(
	level: int = 1,
	border_color: Color = UIPalette.BORDER_NORMAL,
	corner_radius: int = 6,
	border_width: int = 1,
) -> StyleBoxFlat:
	var style := make_prism_surface(level >= 3)
	style.set_border_width_all(clampi(border_width, 0, 2))
	var normalized := prism_normalize_color(border_color)
	# 近白/中灰蓝的"结构线"色不要被归一化成强调蓝 —— 只有真正的语义色才着色。
	if normalized == UIPalette.PRISM_ACCENT and _is_neutral_line_color(border_color):
		normalized = UIPalette.PRISM_LINE_SOFT
	style.set_border_color(normalized)
	return style


## 判断一个颜色是不是"中性结构线"（低饱和的灰 / 蓝灰 / 近白），而不是语义色。
## 用于 make_panel_with_border 的收口：结构线一律走白线，别被渲染成强调蓝。
static func _is_neutral_line_color(color: Color) -> bool:
	var mx := maxf(color.r, maxf(color.g, color.b))
	var mn := minf(color.r, minf(color.g, color.b))
	return (mx - mn) <= 0.22 or mx < 0.45


# ========== 按钮样式 ==========

## 创建标准按钮样式（normal/hover/pressed/disabled 四态）——棱镜线框版。
## 契约：返回 dict 的键与旧版完全一致（normal/hover/pressed/disabled），
## `apply_button_style` 的用法不用改；只是外观从"圆角霓虹描边卡"变成"方角白线"。
## accent_color 保留语义 —— 出售/丢弃的 dange、购买/金币的 warn 仍可辨认。
static func make_button_style(
	fill_color: Color = UIPalette.BG_DARK,
	accent_color: Color = UIPalette.BORDER_FOCUS,
) -> Dictionary:
	var accent := prism_normalize_color(accent_color)
	var emphasized := accent != UIPalette.PRISM_TEXT and not _is_neutral_line_color(accent_color)
	if not emphasized:
		accent = UIPalette.PRISM_LINE_SOFT

	var normal := make_prism_slot_style(false)
	var hover := make_prism_slot_style(true)
	hover.border_color = accent

	var pressed := make_prism_slot_style(false)
	pressed.bg_color.a = 0.18

	var disabled := make_prism_slot_style(false)
	disabled.bg_color.a = 0.10
	disabled.border_color = UIPalette.PRISM_LINE_FAINT

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
	# 字体颜色（棱镜语义槽；按下态降一档亮度，保持"无发光"的物理感）
	btn.add_theme_color_override("font_color", UIPalette.PRISM_TEXT)
	btn.add_theme_color_override("font_hover_color", UIPalette.PRISM_TEXT)
	btn.add_theme_color_override("font_pressed_color", UIPalette.PRISM_LABEL)
	btn.add_theme_color_override("font_disabled_color", UIPalette.PRISM_TEXT_FAINT)
	btn.add_theme_font_override("font", make_prism_font(2))
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

## 创建物品格子样式（棱镜线框版）
## **契约**：与旧版一样不设 content_margin，格子尺寸与落位一像素不动 ——
## 背包 / 仓库 / 售货机带格子逻辑，只允许改外观层。
static func make_slot_style(is_hover: bool = false) -> StyleBoxFlat:
	return make_prism_slot_style(is_hover)


## 创建已占用物品格子样式（棱镜线框版：只把线提亮一档，不填充）
static func make_slot_filled_style() -> StyleBoxFlat:
	return make_prism_slot_filled_style()


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
	var style := make_prism_slot_style(false)
	style.bg_color = Color(
		UIPalette.PRISM_SURFACE.r, UIPalette.PRISM_SURFACE.g, UIPalette.PRISM_SURFACE.b,
		minf(maxf(bg_color.a, 0.0), 0.50)
	)
	style.border_color = prism_normalize_color(UIPalette.item_border_color(item_type))
	if full_border:
		style.set_border_width_all(1)
	else:
		style.set_border_width_all(0)
		style.border_width_left = maxi(2, border_width)
	return style


# ========== 进度条 fill ==========

## 创建进度条 fill 样式（棱镜：平色方角，零渐变零辉光）
## color: 通常传 UIPalette.HP_HIGH/MID/LOW —— 会被归一到棱镜语义槽
static func make_progress_fill(color: Color) -> StyleBoxFlat:
	return make_prism_progress_fill(prism_normalize_color(color))


static func make_progress_background() -> StyleBoxFlat:
	return make_prism_progress_background()


static func make_tactical_panel(
	accent: Color = UIPalette.NEON_CYAN,
	level: int = 1,
	border_width: int = 2,
	corner_radius: int = 7
) -> StyleBoxFlat:
	# 旧名保留，产出棱镜模态面板。内容边距**逐值沿用旧规格**（14/10），
	# 因为调用方（如武器改装树）是按这个内缩摆内容的。
	var style := make_prism_panel(level <= 1, -1.0)
	style.set_border_width_all(clampi(border_width, 0, 2))
	var normalized := prism_normalize_color(accent)
	style.border_color = (
		UIPalette.PRISM_LINE_SOFT if _is_neutral_line_color(accent) else normalized
	)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


static func apply_tactical_tree(root: Node) -> void:
	if root == null:
		return
	# 全自绘 UI（启动页的品牌标题 / 六边形霓虹按钮等）用该 meta 声明整棵子树豁免。
	# 子节点 _ready 先于父节点执行，这里不加豁免就会把矩形 StyleBox 重新套回按钮与面板，
	# 在自绘图形背后露出一圈多余的边框和底色。
	if root.has_meta("ui_style_exempt"):
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
		elif "购买" in button.text or "金币" in button.text:
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
		elif "金币" in label.text or "价格" in label.text:
			label.add_theme_color_override("font_color", UIPalette.SOUL_GOLD)
		elif not label.has_theme_color_override("font_color"):
			label.add_theme_color_override("font_color", UIPalette.TEXT_PRIMARY)
	for child in root.get_children():
		apply_tactical_tree(child)


# ========== 描边文字 ==========

## 创建带描边的标签（棱镜版）
## 用于分数/货币/楼层等压在实景上的 HUD 文字。
## ⚠️ 棱镜禁"投影"，但**允许描边**：HUD 底座是明亮低多边形场景，纯白字直接掉对比度，
## 描边是唯一不引入卡片/背板的可读性兜底（见棱镜规范 §4.4）。因此这里用
## `font_outline_*` 真描边，而不是上一代那种 1px 偏移的假投影。
static func make_outline_label(text: String, font_color: Color = UIPalette.PRISM_TEXT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", prism_normalize_color(font_color))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.62))
	lbl.add_theme_constant_override("outline_size", 4)
	var font := make_prism_font(1)
	if font != null:
		lbl.add_theme_font_override("font", font)
	return lbl


# ========== 内部：背景等级映射（已退役） ==========

## ⚠️ 已无调用者。原为 `make_panel_bg` / `make_panel_with_border` 的"亮度分级"取色表；
## 2026-10-17 棱镜化后，面板底色统一走 `PRISM_SURFACE / PRISM_SURFACE_SOLID`，
## "分级"由 1px 白线的明度（`PRISM_LINE / _SOFT / _FAINT`）承担，不再靠深蓝的深浅区分。
## 保留此函数只为对照旧实现；**禁止在新代码中调用**（见规范 §11 反面清单）。
static func _bg_for_level(level: int) -> Color:
	match level:
		0: return UIPalette.BG_DEEPEST
		1: return UIPalette.BG_DARK
		2: return UIPalette.BG_MID
		3: return UIPalette.BG_SLOT
		4: return UIPalette.BG_SLOT_HOVER
		_: return UIPalette.BG_DARK

## 仓储底板（背包 / 装备 / 仓库 / 售货机的面板底）。
## 名义上仍属"仓储深蓝"，2026-10-17 起外观收敛到棱镜线框：**不设 content_margin**，
## 因此格子尺寸、行列数与落位完全不变（这是"包裹/装备/仓库只改样式"的硬边界）。
static func make_inventory_surface(slot: bool = false) -> StyleBoxFlat:
	return make_prism_surface(slot)


# ======================================================================================
# 「棱镜线框」Prism Wireframe UI 样式工厂
# ======================================================================================
# 2026-10-16 业主否决「鸭科夫深蓝圆角胶囊风」，改按新参考图（明亮低多边形 + 白色棱角线框）重塑：
#   · 不画实心圆角卡片 —— 用 1px 白线 + 四角括号 + 极淡底衬界定区域；
#   · 按钮只有三类：实心近白主行动（深色字）、括号线框次行动（白字）、平红危险；
#   · 全方角（radius 0~2）、无辉光、无渐变、无投影堆叠；
#   · 排版两级：钢蓝小号弱标签 + 近白大字号强数值（字距由 FontVariation 提供）；
#   · 键帽 = 白底深字方角块；左/右切换 = 方角白线框 + 自绘折角箭头。

const _PRISM_CHECK_SIZE := 18
const _PRISM_GRABBER_SIZE := 14

static var _prism_font_cache: FontVariation = null
static var _prism_check_on_tex: ImageTexture = null
static var _prism_check_off_tex: ImageTexture = null
static var _prism_grabber_tex: ImageTexture = null
static var _prism_grabber_hl_tex: ImageTexture = null
static var _prism_blank_tex: ImageTexture = null


# ---------- 字体：字距（参考图最显著的排印特征）----------

## 取一份带字距的字体变体。参考图的大写标题字距极宽（HIDDEN / STRATOSPHERE），
## 中文同样受益：字距让长中文串产生"技术面板"的呼吸感。
## 用 ThemeDB.fallback_font 作基字，避免引入外部字体依赖。
static func make_prism_font(spacing: int = 2) -> FontVariation:
	if _prism_font_cache != null:
		return _prism_font_cache
	var base: Font = ThemeDB.fallback_font
	if base == null:
		var default_theme := ThemeDB.get_default_theme()
		if default_theme != null:
			base = default_theme.default_font
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = spacing
	variation.spacing_space = maxi(0, spacing - 1)
	_prism_font_cache = variation
	return variation


## 把 Label 套进棱镜排版体系。
## role: value(近白强数值) / label(钢蓝弱标签) / faint / accent / danger / warn / ok / ink
static func apply_prism_label(
	label: Label,
	role: String = "value",
	spacing: int = 2,
	font_size: int = 0
) -> void:
	if label == null:
		return
	var variation := make_prism_font(spacing)
	if variation != null:
		label.add_theme_font_override("font", variation)
	label.add_theme_color_override("font_color", prism_text_color(role))
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)


## 文字色语义表。与 prism_line_color 分开维护：文字与线条的对比度诉求不同。
static func prism_text_color(role: String) -> Color:
	match role:
		"label":
			return UIPalette.PRISM_LABEL
		"faint":
			return UIPalette.PRISM_TEXT_FAINT
		"accent":
			return UIPalette.PRISM_ACCENT
		"danger":
			return UIPalette.PRISM_DANGER
		"warn":
			return UIPalette.PRISM_WARN
		"ok":
			return UIPalette.PRISM_OK
		"ink":
			return UIPalette.PRISM_INK
		_:
			return UIPalette.PRISM_TEXT


## 给一棵 UI 子树内所有文本控件加一圈深色描边。
##
## 为什么需要：棱镜语言是「白线 + 白字」，玻璃般干净，但这套语言在**明亮实景**上会直接
## 掉对比度 —— 天台的白地砖、云海天空都是近白背景，白字等于看不见。暂停菜单有整屏压暗
## 兜底，常驻 HUD 没有。描边是唯一不破坏"无卡片"原则、又能保证任意背景下可读的手段。
##
## 白底键帽里的深色字反而不需要描边（会被描成一坨），暂停覆盖层自带压暗也不需要，
## 两者都在 `_prism_outline_exempt` 里排除。
static func apply_prism_outline_recursive(
	root: Node,
	size: float = 4.0,
	alpha: float = 0.62
) -> void:
	if root == null:
		return
	var outline_color := Color(0.0, 0.0, 0.0, alpha)
	for child in root.find_children("*", "Label", true, false):
		var label := child as Label
		if label == null or _prism_outline_exempt(label):
			continue
		label.add_theme_constant_override("outline_size", int(round(size)))
		label.add_theme_color_override("font_outline_color", outline_color)
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button == null or _prism_outline_exempt(button):
			continue
		button.add_theme_constant_override("outline_size", int(round(size * 0.75)))
		button.add_theme_color_override("font_outline_color", outline_color)
	for child in root.find_children("*", "RichTextLabel", true, false):
		var rich := child as RichTextLabel
		if rich == null or _prism_outline_exempt(rich):
			continue
		rich.add_theme_constant_override("outline_size", int(round(size * 0.5)))
		rich.add_theme_color_override("default_color", Color(0.949, 0.965, 0.984, 1.0))


static func _prism_outline_exempt(node: Node) -> bool:
	var current: Node = node
	while current != null:
		var node_name := String(current.name)
		if node_name.begins_with("PrismKeycap"):
			return true
		if node_name == "PauseOverlay" or node_name == "PrismConfirmModal":
			return true
		if current.has_meta("ui_style_exempt"):
			return true
		current = current.get_parent()
	return false


## 线条色语义表。highlight 用于悬停 / 聚焦态提亮。
static func prism_line_color(role: String, highlight: bool = false) -> Color:
	match role:
		"ink":
			return UIPalette.PRISM_INK
		"danger":
			return UIPalette.PRISM_DANGER
		"warn":
			return UIPalette.PRISM_WARN
		"accent":
			return UIPalette.PRISM_ACCENT
		"ok":
			return UIPalette.PRISM_OK
		"solid":
			return UIPalette.PRISM_LINE
		"faint":
			return Color(1.0, 1.0, 1.0, 0.72) if highlight else Color(1.0, 1.0, 1.0, 0.26)
		_:
			return Color(1.0, 1.0, 1.0, 0.96) if highlight else Color(1.0, 1.0, 1.0, 0.62)


# ---------- 面板：无卡片，只有极淡底衬 ----------

## 棱镜面板底衬。刻意不做边框 —— 边框交给四角括号（attach_prism_bracket_frame），
## 这样"框"与"底"解耦：底几乎不可见，框是唯一的结构语言。
## 注：content_margin 恒为 0，内边距一律由内层 MarginContainer 承担，
## 保证既有页面的像素级布局不被样式改造牵动。
static func make_prism_panel(is_modal: bool = true, fill_alpha: float = -1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UIPalette.PRISM_SURFACE_SOLID if is_modal else UIPalette.PRISM_SURFACE
	if fill_alpha >= 0.0:
		style.bg_color.a = clampf(fill_alpha, 0.0, 1.0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(2)
	style.shadow_size = 0
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


## 全透明棱镜外壳（布局职责保留，零可见像素）
static func make_prism_bare_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


## `Window` 系弹窗（`AcceptDialog` / `ConfirmationDialog`）的棱镜化外壳。
##
## 为什么单列一个函数：这类弹窗不是 `Control`，而是**独立子 Viewport**，
## 它的外观由 `panel` + `embedded_border` + `title_*` 这一组主题项共同绘制 ——
## 只覆盖 `panel` 是压不住那层系统灰底与圆角标题栏的（曾踩坑：面板仍渲染成灰色圆角窗）。
##
## 另一个坑：Godot 对嵌入式 `Window` 会**同时**绘制 `panel`（内容矩形）与
## `embedded_border`（含标题条的全窗矩形）。两者都带边框会得到
## "标题处一条线 + 内容处一个框"的**双线假象**。因此这里让 `panel` 带 1px 白线
## （就是玩家看到的那一个框），`embedded_border` 只留底色、不带线。
static func apply_prism_window_chrome(
	win: Window,
	title_font_size: int = 18,
	title_height: int = 28,
	body_font_size: int = 16
) -> void:
	if win == null:
		return
	var inner := StyleBoxFlat.new()
	inner.bg_color = UIPalette.PRISM_SURFACE_SOLID
	inner.bg_color.a = 0.94
	inner.border_color = UIPalette.PRISM_LINE_SOFT
	inner.set_border_width_all(1)
	inner.set_corner_radius_all(2)
	inner.shadow_size = 0
	inner.content_margin_left = 26.0
	inner.content_margin_right = 26.0
	# 正文要给标题栏让位。
	inner.content_margin_top = 22.0
	inner.content_margin_bottom = 20.0
	var chrome := StyleBoxFlat.new()
	chrome.bg_color = UIPalette.PRISM_SURFACE_SOLID
	chrome.bg_color.a = 0.94
	chrome.border_color = Color(0, 0, 0, 0)
	chrome.set_border_width_all(0)
	chrome.set_corner_radius_all(2)
	chrome.shadow_size = 0
	win.add_theme_stylebox_override("panel", inner)
	win.add_theme_stylebox_override("embedded_border", chrome)
	win.add_theme_stylebox_override("embedded_unfocused_border", chrome)
	win.add_theme_color_override("title_color", UIPalette.PRISM_TEXT)
	var title_font := make_prism_font(3)
	if title_font != null:
		win.add_theme_font_override("title_font", title_font)
	win.add_theme_font_size_override("title_font_size", title_font_size)
	win.add_theme_constant_override("title_height", title_height)
	win.add_theme_constant_override("title_outline_size", 0)
	win.add_theme_color_override("title_outline_modulate", Color(0, 0, 0, 0))
	# 抹掉 ✕ —— 取消钮已经承担退出职责，多一个 ✕ 只会破坏"零图标、纯排印"的语言。
	var blank := _prism_blank_texture()
	win.add_theme_icon_override("close", blank)
	win.add_theme_icon_override("close_pressed", blank)
	if win is AcceptDialog:
		var label := (win as AcceptDialog).get_label()
		if label != null:
			apply_prism_label(label, "value", 2, body_font_size)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


# ---------- 核心识别元素：四角括号选框 ----------

## 在目标控件上叠加一层自绘框：四角各一个 L 形折角，边线在中间断开。
## 这是整套设计语言的签名（对应参考图 CONTINUE 外框与选中行包围框）。
## 折角层是独立子 Control，永不抢鼠标（MOUSE_FILTER_IGNORE），只做装饰。
static func attach_prism_bracket_frame(
	target: Control,
	role: String = "ghost",
	arm: float = 16.0,
	thickness: float = 2.0,
	inset: float = 0.0
) -> Control:
	if target == null:
		return null
	var existing := target.get_node_or_null("PrismBracketFrame") as Control
	if existing != null:
		return existing
	var frame := Control.new()
	frame.name = "PrismBracketFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_meta("prism_role", role)
	frame.set_meta("prism_arm", arm)
	frame.set_meta("prism_thickness", thickness)
	frame.set_meta("prism_inset", inset)
	frame.set_meta("prism_highlight", false)
	frame.draw.connect(_draw_prism_bracket_frame.bind(frame))
	target.add_child(frame)
	# 置到最底层：括号是"结构线"，不该压在文字/图标之上（按钮的文字由按钮自身绘制，
	# 永远在子节点之下，因此按钮上的括号仍可见，只是不会盖住任何子内容）。
	target.move_child(frame, 0)
	target.mouse_entered.connect(_set_prism_frame_highlight.bind(frame, true))
	target.mouse_exited.connect(_set_prism_frame_highlight.bind(frame, false))
	target.focus_entered.connect(_set_prism_frame_highlight.bind(frame, true))
	target.focus_exited.connect(_set_prism_frame_highlight.bind(frame, false))
	target.resized.connect(frame.queue_redraw)
	return frame


## 外部手动置亮（例如整行联动高亮时由行容器调用）
static func set_prism_frame_highlight(target: Control, on: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	var frame := target.get_node_or_null("PrismBracketFrame") as Control
	if frame != null:
		_set_prism_frame_highlight(frame, on)


static func _set_prism_frame_highlight(frame: Control, on: bool) -> void:
	if frame == null or not is_instance_valid(frame):
		return
	frame.set_meta("prism_highlight", on)
	frame.queue_redraw()


static func _draw_prism_bracket_frame(frame: Control) -> void:
	if frame == null or not is_instance_valid(frame):
		return
	var box := frame.size
	if box.x < 10.0 or box.y < 10.0:
		return
	var role := str(frame.get_meta("prism_role", "ghost"))
	var highlighted := bool(frame.get_meta("prism_highlight", false))
	var arm: float = float(frame.get_meta("prism_arm", 16.0))
	var thickness: float = float(frame.get_meta("prism_thickness", 2.0))
	var inset: float = float(frame.get_meta("prism_inset", 0.0))
	var color := prism_line_color(role, highlighted)
	var half := thickness * 0.5
	var usable_arm: float = minf(arm, minf(box.x - inset * 2.0, box.y - inset * 2.0) * 0.5)
	if usable_arm <= 1.0:
		return
	var left := inset + half
	var top := inset + half
	var right := box.x - inset - half
	var bottom := box.y - inset - half
	# 左上
	frame.draw_line(Vector2(left, top), Vector2(left + usable_arm, top), color, thickness, true)
	frame.draw_line(Vector2(left, top), Vector2(left, top + usable_arm), color, thickness, true)
	# 右上
	frame.draw_line(Vector2(right, top), Vector2(right - usable_arm, top), color, thickness, true)
	frame.draw_line(Vector2(right, top), Vector2(right, top + usable_arm), color, thickness, true)
	# 左下
	frame.draw_line(Vector2(left, bottom), Vector2(left + usable_arm, bottom), color, thickness, true)
	frame.draw_line(Vector2(left, bottom), Vector2(left, bottom - usable_arm), color, thickness, true)
	# 右下
	frame.draw_line(Vector2(right, bottom), Vector2(right - usable_arm, bottom), color, thickness, true)
	frame.draw_line(Vector2(right, bottom), Vector2(right, bottom - usable_arm), color, thickness, true)


# ---------- 折角箭头 / 分割线 ----------

## 自绘折角箭头（参考图左/右切换钮与标题下方那个 ⌄）
static func make_prism_chevron(
	direction: String = "right",
	color: Color = UIPalette.PRISM_TEXT,
	box: Vector2 = Vector2(18, 18),
	thickness: float = 3.0
) -> Control:
	var node := Control.new()
	node.name = "PrismChevron"
	node.custom_minimum_size = box
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_meta("prism_chevron_dir", direction)
	node.set_meta("prism_chevron_color", color)
	node.set_meta("prism_chevron_thickness", thickness)
	node.draw.connect(_draw_prism_chevron.bind(node))
	return node


static func _draw_prism_chevron(node: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	var box := node.size
	if box.x <= 2.0 or box.y <= 2.0:
		return
	var direction := str(node.get_meta("prism_chevron_dir", "right"))
	var color: Color = node.get_meta("prism_chevron_color", UIPalette.PRISM_TEXT)
	var thickness: float = float(node.get_meta("prism_chevron_thickness", 3.0))
	var center := box * 0.5
	var half_w: float = box.x * 0.19
	var half_h: float = box.y * 0.22
	var tip := Vector2.ZERO
	var first := Vector2.ZERO
	var second := Vector2.ZERO
	match direction:
		"left":
			tip = Vector2(center.x - half_w, center.y)
			first = Vector2(center.x + half_w, center.y - half_h)
			second = Vector2(center.x + half_w, center.y + half_h)
		"up":
			tip = Vector2(center.x, center.y - half_h)
			first = Vector2(center.x - half_w, center.y + half_h)
			second = Vector2(center.x + half_w, center.y + half_h)
		"down":
			tip = Vector2(center.x, center.y + half_h)
			first = Vector2(center.x - half_w, center.y - half_h)
			second = Vector2(center.x + half_w, center.y - half_h)
		_:
			tip = Vector2(center.x + half_w, center.y)
			first = Vector2(center.x - half_w, center.y - half_h)
			second = Vector2(center.x - half_w, center.y + half_h)
	node.draw_line(first, tip, color, thickness, true)
	node.draw_line(tip, second, color, thickness, true)


## 1px 细分割线（参考图中贯穿各行的白色细横线）
static func make_prism_rule(
	color: Color = UIPalette.PRISM_LINE_SOFT,
	thickness: float = 1.0
) -> Control:
	var node := Control.new()
	node.name = "PrismRule"
	node.custom_minimum_size = Vector2(0, maxf(1.0, thickness))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_meta("prism_rule_color", color)
	node.set_meta("prism_rule_thickness", thickness)
	node.draw.connect(_draw_prism_rule.bind(node))
	return node


static func _draw_prism_rule(node: Control) -> void:
	if node == null or not is_instance_valid(node) or node.size.x <= 1.0:
		return
	var color: Color = node.get_meta("prism_rule_color", UIPalette.PRISM_LINE_SOFT)
	var thickness: float = float(node.get_meta("prism_rule_thickness", 1.0))
	var y: float = node.size.y * 0.5
	node.draw_line(Vector2(0.0, y), Vector2(node.size.x, y), color, thickness, true)


# ---------- 徽章 / 页头 ----------

## 深色徽章（对应参考图左上角黑底白字的 NEW GAME 胶囊）
static func make_prism_badge(text: String, font_size: int = 20) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "PrismBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.039, 0.059, 0.086, 0.94)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(6)
	style.shadow_size = 0
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "BadgeLabel"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var variation := make_prism_font(3)
	if variation != null:
		label.add_theme_font_override("font", variation)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	badge.add_child(label)
	return badge


## 参考图页头三件套：深色徽章 + 右侧白色细延长线 + 徽章正下方的 ⌄ 提示。
## subtitle 落在延长线右端（例如渲染器名 / 当前输入设备）。
static func make_prism_header(
	title_text: String,
	subtitle_text: String = "",
	accent: Color = UIPalette.PRISM_ACCENT,
	badge_font_size: int = 20
) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = "PrismHeader"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 1)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)

	var badge := make_prism_badge(title_text, badge_font_size)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var line := make_prism_rule(Color(1.0, 1.0, 1.0, 0.55), 1.0)
	line.name = "Line"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.custom_minimum_size = Vector2(40, 1)
	row.add_child(line)

	if not subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.name = "Subtitle"
		subtitle.text = subtitle_text
		subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var variation := make_prism_font(2)
		if variation != null:
			subtitle.add_theme_font_override("font", variation)
		subtitle.add_theme_font_size_override("font_size", maxi(11, badge_font_size - 8))
		subtitle.add_theme_color_override("font_color", accent)
		row.add_child(subtitle)

	# 徽章正下方的下折角：用等宽占位块把折角推到徽章水平中心
	var chevron_row := HBoxContainer.new()
	chevron_row.name = "ChevronRow"
	chevron_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron_row.add_theme_constant_override("separation", 0)
	root.add_child(chevron_row)
	var spacer := Control.new()
	spacer.name = "BadgeCenterSpacer"
	spacer.custom_minimum_size = Vector2(24, 10)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron_row.add_child(spacer)
	var chevron := make_prism_chevron("down", Color(1.0, 1.0, 1.0, 0.55), Vector2(16, 10), 2.0)
	chevron.name = "HeaderChevron"
	chevron_row.add_child(chevron)
	var tail := Control.new()
	tail.name = "TailSpacer"
	tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron_row.add_child(tail)
	badge.resized.connect(
		func() -> void:
			if is_instance_valid(spacer):
				spacer.custom_minimum_size.x = maxf(0.0, badge.size.x * 0.5 - 8.0)
	)
	return root


# ---------- 按钮 ----------

## 棱镜按钮样式表。
## role:
##   primary — 实心近白底 + 深色字（对应参考图最高对比主行动，如 NEW GAME / CONTINUE 焦点态）
##   ghost   — 透明底 + 四角白括号 + 白字（默认次行动，对应 CONTINUE 常态）
##   danger  — 透明底 + 平红括号 + 红字；悬停时淡红填充
##   warn    — 透明底 + 琥珀括号 + 琥珀字
##   faint   — 弱化线框（禁用/次要提示）
static func make_prism_button_style(role: String = "ghost", corner_radius: int = 2) -> Dictionary:
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var focus := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	for style in [normal, hover, pressed, focus, disabled]:
		(style as StyleBoxFlat).set_border_width_all(0)
		(style as StyleBoxFlat).set_corner_radius_all(corner_radius)
		(style as StyleBoxFlat).shadow_size = 0
		(style as StyleBoxFlat).content_margin_left = 22.0
		(style as StyleBoxFlat).content_margin_right = 22.0
		(style as StyleBoxFlat).content_margin_top = 11.0
		(style as StyleBoxFlat).content_margin_bottom = 11.0

	var font_normal := UIPalette.PRISM_TEXT
	var font_hover := Color(1.0, 1.0, 1.0, 1.0)
	match role:
		"primary":
			normal.bg_color = UIPalette.PRISM_PRIMARY_BG
			hover.bg_color = UIPalette.PRISM_PRIMARY_BG_HOVER
			pressed.bg_color = UIPalette.PRISM_PRIMARY_BG_PRESS
			focus.bg_color = UIPalette.PRISM_PRIMARY_BG_HOVER
			disabled.bg_color = Color(0.62, 0.66, 0.71, 0.45)
			font_normal = UIPalette.PRISM_INK
			font_hover = UIPalette.PRISM_INK
		"danger":
			var red := UIPalette.PRISM_DANGER
			normal.bg_color = Color(red.r, red.g, red.b, 0.0)
			hover.bg_color = Color(red.r, red.g, red.b, 0.16)
			pressed.bg_color = Color(red.r, red.g, red.b, 0.28)
			focus.bg_color = Color(red.r, red.g, red.b, 0.10)
			disabled.bg_color = Color(red.r, red.g, red.b, 0.0)
			font_normal = red
			font_hover = red.lightened(0.18)
		"warn":
			var amber := UIPalette.PRISM_WARN
			normal.bg_color = Color(amber.r, amber.g, amber.b, 0.0)
			hover.bg_color = Color(amber.r, amber.g, amber.b, 0.16)
			pressed.bg_color = Color(amber.r, amber.g, amber.b, 0.28)
			focus.bg_color = Color(amber.r, amber.g, amber.b, 0.10)
			disabled.bg_color = Color(amber.r, amber.g, amber.b, 0.0)
			font_normal = amber
			font_hover = amber.lightened(0.18)
		"faint":
			normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
			hover.bg_color = Color(1.0, 1.0, 1.0, 0.07)
			pressed.bg_color = Color(1.0, 1.0, 1.0, 0.14)
			focus.bg_color = Color(1.0, 1.0, 1.0, 0.05)
			disabled.bg_color = Color(1.0, 1.0, 1.0, 0.0)
			font_normal = UIPalette.PRISM_TEXT_FAINT
			font_hover = UIPalette.PRISM_LABEL
		_:  # ghost
			normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
			hover.bg_color = Color(1.0, 1.0, 1.0, 0.12)
			pressed.bg_color = Color(1.0, 1.0, 1.0, 0.24)
			focus.bg_color = Color(1.0, 1.0, 1.0, 0.06)
			disabled.bg_color = Color(1.0, 1.0, 1.0, 0.0)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"focus": focus,
		"disabled": disabled,
		"font_normal": font_normal,
		"font_hover": font_hover,
	}


## 把棱镜按钮样式应用到 Button。
## bracket_role 传 "" 则不画四角括号（primary 默认不画）。
static func apply_prism_button(
	btn: Button,
	role: String = "ghost",
	corner_radius: int = 2,
	font_size: int = 17,
	spacing: int = 2,
	bracket_role: String = "",
	arm: float = 15.0,
	thickness: float = 2.0
) -> void:
	if btn == null:
		return
	var style_dict := make_prism_button_style(role, corner_radius)
	btn.add_theme_stylebox_override("normal", style_dict["normal"])
	btn.add_theme_stylebox_override("hover", style_dict["hover"])
	btn.add_theme_stylebox_override("pressed", style_dict["pressed"])
	btn.add_theme_stylebox_override("focus", style_dict["focus"])
	btn.add_theme_stylebox_override("disabled", style_dict["disabled"])
	btn.add_theme_stylebox_override("hover_pressed", style_dict["pressed"])
	var font_normal: Color = style_dict.get("font_normal", UIPalette.PRISM_TEXT)
	var font_hover: Color = style_dict.get("font_hover", Color.WHITE)
	btn.add_theme_color_override("font_color", font_normal)
	btn.add_theme_color_override("font_hover_color", font_hover)
	btn.add_theme_color_override("font_focus_color", font_hover)
	btn.add_theme_color_override("font_pressed_color", font_normal.darkened(0.10))
	btn.add_theme_color_override("font_hover_pressed_color", font_hover)
	# 禁用态保留可读性：棱镜语言的"不可用"靠**压暗**而不是靠"糊成一片灰"，
	# 因此取钢蓝弱字而非 Godot 默认的中性灰（后者会与整体冷调脱节）。
	btn.add_theme_color_override(
		"font_disabled_color",
		Color(UIPalette.PRISM_TEXT_FAINT.r, UIPalette.PRISM_TEXT_FAINT.g, UIPalette.PRISM_TEXT_FAINT.b, 0.80)
	)
	btn.add_theme_constant_override("outline_size", 0)
	var variation := make_prism_font(spacing)
	if variation != null:
		btn.add_theme_font_override("font", variation)
	if font_size > 0:
		btn.add_theme_font_size_override("font_size", font_size)
	var resolved_bracket := bracket_role
	if resolved_bracket.is_empty():
		resolved_bracket = "" if role == "primary" else role
	# "none" = 显式声明"不要括号"。批量树皮（apply_prism_tree）靠它避免一屏几十圈
	# 括号互相粘成乱线 —— 规范 §3.1：括号只给唯一的那一个当前选框。
	if resolved_bracket == "none":
		resolved_bracket = ""
	if not resolved_bracket.is_empty():
		attach_prism_bracket_frame(btn, resolved_bracket, arm, thickness, 0.0)
	if btn.is_inside_tree():
		UIFX.attach_button_press(btn, 1.014, 0.988)
		_bind_button_audio(btn)
	else:
		btn.ready.connect(UIFX.attach_button_press.bind(btn, 1.014, 0.988), CONNECT_ONE_SHOT)
		btn.ready.connect(_bind_button_audio.bind(btn), CONNECT_ONE_SHOT)


# ---------- 菜单行：参考图左栏「贯穿细线 + 左对齐大字」列表 ----------

## 参考图左栏的三条选项行，以及底部的 CONTINUE，并不使用「每个按钮各套一圈四角括号」。
## 括号只出现在**唯一的那一个当前选框**上（CONTINUE），行与行之间靠贯穿细线分隔。
## 一屏铺十几圈括号会互相粘成乱线 —— 这正是上一轮的视觉事故来源。
## 所以菜单行单独立一套样式：全透明底、左对齐、无边框，靠上方细线与行尾折角表达状态。
## role: ghost(常规行动行) / danger(平红危险行) / muted(弱化不可用行)
static func apply_prism_row_button(
	btn: Button,
	role: String = "ghost",
	font_size: int = 22,
	spacing: int = 5,
	indent: float = 26.0,
	enable_chevron: bool = true
) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var focus := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	for entry in [normal, hover, pressed, focus, disabled]:
		var style := entry as StyleBoxFlat
		style.set_border_width_all(0)
		style.set_corner_radius_all(0)
		style.shadow_size = 0
		style.content_margin_left = indent
		style.content_margin_right = 52.0
		style.content_margin_top = 9.0
		style.content_margin_bottom = 9.0
	var font_normal := UIPalette.PRISM_TEXT
	var font_hover := Color(1.0, 1.0, 1.0, 1.0)
	match role:
		"danger":
			var red := UIPalette.PRISM_DANGER
			normal.bg_color = Color(red.r, red.g, red.b, 0.0)
			hover.bg_color = Color(red.r, red.g, red.b, 0.13)
			pressed.bg_color = Color(red.r, red.g, red.b, 0.24)
			focus.bg_color = Color(red.r, red.g, red.b, 0.08)
			disabled.bg_color = Color(red.r, red.g, red.b, 0.0)
			font_normal = red
			font_hover = red.lightened(0.24)
		"muted":
			normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
			hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
			pressed.bg_color = Color(1.0, 1.0, 1.0, 0.10)
			focus.bg_color = Color(1.0, 1.0, 1.0, 0.03)
			disabled.bg_color = Color(1.0, 1.0, 1.0, 0.0)
			font_normal = UIPalette.PRISM_TEXT_FAINT
			font_hover = UIPalette.PRISM_LABEL
		_:
			normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
			hover.bg_color = Color(1.0, 1.0, 1.0, 0.08)
			pressed.bg_color = Color(1.0, 1.0, 1.0, 0.17)
			focus.bg_color = Color(1.0, 1.0, 1.0, 0.05)
			disabled.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_color_override("font_color", font_normal)
	btn.add_theme_color_override("font_hover_color", font_hover)
	btn.add_theme_color_override("font_focus_color", font_hover)
	btn.add_theme_color_override("font_pressed_color", font_hover)
	btn.add_theme_color_override("font_hover_pressed_color", font_hover)
	btn.add_theme_color_override("font_disabled_color", Color(0.46, 0.52, 0.60, 0.50))
	btn.add_theme_constant_override("outline_size", 0)
	var variation := make_prism_font(spacing)
	if variation != null:
		btn.add_theme_font_override("font", variation)
	if font_size > 0:
		btn.add_theme_font_size_override("font_size", font_size)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bind_button_audio(btn)
	if enable_chevron:
		attach_prism_row_chevron(btn)


## 行尾折角：静止不可见，悬停 / 聚焦时淡入并右移 4px。
## 整行 900+px 宽，用「整块反相」会过于粗暴，因此改用一个极小的方向标。
static func attach_prism_row_chevron(btn: Button) -> Control:
	if btn == null or btn.get_node_or_null("PrismRowChevron") != null:
		return null
	var chevron := make_prism_chevron("right", UIPalette.PRISM_TEXT, Vector2(13, 13), 2.0)
	chevron.name = "PrismRowChevron"
	chevron.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	chevron.offset_left = -37.0
	chevron.offset_right = -24.0
	chevron.offset_top = -6.0
	chevron.offset_bottom = 7.0
	chevron.modulate = Color(1.0, 1.0, 1.0, 0.0)
	btn.add_child(chevron)
	btn.mouse_entered.connect(sync_prism_row_state.bind(btn, true))
	btn.mouse_exited.connect(sync_prism_row_state.bind(btn, false))
	btn.focus_entered.connect(sync_prism_row_state.bind(btn, true))
	btn.focus_exited.connect(sync_prism_row_state.bind(btn, false))
	btn.button_down.connect(sync_prism_row_state.bind(btn, true))
	return chevron


## 行状态联动：行尾折角淡入 + 该行上方细线提亮。
static func sync_prism_row_state(btn: Button, on: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var chevron := btn.get_node_or_null("PrismRowChevron") as Control
	if chevron != null:
		var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
		if reduce_motion or not btn.is_inside_tree() or btn.get_tree() == null:
			chevron.modulate = Color(1.0, 1.0, 1.0, 1.0 if on else 0.0)
		else:
			var tween := btn.create_tween()
			tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(chevron, "modulate:a", 1.0 if on else 0.0, 0.12)
			tween.parallel().tween_property(chevron, "offset_left", -32.0 if on else -37.0, 0.12)
			tween.parallel().tween_property(chevron, "offset_right", -19.0 if on else -24.0, 0.12)
	var rule := btn.get_meta("prism_row_rule", null) as Control
	if rule != null and is_instance_valid(rule):
		rule.set_meta("prism_rule_color", Color(1.0, 1.0, 1.0, 0.70 if on else 0.22))
		rule.queue_redraw()


## 在按钮正上方插入一条贯穿细线（参考图每行上沿的那条白线）。
## width > 0 时细线只跨到该宽度并靠左 —— 参考图的左栏只有屏宽的三分之一左右，
## 细线铺满整屏会立刻失去"左栏"的语义。
## 注意：同一容器内务必**从后往前**依次调用，否则插入动作会挪动后续行的索引。
static func attach_prism_row_rule(
	btn: Button,
	alpha: float = 0.22,
	name_hint: String = "",
	width: float = 0.0
) -> Control:
	if btn == null or not btn.is_inside_tree():
		return null
	var parent := btn.get_parent()
	if parent == null:
		return null
	var rule := make_prism_rule(Color(1.0, 1.0, 1.0, alpha), 1.0)
	rule.name = "PrismRowRule" if name_hint.is_empty() else "PrismRowRule_%s" % name_hint
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if width > 0.0:
		rule.custom_minimum_size = Vector2(width, 1.0)
		rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		rule.size_flags_horizontal = Control.SIZE_FILL
	parent.add_child(rule)
	parent.move_child(rule, btn.get_index())
	btn.set_meta("prism_row_rule", rule)
	return rule


## 方角箭头钮（参考图的 [<] / [>]）：白线方框 + 自绘折角；
## 悬停/按下时整体反相为白底深折角 —— 参考图选中行正是这个反相白块。
static func make_prism_arrow_button(direction: String, box: float = 46.0) -> Button:
	var btn := Button.new()
	btn.name = "PrismArrowButton_%s" % direction
	btn.text = ""
	btn.custom_minimum_size = Vector2(box, box)
	btn.focus_mode = Control.FOCUS_ALL
	var base := StyleBoxFlat.new()
	base.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	base.border_color = Color(1.0, 1.0, 1.0, 0.62)
	base.set_border_width_all(1)
	base.set_corner_radius_all(1)
	base.shadow_size = 0
	base.content_margin_left = 0.0
	base.content_margin_right = 0.0
	base.content_margin_top = 0.0
	base.content_margin_bottom = 0.0
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	hover.border_color = Color(1.0, 1.0, 1.0, 1.0)
	var pressed := base.duplicate() as StyleBoxFlat
	pressed.bg_color = UIPalette.PRISM_PRIMARY_BG_PRESS
	pressed.border_color = Color(1.0, 1.0, 1.0, 1.0)
	var focus := base.duplicate() as StyleBoxFlat
	focus.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	focus.border_color = Color(1.0, 1.0, 1.0, 0.96)
	var disabled := base.duplicate() as StyleBoxFlat
	disabled.border_color = Color(1.0, 1.0, 1.0, 0.18)
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	var chevron := make_prism_chevron(direction, UIPalette.PRISM_TEXT, Vector2(box, box), 3.0)
	chevron.name = "Chevron"
	btn.add_child(chevron)
	btn.mouse_entered.connect(_sync_prism_arrow_chevron.bind(btn, true))
	btn.mouse_exited.connect(_sync_prism_arrow_chevron.bind(btn, false))
	btn.button_down.connect(_sync_prism_arrow_chevron.bind(btn, true))
	btn.button_up.connect(_sync_prism_arrow_chevron.bind(btn, false))
	if btn.is_inside_tree():
		UIFX.attach_button_press(btn, 1.06, 0.94)
		_bind_button_audio(btn)
	else:
		btn.ready.connect(UIFX.attach_button_press.bind(btn, 1.06, 0.94), CONNECT_ONE_SHOT)
		btn.ready.connect(_bind_button_audio.bind(btn), CONNECT_ONE_SHOT)
	return btn


static func _sync_prism_arrow_chevron(btn: Button, inverted: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var chevron := btn.get_node_or_null("Chevron") as Control
	if chevron == null:
		return
	chevron.set_meta(
		"prism_chevron_color",
		UIPalette.PRISM_INK if inverted else UIPalette.PRISM_TEXT
	)
	chevron.queue_redraw()


# ---------- 选项按钮：极简化，箭头交给独立方角钮 ----------

## OptionButton 在棱镜体系里只保留"当前值"这一个信息 ——
## 去掉底色、边框与自带箭头，只留近白大字号文本。
## 左右切换由外部的 make_prism_arrow_button 承担（参考图 ARENA / THEME 行的形态）。
static func apply_prism_option_button(opt: OptionButton, font_size: int = 20, spacing: int = 3) -> void:
	if opt == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	normal.set_border_width_all(0)
	normal.set_corner_radius_all(0)
	normal.shadow_size = 0
	normal.content_margin_left = 6.0
	normal.content_margin_right = 6.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	opt.add_theme_stylebox_override("normal", normal)
	opt.add_theme_stylebox_override("hover", hover)
	opt.add_theme_stylebox_override("pressed", pressed)
	opt.add_theme_stylebox_override("focus", focus)
	opt.add_theme_stylebox_override("disabled", normal)
	opt.add_theme_icon_override("arrow", _prism_blank_texture())
	opt.add_theme_constant_override("outline_size", 0)
	var variation := make_prism_font(spacing)
	if variation != null:
		opt.add_theme_font_override("font", variation)
	opt.add_theme_font_size_override("font_size", font_size)
	opt.add_theme_color_override("font_color", UIPalette.PRISM_TEXT)
	opt.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	opt.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
	opt.add_theme_color_override("font_pressed_color", UIPalette.PRISM_ACCENT)
	opt.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 下拉弹层同样去圆角、去亮色，保持同一套语言
	var popup := opt.get_popup()
	if popup != null:
		var popup_panel := StyleBoxFlat.new()
		popup_panel.bg_color = Color(0.031, 0.051, 0.078, 0.96)
		popup_panel.border_color = Color(1.0, 1.0, 1.0, 0.30)
		popup_panel.set_border_width_all(1)
		popup_panel.set_corner_radius_all(2)
		popup.add_theme_stylebox_override("panel", popup_panel)
		popup.add_theme_stylebox_override("hover", _prism_popup_row_style(0.12))
		popup.add_theme_stylebox_override("separator", _prism_popup_row_style(0.0))
		popup.add_theme_font_override("font", variation)
		popup.add_theme_font_size_override("font_size", maxi(12, font_size - 5))
		popup.add_theme_color_override("font_color", UIPalette.PRISM_TEXT)
		popup.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))


static func _prism_popup_row_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, alpha)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


# ---------- 勾选框：白方块 ----------

## CheckButton 在棱镜体系里改为「方角勾选框」：未勾选 = 白细线空框 + 暗字，
## 勾选 = 实心白块 + 深色对勾 + 亮字（参考图里"选中即反相成白块"的同一条律）。
static func apply_prism_check_button(chk: CheckButton, font_size: int = 16) -> void:
	if chk == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	normal.set_border_width_all(0)
	normal.set_corner_radius_all(0)
	normal.shadow_size = 0
	normal.content_margin_left = 8.0
	normal.content_margin_right = 8.0
	normal.content_margin_top = 7.0
	normal.content_margin_bottom = 7.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	var disabled := normal.duplicate() as StyleBoxFlat
	chk.add_theme_stylebox_override("normal", normal)
	chk.add_theme_stylebox_override("hover", hover)
	chk.add_theme_stylebox_override("pressed", pressed)
	chk.add_theme_stylebox_override("hover_pressed", hover)
	chk.add_theme_stylebox_override("focus", focus)
	chk.add_theme_stylebox_override("disabled", disabled)
	chk.add_theme_icon_override("checked", _prism_check_texture(true))
	chk.add_theme_icon_override("unchecked", _prism_check_texture(false))
	chk.add_theme_icon_override("checked_disabled", _prism_check_texture(true))
	chk.add_theme_icon_override("unchecked_disabled", _prism_check_texture(false))
	chk.add_theme_constant_override("h_separation", 10)
	chk.add_theme_constant_override("outline_size", 0)
	var variation := make_prism_font(1)
	if variation != null:
		chk.add_theme_font_override("font", variation)
	chk.add_theme_font_size_override("font_size", font_size)
	# 关闭态走钢蓝弱字，开启态反相为亮白 —— 一眼分辨"这个效果开了没有"
	chk.add_theme_color_override("font_color", Color(0.647, 0.722, 0.831, 1.0))
	chk.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	chk.add_theme_color_override("font_hover_color", Color(0.847, 0.898, 0.949, 1.0))
	chk.add_theme_color_override("font_hover_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	chk.add_theme_color_override("font_disabled_color", UIPalette.PRISM_TEXT_FAINT)
	if chk.is_inside_tree():
		_bind_button_audio(chk)
	else:
		chk.ready.connect(_bind_button_audio.bind(chk), CONNECT_ONE_SHOT)


# ---------- 滑条：细线轨道 + 白方块把手 ----------

## HSlider 改为"细白线轨道 + 白方把手"。
## 关键机制：Godot 的 Slider 在横向绘制时把 rect 高度置 0，真正决定轨道视觉高度的是
## `stylebox.get_minimum_size().y`（= content_margin_top + bottom），并且会自动垂直居中。
## 所以把上下 content_margin 设为 2 就得到一条 4px 细线，无需改动控件高度、也不牵动布局。
## ⚠️ 不能用负的 expand_margin：它会让绘制矩形变成负高度，Godot 会反向画出一条**粗带**。
static func apply_prism_slider(slider: HSlider) -> void:
	if slider == null:
		return
	slider.add_theme_stylebox_override("slider", _prism_slider_track_style(Color(1.0, 1.0, 1.0, 0.24)))
	slider.add_theme_stylebox_override("grabber_area", _prism_slider_track_style(Color(1.0, 1.0, 1.0, 0.92)))
	slider.add_theme_stylebox_override(
		"grabber_area_highlight", _prism_slider_track_style(UIPalette.PRISM_ACCENT)
	)
	slider.add_theme_icon_override("grabber", _prism_grabber_texture(false))
	slider.add_theme_icon_override("grabber_highlight", _prism_grabber_texture(true))


static func _prism_slider_track_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


# ---------- 键帽 / 数值框 ----------

## 白底深字方键帽（参考图所有快捷键角标 [1] [T] [O] 的统一形态）
static func make_prism_keycap_badge(
	key_text: String,
	font_size: int = 12,
	min_size: Vector2 = Vector2(24, 22)
) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "PrismKeycap"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = UIPalette.PRISM_KEYCAP_BG
	style.border_color = Color(0.043, 0.071, 0.110, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_size = 0
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "KeycapLabel"
	label.text = key_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UIPalette.PRISM_KEYCAP_TEXT)
	badge.add_child(label)
	return badge


## 把白方键帽骑到按钮右端（参考图所有快捷键都是实体白方块）。
## 按钮文字里就不再需要写 `[Esc]` 这类字符，视觉上是真正的"键帽"而非括号文本。
## 键帽是独立子节点、不参与按钮内文本排版，因此必须显式给文本让出位置，
## 否则长文案会被键帽压住（上一轮 `取消 · 留在 98F` 就被 ESC 盖掉了尾巴）。
static func attach_prism_keycap(
	btn: Button,
	key_text: String,
	font_size: int = 12,
	right_offset: float = 20.0
) -> PanelContainer:
	if btn == null or btn.get_node_or_null("PrismKeycap") != null:
		return null
	var keycap := make_prism_keycap_badge(key_text, font_size, Vector2(38, 22))
	keycap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	keycap.offset_left = -(right_offset + 38.0)
	keycap.offset_right = -right_offset
	keycap.offset_top = -11.0
	keycap.offset_bottom = 11.0
	btn.add_child(keycap)
	_reserve_prism_keycap_space(btn, right_offset + 38.0 + 6.0)
	return keycap


## 撑开按钮五个状态样式盒的右内边距，并同步抬高按钮最小宽度，
## 让文本区在键帽左侧收住。对居中排版的按钮来说，文本会整体左移半个预留量 —— 正是我们要的。
static func _reserve_prism_keycap_space(btn: Button, reserve: float) -> void:
	if btn == null or reserve <= 0.0:
		return
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var style := btn.get_theme_stylebox(state)
		if style is StyleBoxFlat:
			var flat := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
			flat.content_margin_right = maxf(flat.content_margin_right, reserve)
			btn.add_theme_stylebox_override(state, flat)
	btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x + reserve, btn.custom_minimum_size.y)


## 白线方角数值框（滑块当前值 0.20 这类读数）
static func make_prism_value_box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	style.border_color = Color(1.0, 1.0, 1.0, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_size = 0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


## 参考图「弱标签 + 强数值」两行文本块（用于设置行左侧的字段名）
static func make_prism_field_text(label_text: String, value_text: String, value_size: int = 22) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "PrismFieldText"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = label_text
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_prism_label(caption, "label", 3, 12)
	box.add_child(caption)
	var value := Label.new()
	value.name = "Value"
	value.text = value_text
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_prism_label(value, "value", 2, value_size)
	box.add_child(value)
	return box


# ---------- 图标纹理：运行时生成，零外部资源依赖 ----------

static func _prism_check_texture(checked: bool) -> ImageTexture:
	if checked and _prism_check_on_tex != null:
		return _prism_check_on_tex
	if not checked and _prism_check_off_tex != null:
		return _prism_check_off_tex
	var size := _PRISM_CHECK_SIZE
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in size:
		for x in size:
			if not checked:
				var edge := x < 2 or y < 2 or x >= size - 2 or y >= size - 2
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.80) if edge else Color(1.0, 1.0, 1.0, 0.07))
			else:
				image.set_pixel(x, y, UIPalette.PRISM_KEYCAP_BG)
	if checked:
		var a := Vector2(4.0, 9.6)
		var b := Vector2(7.6, 13.2)
		var c := Vector2(13.8, 5.4)
		for y in size:
			for x in size:
				var p := Vector2(float(x) + 0.5, float(y) + 0.5)
				if _prism_point_segment_distance(p, a, b) <= 1.4 or _prism_point_segment_distance(p, b, c) <= 1.4:
					image.set_pixel(x, y, UIPalette.PRISM_INK)
	var texture := ImageTexture.create_from_image(image)
	if checked:
		_prism_check_on_tex = texture
	else:
		_prism_check_off_tex = texture
	return texture


static func _prism_grabber_texture(highlight: bool) -> ImageTexture:
	if highlight and _prism_grabber_hl_tex != null:
		return _prism_grabber_hl_tex
	if not highlight and _prism_grabber_tex != null:
		return _prism_grabber_tex
	var size := _PRISM_GRABBER_SIZE
	var core := UIPalette.PRISM_ACCENT if highlight else Color(1.0, 1.0, 1.0, 0.98)
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in size:
		for x in size:
			var edge := x == 0 or y == 0 or x == size - 1 or y == size - 1
			image.set_pixel(x, y, UIPalette.PRISM_INK if edge else core)
	var texture := ImageTexture.create_from_image(image)
	if highlight:
		_prism_grabber_hl_tex = texture
	else:
		_prism_grabber_tex = texture
	return texture


static func _prism_blank_texture() -> ImageTexture:
	if _prism_blank_tex == null:
		var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		_prism_blank_tex = ImageTexture.create_from_image(image)
	return _prism_blank_tex


static func _prism_point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------- 组合件：选择行 / 开关行 / 数值行 ----------

## 现场搭建一条"棱镜选择行"：左方角箭头 + 中央大号当前值 + 右方角箭头。
## 返回 { root, prev, next, center_slot }；调用方把 OptionButton 塞进 center_slot，
## 并把 prev/next 的 pressed 接到 select(index ± 1)。
static func make_prism_selector_row(
	caption: String,
	center_slot: Control,
	row_name: String = "PrismSelectorRow"
) -> Dictionary:
	var root := HBoxContainer.new()
	root.name = row_name
	root.add_theme_constant_override("separation", 10)
	var prev := make_prism_arrow_button("left", 44.0)
	root.add_child(prev)
	var center := VBoxContainer.new()
	center.name = "Center"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	if not caption.is_empty():
		var caption_label := Label.new()
		caption_label.name = "Caption"
		caption_label.text = caption
		caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		apply_prism_label(caption_label, "label", 3, 11)
		center.add_child(caption_label)
	if center_slot != null:
		center_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center_slot.custom_minimum_size = Vector2(0, 40)
		center.add_child(center_slot)
	root.add_child(center)
	var next := make_prism_arrow_button("right", 44.0)
	root.add_child(next)
	return {
		"root": root,
		"prev": prev,
		"next": next,
		"center": center,
	}


## 让 OptionButton 支持"箭头步进"：把 prev/next 接上去，循环切换选项。
static func bind_prism_option_stepping(opt: OptionButton, prev: Button, next: Button) -> void:
	if opt == null:
		return
	if prev != null and not prev.pressed.is_connected(_prism_step_option.bind(opt, -1)):
		prev.pressed.connect(_prism_step_option.bind(opt, -1))
	if next != null and not next.pressed.is_connected(_prism_step_option.bind(opt, 1)):
		next.pressed.connect(_prism_step_option.bind(opt, 1))


static func _prism_step_option(opt: OptionButton, delta: int) -> void:
	if opt == null or not is_instance_valid(opt) or opt.item_count <= 0:
		return
	var target: int = wrapi(opt.selected + delta, 0, opt.item_count)
	if target == opt.selected:
		return
	opt.select(target)
	opt.item_selected.emit(target)


## 给一行套上"整行括号框 + 悬停/聚焦提亮"（参考图选中行被括号包住的效果）
static func wrap_prism_row(row: Control, role: String = "faint", arm: float = 14.0) -> Control:
	if row == null:
		return null
	return attach_prism_bracket_frame(row, role, arm, 2.0, 0.0)


## 按钮描述（供 make_prism_confirm_modal 用）
static func prism_button_spec(
	node_name: String,
	text: String,
	role: String,
	min_width: float = 280.0,
	min_height: float = 56.0
) -> Dictionary:
	return {
		"name": node_name,
		"text": text,
		"role": role,
		"min_width": min_width,
		"min_height": min_height,
	}


## 生成一张完整的「棱镜」确认/警戒模态卡（返回节点、**不入树**，由调用方 add_child）。
## 结构：全屏冷蓝压暗 + 四角括号面板 + 黑徽章标题条（含下折角）+ 1px 白分隔线 +
## 内嵌"规则说明"细线框 + 底部一排方角语义按钮。
## buttons_spec 里每项由 prism_button_spec 生成；返回字典含 buttons 数组（顺序同 spec）。
static func make_prism_confirm_modal(
	title_text: String,
	subtitle_text: String,
	detail_text: String,
	buttons_spec: Array,
	accent: Color = UIPalette.PRISM_DANGER,
	panel_size: Vector2 = Vector2(740, 400),
	dim_alpha: float = 0.70
) -> Dictionary:
	var overlay := Control.new()
	overlay.name = "PrismConfirmModal"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, dim_alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = panel_size
	panel.position = -panel_size * 0.5
	panel.add_theme_stylebox_override("panel", make_prism_panel(true, 0.62))
	attach_prism_bracket_frame(panel, "solid", 26.0, 2.0, 0.0)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 16)
	# 面板高度是各弹窗各自指定的固定值，而文案长短不一；
	# 居中对齐可以让内容永远落在面板正中，不会在底部留一条空带。
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	box.add_child(make_prism_header(title_text, subtitle_text, accent, 22))
	box.add_child(make_prism_rule(Color(1.0, 1.0, 1.0, 0.28), 1.0))

	var detail_card := PanelContainer.new()
	detail_card.name = "DetailCard"
	detail_card.add_theme_stylebox_override("panel", make_prism_panel(false, 0.28))
	attach_prism_bracket_frame(detail_card, "faint", 12.0, 2.0, 0.0)
	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 18)
	detail_margin.add_theme_constant_override("margin_top", 14)
	detail_margin.add_theme_constant_override("margin_right", 18)
	detail_margin.add_theme_constant_override("margin_bottom", 14)
	detail_card.add_child(detail_margin)
	var detail := Label.new()
	detail.name = "Detail"
	detail.text = detail_text
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_prism_label(detail, "value", 1, 15)
	detail_margin.add_child(detail)
	box.add_child(detail_card)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 22)
	box.add_child(buttons)
	var button_nodes: Array = []
	for spec in buttons_spec:
		var spec_dict := spec as Dictionary
		if spec_dict.is_empty():
			continue
		var node := Button.new()
		node.name = str(spec_dict.get("name", "PrismButton"))
		node.text = str(spec_dict.get("text", ""))
		node.custom_minimum_size = Vector2(
			float(spec_dict.get("min_width", 280.0)),
			float(spec_dict.get("min_height", 56.0))
		)
		apply_prism_button(node, str(spec_dict.get("role", "ghost")), 3, 18, 3)
		buttons.add_child(node)
		button_nodes.append(node)

	return {
		"overlay": overlay,
		"dim": dim,
		"panel": panel,
		"box": box,
		"buttons": button_nodes,
	}


# ======================================================================================
# 「棱镜线框」通用件（进度 / 分隔 / 格子 / 滚动 / 面板）与通用树皮
# ======================================================================================
# 2026-10-17：把暂停系统之外的其余界面（启动页、99F 基地设施、局内弹窗、启动流）
# 一次性收编到同一套白线语言。为避免逐个界面重写 StyleBox，这里提供：
#   · 一组"只换外观、不改几何"的通用件（进度 / 分隔 / 格子 / 滚动 / 输入框）；
#   · 一个通用树皮 apply_prism_tree()，与 apply_tactical_tree 对称，但走棱镜 Token。
# **内容边距保护**：通用树皮替换样式时会把旧样式盒的 content_margin 原样搬过来，
# 因此"换皮"不会挪动内容一像素 —— 这是保住既有布局与格子契约的关键。

## 进度条底槽：1px 白线空槽（无填充色、无圆角）。
static func make_prism_progress_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	style.border_color = UIPalette.PRISM_LINE_FAINT
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	return style


## 进度条填充：平色方角（零渐变、零辉光）。
static func make_prism_progress_fill(color: Color = UIPalette.PRISM_LINE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	return style


## 贯穿细线（HSeparator / VSeparator 用）：1px 白线，无圆角无底色。
static func make_prism_separator_style(alpha: float = 0.22) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


## 格子（背包 / 仓库 / 售货机货架 / 快捷栏）的棱镜外壳。
## **不设 content_margin** —— 与旧 make_slot_style 一致，格子尺寸与落位完全不受影响。
static func make_prism_slot_style(is_hover: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIPalette.PRISM_SURFACE.r, UIPalette.PRISM_SURFACE.g, UIPalette.PRISM_SURFACE.b, 0.46 if is_hover else 0.28)
	style.border_color = Color(1.0, 1.0, 1.0, 0.62 if is_hover else 0.26)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_size = 0
	return style


## 已占用格子：仅把线提亮一档，仍不填充（保持"线框"语言）。
static func make_prism_slot_filled_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIPalette.PRISM_SURFACE.r, UIPalette.PRISM_SURFACE.g, UIPalette.PRISM_SURFACE.b, 0.40)
	style.border_color = Color(1.0, 1.0, 1.0, 0.44)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_size = 0
	return style


## 大面积承载面板（背包 / 仓库 / 售货机 / 工坊的底板）：深蓝半透 + 1px 白线，方角。
## 与 make_inventory_surface 一样**不带 content_margin**，几何零回归。
static func make_prism_surface(slot: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UIPalette.PRISM_SURFACE_SOLID if not slot else Color(UIPalette.PRISM_SURFACE.r, UIPalette.PRISM_SURFACE.g, UIPalette.PRISM_SURFACE.b, 0.42)
	style.border_color = UIPalette.PRISM_LINE_SOFT
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_size = 0
	return style


## 输入框（LineEdit）：白线方角，聚焦时线提亮。
static func apply_prism_line_edit(line: LineEdit) -> void:
	if line == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(UIPalette.PRISM_SURFACE.r, UIPalette.PRISM_SURFACE.g, UIPalette.PRISM_SURFACE.b, 0.42)
	normal.border_color = UIPalette.PRISM_LINE_SOFT
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.shadow_size = 0
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = UIPalette.PRISM_LINE
	line.add_theme_stylebox_override("normal", normal)
	line.add_theme_stylebox_override("focus", focus)
	line.add_theme_color_override("font_color", UIPalette.PRISM_TEXT)
	line.add_theme_color_override("font_placeholder_color", UIPalette.PRISM_TEXT_FAINT)
	line.add_theme_color_override("caret_color", UIPalette.PRISM_LINE)
	line.add_theme_color_override("selection_color", Color(1.0, 1.0, 1.0, 0.22))


# ---------- 滚动条：细白线轨道 + 白方块把手 ----------

static func _prism_scroll_track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	return style


static func _prism_scroll_grabber_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.62 if active else 0.34)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	return style


## 给 ScrollContainer 的内部滚动条套上棱镜样式（细白轨 + 白块把手）。
## 实现方式：在容器上挂一份**只有滚动条条目**的 Theme —— 缺失条目会自动回落到
## 默认主题，因此不会污染子树里其它控件的字体与颜色。
static func apply_prism_scrollbar(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var theme := scroll.theme
	if theme == null:
		theme = Theme.new()
		scroll.theme = theme
	for type_name in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type_name, _prism_scroll_track_style())
		theme.set_stylebox("grabber", type_name, _prism_scroll_grabber_style(false))
		theme.set_stylebox("grabber_highlight", type_name, _prism_scroll_grabber_style(true))
		theme.set_stylebox("grabber_pressed", type_name, _prism_scroll_grabber_style(true))


# ---------- 通用树皮：与 apply_tactical_tree 对称，但走棱镜 Token ----------

## 把遗留调色板（霓虹青 / 灵魂金 / 平红 / 薄荷绿 等）归一化到棱镜语义色。
##
## 为什么需要：老界面把颜色**硬编码**在 add_theme_color_override 里（不走 Token），
## 逐个改写成百上千处既慢又易漏。这里按色相归到棱镜的语义槽位：
## 红→危险、金/橙→警告（同时承担货币读数）、青绿→成功、青/天蓝/紫→天蓝强调、
## 近白→正文、其余→正文。语义分工不丢，调色板收口到一套。
static func prism_normalize_color(source: Color) -> Color:
	var r := source.r
	var g := source.g
	var b := source.b
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	# 近白 / 浅灰：正文。
	if mn > 0.58 and (mx - mn) < 0.22:
		return UIPalette.PRISM_TEXT
	# 红系（含橙红）：危险。
	if r > 0.78 and g < 0.52 and b < 0.55:
		return UIPalette.PRISM_DANGER
	# 金 / 琥珀 / 橙：警告（兼货币与稀有度暖色）。
	if r > 0.80 and g > 0.50 and b < 0.52:
		return UIPalette.PRISM_WARN
	# 青绿 / 薄荷 / 草绿：成功。
	if g > 0.70 and g >= r and g > b:
		return UIPalette.PRISM_OK
	# 紫 / 品红（稀有度「史诗」）：单独一槽，避免与天蓝强调撞色。
	if b > 0.72 and r > 0.48 and g < 0.52:
		return UIPalette.PRISM_EPIC
	# 青 / 天蓝 / 紫 / 品红：天蓝强调（稀有度与焦点同槽）。
	if b > 0.55 or (b > 0.40 and r > 0.40):
		return UIPalette.PRISM_ACCENT
	# 其余中灰蓝：弱标签。
	if mx < 0.72:
		return UIPalette.PRISM_LABEL
	return UIPalette.PRISM_TEXT


## 窄口径归一化：只把子树里**已有**的文字/按钮字色映射到棱镜语义色，
## 不碰任何 StyleBox、不改尺寸、不动布局。
##
## 为什么单列：背包 / 装备 / 仓库带格子尺寸与空间逻辑，只允许"外观层"改动；
## 用整棵树皮（apply_prism_tree）虽然也会沿用内容边距，但会连带替换格子与面板的
## 样式盒，风险高于收益。这个函数只做调色板收口，是最保守的一档。
static func prism_normalize_label_colors(root: Node) -> void:
	if root == null:
		return
	# 注意：这里**只**认 ui_prism_exempt。ui_style_exempt 是"别用旧战术树皮刷我"的历史标记，
	# 背包/装备/仓库都带着它，若一并尊重就会把这些界面整个跳过。
	if root.has_meta("ui_prism_exempt"):
		return
	if root is Label:
		var label := root as Label
		if label.has_theme_color_override("font_color"):
			label.add_theme_color_override("font_color", prism_normalize_color(label.get_theme_color("font_color")))
		label.add_theme_font_override("font", make_prism_font(2))
	elif root is Button:
		var button := root as Button
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			if button.has_theme_color_override(state):
				button.add_theme_color_override(state, prism_normalize_color(button.get_theme_color(state)))
		button.add_theme_font_override("font", make_prism_font(2))
	elif root is ColorRect:
		var rect := root as ColorRect
		var rect_max := maxf(rect.color.r, maxf(rect.color.g, rect.color.b))
		if rect.color.a > 0.45 and rect_max < 0.20:
			rect.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, maxf(rect.color.a, 0.62))
	for child in root.get_children():
		prism_normalize_label_colors(child)


## 把一棵子树里 **面板类** 的样式盒（旧"柔和深蓝圆角")就地换成棱镜线框版。
## 只处理 `panel` 这一项（PanelContainer / Panel / ScrollContainer），
## **不碰按钮的 normal/hover/pressed** —— 否则会把主行动/危险钮一起刷成"格子"。
## 原样保留 content_margin ⇒ 面板与格子的尺寸、行列、落位零变化。
static func prism_reskin_styleboxes(root: Node) -> void:
	if root == null:
		return
	if root.has_meta("ui_prism_exempt"):
		return
	if root is PanelContainer or root is Panel or root is ScrollContainer:
		var control := root as Control
		var current := control.get_theme_stylebox("panel")
		if current is StyleBoxFlat:
			var prism := make_prism_surface(root is ScrollContainer)
			prism.border_color = Color(1.0, 1.0, 1.0, 0.20) if root is ScrollContainer else UIPalette.PRISM_LINE_SOFT
			_prism_adopt_content_margins(current, prism)
			control.add_theme_stylebox_override("panel", prism)
	for child in root.get_children():
		prism_reskin_styleboxes(child)


## 由控件名 / 文本推断语义角色（按钮）。
static func prism_button_role_for(btn: Button) -> String:
	if btn == null:
		return "ghost"
	var lowered := (String(btn.name) + " " + btn.text).to_lower()
	if (
		"出售" in btn.text
		or "丢弃" in btn.text
		or "删除" in btn.text
		or "复位" in btn.text
		or "销毁" in btn.text
		or "放弃" in btn.text
		or "确认撤退" in btn.text
		or "确认退出" in btn.text
		or "danger" in lowered
	):
		return "danger"
	if (
		"购买" in btn.text
		or "买入" in btn.text
		or "卖出" in btn.text
		or "出售全部" in btn.text
		or "金币" in btn.text
		or "warn" in lowered
	):
		return "warn"
	if "primary" in lowered or "主行动" in btn.text:
		return "primary"
	return "ghost"


## 由控件名 / 文本推断语义角色（标签）。
static func prism_label_role_for(label: Label) -> String:
	if label == null:
		return "value"
	var lowered := (String(label.name) + " " + label.text).to_lower()
	if "title" in lowered or "标题" in label.text or "header" in lowered:
		return "value"
	if "danger" in lowered or "危险" in label.text:
		return "danger"
	if "warn" in lowered or "警告" in label.text or "注意" in label.text:
		return "warn"
	if "金币" in label.text or "价格" in label.text or "余额" in label.text or "价值" in label.text:
		return "warn"
	if "hint" in lowered or "提示" in label.text or "说明" in label.text or "caption" in lowered or "footnote" in lowered:
		return "faint"
	if "label" in lowered or "caption" in lowered:
		return "label"
	return "value"


## 把旧样式盒的内容边距搬到新样式盒上 —— "换皮"不挪内容的关键。
static func _prism_adopt_content_margins(source: StyleBox, target: StyleBoxFlat) -> bool:
	if source == null or target == null:
		return false
	target.content_margin_left = source.get_content_margin(SIDE_LEFT)
	target.content_margin_top = source.get_content_margin(SIDE_TOP)
	target.content_margin_right = source.get_content_margin(SIDE_RIGHT)
	target.content_margin_bottom = source.get_content_margin(SIDE_BOTTOM)
	return true


## 给任意子树套上棱镜皮肤（菜单 / 弹窗 / 列表通用）。
##
## opts（全部可选）：
##   · panel_alpha  : float 面板底衬透明度，默认 0.42
##   · panel_modal  : bool  面板走"模态加厚底衬"（默认 true 表示走极淡底衬）
##   · button_role  : String 按钮默认角色，默认 "ghost"
##   · spacing      : int   字距，默认 2
##   · preserve_margins : bool 是否沿用旧内容边距（默认 true —— 布局零回归）
##   · skip_exempt  : bool  是否跳过带 ui_prism_exempt / ui_style_exempt 的子树（默认 true）
static func apply_prism_tree(root: Node, opts: Dictionary = {}) -> void:
	if root == null:
		return
	if bool(opts.get("skip_exempt", true)) and (root.has_meta("ui_prism_exempt") or root.has_meta("ui_style_exempt")):
		return
	var preserve_margins := bool(opts.get("preserve_margins", true))
	var default_role := str(opts.get("button_role", "ghost"))
	var spacing := int(opts.get("spacing", 2))
	var panel_alpha := float(opts.get("panel_alpha", 0.42))
	var panel_modal := bool(opts.get("panel_modal", false))
	var normalize_colors := bool(opts.get("normalize_colors", true))

	if root is PanelContainer or root is Panel:
		var panel_type := "PanelContainer" if root is PanelContainer else "Panel"
		var control := root as Control
		var prism_style := make_prism_panel(panel_modal, panel_alpha)
		if preserve_margins and not _prism_adopt_content_margins(control.get_theme_stylebox("panel"), prism_style):
			pass
		control.add_theme_stylebox_override("panel", prism_style)
	elif root is OptionButton:
		apply_prism_option_button(root as OptionButton, 18, spacing)
	elif root is CheckButton:
		apply_prism_check_button(root as CheckButton, 16)
	elif root is Button:
		var button := root as Button
		var role := default_role
		if role == "auto":
			role = prism_button_role_for(button)
		var style_dict := make_prism_button_style(role, 2)
		if preserve_margins:
			_prism_adopt_content_margins(button.get_theme_stylebox("normal"), style_dict["normal"] as StyleBoxFlat)
			_prism_adopt_content_margins(button.get_theme_stylebox("hover"), style_dict["hover"] as StyleBoxFlat)
			_prism_adopt_content_margins(button.get_theme_stylebox("pressed"), style_dict["pressed"] as StyleBoxFlat)
			_prism_adopt_content_margins(button.get_theme_stylebox("focus"), style_dict["focus"] as StyleBoxFlat)
			_prism_adopt_content_margins(button.get_theme_stylebox("disabled"), style_dict["disabled"] as StyleBoxFlat)
		apply_prism_button(button, role, 2, 0, spacing, "none")
	elif root is ProgressBar:
		var bar := root as ProgressBar
		var fill_color := UIPalette.PRISM_LINE
		var bar_name := String(bar.name).to_lower()
		if "hp" in bar_name or "health" in bar_name or "life" in bar_name:
			fill_color = UIPalette.PRISM_HP_RED
		elif "stamina" in bar_name:
			fill_color = UIPalette.PRISM_WARN
		elif "exp" in bar_name:
			fill_color = UIPalette.PRISM_ACCENT
		bar.add_theme_stylebox_override("background", make_prism_progress_background())
		bar.add_theme_stylebox_override("fill", make_prism_progress_fill(fill_color))
	elif root is HSlider:
		# 滑条也必须收编：否则一块棱镜面板里会嵌着一条上一代主题的圆角滑轨。
		apply_prism_slider(root as HSlider)
	elif root is Label:
		var label := root as Label
		var role := prism_label_role_for(label)
		label.add_theme_font_override("font", make_prism_font(spacing))
		# 已有硬编码色的标签走"归一化"（保留语义分工、收口调色板）；
		# 没有色的按名字/文本推断角色。
		if normalize_colors and label.has_theme_color_override("font_color"):
			label.add_theme_color_override("font_color", prism_normalize_color(label.get_theme_color("font_color")))
		else:
			label.add_theme_color_override("font_color", prism_text_color(role))
	elif root is HSeparator or root is VSeparator:
		(root as Control).add_theme_stylebox_override("separator", make_prism_separator_style(0.22))
	elif root is ScrollContainer:
		var scroll := root as ScrollContainer
		var scroll_style := make_prism_panel(false, 0.30)
		if preserve_margins:
			_prism_adopt_content_margins(scroll.get_theme_stylebox("panel"), scroll_style)
		scroll.add_theme_stylebox_override("panel", scroll_style)
		apply_prism_scrollbar(scroll)
	elif root is LineEdit:
		apply_prism_line_edit(root as LineEdit)
	elif root is ColorRect:
		# 全屏压暗层：老界面惯用近乎纯黑（0.004,0.014,0.018,0.94）。
		# 棱镜要求"冷蓝压暗、保留实景冷调"，因此把**深色半透**的 ColorRect 统一成 PRISM_DIM。
		var rect := root as ColorRect
		var rect_max := maxf(rect.color.r, maxf(rect.color.g, rect.color.b))
		if rect.color.a > 0.45 and rect_max < 0.20:
			rect.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, maxf(rect.color.a, 0.62))
	for child in root.get_children():
		apply_prism_tree(child, opts)


