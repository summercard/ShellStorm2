@tool
extends VBoxContainer

const STAGE := preload("res://tools/scene_builder/preview_stage.gd")
var stage: STAGE
var caption: Label
var surface: SubViewportContainer
var pending_path := ""

func _init() -> void:
	surface = SubViewportContainer.new()
	surface.custom_minimum_size = Vector2(220, 170)
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.stretch = true
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(surface)
	stage = STAGE.new()
	surface.add_child(stage)
	surface.gui_input.connect(_input_preview)
	var bottom := HBoxContainer.new()
	add_child(bottom)
	caption = Label.new()
	caption.text = "选中组件预览 · 拖动旋转 / 滚轮缩放"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(caption)
	var reset := Button.new()
	reset.text = "复位"
	reset.pressed.connect(func(): stage.preview_reset())
	bottom.add_child(reset)

func show_asset(row: Dictionary) -> void:
	caption.text = "拖动旋转 · 滚轮缩放" if stage.show_asset(str(row["prefab_path"])) else "预览失败，请检查资产"

func set_pending(row: Dictionary) -> void:
	pending_path = str(row["prefab_path"])
	caption.text = "正在读取：" + str(row.get("label", "组件"))
	# Hide the old geometry so it cannot be mistaken for the newly selected component.
	stage.pivot.visible = false

func show_resource(row: Dictionary, packed: PackedScene) -> bool:
	if pending_path != str(row["prefab_path"]):
		return false
	var valid := stage.show_asset(pending_path, packed)
	stage.pivot.visible = valid
	caption.text = "拖动旋转 · 滚轮缩放" if valid else "这个组件没有可显示的3D模型"
	return valid

func show_failure(reason: String) -> void:
	stage.pivot.visible = false
	caption.text = reason

func _input_preview(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		stage.yaw -= event.relative.x * 0.012
		stage.pitch = clampf(stage.pitch + event.relative.y * 0.012, -1.3, 1.3)
		stage.update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			stage.distance = clampf(stage.distance * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14), 1.5, 10)
			stage.update_camera()
