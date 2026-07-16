class_name TrainingRange
extends Node2D

const BASE_SCENE := "res://scenes/BaseWorld.tscn"
const ALL_BLUEPRINT_TIER := 99

const TARGET_LAYOUT: Array[Dictionary] = [
	{
		"id": "standard_near",
		"type": TrainingTarget.TargetType.STANDARD,
		"position": Vector2(40, -290),
		"size": 42.0,
		"armor": 0.0,
		"color": Color(0.30, 0.78, 0.88),
	},
	{
		"id": "standard_far",
		"type": TrainingTarget.TargetType.STANDARD,
		"position": Vector2(570, -270),
		"size": 36.0,
		"armor": 0.0,
		"color": Color(0.36, 0.68, 0.84),
	},
	{
		"id": "armored",
		"type": TrainingTarget.TargetType.ARMORED,
		"position": Vector2(450, 40),
		"size": 58.0,
		"armor": 0.42,
		"color": Color(0.94, 0.57, 0.22),
	},
	{
		"id": "runner",
		"type": TrainingTarget.TargetType.RUNNER,
		"position": Vector2(300, 300),
		"size": 35.0,
		"armor": 0.12,
		"span": 210.0,
		"speed": 1.55,
		"axis": Vector2.RIGHT,
		"color": Color(0.66, 0.9, 0.36),
	},
]

@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D
@onready var target_root: Node2D = $Targets
@onready var hud: CanvasLayer = $HUD
@onready var exit_door: Area2D = $ExitDoor
@onready var exit_prompt: Label = $ExitDoor/ExitPrompt

var _weapon_tree: WeaponAssemblyTree
var _guns: Array[Dictionary] = []
var _bullets: Array[Dictionary] = []
var _gun_buttons: Dictionary = {}
var _bullet_buttons: Dictionary = {}
var _targets: Array[TrainingTarget] = []
var _lights: Array[PointLight2D] = []

var _selected_gun_id := ""
var _selected_bullet_id := ""
var _auto_assemble := false
var _exit_player_in_range := false
var _prepared_for_exit := false
var _base_snapshot: Dictionary = {}

var _shots := 0
var _projectiles := 0
var _hits := 0
var _raw_damage := 0.0
var _applied_damage := 0.0
var _critical_hits := 0
var _session_started_ms := 0

var _selection_label: Label
var _weapon_stats_label: Label
var _session_stats_label: Label
var _status_label: Label
var _ammo_label: Label
var _auto_toggle: CheckButton
var _gun_grid: GridContainer
var _bullet_grid: GridContainer


func _ready() -> void:
	Global.clear_pause_reasons()
	if BaseManager != null and BaseManager.data != null:
		_base_snapshot = BaseManager.data._to_dict().duplicate(true)
	_weapon_tree = player.get_weapon_tree()
	_weapon_tree.clear_assembly()
	player.set_combat_enabled(true)
	camera.reparent(player)
	camera.position = Vector2.ZERO
	camera.make_current()
	_build_environment_lights()
	_spawn_targets()
	_build_ui()
	_connect_weapon_signals()
	exit_door.body_entered.connect(_on_exit_body_entered)
	exit_door.body_exited.connect(_on_exit_body_exited)
	exit_prompt.visible = false
	_refresh_weapon_ui()
	_refresh_session_ui()
	queue_redraw()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	for i in range(_lights.size()):
		var light := _lights[i]
		if is_instance_valid(light):
			var slow_pulse := sin(now * (0.7 + i * 0.09) + i * 1.73) * 0.08
			var fault := 0.26 if i == 3 and fmod(now + 0.4, 7.6) < 0.18 else 1.0
			light.energy = (0.52 + slow_pulse) * fault
	if _hits > 0:
		_refresh_session_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _exit_player_in_range:
		get_viewport().set_input_as_handled()
		request_exit()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F:
			assemble_selected()
		KEY_C:
			clear_test_loadout()
		KEY_R:
			reset_session()


