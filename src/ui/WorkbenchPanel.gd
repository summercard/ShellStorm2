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
	
	_build_transform_button()
	_build_weapon_options()

func _build_transform_button() -> void:
	_transform_button = Button.new()
	_transform_button.text = "🔮 命运改造 [T]"
	_transform_button.custom_minimum_size = Vector2(260, 36)
	_transform_button.add_theme_font_size_override("font_size", 14)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	normal_style.set_border_width_all(1)
	normal_style.set_border_color(Color(0.35, 0.30, 0.55, 0.9))
	normal_style.set_corner_radius_all(5)
	_transform_button.add_theme_stylebox_override("normal", normal_style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.18, 0.15, 0.30, 0.95)
	hover_style.set_border_width_all(1)
	hover_style.set_border_color(Color(0.70, 0.55, 0.90, 0.9))
	hover_style.set_corner_radius_all(5)
	_transform_button.add_theme_stylebox_override("hover", hover_style)
	_transform_button.pressed.connect(_on_transform_toggle)
	# 添加到 gunbody panel 标题下面
	if gunbody_options != null:
		gunbody_options.add_child(_transform_button)

func _process(delta: float) -> void:
	# ESC 关闭
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(KEY_ESCAPE):
		_on_close_pressed()
	# T 键切换命运改造模式
	if Input.is_action_just_pressed("ui_text_completion") and _transform_button != null:
		_on_transform_toggle()

func set_player(player: Node) -> void:
	_player = player

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
			weapon_tree_label.text = "当前武器:\n射速:%.1f 弹丸:%d 扩散:%.2f\n弹药:%s" % [
				info.get("fire_rate", 0),
				info.get("projectile_count", 0),
				info.get("spread", 0),
				info.get("ammo", "?"),
			]
		else:
			weapon_tree_label.text = "武器树未就绪"
	else:
		weapon_tree_label.text = "玩家引用无效"

func _populate_gunbody_options(tier: int) -> void:
	if gunbody_options == null:
		return
	
	# 清空旧内容
	for child in gunbody_options.get_children():
		child.queue_free()
	
	var available := BlueprintRegistry.get_available_gunbodies(tier)
	
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
		btn.pressed.connect(_on_gunbody_selected.bind(entry["item_id"]))
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
		btn.pressed.connect(_on_bullet_selected.bind(entry["item_id"]))
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
	for child in gunbody_options.get_children():
		child.queue_free()
	for child in bullet_options.get_children():
		child.queue_free()
	
	# 更新标题
	if _transform_button:
		_transform_button.text = "⚙ 基础改造 [T]"
	
	var header := Label.new()
	header.text = "— 命运卡片 —"
	header.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0, 1.0))
	gunbody_options.add_child(header)
	
	# 随机抽 3 张
	var all_cards: Array[FateCard] = FateCardPresets.all_presets()
	all_cards.shuffle()
	var choices: Array[FateCard] = all_cards.slice(0, 3)
	
	if choices.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "无可用命运卡片"
		gunbody_options.add_child(empty_lbl)
		return
	
	for card in choices:
		var btn := Button.new()
		var rarity_color: Color = FateCard.rarity_color(card.card_rarity)
		var color_hex := "#%02X%02X%02X" % [int(rarity_color.r * 255), int(rarity_color.g * 255), int(rarity_color.b * 255)]
		btn.text = "[%s] %s\n%s" % [
			FateCard.rarity_name(card.card_rarity),
			card.card_name,
			FateCard.type_name(card.card_type),
		]
		btn.custom_minimum_size = Vector2(240, 80)
		btn.tooltip_text = card.description
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = Color(0.10, 0.12, 0.18, 0.95)
		normal_style.set_border_width_all(2)
		normal_style.set_border_color(rarity_color)
		normal_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", normal_style)
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.15, 0.18, 0.28, 0.95)
		hover_style.set_border_width_all(2)
		hover_style.set_border_color(Color(1.0, 1.0, 1.0, 0.8))
		hover_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_color_override("font_color", rarity_color)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_fate_card_selected.bind(card))
		gunbody_options.add_child(btn)
	
	# 右侧显示说明
	var desc := Label.new()
	desc.text = "选择一张卡片\neffects will be applied\nto your weapon assembly"
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.9))
	desc.add_theme_font_size_override("font_size", 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(200, 100)
	bullet_options.add_child(desc)

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
				root.mount(AssemblyNode.SlotType.BULLET, new_bullet)
	
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
