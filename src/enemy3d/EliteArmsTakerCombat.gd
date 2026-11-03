class_name EliteArmsTakerCombat
extends RefCounted
## Enemy3D owns the action timeline; the visual prefab only consumes its context.

const ID := "elite_arms_taker"
const ATTACK_CLIP := "attack_light"
const HIT_TIME := 40.0 / 30.0
const RECOVERY_TIME := 44.0 / 30.0
const ACTION_DURATION := 80.0 / 30.0
const HURT_DURATION := 2.0
const DEATH_DURATION := 4.6
const ACTION_STATES := ["telegraph", "attack", "recovery"]

var owner_enemy: Enemy3D
var elapsed := 0.0
var active := false
var committed := false
var cast_direction := Vector3.FORWARD
var attack_attempts := 0
var damage_events := 0

func _init(enemy: Enemy3D) -> void:
	owner_enemy = enemy

func begin() -> void:
	elapsed = 0.0
	active = true
	committed = false
	cast_direction = -owner_enemy.global_basis.z.normalized()
	# Autonomous melee lunges would add a second movement to the authored swipe.
	owner_enemy._stop_planar()

func cancel() -> void:
	active = false
	committed = false
	elapsed = 0.0

func on_transition(previous: String, current: String) -> void:
	if current == "telegraph":
		begin()
	elif previous in ACTION_STATES and current not in ACTION_STATES:
		cancel()
	elif current in ["dormant", "dead", "stagger"]:
		cancel()

func tick(delta: float) -> bool:
	if owner_enemy.ai_state == "stagger":
		owner_enemy._brake_planar(delta * 18.0)
		owner_enemy._push_planar(owner_enemy._external_velocity)
		owner_enemy._commit_motion(delta)
		if owner_enemy._state_time >= HURT_DURATION:
			owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "arms_taker_hurt_finished")
		return true
	if owner_enemy.ai_state not in ACTION_STATES:
		return false
	if not active:
		owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "arms_taker_no_action")
		return true
	var target := owner_enemy._target
	if not committed and (not is_instance_valid(target) or float(target.get("current_hp")) <= 0.0):
		owner_enemy.transition_to("search", "arms_taker_target_lost")
		return true
	elapsed = minf(ACTION_DURATION, elapsed + maxf(0.0, delta))
	owner_enemy._brake_planar(delta * 18.0)
	owner_enemy._push_planar(owner_enemy._external_velocity)
	owner_enemy._commit_motion(delta)
	if elapsed >= HIT_TIME and not committed:
		owner_enemy.transition_to("attack", "arms_taker_active_frames")
		committed = true
		commit_attack()
	if elapsed >= RECOVERY_TIME and owner_enemy.ai_state != "recovery":
		owner_enemy.transition_to("recovery", "arms_taker_followthrough")
	if elapsed >= ACTION_DURATION:
		owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "arms_taker_action_finished")
	return true

func commit_attack() -> void:
	attack_attempts += 1
	owner_enemy._attack_timer = owner_enemy._resolve_attack_cooldown()
	owner_enemy._last_attack_result = "miss"
	var target := owner_enemy._target
	if not is_instance_valid(target) or float(target.get("current_hp")) <= 0.0:
		return
	var offset := target.global_position - owner_enemy.global_position
	if absf(offset.y) > 1.8:
		return
	offset.y = 0.0
	var direction := offset.normalized() if offset.length_squared() > 0.001 else cast_direction
	if not owner_enemy._has_line_of_sight(target):
		return
	if offset.length() <= owner_enemy.attack_range + 0.65 and direction.dot(cast_direction) >= 0.5 and target.has_method("take_damage"):
		if target.has_method("notify_attacked_by"):
			target.call("notify_attacked_by", owner_enemy)
		target.call("take_damage", owner_enemy.contact_damage, false, direction)
		damage_events += 1
		owner_enemy._last_attack_result = "hit"
	# Preserve the existing weapon_phase_swap count, level scaling and projectile rules.
	owner_enemy._apply_unique_elite_attack_behavior(cast_direction)
	if owner_enemy.elite_modifier_id == "Elite.WeaponParasite" and target.has_method("apply_silence"):
		target.call("apply_silence", 1.8)

func presentation_context() -> Dictionary:
	var state := owner_enemy.ai_state
	var action := "idle"
	var time := owner_enemy._state_time
	if active and state in ACTION_STATES:
		action = ATTACK_CLIP
		time = elapsed
	elif state == "stagger":
		action = "hit"
	elif state == "dead":
		action = "death"
	elif state in ["patrol", "chase", "search", "return"]:
		action = "locomotion"
	var speed := Vector2(owner_enemy.get_real_velocity().x, owner_enemy.get_real_velocity().z).length()
	return {"schema":1, "state":state, "action_id":action, "time":time,
		"speed":speed, "base_speed":owner_enemy.get_effective_move_speed(), "actor_scale":owner_enemy.scale.x,
		"action_active":active, "action_elapsed":elapsed, "committed":committed,
		"hit_time":HIT_TIME, "recovery_time":RECOVERY_TIME, "action_duration":ACTION_DURATION,
		"attack_attempts":attack_attempts, "damage_events":damage_events}
