class_name WorkshopMenu
extends CanvasLayer

## 枪械工坊 — 基地建筑界面
## 展示蓝图解锁进度，玩家可消耗资源解锁新枪身/子弹/配件类别
## 解锁后将使对应的装备池在局内掉落和初始选择时可用

var content: VBoxContainer = null
var status_label: Label = null
var close_button: Button = null

# 手电筒模块切换面板控件
var _flashlight_module_panel: PanelContainer = null
var _flashlight_module_buttons: Dictionary = {}

const MODULE_PROFILES_DISPLAY := [
	{"id": "basic",     "name": "基础模块",   "drain": "1.00×", "reveal": "1.00×"},
	{"id": "advanced",  "name": "加强模块",   "drain": "0.7143×", "reveal": "1.20×"},
	{"id": "efficient", "name": "节能模块",   "drain": "0.50×", "reveal": "0.85×"},
]

func _ready() -> void:
	content = get_node_or_null("Panel/VBox/Content")
	status_label = get_node_or_null("Panel/VBox/StatusLabel")
	close_button = get_node_or_null("Panel/VBox/CloseButton")
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
		# 关闭按钮统一样式
		var close_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_NORMAL)
		UIStyleFactory.apply_button_style(close_button, close_styles)
	_build_blueprint_list()
	_build_flashlight_module_panel()
	_refresh_flashlight_module_panel()
	UIStyleFactory.apply_tactical_tree(self)

## 蓝图解锁阶段定义
## 每个类别有多个Tier，每个Tier解锁后增加该类别在局内的可用变体数量
const BLUEPRINT_TIERS := {
	"gunbody": {
		"label": "枪身蓝图",
		"desc": "解锁新枪身类型",
		"max_tier": 3,
		"unlock_costs": [0, 80, 200, 500]  # Tier 0免费，Tier 1起收费
	},
	"bullet": {
		"label": "弹药蓝图",
		"desc": "解锁新子弹类型",
		"max_tier": 3,
		"unlock_costs": [0, 60, 150, 400]
	},
	"attachment": {
		"label": "配件蓝图",
		"desc": "解锁新配件类型",
		"max_tier": 3,
		"unlock_costs": [0, 50, 120, 350]
	}
}

func _build_blueprint_list() -> void:
	if content == null:
		return
	# 清空旧内容
	for child in content.get_children():
		child.queue_free()
	
	# 标题
	var title := Label.new()
	title.text = "枪械工坊 — 蓝图解锁"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	
	# 分隔
	content.add_child(_make_hsep())
	
	# 说明
	var info := Label.new()
	info.text = "消耗资源解锁蓝图，提升局内装备池多样性"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(info)
	
	content.add_child(_make_hsep())
	
	# 绘制每个类别的Tier进度
	for category_id in BLUEPRINT_TIERS:
		var cat: Dictionary = BLUEPRINT_TIERS[category_id]
		var current_tier: int = BaseManager.get_blueprint_tier(category_id)
		var cat_panel := _make_category_panel(category_id, cat, current_tier)
		content.add_child(cat_panel)

func _make_category_panel(cat_id: String, cat: Dictionary, current_tier: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 80)
	
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	
	# 类别标题行
	var title_row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "[ %s ]  %s" % [cat["label"], cat["desc"]]
	title_row.add_child(lbl)
	var tier_lbl := Label.new()
	tier_lbl.text = " Tier %d / %d" % [current_tier, cat["max_tier"]]
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(tier_lbl)
	vbox.add_child(title_row)
	
	# Tier进度指示（★显示）
	var progress_lbl := Label.new()
	var stars := ""
	for i in range(1, cat["max_tier"] + 1):
		stars += "★" if i <= current_tier else "☆"
	progress_lbl.text = "进度: " + stars
	vbox.add_child(progress_lbl)
	
	# 解锁按钮（如果还有Tier可解锁）
	if current_tier < cat["max_tier"]:
		var next_cost: int = cat["unlock_costs"][current_tier]
		var btn := Button.new()
		btn.text = "解锁下一Tier（消耗 %d 资源）" % next_cost
		btn.pressed.connect(_on_unlock_pressed.bind(cat_id, current_tier, next_cost))
		# 解锁按钮使用金色 accent（与蓝图/解锁主题一致）
		var unlock_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.TEXT_GOLD)
		UIStyleFactory.apply_button_style(btn, unlock_styles)

		# 资源不足时禁用
		var player_points: int = BaseManager.get_extraction_points()
		if player_points < next_cost:
			btn.disabled = true
			btn.text = "资源不足（需要 %d，当前 %d）" % [next_cost, player_points]

		vbox.add_child(btn)
	else:
		var done_lbl := Label.new()
		done_lbl.text = "已满级！所有蓝图已解锁"
		done_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
		vbox.add_child(done_lbl)
	
	return panel

