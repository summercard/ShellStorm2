class_name BossRoomDirector
## Boss房管理 — 管理Boss房的状态、进入条件和击败后的奖励结算

signal boss_spawned(boss_data: Dictionary)
signal boss_damaged(boss_id: String, damage: float, new_hp: float)
signal boss_phase_changed(boss_id: String, new_phase: int)
signal boss_defeated(boss_id: String, rewards: Dictionary)
signal boss_escaped(boss_id: String)
signal boss_reward_claimed(reward_id: String)

var _current_boss: Dictionary = {}
var _boss_rooms: Dictionary = {}  # room_id -> boss_data
var _defeated_bosses: Array[String] = []
var _phase_count: int = 0
var _extraction_director: ExtractionDirector = null  ## 由 MapManager 注入，避免创建局部实例

## 注入 ExtractionDirector 引用（由 MapManager 在初始化时调用）
func set_extraction_director(director: ExtractionDirector) -> void:
	_extraction_director = director

## 注册Boss房
func register_boss_room(room_id: String, boss_id: String, boss_type: String = "standard") -> void:
	var boss_data := {
		"room_id": room_id,
		"boss_id": boss_id,
		"boss_type": boss_type,
		"floor": 1,
		"hp": 0,
		"max_hp": 0,
		"phase": 1,
		"max_phases": 2,
		"is_active": false,
		"is_defeated": false,
		"is_escaped": false,
		"spawned_at": -1,
		"rewards": {}
	}
	_boss_rooms[room_id] = boss_data

## 生成Boss
func spawn_boss(room_id: String, floor: int, config: Dictionary = {}) -> Dictionary:
	if not _boss_rooms.has(room_id):
		register_boss_room(room_id, "boss_%d" % [floor])
	
	var boss_data: Dictionary = _boss_rooms[room_id]
	boss_data["floor"] = floor
	boss_data["is_active"] = true
	boss_data["spawned_at"] = Time.get_ticks_msec()
	
	# 计算Boss属性
	var scaling := _get_boss_scaling(floor)
	boss_data["max_hp"] = int(200.0 * scaling["hp_mult"])
	boss_data["hp"] = boss_data["max_hp"]
	boss_data["damage"] = int(20.0 * scaling["damage_mult"])
	boss_data["max_phases"] = 2 + floor / 3
	boss_data["phase"] = 1
	
	_current_boss = boss_data
	boss_spawned.emit(boss_data)
	
	return boss_data

## 获取Boss属性缩放
func _get_boss_scaling(floor: int) -> Dictionary:
	var config := {
		"hp_mult": 1.0,
		"damage_mult": 1.0,
	}
	
	if floor >= 2:
		config["hp_mult"] = 1.3
		config["damage_mult"] = 1.2
	if floor >= 3:
		config["hp_mult"] = 1.6
		config["damage_mult"] = 1.4
	if floor >= 4:
		config["hp_mult"] = 2.0
		config["damage_mult"] = 1.7
	if floor >= 5:
		config["hp_mult"] = 2.5
		config["damage_mult"] = 2.0
	
	return config

## 对Boss造成伤害
func damage_boss(damage: float) -> Dictionary:
	if _current_boss.size() == 0:
		return {}
	
	_current_boss["hp"] -= damage
	boss_damaged.emit(_current_boss["boss_id"], damage, _current_boss["hp"])
	
	# 检查阶段变化
	var hp_percent: float = _current_boss["hp"] / float(_current_boss["max_hp"])
	var new_phase: int = _calculate_phase(hp_percent)
	
	if new_phase > _current_boss["phase"]:
		_current_boss["phase"] = new_phase
		boss_phase_changed.emit(_current_boss["boss_id"], new_phase)
	
	# 检查死亡
	if _current_boss["hp"] <= 0:
		_current_boss["hp"] = 0
		_defeat_boss()
	
	return _current_boss.duplicate(true)

## 计算当前阶段
func _calculate_phase(hp_percent: float) -> int:
	var max_phases: int = _current_boss.get("max_phases", 2)
	
	if hp_percent <= 0.25:
		return max_phases
	elif hp_percent <= 0.5:
		return int(min(max_phases - 1, 2))
	else:
		return 1

