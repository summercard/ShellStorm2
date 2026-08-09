class_name WeaponAssemblyTreePanel
extends Control

## 武器装配树可视化面板
## 可挂载在当前 3D HUD 下，或独立运行。
## 按指定按键切换显示（如 Tab）
## 显示：树状结构 + 合成属性 + 节点详情
## 响应 WeaponAssemblyTree 的 tree_changed / stats_changed 信号

signal panel_shown()
signal panel_hidden()

## WeaponAssemblyTree 引用（外部传入）
var _weapon_tree: WeaponAssemblyTree = null

## 面板可见性
var _is_visible: bool = false

## 节点样式
const NODE_COLOR: Color = Color(0.25, 0.30, 0.38, 0.95)
const EDGE_COLOR: Color = Color(0.45, 0.50, 0.55, 0.7)
const STATS_BG: Color = Color(0.12, 0.15, 0.20, 0.95)
const SLOT_COLOR_MOUNT: Color = Color(0.50, 0.35, 0.25, 0.9)
const SLOT_COLOR_MUZZLE: Color = Color(0.30, 0.45, 0.50, 0.9)
const SLOT_COLOR_MAGAZINE: Color = Color(0.40, 0.35, 0.50, 0.9)
const SLOT_COLOR_BULLET: Color = Color(0.35, 0.50, 0.35, 0.9)

## 面板尺寸
const PANEL_WIDTH: float = 520.0
const PANEL_HEIGHT: float = 620.0

## 节点图标（枪身/子弹/配件）
const NODE_ICONS: Dictionary = {
	"GunBody": "🔫",
	"BULLET": "•",
	"ATTACHMENT": "⚙",
}

## Tree 节点引用
var _tree_container: VBoxContainer = null
var _stats_container: HBoxContainer = null
var _title_label: Label = null
var _identity_label: Label = null
var _fate_track_label: Label = null
var _weapon_owner: Node = null

## 节点点击详情弹窗
var _detail_popup: Panel = null
var _detail_label: Label = null
var _clicked_node_path: String = ""

## 选中节点高亮
var _selected_node: AssemblyNode = null
const SELECTED_BG_COLOR: Color = Color(0.30, 0.25, 0.40, 0.95)
const SELECTED_BORDER_COLOR: Color = Color(0.70, 0.55, 0.90, 0.9)
var _selected_row: Control = null

func _ready() -> void:
	_build_panel()
	_create_detail_popup()
	_hide_immediately()

	# 监听按键切换
	panel_shown.connect(_on_panel_shown)

	# 监听鼠标点击（用于节点点击检测）
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 必须设置为 ALWAYS，保证游戏暂停时也能接收 Tab 输入
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 面板不可见时关掉 process，仅靠 show() 时唤醒。
	set_process(false)
	UIStyleFactory.apply_tactical_tree(self)

## 构建面板UI
func _build_panel() -> void:
	name = "WeaponAssemblyTreePanel"

	# 整体容器
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# 标题栏
	_title_label = Label.new()
	_title_label.text = "武器表现页"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.70, 1.0))
	_title_label.custom_minimum_size = Vector2(PANEL_WIDTH, 32)
	vbox.add_child(_title_label)

	_identity_label = Label.new()
	_identity_label.text = "未绑定枪械实例"
	_identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_identity_label.add_theme_font_size_override("font_size", 13)
	_identity_label.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0))
	_identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_identity_label)

	_fate_track_label = Label.new()
	_fate_track_label.text = "命运永久 0/0"
	_fate_track_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fate_track_label.add_theme_font_size_override("font_size", 13)
	_fate_track_label.add_theme_color_override("font_color", Color(0.78, 0.48, 1.0))
	_fate_track_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_fate_track_label)

	# 属性总览（Horizontal）
	_stats_container = HBoxContainer.new()
	_stats_container.custom_minimum_size = Vector2(PANEL_WIDTH, 36)
	_stats_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_stats_container)

	# 树状结构容器
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_tree_container = VBoxContainer.new()
	_tree_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_tree_container)

	# 底部说明
	var hint := Label.new()
	hint.text = "命运槽永久不可拆 · 装配可更换且不占槽 | 点击节点查看来源 | [K/Tab] 关闭"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	hint.custom_minimum_size = Vector2(PANEL_WIDTH, 20)
	vbox.add_child(hint)

