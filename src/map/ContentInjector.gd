class_name ContentInjector
extends RefCounted
## 内容注入器接口 — 定义房间内容注入的协议

## 返回内容字典的结构
class ContentConfig:
	var enemies: Array[Dictionary] = []   # 怪物配置列表
	var loot: Array[Dictionary] = []       # 掉落物品配置
	var events: Array[Dictionary] = []     # 事件配置
	var interactables: Array[Dictionary] = []  # 可交互对象
	var special_conditions: Array[String] = []   # 特殊条件

	func to_dict() -> Dictionary:
		return {
			"enemies": _copy_dictionary_array(enemies),
			"loot": _copy_dictionary_array(loot),
			"events": _copy_dictionary_array(events),
			"interactables": _copy_dictionary_array(interactables),
			"special_conditions": special_conditions.duplicate(),
		}

	func _copy_dictionary_array(values: Array[Dictionary]) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for value in values:
			result.append(value.duplicate(true))
		return result

## 注入内容到房间
func inject(room_data: RoomData) -> ContentConfig:
	var config := ContentConfig.new()
	
	# 根据房间类型进行不同的注入
	match room_data.room_type:
		RoomData.RoomType.PLAYER_SPAWN:
			_inject_spawn_room(config, room_data)
		RoomData.RoomType.COMBAT:
			_inject_combat_room(config, room_data)
		RoomData.RoomType.ELITE:
			_inject_elite_room(config, room_data)
		RoomData.RoomType.SCAVENGE:
			_inject_scavenge_room(config, room_data)
		RoomData.RoomType.MERCHANT:
			_inject_merchant_room(config, room_data)
		RoomData.RoomType.UPGRADE:
			_inject_upgrade_room(config, room_data)
		RoomData.RoomType.EVENT:
			_inject_event_room(config, room_data)
		RoomData.RoomType.EXTRACTION:
			_inject_extraction_room(config, room_data)
		RoomData.RoomType.BOSS:
			_inject_boss_room(config, room_data)
		RoomData.RoomType.STORAGE:
			_inject_storage_room(config, room_data)
		RoomData.RoomType.TRAP:
			_inject_trap_room(config, room_data)
	
	return config

## 注入出生房间
func _inject_spawn_room(config: ContentConfig, room_data: RoomData) -> void:
	# 出生房通常没有敌人，但可能有引导性交互物
	var chest := {
		"type": "chest",
		"position": Vector2(-96, 0),
		"loot_table": "spawn_starter",
		"locked": false,
		"guaranteed_items": ["weapon_shotgun"],
	}
	config.interactables.append(chest)

## 注入普通战斗房间
func _inject_combat_room(config: ContentConfig, room_data: RoomData) -> void:
	var floor: int = room_data.floor
	var enemy_count: int = 2 + floor
	
	# 根据层级调整怪物数量和类型
	match room_data.floor_level:
		RoomData.FloorLevel.SHALLOW:
			enemy_count = 2 + floor
		RoomData.FloorLevel.MEDIUM:
			enemy_count = 3 + floor
		RoomData.FloorLevel.DEEP:
			enemy_count = 4 + floor
		RoomData.FloorLevel.ABYSS:
			enemy_count = 5 + floor
	
	# 生成怪物配置
	for i in range(enemy_count):
		var enemy := {
			"type": "random",
			"floor_level": room_data.floor_level,
			"tags": room_data.tags.duplicate()
		}
		config.enemies.append(enemy)
	config.interactables.append({
		"type": "crate",
		"position": Vector2(110, -90),
		"loot_table": "combat_floor_%d" % [min(5, floor)],
	})

## 注入精英战斗房间
func _inject_elite_room(config: ContentConfig, room_data: RoomData) -> void:
	# 精英房：1个精英怪 + 若干小怪
	var elite := {
		"type": "elite",
		"floor_level": room_data.floor_level,
		"modifier_chance": 0.5,
		"tags": room_data.tags.duplicate()
	}
	config.enemies.append(elite)
	
	# 伴随小怪
	var minion_count: int = 2 + room_data.floor / 2
	for i in range(minion_count):
		config.enemies.append({
			"type": "minion",
			"floor_level": room_data.floor_level
		})
	config.interactables.append({
		"type": "locker",
		"position": Vector2(-130, 80),
		"loot_table": "elite_floor_%d" % [min(5, room_data.floor)],
	})

