## PlayerDeadState - 玩家"死亡"状态
##
## 行为：禁用输入；HP <= 0 触发；只能从 idle 进入。
## 一旦进入不能退出（除非外部 game_over 处理完重置角色）。

class_name PlayerDeadState
extends PlayerStateBase

func enter() -> void:
	super.enter()
	_announce("dead")
	player.input_locked = true
	player.set_combat_enabled(false)
	player.velocity = Vector2.ZERO
	player.move_and_slide()

func physics_update(delta: float) -> void:
	player.velocity = Vector2.ZERO
	player.move_and_slide()

func exit() -> void:
	pass  # 死亡状态不主动退出
