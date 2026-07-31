class_name Projectile3D
extends CharacterBody3D

signal hit_confirmed(target: Node, applied_damage: int, critical: bool)
signal expired
signal retired(projectile: Projectile3D)

const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")

var direction := Vector3(0, 0, -1)
var speed := 24.0
var damage := 10
var critical := false
var hostile := false
var bullet_tags: Array[String] = []
var bullet_color := Color(0.45, 0.88, 1.0)
var shooter: Node3D = null
var fate_behavior: Dictionary = {}
var _lifetime := 0.0
var _bounces_left := 0
var _pierces_left := 0
var _built := false
var _active := true
var _collision_shape: CollisionShape3D
var _visual: MeshInstance3D
var _trail: MeshInstance3D
var _visual_material: StandardMaterial3D
var _trail_material: StandardMaterial3D
var _returning := false
var _turret_active := false
var _turret_remaining := 0.0
var _turret_shot_timer := 0.0
var _attached_shot_timer := 0.0
var _growth_stacks := 0


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
	_bounces_left = int(fate_behavior.get("bounce_count", 2 if bullet_tags.has("bounce") else 0))
	_pierces_left = int(fate_behavior.get("pierce_level", 2 if bullet_tags.has("piercing") else 0))
	_lifetime = 0.0
	_returning = false
	_turret_active = false
	_turret_remaining = 0.0
	_turret_shot_timer = 0.0
	_attached_shot_timer = 0.12
	_growth_stacks = 0
	if _built:
		_apply_visual_configuration()
		_sync_visual_orientation()


func activate(config: Dictionary, world_position: Vector3) -> void:
	configure(config)
	collision_mask = 1 if hostile else 5
	for exception in get_collision_exceptions():
		remove_collision_exception_with(exception)
	if shooter is PhysicsBody3D:
		add_collision_exception_with(shooter as PhysicsBody3D)
	_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	global_position = world_position
	velocity = Vector3.ZERO
	if _trail != null:
		_trail.visible = true
	_sync_visual_orientation()
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 if hostile else 5
	if shooter is PhysicsBody3D:
		add_collision_exception_with(shooter as PhysicsBody3D)
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
	var max_lifetime := maxf(5.0, float(fate_behavior.get("home_lifetime", 5.0)))
	if _lifetime >= max_lifetime:
		expired.emit()
		_retire()
		return
	_tick_attached_gun(delta)
	if _returning:
		if shooter == null or not is_instance_valid(shooter) or global_position.distance_to(shooter.global_position) <= 0.72:
			_retire()
			return
		direction = (shooter.global_position + Vector3(0, 0.72, 0) - global_position).normalized()
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
	var collider := collision.get_collider() as Node
	if collider == shooter:
		return
	if collider != null and collider.has_method("take_damage"):
		if collider.has_method("can_absorb_projectile") and bool(collider.call("can_absorb_projectile", bullet_tags)):
			if collider.has_method("on_projectile_absorbed"):
				collider.call("on_projectile_absorbed", damage)
			_spawn_effect("impact", global_position, bullet_color, 1.25)
			_retire()
			return
		if collider.has_method("take_projectile_damage"):
			collider.call("take_projectile_damage", damage, critical, direction, bullet_tags, fate_behavior)
		else:
			collider.call("take_damage", damage, critical, direction)
		_apply_secondary_effect(collider)
		_apply_fate_on_hit(collider)
		hit_confirmed.emit(collider, damage, critical)
		_spawn_effect("impact", global_position, bullet_color, 1.0)
		if bool(fate_behavior.get("spawn_turret_on_land", false)):
			_become_turret()
			return
		if bool(fate_behavior.get("return_to_player", false)) or bool(fate_behavior.get("home_on_land", false)):
			_begin_return()
			if collider is PhysicsBody3D:
				add_collision_exception_with(collider as PhysicsBody3D)
			return
		if _pierces_left > 0:
			_pierces_left -= 1
			if collider is PhysicsBody3D:
				add_collision_exception_with(collider as PhysicsBody3D)
			global_position += direction * 0.28
			return
		if bullet_tags.has("explosive") or bullet_tags.has("blackhole") or bullet_tags.has("balloon"):
			_explode()
		_retire()
		return
	if _bounces_left > 0:
		direction = direction.bounce(collision.get_normal()).normalized()
		damage = maxi(1, int(damage * float(fate_behavior.get("bounce_damage_scale", 0.85))))
		_sync_visual_orientation()
		_bounces_left -= 1
		_spawn_effect("impact", global_position, bullet_color, 0.55)
		return
	if bool(fate_behavior.get("spawn_turret_on_land", false)):
		_become_turret()
		return
	if bool(fate_behavior.get("return_to_player", false)) or bool(fate_behavior.get("home_on_land", false)):
		_begin_return()
		return
	if bullet_tags.has("explosive") or bullet_tags.has("blackhole") or bullet_tags.has("balloon") or bool(fate_behavior.get("nth_explosion", false)):
		_explode()
	_spawn_effect("impact", global_position, bullet_color, 0.7)
	_retire()


