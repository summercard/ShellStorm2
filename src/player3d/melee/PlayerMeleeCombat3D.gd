class_name PlayerMeleeCombat3D
extends Node
## 与八态移动机并行的近战动作子状态机。连段编号是上下文，不复制状态类。

const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d.tscn")
const VfxPool3D = preload("res://src/vfx/VfxPool3D.gd")
const VfxEffectBase3D = preload("res://src/vfx/VfxEffectBase3D.gd")

signal action_changed(snapshot: Dictionary)
signal hit_resolved(result: Dictionary)

const VALID_LOCOMOTION_STATES := ["idle", "moving"]

## ── 僵尸受击件（FX01-20）的近战尺寸 ────────────────────────────────────────
## 业主 2026-10-14 第四轮：「小僵尸和警察僵尸的受击特效太大了，使用击中其它物体的那个特效，
## 然后改成绿色即可，放大大概 10%」。
## ⚠ 近战命中件的 `size`（0.88 + 0.18 × 连段）是按 **FX01-05** 的内部基准定的；FX01-20 v002
## 是 FX01-21 那套火星造型（方块基准 0.16），直接沿用会把方块放到糊住半个怪 —— 正是业主说的
## 「太大」。僵尸分支因此改用与**枪击命中同一量级**的档位，连段 / 暴击的放大倍率保持不变。
##
## ⚠ 2026-10-15 第五轮业主：「击中僵尸的受击特效，**放大 50%**」⇒ 本基准同步 ×1.5
## （与 `Projectile3D.HIT_EFFECT_SIZE_SCALE` 同一个口径；枪击那条在那边派生，
##  近战这条在本文件独立定档，**两处要一起改**，否则「同一只怪被枪打 / 被刀砍」会不一样大）。
## 想调「僵尸受击多大」就动这两个数，别去改特效内部的几何常量。
const ZOMBIE_HIT_BASE_SIZE := 0.42 * 1.5
const ZOMBIE_HIT_COMBO_STEP := 0.18

var player: Player3D = null
var _machine: StateMachine = null
var _phase := "ready"
var _phase_duration := 0.0
var _phase_elapsed := 0.0
var _combo_index := -1
var _queued_next := false
var _attack_sequence := 0
var _attack_instance_id := ""
var _step_snapshot: Dictionary = {}
var _hit_target_ids: Dictionary = {}
var _last_cancel_reason := ""
var _last_hit_count := 0
var _swing_feedback_count := 0
var _impact_feedback_count := 0
var _last_feedback: Dictionary = {}
var _active_resolved := false
var _hit_stop_requested := false
var _attack_mode := "normal"
var _trigger_held := false
var _charge_ratio := 0.0
var _spin_elapsed := 0.0
var _spin_hit_elapsed := 0.0
var _sustained_effect: VfxEffectBase3D = null
const AXE_CHARGE_SECONDS := 1.0
const SWORD_HOLD_SECONDS := 0.35
const SPIN_CYCLE_SECONDS := 0.55
const SPIN_HIT_SECONDS := 0.25


func configure(owner_player: Player3D) -> void:
	player = owner_player
	_machine = StateMachine.new()
	_machine.name = "MeleeActionStateMachine"
	_machine.owner_node = self
	add_child(_machine)
	_machine.register("charging", preload("res://src/player3d/melee/Player3DMeleeChargingState.gd").new())
	_machine.register("spinning", preload("res://src/player3d/melee/Player3DMeleeSpinningState.gd").new())
	_machine.register("ready", Player3DMeleeReadyState.new())
	_machine.register("windup", Player3DMeleeWindupState.new())
	_machine.register("active", Player3DMeleeActiveState.new())
	_machine.register("recovery", Player3DMeleeRecoveryState.new())
	_machine.configure_transition_map({
		"ready": ["windup", "charging"],
		"charging": ["windup", "spinning", "ready"],
		"spinning": ["recovery", "ready"],
		"windup": ["active", "ready"],
		"active": ["recovery", "ready"],
		"recovery": ["windup", "ready"],
	})
	_machine.start("ready")


