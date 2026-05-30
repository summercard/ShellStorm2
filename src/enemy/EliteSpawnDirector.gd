extends Node
## 精英怪出现调度器
## 职责：根据楼层风险权重，从 EliteArchiveModule 抽样并生成可执行精英数据
## 由 RoomGameMode 在房间生成时调用，决定本局是否/哪个精英出现在波次中

## 信号
signal elite_spawn_decided(elite_id: String, spawn_data: Dictionary)
signal no_elite_available

const ARCHIVE_MODULE_PATH := "res://src/enemy/EliteArchiveModule.gd"

var _elite_archive: Node = null
var _rng: RandomNumberGenerator = null
var _pending_elite_id: String = ""  # 已选中但尚未注入波次的精英 ID（用于 has_pending_elite 预查询）

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()

## 查询是否已有选中但尚未注入的精英（供 RoomGameMode 波次分配预判）
func has_pending_elite() -> bool:
	return not _pending_elite_id.is_empty()

## 尝试从档案池抽取一个可出现的精英
## floor: 当前楼层（影响出现概率和生成强度）
## risk_level: 当前局风险等级（影响 elite 出现概率）
## spawn_position_hint: Vector2（可选，用于计算出现位置描述）
## return: EliteRecord 或 null
func try_select_elite(floor: int, risk_level: int = 0) -> Dictionary:
	_elite_archive = _find_elite_archive()
	if _elite_archive == null or not _elite_archive.has_method("get_spawnable_elites"):
		return {}

	var spawnables: Array = _elite_archive.call("get_spawnable_elites")
	if spawnables.is_empty():
		return {}

	# 根据楼层和风险决定是否出现精英（高风险局更高概率）
	var elite_chance := minf(1.0, 0.10 + float(floor) * 0.05 + float(risk_level) * 0.08)
	if _rng.randf() > elite_chance:
		return {}

	# 按 spawn_weight 加权随机抽样
	var total_weight := 0.0
	var weighted: Array[Dictionary] = []
	for record in spawnables:
		var rec: Dictionary = record if record is Dictionary else {}
		var weight: float = float(rec.get("spawn_weight", 0.1))
		total_weight += weight
		weighted.append({"record": record, "weight": weight, "cum": total_weight})

	var roll: float = _rng.randf() * total_weight
	for entry in weighted:
		if roll <= entry["cum"]:
			var selected: Variant = entry["record"]
			var result: Dictionary
			if selected is Dictionary:
				result = _build_elite_spawn_data(selected, floor)
			else:
				result = _build_elite_spawn_data_from_record(selected, floor)
			_pending_elite_id = result.get("elite_id", "")
			return result

	return {}


## 从 EliteRecord（对象）构建可执行生成数据
func _build_elite_spawn_data_from_record(record: Object, floor: int) -> Dictionary:
	if not record.has_method("to_dict"):
		return {}
	var d: Dictionary = record.call("to_dict")
	return _build_elite_spawn_data(d, floor)


## 从 archive dict 构建可用于 RoomWaveSpawner 的完整 enemy data
func _build_elite_spawn_data(archive_dict: Dictionary, floor: int) -> Dictionary:
	var base_enemy_id: String = archive_dict.get("base_enemy_id", "melee_chaser")
	var level: int = int(archive_dict.get("level", 1))
	var growth: Dictionary = archive_dict.get("growth_stats", {})
	var history: Dictionary = archive_dict.get("history", {})

	# hp/damage multiplier → 应用到怪物基础数值
	var hp_mult: float = float(growth.get("hp_multiplier", 1.0))
	var damage_mult: float = float(growth.get("damage_multiplier", 1.0))
	var speed_mult: float = float(growth.get("move_speed_multiplier", 1.0))

	# 基础数值（从 MonsterInjector 读取基准）
	var base_stats: Dictionary = _get_base_stats_for_enemy(base_enemy_id)

	# 楼层缩放（独立于 growth_stats 的地图难度）
	var floor_scale: Dictionary = MonsterInjector.FLOOR_SCALING.get(floor, MonsterInjector.FLOOR_SCALING.get(1, {}))

	# 最终生成数据
	var spawn_data: Dictionary = {
		"enemy_type": base_enemy_id,
		"is_elite": true,
		"elite_id": archive_dict.get("elite_id", ""),
		"name": archive_dict.get("name", "未知精英"),
		"max_hp": int(float(base_stats.get("hp_base", 25)) * hp_mult * float(floor_scale.get("hp_mult", 1.0))),
		# Damage: 基准 × 成长 × 楼层
		"damage": int(float(base_stats.get("damage_base", 5)) * damage_mult * float(floor_scale.get("damage_mult", 1.0))),
		# Speed: 基准 × 速度成长
		"speed": float(base_stats.get("speed", 80.0)) * speed_mult,
		# 货币（精英更高）
		"currency_value": int(archive_dict.get("bounty_reward_level", 1) * 15 + 10),
		# 外观
		"emoji": base_stats.get("emoji", "👹"),
		"color": base_stats.get("color", Color(1.0, 0.2, 0.1, 1.0)),
		"scale": 1.0 + (level - 1) * 0.08,  # 每级 +8% 体型
		# 词缀（从 archive modifiers 映射）
		"modifier": _select_modifier_from_archive(archive_dict, level),
		# modifier_id_en: 英文词缀ID，供 EliteActiveSkillComponent.inject_elite_skills() 路由精英专属主动技能
		"modifier_id_en": _select_modifier_id_en_from_archive(archive_dict, level),
		# tier: 1-3，从 level 换算（level 1-2→tier1，3-4→tier2，5+→tier3）
		"tier": mini(3, (level - 1) / 2 + 1),
		# AI（根据基础类型决定）
		"ai_type": base_stats.get("ai_type", "chase"),
		# 特殊标记（复仇者/区域霸主有额外行为）
		"elite_state": archive_dict.get("state", "Newborn"),
		# 挂载装备（用于视觉渲染）
		"stolen_modules": archive_dict.get("stolen_modules", []),
	}

	# 复仇者标记：更积极追人
	if archive_dict.get("state") == "RevengeHunter":
		spawn_data["ai_aggression"] = 1.5

	elite_spawn_decided.emit(archive_dict.get("elite_id", ""), spawn_data)
	return spawn_data


