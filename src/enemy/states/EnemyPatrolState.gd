## EnemyPatrolState - 敌人"巡逻"状态
##
## 行为：沿固定巡逻路径移动，灰色emoji；
## 看到玩家→警觉；听到玩家→搜索。

class_name EnemyPatrolState
extends EnemyStateBase

func enter() -> void:
	super.enter()
	enemy._ai_state = enemy.AIState.PATROL
	enemy._noise_accumulator = 0.0  # PATROL 进入时清零噪声累积

func physics_update(delta: float) -> void:
	# 噪声衰减（每帧独立衰减，保留原行为）
	enemy._noise_accumulator = maxf(0.0, enemy._noise_accumulator - enemy._NOISE_DECAY_RATE * delta)
	enemy._patrol_cooldown -= delta
	_set_emoji("👾", Color(0.6, 0.6, 0.6, 1.0))
	
	_patrol_tick(delta)  # 在房间边界内巡逻
	
	if _can_see_player():
		_go("alert")
	elif _can_hear_player() and enemy._noise_accumulator > enemy.hearing_range * 0.5:
		if enemy.player_ref and is_instance_valid(enemy.player_ref):
			enemy._last_known_player_pos = enemy.player_ref.global_position
		_go("search")