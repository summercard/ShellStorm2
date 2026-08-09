class_name WorkbenchPanel
extends Control

## 武器改造面板 — 工作台交互界面
## 展示当前武器装配树、可选枪身/子弹/配件
## 允许玩家重新选择和装配武器

@onready var panel_container: PanelContainer
@onready var title_label: Label
@onready var weapon_tree_label: Label
@onready var gunbody_options: VBoxContainer
@onready var bullet_options: VBoxContainer
@onready var status_label: Label
@onready var close_button: Button

var _player: Node = null
var _workbench_ref: Node = null
var _current_selection: Dictionary = {}
var _transform_button: Button = null
var _transform_mode: bool = false


func _ready() -> void:
	panel_container = get_node_or_null("PanelContainer")
	close_button = get_node_or_null("PanelContainer/VBox/CloseButton")
	weapon_tree_label = get_node_or_null("PanelContainer/VBox/WeaponTreeLabel")
	status_label = get_node_or_null("PanelContainer/VBox/StatusLabel")
	gunbody_options = get_node_or_null("PanelContainer/VBox/HBox/GunbodyPanel/VBox")
	bullet_options = get_node_or_null("PanelContainer/VBox/HBox/BulletPanel/VBox")

	panel_container.custom_minimum_size = Vector2(620, 520)
	position = Vector2(100, 80)

	if close_button:
		close_button.pressed.connect(_on_close_pressed)
		# 关闭按钮统一样式
		var close_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_NORMAL)
		UIStyleFactory.apply_button_style(close_button, close_styles)

	_build_transform_button()
	_build_weapon_options()
	UIStyleFactory.apply_tactical_tree(self)


func _build_transform_button() -> void:
	_transform_button = Button.new()
	_transform_button.text = "🔮 命运改造 [T]"
	_transform_button.custom_minimum_size = Vector2(260, 36)
	_transform_button.add_theme_font_size_override("font_size", 14)
	# 命运按钮使用紫色 accent
	var transform_styles := UIStyleFactory.make_button_style(
		UIStyleFactory.make_panel_with_border(2, UIPalette.ITEM_FATE_CARD, 5, 1).bg_color,
		UIPalette.ITEM_FATE_CARD,
	)
	UIStyleFactory.apply_button_style(_transform_button, transform_styles)
	_transform_button.pressed.connect(_on_transform_toggle)
	# 添加到 gunbody panel 标题下面
	if gunbody_options != null:
		gunbody_options.add_child(_transform_button)


func _input(event: InputEvent) -> void:
	# ESC 关闭
	if event.is_action_pressed("ui_cancel") or _is_key_just_pressed(event, KEY_ESCAPE):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
		return
	# T 键切换命运改造模式
	if _is_key_just_pressed(event, KEY_T) and _transform_button != null:
		_on_transform_toggle()
		get_viewport().set_input_as_handled()


func _is_key_just_pressed(event: InputEvent, key: Key) -> bool:
	var key_event := event as InputEventKey
	if key_event == null:
		return false
	return (
		key_event.pressed
		and not key_event.echo
		and (key_event.keycode == key or key_event.physical_keycode == key)
	)


func set_player(player: Node) -> void:
	_player = player
	if is_node_ready():
		_build_weapon_options()


func set_workbench_ref(ref: Node) -> void:
	_workbench_ref = ref


## 切换命运改造模式（基础/命运卡片）
func _on_transform_toggle() -> void:
	_transform_mode = not _transform_mode
	_rebuild_options()


## 重建选项（根据当前模式显示枪身/子弹或命运卡片）
func _rebuild_options() -> void:
	if _transform_mode:
		_show_fate_card_options()
	else:
		_show_blueprint_options()


func _show_blueprint_options() -> void:
	var gunbody_tier: int = BaseManager.get_blueprint_tier("gunbody")
	var bullet_tier: int = BaseManager.get_blueprint_tier("bullet")
	_populate_gunbody_options(gunbody_tier)
	_populate_bullet_options(bullet_tier)
	if _transform_button:
		_transform_button.text = "🔮 命运改造 [T]"
	_update_weapon_tree_display()


## 构建可选武器列表
func _build_weapon_options() -> void:
	if _player == null:
		_update_status("玩家未就绪")
		return

	_update_weapon_tree_display()
	_rebuild_options()