func select_gun(item_id: String) -> bool:
	if not _gun_buttons.has(item_id):
		return false
	_selected_gun_id = item_id
	(_gun_buttons[item_id] as Button).button_pressed = true
	_refresh_selection_ui()
	if _auto_assemble and not _selected_bullet_id.is_empty():
		assemble_selected()
	else:
		_set_status("已选枪身；组合开关关闭，按 F 或点击按钮装配。", Color(0.68, 0.84, 0.94))
	return true


func select_bullet(item_id: String) -> bool:
	if not _bullet_buttons.has(item_id):
		return false
	_selected_bullet_id = item_id
	(_bullet_buttons[item_id] as Button).button_pressed = true
	_refresh_selection_ui()
	if _auto_assemble and not _selected_gun_id.is_empty():
		assemble_selected()
	else:
		_set_status("已选弹药；组合开关关闭，按 F 或点击按钮装配。", Color(0.68, 0.84, 0.94))
	return true


func set_auto_assemble(enabled: bool) -> void:
	_auto_assemble = enabled
	if _auto_toggle != null and _auto_toggle.button_pressed != enabled:
		_auto_toggle.set_pressed_no_signal(enabled)
	_set_status(
		"自动组合已开启：选择变更会立即重建临时武器。"
		if enabled
		else "自动组合已关闭：可先比较选项，再手动装配。",
		Color(0.38, 0.92, 0.72) if enabled else Color(0.68, 0.78, 0.86)
	)
	if enabled and not _selected_gun_id.is_empty() and not _selected_bullet_id.is_empty():
		assemble_selected()


func assemble_selected() -> bool:
	if _selected_gun_id.is_empty() or _selected_bullet_id.is_empty():
		_set_status("请先各选择一个枪身与弹药模块。", Color(1.0, 0.62, 0.3))
		return false
	return assemble_combination(_selected_gun_id, _selected_bullet_id)


func assemble_combination(gun_id: String, bullet_id: String) -> bool:
	var gun := BlueprintRegistry.create_assembly_node(gun_id)
	var bullet := BlueprintRegistry.create_assembly_node(bullet_id)
	if gun == null or bullet == null:
		if gun != null:
			gun.free()
		if bullet != null:
			bullet.free()
		_set_status("测试蓝图创建失败。", Color(1.0, 0.36, 0.32))
		return false
	_weapon_tree.clear_assembly()
	if not _weapon_tree.set_root(gun):
		gun.free()
		bullet.free()
		return false
	if not _weapon_tree.mount(gun, AssemblyNode.SlotType.BULLET, bullet):
		bullet.free()
		_weapon_tree.clear_assembly()
		return false
	_selected_gun_id = gun_id
	_selected_bullet_id = bullet_id
	if _gun_buttons.has(gun_id):
		(_gun_buttons[gun_id] as Button).button_pressed = true
	if _bullet_buttons.has(bullet_id):
		(_bullet_buttons[bullet_id] as Button).button_pressed = true
	_refresh_selection_ui()
	_refresh_weapon_ui()
	_set_status("隔离装配已上线。测试物品将在离场时销毁。", Color(0.36, 0.96, 0.7))
	_pulse_control(_weapon_stats_label)
	return true


func clear_test_loadout() -> void:
	if _weapon_tree != null:
		_weapon_tree.clear_assembly()
	_refresh_weapon_ui()
	_set_status("测试装备已清空；玩家恢复空装状态。", Color(0.76, 0.86, 0.92))


func reset_session() -> void:
	_shots = 0
	_projectiles = 0
	_hits = 0
	_raw_damage = 0.0
	_applied_damage = 0.0
	_critical_hits = 0
	_session_started_ms = 0
	for target in _targets:
		if is_instance_valid(target):
			target.reset_metrics()
	_refresh_session_ui()
	_set_status("靶标与会话数据已重置。", Color(0.72, 0.88, 1.0))
	_pulse_control(_session_stats_label)


func prepare_exit() -> void:
	if _prepared_for_exit:
		return
	_prepared_for_exit = true
	clear_test_loadout()
	player.set_combat_enabled(false)


func request_exit() -> void:
	prepare_exit()
	if not is_progression_unchanged():
		push_error("[TrainingRange] Progression changed inside isolated training session")
	var error := get_tree().change_scene_to_file(BASE_SCENE)
	if error != OK:
		push_error("[TrainingRange] Cannot return to base: %s" % error_string(error))


