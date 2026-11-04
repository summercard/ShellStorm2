class_name EliteArmsTakerCombat
extends RefCounted
## Enemy3D owns the action timeline; the visual prefab only consumes its context.

const ID := "elite_arms_taker"
const BODY_SCALE_MULTIPLIER := 2.5
const FOOT_INSET_M := 0.001
const CONFISCATION_CHANCE := 0.50
const INITIAL_HP_MULTIPLIER := 20
const RETREAT_DAMAGE_RATIO := 0.10
const ATTACK_CLIP := "attack_light"
const HIT_TIME := 40.0 / 30.0
const RECOVERY_TIME := 44.0 / 30.0
const ACTION_DURATION := 80.0 / 30.0
const HURT_DURATION := 2.0
const DEATH_DURATION := 4.6
const ACTION_STATES := ["telegraph", "attack", "recovery"]
const SWIPE := "swipe"
const HEAVY := "heavy"
const ELECTRIC := "electric"
const PHASE := "phase"
const ACTION_TIMING := {
	SWIPE: Vector3(HIT_TIME, RECOVERY_TIME, ACTION_DURATION),
	HEAVY: Vector3(0.72, 0.86, 1.65),
	ELECTRIC: Vector3(0.70, 0.76, 1.20),
}
const HEAVY_FRAME := 8.0 / 30.0
const CHASE_TIMEOUT := 6.0
const PHASE_WINDUP := 0.45
const PHASE_HIDDEN_TIME := 3.0
const PHASE_REENTRY := 0.45
const PHASE_RETRY_TIME := 0.25
const ELECTRIC_MIN_RANGE := 4.0
const ELECTRIC_RANGE := 12.0
const ELECTRIC_HEIGHT_LIMIT := 1.5
const ELECTRIC_COOLDOWN := 8.0
const ELECTRIC_COLOR := Color(0.18, 0.81, 1.0)
const WORLD_MASK := 1

var owner_enemy: Enemy3D
var elapsed := 0.0
var active := false
var committed := false
var cast_direction := Vector3.FORWARD
var attack_attempts := 0
var damage_events := 0
var action := SWIPE
var chase_elapsed := 0.0
var electric_cooldown := 0.0
var phased_out := false
var phase_intangible := false
var _next_action := SWIPE
var _melee_commits := 0
var _cast_floor := Vector3.ZERO
var _electric_target: WeakRef
var _reticle: VfxEffectBase3D
var _phase_retry := 0.0
var _phase_hit_layer := 0
var _phase_body_layer := 0
var _phase_body_mask := 0
var _phase_bar_visible := false
var _phase_damageable := false

func _init(enemy: Enemy3D) -> void:
	owner_enemy = enemy

func begin() -> void:
	action = _next_action
	_next_action = SWIPE
	elapsed = 0.0
	active = true
	committed = false
	cast_direction = -owner_enemy.global_basis.z.normalized()
	owner_enemy._stop_planar()
	if action == ELECTRIC:
		_begin_floor_marker()

func cancel() -> void:
	if phase_intangible:
		_end_phase()
	_finish_floor_marker()
	_electric_target = null
	active = false
	committed = false
	elapsed = 0.0
	chase_elapsed = 0.0
	_phase_retry = 0.0

func on_transition(previous: String, current: String) -> void:
	if current == "telegraph":
		chase_elapsed = 0.0
		begin()
	elif previous in ACTION_STATES and current not in ACTION_STATES:
		cancel()
	elif current in ["dormant", "dead", "stagger", "return", "idle", "patrol"]:
		cancel()

func try_chase_action(to_target: Vector3, distance: float, delta: float) -> bool:
	var target := owner_enemy._target
	if not is_instance_valid(target) or float(target.get("current_hp")) <= 0.0:
		return false
	var facing := distance <= 0.01 or (-owner_enemy.global_basis.z).normalized().dot(to_target / distance) >= 0.9
	if owner_enemy._attack_timer <= 0.0 and facing:
		if distance <= owner_enemy.attack_range:
			if owner_enemy._has_line_of_sight(target) and _request_action(HEAVY if (_melee_commits + 1) % 3 == 0 else SWIPE, "melee"):
				return true
		elif _lock_electric_target(target, distance):
			if _request_action(ELECTRIC, "ranged"):
				return true
			_electric_target = null
	chase_elapsed = minf(CHASE_TIMEOUT, chase_elapsed + delta)
	if chase_elapsed + 0.0001 >= CHASE_TIMEOUT:
		_phase_retry -= delta
		if _phase_retry <= 0.0:
			_phase_retry = PHASE_RETRY_TIME
			if _find_phase_destination(target) is Vector3:
				_next_action = PHASE
				owner_enemy.transition_to("telegraph", "arms_taker_phase_windup")
				return true
	return false