func _update_weapon_tree_display() -> void:
	if weapon_tree_label == null:
		return

	if _player and _player.has_method("get_weapon_tree"):
		var tree: Node = _player.get_weapon_tree()
		if tree != null and tree.has_method("get_assembly_tree_string"):
			weapon_tree_label.text = "当前武器:\n" + tree.get_assembly_tree_string()
		elif tree != null and tree.has_method("get_weapon_info"):
			var info: Dictionary = tree.get_weapon_info()
			weapon_tree_label.text = (
				"当前武器:\n射速:%.1f 弹丸:%d 扩散:%.2f\n弹药:%s"
				% [
					info.get("fire_rate", 0),
					info.get("projectile_count", 0),
					info.get("spread", 0),
					info.get("ammo", "?"),
				]
			)
		else:
			weapon_tree_label.text = "武器树未就绪"
	else:
		weapon_tree_label.text = "玩家引用无效"


func _populate_gunbody_options(tier: int) -> void:
	if gunbody_options == null:
		return

	# 清空旧内容
	_clear_gunbody_options()

	var available := BlueprintRegistry.get_available_gunbodies(tier)
	_ensure_transform_button_parent()

	var header := Label.new()
	header.text = "— 枪身选择 —"
	header.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	gunbody_options.add_child(header)

	if available.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "无可用枪身"
		gunbody_options.add_child(empty_lbl)
		return

	for entry in available:
		var btn := Button.new()
		btn.text = "[Tier %d] %s" % [entry["tier"], entry["display_name"]]
		btn.custom_minimum_size = Vector2(220, 32)
		btn.pressed.connect(_on_gunbody_selected.bind(entry["item_id"]))
		# 枪身选项用 BORDER_FOCUS 蓝
		var gunbody_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_FOCUS)
		UIStyleFactory.apply_button_style(btn, gunbody_styles)
		gunbody_options.add_child(btn)


func _populate_bullet_options(tier: int) -> void:
	if bullet_options == null:
		return

	# 清空旧内容
	for child in bullet_options.get_children():
		child.queue_free()

	var available := BlueprintRegistry.get_available_bullets(tier)

	var header := Label.new()
	header.text = "— 子弹选择 —"
	header.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	bullet_options.add_child(header)

	if available.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "无可用子弹"
		bullet_options.add_child(empty_lbl)
		return

	for entry in available:
		var btn := Button.new()
		btn.text = "[Tier %d] %s" % [entry["tier"], entry["display_name"]]
		btn.custom_minimum_size = Vector2(220, 32)
		btn.pressed.connect(_on_bullet_selected.bind(entry["item_id"]))
		# 子弹选项用 ITEM_BULLET 蓝色
		var bullet_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.ITEM_BULLET)
		UIStyleFactory.apply_button_style(btn, bullet_styles)
		bullet_options.add_child(btn)


func _on_gunbody_selected(item_id: String) -> void:
	_current_selection["gunbody"] = item_id
	_apply_selection()
	_update_status("已选择枪身: %s" % item_id)


func _on_bullet_selected(item_id: String) -> void:
	_current_selection["bullet"] = item_id
	_apply_selection()
	_update_status("已选择子弹: %s" % item_id)