## 击败Boss
func _defeat_boss() -> void:
	var boss_id: String = _current_boss["boss_id"]
	_current_boss["is_defeated"] = true
	
	# 生成奖励
	var rewards: Dictionary = _generate_rewards(_current_boss)
	_current_boss["rewards"] = rewards
	
	boss_defeated.emit(boss_id, rewards)
	_defeated_bosses.append(boss_id)
	
	# 解锁Boss撤离（使用注入的 extraction_director 引用）
	if _extraction_director != null:
		_extraction_director.unlock_boss_extraction()
	elif ExtractionDirector != null:
		# 兜底：直接从 MapManager 获取（适用于 BossRoomDirector 作为 MapManager 子节点）
		var ed = get_node_or_null("/root/Main/MapManager/ExtractionDirector")
		if ed == null:
			ed = get_node_or_null("/root/MapManager/ExtractionDirector")
		if ed != null and ed.has_method("unlock_boss_extraction"):
			ed.unlock_boss_extraction()

## 生成奖励
func _generate_rewards(boss_data: Dictionary) -> Dictionary:
	var floor: int = boss_data["floor"]
	
	return {
		"xp": 200 + floor * 50,
		"credits": 100 * floor,
		"loot_table": "boss_floor_%d" % [floor],
		"fate_card_chance": 0.3 + floor * 0.05,
		"blueprint_chance": 0.2 + floor * 0.03,
		"bounty_level": floor
	}

## Boss逃脱
func on_boss_escaped() -> void:
	if _current_boss.size() > 0:
		_current_boss["is_escaped"] = true
		boss_escaped.emit(_current_boss["boss_id"])

## 领取奖励
func claim_reward(reward_type: String) -> Variant:
	if not _current_boss.has("rewards"):
		return null
	
	var rewards: Dictionary = _current_boss["rewards"]
	var reward: Variant
	
	match reward_type:
		"xp":
			reward = rewards.get("xp", 0)
		"credits":
			reward = rewards.get("credits", 0)
		"fate_card":
			if randf() < rewards.get("fate_card_chance", 0.0):
				reward = true
			else:
				reward = false
		"blueprint":
			if randf() < rewards.get("blueprint_chance", 0.0):
				reward = true
			else:
				reward = false
		_:
			reward = null
	
	if reward != null:
		boss_reward_claimed.emit(reward_type)
	
	return reward

## 获取当前Boss
func get_current_boss() -> Dictionary:
	return _current_boss.duplicate(true)

## 检查Boss是否存活
func is_boss_alive() -> bool:
	return _current_boss.size() > 0 and not _current_boss.get("is_defeated", false)

## 检查Boss是否已击败
func is_boss_defeated() -> bool:
	return _current_boss.get("is_defeated", false)

## 获取Boss血量百分比
func get_boss_hp_percent() -> float:
	if _current_boss.size() == 0 or _current_boss["max_hp"] == 0:
		return 0.0
	return float(_current_boss["hp"]) / float(_current_boss["max_hp"])

## 获取Boss当前阶段
func get_boss_phase() -> int:
	return _current_boss.get("phase", 0)

## 获取击败的Boss数量
func get_defeated_count() -> int:
	return _defeated_bosses.size()

## 清除Boss数据
func clear() -> void:
	_current_boss.clear()
	_boss_rooms.clear()
	_defeated_bosses.clear()

## 调试：打印Boss状态
func debug_status() -> String:
	var lines: Array[String] = ["BossRoomDirector [%d defeated]" % [_defeated_bosses.size()]]
	
	if _current_boss.size() > 0:
		var hp_pct := get_boss_hp_percent() * 100
		var status := "ALIVE" if is_boss_alive() else "DEFEATED"
		lines.append("  Current: %s hp=%d/%d (%.0f%%) phase=%d/%d [%s]" % [
			_current_boss["boss_id"],
			_current_boss["hp"],
			_current_boss["max_hp"],
			hp_pct,
			_current_boss["phase"],
			_current_boss["max_phases"],
			status
		])
	else:
		lines.append("  Current: None")
	
	return "\n".join(lines)