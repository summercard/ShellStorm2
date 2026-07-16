## BossIdleState - Boss"待机"状态
##
## 行为：未被激活，不参与战斗。
## 退出：activate() 被调 → 进入 combat。

class_name BossIdleState
extends BossStateBase

func enter() -> void:
	super.enter()
	boss._activated = false
	if boss._phase_director:
		boss._phase_director.set_process(false)

func physics_update(delta: float) -> void:
	# 待机时：阶段 Director 不需要 tick（未激活不会触发技能）
	pass
