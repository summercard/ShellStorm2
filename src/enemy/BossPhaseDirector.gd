extends Node
## Boss 阶段管理器
## 负责 Boss 阶段切换、触发技能、检测弱点
## 与具体技能解耦，通过配置驱动

signal phase_started(boss_id: String, phase: int)
signal phase_ended(boss_id: String, phase: int)
signal skill_triggered(boss_id: String, skill_id: String, phase: int)
signal boss_weakness_exposed(boss_id: String, weakness_type: String)

var boss_id: String = ""
var current_phase: int = 1
var max_phase: int = 3

var _skill_trees: Dictionary = {}  # phase -> [skill_config]
var _active_skills: Array[String] = []
var _cooldowns: Dictionary = {}
var _hp_thresholds: Array[float] = [0.66, 0.33, 0.0]

func _init(b_id: String = ""):
	boss_id = b_id

func configure(max_phases: int, skill_trees: Dictionary) -> void:
	"""配置 Boss 阶段和技能树
	
	skill_trees: {
		1: [{id, cooldown, trigger="time|hp|event", threshold}],
		2: [...],
		3: [...]
	}
	"""
	max_phase = max_phases
	_skill_trees = skill_trees

func set_phase(new_phase: int) -> void:
	if new_phase == current_phase:
		return
	phase_ended.emit(boss_id, current_phase)
	current_phase = new_phase
	_active_skills.clear()
	phase_started.emit(boss_id, new_phase)

func check_hp_threshold(hp_percent: float) -> void:
	"""检查血量阈值并触发阶段切换"""
	var target_phase = _get_phase_for_hp(hp_percent)
	if target_phase != current_phase and target_phase <= max_phase:
		set_phase(target_phase)

func _get_phase_for_hp(hp_percent: float) -> int:
	if hp_percent <= 0.33:
		return max_phase
	elif hp_percent <= 0.66:
		return 2 if max_phase >= 2 else max_phase
	return 1

func trigger_skill(skill_id: String) -> void:
	"""触发指定的技能"""
	if is_on_cooldown(skill_id):
		return
	_skill_trees.get(current_phase, []).filter(func(s): return s.get("id") == skill_id)
	skill_triggered.emit(boss_id, skill_id, current_phase)
	_set_cooldown(skill_id, _get_skill_cooldown(skill_id))

func _get_skill_cooldown(skill_id: String) -> float:
	for skills in _skill_trees.values():
		for s in skills:
			if s.get("id") == skill_id:
				return s.get("cooldown", 5.0)
	return 5.0

func _set_cooldown(skill_id: String, duration: float) -> void:
	_cooldowns[skill_id] = duration

func is_on_cooldown(skill_id: String) -> bool:
	return _cooldowns.get(skill_id, 0.0) > 0

func tick(delta: float) -> void:
	"""每帧更新冷却时间"""
	var to_clear: Array[String] = []
	for skill_id in _cooldowns:
		_cooldowns[skill_id] -= delta
		if _cooldowns[skill_id] <= 0:
			to_clear.append(skill_id)
	for skill_id in to_clear:
		_cooldowns.erase(skill_id)

func get_skills_for_phase(phase: int) -> Array[Dictionary]:
	return _skill_trees.get(phase, [])

func get_active_skill_ids() -> Array[String]:
	return _active_skills.duplicate()


## 弱点检测
func check_player_weapon_weakness(weapon_assembly: Dictionary) -> String:
	"""检测玩家武器装配树的弱点类型
	
	Returns: "fire"|"electric"|"toxic"|"physical"|"none"
	"""
	# 分析装配树中的组件类型
	var has_electric: bool = false
	var has_fire: bool = false
	var has_toxic: bool = false
	
	# 扫描子弹类型
	var bullets = weapon_assembly.get("bullet", {})
	if bullets.get("element") == "electric":
		has_electric = true
	elif bullets.get("element") == "fire":
		has_fire = true
	elif bullets.get("element") == "toxic":
		has_toxic = true
	
	if has_electric:
		return "electric"
	elif has_fire:
		return "fire"
	elif has_toxic:
		return "toxic"
	return "physical"


func exploit_weakness(weakness_type: String) -> void:
	"""根据弱点类型触发反制"""
	boss_weakness_exposed.emit(boss_id, weakness_type)