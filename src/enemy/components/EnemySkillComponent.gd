extends Node
## 怪物技能组件 — 附加在 EnemyBase 上，为每种怪物类型提供主动/被动/触发型技能
## 与怪物本体解耦，通过 skill_factory 注入到 EnemyTypes.gd
## 支持三类技能：active（周期性主动触发）、passive（常驻被动）、triggered（事件触发）

class_name EnemySkillComponent

signal skill_triggered(skill_id: String, source: Node)
signal trap_planted(pos: Vector2, radius: float, duration: float)

## 技能配置结构
## {
##   "id": String,
##   "type": "active" | "passive" | "triggered",
##   "cooldown": float (秒),
##   "timer": float (内部计时器),
##   "config": Dictionary (技能私有配置)
## }

var _active_skills: Array[Dictionary] = []
var _passive_skills: Array[Dictionary] = []
var _triggered_skills: Array[Dictionary] = []
var _owner: Node = null
var _is_enabled: bool = true

func _init(p_owner: Node = null):
	_owner = p_owner

func set_component_owner(owner: Node) -> void:
	_owner = owner


func _normalize_skill_config(config: Dictionary) -> Dictionary:
	var flat := config.duplicate(true)
	var inner = flat.get("config", null)
	if inner is Dictionary:
		for key in inner.keys():
			flat[key] = inner[key]
		flat.erase("config")
	return flat

## ========== 技能注册 ==========

func register_active_skill(skill_id: String, config: Dictionary) -> void:
	var cfg := _normalize_skill_config(config)
	var skill: Dictionary = {
		"id": skill_id,
		"type": "active",
		"cooldown": cfg.get("cooldown", 5.0),
		"timer": cfg.get("initial_delay", 1.0),
		"config": cfg,
	}
	_active_skills.append(skill)

func register_passive_skill(skill_id: String, config: Dictionary) -> void:
	var cfg := _normalize_skill_config(config)
	var skill: Dictionary = {
		"id": skill_id,
		"type": "passive",
		"config": cfg,
	}
	_passive_skills.append(skill)

func register_triggered_skill(skill_id: String, config: Dictionary) -> void:
	var cfg := _normalize_skill_config(config)
	var skill: Dictionary = {
		"id": skill_id,
		"type": "triggered",
		"trigger": cfg.get("trigger", "on_hit"),
		"cooldown": cfg.get("cooldown", 8.0),
		"timer": 0.0,
		"config": cfg,
	}
	_triggered_skills.append(skill)

## ========== 每帧 Tick（由 EnemyBase 在 _physics_process 中调用）==========
func tick(delta: float) -> void:
	if not _is_enabled or _owner == null:
		return
	_evaluate_active_skills(delta)
	_evaluate_triggered_skills(delta)
	_evaluate_passive_skills(delta)

## ========== 被动技能评估（每帧检查条件）==========
func _evaluate_passive_skills(_delta: float) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var current_hp_ratio: float = 0.0
	var max_hp_val: float = 1.0
	if _owner.has("max_hp"):
		max_hp_val = float(_owner.get("max_hp"))
	if _owner.has("current_hp"):
		current_hp_ratio = float(_owner.get("current_hp")) / maxf(1.0, max_hp_val)
	for skill in _passive_skills:
		var cfg: Dictionary = skill.get("config", {})
		# berserker_rage：低血量时移速+40%
		if skill["id"] == "berserker_rage":
			var threshold: float = cfg.get("hp_threshold", 0.4)
			if current_hp_ratio <= threshold:
				var mult: float = cfg.get("speed_mult", 1.4)
				var cur_speed: float = float(_owner.get("speed", 80.0))
				_owner.set("speed", cur_speed * mult)
		# counter_strike：buff仍在生效时由EnemyBase.take_damage读取并乘算伤害
		if skill["id"] == "counter_strike":
			var key_until: String = "counter_strike_until"
			var until: float = _owner.get(key_until, 0.0)
			var now: float = Time.get_ticks_msec() * 0.001
			if now >= until:
				# buff已过期（仅供监控，不需要主动清除，时间戳自动失效）
				pass

## ========== 事件入口（被攻击时 / 死亡时 / 进入战斗时）==========

## 被攻击时触发（由 EnemyBase.take_damage 调用）
func on_taken_damage(damage: int, attacker_pos: Vector2) -> void:
	_try_trigger("triggered", "on_taken_damage", {"damage": damage, "attacker_pos": attacker_pos})
	# counter_strike：受击时20%概率触发反击buff（被动技能中的事件驱动型）
	for skill in _passive_skills:
		if skill["id"] == "counter_strike":
			var cfg: Dictionary = skill.get("config", {})
			var proc_chance: float = cfg.get("proc_chance", 0.20)
			var buff_duration: float = cfg.get("buff_duration", 3.0)
			if randf() < proc_chance:
				var now: float = Time.get_ticks_msec() * 0.001
				_owner.set("counter_strike_until", now + buff_duration)

## 死亡时触发
func on_death() -> void:
	_try_trigger("triggered", "on_death", {})

## 进入战斗时触发
func on_engaged() -> void:
	_try_trigger("triggered", "on_engaged", {})

## 低血量检测（由 EnemyBase 调用，血量低于40%时）
func on_low_hp() -> void:
	_try_trigger("triggered", "on_low_hp", {})

## ========== 主动技能执行 ==========

func _evaluate_active_skills(delta: float) -> void:
	for skill in _active_skills:
		skill["timer"] -= delta
		if skill["timer"] <= 0.0:
			_execute_active_skill(skill)
			skill["timer"] = skill["cooldown"]

