class_name MonsterInjector
extends RefCounted
## 怪物注入器 — 根据房间类型和层级生成怪物配置

## 怪物基础类型配置
const BASE_ENEMY_TYPES := {
	"melee_chaser": { "name": "小僵尸", "hp_base": 25, "damage_base": 5, "speed": 80 },
	"ranged_caster": { "name": "孢子射手", "hp_base": 15, "damage_base": 8, "speed": 50 },
	"summoner": { "name": "蜂巢怪", "hp_base": 30, "damage_base": 0, "speed": 40 },
	"shielded": { "name": "壳甲卫兵", "hp_base": 40, "damage_base": 3, "speed": 30 },
	"exploder": { "name": "炸弹果", "hp_base": 10, "damage_base": 15, "speed": 70 },
	"ambusher": { "name": "地刺虫", "hp_base": 18, "damage_base": 7, "speed": 90 },
	"boss": { "name": "准首领", "hp_base": 100, "damage_base": 12, "speed": 42 },
}

const ENEMY_PRESENTATION := {
	"melee_chaser": { "emoji": "尸", "color": Color(0.95, 0.28, 0.24, 1.0), "ai_type": "chase" },
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
			var boss := _generate_boss(floor, floor_level, config)
			if not boss.is_empty():
				enemies.append(boss)
		"minion":
			enemies = _generate_minion_pack(floor, floor_level)
		"guard":
			enemies.append(_generate_guard(floor, floor_level))
		"ambush":
			enemies = _generate_ambush_pack(floor, floor_level, int(config.get("count", 2)))
		_:
			enemies.append(_generate_basic_enemy(_get_theme_fallback_enemy(), floor, floor_level))
	
	return enemies

## 触发盒路径：按**明确的怪种**生成一只（`docs/v0.1/design/触发器刷怪设计.md` §3.1）。
##
## 为什么不能用 `generate_enemies`：它走 `match enemy_type`，普通怪种（melee_chaser 等）
## 落到 `_:` 分支 → 生成的是**主题兜底怪**而不是点名的那个种类，盒子写什么都会失效。
## 本函数与 `build_waves_from_plan` 同口径：普通怪直取 `_generate_basic_enemy`，
## `elite` / `boss` 走各自装配端（它们是**身份指派**，不是编成）。
## 未知或非法 type 返回 {}（调用方跳过，绝不退化成别的东西）。
func generate_box_enemy(type_id: String, floor: int, floor_level: int, extra: Dictionary = {}) -> Dictionary:
	if type_id == "elite":
		return _generate_elite(floor, floor_level, extra)
	if type_id == "boss":
		return _generate_boss(floor, floor_level, extra)
	if is_authorable_enemy_type(type_id):
		return _generate_basic_enemy(type_id, floor, floor_level)
	return {}

## 设计源覆盖：按关卡设计源给定的波次计划生成敌人。
## 外层每项 = 一波（**波次数钉死**），每波有两种写法，**互斥**：
##   ① 逐值固定：`{"monsters": [{"type": "melee_chaser", "count": 2}]}`
##   ② 半钉死：  `{"pool": ["melee_chaser","ambusher"], "kinds": {"min":1,"max":2},
##                "count": {"min":2,"max":4}}`
##      —— 从 pool 抽 `kinds` 种、总数量落 `count` 区间（每局按 `variant_seed` 抽）。
##
## 只覆盖**编成**（波次数 / 每波数量 / 怪物种类），不覆盖**数值**：每只怪仍走
## `_generate_basic_enemy`，因此主题倍率与楼层缩放照常生效，避免设计源与全局数值
## 出现两套真源。返回 Array[Array[Dictionary]]（每波一个配置数组）；
## 计划缺失或非法时返回空数组，由调用方回退全局公式 —— 绝不产出半截波次。
func build_waves_from_plan(
	plan: Dictionary, floor: int, floor_level: int, variant_seed: int = 0
) -> Array:
	var waves: Array = []
	if plan.is_empty():
		return waves
	var raw_waves: Variant = plan.get("waves", [])
	if not (raw_waves is Array) or (raw_waves as Array).is_empty():
		return waves
	# 「半钉死」波次的抽取源。**必须是本函数私有的 rng**：本实例的 `_rng` 被
	# boss / elite / 公式路径共用，若在此消耗，抽取结果会依赖「谁先调用」而无法复现。
	# 由调用方传入 `variant_seed`（Dungeon3D 传 run_seed + 房 id 派生）⇒ 同局同房恒定、
	# 不同局/不同房不同。固定写法（monsters）不使用它，故老关卡行为逐字不变。
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	for wave_value in (raw_waves as Array):
		if not (wave_value is Dictionary):
			return []
		var wave := wave_value as Dictionary
		var composition: Array = []
		if wave.has("pool"):
			composition = _roll_pool_wave(wave, rng)
			if composition.is_empty():
				return []
		else:
			var raw_monsters: Variant = wave.get("monsters", [])
			if not (raw_monsters is Array) or (raw_monsters as Array).is_empty():
				return []
			for monster_value in (raw_monsters as Array):
				if not (monster_value is Dictionary):
					return []
				var monster := monster_value as Dictionary
				var type_id := str(monster.get("type", ""))
				var count := int(monster.get("count", 0))
				if not is_authorable_enemy_type(type_id) or count <= 0:
					return []
				composition.append({ "type": type_id, "count": count })
		var batch: Array[Dictionary] = []
		for entry_value in composition:
			var entry := entry_value as Dictionary
			var entry_type := str(entry.get("type", ""))
			for _index in range(int(entry.get("count", 0))):
				batch.append(_generate_basic_enemy(entry_type, floor, floor_level))
		if batch.is_empty():
			return []
		waves.append(batch)
	return waves


## 「半钉死」波次：从 `pool` 里**无重复**抽 `kinds` 种怪，总数量落在 `count` 区间内。
## 波次数由 `waves` 数组长度**钉死**；种类与数量每局按 rng 抽（同 rng 恒定）。
## 返回 `Array[{type, count}]`；输入非法返回空数组（调用方按契约整份丢弃）。
##
## 分配口径：总数量尽量**均分**给抽中的种类，余数给靠前的种类（每种至少 1 只）。
## `count.min` 若不小于抽中的种类数，均分必然成立；校验器另在静态层要求
## `count.min >= kinds.max`，本处的 `maxi` 只是运行时的最后一道兜底。
func _roll_pool_wave(wave: Dictionary, rng: RandomNumberGenerator) -> Array:
	var raw_pool: Variant = wave.get("pool", [])
	if not (raw_pool is Array) or (raw_pool as Array).is_empty():
		return []
	var pool: Array[String] = []
	for type_value in (raw_pool as Array):
		var type_id := str(type_value)
		if not is_authorable_enemy_type(type_id):
			return []
		pool.append(type_id)
	var kinds_min := pool.size()
	var kinds_max := pool.size()
	var raw_kinds: Variant = wave.get("kinds", {})
	if raw_kinds is Dictionary:
		kinds_min = int((raw_kinds as Dictionary).get("min", pool.size()))
		kinds_max = int((raw_kinds as Dictionary).get("max", pool.size()))
	kinds_min = clampi(kinds_min, 1, pool.size())
	kinds_max = clampi(kinds_max, kinds_min, pool.size())
	var raw_count: Variant = wave.get("count", null)
	if not (raw_count is Dictionary):
		return []
	var count_data := raw_count as Dictionary
	var count_min := int(count_data.get("min", 0))
	var count_max := int(count_data.get("max", 0))
	if count_min <= 0 or count_max < count_min:
		return []
	# 抽种类：先洗牌 pool，再取前 kind_count 个（等价于无重复抽样）。
	var shuffled := pool.duplicate() as Array[String]
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = held
	var kind_count := rng.randi_range(kinds_min, kinds_max)
	var total := maxi(rng.randi_range(count_min, count_max), kind_count)
	var base := int(total / kind_count)
	var remainder := total % kind_count
	var out: Array = []
	for index in range(kind_count):
		out.append({
			"type": shuffled[index],
			"count": base + (1 if index < remainder else 0),
		})
	return out


## 该怪物种类能否由设计源直接指定。Boss 不在内：Boss 房有自己的出场/结算路径，
## 走本通道会以普通外壳出场，绕过 Boss 逻辑，故设计源禁用。
## static：校验器需要在不构造实例的前提下复用同一判据（单一实现，禁止复刻）。
static func is_authorable_enemy_type(type_id: String) -> bool:
	return BASE_ENEMY_TYPES.has(type_id) and type_id != "boss"


## 生成随机敌人
func _generate_random_enemies(floor: int, floor_level: int) -> Array[Dictionary]:	# 怪物数量随楼层增加：每房 baseline 3-5 只（floor=1 -> 3, floor=2 -> 4, floor=4 -> 6）
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

## 生成Boss敌人。
## 返回 **空字典 = 本房不出 Boss**（名册里没有可用内容，或设计源写了不存在的 ID）。
## 调用方（`generate_enemies` 的 "boss" 分支 / `Dungeon3D._spawn_room_enemies`）
## 必须把空字典当作「合法空房」处理，不得当成生成失败。
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
	# Boss 身份的唯一解析口径见 BossContentCatalog.resolve_profile：
	# 设计源指定的 boss_content_id 优先，其次按层指派（95/90/85）。
	# 名册条目同时决定目标名、正式模型、竞技场与阶段技能袋 —— 设计源只负责「指定哪一个」。
	var floor_number := int(request.get("floor_number", 95))
	var boss_profile := BossContentCatalog.resolve_profile(
		str(request.get("boss_content_id", "")), floor_number
	)
	if boss_profile.is_empty():
		return {}
	result["floor_number"] = int(boss_profile.get("floor_number", floor_number))
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
	return get_loot_table_for_level(floor_level)


## 楼层深度 → 掉落池。唯一口径：`drop_spec_for` 与旧 `loot_table` 字段共用本函数，
## 不得在别处再写一份 match（那会让两处选池悄悄漂移）。
static func get_loot_table_for_level(floor_level: int) -> String:
	match floor_level:
		RoomData.FloorLevel.SHALLOW: return "loot_floor_1_2"
		RoomData.FloorLevel.MEDIUM: return "loot_floor_3_4"
		RoomData.FloorLevel.DEEP: return "loot_floor_5"
		RoomData.FloorLevel.ABYSS: return "loot_abyss"
	return "loot_common"


# ---------------------------------------------------------------------------
# 怪物表「掉落/进度」列的结构化投影（2026-09-22，REWARD-SERVICE 契约）
# ---------------------------------------------------------------------------
#
# 现状口径：该列在物品/怪物表里仍是自然语言，运行时散在 LootModule 的 26% / 34% / 魂公式里。
# 本段把它**逐值**投影成结构化规格（RewardSpec），供 RewardService 解析。
# **过渡期双写**：旧 `loot_table` 字段与旧 LootModule 分支保留不动（04 §22.11 第 2 步），
# 第 3 步切消费点、第 4 步删旧路径。数值逐值保持，不得在切换过程中改动。

## 普通怪：出 1 件非货币物品的概率。
const DROP_ITEM_CHANCE_NORMAL := 0.26
## 普通怪：备弹概率与数量区间。
const DROP_AMMO_CHANCE_NORMAL := 0.34
const DROP_AMMO_MIN_NORMAL := 3
const DROP_AMMO_MAX_NORMAL := 8
## 精英 / Boss：稳定单件 + 满额备弹。
const DROP_AMMO_MIN_ELITE := 8
const DROP_AMMO_MAX_ELITE := 16
## 魂产量：`round(base + per_floor × floor)`。精英/Boss 的附加魂在现有实现里是**总额**
## （Dungeon3D 见到已有货币就不再补基础魂），故此处直接给总额，不叠加。
const DROP_CURRENCY_BASE_NORMAL := 2
const DROP_CURRENCY_PER_FLOOR_NORMAL := 1
const DROP_CURRENCY_BASE_ELITE := 50
const DROP_CURRENCY_BASE_BOSS := 200
const DROP_CURRENCY_PER_FLOOR_ELITE_BOSS := 20

## 备弹物品 ID。与旧 LootModule 分支使用同一个物品，不得改成第二个 ID。
const DROP_AMMO_ITEM_ID := "item_ammo_pack"

const TIER_NORMAL := "normal"
const TIER_ELITE := "elite"
const TIER_BOSS := "boss"


## 取某只怪在当前档位/层深下的结构化掉落规格（等价于怪物表该行的 `drop` 列）。
##
## 返回一份完整的 RewardSpec，可直接交给 `RewardService.resolve()`。
## `tier` 取 normal / elite / boss；`boss` 时按 `floor` 取 `boss_floor_%d` 池名
## （该名若未登记，RewardService 会**拒绝并报 UNKNOWN_POOL**，不静默返回空）。
static func drop_spec_for(
	monster_id: String, tier: String = TIER_NORMAL, floor_level: int = 0, floor: int = 1
) -> Dictionary:
	if not BASE_ENEMY_TYPES.has(monster_id):
		return {}
	var safe_floor := maxi(1, floor)
	var resolved_tier := tier
	if monster_id == "boss":
		resolved_tier = TIER_BOSS

	var pool_id := ""
	var item_chance := 0.0
	var ammo_chance := 0.0
	var ammo_min := 0
	var ammo_max := 0
	var currency_base := 0
	var currency_per_floor := 0

	match resolved_tier:
		TIER_BOSS:
			pool_id = "boss_floor_%d" % [safe_floor]
			item_chance = 1.0
			ammo_chance = 1.0
			ammo_min = DROP_AMMO_MIN_ELITE
			ammo_max = DROP_AMMO_MAX_ELITE
			currency_base = DROP_CURRENCY_BASE_BOSS
			currency_per_floor = DROP_CURRENCY_PER_FLOOR_ELITE_BOSS
		TIER_ELITE:
			pool_id = "elite_floor_1" if safe_floor <= 2 else "elite_floor_2"
			item_chance = 1.0
			ammo_chance = 1.0
			ammo_min = DROP_AMMO_MIN_ELITE
			ammo_max = DROP_AMMO_MAX_ELITE
			currency_base = DROP_CURRENCY_BASE_ELITE
			currency_per_floor = DROP_CURRENCY_PER_FLOOR_ELITE_BOSS
		_:
			pool_id = get_loot_table_for_level(floor_level)
			item_chance = DROP_ITEM_CHANCE_NORMAL
			ammo_chance = DROP_AMMO_CHANCE_NORMAL
			ammo_min = DROP_AMMO_MIN_NORMAL
			ammo_max = DROP_AMMO_MAX_NORMAL
			currency_base = DROP_CURRENCY_BASE_NORMAL
			currency_per_floor = DROP_CURRENCY_PER_FLOOR_NORMAL

	var entries: Array = []
	if item_chance > 0.0:
		entries.append({
			"kind": "pool", "pool_id": pool_id, "draws": 1, "chance": item_chance,
		})
	if ammo_chance > 0.0:
		entries.append({
			"kind": "item", "item_id": DROP_AMMO_ITEM_ID,
			"count": { "min": ammo_min, "max": ammo_max },
			"chance": ammo_chance,
			# 旧行为：池已抽出同一物品时，以整包数量**覆盖**该件，而不是多出一件。
			"merge_same_item": true,
		})
	entries.append({
		"kind": "currency", "currency_id": "extraction_points",
		"amount": { "base": currency_base, "per_floor": currency_per_floor },
	})

	return {
		"spec_id": "monster:%s:%s:%d" % [monster_id, resolved_tier, safe_floor],
		"entries": entries,
	}


## 人类可读的掉落列文本（等价于旧自然语言，仅供工具/文档展示，不参与运行时判定）。
static func describe_drop_spec(monster_id: String, tier: String = TIER_NORMAL, floor_level: int = 0, floor: int = 1) -> String:
	var spec := drop_spec_for(monster_id, tier, floor_level, floor)
	if spec.is_empty():
		return ""
	var parts: Array[String] = []
	for entry in spec.get("entries", []):
		var e: Dictionary = entry
		match str(e.get("kind", "")):
			"pool":
				parts.append("loot_pool=%s; item_chance=%.2f" % [str(e.get("pool_id", "")), float(e.get("chance", 1.0))])
			"item":
				var rng: Dictionary = e.get("count", {})
				parts.append("ammo=%.2f:%d-%d" % [
					float(e.get("chance", 1.0)), int(rng.get("min", 0)), int(rng.get("max", 0)),
				])
			"currency":
				var amount: Dictionary = e.get("amount", {})
				parts.append("currency=base:%d+per_floor:%d" % [
					int(amount.get("base", 0)), int(amount.get("per_floor", 0)),
				])
	return "%s; tier=%s" % ["; ".join(parts), tier]

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