func physics_update(delta: float) -> void:
	if _machine == null:
		return
	if _phase != "ready" and not _can_continue_attack():
		cancel("locomotion_or_weapon_invalid")
		return
	_phase_elapsed = minf(_phase_duration, _phase_elapsed + maxf(0.0, delta))
	_machine.physics_update(delta)


func request_attack() -> bool:
	if not _can_start_attack():
		return false
	if _phase in ["charging", "spinning"]:
		return false
	if _phase == "ready":
		_attack_mode = "normal"
		_combo_index = 0
		_begin_combo_step()
		return true
	var combo_count := int(_current_melee_profile().get("combo_count", 0))
	if _combo_index < combo_count - 1:
		_queued_next = true
		action_changed.emit(get_snapshot())
		return true
	return false


func cancel(reason := "cancelled") -> void:
	if _machine == null or _phase == "ready":
		return
	player.clear_melee_hit_stop()
	_stop_sustained_effect()
	_trigger_held = false
	_last_cancel_reason = reason
	_queued_next = false
	_combo_index = -1
	_attack_instance_id = ""
	_step_snapshot.clear()
	_hit_target_ids.clear()
	_machine.transition_to("ready", true)


func transition_to(next_state: String) -> void:
	if _machine != null:
		_machine.transition_to(next_state)


func enter_ready() -> void:
	_stop_sustained_effect()
	_attack_mode = "normal"
	_charge_ratio = 0.0
	_phase = "ready"
	_phase_duration = 0.0
	_phase_elapsed = 0.0
	_queued_next = false
	_combo_index = -1
	_attack_instance_id = ""
	_step_snapshot.clear()
	_hit_target_ids.clear()
	action_changed.emit(get_snapshot())


func enter_phase(next_phase: String) -> void:
	_active_resolved = false
	_phase = next_phase
	_phase_elapsed = 0.0
	_phase_duration = maxf(0.01, float(_step_snapshot.get("%s_s" % next_phase, 0.1)))
	action_changed.emit(get_snapshot())
	if next_phase == "active":
		_spawn_swing_feedback()


func finish_recovery() -> void:
	var combo_count := int(_current_melee_profile().get("combo_count", 0))
	if _attack_mode != "normal":
		_machine.transition_to("ready")
		return
	if _queued_next and _combo_index + 1 < combo_count and _can_continue_attack():
		_combo_index += 1
		_begin_combo_step()
	else:
		_machine.transition_to("ready")


func resolve_active_hit() -> void:
	if player == null or _step_snapshot.is_empty() or _phase not in ["active", "spinning"] or _active_resolved:
		return
	_active_resolved = true
	if player.weapon.gun_id == "bp_waraxe" and _phase == "active":
		_acquire_effect(VfxPool3D.FX01_AXE_IMPACT, Color("ffb740"), 1.5 if _attack_mode == "charged" else 0.85, player.global_position + player.aim_direction * 1.3 + Vector3.UP * .04, {"forward":player.aim_direction})
	_last_hit_count = 0
	var origin := player.global_position + Vector3.UP * 0.72
	var forward := player.aim_direction
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var reach := float(_step_snapshot.get("reach", 2.5))
	var half_arc_cos := cos(deg_to_rad(float(_step_snapshot.get("arc_degrees", 100.0)) * 0.5))
	for value in get_tree().get_nodes_in_group("damageable_3d"):
		var target := value as Node3D
		if target == null or target == player or not target.has_method("take_damage"):
			continue
		if str(target.get("ai_state")) == "dead":
			continue
		var target_id := target.get_instance_id()
		if _hit_target_ids.has(target_id):
			continue
		var offset := target.global_position - player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001 or distance > reach:
			continue
		var direction := offset / distance
		if forward.dot(direction) < half_arc_cos:
			continue
		if _is_wall_occluded(origin, target.global_position + Vector3.UP * 0.65):
			continue
		_hit_target_ids[target_id] = true
		var result := _apply_hit(target, direction)
		if not bool(result.get("damage_applied", false)):
			continue
		if not _hit_stop_requested:
			_hit_stop_requested = true
			player.request_melee_hit_stop(4 if _attack_mode == "charged" else (2 if player.weapon.gun_id == "bp_waraxe" else 1))
		_spawn_hit_feedback(target, result)
		_last_hit_count += 1
		hit_resolved.emit(result)
	if _last_hit_count > 0 and AudioManager != null:
		AudioManager.play_melee_impact_sfx(
			str(_current_melee_profile().get("content_id", "")),
			_combo_index + 1
		)
	action_changed.emit(get_snapshot())


