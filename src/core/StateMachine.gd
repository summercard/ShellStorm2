## StateMachine - 通用状态机
##
## 这是状态机框架的零件2：调度器。
## 它挂在任何角色身上，统一管理这个角色有哪些状态、当前在哪个状态、
## 状态之间怎么切换。
##
## 状态本身继承 State 类。
## 状态机本身继承 Node，挂到角色身上（add_child）即可使用。
##
## 使用示例：
##   # 1. 在角色 _ready 里挂上状态机
##   var sm = StateMachine.new()
##   sm.name = "StateMachine"
##   add_child(sm)
##   sm.owner_node = self  # 把角色自己传给状态机
##
##   # 2. 注册所有可能的状态
##   sm.register("idle", EnemyIdleState.new())
##   sm.register("alert", EnemyAlertState.new())
##   sm.register("chase", EnemyChaseState.new())
##   sm.register("search", EnemySearchState.new())
##   sm.register("patrol", EnemyPatrolState.new())
##
##   # 3. 指定起始状态（状态机会自动调用 enter）
##   sm.start("idle")
##
##   # 4. 切换状态
##   sm.transition_to("chase")
##
##   # 5. 发送事件给当前状态
##   sm.dispatch_event("see_player", player_ref)
##
##   # 6. 读取当前状态
##   sm.current_state_name  # "chase"
##   sm.current_state       # EnemyChaseState 实例
##
## 状态切换的安全保证：
## - 切换时自动调用旧状态的 exit() 和新状态的 enter()
## - 同一状态重复切换不会触发多余 enter/exit（除非显式 force=true）
## - 切换是安全的，可以在任何时刻调用（不会打断正在运行的 update）

class_name StateMachine
extends Node

## 当前正在运行的状态名称
var current_state_name: String = ""

## 当前正在运行的状态对象
var current_state: State = null

## 拥有这个状态机的角色节点（状态会通过 owner 访问角色数据）
var owner_node: Node = null

## 已注册的状态字典 {name: State 实例}
var _states: Dictionary = {}

## 状态切换信号（外部可监听）
signal state_changed(from: String, to: String)

## 注册一个状态
## state_name: 状态唯一标识
## state: State 实例（可以是任何继承 State 的类的实例）
func register(state_name: String, state: State) -> void:
	if state == null:
		push_error("StateMachine.register: 状态对象为空")
		return
	state.state_name = state_name
	state.owner = owner_node
	_states[state_name] = state

## 设置起始状态（自动调用 enter）
## 只能在状态机生命周期开始时调用一次
func start(state_name: String) -> void:
	if not _states.has(state_name):
		push_error("StateMachine.start: 未注册的状态 '%s'" % state_name)
		return
	if current_state != null:
		push_warning("StateMachine.start: 已经在运行状态 '%s'，忽略 start('%s')" % [current_state_name, state_name])
		return
	current_state_name = state_name
	current_state = _states[state_name]
	current_state.enter()
	state_changed.emit("", state_name)

## 切换到指定状态
## 自动调用旧状态的 exit() 和新状态的 enter()
## force=true 时即使目标状态与当前状态相同也强制重启（重新调用 exit + enter）
func transition_to(state_name: String, force: bool = false) -> void:
	if not _states.has(state_name):
		push_error("StateMachine.transition_to: 未注册的状态 '%s'" % state_name)
		return
	if current_state == null:
		push_error("StateMachine.transition_to: 状态机还没启动，请先调 start()")
		return
	if state_name == current_state_name and not force:
		return  # 已经在目标状态了，不做切换
	
	var from_state: State = current_state
	var from_name: String = current_state_name
	
	# 退出旧状态
	from_state.exit()
	
	# 进入新状态
	current_state_name = state_name
	current_state = _states[state_name]
	current_state.enter()
	
	state_changed.emit(from_name, state_name)

## 发送事件给当前状态
## 当前状态可以在 handle_event 里决定如何响应
func dispatch_event(event_name: String, data = null) -> void:
	if current_state == null:
		return
	current_state.handle_event(event_name, data)

## 每物理帧调用（由 owner 在 _physics_process 里转发）
func physics_update(delta: float) -> void:
	if current_state == null:
		return
	current_state.physics_update(delta)

## 检查某个状态是否已注册
func has_state(state_name: String) -> bool:
	return _states.has(state_name)

## 获取已注册的状态数量
func get_state_count() -> int:
	return _states.size()

## 获取所有已注册的状态名称
func get_state_names() -> Array:
	return _states.keys()