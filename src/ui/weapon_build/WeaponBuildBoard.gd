extends Control

## 只读表现：所有槽序遵循 WeaponInstance 的 1 起始永久槽编号。
signal presentation_changed(snapshot: Dictionary)
const SOCKET := preload("res://src/ui/weapon_build/WeaponBuildSocket.gd")
const TRACK := preload("res://src/ui/weapon_build/WeaponBuildTrack.gd")
const PREVIEW := preload("res://src/ui/weapon_build/WeaponBuildPreview3D.gd")
const CARD_VIEW := preload("res://src/weapons/FateCardView.gd")
const IMPACT_PATH := "res://assets/art/ui/weapon_build/vfx_card_socket_impact.tscn"
var _owner: Node
var _weapon_tree: WeaponAssemblyTree
var _compact := false
var _snapshot: Dictionary = {}
var _item: Dictionary = {}
var _records: Dictionary = {}
var _cards: Dictionary = {}
var _branches: Array[Dictionary] = []
var _sockets: Array[Control] = []
var _pending_slot := -1
var _pending_identity := ""
var _animation_epoch := 0
var _refresh_queued := false
var _refreshing := false
var _preview_key := ""
var _inspected_slot := 0
var _dragging := false
var _drag_position := Vector2.ZERO
var _drag_scroll := 0
var _title: Label
var _identity: Label
var _counter: Label
var _counter_row: HBoxContainer
var _detail: Label
var _scope: Label
var _preview: Control
var _preview_input: Control
var _module_scroll: ScrollContainer
var _modules: VBoxContainer
var _scroll: ScrollContainer
var _canvas: Control
var _track: Control
var _effects: Control
var _flight_surface: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_meta("ui_prism_exempt", true)
	_build()
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	refresh_from_owner()

func _exit_tree() -> void:
	_disconnect_owner()
	_bind_tree(null)
	_animation_epoch += 1

func _build() -> void:
	_title = _label("未装备武器", 23, UIPalette.PRISM_TEXT)
	_identity = _label("实例未绑定", 12, UIPalette.PRISM_LABEL)
	_counter_row = HBoxContainer.new()
	_counter_row.name = "FateImprintHeader"
	_counter_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter_row.add_theme_constant_override("separation", 8)
	add_child(_counter_row)
	var imprint_title := _label("命运刻印", 19, UIPalette.PRISM_TEXT)
	imprint_title.name = "FateImprintTitle"
	# HBox 使用内容最小宽度；裁切型Label会把最小宽度压到0，导致只剩星标。
	imprint_title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	imprint_title.reparent(_counter_row)
	var star: Control = CARD_VIEW.SCOPE_GLYPH.new()
	star.name = "FateImprintStar"
	star.call("configure", FateCard.Scope.WEAPON)
	star.custom_minimum_size = Vector2(24, 24)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_counter_row.add_child(star)
	_counter = _label("0 / 0", 19, UIPalette.PRISM_TEXT)
	_counter.name = "FateImprintCount"
	_counter.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_counter.reparent(_counter_row)
	_preview = PREVIEW.new()
	_preview.name = "WeaponOriginal3D"
	_preview.set("icon_resolution", 512)
	add_child(_preview)
	_preview_input = Control.new()
	_preview_input.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_input.gui_input.connect(_on_preview_input)
	add_child(_preview_input)
	_module_scroll = ScrollContainer.new()
	_module_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_module_scroll)
	_modules = VBoxContainer.new()
	_modules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modules.add_theme_constant_override("separation", 5)
	_module_scroll.add_child(_modules)
	_scroll = ScrollContainer.new()
	_scroll.name = "FateSocketViewport"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.clip_contents = true
	_scroll.gui_input.connect(_on_track_input)
	add_child(_scroll)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.gui_input.connect(_on_track_input)
	_scroll.add_child(_canvas)
	_track = TRACK.new()
	_canvas.add_child(_track)
	_detail = _label("悬停或聚焦卡巢查看刻印详情", 12, UIPalette.PRISM_LABEL)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.clip_text = true
	_scope = _label("", 16, UIPalette.PRISM_TEXT)
	_scope.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scope.visible = false
	_effects = Control.new()
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_effects.z_index = 20
	add_child(_effects)
	# 独立 CanvasLayer 防止飞行卡被下半区裁剪；没有任何输入捕获。
	var flight_layer := CanvasLayer.new()
	flight_layer.layer = 100
	add_child(flight_layer)
	_flight_surface = Control.new()
	_flight_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_layer.add_child(_flight_surface)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", UIStyleFactory.make_prism_font(1))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(label)
	return label

