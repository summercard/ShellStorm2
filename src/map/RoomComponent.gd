class_name RoomComponent
## 房间组件基类
## 所有房间组件（Foor/Wall/Door/Interact/Spawn）的基类
## 组件注册到 RoomComponentRegistry，支持运行时查询

extends Node2D

## 组件类型枚举
enum ComponentType {
	FLOOR,       # 地板组件
	WALL,        # 墙体组件
	DOOR,        # 门组件
	INTERACT,    # 可交互组件（容器/工作台等）
	SPAWN,       # 敌人出生点组件
	DECORATION,  # 装饰组件
	TRIGGER,     # 触发器组件
}

## 组件优先级（决定渲染/碰撞顺序）
enum ComponentPriority {
	BACKGROUND = 0,   # 背景层
	FLOOR = 10,       # 地板层
	WALL = 20,        # 墙体层
	DECORATION = 30,  # 装饰层
	INTERACT = 40,    # 交互层
	SPAWN = 50,       # 生成层
	DOOR = 60,        # 门层
	FOREGROUND = 70,  # 前景层
}

@export var component_type: ComponentType = ComponentType.FLOOR
@export var priority: ComponentPriority = ComponentPriority.FLOOR

## 组件是否激活（某些组件可以被暂时禁用）
var _is_active: bool = true

## 组件配置数据（由 RoomBlueprint 在实例化时注入）
var component_config: Dictionary = {}

## 是否已完成初始化
var _initialized: bool = false


## 初始化组件（由 RoomBlueprint 调用）
func initialize(config: Dictionary = {}) -> void:
	component_config = config
	_is_active = config.get("active", true)
	_on_initialize()
	_initialized = true


## 子类可重写的初始化逻辑
func _on_initialize() -> void:
	pass


## 激活组件
func activate() -> void:
	_is_active = true
	_on_activate()


## 停用组件
func deactivate() -> void:
	_is_active = false
	_on_deactivate()


## 子类可重写的激活/停用逻辑
func _on_activate() -> void:
	visible = true


func _on_deactivate() -> void:
	visible = false


## 获取组件类型名称
func get_type_name() -> String:
	return ComponentType.keys()[component_type] if component_type in ComponentType.keys() else "UNKNOWN"


## 获取优先级（用于排序）
func get_priority() -> int:
	return priority


## 是否处于激活状态
func is_active() -> bool:
	return _is_active


## 复位组件状态（房间重入时调用）
func reset() -> void:
	_is_active = true
	_on_reset()
	_initialized = false


## 子类可重写的复位逻辑
func _on_reset() -> void:
	pass


## 获取组件调试信息
func get_debug_info() -> Dictionary:
	return {
		"type": get_type_name(),
		"priority": priority,
		"active": _is_active,
		"position": position,
		"config": component_config,
	}