func _make_hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 8)
	return sep

func _on_unlock_pressed(category_id: String, current_tier: int, cost: int) -> void:
	var player_points: int = BaseManager.get_extraction_points()
	if player_points < cost:
		_update_status("资源不足！需要 %d，当前 %d" % [cost, player_points])
		return
	
	# 扣除资源，提升蓝图Tier
	BaseManager.spend_extraction_points(cost)
	BaseManager.set_blueprint_tier(category_id, current_tier + 1)
	_update_status("解锁成功！%s 已升到 Tier %d" % [BLUEPRINT_TIERS[category_id]["label"], current_tier + 1])
	
	# 重建列表
	_build_blueprint_list()

func _update_status(msg: String) -> void:
	if status_label:
		status_label.text = msg

func _on_close_pressed() -> void:
	queue_free()


## — 手电筒模块切换面板 —

func _build_flashlight_module_panel(parent: VBoxContainer = null) -> void:
	var host := parent if parent != null else content
	if host == null:
		return
	host.add_child(_make_hsep())
	var title := Label.new()
	title.text = "手电筒模块"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.add_child(title)
	var info := Label.new()
	info.text = "切换不同模块可改变耗电、亮度、范围与揭示倍率。基础模块永远可用；节能模块需先带回99F安装一次。"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.add_child(info)
	_flashlight_module_panel = PanelContainer.new()
	_flashlight_module_panel.custom_minimum_size = Vector2(560, 90)
	host.add_child(_flashlight_module_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_flashlight_module_panel.add_child(row)
	for profile in MODULE_PROFILES_DISPLAY:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(180, 60)
		var profile_id: String = str(profile.get("id", ""))
		btn.text = "%s\n耗电 %s · 揭示 %s" % [str(profile.get("name", profile_id)), str(profile.get("drain", "?")), str(profile.get("reveal", "?"))]
		btn.pressed.connect(_on_flashlight_module_button_pressed.bind(profile_id))
		row.add_child(btn)
		_flashlight_module_buttons[profile_id] = btn


func _refresh_flashlight_module_panel() -> void:
	if _flashlight_module_panel == null:
		return
	var equipped := BaseManager.get_equipped_flashlight_module_id()
	for profile in MODULE_PROFILES_DISPLAY:
		var profile_id: String = str(profile.get("id", ""))
		var btn: Button = _flashlight_module_buttons.get(profile_id, null)
		if btn == null:
			continue
		var unlocked := BaseManager.is_flashlight_module_unlocked(profile_id)
		btn.disabled = not unlocked
		var prefix := "[已装备] " if profile_id == equipped else ""
		var suffix := "" if unlocked else "  [未解锁]"
		btn.text = "%s%s\n耗电 %s · 揭示 %s%s" % [prefix, str(profile.get("name", profile_id)), str(profile.get("drain", "?")), str(profile.get("reveal", "?")), suffix]


func _on_flashlight_module_button_pressed(module_id: String) -> void:
	if not BaseManager.is_flashlight_module_unlocked(module_id):
		_update_status("该模块尚未解锁")
		return
	if not BaseManager.set_equipped_flashlight_module(module_id):
		_update_status("切换失败")
		return
	# 同步推送到 Player3D(若在基地内)
	var player: Node = get_tree().get_first_node_in_group("player_3d")
	if player != null and player.has_method("equip_flashlight_module"):
		var item := {
			"id": "item_flashlight_%s" % module_id,
			"module_id": module_id,
			"type": "module",
			"subtype": "flashlight_module",
		}
		player.equip_flashlight_module(item)
	_update_status("已切换至 %s" % module_id)
	_refresh_flashlight_module_panel()
	if AudioManager != null:
		AudioManager.play_sfx("ui_click")