func set_weapon_owner(owner: Node) -> void:
	if _owner != owner:
		_disconnect_owner()
		_cancel_install()
		_owner = owner
		_bind_tree(null)
		if is_instance_valid(_owner):
			for signal_name in ["weapon_instance_changed", "weapon_loadout_changed", "weapon_changed"]:
				if _owner.has_signal(signal_name):
					_owner.connect(signal_name, _queue_refresh)
	refresh_from_owner()

func _disconnect_owner() -> void:
	if is_instance_valid(_owner):
		for signal_name in ["weapon_instance_changed", "weapon_loadout_changed", "weapon_changed"]:
			if _owner.has_signal(signal_name) and _owner.is_connected(signal_name, _queue_refresh):
				_owner.disconnect(signal_name, _queue_refresh)

func set_weapon_tree(tree: WeaponAssemblyTree) -> void:
	_disconnect_owner()
	_owner = null
	_cancel_install()
	_bind_tree(tree)
	refresh_from_owner()

func _bind_tree(tree: WeaponAssemblyTree) -> void:
	if _weapon_tree == tree:
		return
	if is_instance_valid(_weapon_tree):
		for signal_name in ["tree_changed", "stats_changed"]:
			if _weapon_tree.is_connected(signal_name, _queue_refresh):
				_weapon_tree.disconnect(signal_name, _queue_refresh)
	_weapon_tree = tree
	if is_instance_valid(tree):
		for signal_name in ["tree_changed", "stats_changed"]:
			tree.connect(signal_name, _queue_refresh)

func _queue_refresh(_a: Variant = null, _b: Variant = null) -> void:
	if _refresh_queued or _refreshing or not is_inside_tree():
		return
	_refresh_queued = true
	call_deferred("refresh_from_owner")

