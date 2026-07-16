## State - 状态机中的"单个状态"基类
##
## 这是状态机框架的零件1：状态模版。
## 任何状态都继承这个类，照着填四个钩子函数即可：
##   enter()            —— 进入这个状态时调用一次
##   exit()             —— 离开这个状态时调用一次
##   physics_update(d)  —— 每物理帧调用（处理持续行为，比如追击时往玩家方向跑）
##   handle_event(name, data) —— 外部事件触发（比如"看到玩家"、"受伤"）
##
## 使用方式（伪代码）：
##   class_name EnemyChaseState extends State
##   func enter(): 主人._ai_state = AIState.CHASE
##   func physics_update(delta): 主人.追击玩家(delta)
##   ...
##   状态机.register("chase", EnemyChaseState.new())
##
## 这里的"主人"指的是挂这个状态机的角色，由子类在构造时传入。
##
## 设计原则：
## - 状态对象本身只关心"我的进入/更新/退出/事件是什么"
## - 不知道下一个状态是谁（切换由状态机调度，不是状态自己决定）
## - 状态可以调用 owner 的方法访问角色数据，但不要反向引用状态机

class_name State
extends RefCounted

## 状态名称（可选，用于调试日志）
var state_name: String = ""

## 拥有这个状态的角色引用（在状态机注册时由调用方设置）
var owner: Node = null

## 进入状态时调用一次（子类重写）
func enter() -> void:
	pass

## 离开状态时调用一次（子类重写）
func exit() -> void:
	pass

## 每物理帧调用（子类重写，处理持续行为）
func physics_update(_delta: float) -> void:
	pass

## 外部事件触发（子类重写，处理瞬时事件，比如"看到玩家"、"受伤"）
## event_name: 事件标识
## data: 事件附带的数据（任意类型，由调用方约定）
func handle_event(_event_name: String, _data = null) -> void:
	pass