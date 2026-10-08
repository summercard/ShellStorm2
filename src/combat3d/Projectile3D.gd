class_name Projectile3D
extends CharacterBody3D

signal hit_confirmed(target: Node, applied_damage: int, critical: bool)
signal expired
signal retired(projectile: Projectile3D)

const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d.tscn")
const BULLET_VISUAL_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn")
## 旧链（CombatEffectPool3D）图例：爆炸仍走旧链，待 14.6 §6 迁移完成后统一删除。
const LEGACY_EFFECT_EXPLOSION := &"explosion"

var direction := Vector3(0, 0, -1)
var speed := 24.0
var damage := 10
var critical := false
var hostile := false
var bullet_tags: Array[String] = []
var bullet_color := Color(0.45, 0.88, 1.0)
var shooter: Node3D = null
var fate_behavior: Dictionary = {}
# 命中击退强度（m/s）。默认 0 = 不让怪物位移；霰弹枪=0.8（轻微）。
# 由 WeaponModel3D / 发射逻辑在 spawn 时赋值，命中时透传给 take_projectile_damage。
var hit_knockback := 0.0
var _lifetime := 0.0
var _bounces_left := 0
var _pierces_left := 0
var _built := false
var _active := true
var _collision_shape: CollisionShape3D
var _visual: VfxEffectBase3D
var _returning := false
var _turret_active := false
var _turret_remaining := 0.0
var _turret_shot_timer := 0.0
var _attached_shot_timer := 0.0
var source_weapon_tree: WeaponAssemblyTree
var source_weapon: WeaponModel3D
var _flight_base_damage := 0
var _ungrown_damage := 0
var _hit_any := false
var _attached_hit_fired := false
var _return_hit_ids: Dictionary = {}
var _tracked_collision_exceptions: Array[PhysicsBody3D] = []


func configure(config: Dictionary) -> void:
	direction = (config.get("direction", direction) as Vector3).normalized()
	speed = float(config.get("speed", speed))
	damage = int(config.get("damage", damage))
	critical = bool(config.get("critical", critical))
	hostile = bool(config.get("hostile", hostile))
	bullet_tags.assign(config.get("tags", []))
	bullet_color = config.get("color", bullet_color) as Color
	shooter = config.get("shooter", shooter) as Node3D
	fate_behavior = (config.get("behavior", {}) as Dictionary).duplicate(true)
	var source_tree_value: Variant = fate_behavior.get("source_weapon_tree")
	var source_weapon_value: Variant = fate_behavior.get("source_weapon")
	source_weapon_tree = source_tree_value as WeaponAssemblyTree if is_instance_valid(source_tree_value) else null
	source_weapon = source_weapon_value as WeaponModel3D if is_instance_valid(source_weapon_value) else null
	_hit_any = false
	_ungrown_damage = damage
	_attached_hit_fired = false
	_return_hit_ids.clear()
	if bool(fate_behavior.get("size_growth", false)) and is_instance_valid(source_weapon_tree):
		var growth := minf(float(fate_behavior.get("max_fate_scale", 3.0)), 1.0 + source_weapon_tree.growth_stacks * float(fate_behavior.get("growth_per_hit", 0.2)))
		damage = maxi(1, int(damage * growth))
		var growth_size := minf(float(fate_behavior.get("max_fate_scale", 3.0)), 1.0 + source_weapon_tree.growth_stacks * float(fate_behavior.get("growth_scale_per_hit", 0.12)))
		fate_behavior["fate_scale"] = float(fate_behavior.get("fate_scale", 1.0)) * growth_size
	_flight_base_damage = damage
	damage = maxi(1, int(damage * float(fate_behavior.get("outbound_damage_multiplier", 1.0))))
	# 默认 0 = 不让怪物位移；霰弹枪在 WeaponModel3D 注入 0.8（轻微击退）。
	hit_knockback = float(config.get("hit_knockback", hit_knockback))
	_bounces_left = int(fate_behavior.get("bounce_count", 2 if bullet_tags.has("bounce") else 0))
	_pierces_left = int(fate_behavior.get("pierce_level", 2 if bullet_tags.has("piercing") else 0))
	_lifetime = 0.0
	_returning = false
	_turret_active = false
	_turret_remaining = 0.0
	_turret_shot_timer = 0.0
	_attached_shot_timer = 0.12
	if _built:
		_apply_visual_configuration()
		_sync_visual_orientation()