func refresh_from_owner() -> void:
	_refresh_queued = false
	if not is_node_ready() or _refreshing:
		return
	_refreshing = true
	var snapshot: Dictionary = {}
	_item = {}
	if is_instance_valid(_owner):
		_bind_tree(_property(_owner, "weapon_tree") as WeaponAssemblyTree)
		if _owner.has_method("get_weapon_presentation_snapshot"):
			var value: Variant = _owner.call("get_weapon_presentation_snapshot")
			if value is Dictionary:
				snapshot = value.duplicate(true)
		if _owner.has_method("get_equipped_weapon_item"):
			var value: Variant = _owner.call("get_equipped_weapon_item")
			if value is Dictionary:
				_item = value.duplicate(true)
	if is_instance_valid(_weapon_tree) and _weapon_tree.get_root() != null:
		var root := _weapon_tree.get_root()
		if _item.is_empty():
			_item = ItemRegistry.get_instance().get_item(WeaponInstance.content_id_for_root(root)).duplicate(true)
			_item["type"] = "weapon"
			_item["assembly_id"] = WeaponInstance.assembly_id_for_root(root)
		# 仅序列化为预览快照，不构造或回写 WeaponInstance。
		_item["assembly_snapshot"] = WeaponInstance._serialize_node(root)
		if snapshot.is_empty():
			snapshot = {"display_name": GameText.node_name(root.node_name), "fate_slot_capacity": int(_item.get("fate_slot_capacity", 8)), "fate_upgrades": _item.get("fate_upgrades", []), "rarity": _item.get("rarity", "common")}
	var nested: Dictionary = _item.get("weapon_instance", {})
	for key in ["display_name", "rarity", "weapon_instance_id", "instance_suffix", "drop_grade_display", "drop_grade_color"]:
		if not snapshot.has(key) and (_item.has(key) or nested.has(key)):
			snapshot[key] = _item.get(key, nested.get(key))
	if not snapshot.has("display_name") and _item.has("name"):
		snapshot["display_name"] = _item["name"]
	if not snapshot.has("fate_upgrades"):
		snapshot["fate_upgrades"] = _item.get("fate_upgrades", nested.get("fate_upgrades", []))
	if not snapshot.has("fate_slot_capacity"):
		snapshot["fate_slot_capacity"] = _item.get("fate_slot_capacity", nested.get("fate_slot_capacity", 0))
	var identity := str(snapshot.get("weapon_instance_id", _item.get("weapon_instance_id", "")))
	if _pending_slot > 0 and identity != _pending_identity:
		_cancel_install()
	_snapshot = snapshot
	_snapshot["weapon_instance_id"] = identity
	_records.clear()
	_cards.clear()
	for entry: Variant in snapshot.get("fate_upgrades", []):
		if not entry is Dictionary:
			continue
		var index := int(entry.get("slot_index", 0))
		if index < 1:
			continue
		_records[index] = entry.duplicate(true)
		var card := FateCardPresets.get_by_card_id(str(entry.get("stable_card_id", "")))
		if card == null:
			card = FateCard.new()
			card.stable_card_id = str(entry.get("stable_card_id", ""))
			card.card_name = str(entry.get("tarot_name", "既有刻印"))
			card.description = "此刻印未在当前牌库中，保留原槽与冻结参数。"
		card.set_orientation(FateCard.Orientation.REVERSED if str(entry.get("orientation", "UPRIGHT")) == "REVERSED" else FateCard.Orientation.UPRIGHT)
		_cards[index] = card
	_branches.clear()
	if is_instance_valid(_weapon_tree) and _weapon_tree.get_root() != null:
		_collect_branches(_weapon_tree.get_root())
	_title.text = str(snapshot.get("display_name", "未装备武器"))
	var rarity := GameText.rarity_name(str(snapshot.get("rarity", "common")))
	_identity.text = "%s · %s\n实例 #%s  %s" % [str(snapshot.get("drop_grade_display", "品质未标注")), rarity, str(snapshot.get("instance_suffix", identity.right(6) if not identity.is_empty() else "------")), GameText.location_name(str(snapshot.get("owner_location", "")))]
	_identity.tooltip_text = identity
	_identity.mouse_filter = Control.MOUSE_FILTER_PASS
	_identity.add_theme_color_override("font_color", snapshot.get("drop_grade_color", UIPalette.PRISM_LABEL))
	_counter.text = "%d / %d" % [_visible_used(), _capacity()]
	_update_modules()
	_rebuild_sockets()
	var preview_key := var_to_str([identity, _item.get("assembly_snapshot", nested.get("assembly_snapshot", {})), _item.get("assembly_id", ""), _item.get("drop_grade", ""), _item.get("fate_upgrades", []), _branches])
	if preview_key != _preview_key:
		_preview_key = preview_key
		_preview.call("present_item", _item)
	_refreshing = false
	_layout()
	if _inspected_slot > 0:
		_inspect(_inspected_slot)
	presentation_changed.emit(get_presentation_snapshot())

func _property(object: Object, key: String) -> Variant:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == key:
			return object.get(key)
	return null

func _capacity() -> int:
	return maxi(0, int(_snapshot.get("fate_slot_capacity", 0)))

func _visible_used() -> int:
	return _records.size() - (1 if _records.has(_pending_slot) else 0)

func _collect_branches(node: AssemblyNode) -> void:
	if node.node_type == AssemblyNode.NodeType.GUN_BODY and node.parent_node != null:
		var kind := ""
		if "Fate.AttachedGun" in node.tags:
			kind = "fate_bullet_carry_gun"
		elif "Fate.SecondaryGun" in node.tags:
			kind = "fate_gun_on_gun"
		if not kind.is_empty():
			_branches.append({"kind": kind, "display_name": GameText.node_name(node.node_name), "node_path": node.get_path_string(), "mapping": "shared_unmapped", "module_names": _node_module_names(node)})
	for value: Variant in node.slots.values():
		var child := value as AssemblyNode
		if child != null:
			_collect_branches(child)

