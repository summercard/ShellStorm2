class_name MonitorBossCombat
extends RefCounted
## Enemy3D-owned skill timeline. Presentation never executes damage or state transitions.

const ID := "boss_monitor002"
const SKILLS := {
	"monitor_keyboard": {"clip":"melee_keyboard", "windup":32.0/30.0, "end":1.8, "radius":1.65, "offset":3.2, "damage":1.0},
	"monitor_cable": {"clip":"melee_cable", "windup":0.8, "end":2.0, "radius":6.0, "offset":0.0, "damage":0.833333},
	"monitor_spin_slam": {"clip":"heavy_spin_slam", "windup":64.0/30.0, "end":3.2, "radius":5.2, "offset":1.4, "damage":1.5},
	"monitor_ground_current": {"clip":"special_prepare", "windup":1.8, "end":0.0, "radius":7.0, "offset":0.0, "damage":0.5},
}
var owner_enemy: Enemy3D
var skill_id := ""
var elapsed := 0.0
var cast_direction := Vector3.FORWARD
var cast_origin := Vector3.ZERO
var contact_point := Vector3.ZERO
var hit_ids: Dictionary = {}
var committed := false
var pulse_index := 0
var electric_cooldown := 0.0
var poise_damage := 0.0
var seated := false
var turning := false
var turn_elapsed := 0.0
var turn_start := 0.0
var turn_delta := 0.0
var turn_clip := "turn_left"
var damage_events := 0
var _phase_at_cast := 1

func _init(enemy: Enemy3D) -> void:
	owner_enemy = enemy

func choose_skill() -> String:
	var chosen := owner_enemy._next_boss_skill()
	if not SKILLS.has(chosen):
		return ""
	if chosen == "monitor_ground_current" and electric_cooldown > 0.0:
		return "monitor_cable"
	if chosen == "monitor_keyboard" and is_instance_valid(owner_enemy._target):
		var distance := owner_enemy.global_position.distance_to(owner_enemy._target.global_position)
		if distance < 1.55 or distance > 4.85:return "monitor_cable"
	return chosen

func begin() -> void:
	skill_id = choose_skill()
	if skill_id.is_empty():return
	elapsed = 0.0
	committed = false
	pulse_index = 0
	hit_ids.clear()
	turning = false
	_phase_at_cast = owner_enemy.boss_phase
	cast_origin = owner_enemy.global_position
	cast_direction = -owner_enemy.global_basis.z.normalized()
	contact_point = cast_origin + cast_direction * float(SKILLS[skill_id].offset)
	if skill_id == "monitor_ground_current":
		# Authored inserted connector offset, in actor space; root remains planted.
		contact_point = owner_enemy.to_global(Vector3(-2.395, 0.0, -1.749))
		contact_point.y = cast_origin.y
	owner_enemy._attack_timer = 0.65

func cancel() -> void:
	skill_id = ""
	committed = false
	hit_ids.clear()
	turning = false

func on_damage(amount: int, critical: bool, knockback: float, interrupt: bool) -> void:
	if owner_enemy.ai_state == "dead" or owner_enemy.current_hp <= 0:
		cancel()
		return
	if owner_enemy.ai_state == "stagger" and seated:
		return # Continue taking damage without restarting seated animation.
	poise_damage += amount
	var threshold := float(owner_enemy.max_hp) * 0.08
	var break_current := skill_id == "monitor_ground_current" and elapsed >= 1.8 and (critical or knockback >= 0.8)
	if poise_damage >= threshold or break_current:
		seated = true
		poise_damage = 0.0
		cancel()
		owner_enemy._state_time = 0.0
		owner_enemy.transition_to("stagger", "monitor_seated_stun")
	elif interrupt and owner_enemy.ai_state not in ["telegraph", "attack", "recovery", "stagger"]:
		seated = false
		owner_enemy.transition_to("stagger", "monitor_hurt")

func tick(delta: float) -> bool:
	electric_cooldown = maxf(0.0, electric_cooldown-delta)
	if owner_enemy.ai_state == "stagger":
		owner_enemy._brake_planar(delta*18.0)
		owner_enemy._commit_motion(delta)
		if owner_enemy._state_time >= (4.8 if seated else 0.5):
			seated = false
			owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "monitor_stagger_finished")
		return true
	if owner_enemy.ai_state not in ["telegraph", "attack", "recovery"]:
		return false
	if skill_id.is_empty():
		owner_enemy.transition_to("chase", "monitor_missing_skill")
		return true
	elapsed += delta
	owner_enemy._brake_planar(delta*18.0)
	owner_enemy._commit_motion(delta)
	var spec: Dictionary = SKILLS[skill_id]
	var windup := float(spec.windup)
	var total := float(spec.end)
	if skill_id == "monitor_ground_current":
		var channel_end := 1.8 + channel_duration()
		total = channel_end + 0.9
		if elapsed >= 1.8 and elapsed < channel_end:
			while pulse_index < int(channel_duration()/0.8) and elapsed >= 1.8 + pulse_index*0.8:
				pulse_index += 1
				hit_ids.clear()
				deal_damage()
		if elapsed >= channel_end and owner_enemy.ai_state != "recovery":
			owner_enemy.transition_to("recovery", "monitor_current_recover")
	else:
		var cable_window := skill_id == "monitor_cable" and elapsed <= 29.0/30.0
		if elapsed >= windup and (not committed or cable_window):
			deal_damage()
			committed = true
		if elapsed >= (29.0/30.0 if skill_id == "monitor_cable" else windup + 1.0/30.0) and owner_enemy.ai_state != "recovery":
			owner_enemy.transition_to("recovery", "monitor_attack_followthrough")
	if elapsed >= windup and owner_enemy.ai_state == "telegraph":
		owner_enemy.transition_to("attack", "monitor_active_frames")
	if elapsed >= total:
		if skill_id == "monitor_ground_current":electric_cooldown = 10.0
		cancel()
		owner_enemy._attack_timer = 0.65
		owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "monitor_skill_finished")
	return true

