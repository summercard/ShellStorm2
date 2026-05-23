extends Node
class_name DamageNumbers

# DamageNumbers.gd — 伤害数字特效
# 当敌人受伤时，在其头顶生成飘字
# 配合 EnemyBase.enemy_hit 信号使用

const NUMBER_SCENE: PackedScene = preload("res://scenes/DamageNumber.tscn")

## 飘字配置
@export var float_distance: float = 40.0   # 向上飘的距离（像素）
@export var float_duration: float = 0.8     # 飘字持续时间（秒）
@export var start_scale: float = 1.2         # 初始缩放（弹出感）
@export var end_scale: float = 0.8          # 结束缩放（缩小消失）

## 生成一个伤害数字
static func spawn(world_pos: Vector2, damage: int, is_crit: bool = false) -> void:
	var container: CanvasLayer = DamageNumbers.get_or_create_container()
	
	var label: Label = Label.new()
	label.text = str(damage)
	label.add_theme_font_size_override("font_size", 24 if is_crit else 16)
	label.modulate = Color(1.0, 0.3, 0.3, 1.0) if not is_crit else Color(1.0, 0.9, 0.2, 1.0)
	label.z_index = 200
	
	# 初始位置（稍微带点随机偏移）
	var offset: Vector2 = Vector2(randf_range(-10, 10), randf_range(-5, 5))
	label.position = world_pos + offset
	
	# 居中对齐
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	container.add_child(label)
	
	# 启动动画
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y - 40.0 + offset.y, 0.8).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(label, "scale", Vector2(0.8, 0.8), 0.8).set_trans(Tween.TRANS_LINEAR)
	
	# 弹出初始缩放
	label.scale = Vector2(1.2, 1.2)
	var pop: Tween = label.create_tween()
	pop.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	
	# 完成后自毁
	tween.chain().tween_callback(label.queue_free.bind())

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