## 创建详情弹窗
func _create_detail_popup() -> void:
	_detail_popup = Panel.new()
	_detail_popup.z_index = 1000
	_detail_popup.custom_minimum_size = Vector2(260, 160)
	_detail_popup.visible = false
	_detail_popup.add_theme_stylebox_override(
		"panel",
		UIStyleFactory.make_tactical_panel(UIPalette.NEON_CYAN, 1, 1, 6)
	)

	# 标题
	var title := Label.new()
	title.text = "节点详情"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.70, 1.0))
	title.custom_minimum_size = Vector2(260, 28)
	title.position = Vector2(0, 4)
	_detail_popup.add_child(title)

	# 详情内容
	_detail_label = Label.new()
	_detail_label.text = ""
	_detail_label.add_theme_font_size_override("font_size", 13)
	_detail_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.60, 1.0))
	_detail_label.position = Vector2(10, 36)
	_detail_label.custom_minimum_size = Vector2(240, 110)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_popup.add_child(_detail_label)

	# 关闭按钮提示
	var close_hint := Label.new()
	close_hint.text = "点击任意处关闭"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.8))
	close_hint.position = Vector2(0, 138)
	close_hint.custom_minimum_size = Vector2(260, 18)
	_detail_popup.add_child(close_hint)

	add_child(_detail_popup)

	# 点击弹窗任意处关闭
	_detail_popup.gui_input.connect(_on_detail_popup_input)

## 弹窗输入处理
func _on_detail_popup_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_detail_popup()

func _close_detail_popup() -> void:
	if _detail_popup != null:
		_detail_popup.visible = false
		_clicked_node_path = ""

## 面板显示时重置点击追踪
func _on_panel_shown() -> void:
	pass

## 隐藏面板（立即）
func _hide_immediately() -> void:
	visible = false
	_is_visible = false
	_close_detail_popup()

## 切换显示
func toggle() -> void:
	_is_visible = not _is_visible
	visible = _is_visible
	# 面板可见时让 _process 监听 Tab/鼠标事件；不可见时挂起。
	set_process(_is_visible)
	if _is_visible:
		_refresh()
		panel_shown.emit()
	else:
		panel_hidden.emit()

func show_panel() -> void:
	if not _is_visible:
		toggle()

func hide_panel() -> void:
	if _is_visible:
		toggle()

## 设置 WeaponAssemblyTree 引用
func set_weapon_tree(wt: WeaponAssemblyTree) -> void:
	if _weapon_tree != null:
		if _weapon_tree.tree_changed.is_connected(_on_tree_changed):
			_weapon_tree.tree_changed.disconnect(_on_tree_changed)
		if _weapon_tree.stats_changed.is_connected(_on_stats_changed):
			_weapon_tree.stats_changed.disconnect(_on_stats_changed)

	_weapon_tree = wt

	if _weapon_tree != null:
		_weapon_tree.tree_changed.connect(_on_tree_changed)
		_weapon_tree.stats_changed.connect(_on_stats_changed)
		_refresh()


func set_weapon_owner(owner: Node) -> void:
	if _weapon_owner != null and is_instance_valid(_weapon_owner) and _weapon_owner.has_signal(
		"weapon_instance_changed"
	):
		if _weapon_owner.weapon_instance_changed.is_connected(_on_weapon_instance_changed):
			_weapon_owner.weapon_instance_changed.disconnect(_on_weapon_instance_changed)
	_weapon_owner = owner
	if _weapon_owner != null and _weapon_owner.has_signal("weapon_instance_changed"):
		if not _weapon_owner.weapon_instance_changed.is_connected(_on_weapon_instance_changed):
			_weapon_owner.weapon_instance_changed.connect(_on_weapon_instance_changed)
	_refresh()