func activate(config: Dictionary, world_position: Vector3) -> void:
	configure(config)
	collision_mask = 1 if hostile else 5
	for exception in _tracked_collision_exceptions:
		# 对象池保留的碰撞例外可能指向已死亡并释放的上一任发射者；Godot
		# 会把服务端列表中的对象变成null占位，连枚举都会触发body=null报错。
		if is_instance_valid(exception):
			remove_collision_exception_with(exception)
	_tracked_collision_exceptions.clear()
	if shooter is PhysicsBody3D:
		_add_tracked_collision_exception(shooter as PhysicsBody3D)
	_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	global_position = world_position
	velocity = Vector3.ZERO
	_sync_visual_orientation()
	if _visual != null:
		_visual.activate(global_position, bullet_color, _visual_scale_factor(), {})
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 if hostile else 5
	if shooter is PhysicsBody3D:
		_add_tracked_collision_exception(shooter as PhysicsBody3D)
	_build_visual()
	_built = true
	_apply_visual_configuration()
	_sync_visual_orientation()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _turret_active:
		_tick_turret(delta)
		return
	_lifetime += delta
	# 子弹最大存活时间：默认下限 1.0 秒（23 m/s ≈ 23 m 理论射程）；
	# 命运卡行为可注入更长的 home_lifetime（如 fate_card 追踪弹 5 秒），只增不减于下限。
	var max_lifetime := maxf(1.0, float(fate_behavior.get("home_lifetime", 1.0)))
	if _lifetime >= max_lifetime:
		if not _returning and bool(fate_behavior.get("spawn_turret_on_land", false)):
			_become_turret()
		elif not _returning and bool(fate_behavior.get("home_on_land", false)):
			_begin_return()
		else:
			expired.emit()
			_retire()
		return
	_tick_attached_gun(delta)
	if _returning:
		if not is_instance_valid(shooter):
			_retire()
			return
		var destination := _return_destination()
		if global_position.distance_to(destination) <= maxf(0.72, speed * delta):
			if is_instance_valid(source_weapon):
				source_weapon.refund_projectile_ammo(int(fate_behavior.get("refund_ammo", 0)), source_weapon_tree)
			_retire()
			return
		direction = (destination - global_position).normalized()
	elif (bullet_tags.has("homing") or bool(fate_behavior.get("homing", false))) and not hostile:
		var target := _nearest_target()
		if target != null:
			var desired := (target.global_position + Vector3(0, 0.68, 0) - global_position).normalized()
			var homing_rate := lerpf(1.6, 7.0, clampf(float(fate_behavior.get("homing_strength", 0.3)), 0.0, 1.0))
			direction = direction.slerp(desired, minf(1.0, delta * homing_rate)).normalized()
	_sync_visual_orientation()
	velocity = direction * speed
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	# 物理命中上下文（先于反弹方向变化），供命中特效读取法线/接触点。
	var hit_context := {"normal": collision.get_normal(), "position": collision.get_position()}
	var collider := collision.get_collider() as Node
	if collider == shooter:
		return
	if collider != null and collider.has_method("take_damage"):
		_hit_target(collider, hit_context)
		return
	_hit_surface(collision.get_normal(), hit_context)


