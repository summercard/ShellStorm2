extends Node
class_name HitEffects

# HitEffects.gd — 战斗反馈中枢
# 监听 enemy_hit 信号，触发屏幕震动
# 挂载在 Main 节点下

var _screen_shake: ScreenShake

func _ready() -> void:
	# 优先查找 Camera2D 子节点下的 ScreenShake
	_screen_shake = get_node_or_null("Camera2D/ScreenShake")
	if not _screen_shake:
		_screen_shake = get_tree().root.find_child("ScreenShake", false, false) as ScreenShake

	# 动态连接所有现有敌人
	_connect_all_enemies()
	# 监听新增敌人
	get_tree().node_added.connect(_on_node_added)

func _connect_all_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_connect_enemy_signals(enemy)

func _on_node_added(node: Node) -> void:
	if node.is_in_group("enemy"):
		_connect_enemy_signals(node)

func _connect_enemy_signals(enemy: Node) -> void:
	if enemy.has_signal("enemy_hit"):
		if not enemy.enemy_hit.is_connected(_on_enemy_hit):
			enemy.enemy_hit.connect(_on_enemy_hit)

func _on_enemy_hit(_hit_from: Vector2, damage: int, is_crit: bool) -> void:
	if _screen_shake:
		# 震动强度根据伤害和暴击动态调整
		var intensity := 5.0
		if damage >= 20:
			intensity = 10.0
		elif damage >= 10:
			intensity = 7.0
		if is_crit:
			intensity *= 1.5
		var duration := 0.12 if not is_crit else 0.18
		_screen_shake.trigger(intensity, duration)