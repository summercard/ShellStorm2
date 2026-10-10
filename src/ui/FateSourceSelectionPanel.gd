extends Window

## FateSourceSelectionPanel —— 统一「来源选择」弹窗，两条调用路径共用同一面板：
##   ① 命运卡来源快照（枪上加枪 / 携枪 / 配件寄生）：条目携带 icon_item ⇒ 渲染 3D 枪械图标卡片；
##   ② 待领命运奖励：条目不带 icon_item ⇒ 回退纯文字行（不出现空图标占位）。
##
## 图标与地面拾取 / 背包 / 商人**同源**：条目里的 icon_item 直接交给 ItemModelIcon3D 投影。
## 面板自己不构造模型、不读玩法数据、不持有槽位规则 —— 它只把调用方给的条目画出来。
##
## 为什么要改：旧版是一列纯文字按钮，标签由 `root.node_name / source.node_name · #id` 拼成，
## 单枪玩家看到的两个名字恰好相同（如 GunBody_Sprinkler / GunBody_Sprinkler），既认不出
## 是哪把枪，也看不出该不该选。现在左侧给真实模型图标、右侧给中文武器名与来源位置。

## 图标场景必须**运行时 load**，不能用 preload。
## 本面板由 `FateCardGameBridge`（启动期 autoload）在编译期 preload，而图标场景的依赖链一路到
## `WeaponModel3D` → autoload `BlueprintRegistry`。编译期提前拉这条链时注册表还没就绪，整条链加载
## 失败，连 `Dungeon3D` 的 HUD 武器图标一起变空 —— 2026-10-10 实测启动报
## `Failed to instantiate scene state of "", node count is 0`。
## 同理下面也不写 `as ItemModelIcon3D`：用鸭子类型调用 `configure()`，编译期与图标组件零耦合。
const ITEM_MODEL_ICON_PATH := "res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn"
## 图标边长对齐 ItemModelIcon3D 的默认视口分辨率，缩放不重采样。
const ICON_PIXELS := 96
## 图标卡片最小高度（图标 96 + 上下留白）；纯文字行沿用旧高度，观感不变。
const CARD_MIN_HEIGHT := 108
const TEXT_ROW_MIN_HEIGHT := 48

static var _icon_scene: PackedScene = null

signal completed(result: Dictionary)
var _finished := false


## 首次真正需要图标时才解析场景（此时 autoload 已全部就绪）；结果缓存，不反复探测磁盘。
static func icon_scene() -> PackedScene:
	if _icon_scene == null:
		_icon_scene = load(ITEM_MODEL_ICON_PATH) as PackedScene
	return _icon_scene

func _ready() -> void:
	name = "FateSourceSelectionPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(cancel)


## heading = 窗口标题（一行摘要）；hint = 正文说明（可选，解释「为什么选、选了会怎样」）。
## 条目可选展示字段：icon_item / title / subtitle / badge / accent；缺 icon_item 时按纯文字行渲染。
## 旧契约字段 label / source 保持可读，调用方（含键盘焦点路径）无需改动。
func open_choices(heading: String, entries: Array[Dictionary], hint := "") -> void:
	title = heading
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var headline := Label.new()
	headline.name = "SourceHeadline"
	headline.text = heading
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.add_theme_color_override("font_color", UIPalette.NEON_CYAN)
	box.add_child(headline)

	# 正文说明：旧版这里重复了一遍标题，等于没解释。文案由调用方给（它才知道是哪张命运）。
	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.name = "SourceHint"
		hint_label.text = hint
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.add_theme_font_size_override("font_size", 13)
		hint_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
		box.add_child(hint_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 8)
	scroll.add_child(choices)

	var cards: Array[Dictionary] = []
	for entry in entries:
		var button := _make_choice(entry)
		choices.add_child(button)
		if _has_icon(entry):
			cards.append({"button": button, "accent": entry.get("accent", UIPalette.BORDER_FOCUS)})

	var back := Button.new()
	back.name = "Cancel"
	back.text = "取消 · 保留卡片"
	back.pressed.connect(cancel)
	box.add_child(back)

	UIStyleFactory.apply_tactical_tree(margin)
	# 稀有度强调必须晚于 apply_tactical_tree：否则卡片的描边会被通用青色样式覆盖。
	# 图标与卡片同色（两侧都取 item 的 rarity），一眼能分清主副枪。
	for card in cards:
		var accent: Color = card["accent"]
		UIStyleFactory.apply_button_style(
			card["button"] as Button, UIStyleFactory.make_button_style(UIPalette.BG_SLOT, accent)
		)
	popup_centered(Vector2i(620, 470))
	back.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()