func _hit_target(collider: Node, hit_context: Dictionary = {}) -> void:
	if not _active:
		return
	if _returning and (damage <= 0 or _return_hit_ids.has(collider.get_instance_id())):
		return
	if collider != null:
		if collider.has_method("can_absorb_projectile") and bool(collider.call("can_absorb_projectile", bullet_tags)):
			if collider.has_method("on_projectile_absorbed"):
				collider.call("on_projectile_absorbed", damage)
			_spawn_effect(VfxPool3D.FX01_IMPACT, global_position, bullet_color, 1.25, hit_context)
			_retire()
			return
		if bool(fate_behavior.get("size_growth", false)) and is_instance_valid(source_weapon_tree):
			var growth := minf(float(fate_behavior.get("max_fate_scale", 3.0)), 1.0 + source_weapon_tree.growth_stacks * float(fate_behavior.get("growth_per_hit", 0.2)))
			_flight_base_damage = maxi(1, int(_ungrown_damage * growth))
			damage = maxi(0, int(_flight_base_damage * float(fate_behavior.get("return_damage_multiplier", 0.6)))) if _returning else maxi(1, int(_flight_base_damage * float(fate_behavior.get("outbound_damage_multiplier", 1.0))))
		_hit_any = true
		if _returning:
			_return_hit_ids[collider.get_instance_id()] = true
		if collider.has_method("take_projectile_damage"):
			collider.call("take_projectile_damage", damage, critical, direction, bullet_tags, fate_behavior, shooter, hit_knockback)
		else:
			if shooter != null and collider.has_method("notify_attacked_by"):
				collider.call("notify_attacked_by", shooter)
			collider.call("take_damage", damage, critical, direction, hit_knockback)
		_apply_secondary_effect(collider)
		_apply_fate_on_hit(collider)
		hit_confirmed.emit(collider, damage, critical)
		_spawn_effect(VfxPool3D.FX01_IMPACT, global_position, bullet_color, 1.0, hit_context)
		if bool(fate_behavior.get("spawn_turret_on_land", false)):
			_become_turret()
			return
		if _returning:
			if collider is PhysicsBody3D:
				_add_tracked_collision_exception(collider as PhysicsBody3D)
			return
		if bool(fate_behavior.get("return_on_hit", false)) or bool(fate_behavior.get("return_to_player", false)) or bool(fate_behavior.get("home_on_land", false)):
			_begin_return()
			if bool(fate_behavior.get("return_on_hit", false)) and damage > 0:
				_hit_target(collider, hit_context)
			global_position += direction * 0.28
			return
		if _pierces_left > 0:
			_pierces_left -= 1
			if collider is PhysicsBody3D:
				_add_tracked_collision_exception(collider as PhysicsBody3D)
			global_position += direction * 0.28
			return
		if bullet_tags.has("explosive") or bullet_tags.has("blackhole") or bullet_tags.has("balloon") or bool(fate_behavior.get("nth_explosion", false)):
			_explode()
		_retire()
		return


func _hit_surface(normal: Vector3, hit_context: Dictionary = {}) -> void:
	if _returning:
		return
	if _bounces_left > 0:
		direction = direction.bounce(normal).normalized()
		damage = maxi(1, int(damage * float(fate_behavior.get("bounce_damage_scale", 0.85))))
		_sync_visual_orientation()
		_bounces_left -= 1
		_spawn_effect(VfxPool3D.FX01_IMPACT, global_position, bullet_color, 0.55, hit_context)
		return
	if bool(fate_behavior.get("spawn_turret_on_land", false)):
		_become_turret()
		return
	if bool(fate_behavior.get("return_to_player", false)) or bool(fate_behavior.get("home_on_land", false)):
		_begin_return()
		return
	if bullet_tags.has("explosive") or bullet_tags.has("blackhole") or bullet_tags.has("balloon") or bool(fate_behavior.get("nth_explosion", false)):
		_explode()
	_spawn_effect(VfxPool3D.FX01_IMPACT, global_position, bullet_color, 0.7, hit_context)
	_retire()


func _add_tracked_collision_exception(body: PhysicsBody3D) -> void:
	if not is_instance_valid(body) or body in _tracked_collision_exceptions:
		return
	add_collision_exception_with(body)
	_tracked_collision_exceptions.append(body)


