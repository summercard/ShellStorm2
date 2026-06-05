class_name ContentInjector
extends RefCounted
## 内容注入器接口 — 定义房间内容注入的协议

var _rng := RandomNumberGenerator.new()
var _theme_profile: Resource = null

func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func set_theme_profile(profile: Resource) -> void:
	_theme_profile = profile

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
		RoomData.RoomType.BASEMENT:
			_inject_basement_room(config, room_data)
		RoomData.RoomType.STAIRS_DOWN, RoomData.RoomType.STAIRS_UP:
			_inject_stairs_room(config, room_data)
		RoomData.RoomType.ELEVATOR:
			_inject_elevator_room(config, room_data)

	_apply_theme_content(config, room_data)
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

	# 根据楼层和进度层级调整怪物数量和类型
	# 第二关（floor>=2）起怪物密度要有明显提升——这是玩家熟悉基础后进入正式挑战的节点
	match room_data.floor_level:
		RoomData.FloorLevel.SHALLOW:
			enemy_count = 2 + floor
		RoomData.FloorLevel.MEDIUM:
			enemy_count = 3 + floor + maxi(0, floor - 1)  # 第二关 MEDIUM: 3+2+1=6（比旧公式多1）
		RoomData.FloorLevel.DEEP:
			enemy_count = 4 + floor + maxi(0, floor - 1)  # 第二关 DEEP: 4+2+1=7（比旧公式多2）
		RoomData.FloorLevel.ABYSS:
			enemy_count = 5 + floor
	
	# 生成怪物配置（同时传入 floor 和 floor_level，让 MonsterInjector 正确差异化怪物类型池）
	for i in range(enemy_count):
		var enemy := {
			"type": "random",
			"floor": floor,                              # 实际关卡数字，影响怪物类型池和缩放
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
		"floor": room_data.floor,
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
			"floor": room_data.floor,
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
		var container_type: String = containers[_rng.randi() % containers.size()]
		var container := {
			"type": container_type,
			"position": _get_scavenge_position(i),
			"loot_table": "scavenge_floor_%d" % [min(5, room_data.floor)],
			"has_secret": _rng.randf() < 0.3
		}
		config.interactables.append(container)
	
	# 可能有1-2个守卫
	if _rng.randf() < 0.5:
		config.enemies.append({
			"type": "random",
			"floor": room_data.floor,
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
	if _theme_profile != null:
		var themed_events: Array = _theme_profile.get_content_rule("event_pool", [])
		if not themed_events.is_empty():
			event_types.clear()
			for event_name in themed_events:
				event_types.append(str(event_name))
	var event_type: String = event_types[_rng.randi() % event_types.size()]
	
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
		"floor": room_data.floor,
		"floor_level": room_data.floor_level,
		"boss_id": "boss_floor_%d" % [room_data.floor]
	})
	
	# Boss伴随的精英小怪
	var elite_count: int = 1 + room_data.floor / 4
	for i in range(elite_count):
		config.enemies.append({
			"type": "elite",
			"floor": room_data.floor,
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
		"floor": room_data.floor,
		"floor_level": room_data.floor_level,
		"count": 1 + int(room_data.floor / 2),
	})

## 获取搜刮房间中容器位置
func _get_scavenge_position(index: int) -> Vector2:
	# 螺旋状分布
	var angle: float = index * 1.618 * PI
	var radius: float = 100 + index * 30
	return Vector2(cos(angle), sin(angle)) * radius


## 注入地下室房间（高奖励、高风险）
func _inject_basement_room(config: ContentConfig, room_data: RoomData) -> void:
	# 地下室：更多箱子、更丰富的资源、更多精英怪
	var container_count: int = 2 + room_data.floor
	var containers: Array[String] = ["crate", "locker", "hidden_cache", "chest"]
	
	for i in range(container_count):
		var container_type: String = containers[_rng.randi() % containers.size()]
		var container := {
			"type": container_type,
			"position": _get_scavenge_position(i),
			"loot_table": "scavenge_floor_%d" % [min(5, room_data.floor)],  # 修复：basement_floor_* 不存在于 ItemRegistry，用 scavenge_floor_* 代替
			"has_secret": _rng.randf() < 0.4  # 地下室更多隐藏容器
		}
		config.interactables.append(container)
	
	# 地下室精英怪概率更高（难度补偿）
	if _rng.randf() < 0.6:
		config.enemies.append({
			"type": "elite",
			"floor": room_data.floor,
			"floor_level": room_data.floor_level,
			"modifier_chance": 0.6,
			"tags": ["basement"]
		})
	
	# 伴随小怪
	var minion_count: int = 1 + room_data.floor / 2
	for i in range(minion_count):
		config.enemies.append({
			"type": "random",
			"floor": room_data.floor,
			"floor_level": room_data.floor_level,
			"count": 1
		})


## 注入楼梯房间（垂直通道）
func _inject_stairs_room(config: ContentConfig, room_data: RoomData) -> void:
	# 楼梯房：没有敌人，但有通往其他垂直楼层的提示
	# 交互物是"楼梯"本身，触发后切换 vertical_level
	config.interactables.append({
		"type": "stairs",
		"position": Vector2.ZERO,
		"direction": "down" if room_data.room_type == RoomData.RoomType.STAIRS_DOWN else "up",
		"target_vertical": room_data.vertical_level,
	})


## 注入电梯房间（可上可下的垂直通道）
func _inject_elevator_room(config: ContentConfig, room_data: RoomData) -> void:
	# 电梯房：可选择前往上层或下层
	config.interactables.append({
		"type": "elevator",
		"position": Vector2.ZERO,
		"can_go_up": room_data.vertical_level != RoomData.VerticalLevel.UPPER,
		"can_go_down": room_data.vertical_level != RoomData.VerticalLevel.BASEMENT,
	})


func _apply_theme_content(config: ContentConfig, room_data: RoomData) -> void:
	if _theme_profile == null:
		return
	config.special_conditions.append("theme:%s" % _theme_profile.theme_id)
	for enemy_config in config.enemies:
		enemy_config["theme_id"] = _theme_profile.theme_id

	var container_bonus := int(_theme_profile.get_content_rule("container_bonus", 0))
	if container_bonus > 0 and room_data.room_type in [
		RoomData.RoomType.SCAVENGE, RoomData.RoomType.STORAGE, RoomData.RoomType.EVENT
	]:
		for i in range(container_bonus):
			config.interactables.append({
				"type": "hidden_cache",
				"position": _get_scavenge_position(config.interactables.size() + i),
				"loot_table": "scavenge_floor_%d" % min(5, room_data.floor),
				"theme_id": _theme_profile.theme_id,
			})

	for npc_rule in _theme_profile.npc_rules:
		var room_types: Array = npc_rule.get("room_types", [])
		var room_name := RoomData.get_type_name(room_data.room_type)
		var enum_name: String = RoomData.get_type_id_name(room_data.room_type)
		if not room_types.is_empty() and enum_name not in room_types and room_name not in room_types:
			continue
		if _rng.randf() > float(npc_rule.get("chance", 1.0)):
			continue
		var npc_config: Dictionary = npc_rule.duplicate(true)
		npc_config["type"] = "themed_npc"
		npc_config["position"] = npc_config.get("position", Vector2(0, 110))
		npc_config["theme_id"] = _theme_profile.theme_id
		config.interactables.append(npc_config)
