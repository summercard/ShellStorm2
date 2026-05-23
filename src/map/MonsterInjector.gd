class_name MonsterInjector
extends RefCounted
## 怪物注入器 — 根据房间类型和层级生成怪物配置

## 怪物基础类型配置
const BASE_ENEMY_TYPES := {
	"melee_chaser": { "name": "小菌猪", "hp_base": 25, "damage_base": 5, "speed": 80 },
	"ranged_caster": { "name": "孢子射手", "hp_base": 15, "damage_base": 8, "speed": 50 },
	"summoner": { "name": "蜂巢怪", "hp_base": 30, "damage_base": 0, "speed": 40 },
	"shielded": { "name": "壳甲卫兵", "hp_base": 40, "damage_base": 3, "speed": 30 },
	"exploder": { "name": "炸弹果", "hp_base": 10, "damage_base": 15, "speed": 70 },
	"ambusher": { "name": "地刺虫", "hp_base": 18, "damage_base": 7, "speed": 90 },
}

## 精英词缀配置
const ELITE_MODIFIERS := {
	"巨大化": { "hp_mult": 2.0, "scale_mult": 1.5, "speed_mult": 0.8 },
	"分裂": { "on_death_spawn": 3, "spawn_type": "minion" },
	"反弹": { "reflect_chance": 0.3, "reflect_damage_mult": 0.5 },
	"寄生": { "on_death_attach_to": "nearest_enemy", "stat_mult": 1.3 },
	"抢枪": { "steal_weapon": true, "duration_sec": 10 },
	"吞弹": { "absorb_bullets": true, "convert_to_attack": true },
}

## 层级难度缩放
const FLOOR_SCALING := {
	1: { "hp_mult": 1.0, "damage_mult": 1.0, "loot_mult": 1.0 },
	2: { "hp_mult": 1.2, "damage_mult": 1.15, "loot_mult": 1.2 },
	3: { "hp_mult": 1.5, "damage_mult": 1.3, "loot_mult": 1.5 },
	4: { "hp_mult": 1.8, "damage_mult": 1.5, "loot_mult": 1.8 },
	5: { "hp_mult": 2.2, "damage_mult": 1.8, "loot_mult": 2.2 },
}

var _rng: RandomNumberGenerator

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()

## 根据配置生成怪物列表
func generate_enemies(config: Dictionary) -> Array[Dictionary]:
	var enemies: Array[Dictionary] = []
	var enemy_type: String = config.get("type", "random")
	var floor_level: int = config.get("floor_level", RoomData.FloorLevel.SHALLOW)
	var floor: int = config.get("floor", 1)
	
	match enemy_type:
		"random":
			enemies = _generate_random_enemies(floor, floor_level)
		"elite":
			enemies.append(_generate_elite(floor, floor_level))
		"boss":
			enemies.append(_generate_boss(floor, floor_level))
		"minion":
			enemies = _generate_minion_pack(floor, floor_level)
		"guard":
			enemies.append(_generate_guard(floor, floor_level))
		_:
			enemies.append(_generate_basic_enemy("melee_chaser", floor, floor_level))
	
	return enemies

## 生成随机敌人
func _generate_random_enemies(floor: int, floor_level: int) -> Array[Dictionary]:
	var count: int = 1 + floor / 2
	var enemies: Array[Dictionary] = []
	
	var available_types: Array = _get_available_types_for_level(floor_level)
	
	for i in range(count):
		var enemy_type: String = available_types[_rng.randi() % available_types.size()]
		enemies.append(_generate_basic_enemy(enemy_type, floor, floor_level))
	
	return enemies

## 获取指定层级可用的敌人类型
func _get_available_types_for_level(floor_level: int) -> Array[String]:
	match floor_level:
		RoomData.FloorLevel.SHALLOW:
			return ["melee_chaser", "ranged_caster", "exploder"]
		RoomData.FloorLevel.MEDIUM:
			return ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher"]
		RoomData.FloorLevel.DEEP:
			return ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher"]
		RoomData.FloorLevel.ABYSS:
			return ["summoner", "shielded", "ambusher"]  # 高难度只留精英类型
	return ["melee_chaser"]