func _execute_active_skill(skill: Dictionary) -> void:
	var skill_id: String = skill["id"]
	var cfg: Dictionary = skill["config"]
	match skill_id:
		"chaser_rush":
			_exec_chaser_rush(cfg)
		"ranged_volley":
			_exec_ranged_volley(cfg)
		"summoner_spawn":
			_exec_summoner_spawn(cfg)
		"tank_shield_bash":
			_exec_tank_shield_bash(cfg)
		"bomber_trap":
			_exec_bomber_trap(cfg)
		"trapper_trap":
			_exec_trapper_trap(cfg)
		"ranged_sniper_shot":
			_exec_ranged_sniper_shot(cfg)
		"summoner_heal_aura":
			_exec_summoner_heal_aura(cfg)
		"summoner_chain_lightning":
			_exec_summoner_chain_lightning(cfg)
		"summoner_barrier":
			_exec_summoner_barrier(cfg)
		"tank_rock_throw":
			_exec_tank_rock_throw(cfg)
		"bomber_charge_up":
			_exec_bomber_charge_up(cfg)
		"tank_shield_wall":
			_exec_tank_shield_wall(cfg)
		"trapper_poison_cloud":
			_exec_trapper_poison_cloud(cfg)
		"trapper_vine":
			_exec_trapper_vine(cfg)
		"trapper_quake":
			_exec_trapper_quake(cfg)
		"trapper_stealth":
			_exec_trapper_stealth(cfg)

## ========== 触发型技能执行 ==========

func _evaluate_triggered_skills(delta: float) -> void:
	for skill in _triggered_skills:
		if skill["timer"] > 0.0:
			skill["timer"] -= delta

func _try_trigger(skill_type: String, trigger_event: String, ctx: Dictionary) -> void:
	for skill in _triggered_skills:
		if skill["config"].get("trigger_event") != trigger_event:
			continue
		if skill["timer"] > 0.0:
			continue
		_execute_triggered_skill(skill, ctx)
		skill["timer"] = skill["cooldown"]

func _execute_triggered_skill(skill: Dictionary, ctx: Dictionary) -> void:
	var skill_id: String = skill["id"]
	var cfg: Dictionary = skill["config"]
	match skill_id:
		"trapper_spore", "spore_on_hit":
			_exec_trapper_spore(cfg, ctx)
		"bomber_debris", "debris_on_death":
			_exec_bomber_debris(cfg, ctx)
		"ranged_escape_cloud", "close_quarter_retreat":
			_exec_ranged_escape_cloud(cfg)
		"ranged_flank_anticipation":
			_exec_ranged_flank_anticipation(cfg)
		"summoner_rally":
			_exec_summoner_rally(cfg)
		"tank_enrage", "low_hp_fury":
			_exec_tank_enrage(cfg)
		"bomber_early_detonation":
			_exec_bomber_early_detonation(cfg)
		"trapper_stealth":
			_exec_trapper_stealth(cfg)

## ========== 技能实现 ==========