## 从基础怪物 ID 获取基准数值（Mirror MonsterInjector 逻辑）
func _get_base_stats_for_enemy(enemy_type: String) -> Dictionary:
	var injector: Node = Node.new()
	# 不实例化完整 injector，直接用常量
	var types: Dictionary = {
		"melee_chaser": {"hp_base": 25, "damage_base": 5, "speed": 80.0, "emoji": "🐗", "color": Color(0.95, 0.28, 0.24, 1.0), "ai_type": "chase"},
		"ranged_caster": {"hp_base": 15, "damage_base": 8, "speed": 50.0, "emoji": "🍄", "color": Color(0.62, 0.35, 1.0, 1.0), "ai_type": "ranged"},
		"summoner": {"hp_base": 30, "damage_base": 0, "speed": 40.0, "emoji": "🐝", "color": Color(0.95, 0.70, 0.16, 1.0), "ai_type": "summoner"},
		"shielded": {"hp_base": 40, "damage_base": 3, "speed": 30.0, "emoji": "🛡", "color": Color(0.35, 0.62, 0.95, 1.0), "ai_type": "chase"},
		"exploder": {"hp_base": 10, "damage_base": 15, "speed": 70.0, "emoji": "💣", "color": Color(1.0, 0.58, 0.14, 1.0), "ai_type": "bomber"},
		"ambusher": {"hp_base": 18, "damage_base": 7, "speed": 90.0, "emoji": "🦂", "color": Color(0.78, 0.28, 0.88, 1.0), "ai_type": "trapper"},
		"boss": {"hp_base": 120, "damage_base": 18, "speed": 60.0, "emoji": "👹", "color": Color(1.0, 0.12, 0.08, 1.0), "ai_type": "chase"},
	}
	injector.free()
	return types.get(enemy_type, types["melee_chaser"])


## 从 archive modifiers 中选择要应用的词缀
func _select_modifier_from_archive(archive_dict: Dictionary, level: int) -> String:
	var modifiers: Array = archive_dict.get("modifiers", [])
	if modifiers.is_empty():
		# 根据等级自动生成默认词缀
		var default_mods: Array[String] = []
		if level >= 2:
			default_mods.append("巨大化")
		if level >= 4:
			default_mods.append("分裂")
		if level >= 6:
			default_mods.append("反弹")
		if default_mods.is_empty():
			return ""
		return default_mods[0]
	return modifiers[0]


## 英文词缀ID映射（Mirror MonsterInjector._map_modifier_to_english）
static func _map_modifier_to_english(cn_id: String) -> String:
	match cn_id:
		"巨大化": return "Elite.Huge"
		"分裂": return "Elite.SpawnOnDeath"
		"反弹": return "Elite.Ricochet"
		"寄生": return "Elite.Parasite"
		"抢枪": return "Elite.WeaponParasite"
		"吞弹": return "Elite.BulletEater"
	return "Elite.Huge"


## 从 archive modifiers 中选择英文词缀ID（供精英专属主动技能注入）
func _select_modifier_id_en_from_archive(archive_dict: Dictionary, level: int) -> String:
	var modifiers: Array = archive_dict.get("modifiers", [])
	var cn_modifier: String = ""
	if modifiers.is_empty():
		# 与 _select_modifier_from_archive 保持一致的默认生成逻辑
		if level >= 6:
			cn_modifier = "反弹"
		elif level >= 4:
			cn_modifier = "分裂"
		elif level >= 2:
			cn_modifier = "巨大化"
		else:
			cn_modifier = "巨大化"
	else:
		cn_modifier = str(modifiers[0])
	return _map_modifier_to_english(cn_modifier)


## 找到场景中的 EliteArchiveModule（通过分组或父节点向上查找）
func _find_elite_archive() -> Node:
	# 优先从分组找
	var groups: Array = get_tree().get_nodes_in_group("elite_archive")
	if not groups.is_empty():
		return groups[0]

	# 从父节点链向上找
	var parent: Node = get_parent()
	while parent:
		if parent.has_method("get_spawnable_elites"):
			return parent
		parent = parent.get_parent()

	# 尝试从场景树找
	var roots: Array = get_tree().root.get_children()
	for r in roots:
		if r.has_method("get_spawnable_elites"):
			return r
		# 搜索子节点
		var found: Node = _search_in_children(r, "get_spawnable_elites")
		if found:
			return found
	return null


func _search_in_children(node: Node, method_name: String) -> Node:
	for ch in node.get_children():
		if ch.has_method(method_name):
			return ch
		var sub: Node = _search_in_children(ch, method_name)
		if sub:
			return sub
	return null
