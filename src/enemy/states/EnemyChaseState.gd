## EnemyChaseState - 敌人"追击"状态
##
## 行为：全速追击玩家（带房间边界拦截），头上显示红感叹号；
## 看不到玩家→去搜索。
## 进入时：发"警觉信号"给房间刷怪控制器 + 触发精英联动。

class_name EnemyChaseState
extends EnemyStateBase

func enter() -> void:
	super.enter()
	enemy._ai_state = enemy.AIState.CHASE
	# v0.1 P1+P2：追击时向房间刷怪控制器发警觉信号 + 触发精英联动
	enemy.enemy_entered_chase.emit(enemy, enemy._last_known_player_pos)
	if enemy.has_method("_notify_skill_components"):
		enemy._notify_skill_components("on_engaged")
	if enemy._is_elite:
		enemy.elite_entered_chase.emit(enemy, enemy._last_known_player_pos)

func physics_update(delta: float) -> void:
	if not (enemy.player_ref and is_instance_valid(enemy.player_ref)):
		return
	var dir: Vector2 = (enemy.player_ref.global_position - enemy.global_position).normalized()
	enemy.velocity = _move_toward(dir, enemy.speed)
	_set_emoji("❗", Color(1.0, 0.15, 0.15, 1.0))
	
	if not _can_see_player():
		if enemy.player_ref and is_instance_valid(enemy.player_ref):
			enemy._last_known_player_pos = enemy.player_ref.global_position
		_go("search")