func is_progression_unchanged() -> bool:
	if _base_snapshot.is_empty() or BaseManager == null or BaseManager.data == null:
		return true
	return BaseManager.data._to_dict() == _base_snapshot


func is_empty_loadout() -> bool:
	return _weapon_tree != null and _weapon_tree.get_root() == null


func get_weapon_tree() -> WeaponAssemblyTree:
	return _weapon_tree


func get_gun_selector_count() -> int:
	return _gun_buttons.size()


func get_bullet_selector_count() -> int:
	return _bullet_buttons.size()


func get_target_count() -> int:
	return _targets.size()


func get_targets() -> Array[TrainingTarget]:
	return _targets.duplicate()


func get_session_metrics() -> Dictionary:
	var elapsed := 0.0
	if _session_started_ms > 0:
		elapsed = maxf(0.001, (Time.get_ticks_msec() - _session_started_ms) * 0.001)
	return {
		"shots": _shots,
		"projectiles": _projectiles,
		"hits": _hits,
		"raw_damage": _raw_damage,
		"applied_damage": _applied_damage,
		"critical_hits": _critical_hits,
		"accuracy": float(_hits) / maxf(1.0, float(_projectiles)),
		"dps": _applied_damage / elapsed if _hits > 0 else 0.0,
	}


func _spawn_targets() -> void:
	for config in TARGET_LAYOUT:
		var target := TrainingTarget.new()
		target.name = str(config.get("id", "Target")).to_pascal_case()
		target.position = config.get("position", Vector2.ZERO)
		target.configure(config)
		target_root.add_child(target)
		target.hit_received.connect(_on_target_hit)
		_targets.append(target)


func _connect_weapon_signals() -> void:
	if not _weapon_tree.weapon_fired.is_connected(_on_weapon_fired):
		_weapon_tree.weapon_fired.connect(_on_weapon_fired)
	if not _weapon_tree.stats_changed.is_connected(_on_weapon_stats_changed):
		_weapon_tree.stats_changed.connect(_on_weapon_stats_changed)
	if not _weapon_tree.ammo_changed.is_connected(_on_ammo_changed):
		_weapon_tree.ammo_changed.connect(_on_ammo_changed)


func _on_weapon_fired(_position: Vector2, _direction: Vector2, count: int) -> void:
	if _session_started_ms == 0:
		_session_started_ms = Time.get_ticks_msec()
	_shots += 1
	_projectiles += count
	_refresh_session_ui()


func _on_target_hit(_target_id: String, raw: float, applied: float, crit: bool) -> void:
	if _session_started_ms == 0:
		_session_started_ms = Time.get_ticks_msec()
	_hits += 1
	_raw_damage += raw
	_applied_damage += applied
	if crit:
		_critical_hits += 1
	_refresh_session_ui()
	_pulse_control(_session_stats_label)


func _on_weapon_stats_changed(_stats: Dictionary) -> void:
	_refresh_weapon_ui()


func _on_ammo_changed(current: int, maximum: int) -> void:
	if _ammo_label != null:
		_ammo_label.text = "弹药  %d / %d" % [current, maximum]


func _on_exit_body_entered(body: Node2D) -> void:
	if body != player:
		return
	_exit_player_in_range = true
	exit_prompt.visible = true


func _on_exit_body_exited(body: Node2D) -> void:
	if body != player:
		return
	_exit_player_in_range = false
	exit_prompt.visible = false