func _apply_secondary_effect(target: Node) -> void:
	if bullet_tags.has("sticky") or bullet_tags.has("slow") or bullet_tags.has("balloon"):
		if target.has_method("apply_slow"):
			target.call("apply_slow", 0.62, 2.0)
	if bullet_tags.has("sticky") and target.has_method("apply_damage_over_time"):
		target.call("apply_damage_over_time", maxi(2, damage / 3), 2.4)
	if bullet_tags.has("pull") and shooter != null and target.has_method("apply_pull"):
		target.call("apply_pull", shooter.global_position, 3.2)


func _apply_fate_on_hit(target: Node) -> void:
	if target.has_method("apply_fate_element"):
		var elements: Dictionary = fate_behavior.get("fate_elements", {})
		for element in elements:
			target.call("apply_fate_element", element, elements[element], _flight_base_damage, source_weapon_tree, shooter)
	var attached: Dictionary = fate_behavior.get("attached_gun", {})
	if bool(attached.get("fire_on_hit", false)) and not _attached_hit_fired:
		_attached_hit_fired = true
		_fire_attached_gun(attached, direction)
	if bool(fate_behavior.get("chain_lightning", false)):
		_apply_chain_lightning(target)
	if is_instance_valid(source_weapon_tree):
		source_weapon_tree.record_growth_result(true, fate_behavior)
		var attachment := source_weapon_tree.claim_attachment_trigger("hit", target) if bool(fate_behavior.get("fate_attachment_hit_trigger", false)) else {}
		if attachment.has("pull_strength") and target.has_method("apply_pull") and is_instance_valid(shooter):
			target.call("apply_pull", shooter.global_position, float(attachment["pull_strength"]))
		var count := int(attachment.get("bullet_count", 0))
		if randf() < float(attachment.get("copy_chance", 0.0)):
			count += 1
		for index in range(count):
			var angle := (float(index) - float(count - 1) * 0.5) * float(attachment.get("spread", 0.0))
			_spawn_child_projectile(direction.rotated(Vector3.UP, angle), damage, bullet_color)


func _apply_chain_lightning(first_target: Node) -> void:
	var chain_count := maxi(0, int(fate_behavior.get("chain_count", 3)))
	var chain_range := maxf(1.0, float(fate_behavior.get("chain_range", 150.0)) / 30.0)
	var chain_scale := clampf(float(fate_behavior.get("chain_damage_scale", 0.7)), 0.05, 1.0)
	var current := first_target as Node3D
	var visited := {first_target.get_instance_id(): true}
	var chain_damage := damage
	for _index in range(chain_count):
		var nearest: Enemy3D = null
		var nearest_distance := chain_range
		for value in get_tree().get_nodes_in_group("enemy_3d"):
			var enemy := value as Enemy3D
			if enemy == null or enemy.ai_state == "dead" or visited.has(enemy.get_instance_id()):
				continue
			var distance := current.global_position.distance_to(enemy.global_position)
			if distance < nearest_distance:
				nearest = enemy
				nearest_distance = distance
		if nearest == null:
			break
		chain_damage = maxi(1, int(chain_damage * chain_scale))
		nearest.take_projectile_damage(chain_damage, false, (nearest.global_position - current.global_position).normalized(), bullet_tags, fate_behavior, shooter)
		_spawn_effect(VfxPool3D.FX01_IMPACT, nearest.global_position + Vector3(0, 0.6, 0), bullet_color, 0.72)
		visited[nearest.get_instance_id()] = true
		current = nearest


