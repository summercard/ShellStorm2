extends Node
class_name DamageNumbers

# DamageNumbers.gd — 伤害数字特效
# 当敌人受伤时，在其头顶生成飘字
# 配合 EnemyBase.enemy_hit 信号使用

## 飘字配置
@export var float_distance: float = 40.0   # 向上飘的距离（像素）
@export var float_duration: float = 0.8     # 飘字持续时间（秒）
@export var start_scale: float = 1.2         # 初始缩放（弹出感）
@export var end_scale: float = 0.8          # 结束缩放（缩小消失）

## 生成一个伤害数字
## damage: 伤害值，用于字号缩放
## is_crit: 是否暴击，决定颜色和额外特效
static func spawn(world_pos: Vector2, damage: int, is_crit: bool = false) -> void:
	var container: CanvasLayer = DamageNumbers.get_or_create_container()
	if container == null:
		return
	var canvas_pos := DamageNumbers.world_to_canvas(world_pos)

	# === 字号按伤害值缩放 ===
	var font_size: int
	if damage >= 100:
		font_size = 42
	elif damage >= 50:
		font_size = 34
	elif damage >= 25:
		font_size = 26
	elif damage >= 12:
		font_size = 20
	else:
		font_size = 16

	# === 颜色：普通命中按伤害分档，暴击统一金黄 ===
	var modulate_color: Color
	if is_crit:
		# 暴击：金黄（所有暴击统一视觉通道）
		modulate_color = Color(1.0, 0.92, 0.2, 1.0)
	else:
		if damage >= 50:
			modulate_color = Color(1.0, 0.35, 0.1, 1.0)   # 大伤害：亮红
		elif damage >= 25:
			modulate_color = Color(1.0, 0.5, 0.15, 1.0)  # 中大伤害：橙红
		else:
			modulate_color = Color(1.0, 0.3, 0.3, 1.0)    # 普通伤害：标准红

	var label: Label = Label.new()
	label.text = str(damage)
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = modulate_color
	label.z_index = 200
	
	# 初始位置（稍微带点随机偏移）
	var offset: Vector2 = Vector2(randf_range(-10, 10), randf_range(-5, 5))
	label.position = canvas_pos + offset

	# 居中对齐
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	container.add_child(label)

	# 飘字时长随伤害增大而略微延长
	var actual_duration := clampf(0.6 + abs(damage) * 0.003, 0.5, 1.2)

	# 启动动画
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", canvas_pos.y - 40.0 + offset.y, actual_duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(label, "modulate:a", 0.0, actual_duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(label, "scale", Vector2(0.8, 0.8), actual_duration).set_trans(Tween.TRANS_LINEAR)

	# 弹出初始缩放（暴击时更明显）
	var pop_scale := 1.35 if is_crit else 1.2
	label.scale = Vector2(pop_scale, pop_scale)
	var pop: Tween = label.create_tween()
	pop.tween_property(label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 完成后自毁
	tween.chain().tween_callback(label.queue_free.bind())

	# === 暴击时额外特效：屏幕震动（伤害>=50时）===
	if is_crit and damage >= 50:
		var shake: Node = Engine.get_main_loop().root.find_child("ScreenShake", true, false)
		if shake and shake.has_method("trigger"):
			var shake_intensity := clampf(damage * 0.06, 4.0, 8.0)
			var shake_duration := clampf(0.08 + damage * 0.0005, 0.08, 0.15)
			shake.trigger(shake_intensity, shake_duration)

## 获取/创建 CanvasLayer 容器（单例模式）
static func get_or_create_container() -> CanvasLayer:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var existing: CanvasLayer = tree.root.get_node_or_null("DamageNumbersLayer") as CanvasLayer
	if existing:
		return existing
	
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "DamageNumbersLayer"
	layer.layer = 200
	tree.root.add_child(layer)
	return layer

static func world_to_canvas(world_pos: Vector2) -> Vector2:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return world_pos
	var viewport := tree.root.get_viewport()
	if viewport == null:
		return world_pos
	var camera := viewport.get_camera_2d()
	if camera == null:
		return world_pos
	var viewport_size := viewport.get_visible_rect().size
	return (world_pos - camera.get_screen_center_position()) * camera.zoom + viewport_size * 0.5
