class_name WeaponAssemblyTreePanel
extends Control

## K 页只拥有显示生命周期；K / ESC 与玩家输入锁由宿主负责。
signal panel_shown()
signal panel_hidden()
const TRANSITION := preload("res://src/ui/weapon_build/WeaponHologramTransition.gd")
const BOARD_PATH := "res://assets/art/ui/weapon_build/weapon_build_board.tscn"
var _weapon_tree: WeaponAssemblyTree = null
var _owner: Node = null
var _weapon_owner: Node = null
var _identity_label: Label
var _fate_track_label: Label
var _is_visible := false
var _closing := false
var _transition_serial := 0
var _board: Control
var _header: Label
var _hint: Label
var _close_button: Button
var _animation: Tween
var _previous_focus: WeakRef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta("ui_prism_exempt", true)
	_build_panel()
	resized.connect(_layout)
	visible = false
	if is_instance_valid(_owner):
		_board.call("set_weapon_owner", _owner)
	else:
		_board.call("set_weapon_tree", _weapon_tree)
	_layout()

func _build_panel() -> void:
	_header = Label.new()
	_header.text = "武器构建 / 命运刻印"
	_header.add_theme_font_override("font", UIStyleFactory.make_prism_font(3))
	_header.add_theme_font_size_override("font_size", 23)
	_header.add_theme_color_override("font_color", UIPalette.PRISM_TEXT)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)
	_hint = Label.new()
	_hint.text = "永久升级，不可拆卸    /    拖动枪身旋转 · 滚轮 / 拖动轨道 · 方向键聚焦"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", UIPalette.PRISM_LABEL)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.clip_text = true
	add_child(_hint)
	_close_button = Button.new()
	_close_button.text = "收起"
	_close_button.add_theme_font_size_override("font_size", 15)
	UIStyleFactory.apply_prism_button(_close_button, "ghost", 0, 15, 1, "none")
	_close_button.pressed.connect(hide_panel)
	add_child(_close_button)
	var scene := load(BOARD_PATH) as PackedScene
	_board = scene.instantiate() as Control
	_board.name = "WeaponBuildBoard"
	add_child(_board)
	_board.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_board.connect("presentation_changed", _on_presentation_changed)
	# 保留旧探针可读 Label，不再把整棵树输出成文本表格。
	_identity_label = Label.new()
	_identity_label.name = "IdentityProbe"
	_identity_label.hide()
	add_child(_identity_label)
	_fate_track_label = Label.new()
	_fate_track_label.name = "FateTrackProbe"
	_fate_track_label.hide()
	add_child(_fate_track_label)

func _layout() -> void:
	if _board == null:
		return
	_header.position = Vector2(18, 8)
	_header.size = Vector2(maxf(1, size.x - 130), 32)
	_close_button.position = Vector2(maxf(0, size.x - 94), 7)
	_close_button.size = Vector2(76, 32)
	_hint.position = Vector2(18, size.y - 27)
	_hint.size = Vector2(maxf(1, size.x - 36), 22)
	_board.position = Vector2(0, 46)
	_board.size = Vector2(size.x, maxf(1, size.y - 79))
	queue_redraw()

func _draw() -> void:
	var color := UIPalette.PRISM_LINE_SOFT
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var sx := 1.0 if corner.x == 0 else -1.0
		var sy := 1.0 if corner.y == 0 else -1.0
		draw_line(corner, corner + Vector2(sx * 24, 0), color, 2.0)
		draw_line(corner, corner + Vector2(0, sy * 18), color, 2.0)
	draw_line(Vector2(18, 42), Vector2(size.x - 18, 42), UIPalette.PRISM_LINE_FAINT)

func toggle() -> void:
	if _is_visible and not _closing:
		hide_panel()
	else:
		show_panel()

func show_panel() -> void:
	if not is_node_ready():
		call_deferred("show_panel")
		return
	if _is_visible and not _closing:
		return
	_transition_serial += 1
	_closing = false
	_is_visible = true
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and not is_ancestor_of(focused):
		_previous_focus = weakref(focused)
	show()
	_board.call("refresh_from_owner")
	_animation = TRANSITION.open(self, _owner)
	_close_button.grab_focus()
	panel_shown.emit()

func hide_panel() -> void:
	if not _is_visible or _closing or not is_node_ready():
		return
	_closing = true
	_transition_serial += 1
	var serial := _transition_serial
	_animation = TRANSITION.close(self, _owner)
	_animation.finished.connect(func() -> void:
		if serial != _transition_serial:
			return
		_closing = false
		_is_visible = false
		if _previous_focus != null:
			var focused := _previous_focus.get_ref() as Control
			if is_instance_valid(focused) and focused.is_visible_in_tree():
				focused.grab_focus()
		_previous_focus = null
		panel_hidden.emit())

func set_weapon_tree(tree: WeaponAssemblyTree) -> void:
	_weapon_tree = tree
	if _board != null:
		if is_instance_valid(_owner):
			_board.call("refresh_from_owner")
		else:
			_board.call("set_weapon_tree", tree)

func set_weapon_owner(owner: Node) -> void:
	_owner = owner
	_weapon_owner = owner
	if _board != null:
		_board.call("set_weapon_owner", owner)

func get_build_board() -> Control:
	return _board

func refresh_from_owner() -> void:
	if _board != null:
		_board.call("refresh_from_owner")

func _on_presentation_changed(snapshot: Dictionary) -> void:
	_weapon_tree = _board.get("_weapon_tree") as WeaponAssemblyTree
	_identity_label.text = GameText.text("panel.identity_format", [snapshot.get("display_name", "未装备武器"), GameText.rarity_name(str(snapshot.get("rarity", "common"))), snapshot.get("instance_suffix", "------"), GameText.location_name(str(snapshot.get("owner_location", "")))])
	var labels: Array[String] = []
	for entry: Dictionary in snapshot.get("cards", []):
		labels.append("%02d %s" % [int(entry.get("slot_index", 0)), "已刻印" if bool(entry.get("occupied", false)) else "空"])
	_fate_track_label.text = GameText.text("panel.fate_track_format", [int(snapshot.get("used", 0)), int(snapshot.get("slot_count", 0)), " / ".join(labels)])