func cancel() -> void:
	_finish({"success": false, "reason": "source_selection_cancelled", "message": "已取消来源选择；卡片保留"})


func _finish(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	# Window 自带独立 Viewport。不能在 _unhandled_key_input / Button.gui_input
	# 的当前派发栈里同步 hide + emit；上层 await 恢复后会继续 remove_child，
	# 进而让 Godot 在同一轮派发里向已离树的 Viewport 推送 unhandled input。
	# 把关闭和完成信号推迟到当前输入回调返回后，保持 Window 生命周期完整。
	call_deferred("_finish_deferred", result)


func _finish_deferred(result: Dictionary) -> void:
	if not is_instance_valid(self):
		return
	if is_inside_tree():
		hide()
	completed.emit(result)


# --- 条目渲染 ---------------------------------------------------------------


func _has_icon(entry: Dictionary) -> bool:
	var icon_item: Variant = entry.get("icon_item", {})
	return icon_item is Dictionary and not (icon_item as Dictionary).is_empty()


func _make_choice(entry: Dictionary) -> Button:
	if _has_icon(entry):
		return _make_icon_choice(entry, entry["icon_item"] as Dictionary)
	return _make_text_choice(entry)


func _make_text_choice(entry: Dictionary) -> Button:
	var button := Button.new()
	button.name = "TextChoice"
	button.text = str(entry.get("label", "来源"))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = TEXT_ROW_MIN_HEIGHT
	button.set_meta("fate_source", entry.get("source"))
	button.pressed.connect(_on_entry_pressed.bind(entry))
	return button


## 图标卡片：左 ItemModelIcon3D 投影、右三行文字（名称 / 来源位置与实例号 / 槽位或警示）。
## 按钮文本置空 —— Button.text 与子控件会叠在同一位置，只能二选一。
func _make_icon_choice(entry: Dictionary, icon_item: Dictionary) -> Button:
	var button := Button.new()
	button.name = "IconChoice"
	button.text = ""
	button.custom_minimum_size.y = CARD_MIN_HEIGHT
	button.set_meta("fate_source", entry.get("source"))
	button.pressed.connect(_on_entry_pressed.bind(entry))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12.0
	row.offset_top = 6.0
	row.offset_right = -12.0
	row.offset_bottom = -6.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	button.add_child(row)

	# 图标只做投影：取景、居中、视口分辨率全部由 ItemModelIcon3D 自适应，
	# 这里不写死相机倍率，换枪型也不会出框（2026-09-30 的既有口径）。
	var scene := icon_scene()
	if scene != null:
		var icon := scene.instantiate() as Control
		if icon != null:
			icon.name = "SourceModelIcon3D"
			icon.custom_minimum_size = Vector2(ICON_PIXELS, ICON_PIXELS)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
			if icon.has_method("configure"):
				icon.call("configure", icon_item)

	var text_box := VBoxContainer.new()
	text_box.name = "ChoiceText"
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)

	var accent: Color = entry.get("accent", UIPalette.TEXT_PRIMARY)
	text_box.add_child(
		_make_row_label("ChoiceTitle", str(entry.get("title", entry.get("label", "来源"))), 17, accent)
	)
	var subtitle := str(entry.get("subtitle", ""))
	if not subtitle.is_empty():
		text_box.add_child(_make_row_label("ChoiceSubtitle", subtitle, 13, UIPalette.TEXT_SECONDARY))
	var badge := str(entry.get("badge", ""))
	if not badge.is_empty():
		text_box.add_child(_make_row_label("ChoiceBadge", badge, 12, UIPalette.SOUL_GOLD))
	return button


func _make_row_label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_entry_pressed(entry: Dictionary) -> void:
	_finish({"success": true, "entry": entry})
