## PlayerStateBase - 玩家所有状态的基类
##
## 提供 6 个顶层状态（idle/moving/dashing/hurt/locked/dead）的共用工具方法。
## 注意：沉默（silenced）和无敌（invincible）不是顶层状态：
## - 沉默：叠加标志，与任何状态共存
## - 无敌：dashing 状态的副作用，take_damage 时临时附加

class_name PlayerStateBase
extends State

## 缓存 player 引用
var player: Node = null

## 进入时把 owner 缓存到 player 字段
func enter() -> void:
	player = owner

## 便捷：读取输入方向（包含 PC + 移动端）
func _input_direction() -> Vector2:
	if player and player.has_method("_get_input_direction"):
		return player._get_input_direction()
	return Vector2.ZERO

## 便捷：发射冲刺开始信号
func _emit_dash_started() -> void:
	if player and player.has_signal("dash_started"):
		player.dash_started.emit()

## 便捷：发射冲刺结束信号
func _emit_dash_ended() -> void:
	if player and player.has_signal("dash_ended"):
		player.dash_ended.emit()

## 便捷：发射冷却信号
func _emit_dash_cooldown(ratio: float) -> void:
	if player and player.has_signal("dash_cooldown_changed"):
		player.dash_cooldown_changed.emit(ratio)


func _announce(state_id: String, context: Dictionary = {}) -> void:
	if player and player.has_method("_set_presentation_state"):
		player.call("_set_presentation_state", state_id, context)


func _tick_dash_cooldown(delta: float) -> void:
	if player and player.has_method("_tick_dash_cooldown"):
		player.call("_tick_dash_cooldown", delta)


func _begin_dash() -> bool:
	if player and player.has_method("_begin_dash"):
		return bool(player.call("_begin_dash"))
	return false

## 便捷：请求切换到指定状态
func _go(state_name: String) -> void:
	if player and player._state_machine:
		player._state_machine.transition_to(state_name)