func _node_module_names(node: AssemblyNode) -> Array[String]:
	var names: Array[String] = []
	for key: Variant in node.slots:
		var child := node.slots[key] as AssemblyNode
		if child != null and child.node_type != AssemblyNode.NodeType.GUN_BODY:
			names.append(GameText.node_name(child.node_name))
	return names

func _update_modules() -> void:
	for child in _modules.get_children():
		_modules.remove_child(child)
		child.queue_free()
	var lines: Array[String] = []
	if is_instance_valid(_weapon_tree) and _weapon_tree.get_root() != null:
		var root := _weapon_tree.get_root()
		var bullet := root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
		lines.append("弹种 / " + (GameText.node_name(bullet.node_name) if bullet != null else "无弹种模块"))
		for slot: int in AssemblyNode.PUBLIC_ATTACHMENT_SLOTS:
			if not root.supports_attachment_slot(slot):
				continue
			var node := root.slots.get(slot) as AssemblyNode
			lines.append("%s / %s" % [GameText.slot_key_name(str(AssemblyNode.SlotType.keys()[slot])), GameText.node_name(node.node_name) if node != null else "空"])
	else:
		var bullet: Dictionary = _snapshot.get("bullet_module", {})
		lines.append("弹种 / " + str(bullet.get("display_name", "无弹种模块")))
		for entry: Dictionary in _snapshot.get("attachment_layout", []):
			if not bool(entry.get("supported", false)):
				continue
			var node_name := str(entry.get("installed_node_name", ""))
			lines.append("%s / %s" % [str(entry.get("display_name", "配件")), GameText.node_name(node_name) if not node_name.is_empty() else "空"])
	lines.append("只读装配 · 不占命运槽")
	for text: String in lines:
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.12, 0.08, 0.38)
		style.border_color = Color(0.82, 0.69, 0.43, 0.72)
		style.border_width_left = 2
		style.content_margin_left = 8
		style.content_margin_right = 5
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		row.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.88, 0.80, 0.63))
		row.add_child(label)
		_modules.add_child(row)

func _branches_for(record: Dictionary) -> Array:
	var result: Array = []
	for branch: Dictionary in _branches:
		if branch["kind"] == str(record.get("stable_card_id", "")):
			result.append(branch)
	return result

func _rebuild_sockets() -> void:
	var focused := 0
	for socket: Control in _sockets:
		if socket.has_focus():
			focused = int(socket.get("slot_index"))
		_canvas.remove_child(socket)
		socket.queue_free()
	_sockets.clear()
	for index in range(1, _capacity() + 1):
		var socket: Control = SOCKET.new()
		socket.name = "FateSocket%02d" % index
		_canvas.add_child(socket)
		var record: Dictionary = _records.get(index, {})
		socket.call("configure", index, record, _cards.get(index), index == _pending_slot, index == _visible_used() + 1, _branches_for(record))
		socket.connect("inspected", _inspect)
		socket.gui_input.connect(_on_track_input)
		_sockets.append(socket)
	for i in _sockets.size():
		var socket := _sockets[i]
		socket.focus_neighbor_left = socket.get_path_to(_sockets[maxi(0, i - 1)])
		socket.focus_neighbor_right = socket.get_path_to(_sockets[mini(_sockets.size() - 1, i + 1)])
		socket.focus_previous = socket.focus_neighbor_left
		socket.focus_next = socket.focus_neighbor_right
	if focused > 0 and focused <= _sockets.size():
		_sockets[focused - 1].grab_focus()

func set_compact(value: bool) -> void:
	_compact = value
	if is_node_ready():
		_layout()