func _build_ui() -> void:
	_guns = BlueprintRegistry.get_available_gunbodies(ALL_BLUEPRINT_TIER)
	_bullets = BlueprintRegistry.get_available_bullets(ALL_BLUEPRINT_TIER)

	var header := PanelContainer.new()
	header.position = Vector2(24, 20)
	header.size = Vector2(500, 86)
	header.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.06, 0.075, 0.93), Color(0.24, 0.66, 0.76, 0.8), 8))
	hud.add_child(header)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 18)
	header_margin.add_theme_constant_override("margin_right", 18)
	header_margin.add_theme_constant_override("margin_top", 11)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header.add_child(header_margin)
	var header_box := VBoxContainer.new()
	header_margin.add_child(header_box)
	var title := Label.new()
	title.text = "B-07  隔离测试廊"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.72, 0.94, 1.0))
	header_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "射击测试已授权  ·  局外数据隔离  ·  离场自动消毒"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.48, 0.68, 0.74))
	header_box.add_child(subtitle)

	var sidebar := PanelContainer.new()
	sidebar.name = "AssemblyConsole"
	sidebar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	sidebar.offset_left = -474.0
	sidebar.offset_top = 16.0
	sidebar.offset_right = -16.0
	sidebar.offset_bottom = -16.0
	sidebar.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.045, 0.06, 0.96), Color(0.21, 0.5, 0.59, 0.86), 10))
	hud.add_child(sidebar)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	sidebar.add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)

	var console_title := Label.new()
	console_title.text = "武器组合终端"
	console_title.add_theme_font_size_override("font_size", 22)
	console_title.add_theme_color_override("font_color", Color(0.86, 0.95, 0.98))
	root_box.add_child(console_title)

	_selection_label = Label.new()
	_selection_label.text = "枪身：未选择\n弹药：未选择"
	_selection_label.custom_minimum_size = Vector2(0, 48)
	_selection_label.add_theme_color_override("font_color", Color(0.64, 0.78, 0.84))
	root_box.add_child(_selection_label)

	_add_section_label(root_box, "01  枪身货架  ·  全蓝图")
	var gun_scroll := ScrollContainer.new()
	gun_scroll.custom_minimum_size = Vector2(0, 118)
	root_box.add_child(gun_scroll)
	_gun_grid = GridContainer.new()
	_gun_grid.columns = 2
	_gun_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gun_grid.add_theme_constant_override("h_separation", 6)
	_gun_grid.add_theme_constant_override("v_separation", 6)
	gun_scroll.add_child(_gun_grid)
	_build_selector_buttons(_guns, _gun_grid, true)

	_add_section_label(root_box, "02  弹药架  ·  全模块")
	var bullet_scroll := ScrollContainer.new()
	bullet_scroll.custom_minimum_size = Vector2(0, 138)
	root_box.add_child(bullet_scroll)
	_bullet_grid = GridContainer.new()
	_bullet_grid.columns = 2
	_bullet_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bullet_grid.add_theme_constant_override("h_separation", 6)
	_bullet_grid.add_theme_constant_override("v_separation", 6)
	bullet_scroll.add_child(_bullet_grid)
	_build_selector_buttons(_bullets, _bullet_grid, false)

	_auto_toggle = CheckButton.new()
	_auto_toggle.text = "组合开关  ·  选择后自动装配"
	_auto_toggle.add_theme_color_override("font_color", Color(0.72, 0.85, 0.9))
	_auto_toggle.toggled.connect(set_auto_assemble)
	root_box.add_child(_auto_toggle)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root_box.add_child(actions)
	var assemble_button := _make_action_button("装配测试组合  [F]", Color(0.24, 0.72, 0.62))
	assemble_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assemble_button.pressed.connect(assemble_selected)
	actions.add_child(assemble_button)
	var clear_button := _make_action_button("清空  [C]", Color(0.55, 0.42, 0.28))
	clear_button.pressed.connect(clear_test_loadout)
	actions.add_child(clear_button)

	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.075, 0.09, 0.86), Color(0.18, 0.34, 0.39, 0.9), 6))
	root_box.add_child(stats_panel)
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 3)
	stats_panel.add_child(stats_box)
	_ammo_label = Label.new()
	_ammo_label.text = "弹药  0 / 0"
	_ammo_label.add_theme_font_size_override("font_size", 20)
	_ammo_label.add_theme_color_override("font_color", Color(0.96, 0.78, 0.3))
	stats_box.add_child(_ammo_label)
	_weapon_stats_label = Label.new()
	_weapon_stats_label.text = "空装：无可用射击参数"
	_weapon_stats_label.add_theme_color_override("font_color", Color(0.7, 0.82, 0.86))
	stats_box.add_child(_weapon_stats_label)
	_session_stats_label = Label.new()
	_session_stats_label.text = "会话  射击 0  命中 0  命中率 0%  DPS 0"
	_session_stats_label.add_theme_color_override("font_color", Color(0.52, 0.9, 0.72))
	stats_box.add_child(_session_stats_label)

	var footer_actions := HBoxContainer.new()
	footer_actions.add_theme_constant_override("separation", 8)
	root_box.add_child(footer_actions)
	var reset_button := _make_action_button("重置数据  [R]", Color(0.3, 0.48, 0.6))
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.pressed.connect(reset_session)
	footer_actions.add_child(reset_button)
	var exit_button := _make_action_button("消毒离场", Color(0.66, 0.28, 0.26))
	exit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_button.pressed.connect(request_exit)
	footer_actions.add_child(exit_button)

	_status_label = Label.new()
	_status_label.text = "隔离系统就绪。进场装备已清空。"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 40)
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.52, 0.82, 0.9))
	root_box.add_child(_status_label)