func _apply_secondary_effect(target: Node) -> void:
	if bullet_tags.has("sticky") or bullet_tags.has("slow") or bullet_tags.has("balloon"):
		if target.has_method("apply_slow"):
			target.call("apply_slow", 0.62, 2.0)
	if bullet_tags.has("sticky") and target.has_method("apply_damage_over_time"):
		target.call("apply_damage_over_time", maxi(2, damage / 3), 2.4)
	if bullet_tags.has("pull") and shooter != null and target.has_method("apply_pull"):
		target.call("apply_pull", shooter.global_position, 3.2)


func _apply_fate_on_hit(target: Node) -> void:
	if bool(fate_behavior.get("fuse_damage", false)) and target.has_method("apply_damage_over_time"):
		var duration := maxf(1.0, float(fate_behavior.get("dot_duration", 3.0)))
		var ratio := float(fate_behavior.get(
			"dot_damage_per_stack",
			fate_behavior.get("dot_damage_per_sec", 0.08),
		))
		target.call("apply_damage_over_time", maxi(1, int(damage * ratio * duration)), duration)
	var freeze_duration := float(fate_behavior.get("freeze_duration", 0.0))
	if freeze_duration > 0.0 and target.has_method("apply_slow"):
		if target is Enemy3D and not (target as Enemy3D).elite_modifier_id.is_empty():
			freeze_duration = float(fate_behavior.get("freeze_duration_elite", freeze_duration * 0.5))
		target.call("apply_slow", 0.25, freeze_duration)
	if bool(fate_behavior.get("chain_lightning", false)):
		_apply_chain_lightning(target)
	if bool(fate_behavior.get("size_growth", false)):
		_apply_growth()
	if bool(fate_behavior.get("fate_attachment_hit_trigger", false)):
		for angle in [-0.24, 0.24]:
			_spawn_child_projectile(
				direction.rotated(Vector3.UP, angle),
				maxi(1, int(damage * 0.35)),
				bullet_color.lightened(0.08),
			)


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
		nearest.take_projectile_damage(chain_damage, false, (nearest.global_position - current.global_position).normalized(), bullet_tags, fate_behavior)
		_spawn_effect("impact", nearest.global_position + Vector3(0, 0.6, 0), bullet_color, 0.72)
		visited[nearest.get_instance_id()] = true
		current = nearest


func _apply_growth() -> void:
	var max_stacks := maxi(1, int(fate_behavior.get("max_stacks", 5)))
	if _growth_stacks >= max_stacks:
		return
	_growth_stacks += 1
	var growth := maxf(0.02, float(fate_behavior.get("growth_per_hit", 0.12)))
	damage = maxi(1, int(damage * (1.0 + growth)))
	var growth_scale := 1.0 + growth
	if _visual != null:
		_visual.scale *= growth_scale
	if _trail != null:
		_trail.scale *= growth_scale
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius *= growth_scale


func _explode() -> void:
	var radius := maxf(0.5, float(fate_behavior.get("explosion_radius", 90.0)) / 30.0) if fate_behavior.has("explosion_radius") else 3.0
	if bullet_tags.has("blackhole"):
		radius = 4.0
	elif bullet_tags.has("balloon"):
		radius = 3.6
	_spawn_effect("explosion", global_position, bullet_color, radius * 0.42)
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
		target.call("take_damage", maxi(1, int(damage * falloff * explosion_scale)), false, hit_direction)
		if bullet_tags.has("blackhole") and target.has_method("apply_pull"):
			target.call("apply_pull", global_position, 3.0 + falloff * 5.0)
		if bullet_tags.has("balloon") and target.has_method("apply_slow"):
			target.call("apply_slow", 0.48, 2.6)


func _nearest_target() -> Node3D:
	var best: Node3D = null
	var best_distance := 12.0
	for candidate in get_tree().get_nodes_in_group("enemy_3d"):
		if not candidate is Node3D:
			continue
		var candidate_3d := candidate as Node3D
		if candidate is Enemy3D and (candidate as Enemy3D).ai_state == "dead":
			continue
		var distance := global_position.distance_to(candidate_3d.global_position)
		if distance < best_distance:
			best = candidate_3d
			best_distance = distance
	return best