func _explode() -> void:
	var radius := maxf(0.5, float(fate_behavior.get("explosion_radius", 90.0)) / 30.0) if fate_behavior.has("explosion_radius") else 3.0
	if bullet_tags.has("blackhole"):
		radius = 4.0
	elif bullet_tags.has("balloon"):
		radius = 3.6
	_spawn_effect(LEGACY_EFFECT_EXPLOSION, global_position, bullet_color, radius * 0.42)
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(
			global_position, maxf(12.0, radius * 4.0), "explosion", shooter
		)
	var group_name := "player_3d" if hostile else "enemy_3d"
	for target in get_tree().get_nodes_in_group(group_name):
		if target == shooter or not target is Node3D or not target.has_method("take_damage"):
			continue
		var target_3d := target as Node3D
		var distance := global_position.distance_to(target_3d.global_position)
		if distance > radius:
			continue
		var falloff := clampf(1.0 - distance / radius, 0.25, 1.0)
		var hit_direction := (target_3d.global_position - global_position).normalized()
		var explosion_scale := float(fate_behavior.get("explosion_damage_scale", 0.72))
		if shooter != null and target.has_method("notify_attacked_by"):
			target.call("notify_attacked_by", shooter)
		if target.has_method("take_projectile_damage"):
			target.call("take_projectile_damage", maxi(1, int(damage * falloff * explosion_scale)), false, hit_direction, bullet_tags, fate_behavior, shooter)
		else:
			target.call("take_damage", maxi(1, int(damage * falloff * explosion_scale)), false, hit_direction)
		if bullet_tags.has("blackhole") and target.has_method("apply_pull"):
			target.call("apply_pull", global_position, 3.0 + falloff * 5.0)
		if bullet_tags.has("balloon") and target.has_method("apply_slow"):
			target.call("apply_slow", 0.48, 2.6)


func _nearest_target() -> Node3D:
	var best: Node3D = null
	var farthest := str(fate_behavior.get("target_mode", "nearest")) == "farthest"
	var best_distance := -1.0 if farthest else 12.0
	for candidate in get_tree().get_nodes_in_group("enemy_3d"):
		if not candidate is Node3D:
			continue
		var candidate_3d := candidate as Node3D
		if candidate is Enemy3D and (candidate as Enemy3D).ai_state == "dead":
			continue
		var distance := global_position.distance_to(candidate_3d.global_position)
		if distance > 12.0:
			continue
		if farthest and not _target_visible(candidate_3d):
			continue
		if (distance > best_distance if farthest else distance < best_distance):
			best = candidate_3d
			best_distance = distance
	return best