func _request_action(kind: String, channel: String) -> bool:
	if MonsterAIManager != null and not MonsterAIManager.request_attack_token(owner_enemy, owner_enemy._target, channel):
		owner_enemy._last_attack_result = "token_wait"
		return false
	_next_action = kind
	owner_enemy._last_attack_result = "token_granted"
	return owner_enemy.transition_to("telegraph")

func _lock_electric_target(target: Node3D, distance: float) -> bool:
	if electric_cooldown > 0.0 or distance < ELECTRIC_MIN_RANGE or distance > ELECTRIC_RANGE:
		return false
	if not is_instance_valid(target) or float(target.get("current_hp")) <= 0.0:
		return false
	var caster_y := owner_enemy.global_position.y
	if absf(target.global_position.y - caster_y) > ELECTRIC_HEIGHT_LIMIT or not owner_enemy._has_line_of_sight(target):
		return false
	var hit := _floor_below(target.global_position, 0.12, 3.2, target as PhysicsBody3D)
	if hit.is_empty():
		return false
	var floor_point := hit["position"] as Vector3
	if absf(floor_point.y - caster_y) > ELECTRIC_HEIGHT_LIMIT:
		return false
	_cast_floor = floor_point
	_electric_target = weakref(target)
	return true

func _begin_floor_marker() -> void:
	_reticle = VfxPool3D.create_unpooled(VfxPool3D.FX01_ARMS_TAKER_FLOOR_CAST)
	if _reticle != null:
		_reticle.top_level = true
		owner_enemy.add_child(_reticle)
		_reticle.activate(_cast_floor + Vector3.UP * 0.035, ELECTRIC_COLOR, 1.0, {"duration": ACTION_TIMING[ELECTRIC].x})

func _finish_floor_marker() -> void:
	if is_instance_valid(_reticle):
		_reticle.finish()
	_reticle = null

func tick(delta: float) -> bool:
	electric_cooldown = maxf(0.0, electric_cooldown - delta)
	if is_zero_approx(electric_cooldown):
		electric_cooldown = 0.0
	if owner_enemy.ai_state == "stagger":
		commit_motion(delta, true)
		if owner_enemy._state_time >= HURT_DURATION:
			owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "arms_taker_hurt_finished")
		return true
	if owner_enemy.ai_state not in ACTION_STATES:
		return false
	if not active:
		owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "arms_taker_no_action")
		return true
	if action == PHASE:
		return _tick_phase(delta)
	var target := _electric_target.get_ref() as Node3D if action == ELECTRIC and _electric_target != null else owner_enemy._target
	if not committed and (not is_instance_valid(target) or not target.is_inside_tree() or float(target.get("current_hp")) <= 0.0):
		owner_enemy.transition_to("search", "arms_taker_target_lost")
		return true
	var timing: Vector3 = ACTION_TIMING[action]
	elapsed = minf(timing.z, elapsed + maxf(0.0, delta))
	commit_motion(delta)
	if elapsed >= timing.x and not committed:
		owner_enemy.transition_to("attack", "arms_taker_active_frames")
		committed = true
		commit_attack()
		# A reflected hit or a player kill can synchronously end this action.
		if not active:
			return true
	if elapsed >= timing.y and owner_enemy.ai_state != "recovery":
		owner_enemy.transition_to("recovery", "arms_taker_followthrough")
	if elapsed >= timing.z:
		owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "idle", "arms_taker_action_finished")
	return true