## 信号回调：树结构变化
func _on_tree_changed() -> void:
	var prev_path := ""
	if _selected_node != null and is_instance_valid(_selected_node):
		prev_path = _selected_node.get_path_string()
	_refresh()
	# 树刷新后恢复选中高亮（仅在之前有有效选中时）
	if prev_path != "" and _weapon_tree != null:
		_find_and_highlight_row(_weapon_tree.get_root(), prev_path)

## 信号回调：属性变化
func _on_stats_changed(_stats: Dictionary) -> void:
	_refresh()


func _on_weapon_instance_changed(_snapshot: Dictionary) -> void:
	_refresh()

## 刷新整个面板
func _refresh() -> void:
	if not _is_visible or _weapon_tree == null:
		return

	_refresh_stats()
	_refresh_presentation_snapshot()
	_refresh_tree()


func _refresh_presentation_snapshot() -> void:
	if _identity_label == null or _fate_track_label == null:
		return
	if _weapon_owner == null or not is_instance_valid(_weapon_owner) or not _weapon_owner.has_method(
		"get_weapon_presentation_snapshot"
	):
		_identity_label.text = "兼容装配树视图 · 尚未绑定枪械实例"
		_fate_track_label.text = "命运永久槽：实例数据不可用"
		return
	var snapshot := _weapon_owner.call("get_weapon_presentation_snapshot") as Dictionary
	var used := int(snapshot.get("fate_slot_used", 0))
	var capacity := int(snapshot.get("fate_slot_capacity", 0))
	_identity_label.text = "%s · %s · #%s · %s" % [
		snapshot.get("display_name", "武器"), str(snapshot.get("rarity", "common")).to_upper(),
		snapshot.get("instance_suffix", "------"), snapshot.get("owner_location", ""),
	]
	var slots: Array[String] = []
	for index in range(1, capacity + 1):
		if index <= used:
			slots.append("%02d◆🔒" % index)
		elif index == used + 1:
			slots.append("%02d◇" % index)
		else:
			slots.append("%02d·" % index)
	_fate_track_label.text = "命运永久 %d/%d  %s" % [used, capacity, " ".join(slots)]

## 刷新属性总览（横向排列关键属性）
func _refresh_stats() -> void:
	# 清空旧
	for child in _stats_container.get_children():
		child.queue_free()

	if _weapon_tree == null or _weapon_tree.get_root() == null:
		return

	var stats: Dictionary = _weapon_tree.get_computed_stats()
	var items: Array = [
		["DPS", _compute_dps(stats)],
		["射速", "%.1f/s" % stats.get("fire_rate", 0.0)],
		["伤害", str(stats.get("damage", 0))],
		["弹量", str(_weapon_tree.current_ammo) + "/" + str(_weapon_tree.magazine_size)],
		["扩散", "%.2f" % stats.get("spread", 0.0)],
	]

	for item in items:
		var label := Label.new()
		label.text = "%s: %s" % [item[0], item[1]]
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.80, 0.75, 0.65, 1.0))
		_stats_container.add_child(label)

## 计算简单 DPS（伤害 × 射速）
func _compute_dps(stats: Dictionary) -> String:
	var damage: float = stats.get("damage", 0)
	var fire_rate: float = stats.get("fire_rate", 0)
	var dps: float = damage * fire_rate
	return "%.0f" % dps

## 刷新树状结构
func _refresh_tree() -> void:
	# 清空旧
	for child in _tree_container.get_children():
		child.queue_free()

	if _weapon_tree == null or _weapon_tree.get_root() == null:
		var empty_lbl := Label.new()
		empty_lbl.text = "(无武器)"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
		_tree_container.add_child(empty_lbl)
		return

	# 更新标题
	var root_name: String = _weapon_tree.get_root().node_name
	var depth: int = _weapon_tree.get_max_depth()
	_title_label.text = "武器表现页 · %s (装配深度%d)" % [root_name, depth]

	# 递归绘制树
	_draw_node(_weapon_tree.get_root(), _tree_container, 0)

