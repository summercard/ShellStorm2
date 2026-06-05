extends Node
## 精英遭遇结算桥接器
## 职责：实例化 EliteGrowthModule，提供统一遭遇结算 API，路由环境成长
##
## 使用方式：
##   var bridge := EliteEncounterBridge.new()
##   var growth = bridge.resolve_extraction(elite_id, biome_level)
##   _elite_archive.on_encounter_result(elite_id, "PlayerExtracted", growth)
##
## 原本硬编码在 RoomGameMode._resolve_elite_encounters_for_extraction/death 中的
## growth 数据计算逻辑全部移到这里，由 EliteGrowthModule 提供可配置的成长函数。

const ELITE_GROWTH_MODULE_SCRIPT := preload("res://src/enemy/EliteGrowthModule.gd")

var _growth_module: Node = null

func _init() -> void:
	_growth_module = ELITE_GROWTH_MODULE_SCRIPT.new()
	add_child(_growth_module)


func resolve_extraction(elite_id: String, biome_level: int) -> Dictionary:
	"""玩家成功撤离时，结算精英逃脱成长

	biome_level: 当前楼层（影响 HP/speed 成长幅度）
	return: growth_data 字典，供 EliteArchiveModule.on_encounter_result() 使用
	"""
	return _growth_module.calculate_growth_from_escape(biome_level)


func resolve_death(elite_id: String, level_diff: int) -> Dictionary:
	"""玩家死亡时，结算精英击杀玩家成长

	level_diff: 精英等级 - 玩家等级（差值影响成长幅度）
	return: growth_data 字典
	"""
	return _growth_module.calculate_growth_from_kill_player(level_diff)


func resolve_environment(biome_tag: String) -> Dictionary:
	"""精英吸收环境能量后获得成长

	biome_tag: 环境标签（ToxicGarden/FireZone/DarkCave/IceCave/ElectricZone）
	return: growth_data 字典（可叠加到其他成长上）
	"""
	return _growth_module.calculate_growth_from_environment(biome_tag)


func convert_stolen_module(module_data: Dictionary) -> Dictionary:
	"""将玩家掉落的模块转换为精英怪可用的技能数据

	module_data: {module_id, module_type, ...}
	return: {skill_id, module_type, module_id, damage_scale, cooldown_scale}
	"""
	return _growth_module.convert_player_module(module_data)


func can_elite_equip(existing_count: int, elite_level: int) -> bool:
	"""判断精英怪是否可以继续装备模块"""
	return _growth_module.can_equip_module(existing_count, elite_level)


func select_modifiers(base_enemy_id: String, level: int) -> Array[String]:
	"""根据精英类型和等级选择词缀"""
	return _growth_module.select_modifier_for_enemy(base_enemy_id, level)