func _tick_phase(delta: float) -> bool:
	elapsed += delta
	match owner_enemy.ai_state:
		"telegraph":
			commit_motion(delta)
			if elapsed + 0.0001 >= PHASE_WINDUP:
				_begin_phase()
				owner_enemy.transition_to("attack", "arms_taker_phase_hidden")
				elapsed = 0.0
		"attack":
			if elapsed + 0.0001 >= PHASE_HIDDEN_TIME:
				_phase_retry -= delta
				if _phase_retry <= 0.0:
					_phase_retry = PHASE_RETRY_TIME
					var target := owner_enemy._target
					if not is_instance_valid(target):
						target = owner_enemy._get_player_in_proximity(48.0)
					var destination: Variant = _find_phase_destination(target)
					if destination is Vector3:
						var landing: Vector3 = destination
						owner_enemy.global_position = landing
						owner_enemy.velocity = Vector3.ZERO
						owner_enemy._external_velocity = Vector3.ZERO
						var toward := target.global_position - landing
						owner_enemy.rotation.y = atan2(-toward.x, -toward.z)
						phased_out = false
						owner_enemy.visible = true
						owner_enemy.transition_to("recovery", "arms_taker_phase_reentry")
						elapsed = 0.0
		"recovery":
			if elapsed + 0.0001 >= PHASE_REENTRY:
				_finish_phase()
	return true

func _finish_phase() -> void:
	_end_phase()
	var target := owner_enemy._target
	if not is_instance_valid(target):
		target = owner_enemy._get_player_in_proximity(ELECTRIC_RANGE + ELECTRIC_HEIGHT_LIMIT)
	if is_instance_valid(target):
		var offset := target.global_position - owner_enemy.global_position
		if _lock_electric_target(target, Vector2(offset.x, offset.z).length()):
			owner_enemy.rotation.y = atan2(-offset.x, -offset.z)
			_next_action = ELECTRIC
			# This follow-up is part of the independent elite action. Ordinary waves keep their attack slot.
			owner_enemy.transition_to("telegraph", "arms_taker_phase_followup")
			return
	owner_enemy.transition_to("chase" if is_instance_valid(owner_enemy._target) else "search", "arms_taker_phase_complete")

func _begin_phase() -> void:
	phase_intangible = true
	phased_out = true
	_phase_retry = 0.0
	owner_enemy.velocity = Vector3.ZERO
	_phase_body_layer = owner_enemy.collision_layer
	_phase_body_mask = owner_enemy.collision_mask
	owner_enemy.collision_layer = 0
	owner_enemy.collision_mask = 0
	var hit_body := owner_enemy.get_animated_hit_volume_body()
	if is_instance_valid(hit_body):
		_phase_hit_layer = hit_body.collision_layer
		hit_body.collision_layer = 0
	_phase_damageable = owner_enemy.is_in_group("damageable_3d")
	if _phase_damageable:
		owner_enemy.remove_from_group("damageable_3d")
	if is_instance_valid(owner_enemy._overhead_health_root):
		_phase_bar_visible = owner_enemy._overhead_health_root.visible
		owner_enemy._overhead_health_root.hide()
	owner_enemy.hide()

func _end_phase() -> void:
	var was_hidden := phased_out
	phased_out = false
	phase_intangible = false
	if owner_enemy.ai_state == "dead" or not owner_enemy.is_inside_tree():
		return
	owner_enemy.collision_layer = _phase_body_layer
	owner_enemy.collision_mask = _phase_body_mask
	var hit_body := owner_enemy.get_animated_hit_volume_body()
	if is_instance_valid(hit_body):
		hit_body.collision_layer = _phase_hit_layer
	if _phase_damageable:
		owner_enemy.add_to_group("damageable_3d")
	if is_instance_valid(owner_enemy._overhead_health_root):
		owner_enemy._overhead_health_root.visible = _phase_bar_visible
	if was_hidden:
		owner_enemy.visible = owner_enemy.is_runtime_ai_active()

func _floor_below(point: Vector3, above: float, below: float, ignore: PhysicsBody3D = null) -> Dictionary:
	var exclude: Array[RID] = [owner_enemy.get_rid()]
	if is_instance_valid(ignore):
		exclude.append(ignore.get_rid())
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * above, point - Vector3.UP * below, WORLD_MASK, exclude)
	var hit := owner_enemy.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.65 or hit.get("collider") is CharacterBody3D:
		return {}
	return hit