func get_phase_progress() -> float:
	if _phase == "ready" or _phase_duration <= 0.0:
		return 0.0
	return clampf(_phase_elapsed / _phase_duration, 0.0, 1.0)


func get_snapshot() -> Dictionary:
	var machine_snapshot := _machine.get_snapshot() if _machine != null else {}
	return {
		"active": _phase != "ready",
		"attack_mode": _attack_mode,
		"charge_ratio": _charge_ratio,
		"spin_progress": fposmod(_spin_elapsed / SPIN_CYCLE_SECONDS, 1.0),
		"phase": _phase,
		"phase_progress": get_phase_progress(),
		"phase_duration_s": _phase_duration,
		"combo_index": _combo_index,
		"combo_step": _combo_index + 1 if _combo_index >= 0 else 0,
		"combo_count": int(_current_melee_profile().get("combo_count", 0)),
		"queued_next": _queued_next,
		"attack_instance_id": _attack_instance_id,
		"weapon_content_id": str(_current_melee_profile().get("content_id", "")),
		"last_cancel_reason": _last_cancel_reason,
		"last_hit_count": _last_hit_count,
		"feedback": {
			"swing_count": _swing_feedback_count,
			"impact_target_count": _impact_feedback_count,
			"last": _last_feedback.duplicate(true),
		},
		"state_machine": machine_snapshot,
	}


func _begin_combo_step() -> void:
	var profile := _current_melee_profile()
	var steps := profile.get("combo_steps", []) as Array
	if _combo_index < 0 or _combo_index >= steps.size():
		cancel("missing_combo_step")
		return
	_hit_stop_requested = false
	_step_snapshot = (steps[_combo_index] as Dictionary).duplicate(true)
	_step_snapshot["reach"] = float(profile.get("reach", 2.5))
	_step_snapshot["arc_degrees"] = float(profile.get("arc_degrees", 100.0))
	_queued_next = false
	_hit_target_ids.clear()
	_attack_sequence += 1
	_attack_instance_id = "melee:%s:%06d" % [str(profile.get("content_id", "unknown")), _attack_sequence]
	_machine.transition_to("windup")


func _current_melee_profile() -> Dictionary:
	if player == null or player.weapon == null or not is_instance_valid(player.weapon):
		return {}
	return player.weapon.get_melee_profile()


func _can_start_attack() -> bool:
	return _can_continue_attack() and player.combat_enabled and player._silence_remaining <= 0.0


func _can_continue_attack() -> bool:
	if player == null or player.current_hp <= 0 or player.input_locked:
		return false
	if player.weapon == null or not is_instance_valid(player.weapon) or not player.weapon.is_melee_weapon():
		return false
	return not player.weapon_holstered and player._weapon_transition_phase.is_empty() and player._silence_remaining <= 0.0 and player.get_state_machine_state() in VALID_LOCOMOTION_STATES


