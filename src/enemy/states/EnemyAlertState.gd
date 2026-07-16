## EnemyAlertState - 敌人"警觉"状态
##
## 行为：原地不动，头上显示黄问号，持续看到玩家就重置计时器；
## 计时器跑完：能看到→追击；看不到→去搜索。

class_name EnemyAlertState
extends EnemyStateBase

var _alert_timer: float = 0.0

func enter() -> void:
	super.enter()
	enemy._ai_state = enemy.AIState.ALERT
	_alert_timer = enemy.alert_duration

func physics_update(delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	_set_emoji("❓", Color(1.0, 0.85, 0.0, 1.0))
	
	_alert_timer -= delta
	if _can_see_player():
		_alert_timer = enemy.alert_duration  # 持续看到目标，重置计时
	if _alert_timer <= 0.0:
		if _can_see_player():
			_go("chase")
		else:
			if enemy.player_ref and is_instance_valid(enemy.player_ref):
				enemy._last_known_player_pos = enemy.player_ref.global_position
			_go("search")