## 递归绘制节点
func _draw_node(node: AssemblyNode, parent: VBoxContainer, indent_depth: int) -> void:
	if node == null:
		return

	# 该节点的行（用 Control 作为可点击容器）
	var row := Control.new()
	row.custom_minimum_size = Vector2(PANEL_WIDTH - 16, 28)
	row.set_meta("node_path", node.get_path_string())
	row.set_meta("node_ref", node)
	row.set_meta("node_row", row)  # 自引用，供高亮查找用
	parent.add_child(row)

	# 记录节点点击区域（用于鼠标命中检测）
	var node_path := node.get_path_string()

	# 缩进
	var indent_label := Label.new()
	var indent_text: String = ""
	for i in range(indent_depth):
		indent_text += "  "
	indent_label.text = indent_text
	indent_label.custom_minimum_size = Vector2(indent_depth * 18 + 4, 20)
	indent_label.position = Vector2(0, 4)
	row.add_child(indent_label)

	# 连接线（如果是子节点）
	if indent_depth > 0:
		var line := Label.new()
		line.text = "├─" if _has_siblings(node) else "└─"
		line.add_theme_color_override("font_color", EDGE_COLOR)
		line.position = Vector2(indent_depth * 18 + 4, 4)
		row.add_child(line)

	# 节点类型图标
	var icon_lbl := Label.new()
	var type_key: String = AssemblyNode.NodeType.keys()[node.node_type]
	icon_lbl.text = _get_node_icon(type_key)
	icon_lbl.add_theme_color_override("font_color", _get_node_color(node.node_type))
	icon_lbl.position = Vector2(indent_depth * 18 + 30, 4)
	row.add_child(icon_lbl)

	# 节点名称
	var name_lbl := Label.new()
	name_lbl.text = node.node_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70, 1.0))
	name_lbl.position = Vector2(indent_depth * 18 + 52, 4)
	row.add_child(name_lbl)
	# 等待布局完成后计算 name_lbl 的实际渲染宽度，用于定位标签
	# （get_minimum_size() 在节点未加入场景树时返回 (0,0)，需要用 size.x）
	var name_actual_width: float = name_lbl.size.x if name_lbl.size.x > 0 else name_lbl.get_minimum_size().x

	# 标签（如果有用的话）
	var tag_x := indent_depth * 18 + 52 + name_actual_width + 6
	for tag in node.tags:
		if tag.begins_with("Fate."):
			var fate_lbl := Label.new()
			fate_lbl.text = "◆"
			fate_lbl.add_theme_color_override("font_color", Color(0.8, 0.3, 0.9, 0.9))
			fate_lbl.tooltip_text = tag
			fate_lbl.position = Vector2(tag_x, 4)
			row.add_child(fate_lbl)
			tag_x += 16

	# 关键属性（从小到大）
	var stats: Dictionary = node.get_computed_stats()
	var attr_x := tag_x + 4  # 动态属性标签起始位置（随 Fate.标签累加）
	if node.node_type == AssemblyNode.NodeType.GUN_BODY:
		# 伤害
		var dmg_lbl := Label.new()
		dmg_lbl.text = "⚔%s" % stats.get("damage", 0)
		dmg_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3, 0.9))
		dmg_lbl.position = Vector2(attr_x, 4)
		row.add_child(dmg_lbl)
		attr_x += 44
		# 射速⭐
		var fr_lbl := Label.new()
		fr_lbl.text = "⭐%.1f/s" % stats.get("fire_rate", 0.0)
		fr_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.9))
		fr_lbl.position = Vector2(attr_x, 4)
		row.add_child(fr_lbl)
		attr_x += 65
		# 弹药量
		var ammo_lbl := Label.new()
		var ammo_str: String = "%d/%d" % [_weapon_tree.current_ammo, _weapon_tree.magazine_size]
		ammo_lbl.text = "弹%s" % ammo_str
		ammo_lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.8))
		ammo_lbl.position = Vector2(attr_x, 4)
		row.add_child(ammo_lbl)
	elif node.node_type == AssemblyNode.NodeType.BULLET:
		# 速度
		var spd_lbl := Label.new()
		spd_lbl.text = "•%sx" % stats.get("speed", 1.0)
		spd_lbl.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9, 0.9))
		spd_lbl.position = Vector2(attr_x, 4)
		row.add_child(spd_lbl)
		attr_x += 42
		# 扩散（spread > 0 时显示）
		var spread_val: float = stats.get("spread", 0.0)
		if spread_val > 0.0:
			var spr_lbl := Label.new()
			spr_lbl.text = "散%.1f" % spread_val
			spr_lbl.add_theme_color_override("font_color", Color(0.9, 0.65, 0.3, 0.8))
			spr_lbl.position = Vector2(attr_x, 4)
			row.add_child(spr_lbl)
			attr_x += 48
		# 暴击倍率（crit_mult > 1.0 时显示）
		var crit_mult: float = stats.get("crit_damage_multiplier", 1.0)
		if crit_mult > 1.0:
			var crit_lbl := Label.new()
			crit_lbl.text = "爆×%.1f" % crit_mult
			crit_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 0.9))
			crit_lbl.position = Vector2(attr_x, 4)
			row.add_child(crit_lbl)
			attr_x += 50
		# 穿透等级（pierce_level > 0 时显示）
		var pierce: int = int(stats.get("pierce_level", 0))
		if pierce > 0:
			var prc_lbl := Label.new()
			prc_lbl.text = "穿%d" % pierce
			prc_lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 0.55, 0.85))
			prc_lbl.position = Vector2(attr_x, 4)
			row.add_child(prc_lbl)

	# 鼠标输入连接到节点点击检测
	row.gui_input.connect(_on_node_row_input.bind(node))

	# 递归绘制子槽位（按槽位类型顺序：MOUNT > MUZZLE > MAGAZINE > BULLET）
	var slot_order: Array[int] = [
		AssemblyNode.SlotType.MOUNT,
		AssemblyNode.SlotType.MUZZLE,
		AssemblyNode.SlotType.MAGAZINE,
		AssemblyNode.SlotType.BULLET,
	]
	for slot_type in slot_order:
		var child: AssemblyNode = node.slots[slot_type]
		if child != null:
			_draw_child_with_slot(child, parent, indent_depth + 1, slot_type)
		else:
			_draw_empty_slot(parent, indent_depth + 1, slot_type)

