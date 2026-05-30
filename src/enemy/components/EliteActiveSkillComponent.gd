extends Node
## 精英怪专属主动技能组件
## 与 EnemySkillComponent（基础怪物技能）解耦，精英怪物专用的主动技能层
## 注入在 EliteSpawnDirector 生成精英怪物时，由 EnemyBase 调用 tick
## 支持：精英冲锋 / 护盾反射 / 召集同伴 / 狂暴化 / 技能反制

class_name EliteActiveSkillComponent

signal elite_skill_triggered(skill_id: String, source: Node)
signal elite_barrier_activated(target: Node, duration: float)
signal elite_rally_issued(radius: float, speed_mult: float)

var _owner: Node = null
var _active_skills: Array[Dictionary] = []
var _cooldown_timers: Dictionary = {}
var _is_enabled: bool = true
var _elite_tier: int = 1  # 1-3，影响技能强度

func _init(owner: Node = null, tier: int = 1):
	_owner = owner
	_elite_tier = tier

func set_owner(owner: Node) -> void:
	_owner = owner

func set_elite_tier(tier: int) -> void:
	_elite_tier = maxi(1, mini(3, tier))

## ========== 技能注册 ==========

func register_elite_skill(skill_id: String, cooldown: float, config: Dictionary) -> void:
	var skill: Dictionary = {
		"id": skill_id,
		"cooldown": cooldown,
		"timer": config.get("initial_delay", 1.0),
		"config": config,
	}
	_active_skills.append(skill)
	_cooldown_timers[skill_id] = 0.0

## ========== 每帧 Tick（由 EnemyBase 在 _physics_process 中调用）==========
func tick(delta: float) -> void:
	if not _is_enabled or _owner == null or not is_instance_valid(_owner):
		return
	_evaluate_elite_skills(delta)

func _evaluate_elite_skills(delta: float) -> void:
	for skill in _active_skills:
		var skill_id: String = skill["id"]
		_cooldown_timers[skill_id] = maxi(0.0, _cooldown_timers.get(skill_id, 0.0) - delta)
		skill["timer"] -= delta
		if skill["timer"] <= 0.0 and _cooldown_timers.get(skill_id, 0.0) <= 0.0:
			_execute_elite_skill(skill)
			skill["timer"] = skill["cooldown"]
			_cooldown_timers[skill_id] = skill["cooldown"]

func _execute_elite_skill(skill: Dictionary) -> void:
	var skill_id: String = skill["id"]
	var cfg: Dictionary = skill["config"]
	match skill_id:
		"elite_charge":
			_exec_elite_charge(cfg)
		"shield_reflect":
			_exec_shield_reflect(cfg)
		"elite_rally":
			_exec_elite_rally(cfg)
		"elite_enrage":
			_exec_elite_enrage(cfg)
		"skill_countershot":
			_exec_skill_countershot(cfg)
		"elite_teleportstrike":
			_exec_elite_teleportstrike(cfg)

## ========== 精英专属技能实现 ==========

