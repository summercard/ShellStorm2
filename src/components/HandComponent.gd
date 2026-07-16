## HandComponent - 手部组件（2026-06-10）
##
## 自带 emoji 文字占位 + 武器挂点
## 武器挂到 WeaponAnchor 下（自动建）

class_name HandComponent
extends CharacterComponentBase

## 手部 emoji 文字
@export var emoji_text: String = "✋"
## 手部 emoji 字号
@export var emoji_font_size: int = 16
## 手部 emoji 颜色
@export var emoji_color: Color = Color.WHITE
## 武器占位长方形（尺寸，颜色）
@export var weapon_size: Vector2 = Vector2(20, 6)
@export var weapon_color: Color = Color(0.85, 0.7, 0.3, 1.0)
## 外部传入的视觉节点路径（可选）
@export var visual_node_path: NodePath
@export var weapon_anchor_path: NodePath = NodePath("WeaponAnchor")

var weapon: Node = null

func _ready() -> void:
	# 1. 确保 WeaponAnchor 存在
	if get_node_or_null(weapon_anchor_path) == null:
		var anchor: Marker2D = Marker2D.new()
		anchor.name = "WeaponAnchor"
		add_child(anchor)
	# 2. 临时武器占位（长方形）
	var anchor_node: Node = get_node_or_null(weapon_anchor_path)
	if anchor_node != null:
		var existing: Node = anchor_node.get_node_or_null("WeaponDisplay")
		if existing == null:
			var weapon_rect: ColorRect = ColorRect.new()
			weapon_rect.name = "WeaponDisplay"
			weapon_rect.size = weapon_size
			weapon_rect.position = Vector2(0, -weapon_size.y * 0.5)
			weapon_rect.color = weapon_color
			weapon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			anchor_node.add_child(weapon_rect)
	# 3. 手部视觉（emoji）—— 若没外部传入则创建一个 Label
	if visual_node_path.is_empty() and get_visual_node() == null:
		var lbl: Label = Label.new()
		lbl.name = "Emoji"
		lbl.text = emoji_text
		lbl.add_theme_color_override("font_color", emoji_color)
		lbl.add_theme_font_size_override("font_size", emoji_font_size)
		lbl.position = Vector2(-12, -12)
		lbl.size = Vector2(24, 24)
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

func get_weapon_anchor() -> Marker2D:
	var n: Node = get_node_or_null(weapon_anchor_path)
	if n is Marker2D:
		return n as Marker2D
	return null

func attach_weapon(weapon_node: Node) -> void:
	if weapon != null:
		detach_weapon()
	weapon = weapon_node
	var anchor: Marker2D = get_weapon_anchor()
	if anchor == null:
		push_warning("HandComponent.attach_weapon: 找不到 WeaponAnchor")
		return
	anchor.add_child(weapon_node)

func detach_weapon() -> void:
	if weapon != null and is_instance_valid(weapon):
		weapon.queue_free()
	weapon = null

func set_aim_direction(dir: Vector2) -> void:
	var anchor: Marker2D = get_weapon_anchor()
	if anchor != null and dir.length_squared() > 0.0001:
		anchor.rotation = dir.angle()