## 绘制子节点（带槽位标签）
func _draw_child_with_slot(child: AssemblyNode, parent: VBoxContainer, indent_depth: int, slot_type: AssemblyNode.SlotType) -> void:
	if child == null:
		return
	var slot_key: String = AssemblyNode.SlotType.keys()[slot_type]
	# 记录_draw_node前parent子节点数量，这样递归完成后可以精确定位child对应的那一行
	var child_count_before: int = parent.get_child_count()
	_draw_node(child, parent, indent_depth)
	# _draw_node递归会把child的子树全部加入parent，因此要取child_count_before而不是get_child_count()-1
	var child_row: Control = parent.get_child(child_count_before) as Control
	if child_row != null:
		var slot_lbl := Label.new()
		slot_lbl.text = "←%s" % slot_key
		slot_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 0.7))
		slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slot_lbl.position = Vector2(PANEL_WIDTH - 80, 4)
		slot_lbl.custom_minimum_size = Vector2(76, 20)
		child_row.add_child(slot_lbl)

## 绘制空槽位提示
func _draw_empty_slot(parent: VBoxContainer, indent_depth: int, slot_type: AssemblyNode.SlotType) -> void:
	var slot_key: String = AssemblyNode.SlotType.keys()[slot_type]
	var slot_colors: Dictionary = {
		AssemblyNode.SlotType.MOUNT: SLOT_COLOR_MOUNT,
		AssemblyNode.SlotType.MUZZLE: SLOT_COLOR_MUZZLE,
		AssemblyNode.SlotType.MAGAZINE: SLOT_COLOR_MAGAZINE,
		AssemblyNode.SlotType.BULLET: SLOT_COLOR_BULLET,
	}
	var slot_color: Color = slot_colors.get(slot_type, SLOT_COLOR_MOUNT)

	var row := Control.new()
	row.custom_minimum_size = Vector2(PANEL_WIDTH - 16, 22)
	parent.add_child(row)

	# 缩进
	var indent_text: String = ""
	for i in range(indent_depth):
		indent_text += "  "
	var indent_lbl := Label.new()
	indent_lbl.text = indent_text
	indent_lbl.custom_minimum_size = Vector2(indent_depth * 18 + 4, 18)
	indent_lbl.position = Vector2(0, 4)
	row.add_child(indent_lbl)

	# 连接线
	var line := Label.new()
	line.text = "└─"
	line.add_theme_color_override("font_color", EDGE_COLOR)
	line.position = Vector2(indent_depth * 18 + 4, 4)
	row.add_child(line)

	# 空槽标签（虚线样式）
	var empty_lbl := Label.new()
	empty_lbl.text = "--- %s ---" % slot_key
	empty_lbl.add_theme_font_size_override("font_size", 12)
	empty_lbl.add_theme_color_override("font_color", Color(slot_color.r, slot_color.g, slot_color.b, 0.45))
	empty_lbl.position = Vector2(indent_depth * 18 + 30, 4)
	row.add_child(empty_lbl)

	# 槽位类型标签
	var slot_lbl := Label.new()
	slot_lbl.text = "←%s" % slot_key
	slot_lbl.add_theme_color_override("font_color", Color(slot_color.r, slot_color.g, slot_color.b, 0.35))
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slot_lbl.position = Vector2(PANEL_WIDTH - 80, 4)
	slot_lbl.custom_minimum_size = Vector2(76, 20)
	row.add_child(slot_lbl)