func _build_selector_buttons(entries: Array[Dictionary], grid: GridContainer, is_gun: bool) -> void:
	var group := ButtonGroup.new()
	for entry in entries:
		var item_id := str(entry.get("item_id", ""))
		var button := Button.new()
		button.text = "T%d  %s" % [int(entry.get("tier", 0)), str(entry.get("display_name", item_id))]
		button.tooltip_text = "%s\n%s" % [item_id, ", ".join(entry.get("tags", []))]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(194, 32)
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.06, 0.09, 0.105, 0.95), Color(0.16, 0.27, 0.31, 0.9), 4))
		button.add_theme_stylebox_override("hover", _panel_style(Color(0.09, 0.15, 0.17, 1.0), Color(0.3, 0.72, 0.78, 1.0), 4))
		button.add_theme_stylebox_override("pressed", _panel_style(Color(0.12, 0.27, 0.28, 1.0), Color(0.42, 0.94, 0.78, 1.0), 4))
		button.add_theme_color_override("font_color", Color(0.68, 0.79, 0.83))
		button.add_theme_color_override("font_pressed_color", Color(0.9, 1.0, 0.95))
		if is_gun:
			button.pressed.connect(select_gun.bind(item_id))
			_gun_buttons[item_id] = button
		else:
			button.pressed.connect(select_bullet.bind(item_id))
			_bullet_buttons[item_id] = button
		grid.add_child(button)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.38, 0.72, 0.78))
	parent.add_child(label)


func _make_action_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_stylebox_override("normal", _panel_style(color.darkened(0.55), color.darkened(0.08), 5))
	button.add_theme_stylebox_override("hover", _panel_style(color.darkened(0.35), color.lightened(0.18), 5))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.18), Color.WHITE, 5))
	button.add_theme_color_override("font_color", Color(0.9, 0.96, 0.97))
	return button


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _refresh_selection_ui() -> void:
	if _selection_label == null:
		return
	_selection_label.text = "枪身：%s\n弹药：%s" % [
		_display_name_for(_guns, _selected_gun_id),
		_display_name_for(_bullets, _selected_bullet_id),
	]


func _refresh_weapon_ui() -> void:
	if _weapon_stats_label == null or _weapon_tree == null:
		return
	var root := _weapon_tree.get_root()
	if root == null:
		_weapon_stats_label.text = "空装：无可用射击参数"
		_on_ammo_changed(0, 0)
		return
	var stats := _weapon_tree.get_computed_stats()
	_weapon_stats_label.text = "枪身威力 %d  弹伤 %d  射速 %.1f/s  投射物 %d  扩散 %.2f" % [
		int(stats.get("damage", 0)),
		_weapon_tree.bullet_damage,
		_weapon_tree.fire_rate,
		_weapon_tree.projectile_count,
		_weapon_tree.spread,
	]
	_on_ammo_changed(_weapon_tree.current_ammo, _weapon_tree.magazine_size)


func _refresh_session_ui() -> void:
	if _session_stats_label == null:
		return
	var metrics := get_session_metrics()
	_session_stats_label.text = "会话  射击 %d  命中 %d  命中率 %.0f%%  结算伤害 %.0f  DPS %.1f" % [
		int(metrics["shots"]),
		int(metrics["hits"]),
		float(metrics["accuracy"]) * 100.0,
		float(metrics["applied_damage"]),
		float(metrics["dps"]),
	]


