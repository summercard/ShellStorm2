## BossStateBase - Boss 所有状态的基类
##
## 3 个具体状态（idle/combat/dead）共用工具方法。
## 注意：Boss 的"战斗阶段"（phase1/2/3）由 BossPhaseDirector 管理，
##       这是独立子系统，不纳入 BossActor 顶层状态机。

class_name BossStateBase
extends State

## 缓存 boss 引用
var boss: Node = null

## 进入时把 owner 缓存到 boss 字段
func enter() -> void:
	boss = owner

## 便捷：请求切换到指定状态
func _go(state_name: String) -> void:
	if boss and boss._state_machine:
		boss._state_machine.transition_to(state_name)