## 节点行点击检测
func _on_node_row_input(event: InputEvent, node: AssemblyNode) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_node(node)
		_show_node_detail(node)

## 选中节点高亮
func _select_node(node: AssemblyNode) -> void:
	# 取消旧选中行的高亮
	if _selected_row != null:
		_set_row_highlight(_selected_row, null)

	_selected_node = node

	# 找到新选中行（需要重新绘制后才能找到，因为 _draw_node 在 _refresh_tree 中）
	# 由于行是在 _refresh_tree 中动态创建的，我们在选中时直接高亮当前行
	# 实际上节点行在 _draw_node 创建后就被添加了，这里 _selected_row 引用的是最后创建的行
	# 正确的做法是在行 Control 上通过 node_path 查找
	_find_and_highlight_row(_weapon_tree.get_root(), node.get_path_string())

func _find_and_highlight_row(node: AssemblyNode, target_path: String) -> bool:
	if node == null or _tree_container == null:
		return false
	var node_path := node.get_path_string()
	if node_path == target_path:
		# 遍历视觉树找到对应的行（DFS，含嵌套行）
		if _find_row_in_container(_tree_container, target_path):
			return true
		return false  # 目标节点在树中但不在视觉容器中，继续搜索其他分支
	# 递归检查子节点（槽位）
	for slot_type in AssemblyNode.SlotType.values():
		var child: AssemblyNode = node.slots[slot_type]
		if child != null:
			if _find_and_highlight_row(child, target_path):
				return true
	return false

## DFS 遍历视觉树（包含嵌套在 VBoxContainer 中的行）
func _find_row_in_container(container: Control, target_path: String) -> bool:
	for child in container.get_children():
		if child.has_meta("node_ref"):
			var ref: AssemblyNode = child.get_meta("node_ref")
			if ref != null and ref.get_path_string() == target_path:
				_set_row_highlight(child, SELECTED_BG_COLOR)
				_selected_row = child
				return true
		# 递归检查嵌套容器（如 VBoxContainer）
		if child is Container and not child.is_class("ScrollContainer"):
			if _find_row_in_container(child as Control, target_path):
				return true
	return false

