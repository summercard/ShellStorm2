## HeadComponent - 头部组件（2026-06-10）
##
## 自带 emoji 文字占位资产

class_name HeadComponent
extends CharacterComponentBase

## 头部 emoji 文字
@export var emoji_text: String = "(•_•)"
## 头部 emoji 字号
@export var emoji_font_size: int = 18
## 头部 emoji 颜色
@export var emoji_color: Color = Color.WHITE
## 外部传入的视觉节点路径（可选）；若为空则自动创建 Label 占位
@export var visual_node_path: NodePath

func _ready() -> void:
	if visual_node_path.is_empty() and get_visual_node() == null:
		var lbl: Label = Label.new()
		lbl.name = "Emoji"
		lbl.text = emoji_text
		lbl.add_theme_color_override("font_color", emoji_color)
		lbl.add_theme_font_size_override("font_size", emoji_font_size)
		# 让 Label 自适应大小
		lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		lbl.position = Vector2(-20, -42)
		lbl.size = Vector2(40, 24)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)
		visual_node_path = NodePath("Emoji")

func set_visual(path: NodePath) -> void:
	visual_node_path = path

func get_visual_node() -> Node:
	if visual_node_path.is_empty():
		return null
	return get_node_or_null(visual_node_path)