## 在命运改造模式下显示随机抽取的命运卡片
func _show_fate_card_options() -> void:
	if gunbody_options == null or bullet_options == null:
		return

	# 清空两侧
	_clear_gunbody_options()
	for child in bullet_options.get_children():
		child.queue_free()

	# 更新标题
	if _transform_button:
		_transform_button.text = "⚙ 基础改造 [T]"
	_ensure_transform_button_parent()

	var header := Label.new()
	header.text = "— 命运卡片 —"
	header.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0, 1.0))
	gunbody_options.add_child(header)

	# 共享塔罗抽牌：无重复，正/逆位各50%。
	var choices := FateCardPresets.draw_offer(3)

	if choices.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "无可用命运卡片"
		gunbody_options.add_child(empty_lbl)
		return

	for choice_index in range(choices.size()):
		var card := choices[choice_index]
		var btn := Button.new()
		var rarity_color: Color = FateCard.rarity_color(card.card_rarity)
		var color_hex := (
			"#%02X%02X%02X"
			% [int(rarity_color.r * 255), int(rarity_color.g * 255), int(rarity_color.b * 255)]
		)
		btn.text = (
			"%s · [%s]\n%s\n%s %s · %s"
			% [
				FateCard.scope_display_name(card.scope),
				FateCard.rarity_name(card.card_rarity),
				card.card_name,
				card.orientation_symbol(),
				card.orientation_name(),
				FateCard.type_name(card.card_type),
			]
		)
		btn.custom_minimum_size = Vector2(240, 80)
		btn.tooltip_text = "%s\n%s\n%s" % [FateCard.scope_display_name(card.scope), FateCard.scope_target_text(card.scope), card.description]
		# 稀有边框：normal = 稀有色，hover = 白色高亮
		var card_normal := UIStyleFactory.make_panel_with_border(2, rarity_color, 6, 2)
		card_normal.bg_color = UIPalette.BG_DARK
		var card_hover := UIStyleFactory.make_panel_with_border(2, Color(1.0, 1.0, 1.0, 0.8), 6, 2)
		card_hover.bg_color = UIPalette.BG_MID
		btn.add_theme_stylebox_override("normal", card_normal)
		btn.add_theme_stylebox_override("hover", card_hover)
		btn.add_theme_color_override("font_color", rarity_color)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_fate_card_selected.bind(card))
		gunbody_options.add_child(btn)
		_play_workbench_tarot_flip(btn, card, choice_index)

	# 右侧显示说明
	var desc := Label.new()
	desc.text = "选择一张卡片\n效果会立即应用到当前武器装配"
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.9))
	desc.add_theme_font_size_override("font_size", 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(200, 100)
	bullet_options.add_child(desc)


func _play_workbench_tarot_flip(button: Button, card: FateCard, choice_index: int) -> void:
	var face_text := button.text
	button.disabled = true
	button.text = "✦ 命运塔罗"
	button.set_meta("tarot_face_ready", false)
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		button.modulate.a = 0.0
		button.text = face_text
		button.rotation = PI if card.is_reversed() else 0.0
		tween.tween_property(button, "modulate:a", 1.0, 0.15)
	else:
		tween.tween_interval(0.10 + float(choice_index) * 0.08)
		tween.tween_property(button, "scale:x", 0.04, 0.14)
		tween.tween_callback(func() -> void:
			button.text = face_text
			button.rotation = PI if card.is_reversed() else 0.0
		)
		tween.tween_property(button, "scale:x", 1.0, 0.18)
	tween.tween_callback(func() -> void:
		button.disabled = false
		button.set_meta("tarot_face_ready", true)
		button.set_meta("tarot_face_rotation", button.rotation)
	)


func _clear_gunbody_options() -> void:
	for child in gunbody_options.get_children():
		if child == _transform_button:
			continue
		child.queue_free()


func _ensure_transform_button_parent() -> void:
	if _transform_button == null or gunbody_options == null:
		return
	if _transform_button.get_parent() != gunbody_options:
		if _transform_button.get_parent() != null:
			_transform_button.get_parent().remove_child(_transform_button)
		gunbody_options.add_child(_transform_button)
	gunbody_options.move_child(_transform_button, 0)


func _apply_selection() -> void:
	if _player == null or not _player.has_method("get_weapon_tree"):
		return

	var tree: Node = _player.get_weapon_tree()
	if tree == null:
		return

	# 如果选择了枪身，替换根节点
	if _current_selection.has("gunbody"):
		var gun_id: String = _current_selection["gunbody"]
		var new_gun: Node = BlueprintRegistry.create_assembly_node(gun_id)
		if new_gun != null:
			tree.set_root(new_gun)

	# 如果选择了子弹，挂到枪身上
	if _current_selection.has("bullet"):
		var bullet_id: String = _current_selection["bullet"]
		var new_bullet: Node = BlueprintRegistry.create_assembly_node(bullet_id)
		if new_bullet != null:
			var root: Node = tree.get_root()
			if root != null:
				var old_bullet: Node = root.slots.get(AssemblyNode.SlotType.BULLET)
				if old_bullet != null:
					tree.unmount(old_bullet)
					old_bullet.free()
				# 必须走 WeaponAssemblyTree.mount，才能触发数值、3D 模型和 HUD 同步。
				if not tree.mount(root, AssemblyNode.SlotType.BULLET, new_bullet):
					new_bullet.free()

	_current_selection.clear()
	_update_weapon_tree_display()


## 命运卡片被选中 → 通过 FateCardGameBridge 应用到武器树
func _on_fate_card_selected(card: FateCard) -> void:
	var result: Dictionary = FateCardGameBridge.apply_card(card)
	if result.get("success", false):
		_update_status("✓ %s 已应用！" % card.card_name)
		_update_weapon_tree_display()
	else:
		_update_status("✗ %s 失败: %s" % [card.card_name, result.get("message", "未知错误")])


func _update_status(msg: String) -> void:
	if status_label:
		status_label.text = msg


func _on_close_pressed() -> void:
	if _workbench_ref != null and _workbench_ref.has_method("handle_esc"):
		_workbench_ref.handle_esc()
	else:
		queue_free()
