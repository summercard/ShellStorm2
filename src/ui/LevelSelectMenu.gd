class_name LevelSelectMenu
extends CanvasLayer

@onready var level_buttons_container: VBoxContainer = $Panel/VBox/LevelButtonsContainer

const FLOOR_INFO = {
	1: { "name": "第一关", "desc": "新手区 · 敌人较弱", "color": Color(0.4, 0.8, 0.4, 1.0) },
	2: { "name": "第二关", "desc": "危险区 · 精英出现", "color": Color(1.0, 0.7, 0.2, 1.0) },
	3: { "name": "第三关", "desc": "深渊区 · 怪物密集", "color": Color(1.0, 0.4, 0.3, 1.0) },
	4: { "name": "第四关", "desc": "噩梦区 · 极限挑战", "color": Color(0.7, 0.2, 1.0, 1.0) },
}

func _ready() -> void:
	_build_level_buttons()
	_refresh_unlocks()
	var close_btn: Button = $Panel/VBox/CloseButton
	if close_btn:
		close_btn.pressed.connect(_on_close_pressed)

func _build_level_buttons() -> void:
	for child in level_buttons_container.get_children():
		child.queue_free()

	for floor in range(1, 5):
		var info: Dictionary = FLOOR_INFO[floor]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(500, 70)
		btn.text = ""
		btn.pressed.connect(_on_level_button_pressed.bind(floor))

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl := Label.new()
		name_lbl.text = info["name"]
		name_lbl.add_theme_color_override("font_color", info["color"])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = info["desc"]
		desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1.0))
		hbox.add_child(desc_lbl)

		btn.add_child(hbox)
		level_buttons_container.add_child(btn)

func _refresh_unlocks() -> void:
	# 默认全部解锁（后续可接入 BaseManager 数据）
	pass

func _on_level_button_pressed(floor: int) -> void:
	# 清理菜单，再切换场景
	queue_free()
	# 切换场景并指定初始楼层
	LevelSelect.selected_floor = floor
	LevelSelect.selection_made = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_close_pressed() -> void:
	queue_free()