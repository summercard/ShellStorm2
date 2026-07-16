## EnemyIdleState - 敌人"空闲"状态
##
## 行为：原地轻微随机徘徊，看到玩家就进警觉，听到玩家就去搜索。

class_name EnemyIdleState
extends EnemyStateBase

func enter() -> void:
	super.enter()
	enemy._ai_state = enemy.AIState.IDLE  # 同步旧字段，兼容可能存在的外部判断
	enemy._noise_accumulator = 0.0  # IDLE 进入时清零噪声累积

func physics_update(delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	_set_emoji("👾", Color.WHITE)
	
	if _can_see_player():
		_go("alert")
	elif _can_hear_player() and enemy._noise_accumulator > enemy.hearing_range * 0.6:
		_go("search")
	else:
		_idle_wander(delta)