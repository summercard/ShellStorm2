## EnemySearchState - 敌人"搜索"状态
##
## 行为：朝最后看到玩家的位置移动（减速到 60%），到达后停下；
## 计时器跑完→转巡逻；中途看到玩家→追击。

class_name EnemySearchState
extends EnemyStateBase

var _search_timer: float = 0.0

func enter() -> void:
	super.enter()
	enemy._ai_state = enemy.AIState.SEARCH
	_search_timer = enemy.search_duration

func physics_update(delta: float) -> void:
	var to_last: Vector2 = enemy._last_known_player_pos - enemy.global_position
	if to_last.length() > 15.0:
		enemy.velocity = _move_toward(to_last.normalized(), enemy.speed * 0.6)
	else:
		enemy.velocity = Vector2.ZERO
	_set_emoji("❓", Color(0.9, 0.75, 0.0, 1.0))
	
	_search_timer -= delta
	if _can_see_player():
		_go("chase")
	elif _search_timer <= 0.0:
		_go("patrol")