func _build_visual() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.10
	mesh.height = 0.20
	mesh.radial_segments = 10
	mesh.rings = 5
	_visual_material = StandardMaterial3D.new()
	_visual_material.emission_enabled = true
	_visual_material.emission_energy_multiplier = 2.2
	mesh.material = _visual_material
	_visual = MeshInstance3D.new()
	_visual.mesh = mesh
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_visual)
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.035, 0.035, 0.65)
	_trail_material = _visual_material.duplicate() as StandardMaterial3D
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mesh.material = _trail_material
	_trail = MeshInstance3D.new()
	_trail.position = Vector3(0, 0, 0.34)
	_trail.mesh = trail_mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_trail)
	var shape := SphereShape3D.new()
	shape.radius = 0.12
	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = shape
	add_child(_collision_shape)


func _apply_visual_configuration() -> void:
	var scale_factor := 1.55 if bullet_tags.has("balloon") else 1.0
	scale_factor *= clampf(float(fate_behavior.get("fate_scale", 1.0)), 0.35, 4.0)
	if _visual != null:
		_visual.scale = Vector3.ONE * scale_factor
	if _trail != null:
		_trail.scale = Vector3.ONE * scale_factor
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = 0.12 * scale_factor
	if _visual_material != null:
		_visual_material.albedo_color = bullet_color
		_visual_material.emission = bullet_color
	if _trail_material != null:
		_trail_material.albedo_color = Color(bullet_color.r, bullet_color.g, bullet_color.b, 0.36)
		_trail_material.emission = bullet_color


func _begin_return() -> void:
	if shooter == null or not is_instance_valid(shooter):
		_retire()
		return
	_returning = true
	damage = maxi(1, int(damage * float(fate_behavior.get("return_damage_multiplier", 0.6))))
	direction = (shooter.global_position + Vector3(0, 0.72, 0) - global_position).normalized()
	_sync_visual_orientation()


func _become_turret() -> void:
	_turret_active = true
	velocity = Vector3.ZERO
	_turret_remaining = maxf(0.5, float(fate_behavior.get("turret_duration", 5.0)))
	_turret_shot_timer = 0.0
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	if _trail != null:
		_trail.visible = false
	if _visual != null:
		_visual.scale *= 1.45
	_spawn_effect("impact", global_position, bullet_color, 1.25)


func _tick_turret(delta: float) -> void:
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
	var target := _nearest_target()
	if target == null:
		return
	_attached_shot_timer = 1.0 / maxf(0.2, float(attached.get("fire_rate", 2.0)))
	var count := maxi(1, int(attached.get("bullet_count", 1)))
	var base_direction := (target.global_position + Vector3(0, 0.65, 0) - global_position).normalized()
	if bool(fate_behavior.get("uncontrolled_gun", false)):
		base_direction = base_direction.rotated(Vector3.UP, randf_range(-PI, PI))
	for index in range(count):
		var angle := (float(index) - float(count - 1) * 0.5) * 0.10
		_spawn_child_projectile(
			base_direction.rotated(Vector3.UP, angle),
			maxi(1, int(attached.get("damage", 5))),
			bullet_color.lightened(0.10),
		)


func _spawn_child_projectile(shot_direction: Vector3, shot_damage: int, color: Color) -> void:
	var config := {
		"direction": shot_direction,
		"speed": maxf(14.0, speed * 0.9),
		"damage": shot_damage,
		"critical": false,
		"hostile": hostile,
		"tags": [],
		"color": color,
		"shooter": shooter,
		"behavior": {},
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
	return {
		"direction": direction,
		"visual_forward": -global_basis.z,
		"alignment": direction.normalized().dot((-global_basis.z).normalized()),
		"trail_local_position": _trail.position if _trail != null else Vector3.ZERO,
		"trail_is_behind": _trail != null and _trail.position.z > 0.0,
	}


func _retire() -> void:
	if not _active:
		return
	_active = false
	velocity = Vector3.ZERO
	visible = false
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	process_mode = Node.PROCESS_MODE_DISABLED
	if retired.get_connections().is_empty():
		queue_free()
	else:
		retired.emit(self)


func _spawn_effect(kind: String, world_position: Vector3, color: Color, size: float) -> void:
	if get_tree().current_scene == null:
		return
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire(kind, color, size, world_position)
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure(kind, color, size)
	get_tree().current_scene.add_child(effect)
	effect.global_position = world_position
