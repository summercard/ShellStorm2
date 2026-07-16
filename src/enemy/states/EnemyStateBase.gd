## EnemyStateBase - 敌人所有状态的基类
##
## 提供 5 个状态共用的工具方法，让每个具体状态不用重复样板代码。
## 所有具体敌人状态（空闲/警觉/追击/搜索/巡逻）都继承这个类。

class_name EnemyStateBase
extends State

## 获取 enemy 引用（owner 字段在 register 时会被设成 EnemyBase 实例）
var enemy: Node = null

## 便捷方法：调用 enemy 的 _update_emoji_display
func _set_emoji(text: String, color: Color) -> void:
	if enemy and enemy.has_method("_update_emoji_display"):
		enemy._update_emoji_display(text, color)

## 便捷方法：调用 enemy 的 _apply_boundary_on_dir（带边界修正的方向速度）
func _move_toward(dir: Vector2, spd: float) -> Vector2:
	if enemy and enemy.has_method("_apply_boundary_on_dir"):
		return enemy._apply_boundary_on_dir(dir, spd)
	return dir * spd

## 便捷方法：调用 enemy 的 _idle_wander（原地轻微随机移动）
func _idle_wander(delta: float) -> void:
	if enemy and enemy.has_method("_idle_wander"):
		enemy._idle_wander(delta)

## 便捷方法：调用 enemy 的 _patrol_tick（巡逻路径推进）
func _patrol_tick(delta: float) -> void:
	if enemy and enemy.has_method("_patrol_tick"):
		enemy._patrol_tick(delta)

## 便捷方法：计算到玩家的距离
func _dist_to_player() -> float:
	if enemy and enemy.player_ref and is_instance_valid(enemy.player_ref):
		return enemy.global_position.distance_to(enemy.player_ref.global_position)
	return INF

## 便捷方法：判断能否看到玩家（带视线遮挡检测）
func _can_see_player() -> bool:
	if enemy and enemy.has_method("_line_of_sight_check"):
		if enemy.player_ref and is_instance_valid(enemy.player_ref):
			return enemy._line_of_sight_check(enemy.global_position, enemy.player_ref.global_position)
	return false

## 便捷方法：判断能否听到玩家（距离 < 听觉范围）
func _can_hear_player() -> bool:
	var d: float = _dist_to_player()
	if enemy:
		return d <= enemy.hearing_range
	return false

## 便捷方法：切换到指定状态（通过 enemy 持有的状态机）
func _go(state_name: String) -> void:
	if enemy and enemy._state_machine:
		enemy._state_machine.transition_to(state_name)

## 进入状态时把 owner 缓存到 enemy 字段（因为 owner 类型是 Node，不方便）
func enter() -> void:
	enemy = owner