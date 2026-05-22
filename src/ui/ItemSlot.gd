## ItemSlot — 物品格子UI组件
## 配合 InventoryUI 使用，显示物品图标、叠加数量

class_name ItemSlot
extends TextureRect

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)

var slot_index: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func set_slot_index(idx: int) -> void:
	slot_index = idx

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				slot_clicked.emit(slot_index)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				slot_right_clicked.emit(slot_index)