func _apply_hit(target: Node3D, direction: Vector3) -> Dictionary:
	var weapon := player.weapon
	var damage_scale := float(_step_snapshot.get("damage_scale", 1.0))
	var critical := weapon.roll_melee_critical()
	var applied_damage := maxi(1, int(round(float(weapon.damage) * damage_scale)))
	var hp_before: Variant = target.get("current_hp")
	target.call("take_damage", applied_damage, critical, direction)
	var hp_after: Variant = target.get("current_hp")
	var damage_applied := hp_before != null and hp_after != null and int(hp_after) < int(hp_before)
	if damage_applied and target.has_method("apply_melee_stagger"):
		target.call("apply_melee_stagger", 0.30 if _combo_index == 2 or _attack_mode == "charged" else 0.20)
	var knockback := float(_current_melee_profile().get("knockback", 4.0)) * float(_step_snapshot.get("knockback_scale", 1.0))
	if damage_applied and target.has_method("apply_melee_knockback"):
		if target is Enemy3D and _attack_mode == "charged":
			target.call("apply_melee_knockback", direction, knockback, 0.35, 20.0)
		else:
			target.call("apply_melee_knockback", direction, knockback, 0.20)
	return {
		"attack_instance_id": _attack_instance_id,
		"weapon_instance_id": player.get_equipped_weapon_instance_id(),
		"weapon_content_id": str(_current_melee_profile().get("content_id", "")),
		"combo_step": _combo_index + 1,
		"target_instance_id": target.get_instance_id(),
		"damage": applied_damage,
		"damage_applied": damage_applied,
		"critical": critical,
		"knockback": knockback,
		"attack_mode": _attack_mode,
		"charge_ratio": _charge_ratio,
		"hit_position": target.global_position + Vector3.UP * 0.65,
	}


func _spawn_swing_feedback() -> void:
	if player == null or player.weapon == null:
		return
	var profile := _current_melee_profile()
	var forward := player.aim_direction
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var combo_step := _combo_index + 1
	var reach := float(profile.get("reach", 2.5))
	var color := player.weapon.bullet_color
	var size := (0.92 + float(combo_step - 1) * 0.13) * reach / 2.65
	var position := player.global_position + Vector3.UP * 0.72 + forward * reach * 0.40
	var context := {
		"forward": forward,
		"combo_step": combo_step,
		"weapon_content_id": str(profile.get("content_id", "")),
		"attack_instance_id": _attack_instance_id,
	}
	context["follow"] = player.avatar.visual_root
	context["follow_local_offset"] = Vector3(0,0.6,0)
	context["combo_step"] = combo_step
	context["duration"] = _phase_duration
	var effect_id := VfxPool3D.FX01_MELEE_SLASH
	if player.weapon.gun_id == "bp_waraxe":
		effect_id = VfxPool3D.FX01_AXE_CLEAVE
	elif player.weapon.gun_id == "bp_greatblade":
		effect_id = VfxPool3D.FX01_BLADE_SWEEP
	_acquire_effect(effect_id, color, size, position, context)
	_swing_feedback_count += 1
	_last_feedback = {"kind": "slash", "combo_step": combo_step, "position": position}
	if AudioManager != null:
		AudioManager.play_melee_swing_sfx(str(profile.get("content_id", "")), combo_step)