func _layout() -> void:
	if _scroll == null:
		return
	var left_width := clampf(size.x * 0.235, 180.0, 268.0)
	var right_x := left_width + 28.0
	_title.position = Vector2(18, 12)
	_title.size = Vector2(left_width - 20, 30)
	_identity.position = Vector2(18, 46)
	_identity.size = Vector2(left_width - 20, 40)
	_counter_row.position = Vector2(right_x, 14)
	_counter_row.size = Vector2(maxf(1, size.x - right_x - 18), 28)
	var module_height := 66.0 if _compact else 110.0
	_preview.position = Vector2(14, 87)
	_preview.size = Vector2(left_width - 8, maxf(42, size.y - module_height - 109))
	_preview_input.position = _preview.position
	_preview_input.size = _preview.size
	_module_scroll.position = Vector2(18, size.y - module_height - 12)
	_module_scroll.size = Vector2(left_width - 20, module_height)
	_scroll.position = Vector2(right_x, 50)
	_scroll.size = Vector2(maxf(1, size.x - right_x - 18), maxf(1, size.y - (100 if _compact else 118)))
	var track_height := maxf(1, _scroll.size.y - 14)
	var socket_width := 76.0 if _compact else 84.0
	# 焊盘之间留出真正可见的走线；紧凑购卡页也不挤成一排图标。
	var pitch := socket_width + (40.0 if _compact else 38.0)
	var stagger := minf(8.0 if _compact else 52.0, track_height * 0.20)
	var socket_height := minf(200.0 if not _compact else 164.0, maxf(1, track_height - stagger - 6))
	_canvas.custom_minimum_size = Vector2(maxf(_scroll.size.x, pitch * _sockets.size() + 24), track_height)
	_canvas.size = _canvas.custom_minimum_size
	_track.size = _canvas.size
	var segments: Array[Dictionary] = []
	for i in _sockets.size():
		var socket := _sockets[i]
		socket.position = Vector2(14 + i * pitch, 3 + (stagger if i % 2 == 1 else 0.0))
		socket.size = Vector2(socket_width, socket_height)
		var end := socket.position + Vector2(0, socket_height * 0.45)
		var start := Vector2(0, track_height * 0.5)
		if i > 0:
			var previous := _sockets[i - 1]
			start = previous.position + Vector2(socket_width, socket_height * 0.45)
		var bend := (start.x + end.x) * 0.5
		segments.append({"to_slot": i + 1, "active": _records.has(i + 1) and i + 1 != _pending_slot, "points": PackedVector2Array([start, Vector2(bend, start.y), Vector2(bend, end.y), end])})
	_track.call("set_segments", segments)
	_detail.position = Vector2(right_x, size.y - (44 if _compact else 60))
	_detail.size = Vector2(maxf(1, size.x - right_x - 20), 36 if _compact else 52)
	_scope.position = Vector2(right_x, size.y - 65)
	_scope.size = Vector2(maxf(1, size.x - right_x - 20), 40)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIPalette.PRISM_SURFACE)
	var divider := clampf(size.x * 0.235, 180.0, 268.0) + 12.0
	draw_line(Vector2(divider, 15), Vector2(divider, size.y - 15), UIPalette.PRISM_LINE_SOFT)
	draw_line(Vector2(divider + 16, 46), Vector2(size.x - 18, 46), UIPalette.PRISM_LINE_SOFT)
	var detail_rule_y := size.y - (48 if _compact else 67)
	draw_line(Vector2(divider + 16, detail_rule_y), Vector2(size.x - 18, detail_rule_y), UIPalette.PRISM_LINE_FAINT)
	for x in range(18, int(size.x) - 18, 24):
		draw_line(Vector2(x, 2), Vector2(x, 5 if x % 3 else 8), UIPalette.PRISM_LINE_FAINT)