func channel_duration() -> float:
	return 1.6 + _phase_at_cast*0.8

func deal_damage() -> void:
	var spec: Dictionary = SKILLS[skill_id]
	var radius := float(spec.radius)
	var amount := maxi(1, roundi(owner_enemy.contact_damage*float(spec.damage)))
	for candidate in owner_enemy.get_tree().get_nodes_in_group("player_3d"):
		var player := candidate as Node3D
		if not is_instance_valid(player) or not player.has_method("take_damage") or hit_ids.has(player.get_instance_id()):continue
		var offset := player.global_position-contact_point
		if absf(offset.y) > 1.8:continue
		offset.y = 0.0
		if offset.length() > radius:continue
		if skill_id == "monitor_cable" and offset.length_squared() > 0.001 and cast_direction.dot(offset.normalized()) < cos(deg_to_rad(80.0)):continue
		if not owner_enemy._has_line_of_sight(player):continue
		hit_ids[player.get_instance_id()] = true
		if player.has_method("notify_attacked_by"):player.call("notify_attacked_by",owner_enemy)
		player.call("take_damage",amount,false,(player.global_position-cast_origin).normalized())
		damage_events += 1
	owner_enemy._last_attack_result = "hit" if not hit_ids.is_empty() else "miss"

func face_target(to_target: Vector3, delta: float) -> void:
	if to_target.length_squared() < 0.01:return
	var wanted := atan2(-to_target.x,-to_target.z)
	if not turning and absf(angle_difference(owner_enemy.rotation.y,wanted)) >= 0.9:
		turning = true;turn_start = owner_enemy.rotation.y
		turn_delta = clampf(angle_difference(turn_start,wanted),-PI/2.0,PI/2.0)
		turn_elapsed = 0.0;turn_clip = "turn_left" if turn_delta > 0.0 else "turn_right"
	if turning:
		turn_elapsed = minf(0.8,turn_elapsed+delta)
		owner_enemy.rotation.y = turn_start + turn_delta*smoothstep(0.0,0.8,turn_elapsed)
		if turn_elapsed >= 0.8:turning = false
	else:
		owner_enemy.rotation.y = lerp_angle(owner_enemy.rotation.y,wanted,minf(1.0,delta*4.0))

func presentation_context() -> Dictionary:
	var clip := "idle"
	var time := owner_enemy._state_time
	var state := owner_enemy.ai_state
	if state == "dead":clip = "dead"
	elif state == "stagger":
		clip = "hurt"
		if seated:
			if time < 1.4:clip = "stun_enter"
			elif time < 3.8:clip = "stun_loop";time -= 1.4
			else:clip = "stun_exit";time -= 3.8
	elif not skill_id.is_empty() and state in ["telegraph","attack","recovery"]:
		clip = str(SKILLS[skill_id].clip);time = elapsed
		if skill_id == "monitor_ground_current":
			if time < 1.2:clip = "special_prepare"
			elif time < 1.8:clip = "special_insert";time -= 1.2
			elif time < 1.8+channel_duration():clip = "special_channel";time -= 1.8
			else:clip = "special_recover";time -= 1.8+channel_duration()
	elif turning:
		clip = turn_clip;time = turn_elapsed
	elif state in ["patrol","chase","search","return"]:
		clip = "move" if Vector2(owner_enemy.velocity.x,owner_enemy.velocity.z).length() > 0.1 else "idle"
	var radius := float(SKILLS[skill_id].radius) if not skill_id.is_empty() else 0.0
	return {"schema":1,"action_id":clip,"time":time,"skill_id":skill_id,"phase":owner_enemy.boss_phase,
		"electric_active":skill_id == "monitor_ground_current" and elapsed >= 1.667 and elapsed < 1.8+channel_duration(),
		"telegraph_radius":radius if state == "telegraph" else 0.0,"contact_point":contact_point,
		"hit_flash":skill_id == "monitor_spin_slam" and elapsed >= 64.0/30.0 and elapsed < 65.0/30.0}
