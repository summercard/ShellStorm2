extends Node
## 精英怪档案模块
## 负责精英怪的全生命周期记录、状态变迁、属性存档
## 跨局持久化：玩家死亡/撤离后，精英怪按成长规则继续存在于档案池

signal elite_state_changed(elite_id: String, old_state: String, new_state: String)
signal elite_spawned(elite_id: String)
signal elite_killed(elite_id: String)

const SAVE_PATH = "user://elite_archive.dat"

var archive: Dictionary = {}  # {elite_id: EliteRecord}
var _next_id: int = 0

class EliteRecord:
	var elite_id: String
	var base_enemy_id: String
	var name: String
	var level: int
	var state: String  # Newborn/Escaped/Equipped/Growing/RevengeHunter/RegionalBoss/QuasiBoss/Killed
	var history: Dictionary  # escaped_count, killed_player_count, last_seen_biome, last_encounter_result
	var growth_stats: Dictionary  # hp_multiplier, damage_multiplier, move_speed_multiplier
	var modifiers: Array[String]
	var stolen_modules: Array[Dictionary]  # [{module_id, module_type, converted_skill}]
	var fate_residues: Array[String]
	var spawn_weight: float
	var bounty_reward_level: int

	func _init(base_id: String, base_name: String = ""):
		elite_id = "elite_%06d" % 0
		base_enemy_id = base_id
		# 如果没有传入名字，自动生成
		name = base_name if not base_name.is_empty() else "未知精英"
		level = 1
		state = "Newborn"
		history = {
			"escaped_count": 0,
			"killed_player_count": 0,
			"last_seen_biome": "",
			"last_encounter_result": ""
		}
		growth_stats = {
			"hp_multiplier": 1.0,
			"damage_multiplier": 1.0,
			"move_speed_multiplier": 1.0
		}
		modifiers = []
		stolen_modules = []
		fate_residues = []
		spawn_weight = 0.1
		bounty_reward_level = 0

	const TITLE_TEMPLATES: Array[String] = [
		"背枪的%base%",
		"吞弹者·%base%",
		"抢走机枪的%base%",
		"三次逃脱的%base%幼体",
		"%base%仇敌",
		"狡猾的%base%",
		"不死的%base%",
		"带毒的%base%",
		"焦黑的%base%",
		"冰壳的%base%"
	]

	static func generate_elite_name(base_enemy_id: String, modifiers: Array[String], stolen_modules: Array[Dictionary]) -> String:
		"""根据精英怪的成长经历生成半随机名字
		
		名字格式：称号 + 怪物基础名 + 后缀
		示例：背枪的孢子射手、吞弹者·毒囊花、抢走机枪的蜂巢怪
		"""
		# 基础怪物名映射
		var base_names: Dictionary = {
			"melee_chaser": "裂口爬虫",
			"ranged_caster": "孢子射手",
			"summoner": "蜂巢怪",
			"shielded": "壳甲卫兵",
			"exploder": "炸弹果",
			"ambusher": "地刺虫",
			"boss": "弹壳巨兽"
		}
		var base_name: String = base_names.get(base_enemy_id, "小菌猪")

		# 按优先级构建称号关键词列表
		var title_parts: Array[String] = []

		# 装备类称号（最高优先级，决定性特征）
		for m in stolen_modules:
			if m is Dictionary:
				match m.get("module_type", ""):
					"GunBody":
						title_parts.append("背枪的")
					"Bullet":
						title_parts.append("吞弹的")
					"Attachment":
						title_parts.append("挂载的")
					"FateCard":
						title_parts.append("命运的")

		# 词缀类称号（成长经历）
		for mod in modifiers:
			match mod:
				"Elite.WeaponParasite":
					title_parts.append("枪械寄生的")
				"Elite.Huge":
					title_parts.append("巨型的")
				"Elite.SpawnOnDeath":
					title_parts.append("分裂的")
				"Elite.Ricochet":
					title_parts.append("弹跳的")
				"Elite.Parasite":
					title_parts.append("寄生的")
				"Elite.GunFeed":
					title_parts.append("喂枪的")
				"Elite.Shielded":
					title_parts.append("护盾的")
				"Elite.PoisonResist":
					title_parts.append("抗毒的")
				"Elite.FireResist":
					title_parts.append("耐火的")
				"Elite.IceResist":
					title_parts.append("抗寒的")
				"Elite.FateResidue":
					title_parts.append("残魂的")

		# 如果没有任何特征，用随机称号池
		if title_parts.is_empty():
			var rng := RandomNumberGenerator.new()
			rng.seed = Time.get_ticks_msec()
			var template: String = TITLE_TEMPLATES[rng.randi() % TITLE_TEMPLATES.size()]
			return template.replace("%base%", base_name)

		# 取第一个有意义的称号（最重要的特征）
		var title: String = title_parts[0]
		# 去掉末尾的"的"方便连接，或保留"XX的"格式
		if title.ends_with("的"):
			return title + base_name
		else:
			return title + base_name

	func to_dict() -> Dictionary:
		return {
			"elite_id": elite_id,
			"base_enemy_id": base_enemy_id,
			"name": name,
			"level": level,
			"state": state,
			"history": history,
			"growth_stats": growth_stats,
			"modifiers": modifiers,
			"stolen_modules": stolen_modules,
			"fate_residues": fate_residues,
			"spawn_weight": spawn_weight,
			"bounty_reward_level": bounty_reward_level
		}

	static func from_dict(d: Dictionary) -> EliteRecord:
		var r = EliteRecord.new(d.get("base_enemy_id", ""))
		r.elite_id = d.get("elite_id", "")
		r.name = d.get("name", "")
		r.level = d.get("level", 1)
		r.state = d.get("state", "Newborn")
		r.history = d.get("history", {})
		r.growth_stats = d.get("growth_stats", {})
		r.modifiers = Array(d.get("modifiers", []), TYPE_STRING, "", null)
		r.stolen_modules = d.get("stolen_modules", [])
		r.fate_residues = Array(d.get("fate_residues", []), TYPE_STRING, "", null)
		r.spawn_weight = d.get("spawn_weight", 0.1)
		r.bounty_reward_level = d.get("bounty_reward_level", 0)
		return r

	func apply_growth(growth_data: Dictionary) -> void:
		"""根据战斗结果应用成长"""
		if growth_data.get("hp_gain"):
			growth_stats["hp_multiplier"] += growth_data["hp_gain"]
		if growth_data.get("damage_gain"):
			growth_stats["damage_multiplier"] += growth_data["damage_gain"]
		if growth_data.get("speed_gain"):
			growth_stats["move_speed_multiplier"] += growth_data["speed_gain"]
		level += growth_data.get("level_up", 0)
		_synchronize_state()

	func _synchronize_state() -> void:
		"""根据属性同步状态"""
		if history.get("escaped_count", 0) >= 3 and state != "RegionalBoss":
			state = "RegionalBoss"
		elif history.get("killed_player_count", 0) > 0 and state != "RevengeHunter":
			state = "RevengeHunter"
		elif level >= 10 and state != "QuasiBoss":
			state = "QuasiBoss"

	func add_modifier(mod: String) -> void:
		if mod not in modifiers:
			modifiers.append(mod)
			# 当精英获得新词缀时，更新名字以反映最新成长状态
			name = generate_elite_name(base_enemy_id, modifiers, stolen_modules)

	func equip_module(module_data: Dictionary) -> void:
		stolen_modules.append(module_data)
		# 根据装备模块添加修饰词缀
		match module_data.get("module_type"):
			"GunBody":
				add_modifier("Elite.WeaponParasite")
			"FateCard":
				add_modifier("Elite.FateResidue")
		# 当精英获得新装备/词缀时，更新名字以反映最新成长状态
		name = generate_elite_name(base_enemy_id, modifiers, stolen_modules)