func _inspect(slot_index: int) -> void:
	_inspected_slot = slot_index
	_detail.tooltip_text = ""
	if slot_index > 0 and slot_index <= _sockets.size() and _sockets[slot_index - 1].has_focus():
		ensure_slot_visible(slot_index)
	var card := _cards.get(slot_index) as FateCard
	if slot_index == _pending_slot:
		_detail.text = "永久槽 %02d / 刻印同步中" % slot_index
	elif card != null:
		var record: Dictionary = _records.get(slot_index, {})
		var effect := card.short_description if not card.short_description.is_empty() else card.description
		var frozen: Dictionary = record.get("effect_params_snapshot", {})
		_detail.text = "%02d / %s · %s · 永久不可拆卸\n%s" % [slot_index, card.card_name, "逆位" if card.is_reversed() else "正位", effect]
		_detail.tooltip_text = _detail.text + "\n" + card.description + "\n冻结参数：" + var_to_str(frozen)
		var branches := _branches_for(record)
		if not branches.is_empty():
			_detail.text += " · 同类来源 %d（无逐槽映射）" % branches.size()
			for branch: Dictionary in branches:
				_detail.tooltip_text += "\n" + str(branch["display_name"]) + " / " + "、".join(branch["module_names"])
	else:
		_detail.text = "永久槽 %02d / %s\n顺序刻印，不可替换；空巢尚未生效。" % [slot_index, "下一可用槽" if slot_index == _visible_used() + 1 else "未激活"]
	_detail.mouse_filter = Control.MOUSE_FILTER_PASS

func get_slot_global_rect(slot_index: int) -> Rect2:
	if slot_index < 1 or slot_index > _sockets.size():
		return Rect2()
	return _sockets[slot_index - 1].call("get_art_global_rect")

func ensure_slot_visible(slot_index: int) -> void:
	if _scroll == null or slot_index < 1 or slot_index > _sockets.size():
		return
	var socket := _sockets[slot_index - 1]
	var low := socket.position.x - 12.0
	var high := socket.position.x + socket.size.x + 12.0
	if low < _scroll.scroll_horizontal:
		_scroll.scroll_horizontal = int(low)
	elif high > _scroll.scroll_horizontal + _scroll.size.x:
		_scroll.scroll_horizontal = int(high - _scroll.size.x)

func get_presentation_snapshot() -> Dictionary:
	var result := _snapshot.duplicate(true)
	var cards: Array[Dictionary] = []
	for index in range(1, _capacity() + 1):
		var record: Dictionary = _records.get(index, {})
		var occupied := not record.is_empty() and index != _pending_slot
		var effect_brief := GameText.fate_effect_brief(str(record.get("stable_card_id", "")), str(record.get("orientation", "UPRIGHT")) == "REVERSED") if occupied else ""
		cards.append({"slot_index": index, "stable_card_id": record.get("stable_card_id", ""), "orientation": record.get("orientation", "UPRIGHT"), "occupied": occupied, "pending": index == _pending_slot, "shows_back": record.is_empty() or index == _pending_slot, "effect_brief": effect_brief})
	result.merge({"cards": cards, "slot_count": _capacity(), "used": _visible_used(), "committed_used": _records.size(), "pending_slot": _pending_slot, "branch_count": _branches.size(), "branches": _branches.duplicate(true), "branch_mapping": "shared_unmapped", "flow_segments": _track.get("segments").duplicate(true) if _track != null else [], "compact": _compact, "scroll_horizontal": _scroll.scroll_horizontal if _scroll != null else 0, "preview": _preview.call("get_snapshot") if _preview != null else {}}, true)
	return result

func set_pending_install(slot_index: int) -> void:
	_pending_slot = slot_index
	_pending_identity = str(_snapshot.get("weapon_instance_id", _item.get("weapon_instance_id", "")))
	if is_node_ready():
		refresh_from_owner()

func clear_pending_install() -> void:
	_pending_slot = -1
	_pending_identity = ""
	if is_node_ready():
		refresh_from_owner()

func _cancel_install() -> void:
	_animation_epoch += 1
	_pending_slot = -1
	_pending_identity = ""
	for surface: Control in [_effects, _flight_surface]:
		if surface == null:
			continue
		for child in surface.get_children():
			# 让在途协程自行结束并释放，避免宿主 await 永久悬挂。
			if child is CanvasItem:
				child.hide()

