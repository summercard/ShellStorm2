class_name WorkbenchPanel
extends Control

## 武器改造面板 — 工作台交互界面
## 展示当前武器装配树、可选枪身/子弹/配件
## 允许玩家重新选择和装配武器

@onready var panel_container: PanelContainer = $PanelContainer
@onready var title_label: Label = $PanelContainer/VBox/TitleLabel
@onready var weapon_tree_label: Label = $PanelContainer/VBox/WeaponTreeLabel
@onready var gunbody_options: VBoxContainer = $PanelContainer/VBox/GunbodyPanel/VBox
@onready var bullet_options: VBoxContainer = $PanelContainer/VBox/BulletPanel/VBox
@onready var status_label: Label = $PanelContainer/VBox/StatusLabel
@onready var close_button: Button = $PanelContainer/VBox/CloseButton

var _player: Node = null
var _workbench_ref: Node = null
var _current_selection: Dictionary = {}

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
	
	_build_weapon_options()

func _process(delta: float) -> void:
	# ESC 关闭
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(KEY_ESCAPE):
		_on_close_pressed()

func set_player(player: Node) -> void:
	_player = player

func set_workbench_ref(ref: Node) -> void:
	_workbench_ref = ref

## 构建可选武器列表
func _build_weapon_options() -> void:
	if _player == null:
		_update_status("玩家未就绪")
		return
	
	# 获取 BlueprintTier
	var gunbody_tier: int = BaseManager.get_blueprint_tier("gunbody")
	var bullet_tier: int = BaseManager.get_blueprint_tier("bullet")
	var attachment_tier: int = BaseManager.get_blueprint_tier("attachment")
	
	# 更新武器树显示
	_update_weapon_tree_display()
	
	# 填充枪身选项
	_populate_gunbody_options(gunbody_tier)
	
	# 填充子弹选项
	_populate_bullet_options(bullet_tier)

func _update_weapon_tree_display() -> void:
	if weapon_tree_label == null:
		return
	
	if _player and _player.has_method("get_weapon_tree"):
		var tree: Node = _player.get_weapon_tree()
		if tree != null and tree.has_method("get_tree_string"):
			weapon_tree_label.text = "当前武器:\n" + tree.get_tree_string()
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

func _update_status(msg: String) -> void:
	if status_label:
		status_label.text = msg

func _on_close_pressed() -> void:
	if _workbench_ref != null and _workbench_ref.has_method("handle_esc"):
		_workbench_ref.handle_esc()
	else:
		queue_free()