func _find_phase_destination(target: Node3D) -> Variant:
	var camera := owner_enemy.get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(target) or float(target.get("current_hp")) <= 0.0:
		return null
	var anchor := target.global_position
	anchor.y = owner_enemy.global_position.y
	var half_width := maxf(owner_enemy.get_world_body_radius(), 1.15 * owner_enemy.scale.x)
	var height := maxf(owner_enemy.get_world_body_height(), 3.65 * owner_enemy.scale.y)
	var shape := CylinderShape3D.new()
	shape.radius = owner_enemy.get_world_body_radius()
	shape.height = owner_enemy.get_world_body_height()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WORLD_MASK | Enemy3D.ENEMY_BULLET_LAYER
	query.exclude = [owner_enemy.get_rid()]
	var hit_body := owner_enemy.get_animated_hit_volume_body()
	if is_instance_valid(hit_body):
		query.exclude.append(hit_body.get_rid())
	var toward_camera := camera.global_position - anchor
	var away_angle := atan2(-toward_camera.z, -toward_camera.x)
	var planes := camera.get_frustum()
	var frustum_center := camera.project_position(camera.get_viewport().get_visible_rect().size * 0.5, (camera.near + camera.far) * 0.5)
	for radius in [5.0, 8.0, 12.0, 16.0, 22.0, 30.0]:
		for index in 12:
			var angle := away_angle + TAU * float(index) / 12.0
			var point := anchor + Vector3(cos(angle), 0.0, sin(angle)) * float(radius)
			if owner_enemy._has_room_bounds:
				point = owner_enemy._clamp_into_room(point, 0.08)
			elif point.distance_to(owner_enemy._home_position) > 12.0:
				continue
			if point.distance_to(anchor) < 4.0 or point.distance_to(owner_enemy.global_position) < 1.2:
				continue
			var floor_hit := _floor_below(point, 0.55, 0.65, target as PhysicsBody3D)
			if floor_hit.is_empty():
				continue
			point = floor_hit["position"] as Vector3
			point.y += 0.035
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (shape.height * 0.5 + 0.015))
			if not owner_enemy.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				continue
			var half_bounds := Vector3(half_width, height * 0.5, half_width)
			if _outside_frustum(point + Vector3.UP * half_bounds.y, half_bounds, planes, frustum_center):
				return point
			if target is Player3D and _occluded_from_player_and_camera(point, height, half_width, target as Player3D, camera):
				return point
	return null

func _outside_frustum(center: Vector3, half_bounds: Vector3, planes: Array[Plane], interior: Vector3) -> bool:
	for plane in planes:
		var extent := plane.normal.abs().dot(half_bounds)
		var orientation := 1.0 if plane.distance_to(interior) <= 0.0 else -1.0
		if plane.distance_to(center) * orientation > extent:
			return true
	return false

func _occluded_from_player_and_camera(point: Vector3, height: float, width: float, target: Player3D, camera: Camera3D) -> bool:
	var space := owner_enemy.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(target.global_position + Vector3.UP * 0.8, point, WORLD_MASK, [target.get_rid(), owner_enemy.get_rid()])
	for source in [query.from, camera.global_position]:
		query.from = source
		for y in [0.12, height * 0.5, height]:
			for offset in [Vector3.ZERO, Vector3(width, 0, width), Vector3(-width, 0, width), Vector3(width, 0, -width), Vector3(-width, 0, -width)]:
				query.to = point + Vector3.UP * float(y) + offset
				var collider := space.intersect_ray(query).get("collider") as Node
				if not collider is StaticBody3D and not collider is GridMap and not collider is CSGShape3D:
					return false
	return true

func commit_motion(delta: float, hurt := false) -> void:
	# External velocity is a velocity, not a per-frame impulse to accumulate.
	var motion := owner_enemy._external_velocity
	if hurt and owner_enemy._state_time < float(owner_enemy._active_profile.get("stagger", 0.16)):
		motion += owner_enemy._last_hit_direction * owner_enemy._hit_knockback
	owner_enemy._steer_planar(motion, 1.0)
	owner_enemy._commit_motion(delta)

func commit_attack() -> void:
	attack_attempts += 1
	owner_enemy._attack_timer = owner_enemy._resolve_attack_cooldown()
	owner_enemy._last_attack_result = "miss"
	if action == ELECTRIC:
		_commit_electric()
		return
	_melee_commits += 1
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
	var heavy := action == HEAVY
	var arc := 0.30 if heavy else 0.50
	if offset.length() <= owner_enemy.attack_range + 0.65 and direction.dot(cast_direction) >= arc and target.has_method("take_damage"):
		var previous_hp := int(target.get("current_hp"))
		if target.has_method("notify_attacked_by"):
			target.call("notify_attacked_by", owner_enemy)
		var damage := roundi(owner_enemy.contact_damage * 1.35) if heavy else owner_enemy.contact_damage
		target.call("take_damage", damage, false, direction)
		damage_events += 1
		owner_enemy._last_attack_result = "hit"
		if is_instance_valid(target) and int(target.get("current_hp")) < previous_hp and randf() < CONFISCATION_CHANCE:
			var scene := owner_enemy.get_tree().current_scene
			if scene != null and scene.has_method("collect_elite_rent"):
				scene.call("collect_elite_rent", owner_enemy, target)
	if owner_enemy.elite_modifier_id == "Elite.WeaponParasite" and target.has_method("apply_silence"):
		target.call("apply_silence", 1.8)