func _spawn_hit_feedback(target: Node3D, result: Dictionary) -> void:
	if player == null or player.weapon == null:
		return
	var combo_step := _combo_index + 1
	var critical := bool(result.get("critical", false))
	var color := Color("ffd166") if critical else player.weapon.bullet_color
	var size := (0.88 + float(combo_step - 1) * 0.18) * (1.18 if critical else 1.0)
	var position := target.global_position + Vector3.UP * 0.65
	var context := {
		"forward": player.aim_direction,
		"combo_step": combo_step,
		"critical": critical,
		"target_instance_id": target.get_instance_id(),
		"attack_instance_id": _attack_instance_id,
	}
	# 命中特效分流（业主 2026-10-14「对击中特效进行区分」＋追问后明确「枪击 + 近战都用」）：
	#   打中「僵尸三兄弟」（小僵尸 / 警察僵尸 / 胖子僵尸）⇒ FX01-20 `VFX-GOO-HIT-3D`
	#   （v002 起 = 金属火星造型 + 僵尸绿，与枪击命中是**同一件**）；
	#   打中其余怪种 ⇒ **仍是** FX01-05 `VFX-MELEE-IMPACT-3D`（近战专属命中件，逐字不变）。
	# ⚠ 这里刻意**不**把非僵尸的替换成 FX01-21 金属火星：那件是「打墙/打金属」的读法，
	# 用在肉身上不对，而且会把 FX01-05 变成无人引用的孤儿资产。
	# 分流判据与 `Projectile3D._spawn_hit_effect` 共用同一个入口 `Enemy3D.uses_goo_hit_burst()`，
	# 避免「同一只怪被枪打是一种读法、被刀砍又是另一种」。
	var asset_id: StringName = VfxPool3D.FX01_MELEE_IMPACT
	var effect_size := size
	if target is Enemy3D and (target as Enemy3D).uses_goo_hit_burst():
		asset_id = VfxPool3D.FX01_GOO_HIT
		# ⚠ 尺寸换成僵尸受击件自己的档位（见 `ZOMBIE_HIT_BASE_SIZE`）——不能沿用近战件的 `size`，
		# 那套数是按 FX01-05 的内部基准定的，喂给火星造型会把方块放大到糊住半个怪。
		effect_size = (
			ZOMBIE_HIT_BASE_SIZE
			* (1.0 + float(combo_step - 1) * ZOMBIE_HIT_COMBO_STEP)
			* (1.18 if critical else 1.0)
		)
		# 贴肉朝向：命中点在躯干中心，另给一条「从怪体中心指向玩家」的外法线，
		# 火星才会擦着**朝向玩家那一面**飞出去，而不是绕一圈乱散。
		context["normal"] = _hit_surface_normal(target)
	_acquire_effect(asset_id, color, effect_size, position, context)
	_impact_feedback_count += 1
	_last_feedback = {
		"kind": "goo_hit" if asset_id == VfxPool3D.FX01_GOO_HIT else "melee_impact",
		"combo_step": combo_step,
		"position": position,
		"critical": critical,
	}


## 近战命中点所在**表面**的外法线（从怪体中心指向玩家）—— 僵尸受击件（FX01-20）v002 起
## 消费 `context.normal`，靠它把「擦出去的长条火星」对到朝向玩家那一面。
## 退化情形返回 `Vector3.UP`（特效侧本来就把零向量当 UP）。
func _hit_surface_normal(target: Node3D) -> Vector3:
	if player == null:
		return Vector3.UP
	var outward := player.global_position - target.global_position
	if outward.length_squared() < 0.0001:
		return Vector3.UP
	return outward.normalized()


func _acquire_effect(
	asset_id: StringName,
	color: Color,
	size: float,
	world_position: Vector3,
	context: Dictionary
) -> void:
	# FX01-* 战斗反馈特效：走 VfxPool3D 新体系（按 AssetID 路由）
	var vfx_pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if not vfx_pools.is_empty() and vfx_pools[0] is VfxPool3D:
		(vfx_pools[0] as VfxPool3D).acquire(asset_id, world_position, color, size, context)
		return
	# 兼容旧 CombatEffectPool3D（待 14.6 §6 迁移完成后删除）
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire(str(asset_id).to_lower(), color, size, world_position, "", context)
		return
	if get_tree().current_scene == null:
		return
	# 直接独立实例化作为后备
	var effect := VfxPool3D.create_unpooled(asset_id)
	if effect != null:
		get_tree().current_scene.add_child(effect)
		effect.activate(world_position, color, size, context)


func _is_wall_occluded(from: Vector3, to: Vector3) -> bool:
	var world := player.get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	return not world.direct_space_state.intersect_ray(query).is_empty()


