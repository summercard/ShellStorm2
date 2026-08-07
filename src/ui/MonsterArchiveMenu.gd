class_name MonsterArchiveMenu
extends CanvasLayer

## 怪物档案室 — 基地建筑界面
## 展示玩家遭遇过的所有精英怪记录（名字/等级/状态/词缀/持有装备）
## 精英怪档案由 EliteArchiveModule 管理，跨局持久化

@onready var content: VBoxContainer
@onready var status_label: Label
@onready var close_button: Button
@onready var scroll_container: ScrollContainer

## 档案引用（从 RoomGameMode 场景树中获取）
var _elite_archive = null

func _ready() -> void:
	content = get_node_or_null("Panel/VBox/Content")
	status_label = get_node_or_null("Panel/VBox/StatusLabel")
	close_button = get_node_or_null("Panel/VBox/CloseButton")
	scroll_container = get_node_or_null("Panel/VBox/ScrollContainer")
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
		# 关闭按钮统一样式
		var close_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_NORMAL)
		UIStyleFactory.apply_button_style(close_button, close_styles)
	_find_elite_archive()
	_build_archive_view()
	UIStyleFactory.apply_tactical_tree(self)

func _find_elite_archive() -> void:
	# 从场景树中查找 EliteArchiveModule（挂载在 RoomGameMode 下的子节点）
	_elite_archive = get_tree().get_first_node_in_group("elite_archive")
	if _elite_archive == null:
		# fallback: 通过 root 场景查找
		var root = get_tree().get_root()
		var room_game = root.find_child("RoomGameMode", false, false)
		if room_game and room_game.has_node("EliteArchive"):
			_elite_archive = room_game.get_node("EliteArchive")
	if _elite_archive == null:
		print("[MonsterArchiveMenu] EliteArchiveModule not found — 使用空存档")

func _build_archive_view() -> void:
	if content == null:
		return
	# 清理旧内容
	for child in content.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "怪物档案室"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	if _elite_archive == null or not _elite_archive.has_method("get_all_elites"):
		var no_data_lbl := Label.new()
		no_data_lbl.text = "暂无精英怪记录"
		no_data_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(no_data_lbl)
		_add_close_hint()
		return

	var all_elites: Array = _elite_archive.get_all_elites()
	if all_elites.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "暂无精英怪记录\n进入游戏后遭遇的精英怪会显示在这里"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty_lbl)
		_add_close_hint()
		return

	# 统计信息
	var total_count: int = all_elites.size()
	var killed_count: int = 0
	var active_count: int = 0
	for e in all_elites:
		var state: String = e.state if "state" in e else "Unknown"
		if state == "Killed":
			killed_count += 1
		else:
			active_count += 1

	var stats_lbl := Label.new()
	stats_lbl.text = "总记录: %d | 存活: %d | 已击杀: %d" % [total_count, active_count, killed_count]
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(stats_lbl)

	content.add_child(_make_hsep())

	# 按状态分组显示
	var states := ["RevengeHunter", "RegionalBoss", "QuasiBoss", "Escaped", "Equipped", "Growing", "Newborn", "Killed"]
	for st in states:
		var in_state: Array = []
		for e in all_elites:
			var state: String = e.state if "state" in e else "Unknown"
			if state == st:
				in_state.append(e)
		if in_state.is_empty():
			continue
		var state_hdr := Label.new()
		state_hdr.text = "—— %s ——" % _translate_state(st)
		state_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(state_hdr)
		for elite in in_state:
			content.add_child(_make_elite_row(elite))
		content.add_child(_make_hsep())

	_add_close_hint()

func _translate_state(state: String) -> String:
	match state:
		"Newborn": return "新生精英"
		"Escaped": return "逃脱中"
		"Equipped": return "装备中"
		"Growing": return "成长中"
		"RevengeHunter": return "复仇猎手"
		"RegionalBoss": return "区域霸主"
		"QuasiBoss": return "准Boss"
		"Killed": return "已击杀"
		_: return state

