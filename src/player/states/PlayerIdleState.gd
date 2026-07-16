## PlayerIdleState - 玩家"空闲"状态（默认）
##
## 行为：响应输入方向移动；检测冲刺按键；检测死亡；处理冷却计时。
## 这是默认状态，受伤后的无敌帧也算在这个状态里。

class_name PlayerIdleState
extends PlayerStateBase

func enter() -> void:
	super.enter()
	_announce("idle")
	player.is_dashing = false

func physics_update(delta: float) -> void:
	if player.current_hp <= 0:
		_go("dead")
		return
	if player.input_locked:
		_go("locked")
		return
	_tick_dash_cooldown(delta)
	
	# 检测冲刺按键
	if Input.is_action_just_pressed("dash") and _begin_dash():
		return
	
	# 正常移动
	var dir: Vector2 = _input_direction()
	if dir != Vector2.ZERO:
		player.last_move_direction = dir
		player.velocity = dir * player.SPEED
		player.move_and_slide()
		_go("moving")
		return
	player.velocity = Vector2.ZERO
	player.move_and_slide()

## 事件钩子：Player 转发 request_dash 事件到这里
func handle_event(event_name: String, _data = null) -> void:
	if event_name == "request_dash":
		_begin_dash()
