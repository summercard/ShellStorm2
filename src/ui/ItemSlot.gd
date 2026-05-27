## ItemSlot — 物品格子UI组件
## 配合 InventoryUI 使用，显示物品图标、叠加数量

class_name ItemSlot
extends TextureRect

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)

var slot_index: int = -1
var _hovered: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var count_label := get_node_or_null("CountLabel") as Control
	if count_label != null:
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func set_slot_index(idx: int) -> void:
	slot_index = idx

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				slot_clicked.emit(slot_index)
				accept_event()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				slot_right_clicked.emit(slot_index)
				accept_event()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _draw() -> void:
	var border_color := Color(0.34, 0.39, 0.48, 0.75)
	if _hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.56, 0.82, 0.18), true)
		border_color = Color(0.72, 0.82, 1.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 2.0 if _hovered else 1.0)