func play_card_install(card: FateCard, slot_index: int, from_global_rect: Rect2) -> void:
	if card == null or not card.occupies_weapon_slot():
		if card != null:
			await play_scope_feedback(card)
		return
	if slot_index < 1 or slot_index > _capacity():
		clear_pending_install()
		return
	_cancel_install()
	var epoch := _animation_epoch
	set_pending_install(slot_index)
	ensure_slot_visible(slot_index)
	await get_tree().process_frame
	if epoch != _animation_epoch or not is_inside_tree():
		return
	ensure_slot_visible(slot_index)
	var landing := get_slot_global_rect(slot_index)
	var inverse := _flight_surface.get_global_transform_with_canvas().affine_inverse() * get_canvas_transform()
	var destination := inverse * landing.position
	var destination_size := inverse.basis_xform(landing.size).abs()
	var flyer := Control.new()
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flight_surface.add_child(flyer)
	flyer.position = inverse * from_global_rect.position
	flyer.size = inverse.basis_xform(from_global_rect.size).abs()
	if flyer.size.x < 1 or flyer.size.y < 1:
		flyer.size = destination_size * 1.8
		flyer.position = destination - Vector2(0, 100)
	var art := CARD_VIEW.build_art_layer(flyer, CARD_VIEW.art_for(card), card.is_reversed(), "InstallFace")
	art.material = null
	var reduced := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	if not reduced:
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(flyer, "position", destination, 0.46)
		tween.tween_property(flyer, "size", destination_size, 0.46)
		tween.tween_property(art, "scale:x", 0.04, 0.17)
		tween.tween_property(art, "scale:x", 1.0, 0.20).set_delay(0.17)
		await tween.finished
	else:
		await get_tree().process_frame
	if epoch != _animation_epoch:
		if is_instance_valid(flyer):
			flyer.queue_free()
		return
	# 期间允许用户继续滚动，落巢时再次取当前槽位，而不是沿用旧落点。
	ensure_slot_visible(slot_index)
	landing = get_slot_global_rect(slot_index)
	flyer.position = inverse * landing.position
	flyer.size = inverse.basis_xform(landing.size).abs()
	await _play_impact(landing.get_center(), reduced)
	if is_instance_valid(flyer):
		flyer.queue_free()
	if epoch == _animation_epoch:
		clear_pending_install()

func _play_impact(global_point: Vector2, reduced: bool) -> void:
	var prefab := load(IMPACT_PATH) as PackedScene
	if prefab == null:
		return
	var effect: Control = prefab.instantiate()
	_effects.add_child(effect)
	effect.size = size
	await effect.call("play", _effects.get_global_transform().affine_inverse() * global_point, reduced)
	if is_instance_valid(effect):
		effect.queue_free()

func play_scope_feedback(card: FateCard) -> void:
	if card == null or not is_node_ready():
		return
	_cancel_install()
	_scope.text = "%s · %s 已生效 · 不占武器槽" % [FateCard.scope_display_name(card.scope), card.card_name]
	_scope.modulate.a = 1.0
	_scope.show()
	_detail.hide()
	var epoch := _animation_epoch
	await _play_impact(_scope.get_global_rect().get_center(), bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)))
	if epoch == _animation_epoch and is_instance_valid(_scope):
		_scope.hide()
		_detail.show()

func _on_track_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT] and event.pressed:
			_scroll.scroll_horizontal += -64 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 64
			_scroll.accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_drag_position = get_global_mouse_position()
			_drag_scroll = _scroll.scroll_horizontal
	elif event is InputEventMouseMotion and _dragging:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_dragging = false
			return
		_scroll.scroll_horizontal = _drag_scroll + int(_drag_position.x - get_global_mouse_position().x)
		_scroll.accept_event()
	elif event is InputEventPanGesture:
		_scroll.scroll_horizontal += int((event.delta.x + event.delta.y) * 36)
		_scroll.accept_event()

func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_preview.call("rotate_preview", event.relative.x)
		_preview_input.accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_preview.call("set_camera_size_multiplier", float((_preview.call("get_snapshot") as Dictionary).get("camera_size_multiplier", 1.0)) - 0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_preview.call("set_camera_size_multiplier", float((_preview.call("get_snapshot") as Dictionary).get("camera_size_multiplier", 1.0)) + 0.1)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_dragging = false
		_cancel_install()
		if _scope != null:
			_scope.hide()
			_detail.show()
	else:
		_queue_refresh()
