## BodyComponent - 身体组件（2026-06-10）
##
## 角色躯干组件。负责：
## - 容纳头部和手部组件（层级式：body 包含 head 包含 hand）
## - 身体级别的反馈（受伤闪白、抖动、缩放反馈等）
## - 自带方块占位资产

class_name BodyComponent
extends CharacterComponentBase

## 身体临时资产：方块大小
@export var body_size: Vector2 = Vector2(28, 32)
## 身体临时资产：方块颜色
@export var body_color: Color = Color(0.25, 0.55, 0.95, 1.0)
## 外部传入的视觉节点路径（可选）；若为空则自动创建方块
@export var visual_node_path: NodePath

var head: HeadComponent = null
var hand: HandComponent = null

func _ready() -> void:
	for child in get_children():
		if child is HeadComponent:
			head = child
		elif child is HandComponent:
			hand = child
	# 如果没有外部传入视觉节点，就创建一个方块占位
	if visual_node_path.is_empty() and get_visual_node() == null:
		var rect: ColorRect = ColorRect.new()
		rect.name = "BodyShape"
		rect.size = body_size
		rect.position = -body_size * 0.5
		rect.color = body_color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		visual_node_path = NodePath("BodyShape")

func set_visual(path: NodePath) -> void:
	visual_node_path = path

func get_visual_node() -> Node:
	if visual_node_path.is_empty():
		return null
	return get_node_or_null(visual_node_path)

func attach_head(h: HeadComponent) -> void:
	if head != null:
		head.queue_free()
	head = h
	head.name = "Head"
	add_child(h)

func attach_hand(h: HandComponent) -> void:
	if hand != null:
		hand.queue_free()
	hand = h
	hand.name = "Hand"
	if head != null:
		head.add_child(h)
	else:
		add_child(h)