func begin_trigger() -> bool:
	if not _can_start_attack(): return false
	if player.weapon.gun_id == "bp_baseball_bat" or _phase != "ready":
		return request_attack()
	_trigger_held = true
	_charge_ratio = 0.0
	_combo_index = 0
	_attack_mode = "charging"
	_machine.transition_to("charging")
	return true

func release_trigger() -> void:
	_trigger_held = false
	if not _can_continue_attack():
		cancel("release_invalid")
		return
	if _phase == "spinning":
		_stop_sustained_effect()
		_step_snapshot["recovery_s"] = 0.30
		_machine.transition_to("recovery")
	elif _phase == "charging":
		_stop_sustained_effect()
		_attack_mode = "charged" if player.weapon.gun_id == "bp_waraxe" and _charge_ratio >= 0.30 else "normal"
		_begin_combo_step()
		if _attack_mode == "charged":
			_step_snapshot["damage_scale"] = lerpf(1.2,2.0,_charge_ratio)
			_step_snapshot["knockback_scale"] = lerpf(1.4,2.6,_charge_ratio)
			_step_snapshot["windup_s"] = 0.08
			_step_snapshot["active_s"] = 0.18
			_step_snapshot["recovery_s"] = 0.70
			_phase_duration = 0.08

func enter_charging() -> void:
	_phase = "charging"
	_phase_elapsed = 0.0
	_phase_duration = AXE_CHARGE_SECONDS if player.weapon.gun_id == "bp_waraxe" else SWORD_HOLD_SECONDS
	if player.weapon.gun_id == "bp_waraxe":
		_start_sustained_effect(VfxPool3D.FX01_AXE_CHARGE,Color("ffc14a"),0.8)
	action_changed.emit(get_snapshot())

func tick_charging() -> void:
	_charge_ratio = get_phase_progress()
	if player.weapon.gun_id == "bp_greatblade" and _trigger_held and _charge_ratio >= 1.0:
		_machine.transition_to("spinning")

func enter_spinning() -> void:
	_phase = "spinning"
	_attack_mode = "spin"
	_spin_elapsed = 0.0
	_spin_hit_elapsed = 0.0
	_phase_duration = SPIN_CYCLE_SECONDS
	_phase_elapsed = 0.0
	_step_snapshot = {"damage_scale":0.55,"knockback_scale":0.35,"reach":float(_current_melee_profile().get("reach",2.65)),"arc_degrees":360.0,"recovery_s":0.30}
	_start_sustained_effect(VfxPool3D.FX01_BLADE_WHIRLWIND,Color("93eaff"),float(_step_snapshot.reach))
	action_changed.emit(get_snapshot())

func tick_spinning(delta: float) -> void:
	_spin_elapsed += delta
	_spin_hit_elapsed += delta
	_phase_elapsed = fposmod(_spin_elapsed, SPIN_CYCLE_SECONDS)
	if _spin_hit_elapsed >= SPIN_HIT_SECONDS:
		_spin_hit_elapsed = fposmod(_spin_hit_elapsed, SPIN_HIT_SECONDS)
		_attack_sequence += 1
		_attack_instance_id = "spin:%d" % _attack_sequence
		_hit_target_ids.clear()
		_active_resolved = false
		_hit_stop_requested = false
		resolve_active_hit()

func movement_multiplier() -> float:
	if _phase == "spinning": return 0.45
	if _phase == "charging": return 0.55
	return 1.0

func _start_sustained_effect(asset_id: StringName, color: Color, size: float) -> void:
	_stop_sustained_effect()
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		_sustained_effect = pool.acquire(asset_id,player.global_position,color,size,{"follow":player,"follow_local_offset":Vector3(0,.65,0),"duration":86400.0})

func _stop_sustained_effect() -> void:
	if is_instance_valid(_sustained_effect): _sustained_effect.finish()
	_sustained_effect = null

func _exit_tree() -> void:
	_stop_sustained_effect()
