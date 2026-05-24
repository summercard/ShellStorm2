class_name RoomComponentRegistry
## 房间组件注册表
## 运行时管理所有房间组件实例，支持按类型查询/激活/停用

extends Node

## 注册表：component_type → 组件实例列表
var _registry: Dictionary = {}

## 调试模式（打印注册/注销信息）
var _debug_mode: bool = false


func _ready() -> void:
	_init_registry()


func _init_registry() -> void:
	for type_key in RoomComponent.ComponentType.keys():
		var type_val: int = RoomComponent.ComponentType.get(type_key)
		_registry[type_val] = []


## 注册组件实例
func register(component: RoomComponent) -> void:
	var comp_type: int = component.component_type
	if not _registry.has(comp_type):
		_registry[comp_type] = []
	_registry[comp_type].append(component)
	if _debug_mode:
		print("[Registry] Registered %s component at %s" % [component.get_type_name(), component.position])


## 注销组件实例
func unregister(component: RoomComponent) -> void:
	var comp_type: int = component.component_type
	if _registry.has(comp_type):
		var arr: Array = _registry[comp_type]
		var idx: int = arr.find(component)
		if idx >= 0:
			arr.remove_at(idx)
		if _debug_mode:
			print("[Registry] Unregistered %s component" % component.get_type_name())


## 获取指定类型的组件列表
func get_components_by_type(component_type: RoomComponent.ComponentType) -> Array[RoomComponent]:
	return _registry.get(component_type, [])


## 获取所有已激活的指定类型组件
func get_active_components_by_type(component_type: RoomComponent.ComponentType) -> Array[RoomComponent]:
	var all_comp: Array[RoomComponent] = get_components_by_type(component_type)
	var active: Array[RoomComponent] = []
	for comp in all_comp:
		if comp.is_active():
			active.append(comp)
	return active


## 获取所有门组件
func get_door_components() -> Array[RoomComponent]:
	return get_components_by_type(RoomComponent.ComponentType.DOOR)


## 获取所有可交互组件
func get_interact_components() -> Array[RoomComponent]:
	return get_components_by_type(RoomComponent.ComponentType.INTERACT)


## 获取所有出生点组件
func get_spawn_components() -> Array[RoomComponent]:
	return get_components_by_type(RoomComponent.ComponentType.SPAWN)


## 获取所有激活的门组件
func get_active_doors() -> Array[RoomComponent]:
	return get_active_components_by_type(RoomComponent.ComponentType.DOOR)


## 获取最近的门组件（按方向筛选）
func get_door_by_direction(direction: Vector2, active_only: bool = true) -> RoomComponent:
	var doors: Array[RoomComponent] = get_active_doors() if active_only else get_door_components()
	for door in doors:
		var door_comp: DoorComponent = door as DoorComponent
		if door_comp != null and door_comp.direction == direction:
			return door_comp
	return null


## 获取房间内所有组件
func get_all_components() -> Array[RoomComponent]:
	var all: Array[RoomComponent] = []
	for arr in _registry.values():
		all.append_array(arr)
	return all


## 获取已激活的组件数量
func get_active_count() -> int:
	var count: int = 0
	for arr in _registry.values():
		for comp in arr:
			if (comp as RoomComponent).is_active():
				count += 1
	return count


## 按优先级获取排序后的组件列表
func get_sorted_components() -> Array[RoomComponent]:
	var all: Array[RoomComponent] = get_all_components()
	all.sort_custom(func(a: RoomComponent, b: RoomComponent):
		return a.get_priority() < b.get_priority()
	)
	return all


## 激活所有指定类型的组件
func activate_all_by_type(component_type: RoomComponent.ComponentType) -> void:
	var comps: Array[RoomComponent] = get_components_by_type(component_type)
	for comp in comps:
		comp.activate()


## 停用所有指定类型的组件
func deactivate_all_by_type(component_type: RoomComponent.ComponentType) -> void:
	var comps: Array[RoomComponent] = get_components_by_type(component_type)
	for comp in comps:
		comp.deactivate()


## 复位所有组件状态
func reset_all() -> void:
	for arr in _registry.values():
		for comp in arr:
			comp.reset()


## 清空注册表
func clear() -> void:
	for type_key in _registry.keys():
		_registry[type_key] = []


## 调试：打印注册表摘要
func print_summary() -> void:
	print("=== RoomComponentRegistry Summary ===")
	for type_key in RoomComponent.ComponentType.keys():
		var type_val: int = RoomComponent.ComponentType.get(type_key)
		var count: int = _registry.get(type_val, []).size()
		print("  %s: %d" % [type_key, count])
	print("===================================")


## 调试：设置调试模式
func set_debug(enabled: bool) -> void:
	_debug_mode = enabled