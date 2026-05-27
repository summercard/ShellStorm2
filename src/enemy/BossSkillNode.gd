extends Node
## Boss 技能节点 — 可独立配置的 Boss 技能单元
## 与 BossPhaseDirector 解耦，每个技能自己管理自己的触发和行为

class_name BossSkillNode

signal skill_started(skill_id: String)
signal skill_ended(skill_id: String)
signal skill_damaged(target_pos: Vector2, damage: float)

enum TriggerMode { TIME, HP_THRESHOLD, EVENT, MANUAL }

var skill_id: String = ""
var skill_name: String = ""
var trigger_mode: TriggerMode = TriggerMode.TIME
var trigger_value: float = 5.0  # 时间(秒) 或 HP百分比
var duration: float = 0.0
var cooldown: float = 5.0

var damage: float = 0.0
var target_type: String = "player"  # player | area | self
var area_radius: float = 0.0
var effect_scene: String = ""

var _elapsed: float = 0.0
var _is_active: bool = false
var _owner_boss_id: String = ""

func _init(id: String = "", name: String = "", mode: TriggerMode = TriggerMode.TIME):
	skill_id = id
	skill_name = name
	trigger_mode = mode

func configure(config: Dictionary) -> void:
	"""从配置字典初始化技能
	
	config: {
		id, name, trigger_mode, trigger_value, duration, cooldown,
		damage, target_type, area_radius, effect_scene
	}
	"""
	skill_id = config.get("id", skill_id)
	skill_name = config.get("name", skill_name)
	trigger_mode = config.get("trigger_mode", trigger_mode)
	trigger_value = config.get("trigger_value", trigger_value)
	duration = config.get("duration", duration)
	cooldown = config.get("cooldown", cooldown)
	damage = config.get("damage", damage)
	target_type = config.get("target_type", target_type)
	area_radius = config.get("area_radius", area_radius)
	effect_scene = config.get("effect_scene", effect_scene)

func set_owner_boss(boss_id: String) -> void:
	_owner_boss_id = boss_id

func can_trigger() -> bool:
	return not _is_active

func trigger() -> void:
	"""触发技能"""
	if not can_trigger():
		return
	_is_active = true
	_elapsed = 0.0
	skill_started.emit(skill_id)
	_execute_skill()

func _execute_skill() -> void:
	"""执行技能效果 — 子类重写，或由 factory 静态方法创建的预置技能调用"""
	# 空实现；实际行为由预置技能子类在构造时通过闭包或派生类重写补充
	pass

func tick(delta: float) -> void:
	if not _is_active:
		return
	_elapsed += delta
	if _elapsed >= duration:
		end()

func end() -> void:
	_is_active = false
	_elapsed = 0.0
	skill_ended.emit(skill_id)

func get_progress() -> float:
	if duration <= 0:
		return 0.0
	return clamp(_elapsed / duration, 0.0, 1.0)


## 预制技能工厂

static func create_spawn_minions(minion_type: String, count: int, delay: float) -> BossSkillNode:
	var s = BossSkillNode.new("spawn_minions", "召唤小怪", TriggerMode.MANUAL)
	s.configure({
		"duration": delay * count,
		"cooldown": 15.0,
		"target_type": "self",
		"minion_type": minion_type,
		"minion_count": count,
		"spawn_delay": delay,
	})
	return s

static func create_telegraphed_shot(damage: float, target: String) -> BossSkillNode:
	var s = BossSkillNode.new("telegraphed_shot", "蓄力射击", TriggerMode.MANUAL)
	s.configure({
		"duration": 1.5,
		"cooldown": 4.0,
		"damage": damage,
		"target_type": target
	})
	return s

static func create_aoe_damage(radius: float, dmg: float) -> BossSkillNode:
	var s = BossSkillNode.new("aoe_damage", "范围伤害", TriggerMode.MANUAL)
	s.configure({
		"duration": 0.5,
		"cooldown": 8.0,
		"damage": dmg,
		"area_radius": radius,
		"target_type": "area"
	})
	return s

static func create_debuff_zone(duration: float, effect_type: String) -> BossSkillNode:
	var s = BossSkillNode.new("debuff_zone", "减益区域", TriggerMode.MANUAL)
	s.configure({
		"duration": duration,
		"cooldown": 12.0,
		"target_type": "area",
		"area_radius": 120.0,
		"effect_type": effect_type,
	})
	return s

static func create_weapon_copy(weapon_tree: Dictionary) -> BossSkillNode:
	var s = BossSkillNode.new("weapon_copy", "复制武器", TriggerMode.MANUAL)
	s.configure({
		"duration": 8.0,
		"cooldown": 20.0,
		"weapon_tree": weapon_tree,
	})
	return s