func _make_elite_row(elite) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 60)
	panel.add_theme_stylebox_override("panel", _get_elite_panel_style(elite))

	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	# 左侧：名字 + 等级
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = elite.name if "name" in elite else "未知精英"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(name_lbl)

	var level_lbl := Label.new()
	var lvl: int = elite.level if "level" in elite else 1
	var base_id: String = elite.base_enemy_id if "base_enemy_id" in elite else "?"
	level_lbl.text = "Lv.%d | %s" % [lvl, base_id]
	level_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(level_lbl)

	hbox.add_child(info_vbox)

	# 中间：状态标签
	var state_lbl := Label.new()
	var state: String = elite.state if "state" in elite else "?"
	state_lbl.text = _translate_state(state)
	state_lbl.custom_minimum_size = Vector2(80, 0)
	state_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(state_lbl)

	# 右侧：词缀 + 持有装备
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(200, 0)

	# 词缀显示
	var mod_list: Array = elite.modifiers if "modifiers" in elite else []
	if not mod_list.is_empty():
		var mod_lbl := Label.new()
		var mod_texts: Array = []
		for m in mod_list:
			var s: String = m as String
			mod_texts.append(_shorten_modifier(s))
		mod_lbl.text = "词缀: " + ", ".join(mod_texts.slice(0, 3))
		mod_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_vbox.add_child(mod_lbl)

	# 持有装备
	var stolen: Array = elite.stolen_modules if "stolen_modules" in elite else []
	if not stolen.is_empty():
		var stolen_lbl := Label.new()
		var stolen_names: Array = []
		for sm in stolen:
			var mid: String = sm.get("module_id", "?") as String
			stolen_names.append(_shorten_module_id(mid))
		stolen_lbl.text = "持有: " + ", ".join(stolen_names.slice(0, 2))
		stolen_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_vbox.add_child(stolen_lbl)

	# 击杀玩家次数
	var history: Dictionary = elite.history if "history" in elite else {}
	var kills: int = history.get("killed_player_count", 0) as int
	if kills > 0:
		var kills_lbl := Label.new()
		kills_lbl.text = "击杀玩家: %d次" % kills
		kills_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_vbox.add_child(kills_lbl)

	hbox.add_child(right_vbox)

	# 悬赏等级
	var bounty: int = elite.bounty_reward_level if "bounty_reward_level" in elite else 0
	if bounty > 0:
		var bounty_lbl := Label.new()
		bounty_lbl.text = "悬赏%d" % bounty
		bounty_lbl.custom_minimum_size = Vector2(60, 0)
		bounty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(bounty_lbl)

	return panel

func _shorten_modifier(mod: String) -> String:
	# 缩短词缀名称用于UI显示
	var m: String = mod as String
	if m.begins_with("Elite."):
		m = m.substr(6)
	# 截断过长名称
	if m.length() > 8:
		return m.substr(0, 6) + ".."
	return m

func _shorten_module_id(module_id: String) -> String:
	# 缩短模块ID用于UI显示
	var m: String = module_id as String
	if m.length() > 12:
		return m.substr(0, 10) + ".."
	return m

func _get_elite_panel_style(elite) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)

	var state: String = elite.state if "state" in elite else "?"
	match state:
		"Killed":
			style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
			style.set_border_color(Color(0.3, 0.3, 0.35, 0.5))
		"RegionalBoss", "QuasiBoss":
			style.bg_color = Color(0.25, 0.08, 0.05, 0.9)
			style.set_border_color(Color(0.8, 0.2, 0.1, 0.7))
		"RevengeHunter":
			style.bg_color = Color(0.20, 0.10, 0.20, 0.9)
			style.set_border_color(Color(0.7, 0.3, 0.8, 0.6))
		"Escaped", "Equipped", "Growing":
			style.bg_color = Color(0.12, 0.18, 0.25, 0.9)
			style.set_border_color(Color(0.4, 0.55, 0.8, 0.5))
		_:  # Newborn
			style.bg_color = Color(0.15, 0.18, 0.20, 0.9)
			style.set_border_color(Color(0.4, 0.4, 0.5, 0.5))

	return style

func _make_hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 4)
	return sep

func _add_close_hint() -> void:
	content.add_child(_make_hsep())
	var hint := Label.new()
	hint.text = "按 Esc 或点击关闭"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

func _on_close_pressed() -> void:
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