func _target_visible(target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, target.global_position + Vector3(0, 0.68, 0), 1)
	query.exclude = [get_rid()]
	if shooter is CollisionObject3D:
		query.exclude.append(shooter.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target


func _build_visual() -> void:
	# 独立子弹纯视觉 Prefab：由 ProjectilePool3D 宿主生命周期管理，不放 VfxPool 自动计时。
	_visual = BULLET_VISUAL_SCENE.instantiate() as VfxEffectBase3D
	add_child(_visual)
	# 单独建立球碰撞（半径 0.12，与命运缩放公式保持一致）。
	var shape := SphereShape3D.new()
	shape.radius = 0.12
	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = shape
	add_child(_collision_shape)


func _visual_scale_factor() -> float:
	var scale_factor := 1.55 if bullet_tags.has("balloon") else 1.0
	scale_factor *= clampf(float(fate_behavior.get("fate_scale", 1.0)), 0.35, 4.0)
	return scale_factor

func _apply_visual_configuration() -> void:
	var scale_factor := _visual_scale_factor()
	if _visual != null:
		_visual.configure(bullet_color, scale_factor, {})
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = 0.12 * scale_factor


func _return_destination() -> Vector3:
	if int(fate_behavior.get("refund_ammo", 0)) > 0 and is_instance_valid(source_weapon):
		return source_weapon.global_position
	return shooter.global_position + Vector3(0, 0.72, 0)


func _begin_return() -> void:
	if _returning:
		return
	if not is_instance_valid(shooter):
		_retire()
		return
	_returning = true
	_lifetime = 0.0
	damage = maxi(0, int(_flight_base_damage * float(fate_behavior.get("return_damage_multiplier", 0.6))))
	# 返航不再被去程穿透例外或墙体阻断；回程每个目标只结算一次。
	for exception in _tracked_collision_exceptions:
		if is_instance_valid(exception) and exception != shooter:
			remove_collision_exception_with(exception)
	_tracked_collision_exceptions.clear()
	if shooter is PhysicsBody3D:
		_add_tracked_collision_exception(shooter)
	collision_mask = 4 if damage > 0 else 0
	direction = (_return_destination() - global_position).normalized()
	_sync_visual_orientation()


func _become_turret() -> void:
	_turret_active = true
	velocity = Vector3.ZERO
	_turret_remaining = maxf(0.5, float(fate_behavior.get("turret_duration", 5.0)))
	_turret_shot_timer = 0.0
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	if _visual != null:
		if _visual.has_method("set_trail_visible"):
			_visual.call("set_trail_visible", false)
		if _visual.has_method("apply_growth"):
			_visual.call("apply_growth", 1.45)
	_spawn_effect(VfxPool3D.FX01_IMPACT, global_position, bullet_color, 1.25)


func _tick_turret(delta: float) -> void:
	if bool(fate_behavior.get("mobile_turret", false)) and is_instance_valid(shooter):
		global_position = global_position.move_toward(shooter.global_position + Vector3(0, 0.72, 0), speed * delta)
	_turret_remaining -= delta
	if _turret_remaining <= 0.0:
		_retire()
		return
	_turret_shot_timer -= delta
	if _turret_shot_timer > 0.0:
		return
	var target := _nearest_target()
	if target == null:
		return
	_turret_shot_timer = 1.0 / maxf(0.2, float(fate_behavior.get("turret_fire_rate", 2.0)))
	_spawn_child_projectile(
		(target.global_position + Vector3(0, 0.65, 0) - global_position).normalized(),
		maxi(1, int(damage * 0.30)),
		bullet_color.lightened(0.16),
	)


func _tick_attached_gun(delta: float) -> void:
	if not fate_behavior.has("attached_gun"):
		return
	_attached_shot_timer -= delta
	if _attached_shot_timer > 0.0:
		return
	var attached := fate_behavior.get("attached_gun", {}) as Dictionary
	if bool(attached.get("fire_on_hit", false)):
		return
	var target := _nearest_target()
	if target == null:
		return
	_attached_shot_timer = 1.0 / maxf(0.2, float(attached.get("fire_rate", 2.0)) * float(fate_behavior.get("uncontrolled_fire_rate_scale", 1.0)))
	_fire_attached_gun(attached, (target.global_position + Vector3(0, 0.65, 0) - global_position).normalized())


func _fire_attached_gun(attached: Dictionary, base_direction: Vector3) -> void:
	var count := maxi(1, int(attached.get("bullet_count", 1)))
	var child_damage := (float(attached.get("damage", 0)) + float(attached.get("bullet_damage", 5))) * float(attached.get("fate_damage_multiplier", 1.0)) * float(fate_behavior.get("owner_damage_multiplier", 1.0))
	if bool(fate_behavior.get("uncontrolled_gun", false)):
		base_direction = base_direction.rotated(Vector3.UP, randf_range(-PI, PI) * float(fate_behavior.get("aim_randomness", 1.0)))
		child_damage *= float(fate_behavior.get("uncontrolled_damage_scale", 1.0))
	var child_behavior := attached.duplicate(true)
	if bool(fate_behavior.get("uncontrolled_gun", false)) and is_instance_valid(source_weapon):
		source_weapon._recoil = maxf(source_weapon._recoil, 0.09 * float(fate_behavior.get("uncontrolled_recoil_scale", 1.0)))
		source_weapon.set_process(true)
	child_behavior.erase("attached_gun")
	child_behavior.erase("size_growth")
	for index in range(count):
		var angle := (float(index) - float(count - 1) * 0.5) * float(attached.get("spread", 0.10))
		_spawn_child_projectile(base_direction.rotated(Vector3.UP, angle), maxi(1, int(child_damage)), bullet_color.lightened(0.10), child_behavior)


func _spawn_child_projectile(shot_direction: Vector3, shot_damage: int, color: Color, child_behavior: Dictionary = {}) -> void:
	child_behavior = child_behavior.duplicate(true)
	child_behavior["source_weapon_tree"] = source_weapon_tree
	child_behavior["source_weapon"] = source_weapon
	var is_critical := randf() < float(fate_behavior.get("owner_critical_chance", 0.0))
	var critical_multiplier := float(fate_behavior.get("owner_critical_multiplier", 1.5))
	var config := {
		"direction": shot_direction,
		"speed": 23.0 * float(child_behavior.get("bullet_speed", speed / 23.0)) * float(child_behavior.get("fate_speed_multiplier", 1.0)),
		"damage": maxi(1, int(shot_damage * (critical_multiplier / 1.5 if is_critical else 1.0))),
		"critical": is_critical,
		"hostile": hostile,
		"tags": child_behavior.get("tags", []),
		"color": color,
		"shooter": shooter,
		"behavior": child_behavior,
	}
	var pools := get_tree().get_nodes_in_group("projectile_pool_3d")
	if not pools.is_empty() and pools[0] is ProjectilePool3D:
		(pools[0] as ProjectilePool3D).acquire(config, global_position + shot_direction * 0.32)
		return
	var projectile := Projectile3D.new()
	projectile.configure(config)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + shot_direction * 0.32


func _sync_visual_orientation() -> void:
	if direction.length_squared() <= 0.0001 or not is_inside_tree():
		return
	var forward := direction.normalized()
	if absf(forward.dot(Vector3.UP)) > 0.995:
		return
	look_at(global_position + forward, Vector3.UP)


func get_orientation_snapshot() -> Dictionary:
	var snapshot := {
		"direction": direction,
		"visual_forward": -global_basis.z,
		"alignment": direction.normalized().dot((-global_basis.z).normalized()),
		"trail_local_position": Vector3.ZERO,
		"trail_is_behind": false,
	}
	if _visual != null and _visual.has_method("get_presentation_snapshot"):
		var presentation := _visual.call("get_presentation_snapshot") as Dictionary
		snapshot["trail_local_position"] = presentation.get("trail_local_position", Vector3.ZERO)
		snapshot["trail_is_behind"] = presentation.get("trail_is_behind", false)
	return snapshot


func _retire() -> void:
	if not _active:
		return
	_active = false
	if not _hit_any and is_instance_valid(source_weapon_tree):
		source_weapon_tree.record_growth_result(false, fate_behavior)
	velocity = Vector3.ZERO
	visible = false
	if _visual != null and _visual.has_method("deactivate"):
		_visual.call("deactivate")
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	process_mode = Node.PROCESS_MODE_DISABLED
	if retired.get_connections().is_empty():
		queue_free()
	else:
		retired.emit(self)


func _spawn_effect(effect_id: StringName, world_position: Vector3, color: Color, size: float, context: Dictionary = {}) -> void:
	# 已注册 AssetID（FX01-* 战斗反馈）走全局 VfxPool 新体系，按 AssetID 路由。
	var vfx_pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if not vfx_pools.is_empty() and vfx_pools[0] is VfxPool3D and VfxPool3D.has_effect(effect_id):
		(vfx_pools[0] as VfxPool3D).acquire(effect_id, world_position, color, size, context)
		return
	if get_tree().current_scene == null:
		return
	# 未注册 AssetID（爆炸等旧链图例）：仍走 CombatEffectPool3D，待 14.6 §6 迁移完成后删除。
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire(str(effect_id), color, size, world_position)
		return
	# VfxPool 不在场（异常态）且该 AssetID 已注册：直接从注册表实例化，保留 AssetID 语义。
	var pooled_effect := VfxPool3D.create_unpooled(effect_id)
	if pooled_effect != null:
		get_tree().current_scene.add_child(pooled_effect)
		pooled_effect.activate(world_position, color, size, context)
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure(str(effect_id), color, size)
	get_tree().current_scene.add_child(effect)
	effect.global_position = world_position
