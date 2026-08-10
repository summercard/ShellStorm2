class_name PlayerMeleeCombat3D
extends Node
## 与八态移动机并行的近战动作子状态机。连段编号是上下文，不复制状态类。

const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")

signal action_changed(snapshot: Dictionary)
signal hit_resolved(result: Dictionary)

const VALID_LOCOMOTION_STATES := ["idle", "moving"]

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


func configure(owner_player: Player3D) -> void:
	player = owner_player
	_machine = StateMachine.new()
	_machine.name = "MeleeActionStateMachine"
	_machine.owner_node = self
	add_child(_machine)
	_machine.register("ready", Player3DMeleeReadyState.new())
	_machine.register("windup", Player3DMeleeWindupState.new())
	_machine.register("active", Player3DMeleeActiveState.new())
	_machine.register("recovery", Player3DMeleeRecoveryState.new())
	_machine.configure_transition_map({
		"ready": ["windup"],
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
	if _phase == "ready":
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
	_phase = next_phase
	_phase_elapsed = 0.0
	_phase_duration = maxf(0.01, float(_step_snapshot.get("%s_s" % next_phase, 0.1)))
	action_changed.emit(get_snapshot())
	if next_phase == "active":
		_spawn_swing_feedback()


func finish_recovery() -> void:
	var combo_count := int(_current_melee_profile().get("combo_count", 0))
	if _queued_next and _combo_index + 1 < combo_count and _can_continue_attack():
		_combo_index += 1
		_begin_combo_step()
	else:
		_machine.transition_to("ready")


func resolve_active_hit() -> void:
	if player == null or _step_snapshot.is_empty() or _phase != "active":
		return
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
	return player.get_state_machine_state() in VALID_LOCOMOTION_STATES


func _apply_hit(target: Node3D, direction: Vector3) -> Dictionary:
	var weapon := player.weapon
	var damage_scale := float(_step_snapshot.get("damage_scale", 1.0))
	var critical := weapon.roll_melee_critical()
	var applied_damage := maxi(1, int(round(float(weapon.damage) * damage_scale)))
	target.call("take_damage", applied_damage, critical, direction)
	var knockback := float(_current_melee_profile().get("knockback", 4.0)) * float(_step_snapshot.get("knockback_scale", 1.0))
	if target.has_method("apply_melee_knockback"):
		target.call("apply_melee_knockback", direction, knockback, 0.20)
	return {
		"attack_instance_id": _attack_instance_id,
		"weapon_instance_id": player.get_equipped_weapon_instance_id(),
		"weapon_content_id": str(_current_melee_profile().get("content_id", "")),
		"combo_step": _combo_index + 1,
		"target_instance_id": target.get_instance_id(),
		"damage": applied_damage,
		"critical": critical,
		"knockback": knockback,
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
	_acquire_effect("slash", color, size, position, context)
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
	_acquire_effect("melee_impact", color, size, position, context)
	_impact_feedback_count += 1
	_last_feedback = {"kind": "melee_impact", "combo_step": combo_step, "position": position, "critical": critical}


func _acquire_effect(
	kind: String,
	color: Color,
	size: float,
	world_position: Vector3,
	context: Dictionary
) -> void:
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire(kind, color, size, world_position, "", context)
		return
	if get_tree().current_scene == null:
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure(kind, color, size, "", context)
	get_tree().current_scene.add_child(effect)
	effect.global_position = world_position


func _is_wall_occluded(from: Vector3, to: Vector3) -> bool:
	var world := player.get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	return not world.direct_space_state.intersect_ray(query).is_empty()