func _ready() -> void:
	_load_archive()


func create_elite(base_enemy_id: String, name: String = "", biome: String = "") -> EliteRecord:
	"""创建新的精英怪记录"""
	# 如果没有传入名字，自动生成半随机名字
	if name.is_empty():
		name = EliteRecord.generate_elite_name(base_enemy_id, [], [])
	var elite = EliteRecord.new(base_enemy_id, name)
	elite.elite_id = "elite_%06d" % _get_next_id()
	if biome:
		elite.history["last_seen_biome"] = biome
	archive[elite.elite_id] = elite
	elites_changed()
	return elite


func _get_next_id() -> int:
	_next_id += 1
	return _next_id


func get_elite(elite_id: String) -> EliteRecord:
	return archive.get(elite_id)


func get_all_elites() -> Array[EliteRecord]:
	return archive.values()


func get_elites_by_state(target_state: String) -> Array[EliteRecord]:
	var result: Array[EliteRecord] = []
	for elite in archive.values():
		if elite.state == target_state:
			result.append(elite)
	return result


func get_spawnable_elites() -> Array[EliteRecord]:
	"""获取可以生成的精英怪列表（排除已击杀的）"""
	var result: Array[EliteRecord] = []
	for elite in archive.values():
		if elite.state != "Killed":
			result.append(elite)
	return result


func on_encounter_result(elite_id: String, result: String, growth_data: Dictionary) -> void:
	"""记录精英怪遭遇结果并应用成长
	
	result: PlayerKilled / PlayerEscaped / PlayerDied / PlayerExtracted
	"""
	var elite = get_elite(elite_id)
	if not elite:
		return

	var old_state = elite.state
	elite.history["last_encounter_result"] = result

	match result:
		"PlayerEscaped", "PlayerExtracted":
			elite.history["escaped_count"] += 1
			growth_data["hp_gain"] = growth_data.get("hp_gain", 0.0) + 0.1
			growth_data["speed_gain"] = growth_data.get("speed_gain", 0.0) + 0.05
		"PlayerDied":
			elite.history["killed_player_count"] += 1
			growth_data["damage_gain"] = growth_data.get("damage_gain", 0.0) + 0.2
			growth_data["hp_gain"] = growth_data.get("hp_gain", 0.0) + 0.15
		"PlayerKilled":
			# 被玩家击杀，降级或移除
			elite.state = "Killed"
			elites_changed()
			elite_killed.emit(elite_id)
			return

	elite.apply_growth(growth_data)
	elites_changed()
	elite_state_changed.emit(elite_id, old_state, elite.state)


func kill_elite(elite_id: String) -> void:
	var elite = get_elite(elite_id)
	if elite:
		elite.state = "Killed"
		elites_changed()
		elite_killed.emit(elite_id)


func get_total_count() -> int:
	return archive.size()


func get_active_count() -> int:
	return get_spawnable_elites().size()


func _load_archive() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		archive.clear()
		var records = data.get("elites", [])
		for d in records:
			var rec = EliteRecord.from_dict(d)
			archive[rec.elite_id] = rec
		_next_id = data.get("next_id", 0)


func save_archive() -> void:
	var records = []
	for elite in archive.values():
		records.append(elite.to_dict())
	var data = {
		"elites": records,
		"next_id": _next_id
	}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _exit_tree() -> void:
	save_archive()


func elites_changed() -> void:
	# 触发保存（debounce 由调用方控制）
	pass