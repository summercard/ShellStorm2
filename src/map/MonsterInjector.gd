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
	"boss": { "name": "准首领", "hp_base": 100, "damage_base": 12, "speed": 42 },
}

const ENEMY_PRESENTATION := {
	"melee_chaser": { "emoji": "🐗", "color": Color(0.95, 0.28, 0.24, 1.0), "ai_type": "chase" },
	"ranged_caster": { "emoji": "🍄", "color": Color(0.62, 0.35, 1.0, 1.0), "ai_type": "ranged" },
	"summoner": { "emoji": "🐝", "color": Color(0.95, 0.70, 0.16, 1.0), "ai_type": "summoner" },
	"shielded": { "emoji": "🛡", "color": Color(0.35, 0.62, 0.95, 1.0), "ai_type": "chase" },
	"exploder": { "emoji": "💣", "color": Color(1.0, 0.58, 0.14, 1.0), "ai_type": "bomber" },
	"ambusher": { "emoji": "🦂", "color": Color(0.78, 0.28, 0.88, 1.0), "ai_type": "trapper" },
	"boss": { "emoji": "👹", "color": Color(1.0, 0.12, 0.08, 1.0), "ai_type": "chase" },
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
## 注意：floor参数是实际楼层（1-4），不是 floor_level 进度层级
## 第一关：教学难度，怪物弱，种类少
## 第二关：正式挑战开始，怪物变强，种类增加，体型明显增大
## 第三关及以上：硬核，怪物强，密度高
const FLOOR_SCALING := {
	1: { "hp_mult": 1.0, "damage_mult": 1.0, "loot_mult": 1.0 },
	2: { "hp_mult": 1.4, "damage_mult": 1.2, "loot_mult": 1.3 },  # 第二关：显著提升（hp 1.2→1.4, dmg 1.15→1.2）
	3: { "hp_mult": 1.5, "damage_mult": 1.3, "loot_mult": 1.5 },
	4: { "hp_mult": 1.8, "damage_mult": 1.5, "loot_mult": 1.8 },
	5: { "hp_mult": 2.2, "damage_mult": 1.8, "loot_mult": 2.2 },
}

var _rng: RandomNumberGenerator
var _theme_profile: Resource = null

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()

func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func set_theme_profile(profile: Resource) -> void:
	_theme_profile = profile

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
			var elite := _generate_elite(floor, floor_level, config)
			if not elite.is_empty():
				enemies.append(elite)
		"boss":
			enemies.append(_generate_boss(floor, floor_level, config))
		"minion":
			enemies = _generate_minion_pack(floor, floor_level)
		"guard":
			enemies.append(_generate_guard(floor, floor_level))
		"ambush":
			enemies = _generate_ambush_pack(floor, floor_level, int(config.get("count", 2)))
		_:
			enemies.append(_generate_basic_enemy(_get_theme_fallback_enemy(), floor, floor_level))
	
	return enemies

## 生成随机敌人
func _generate_random_enemies(floor: int, floor_level: int) -> Array[Dictionary]:
	# 怪物数量随楼层增加：每房 baseline 3-5 只（floor=1 -> 3, floor=2 -> 4, floor=4 -> 6）
	var count: int = 2 + floor
	var enemies: Array[Dictionary] = []
	
	var available_types: Array = _get_available_types_for_level(floor_level, floor)
	
	for i in range(count):
		var enemy_type: String = available_types[_rng.randi() % available_types.size()]
		enemies.append(_generate_basic_enemy(enemy_type, floor, floor_level))
	
	return enemies

## 获取指定层级可用的敌人类型（按楼层差异化）
## floor_level: RoomData.FloorLevel 进度层级（SHALLOW/MEDIUM/DEEP/ABYSS）
## floor: 实际楼层数字（1-4），影响同进度层级下的怪物池大小
func _get_available_types_for_level(floor_level: int, floor: int = 1) -> Array[String]:
	if _theme_profile != null:
		var themed_pool: Array = _theme_profile.get_enemy_rule("enemy_pool", [])
		if not themed_pool.is_empty():
			var result: Array[String] = []
			for enemy_type in themed_pool:
				result.append(str(enemy_type))
			return result
	match floor_level:
		RoomData.FloorLevel.SHALLOW:
			# 第一层：3种基础怪物（新手熟悉）
			if floor <= 1:
				return ["melee_chaser", "ranged_caster", "exploder"]
			# 第二层及以上：SHALLOW也开放6种怪物池，丰富度提升
			else:
				return ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher"]
		RoomData.FloorLevel.MEDIUM:
			# 全部6种
			return ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher"]
		RoomData.FloorLevel.DEEP:
			# 全部6种，且怪物密度更高（波次更多）
			return ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher"]
		RoomData.FloorLevel.ABYSS:
			# 仅精英类型
			return ["summoner", "shielded", "ambusher"]
	return ["melee_chaser"]

## 生成基础敌人
func _generate_basic_enemy(enemy_type: String, floor: int, floor_level: int) -> Dictionary:
	var base: Dictionary = BASE_ENEMY_TYPES.get(enemy_type, BASE_ENEMY_TYPES["melee_chaser"])
	var scaling: Dictionary = FLOOR_SCALING.get(floor, FLOOR_SCALING[1])
	var presentation: Dictionary = ENEMY_PRESENTATION.get(enemy_type, ENEMY_PRESENTATION["melee_chaser"])
	
	var hp: float = base["hp_base"] * scaling["hp_mult"]
	var damage: float = base["damage_base"] * scaling["damage_mult"]
	var speed: float = base["speed"]
	if _theme_profile != null:
		hp *= float(_theme_profile.get_enemy_rule("hp_multiplier", 1.0))
		damage *= float(_theme_profile.get_enemy_rule("damage_multiplier", 1.0))
		speed *= float(_theme_profile.get_enemy_rule("speed_multiplier", 1.0))
	
	var result := {
		"enemy_type": enemy_type,
		"name": base["name"],
		"hp": int(hp),
		"max_hp": int(hp),
		"damage": int(damage),
		"speed": speed,
		"emoji": presentation.get("emoji", "🐗"),
		"color": presentation.get("color", Color(1.0, 0.25, 0.25, 1.0)),
		"ai_type": presentation.get("ai_type", "chase"),
		"floor": floor,
		"loot_table": _get_loot_table(floor_level),
		"xp_value": 10 + floor * 5
	}
	if _theme_profile != null:
		var prefix := str(_theme_profile.get_enemy_rule("name_prefix", ""))
		if not prefix.is_empty():
			result["name"] = "%s%s" % [prefix, result["name"]]
		result["theme_id"] = _theme_profile.theme_id
	return result

## 生成精英敌人
func _generate_elite(floor: int, floor_level: int, request: Dictionary = {}) -> Dictionary:
	var encounter_id := str(request.get(
		"encounter_id", "legacy:%d:%d:%d" % [_rng.seed, floor, _rng.randi()]
	))
	var elite_snapshot: Dictionary = {}
	if EliteRosterService != null:
		elite_snapshot = EliteRosterService.select_and_reserve(
			int(request.get("seed", _rng.seed)),
			int(request.get("floor_number", floor)),
			encounter_id
		)
	if elite_snapshot.is_empty() or bool(elite_snapshot.get("success", true)) == false:
		return {}
	var base_type := str(elite_snapshot.get(
		"base_enemy_id", _get_theme_fallback_enemy("shielded")
	))
	# 无名王冠复用Boss轻量外观，但仍走精英结算而不是Boss路线解锁。
	var base: Dictionary = _generate_basic_enemy(base_type, floor, floor_level)
	base["is_elite"] = true
	base["hp"] = int(base["hp"] * 1.5)
	base["max_hp"] = base["hp"]
	base["damage"] = int(base["damage"] * 1.3)
	
	# 随机词缀
	var modifier_keys: Array = ELITE_MODIFIERS.keys()
	var selected_modifier: String = modifier_keys[_rng.randi() % modifier_keys.size()]
	var requested_modifier := str(elite_snapshot.get("modifier_id", ""))
	for localized_name in modifier_keys:
		if _map_modifier_to_english(str(localized_name)) == requested_modifier:
			selected_modifier = str(localized_name)
			break
	var mod_data: Dictionary = ELITE_MODIFIERS[selected_modifier]
	
	base["modifier"] = selected_modifier
	base["modifier_data"] = mod_data
	# 映射中文词缀到英文ID，供 EliteActiveSkillComponent.inject_elite_skills() 正确路由技能
	base["modifier_id_en"] = _map_modifier_to_english(selected_modifier)
	base["name"] = selected_modifier + base["name"]
	base["xp_value"] = 50 + floor * 20
	base["bounty_tier"] = floor
	# 精英怪使用专用掉落表（elite_floor_1 / elite_floor_2）
	# 这样 ItemRegistry 中配置的 elite_floor_* 权重才能生效
	base["loot_table"] = "elite_floor_1" if floor <= 2 else "elite_floor_2"
	if EliteRosterService != null and not elite_snapshot.is_empty():
		base = EliteRosterService.apply_archive_to_enemy_config(base, elite_snapshot)
	return base

## 生成Boss敌人
func _generate_boss(floor: int, floor_level: int, request: Dictionary = {}) -> Dictionary:
	var scaling: Dictionary = FLOOR_SCALING.get(floor, FLOOR_SCALING[1])
	var hp: float = 200.0 * scaling["hp_mult"]
	
	# 第二关Boss体型按策划案要求为1.5x（v0.1规范）
	# 第三关1.6，第四关1.75，后续按+0.15递增
	var boss_scale: float = 1.0
	if floor >= 2:
		boss_scale = 1.5 + (floor - 2) * 0.15  # floor=2→1.5, floor=3→1.65, floor=4→1.8
	
	var result := {
		"enemy_type": "boss",
		"name": "Boss 第%d层" % [floor],
		"hp": int(hp * boss_scale),  # boss_scale 同步放大 HP（与 BossActor._apply_shape_scale 联动）
		"max_hp": int(hp * boss_scale),
		"damage": int(20.0 * scaling["damage_mult"]),
		"speed": 60,
		"emoji": ENEMY_PRESENTATION["boss"]["emoji"],
		"color": ENEMY_PRESENTATION["boss"]["color"],
		"scale": 1.5 * boss_scale,  # 视觉效果同步放大（与碰撞体 boss_scale 成比例）
		"boss_scale": boss_scale,   # BossActor 读取此字段并应用到碰撞体形状大小
		"ai_type": ENEMY_PRESENTATION["boss"]["ai_type"],
		"floor": floor,
		"is_boss": true,
		"phases": 2 + floor / 3,
		"loot_table": "boss_floor_%d" % [floor],
		"xp_value": 200 + floor * 50,
		"bounty_tier": floor + 1
	}
	if _theme_profile != null:
		result["hp"] = int(result["hp"] * float(_theme_profile.get_enemy_rule("hp_multiplier", 1.0)))
		result["max_hp"] = result["hp"]
		result["damage"] = int(result["damage"] * float(
			_theme_profile.get_enemy_rule("damage_multiplier", 1.0)
		))
		result["speed"] = float(result["speed"]) * float(
			_theme_profile.get_enemy_rule("speed_multiplier", 1.0)
		)
		result["name"] = str(_theme_profile.get_enemy_rule(
			"boss_name", "%s首领" % _theme_profile.display_name
		))
		result["theme_id"] = _theme_profile.theme_id
	var floor_number := int(request.get("floor_number", 95))
	var boss_profile := BossContentCatalog.get_for_floor(floor_number)
	if not boss_profile.is_empty():
		result["floor_number"] = floor_number
		result["boss_content_id"] = str(boss_profile["boss_content_id"])
		result["name"] = str(boss_profile["display_name"])
		result["presentation_asset_id"] = str(boss_profile["presentation_asset_id"])
		result["presentation_scene"] = str(boss_profile["presentation_scene"])
		result["arena_asset_id"] = str(boss_profile["arena_asset_id"])
		result["arena_scene"] = str(boss_profile["arena_scene"])
		result["boss_accent"] = boss_profile.get("accent", Color(1.0, 0.2, 0.035))
		result["boss_phase_skill_bags"] = (boss_profile["phase_skill_bags"] as Dictionary).duplicate(true)
	return result

## 生成小怪群
func _generate_minion_pack(floor: int, floor_level: int) -> Array[Dictionary]:
	var count: int = 3 + floor
	var minions: Array[Dictionary] = []
	
	for i in range(count):
		var minion := _generate_basic_enemy(_get_theme_fallback_enemy("exploder"), floor, floor_level)
		minion["hp"] = int(minion["hp"] * 0.5)
		minion["max_hp"] = minion["hp"]
		minions.append(minion)
	
	return minions

## 生成守卫
func _generate_guard(floor: int, floor_level: int) -> Dictionary:
	var guard := _generate_basic_enemy(_get_theme_fallback_enemy("shielded"), floor, floor_level)
	guard["name"] = "商人护卫"
	guard["is_guard"] = true
	guard["xp_value"] = 15 + floor * 5
	return guard


func _generate_ambush_pack(floor: int, floor_level: int, count: int) -> Array[Dictionary]:
	var enemies: Array[Dictionary] = []
	var pool := _get_available_types_for_level(floor_level, floor)
	for i in range(maxi(1, count)):
		var enemy_type := pool[_rng.randi() % pool.size()]
		enemies.append(_generate_basic_enemy(enemy_type, floor, floor_level))
	return enemies


func _get_theme_fallback_enemy(default_enemy: String = "melee_chaser") -> String:
	if _theme_profile == null:
		return default_enemy
	var pool: Array = _theme_profile.get_enemy_rule("enemy_pool", [])
	if pool.is_empty():
		return default_enemy
	return str(pool[0])

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

## 映射中文词缀ID到英文，供 EliteActiveSkillComponent.inject_elite_skills() 正确路由
static func _map_modifier_to_english(cn_id: String) -> String:
	match cn_id:
		"巨大化": return "Elite.Huge"
		"分裂": return "Elite.SpawnOnDeath"
		"反弹": return "Elite.Ricochet"
		"寄生": return "Elite.Parasite"
		"抢枪": return "Elite.WeaponParasite"
		"吞弹": return "Elite.BulletEater"
	return "Elite.Huge"
