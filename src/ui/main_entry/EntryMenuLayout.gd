extends Control
## 启动页左侧区域动态布局：管理 Screen/MenuPanel/Margin/Content 下的
## 兼容节点（Title / PlayerStatus / OutfitStatus 隐藏）与可见节点
## （Brand / Eyebrow / Subtitle / StartButton / SettingsButton / Hint）的响应式定位。
## 全程用 Control 直接定位，避免 PanelContainer 布局，保留主脚本依赖的节点路径。
##
## 说明：本脚本只负责定位与绘制左侧底纹，不连任何业务逻辑；SettingsButton 的
## pressed 由主脚本（MainEntryScreen3D.gd）负责接线。

@onready var eyebrow: Label = $Margin/Content/Eyebrow
@onready var brand: Control = $Margin/Content/Brand
@onready var subtitle: Label = $Margin/Content/Subtitle
@onready var start_button: Button = $Margin/Content/StartButton
@onready var settings_button: Button = $Margin/Content/SettingsButton
@onready var hint: Label = $Margin/Content/Hint

const DESIGN_W := 1280.0
const DESIGN_H := 720.0

func _ready() -> void:
	for n in ["Title", "PlayerStatus", "OutfitStatus"]:
		var c := get_node_or_null("Margin/Content/" + n)
		if c != null:
			c.visible = false
	resized.connect(_on_resized)
	call_deferred("_layout")

func _on_resized() -> void:
	_layout()
	queue_redraw()

func _layout() -> void:
	if get_viewport() == null:
		return
	var vp := get_viewport_rect().size
	var s := clampf(minf(vp.x / DESIGN_W, vp.y / DESIGN_H), 0.75, 2.0)
	_place(eyebrow, 50.0, 92.0, 440.0, 26.0, s)
	_place(brand, 44.0, 140.0, 452.0, 150.0, s)
	_place(subtitle, 50.0, 296.0, 440.0, 22.0, s)
	_place(start_button, 50.0, 325.0, 440.0, 56.0, s)
	_place(settings_button, 50.0, 425.0, 440.0, 56.0, s)
	_place(hint, 50.0, 668.0, 440.0, 26.0, s)

func _place(node: Control, x: float, y: float, w: float, h: float, s: float) -> void:
	if node == null:
		return
	node.position = Vector2(x * s, y * s)
	node.size = Vector2(w * s, h * s)
	node.queue_redraw()

func _draw() -> void:
	# 左侧半透明底纹，向右渐隐为透明，为右侧 3D 角色留出可视区域。
	var w := size.x
	var h := size.y
	var limit := w * 0.42
	var steps := 56
	for i in range(steps):
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var x0 := t0 * limit
		var x1 := t1 * limit
		var a := 0.60 * (1.0 - t0) * (1.0 - t0)
		draw_rect(Rect2(x0, 0.0, (x1 - x0) + 1.0, h), Color(0.004, 0.012, 0.020, a), true)
	# 不画隔栏：菜单与实景自然融合。