func _commit_electric() -> void:
	electric_cooldown = ELECTRIC_COOLDOWN
	_finish_floor_marker()
	var origin := owner_enemy.global_position + Vector3.UP * (2.55 * owner_enemy.scale.y)
	var visual := owner_enemy.avatar.get_animated_elite_root()
	if is_instance_valid(visual):
		origin = visual.call("get_screen_emitter_position")
	var direction := (_cast_floor - origin).normalized()
	owner_enemy._fire_projectile(direction, owner_enemy.contact_damage, ELECTRIC_COLOR, false, {
		"floor_burst": {"floor_y": _cast_floor.y, "count": 8, "speed": 4.4, "damage_ratio": 0.50, "lifetime": 2.1, "root_seconds": 1.0},
		"visual_id": VfxPool3D.FX01_BULLET_ELECTRIC,
		"home_lifetime": 1.6,
		"ignore_body": _electric_target.get_ref() if _electric_target != null else null,
	}, 14.0, origin + direction * 0.15)
	owner_enemy._last_attack_result = "fired"

func presentation_context() -> Dictionary:
	var state := owner_enemy.ai_state
	var clip := "idle"
	var time := owner_enemy._state_time
	var glitch := 0.0
	var charge := 0.0
	var timing: Vector3 = ACTION_TIMING.get(action, Vector3.ZERO)
	if active and state in ACTION_STATES:
		match action:
			SWIPE:
				clip = ATTACK_CLIP
				time = elapsed
			HEAVY:
				clip = "attack_heavy"
				if elapsed <= timing.x:
					time = HEAVY_FRAME * elapsed / timing.x
				else:
					time = lerpf(HEAVY_FRAME, 1.1, inverse_lerp(timing.x, timing.z, elapsed))
			ELECTRIC:
				charge = smoothstep(0.0, timing.x, elapsed) if not committed else 1.0 - smoothstep(timing.x, timing.z, elapsed)
			PHASE:
				if state == "telegraph":
					glitch = smoothstep(0.0, PHASE_WINDUP, elapsed)
				elif state == "recovery":
					glitch = 1.0 - smoothstep(0.0, PHASE_REENTRY, elapsed)
	elif state == "stagger":
		clip = "hit"
	elif state == "dead":
		clip = "death"
	elif state in ["patrol", "chase", "search", "return"]:
		clip = "locomotion"
	var speed := Vector2(owner_enemy.get_real_velocity().x, owner_enemy.get_real_velocity().z).length()
	var touching_floor := owner_enemy.is_on_floor()
	var grounded := touching_floor and state != "dead"
	var floor_height := owner_enemy.global_position.y
	if touching_floor:
		var cylinder := owner_enemy.collision_shape.shape as CylinderShape3D
		floor_height = owner_enemy.collision_shape.global_position.y - cylinder.height * owner_enemy.scale.y * 0.5 - owner_enemy.safe_margin
		for index in owner_enemy.get_slide_collision_count():
			var collision := owner_enemy.get_slide_collision(index)
			if collision.get_normal().dot(Vector3.UP) > cos(owner_enemy.floor_max_angle):
				floor_height = collision.get_position().y
				break
	return {"schema":1, "state":state, "action_id":clip, "time":time, "tactic":action,
		"glitch":glitch, "screen_charge":charge, "phased_out":phased_out, "chase_elapsed":chase_elapsed,
		"speed":speed, "base_speed":owner_enemy.get_effective_move_speed(), "actor_scale":owner_enemy.scale.x,
		"grounded":grounded, "floor_height":floor_height, "foot_inset":FOOT_INSET_M,
		"floor_offset":floor_height - owner_enemy.global_position.y,
		"action_active":active, "action_elapsed":elapsed, "committed":committed,
		"hit_time":timing.x, "recovery_time":timing.y, "action_duration":timing.z,
		"attack_attempts":attack_attempts, "damage_events":damage_events}