func _set_row_highlight(row: Control, color) -> void:
	if row == null:
		return
	# 清除现有的背景装饰
	for c in row.get_children():
		if c.has_meta("row_highlight"):
			c.queue_free()
	if color == null:
		return
	var bg := ColorRect.new()
	bg.set_meta("row_highlight", true)
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.position = Vector2(0, 0)
	bg.size = row.custom_minimum_size
	bg.z_index = -1
	row.add_child(bg)
	# 给 border 颜色（用 StyleBoxFlat）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(1)
	style.set_border_color(SELECTED_BORDER_COLOR)
	style.set_corner_radius_all(3)
	row.add_theme_stylebox_override("hover", style)

## 显示节点详情弹窗
func _show_node_detail(node: AssemblyNode) -> void:
	if node == null or _detail_popup == null or _detail_label == null:
		return

	_clicked_node_path = node.get_path_string()

	# 构建详情文本
	var type_str: String = str(AssemblyNode.NodeType.keys()[node.node_type])
	var stats: Dictionary = node.get_computed_stats()
	var base_stats: Dictionary = node.get_base_stats()

	var lines: Array[String] = []
	lines.push_back("[b]%s[/b] %s" % [type_str, node.node_name])
	lines.push_back("")
	lines.push_back("路径: %s" % node.get_path_string())
	lines.push_back("深度: %d" % node.depth)

	if not base_stats.is_empty():
		lines.push_back("")
		lines.push_back("基础属性:")
		for k in base_stats:
			lines.push_back("  %s: %s" % [k, str(base_stats[k])])

	if not stats.is_empty():
		lines.push_back("")
		lines.push_back("合成属性:")
		for k in stats:
			lines.push_back("  %s: %s" % [k, str(stats[k])])

	if not node.tags.is_empty():
		lines.push_back("")
		lines.push_back("标签:")
		for t in node.tags:
			lines.push_back("  • %s" % t)

	# 槽位信息
	var slot_lines: Array[String] = []
	for st in AssemblyNode.SlotType.keys():
		var idx = AssemblyNode.SlotType.get(st)
		var child = node.slots[idx]
		if child != null:
			slot_lines.push_back("  %s → %s" % [st, child.node_name])

	if not slot_lines.is_empty():
		lines.push_back("")
		lines.push_back("已挂载槽位:")
		for sl in slot_lines:
			lines.push_back(sl)

	_detail_label.text = "\n".join(lines)

	# 计算弹窗位置（相对于面板右下角）
	var panel_pos := position
	var popup_pos := Vector2(
		panel_pos.x + PANEL_WIDTH - 270,
		panel_pos.y + PANEL_HEIGHT - 170
	)
	_detail_popup.position = popup_pos
	_detail_popup.visible = true

## 获取节点图标（文本 emoji）
func _get_node_icon(type_key: String) -> String:
	return NODE_ICONS.get(type_key, "?")

## 获取节点颜色（按类型）
func _get_node_color(node_type: int) -> Color:
	match node_type:
		AssemblyNode.NodeType.GUN_BODY:
			return Color(0.60, 0.75, 0.90, 1.0)
		AssemblyNode.NodeType.BULLET:
			return Color(0.50, 0.85, 0.55, 1.0)
		AssemblyNode.NodeType.ATTACHMENT:
			return Color(0.85, 0.70, 0.40, 1.0)
		_:
			return Color(0.6, 0.6, 0.6, 1.0)

## 是否有兄弟节点（用于决定连接线样式）
func _has_siblings(node: AssemblyNode) -> bool:
	if node.parent_node == null:
		return false
	for slot_type in node.parent_node.slots:
		var sibling: AssemblyNode = node.parent_node.slots[slot_type]
		if sibling != null and sibling != node:
			return true
	return false

func _process(_delta: float) -> void:
	# 检测切换键（Tab）
	if Input.is_action_just_pressed("ui_tab"):
		toggle()