func _display_name_for(entries: Array[Dictionary], item_id: String) -> String:
	if item_id.is_empty():
		return "未选择"
	for entry in entries:
		if str(entry.get("item_id", "")) == item_id:
			return str(entry.get("display_name", item_id))
	return item_id


func _set_status(message: String, color: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", color)
	_pulse_control(_status_label)


func _pulse_control(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.modulate = Color(1.22, 1.22, 1.22, 1.0)
	var tween := control.create_tween()
	tween.tween_property(control, "modulate", Color.WHITE, 0.22).set_trans(Tween.TRANS_QUAD)


func _build_environment_lights() -> void:
	var configs := [
		{ "position": Vector2(-650, -330), "color": Color(0.28, 0.72, 0.82), "scale": 2.8 },
		{ "position": Vector2(-80, -300), "color": Color(0.22, 0.62, 0.72), "scale": 2.4 },
		{ "position": Vector2(400, -260), "color": Color(0.24, 0.56, 0.65), "scale": 2.2 },
		{ "position": Vector2(700, 20), "color": Color(0.82, 0.22, 0.16), "scale": 2.0 },
		{ "position": Vector2(260, 330), "color": Color(0.34, 0.72, 0.4), "scale": 1.8 },
	]
	var texture := _make_radial_light_texture()
	for i in range(configs.size()):
		var config: Dictionary = configs[i]
		var light := PointLight2D.new()
		light.name = "SparseLight%02d" % (i + 1)
		light.position = config["position"]
		light.color = config["color"]
		light.texture = texture
		light.texture_scale = float(config["scale"])
		light.energy = 0.52
		light.range_z_min = -10
		light.range_z_max = 10
		add_child(light)
		_lights.append(light)


func _make_radial_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.46, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.24),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _draw() -> void:
	# 破败工业射击廊：底层地面、分道线、弹痕与损坏区均为可替换的程序化表现。
	draw_rect(Rect2(-900, -540, 1800, 1080), Color(0.065, 0.085, 0.09), true)
	draw_rect(Rect2(-855, -495, 1710, 990), Color(0.09, 0.115, 0.12), true)
	for lane_y in [-340.0, -110.0, 120.0, 350.0]:
		draw_line(Vector2(-760, lane_y), Vector2(790, lane_y), Color(0.24, 0.34, 0.34, 0.46), 3.0)
		for x in range(-720, 780, 120):
			draw_line(Vector2(x, lane_y - 5), Vector2(x + 48, lane_y - 5), Color(0.52, 0.48, 0.22, 0.24), 5.0)
	for x in range(-760, 760, 170):
		draw_line(Vector2(x, -470), Vector2(x + 35, -440), Color(0.18, 0.23, 0.23, 0.65), 2.0)
		draw_line(Vector2(x + 35, -440), Vector2(x + 18, -405), Color(0.18, 0.23, 0.23, 0.5), 2.0)
	for i in range(34):
		var px := -680.0 + float((i * 137) % 1410)
		var py := -420.0 + float((i * 89) % 820)
		draw_circle(Vector2(px, py), 2.0 + float(i % 4), Color(0.03, 0.035, 0.035, 0.72))
	# 远端射击损伤区和左侧消毒门。
	draw_rect(Rect2(735, -430, 78, 860), Color(0.055, 0.055, 0.05), true)
	for y in range(-400, 420, 80):
		draw_line(Vector2(748, y), Vector2(800, y + 48), Color(0.5, 0.23, 0.12, 0.35), 5.0)
	draw_rect(Rect2(-875, -125, 65, 250), Color(0.025, 0.05, 0.06), true)
	draw_rect(Rect2(-865, -112, 12, 224), Color(0.25, 0.78, 0.84, 0.72), true)
	draw_string(ThemeDB.fallback_font, Vector2(-790, -148), "DECON / EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 0.7, 0.74))
	draw_string(ThemeDB.fallback_font, Vector2(-540, -438), "LIVE FIRE  →", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(0.35, 0.68, 0.72, 0.72))
	draw_string(ThemeDB.fallback_font, Vector2(-540, -408), "WASD 移动  ·  鼠标瞄准 / 射击", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.28, 0.5, 0.54, 0.72))