## 【Chaser】冲刺猛击：向玩家方向短距离突进
func _exec_chaser_rush(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player_ref = _get_player()
	if player_ref == null:
		return
	var rush_speed: float = cfg.get("rush_speed", 350.0)
	var rush_dist: float = cfg.get("rush_dist", 65.0)
	var dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
	_owner.velocity = dir * rush_speed
	# 眩晕效果通过标记实现（由 EnemyBase 的 contact 处理）
	if cfg.get("stun"):
		_stun_player_if_contact(cfg.get("stun_dur", 0.5))

## 【Ranged】散射弹幕：同时发射3颗角度偏移的子弹
func _exec_ranged_volley(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player_ref = _get_player()
	if player_ref == null:
		return
	var dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
	var base_angle: float = dir.angle()
	var spread_rad: float = cfg.get("spread_rad", 0.22)
	var bullet_count: int = cfg.get("bullet_count", 3)
	var dmg: int = int(cfg.get("damage", 8))
	var bullet_scene: PackedScene = preload("res://scenes/EnemyProjectile.tscn")
	for i in bullet_count:
		var offset: float = (float(i) - float(bullet_count - 1) * 0.5) * spread_rad
		var bullet_dir: Vector2 = Vector2.from_angle(base_angle + offset)
		var spawn_pos: Vector2 = _owner.global_position + bullet_dir * 28.0
		var proj: Node = bullet_scene.instantiate()
		var parent = _get_parent_scene()
		if parent:
			parent.add_child(proj)
			proj.z_as_relative = false
			proj.z_index = 890
			if proj.has_method("launch"):
				proj.launch(spawn_pos, bullet_dir, 280.0, dmg)

## 【Summoner】召唤小怪
func _exec_summoner_spawn(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var count: int = cfg.get("count", 2)
	var parent = _get_parent_scene()
	if parent == null:
		return
	var minion_scene: PackedScene = preload("res://scenes/Enemy.tscn")
	for i in count:
		var offset: Vector2 = Vector2(randf_range(-48, 48), randf_range(-48, 48))
		var minion = minion_scene.instantiate()
		parent.add_child(minion)
		minion.global_position = _owner.global_position + offset
		minion.max_hp = max(10, int(_owner.max_hp * 0.35))
		minion.current_hp = minion.max_hp
		minion.damage = max(4, int(_owner.damage * 0.65))
		minion.speed = _owner.speed * 1.08
		if minion.has_method("set_visuals"):
			minion.set_visuals("🦇", Color(0.85, 0.25, 0.95, 1.0), 0.82)

## 【Tank】盾击：冲锋眩晕玩家0.5s
func _exec_tank_shield_bash(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player_ref = _get_player()
	if player_ref == null:
		return
	var dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
	_owner.velocity = dir * 180.0
	_stun_player_if_contact(cfg.get("stun_dur", 0.5))

## 【Bomber】放置地刺陷阱
func _exec_bomber_trap(cfg: Dictionary) -> void:
	if _owner == null:
		return
	var radius: float = cfg.get("radius", 65.0)
	var duration: float = cfg.get("duration", 4.0)
	var pos: Vector2 = _owner.global_position
	trap_planted.emit(pos, radius, duration)

## 【Trapper】放置地刺陷阱
func _exec_trapper_trap(cfg: Dictionary) -> void:
	if _owner == null:
		return
	var radius: float = cfg.get("radius", 80.0)
	var duration: float = cfg.get("duration", 4.0)
	var pos: Vector2 = _owner.global_position
	trap_planted.emit(pos, radius, duration)

## 【Trapper】藤蔓缠绕：向玩家发射缓慢藤蔓，命中后定身2秒
func _exec_trapper_vine(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player_ref = _get_player()
	if player_ref == null:
		return
	var dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
	var dmg: int = int(cfg.get("damage", 12))
	var bullet_speed: float = cfg.get("vine_speed", 200.0)
	var stun_dur: float = cfg.get("stun_dur", 2.0)
	var bullet_scene: PackedScene = preload("res://scenes/EnemyProjectile.tscn")
	var proj: Node = bullet_scene.instantiate()
	var parent = _get_parent_scene()
	if parent:
		parent.add_child(proj)
		proj.z_as_relative = false
		proj.z_index = 890
		if proj.has_method("apply_fate_stats_from_node"):
			var stats_node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "VineRootBullet")
			stats_node.set_base_stats({"root_duration": stun_dur, "root_damage": dmg})
			proj.apply_fate_stats_from_node(stats_node)
			stats_node.free()
		if proj.has_method("launch"):
			proj.launch(_owner.global_position + dir * 28.0, dir, bullet_speed, dmg)

## 【Trapper】地刺弹幕：扇形发射5根地刺，命中造成伤害+减速
func _exec_trapper_quake(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player_ref = _get_player()
	if player_ref == null:
		return
	var dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
	var base_angle: float = dir.angle()
	var spread_rad: float = cfg.get("spread_rad", 0.35)
	var spike_count: int = cfg.get("spike_count", 5)
	var dmg: int = int(cfg.get("damage", 8))
	var bullet_speed: float = cfg.get("bullet_speed", 320.0)
	var slow_factor: float = cfg.get("slow_factor", 0.6)
	var slow_dur: float = cfg.get("slow_duration", 1.2)
	var bullet_scene: PackedScene = preload("res://scenes/EnemyProjectile.tscn")
	var parent = _get_parent_scene()
	if parent == null:
		return
	for i in spike_count:
		var offset: float = (float(i) - float(spike_count - 1) * 0.5) * spread_rad
		var spike_dir: Vector2 = Vector2.from_angle(base_angle + offset)
		var spawn_pos: Vector2 = _owner.global_position + spike_dir * 28.0
		var proj: Node = bullet_scene.instantiate()
		parent.add_child(proj)
		proj.z_as_relative = false
		proj.z_index = 890
		if proj.has_method("apply_fate_stats_from_node"):
			var stats_node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "GroundSpikeSlow")
			stats_node.set_base_stats({"slow_factor": slow_factor, "slow_duration": slow_dur})
			proj.apply_fate_stats_from_node(stats_node)
			stats_node.free()
		if proj.has_method("launch"):
			proj.launch(spawn_pos, spike_dir, bullet_speed, dmg)

## 【Trapper】伪装伏击：短暂消失后从玩家背后出现并减速
func _exec_trapper_stealth(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	_owner.set("movement_locked", true)
	if _owner.has_node("Shape"):
		var shape: Node = _owner.get_node("Shape")
		if shape is ColorRect:
			var t := _owner.create_tween()
			t.tween_property(shape, "modulate:a", 0.15, 0.5)
	await _owner.get_tree().create_timer(2.0).timeout
	if not is_instance_valid(_owner) or _owner._is_dead:
		return
	var player_ref = _get_player()
	if player_ref != null:
		var behind_dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
		_owner.global_position = player_ref.global_position + behind_dir * 90.0
	_owner.set("movement_locked", false)
	if _owner.has_node("Shape"):
		var shape: Node = _owner.get_node("Shape")
		if shape is ColorRect:
			var t2 := _owner.create_tween()
			t2.tween_property(shape, "modulate:a", 1.0, 0.3)
	if player_ref != null and is_instance_valid(player_ref):
		if player_ref.has_method("apply_slow"):
			player_ref.apply_slow(0.4, 0.8)

## 【Trapper】诱捕孢子：被攻击时释放减速区域
func _exec_trapper_spore(cfg: Dictionary, ctx: Dictionary) -> void:
	if _owner == null:
		return
	var radius: float = cfg.get("radius", 90.0)
	var duration: float = cfg.get("duration", 2.0)
	var pos: Vector2 = _owner.global_position
	trap_planted.emit(pos, radius, duration)

## 【Bomber】碎片飞溅：死亡时散射8颗可伤害玩家的碎片
func _exec_bomber_debris(cfg: Dictionary, ctx: Dictionary) -> void:
	if _owner == null:
		return
	var debris_count: int = cfg.get("debris_count", 8)
	var debris_dmg: int = int(cfg.get("debris_damage", 8))
	var parent = _get_parent_scene()
	if parent == null:
		return
	var bullet_scene: PackedScene = preload("res://scenes/EnemyProjectile.tscn")
	for i in debris_count:
		var angle: float = (TAU / debris_count) * i
		var dir: Vector2 = Vector2.from_angle(angle)
		var spawn_pos: Vector2 = _owner.global_position + dir * 20.0
		var proj: Node = bullet_scene.instantiate()
		parent.add_child(proj)
		proj.z_as_relative = false
		proj.z_index = 890
		if proj.has_method("launch"):
			proj.launch(spawn_pos, dir, 180.0, debris_dmg)


## 范围伤害（Tank投石落地AOE用）
func _do_aoe_damage(pos: Vector2, radius: float, damage: int) -> void:
	var player = _get_player()
	if player != null and is_instance_valid(player):
		if pos.distance_to(player.global_position) <= radius and player.has_method("take_damage"):
			player.take_damage(damage)
	# AOE视觉闪光
	_spawn_aoe_flash(pos, radius)

## AOE区域闪光视觉（Tank投石/治疗光环用）
func _spawn_aoe_flash(pos: Vector2, radius: float) -> void:
	var parent = _get_parent_scene()
	if parent == null:
		return
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 870
	flash.size = Vector2(radius * 2.0, radius * 2.0)
	flash.pivot_offset = flash.size * 0.5
	flash.color = Color(0.8, 0.6, 0.2, 0.35)
	flash.global_position = pos - flash.size * 0.5
	parent.add_child(flash)
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(0.2, 0.2), 0.2)
	t.tween_property(flash, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(flash.queue_free)

## 治疗光环视觉（绿色脉冲扩散）
func _spawn_heal_aura_effect(radius: float) -> void:
	var parent = _get_parent_scene()
	if parent == null:
		return
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 870
	flash.size = Vector2(radius * 2.0, radius * 2.0)
	flash.pivot_offset = flash.size * 0.5
	flash.color = Color(0.2, 1.0, 0.4, 0.25)
	flash.global_position = _owner.global_position - flash.size * 0.5
	parent.add_child(flash)
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(0.3, 0.3), 0.4)
	t.tween_property(flash, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(flash.queue_free)

## 【Ranged】蓄力狙击射击：蓄力1.2秒后发射高伤害弹，命中后玩家短暂减速
## 与普通狙击射击区分：需要蓄力窗口（暴露弱点），但伤害更高且带控制效果
func _exec_ranged_sniper_shot(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player_ref = _get_player()
	if player_ref == null:
		return
	# 蓄力1.2秒（暴露弱点窗口）
	_owner.set("movement_locked", true)
	if _owner.has_node("Shape"):
		var shape: Node = _owner.get_node("Shape")
		if shape is ColorRect:
			var t := _owner.create_tween()
			t.set_parallel(true)
			t.tween_property(shape, "modulate", Color(1.0, 0.5, 0.5, 1.0), 0.6)
			t.chain().tween_property(shape, "modulate", Color(1.0, 0.2, 0.2, 1.0), 0.6)
	await _owner.get_tree().create_timer(1.2).timeout
	if not is_instance_valid(_owner) or _owner._is_dead:
		return
	_owner.set("movement_locked", false)
	var dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
	var dmg: int = int(cfg.get("damage", 28))
	var bullet_speed: float = cfg.get("bullet_speed", 580.0)
	var slow_duration: float = cfg.get("slow_duration", 0.8)
	var bullet_scene: PackedScene = preload("res://scenes/EnemyProjectile.tscn")
	var proj: Node = bullet_scene.instantiate()
	var parent = _get_parent_scene()
	if parent:
		parent.add_child(proj)
		proj.z_as_relative = false
		proj.z_index = 890
		if proj.has_method("apply_fate_stats_from_node"):
			var stats_node := AssemblyNode.new(AssemblyNode.NodeType.BULLET, "SniperSlowBullet")
			stats_node.set_base_stats({"slow_duration": slow_duration})
			proj.apply_fate_stats_from_node(stats_node)
			stats_node.free()
		if proj.has_method("launch"):
			proj.launch(_owner.global_position + dir * 28.0, dir, bullet_speed, dmg)

## 【Summoner】治疗光环：区域内友军每3秒恢复少量HP
func _exec_summoner_heal_aura(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var heal_amount: int = int(cfg.get("heal_amount", 8))
	var heal_radius: float = cfg.get("heal_radius", 120.0)
	var heal_interval: float = cfg.get("heal_interval", 3.0)
	# 找到范围内所有友军怪物并治疗
	var healed_any: bool = false
	for other in _owner.get_tree().get_nodes_in_group("enemy"):
		if other == _owner or not is_instance_valid(other):
			continue
		if _owner.global_position.distance_to(other.global_position) <= heal_radius:
			if other.has_method("heal"):
				other.heal(heal_amount)
				healed_any = true
	# 视觉反馈：光环
	if healed_any:
		_spawn_heal_aura_effect(heal_radius)

## 【Tank】投石：朝玩家当前位置投掷一块巨石，落地造成范围伤害+击退
func _exec_tank_rock_throw(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var player_ref = _get_player()
	if player_ref == null:
		return
	var dmg: int = int(cfg.get("damage", 15))
	var rock_radius: float = cfg.get("rock_radius", 65.0)
	var dir: Vector2 = (player_ref.global_position - _owner.global_position).normalized()
	# 在目标位置生成一个范围伤害区域
	var target_pos: Vector2 = player_ref.global_position
	var parent = _get_parent_scene()
	if parent == null:
		return
	# 投掷物：快速飞向目标位置的小石头
	var rock_scene: PackedScene = preload("res://scenes/EnemyProjectile.tscn")
	var proj: Node = rock_scene.instantiate()
	parent.add_child(proj)
	proj.z_as_relative = false
	proj.z_index = 890
	if proj.has_method("launch"):
		proj.launch(_owner.global_position + dir * 28.0, dir, 380.0, dmg)
	# 落地后在目标位置造成AOE
	var aoe_delay: float = _owner.global_position.distance_to(target_pos) / 380.0 * 0.9
	await _owner.get_tree().create_timer(aoe_delay).timeout
	if is_instance_valid(_owner):
		_do_aoe_damage(target_pos, rock_radius, dmg)

## 【Bomber】充能自爆：蓄力后大幅增强下一次爆炸的半径和伤害
func _exec_bomber_charge_up(cfg: Dictionary) -> void:
	if _owner == null:
		return
	# 充能：增大爆炸半径和伤害倍率
	var explosion_radius_mult: float = cfg.get("explosion_radius_mult", 2.0)
	var explosion_damage_mult: float = cfg.get("explosion_damage_mult", 2.5)
	var base_radius: float = 80.0
	var base_dmg: int = 25
	if _owner.has("explosion_radius"):
		base_radius = float(_owner.get("explosion_radius"))
	if _owner.has("explosion_damage"):
		base_dmg = int(_owner.get("explosion_damage"))
	_owner.set("explosion_radius", base_radius * explosion_radius_mult)
	_owner.set("explosion_damage", int(float(base_dmg) * explosion_damage_mult))
	# 充能视觉：红色脉冲
	if _owner.has_node("Shape"):
		var shape: Node = _owner.get_node("Shape")
		if shape is ColorRect:
			var t := _owner.create_tween()
			t.set_parallel(true)
			t.tween_property(shape, "color", Color(1.0, 0.1, 0.1, 1.0), 0.3)
			t.chain().tween_property(shape, "color", Color(1.0, 0.3, 0.3, 1.0), 0.3).set_trans(Tween.TRANS_QUAD)


## 【Ranged】低血量逃逸云：加速逃离并释放烟幕遮蔽
func _exec_ranged_escape_cloud(cfg: Dictionary) -> void:
	if _owner == null:
		return
	var speed_boost: float = cfg.get("speed_boost", 2.0)
	var duration: float = cfg.get("duration", 1.5)
	var cur_speed: float = float(_owner.get("speed", 50.0))
	_owner.set("speed", cur_speed * speed_boost)
	_spawn_heal_aura_effect(90.0)
	await _owner.get_tree().create_timer(duration).timeout
	if is_instance_valid(_owner):
		_owner.set("speed", cur_speed)

## 【Summoner】集会号令：提升范围内友军移速
func _exec_summoner_rally(cfg: Dictionary) -> void:
	if _owner == null:
		return
	var radius: float = cfg.get("radius", 150.0)
	var speed_mult: float = cfg.get("speed_mult_allies", 1.25)
	var done: bool = false
	for other in _owner.get_tree().get_nodes_in_group("enemy"):
		if other == _owner or not is_instance_valid(other):
			continue
		if _owner.global_position.distance_to(other.global_position) <= radius:
			if other.has_method("heal"):
				other.heal(1)
				done = true
			var cur_spd: float = float(other.get("speed", 80.0))
			other.set("speed", cur_spd * speed_mult)
			done = true
	if done:
		_spawn_heal_aura_effect(radius)

## 【Summoner】连锁闪电：弹跳攻击最多3个邻近敌人
func _exec_summoner_chain_lightning(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var chain_count: int = cfg.get("chain_count", 3)
	var chain_dmg: int = int(cfg.get("chain_damage", 10))
	var chain_range: float = cfg.get("chain_range", 110.0)
	var chain_delay: float = cfg.get("chain_delay", 0.18)
	var player_ref = _get_player()
	var targets: Array = [player_ref] if player_ref != null else []
	# 收集邻近友军
	for other in _owner.get_tree().get_nodes_in_group("enemy"):
		if other == _owner or not is_instance_valid(other):
			continue
		if _owner.global_position.distance_to(other.global_position) <= chain_range:
			targets.append(other)
	# 对每个目标执行闪电（弹跳）
	var hit_set: Array = []
	for target in targets:
		if target == null or not is_instance_valid(target):
			continue
		if target.has_method("take_damage"):
			target.take_damage(chain_dmg)
		hit_set.append(target)
		_spawn_lightning_effect(_owner.global_position, target.global_position)
		chain_dmg = int(float(chain_dmg) * 0.7)  # 每次弹跳伤害衰减30%
		if hit_set.size() >= chain_count:
			break
		# 找最近未命中目标
		var next_target = null
		var min_dist: float = INF
		for other in _owner.get_tree().get_nodes_in_group("enemy"):
			if other == _owner or not is_instance_valid(other) or hit_set.has(other):
				continue
			var d: float = target.global_position.distance_to(other.global_position)
			if d <= chain_range and d < min_dist:
				min_dist = d
				next_target = other
		if next_target != null:
			target = next_target
		else:
			break
		await _owner.get_tree().create_timer(chain_delay).timeout

func _spawn_lightning_effect(from: Vector2, to: Vector2) -> void:
	var parent = _get_parent_scene()
	if parent == null:
		return
	var line := Line2D.new()
	line.z_as_relative = false
	line.z_index = 895
	line.width = 2.0
	line.default_color = Color(0.6, 0.8, 1.0, 0.9)
	var mid: Vector2 = (from + to) * 0.5 + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	line.points = [from, mid, to]
	parent.add_child(line)
	var t := line.create_tween()
	t.tween_property(line, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(line.queue_free)

## 【Summoner】守护屏障：为范围内一名友军吸收一次攻击
func _exec_summoner_barrier(cfg: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var barrier_radius: float = cfg.get("barrier_radius", 100.0)
	var barrier_dur: float = cfg.get("barrier_dur", 4.0)
	# 找范围内hp最低的友军
	var best: Node = null
	var min_hp: float = INF
	for other in _owner.get_tree().get_nodes_in_group("enemy"):
		if other == _owner or not is_instance_valid(other):
			continue
		if _owner.global_position.distance_to(other.global_position) <= barrier_radius:
			var hp: float = float(other.get("current_hp", INF))
			if hp < min_hp:
				min_hp = hp
				best = other
	if best != null and is_instance_valid(best):
		best.set("_barrier_active", true)
		best.set("_barrier_until", Time.get_ticks_msec() * 0.001 + barrier_dur)
		_spawn_heal_aura_effect(barrier_radius * 0.6)

## 【Tank】狂暴化：低血量时大幅提升移速和伤害
func _exec_tank_enrage(cfg: Dictionary) -> void:
	if _owner == null:
		return
	var speed_mult: float = cfg.get("speed_mult", 1.5)
	var dmg_mult: float = cfg.get("damage_mult", 1.4)
	var cur_speed: float = 40.0
	var cur_dmg: int = 15
	if _owner.has("speed"):
		cur_speed = float(_owner.get("speed"))
	if _owner.has("damage"):
		cur_dmg = int(_owner.get("damage"))
	_owner.set("speed", cur_speed * speed_mult)
	_owner.set("damage", int(cur_dmg * dmg_mult))
	if _owner.has_node("Shape"):
		var shape: Node = _owner.get_node("Shape")
		if shape is ColorRect:
			var t := _owner.create_tween()
			t.set_parallel(true)
			t.tween_property(shape, "color", Color(1.0, 0.85, 0.1, 1.0), 0.3)
			t.chain().tween_property(shape, "color", Color(0.4, 0.5, 0.8, 1.0), 0.5).set_trans(Tween.TRANS_QUAD)

## 【Tank】盾墙：周期性举起盾牌，短时间内格挡所有近战伤害
func _exec_tank_shield_wall(cfg: Dictionary) -> void:
	if _owner == null:
		return
	var duration: float = cfg.get("duration", 2.5)
	var effectiveness: float = cfg.get("block_effectiveness", 0.9)
	_owner.set("_shield_wall_active", true)
	_owner.set("_shield_wall_effectiveness", effectiveness)
	# 视觉：盾牌变大且变亮
	if _owner.has_node("Shape"):
		var shape: Node = _owner.get_node("Shape")
		if shape is ColorRect:
			var t := _owner.create_tween()
			t.set_parallel(true)
			t.tween_property(shape, "modulate", Color(0.6, 0.7, 1.0, 1.0), 0.2)
	await _owner.get_tree().create_timer(duration).timeout
	if is_instance_valid(_owner):
		_owner.set("_shield_wall_active", false)
		if _owner.has_node("Shape"):
			var shape: Node = _owner.get_node("Shape")
			if shape is ColorRect:
				var t2 := _owner.create_tween()
				t2.set_parallel(true)
				t2.tween_property(shape, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.3)

## 【Trapper】毒云：释放毒雾，区域内敌人持续掉血
func _exec_trapper_poison_cloud(cfg: Dictionary) -> void:
	if _owner == null:
		return
	var cloud_radius: float = cfg.get("cloud_radius", 80.0)
	var cloud_duration: float = cfg.get("cloud_duration", 4.0)
	var dot_dps: float = cfg.get("dot_dps", 6.0)
	var dot_type: String = cfg.get("dot_type", "poison")
	var parent = _get_parent_scene()
	if parent == null:
		return
	var cloud_node := ColorRect.new()
	cloud_node.z_as_relative = false
	cloud_node.z_index = 850
	cloud_node.size = Vector2(cloud_radius * 2.0, cloud_radius * 2.0)
	cloud_node.pivot_offset = cloud_node.size * 0.5
	cloud_node.color = Color(0.3, 0.8, 0.1, 0.25)
	cloud_node.global_position = _owner.global_position - cloud_node.size * 0.5
	parent.add_child(cloud_node)
	var tick_interval: float = 0.5
	var tick_damage: int = maxi(1, int(dot_dps * tick_interval))
	var elapsed: float = 0.0
	while elapsed < cloud_duration:
		await _owner.get_tree().create_timer(tick_interval).timeout
		if not is_instance_valid(_owner) or _owner._is_dead:
			break
		elapsed += tick_interval
		var player = _get_player()
		if player != null and is_instance_valid(player):
			if _owner.global_position.distance_to(player.global_position) <= cloud_radius:
				if player.has_method("take_damage"):
					player.take_damage(tick_damage)
	var t := cloud_node.create_tween()
	t.set_parallel(true)
	t.tween_property(cloud_node, "modulate:a", 0.0, 0.5)
	t.chain().tween_callback(cloud_node.queue_free)

## 【Bomber】殉爆：低血量时提前引爆
func _exec_bomber_early_detonation(cfg: Dictionary) -> void:
	if _owner == null or _owner._is_dead:
		return
	var mult_radius: float = cfg.get("explosion_radius_mult", 1.8)
	var mult_dmg: float = cfg.get("explosion_damage_mult", 1.5)
	var base_radius: float = 80.0
	var base_dmg: int = 25
	if _owner.has("explosion_radius"):
		base_radius = float(_owner.get("explosion_radius"))
	if _owner.has("explosion_damage"):
		base_dmg = int(_owner.get("explosion_damage"))
	_owner.set("explosion_radius", base_radius * mult_radius)
	_owner.set("explosion_damage", int(base_dmg * mult_dmg))
	if _owner.has_method("_trigger_explosion"):
		_owner.call("_trigger_explosion")
	elif _owner.has_method("die"):
		_owner.call("die")

## ========== 工具方法 ==========

func _get_player() -> Node:
	if _owner == null:
		return null
	var tree: SceneTree = _owner.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")

func _get_parent_scene() -> Node:
	if _owner == null:
		return null
	var current_scene = _owner.get_tree().current_scene
	return current_scene if current_scene != null else _owner.get_tree().root

func _stun_player_if_contact(dur: float) -> void:
	var player = _get_player()
	if player == null or not is_instance_valid(player):
		return
	if _owner.global_position.distance_to(player.global_position) < 42.0:
		if player.has_method("apply_stun"):
			player.call("apply_stun", dur)

## ========== 技能工厂（为 EnemyTypes 每种怪物注入技能）==========

## 为近战追击型怪物注入技能（v2 — 更激进的狂暴+反击）
static func inject_chaser_skill(enemy: Node) -> EnemySkillComponent:
	var comp := EnemySkillComponent.new(enemy)
	comp.register_active_skill("chaser_rush", {
		"cooldown": 5.5,
		"initial_delay": 3.0,
		"rush_speed": 380.0,
		"rush_dist": 70.0,
		"stun": true,
		"stun_dur": 0.55,
	})
	comp.register_passive_skill("berserker_rage", {
		## 低血量时移速+50%，狂暴化（v2: threshold 0.5, speed 1.5）
		"config": {"hp_threshold": 0.5, "speed_mult": 1.5},
	})
	comp.register_passive_skill("counter_strike", {
		## 被攻击时20%概率反击（下次攻击伤害+40%）（v2: proc 0.2, buff 1.4）
		"config": {"proc_chance": 0.20, "damage_buff": 1.4, "buff_duration": 3.0},
	})
	comp.register_triggered_skill("low_hp_fury", {
		"trigger_event": "on_low_hp",
		"cooldown": 0.0,
		"config": {"speed_mult": 1.5},
	})
	return comp

## 为远程弹幕型怪物注入技能（v2 — 侧翼机动+更积极弹幕）
static func inject_ranged_skill(enemy: Node) -> EnemySkillComponent:
	var comp := EnemySkillComponent.new(enemy)
	comp.register_active_skill("ranged_volley", {
		"cooldown": 4.5,       # v2: 更快的弹幕节奏
		"initial_delay": 1.5,
		"spread_rad": 0.25,   # v2: 更宽的扩散
		"bullet_count": 4,    # v2: 4发而非3发
		"damage": 8,
	})
	comp.register_active_skill("ranged_sniper_shot", {
		"cooldown": 8.0,       # v2: 更频繁的狙击
		"initial_delay": 4.0,
		"damage": 22,          # v2: 略增伤害
		"bullet_speed": 520.0, # v2: 更快
	})
	comp.register_triggered_skill("close_quarter_retreat", {
		"trigger_event": "on_engaged",
		"cooldown": 5.0,       # v2: 延长冷却防止频繁逃跑
		"config": {"retreat_speed": 220.0, "retreat_dur": 1.0},
	})
	comp.register_triggered_skill("ranged_escape_cloud", {
		"trigger_event": "on_low_hp",
		"cooldown": 0.0,
		"config": {"speed_boost": 2.2, "duration": 1.8},
	})
	## v2 新增：远程精英专属侧翼迂回（需要 EnemyBase 支持）
	## 由 EnemyBase._ranged_flank_dir/_ranged_flank_timer 驱动，此处只是技能框架占位
	comp.register_triggered_skill("ranged_flank_anticipation", {
		"trigger_event": "on_engaged",
		"cooldown": 0.0,
		"config": {"flank_interval": 3.8, "tangent_speed_bonus": 1.3},
	})
	return comp

## 为召唤型怪物注入技能
static func inject_summoner_skill(enemy: Node) -> EnemySkillComponent:
	var comp := EnemySkillComponent.new(enemy)
	comp.register_active_skill("summoner_spawn", {
		"cooldown": 5.0,
		"initial_delay": 1.0,
		"count": 2,
	})
	comp.register_active_skill("summoner_heal_aura", {
		"cooldown": 8.0,
		"initial_delay": 4.0,
		"heal_amount": 6,
		"heal_radius": 120.0,
		"heal_interval": 3.0,
	})
	comp.register_triggered_skill("summoner_rally", {
		"trigger_event": "on_low_hp",
		"cooldown": 0.0,
		"config": {"speed_mult_allies": 1.25, "radius": 150.0},
	})
	## v3 新增：连锁闪电（弹跳攻击3个邻近敌人）
	comp.register_active_skill("summoner_chain_lightning", {
		"cooldown": 7.0,
		"initial_delay": 3.5,
		"chain_count": 3,
		"chain_damage": 10,
		"chain_range": 110.0,
		"chain_delay": 0.18,
	})
	## v3 新增：守护屏障（为范围内一名友军吸收一次攻击）
	comp.register_active_skill("summoner_barrier", {
		"cooldown": 9.0,
		"initial_delay": 5.5,
		"barrier_radius": 100.0,
		"barrier_dur": 4.0,
	})
	return comp

## 为护盾型怪物注入技能（v2 — 更硬核的盾墙+强化格挡+盾击）
static func inject_tank_skill(enemy: Node) -> EnemySkillComponent:
	var comp := EnemySkillComponent.new(enemy)
	comp.register_active_skill("tank_shield_bash", {
		"cooldown": 6.5,        # v2: 更快
		"initial_delay": 2.5,
		"stun": true,
		"stun_dur": 0.6,       # v2: 更长眩晕
	})
	comp.register_active_skill("tank_rock_throw", {
		"cooldown": 8.5,        # v2: 略快
		"initial_delay": 4.0,
		"damage": 18,           # v2: 更多伤害
		"rock_radius": 70.0,   # v2: 略大半径
	})
	## v2 新增：盾墙（周期性举起盾，短时间内格挡所有近战伤害）
	comp.register_active_skill("tank_shield_wall", {
		"cooldown": 12.0,
		"initial_delay": 6.0,
		"duration": 2.5,
		"block_effectiveness": 0.9,
	})
	comp.register_passive_skill("iron_will", {
		## 护盾格挡：20%几率完全抵挡伤害（v2: 15%→20%）
		"config": {"block_chance": 0.20},
	})
	comp.register_triggered_skill("tank_enrage", {
		"trigger_event": "on_low_hp",
		"cooldown": 0.0,
		"config": {"speed_mult": 1.5, "damage_mult": 1.4},
	})
	return comp

## 为自爆型怪物注入技能（v2 — 殉爆+强化碎片）
static func inject_bomber_skill(enemy: Node) -> EnemySkillComponent:
	var comp := EnemySkillComponent.new(enemy)
	comp.register_active_skill("bomber_trap", {
		"cooldown": 5.5,        # v2: 更快布陷阱
		"initial_delay": 2.0,
		"radius": 70.0,       # v2: 略大
		"duration": 4.0,
	})
	comp.register_active_skill("bomber_charge_up", {
		"cooldown": 7.5,        # v2: 更早充能
		"initial_delay": 3.0,
		"explosion_radius_mult": 2.0,
		"explosion_damage_mult": 2.5,
	})
	## v2 新增：殉爆（低血量时提前引爆，不等玩家跑远）
	comp.register_triggered_skill("bomber_early_detonation", {
		"trigger_event": "on_low_hp",
		"cooldown": 0.0,
		"config": {"hp_threshold": 0.35, "explosion_radius_mult": 1.8, "explosion_damage_mult": 1.5},
	})
	comp.register_triggered_skill("debris_on_death", {
		"trigger_event": "on_death",
		"cooldown": 0.0,
		"config": {"debris_count": 10, "debris_damage": 10},  # v2: 8→10, 8→10
	})
	return comp

## 为潜伏型怪物注入技能（v2 — 伪装+剧毒孢子+强化陷阱）
static func inject_trapper_skill(enemy: Node) -> EnemySkillComponent:
	var comp := EnemySkillComponent.new(enemy)
	comp.register_active_skill("trapper_trap", {
		"cooldown": 4.5,        # v2: 更快
		"initial_delay": 1.5,
		"radius": 85.0,        # v2: 略大
		"duration": 5.0,       # v2: 更长
	})
	comp.register_triggered_skill("spore_on_hit", {
		"trigger_event": "on_taken_damage",
		"cooldown": 5.0,       # v2: 更快能再放
		"config": {"radius": 95.0, "duration": 2.5, "slow_factor": 0.5},  # v2: 减速效果
	})
	## v2 新增：剧毒孢子（释放毒雾，区域内敌人持续掉血）
	comp.register_active_skill("trapper_poison_cloud", {
		"cooldown": 10.0,
		"initial_delay": 5.0,
		"cloud_radius": 80.0,
		"cloud_duration": 4.0,
		"dot_dps": 6,
		"dot_type": "poison",
	})
	## v3 新增：藤蔓缠绕（向玩家发射缓慢藤蔓，命中定身2秒）
	comp.register_active_skill("trapper_vine", {
		"cooldown": 8.0,
		"initial_delay": 3.0,
		"damage": 12,
		"vine_speed": 200.0,
		"stun_dur": 2.0,
	})
	## v3 新增：地刺弹幕（扇形发射5根地刺，命中减速）
	comp.register_active_skill("trapper_quake", {
		"cooldown": 6.5,
		"initial_delay": 4.5,
		"spread_rad": 0.35,
		"spike_count": 5,
		"damage": 8,
		"bullet_speed": 320.0,
		"slow_factor": 0.6,
		"slow_duration": 1.2,
	})
	## v3 新增：伪装伏击（短暂消失后从玩家背后出现并减速）
	comp.register_triggered_skill("trapper_stealth", {
		"trigger_event": "on_engaged",
		"cooldown": 12.0,
		"config": {"stealth_dur": 2.0, "behind_dist": 90.0},
	})
	return comp