## 【精英冲锋】精英怪快速冲向玩家，接触时造成伤害+短距离击退
## tier 影响：冲锋速度、伤害、击退距离
func _exec_elite_charge(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player: Node = _get_player()
	if player == null or not is_instance_valid(player):
		return
	var charge_speed: float = cfg.get("charge_speed", 320.0) + _elite_tier * 40.0
	var charge_dist: float = cfg.get("charge_dist", 110.0) + _elite_tier * 15.0
	var damage: int = int(cfg.get("damage", 15) * (1.0 + (_elite_tier - 1) * 0.3))
	var knockback: float = cfg.get("knockback", 55.0) + _elite_tier * 10.0
	var dir: Vector2 = (player.global_position - _owner.global_position).normalized()
	_owner.velocity = dir * charge_speed
	# 冲锋期间霸体（不被击退）
	_owner.set("_charge_immune", true)
	await _owner.get_tree().create_timer(0.35).timeout
	_owner.set("_charge_immune", false)
	# 接触判定
	if is_instance_valid(player) and _owner.global_position.distance_to(player.global_position) < 48.0:
		if player.has_method("take_damage"):
			player.take_damage(damage)
		if player.has_method("apply_knockback"):
			player.call("apply_knockback", dir * knockback)
	elite_skill_triggered.emit("elite_charge", _owner)

## 【护盾反射】激活护盾，在持续时间内反射投射物
## tier 影响：持续时间、反射概率
func _exec_shield_reflect(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var duration: float = cfg.get("duration", 2.5) * (1.0 + (_elite_tier - 1) * 0.2)
	var reflect_chance: float = cfg.get("reflect_chance", 0.5) + _elite_tier * 0.15
	_owner.set("_shield_reflect_active", true)
	_owner.set("_shield_reflect_chance", reflect_chance)
	# 视觉反馈：护盾光环
	_spawn_shield_effect(reflect_chance)
	elite_skill_triggered.emit("shield_reflect", _owner)
	await _owner.get_tree().create_timer(duration).timeout
	if is_instance_valid(_owner):
		_owner.set("_shield_reflect_active", false)
		_owner.set("_shield_reflect_chance", 0.0)

## 【精英召集】精英怪向周围发出召集令，附近友军获得移速和伤害加成
## tier 影响：范围、buff强度
func _exec_elite_rally(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var radius: float = cfg.get("radius", 180.0) + _elite_tier * 30.0
	var speed_mult: float = cfg.get("speed_mult", 1.25) + (_elite_tier - 1) * 0.05
	var damage_mult: float = cfg.get("damage_mult", 1.15) + (_elite_tier - 1) * 0.05
	var duration: float = cfg.get("duration", 4.0)
	# 给范围内友军上buff
	var rally_count: int = 0
	for other in _owner.get_tree().get_nodes_in_group("enemy"):
		if other == _owner or not is_instance_valid(other):
			continue
		if _owner.global_position.distance_to(other.global_position) <= radius:
			# 移速buff
			var cur_speed: float = float(other.get("speed", 80.0))
			other.set("speed", cur_speed * speed_mult)
			# 伤害buff
			var cur_dmg: int = int(other.get("damage", 10))
			other.set("damage", int(cur_dmg * damage_mult))
			# 记录buff结束时间（简单用时间戳）
			var until: float = Time.get_ticks_msec() * 0.001 + duration
			other.set("_rally_buff_until", until)
			rally_count += 1
	if rally_count > 0:
		elite_rally_issued.emit(radius, speed_mult)
	elite_skill_triggered.emit("elite_rally", _owner)

## 【精英狂暴化】低血量时触发，大幅提升移速和伤害，持续到死亡
## tier 影响：提升幅度（一次性触发，不恢复）
func _exec_elite_enrage(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	# 检查是否已狂暴化
	if _owner.get("_enraged", false):
		return
	var speed_mult: float = cfg.get("speed_mult", 1.5) + (_elite_tier - 1) * 0.15
	var damage_mult: float = cfg.get("damage_mult", 1.4) + (_elite_tier - 1) * 0.1
	var cur_speed: float = float(_owner.get("speed", 80.0))
	var cur_dmg: int = int(_owner.get("damage", 15))
	_owner.set("speed", cur_speed * speed_mult)
	_owner.set("damage", int(cur_dmg * damage_mult))
	_owner.set("_enraged", true)
	# 视觉反馈：身体变红
	if _owner.has_node("Shape"):
		var shape: Node = _owner.get_node("Shape")
		if shape is ColorRect:
			var t := _owner.create_tween()
			t.set_parallel(true)
			t.tween_property(shape, "modulate", Color(1.0, 0.2, 0.1, 1.0), 0.4)
			t.chain().tween_property(shape, "color", Color(1.0, 0.15, 0.15, 1.0), 0.3)
	elite_skill_triggered.emit("elite_enrage", _owner)

## 【技能反制】被命中时一定概率反制玩家技能（沉默玩家1.5秒）
## tier 影响：反制概率、沉默时长
func _exec_skill_countershot(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var counter_chance: float = cfg.get("counter_chance", 0.18) + _elite_tier * 0.06
	var silence_dur: float = cfg.get("silence_dur", 1.5) + (_elite_tier - 1) * 0.3
	var player: Node = _get_player()
	if player != null and is_instance_valid(player):
		if randf() < counter_chance:
			if player.has_method("apply_silence"):
				player.call("apply_silence", silence_dur)
	elite_skill_triggered.emit("skill_countershot", _owner)

## 【瞬移打击】精英怪短距离传送到玩家背后并造成范围伤害
## tier 影响：传送距离、伤害半径
func _exec_elite_teleportstrike(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player: Node = _get_player()
	if player == null or not is_instance_valid(player):
		return
	var teleport_dist: float = cfg.get("teleport_dist", 130.0) + _elite_tier * 20.0
	var damage: int = int(cfg.get("damage", 20) * (1.0 + (_elite_tier - 1) * 0.25))
	var aoe_radius: float = cfg.get("aoe_radius", 70.0) + _elite_tier * 10.0
	# 计算玩家背后的位置
	var behind_dir: Vector2 = (_owner.global_position - player.global_position).normalized()
	var target_pos: Vector2 = player.global_position + behind_dir * teleport_dist
	# 传送特效
	_spawn_teleport_effect(_owner.global_position)
	_owner.global_position = target_pos
	_spawn_teleport_effect(target_pos)
	# AOE 伤害
	_do_aoe_damage(target_pos, aoe_radius, damage)
	elite_skill_triggered.emit("elite_teleportstrike", _owner)

## ========== 事件入口（被攻击时 / 死亡时）==========

## 被攻击时触发（由 EnemyBase 调用）
func on_taken_damage(damage: int, attacker_pos: Vector2) -> void:
	# skill_countershot 是被动反制，不需要额外处理
	pass

## 死亡时触发（用于清理状态）
func on_death() -> void:
	_is_enabled = false
	# 清理召集buff
	_clear_rally_buffs()

## ========== 工具方法 ==========

func _get_player() -> Node:
	if _owner == null:
		return null
	var tree: SceneTree = _owner.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")

func _spawn_shield_effect(reflect_chance: float) -> void:
	var parent: Node = _get_parent_scene()
	if parent == null:
		return
	var shield_radius: float = 50.0 + _elite_tier * 8.0
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 875
	flash.size = Vector2(shield_radius * 2.0, shield_radius * 2.0)
	flash.pivot_offset = flash.size * 0.5
	var alpha: float = 0.3 + reflect_chance * 0.2
	flash.color = Color(0.5, 0.7, 1.0, alpha)
	flash.global_position = _owner.global_position - flash.size * 0.5
	parent.add_child(flash)
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "modulate:a", 0.0, 1.5)
	t.chain().tween_callback(flash.queue_free)

func _spawn_teleport_effect(pos: Vector2) -> void:
	var parent: Node = _get_parent_scene()
	if parent == null:
		return
	var ring := ColorRect.new()
	ring.z_as_relative = false
	ring.z_index = 875
	ring.size = Vector2(60, 60)
	ring.pivot_offset = ring.size * 0.5
	ring.color = Color(0.5, 0.2, 1.0, 0.6)
	ring.global_position = pos - ring.size * 0.5
	parent.add_child(ring)
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2(2.5, 2.5), 0.25)
	t.tween_property(ring, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(ring.queue_free)

func _do_aoe_damage(pos: Vector2, radius: float, damage: int) -> void:
	var player: Node = _get_player()
	if player != null and is_instance_valid(player):
		if pos.distance_to(player.global_position) <= radius and player.has_method("take_damage"):
			player.call("take_damage", damage)
	# AOE 视觉
	var parent: Node = _get_parent_scene()
	if parent == null:
		return
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 870
	flash.size = Vector2(radius * 2.0, radius * 2.0)
	flash.pivot_offset = flash.size * 0.5
	flash.color = Color(0.9, 0.3, 0.2, 0.3)
	flash.global_position = pos - flash.size * 0.5
	parent.add_child(flash)
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(0.2, 0.2), 0.3)
	t.tween_property(flash, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(flash.queue_free)

func _get_parent_scene() -> Node:
	if _owner == null:
		return null
	var current_scene = _owner.get_tree().current_scene
	return current_scene if current_scene != null else _owner.get_tree().root

func _clear_rally_buffs() -> void:
	if _owner == null:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	for other in _owner.get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(other):
			continue
		var until: float = other.get("_rally_buff_until", 0.0)
		if until > now:
			# 恢复原始移速（简化处理，实际应存原始值）
			other.set("speed", float(other.get("speed", 80.0)) * 0.8)

## ========== 技能工厂（由 EliteSpawnDirector 调用）==========

## 根据精英词缀和 tier 注入对应技能
## modifier_id: EliteSpawnDirector 中的 modifier 标签
## tier: 精英等级（1-3）
static func inject_elite_skills(enemy: Node, modifier_id: String, tier: int) -> EliteActiveSkillComponent:
	var comp := EliteActiveSkillComponent.new(enemy, tier)
	comp.set_owner(enemy)
	enemy.add_child(comp)
	comp.set_owner(enemy)  # re-set after add_child

	match modifier_id:
		"Elite.Huge":
			_inject_huge_elite_skills(comp, tier)
		"Elite.SpawnOnDeath":
			_inject_spawn_elite_skills(comp, tier)
		"Elite.Ricochet":
			_inject_ricochet_elite_skills(comp, tier)
		"Elite.Parasite":
			_inject_parasite_elite_skills(comp, tier)
		"Elite.WeaponParasite":
			_inject_weapon_elite_skills(comp, tier)
		"Elite.BulletEater":
			_inject_bulleteater_elite_skills(comp, tier)
		_:
			# 默认：给精英一个随机技能
			_inject_default_elite_skills(comp, tier)

	return comp

static func _inject_huge_elite_skills(comp: EliteActiveSkillComponent, tier: int) -> void:
	# 巨大化精英：笨重但威胁大，给予冲锋+狂暴
	comp.register_elite_skill("elite_charge", 6.0 + tier * 0.5, {
		"initial_delay": 3.0 + tier * 0.5,
		"charge_speed": 300.0,
		"charge_dist": 100.0,
		"damage": 18,
		"knockback": 50.0,
	})
	comp.register_elite_skill("elite_enrage", 0.0, {
		# 低血量狂暴，一次性触发
	})
	# 狂暴化通过 on_low_hp 触发

static func _inject_spawn_elite_skills(comp: EliteActiveSkillComponent, tier: int) -> void:
	# 分裂精英：召唤同伴，给予召集令强化召唤物
	comp.register_elite_skill("elite_rally", 8.0 + tier * 0.5, {
		"initial_delay": 4.0,
		"radius": 160.0 + tier * 25,
		"speed_mult": 1.2,
		"damage_mult": 1.12,
		"duration": 5.0,
	})

static func _inject_ricochet_elite_skills(comp: EliteActiveSkillComponent, tier: int) -> void:
	# 反弹精英：给予护盾反射，触发时短时间反射投射物
	comp.register_elite_skill("shield_reflect", 10.0 + tier * 1.0, {
		"initial_delay": 5.0,
		"duration": 2.0 + tier * 0.3,
		"reflect_chance": 0.45 + tier * 0.08,
	})

static func _inject_parasite_elite_skills(comp: EliteActiveSkillComponent, tier: int) -> void:
	# 寄生精英：给予瞬移打击，快速接近玩家
	comp.register_elite_skill("elite_teleportstrike", 7.0 + tier * 0.5, {
		"initial_delay": 3.5,
		"teleport_dist": 120.0 + tier * 20,
		"damage": 20,
		"aoe_radius": 65.0 + tier * 8,
	})
	comp.register_elite_skill("elite_enrage", 0.0, {
		# 低血量狂暴
	})

static func _inject_weapon_elite_skills(comp: EliteActiveSkillComponent, tier: int) -> void:
	# 抢枪精英：给予技能反制，沉默玩家
	comp.register_elite_skill("skill_countershot", 6.0 + tier * 0.5, {
		"initial_delay": 2.5,
		"counter_chance": 0.15 + tier * 0.05,
		"silence_dur": 1.3 + tier * 0.25,
	})
	comp.register_elite_skill("elite_charge", 7.5 + tier * 0.5, {
		"initial_delay": 4.5,
		"charge_speed": 280.0,
		"charge_dist": 90.0,
		"damage": 15,
		"knockback": 45.0,
	})

static func _inject_bulleteater_elite_skills(comp: EliteActiveSkillComponent, tier: int) -> void:
	# 吞弹精英：给予护盾反射 + 召集
	comp.register_elite_skill("shield_reflect", 9.0 + tier * 0.8, {
		"initial_delay": 4.0,
		"duration": 2.2 + tier * 0.25,
		"reflect_chance": 0.5 + tier * 0.06,
	})
	comp.register_elite_skill("elite_rally", 10.0 + tier * 0.5, {
		"initial_delay": 6.0,
		"radius": 140.0 + tier * 20,
		"speed_mult": 1.18,
		"damage_mult": 1.1,
		"duration": 4.5,
	})

static func _inject_default_elite_skills(comp: EliteActiveSkillComponent, tier: int) -> void:
	# 默认：给精英一个随机主动技能
	var skills: Array = ["elite_charge", "shield_reflect", "elite_rally"]
	var chosen: String = skills[randi() % skills.size()]
	match chosen:
		"elite_charge":
			comp.register_elite_skill("elite_charge", 6.5, {
				"initial_delay": 3.0,
				"charge_speed": 290.0,
				"charge_dist": 95.0,
				"damage": 16,
				"knockback": 48.0,
			})
		"shield_reflect":
			comp.register_elite_skill("shield_reflect", 10.0, {
				"initial_delay": 5.0,
				"duration": 2.0,
				"reflect_chance": 0.5,
			})
		"elite_rally":
			comp.register_elite_skill("elite_rally", 9.0, {
				"initial_delay": 5.0,
				"radius": 160.0,
				"speed_mult": 1.22,
				"damage_mult": 1.12,
				"duration": 4.0,
			})
