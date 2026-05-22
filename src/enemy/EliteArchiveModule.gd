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
		name = base_name if base_name else "未知精英"
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

	func equip_module(module_data: Dictionary) -> void:
		stolen_modules.append(module_data)
		# 根据装备模块添加修饰词缀
		match module_data.get("module_type"):
			"GunBody":
				add_modifier("Elite.WeaponParasite")
			"FateCard":
				add_modifier("Elite.FateResidue")


func _ready() -> void:
	_load_archive()


func create_elite(base_enemy_id: String, name: String = "", biome: String = "") -> EliteRecord:
	"""创建新的精英怪记录"""
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