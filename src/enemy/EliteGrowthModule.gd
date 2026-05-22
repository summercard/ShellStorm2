extends Node
## 精英怪成长模块
## 根据战斗结果计算成长，处理装备转化

signal growth_applied(elite_id: String, growth_data: Dictionary)

const MODULE_CONVERSION = {
	"GunBody": "EnemySkill_BackMountedMachinegun",
	"Bullet": "EnemyRanged_AdaptedBullet",
	"Attachment": "EnemySkill_Modifier",
	"FateCard": "Elite.FateResidue"
}

func _ready() -> void:
	pass


func calculate_growth_from_escape(biome_level: int) -> Dictionary:
	"""根据逃脱场景计算成长"""
	return {
		"hp_gain": 0.1 + biome_level * 0.02,
		"damage_gain": 0.05,
		"speed_gain": 0.05 + biome_level * 0.01,
		"level_up": 1 if randf() < 0.3 else 0
	}


func calculate_growth_from_kill_player(level_diff: int) -> Dictionary:
	"""根据击杀玩家计算成长"""
	return {
		"hp_gain": 0.2 + level_diff * 0.05,
		"damage_gain": 0.2 + level_diff * 0.05,
		"speed_gain": 0.05,
		"level_up": 1
	}


func calculate_growth_from_environment(biome_tag: String) -> Dictionary:
	"""根据环境吸收计算成长"""
	var growth: Dictionary = {"hp_gain": 0.0, "damage_gain": 0.0, "speed_gain": 0.0, "level_up": 0}
	match biome_tag:
		"ToxicGarden":
			growth["hp_gain"] = 0.1
		"FireZone":
			growth["damage_gain"] = 0.1
		"DarkCave":
			growth["speed_gain"] = 0.08
		"IceCave":
			growth["hp_gain"] = 0.08
		"ElectricZone":
			growth["damage_gain"] = 0.1
	return growth


func convert_player_module(module_data: Dictionary) -> Dictionary:
	"""将玩家模块转换为精英怪技能
	
	module_data: {module_id, module_type, ...}
	return: {skill_id, skill_params}
	"""
	var module_type = module_data.get("module_type", "")
	var skill_id = MODULE_CONVERSION.get(module_type, "EnemySkill_Generic")
	return {
		"skill_id": skill_id,
		"module_type": module_type,
		"module_id": module_data.get("module_id", ""),
		"damage_scale": 0.3,  # 精英怪使用玩家模块时伤害打三折
		"cooldown_scale": 1.5  # 冷却时间拉长一半
	}


func can_equip_module(existing_count: int, elite_level: int) -> bool:
	"""判断精英怪是否可以继续装备模块"""
	var max_slots = 1 + (elite_level / 3)
	return existing_count < max_slots


func select_modifier_for_enemy(base_enemy_id: String, level: int) -> Array[String]:
	"""根据精英怪基础类型和等级选择词缀
	
	Returns array of modifier strings
	"""
	var pool: Array[String] = []
	if level >= 2:
		pool.append("Elite.Huge")
	if level >= 3:
		pool.append("Elite.SpawnOnDeath")
	if level >= 4:
		pool.append("Elite.Ricochet")
	if level >= 5:
		pool.append("Elite.Parasite")
	if level >= 6:
		pool.append("Elite.WeaponParasite")
	if level >= 7:
		pool.append("Elite.GunFeed")
	return pool.slice(0, min(2, pool.size()))