## 注入搜刮房间
func _inject_scavenge_room(config: ContentConfig, room_data: RoomData) -> void:
	# 搜刮房：多个容器
	var container_count: int = 2 + room_data.floor
	var containers: Array[String] = ["crate", "locker", "hidden_cache"]
	
	for i in range(container_count):
		var container_type: String = containers[randi() % containers.size()]
		var container := {
			"type": container_type,
			"position": _get_scavenge_position(i),
			"loot_table": "scavenge_floor_%d" % [min(5, room_data.floor)],
			"has_secret": randf() < 0.3
		}
		config.interactables.append(container)
	
	# 可能有1-2个守卫
	if randf() < 0.5:
		config.enemies.append({
			"type": "random",
			"floor_level": room_data.floor_level,
			"count": 1
		})

## 注入商人房间
func _inject_merchant_room(config: ContentConfig, room_data: RoomData) -> void:
	# 商人房：商人NPC + 可购买物品
	config.interactables.append({
		"type": "merchant",
		"position": Vector2.ZERO,
		"inventory_tier": room_data.floor
	})
	
	# 环境敌人（商人保镖）
	if room_data.floor >= 2:
		config.enemies.append({
			"type": "guard",
			"floor_level": room_data.floor_level
		})

## 注入改造房间
func _inject_upgrade_room(config: ContentConfig, room_data: RoomData) -> void:
	# 改造房：工作台 + 可改造物品
	config.interactables.append({
		"type": "workbench",
		"position": Vector2.ZERO,
		"upgrade_slots": 1 + room_data.floor / 3,
		"free_use": room_data.floor < 3
	})

## 注入事件房间
func _inject_event_room(config: ContentConfig, room_data: RoomData) -> void:
	# 事件房：随机事件触发器
	var event_types: Array[String] = ["gamble", "trade", "curse", "blessing", "ambush"]
	var event_type: String = event_types[randi() % event_types.size()]
	
	config.events.append({
		"type": event_type,
		"floor_level": room_data.floor_level
	})

## 注入撤离房间
func _inject_extraction_room(config: ContentConfig, room_data: RoomData) -> void:
	# 撤离房：撤离点配置
	config.interactables.append({
		"type": "extraction_point",
		"position": Vector2.ZERO,
		"extraction_type": "standard",
		"countdown": 10
	})
	config.interactables.append({
		"type": "locker",
		"position": Vector2(120, 80),
		"loot_table": "extraction_floor_%d" % [min(5, room_data.floor)],
	})

## 注入Boss房间
func _inject_boss_room(config: ContentConfig, room_data: RoomData) -> void:
	# Boss房：Boss + 小怪
	config.enemies.append({
		"type": "boss",
		"floor_level": room_data.floor_level,
		"boss_id": "boss_floor_%d" % [room_data.floor]
	})
	
	# Boss伴随的精英小怪
	var elite_count: int = 1 + room_data.floor / 4
	for i in range(elite_count):
		config.enemies.append({
			"type": "elite",
			"floor_level": room_data.floor_level
		})
	config.interactables.append({
		"type": "chest",
		"position": Vector2(0, -130),
		"loot_table": "boss_floor_%d" % [min(5, room_data.floor)],
	})

func _inject_storage_room(config: ContentConfig, room_data: RoomData) -> void:
	var count := 2 + room_data.floor
	for i in range(count):
		config.interactables.append({
			"type": "locker",
			"position": _get_scavenge_position(i),
			"loot_table": "storage_floor_%d" % [min(5, room_data.floor)],
		})

func _inject_trap_room(config: ContentConfig, room_data: RoomData) -> void:
	config.interactables.append({
		"type": "hidden_cache",
		"position": Vector2(90, 70),
		"loot_table": "trap_floor_%d" % [min(5, room_data.floor)],
	})
	config.enemies.append({
		"type": "ambush",
		"floor_level": room_data.floor_level,
		"count": 1 + int(room_data.floor / 2),
	})

## 获取搜刮房间中容器位置
func _get_scavenge_position(index: int) -> Vector2:
	# 螺旋状分布
	var angle: float = index * 1.618 * PI
	var radius: float = 100 + index * 30
	return Vector2(cos(angle), sin(angle)) * radius
