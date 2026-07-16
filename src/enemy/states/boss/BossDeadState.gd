## BossDeadState - Boss"死亡"状态
##
## 行为：HP <= 0 触发，停止所有活动，禁用碰撞，触发死亡特效。
## 一次性状态，进去了不再被任何事件切换。

class_name BossDeadState
extends BossStateBase

func enter() -> void:
	super.enter()
	if boss._phase_director:
		boss._phase_director.set_process(false)
	if boss.has_method("_complete_death"):
		boss._complete_death()

func physics_update(delta: float) -> void:
	# 死亡状态不做任何事
	pass