## 生成基础敌人
func _generate_basic_enemy(enemy_type: String, floor: int, floor_level: int) -> Dictionary:
	var base: Dictionary = BASE_ENEMY_TYPES.get(enemy_type, BASE_ENEMY_TYPES["melee_chaser"])
	var scaling: Dictionary = FLOOR_SCALING.get(floor, FLOOR_SCALING[1])
	
	var hp: float = base["hp_base"] * scaling["hp_mult"]
	var damage: float = base["damage_base"] * scaling["damage_mult"]
	var speed: float = base["speed"]
	
	return {
		"enemy_type": enemy_type,
		"name": base["name"],
		"hp": int(hp),
		"max_hp": int(hp),
		"damage": int(damage),
		"speed": speed,
		"floor": floor,
		"loot_table": _get_loot_table(floor_level),
		"xp_value": 10 + floor * 5
	}

## 生成精英敌人
func _generate_elite(floor: int, floor_level: int) -> Dictionary:
	var base: Dictionary = _generate_basic_enemy("shielded", floor, floor_level)
	base["is_elite"] = true
	base["hp"] = int(base["hp"] * 1.5)
	base["max_hp"] = base["hp"]
	base["damage"] = int(base["damage"] * 1.3)
	
	# 随机词缀
	var modifier_keys: Array = ELITE_MODIFIERS.keys()
	var selected_modifier: String = modifier_keys[_rng.randi() % modifier_keys.size()]
	var mod_data: Dictionary = ELITE_MODIFIERS[selected_modifier]
	
	base["modifier"] = selected_modifier
	base["modifier_data"] = mod_data
	base["name"] = selected_modifier + base["name"]
	base["xp_value"] = 50 + floor * 20
	base["bounty_tier"] = floor
	
	return base

## 生成Boss敌人
func _generate_boss(floor: int, floor_level: int) -> Dictionary:
	var scaling: Dictionary = FLOOR_SCALING.get(floor, FLOOR_SCALING[1])
	var hp: float = 200.0 * scaling["hp_mult"]
	
	return {
		"enemy_type": "boss",
		"name": "Boss 第%d层" % [floor],
		"hp": int(hp),
		"max_hp": int(hp),
		"damage": int(20.0 * scaling["damage_mult"]),
		"speed": 60,
		"floor": floor,
		"is_boss": true,
		"phases": 2 + floor / 3,
		"loot_table": "boss_floor_%d" % [floor],
		"xp_value": 200 + floor * 50,
		"bounty_tier": floor + 1
	}

## 生成小怪群
func _generate_minion_pack(floor: int, floor_level: int) -> Array[Dictionary]:
	var count: int = 3 + floor
	var minions: Array[Dictionary] = []
	
	for i in range(count):
		var minion := _generate_basic_enemy("exploder", floor, floor_level)
		minion["hp"] = int(minion["hp"] * 0.5)
		minion["max_hp"] = minion["hp"]
		minions.append(minion)
	
	return minions

## 生成守卫
func _generate_guard(floor: int, floor_level: int) -> Dictionary:
	var guard := _generate_basic_enemy("shielded", floor, floor_level)
	guard["name"] = "商人护卫"
	guard["is_guard"] = true
	guard["xp_value"] = 15 + floor * 5
	return guard

## 获取掉落表名称
func _get_loot_table(floor_level: int) -> String:
	match floor_level:
		RoomData.FloorLevel.SHALLOW: return "loot_floor_1_2"
		RoomData.FloorLevel.MEDIUM: return "loot_floor_3_4"
		RoomData.FloorLevel.DEEP: return "loot_floor_5"
		RoomData.FloorLevel.ABYSS: return "loot_abyss"
	return "loot_common"

## 获取精英词缀描述
static func get_modifier_description(modifier: String) -> String:
	match modifier:
		"巨大化": return "体型增大，血量翻倍，移动变慢"
		"分裂": return "死亡时分裂成小怪"
		"反弹": return "周期性反弹子弹"
		"寄生": return "死亡后强化附近的怪物"
		"抢枪": return "短暂复制玩家的武器效果"
		"吞弹": return "吃掉投射物并转化为攻击"
	return ""
