class_name Projectile3D
extends CharacterBody3D

signal hit_confirmed(target: Node, applied_damage: int, critical: bool)
signal expired

const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")

var direction := Vector3(0, 0, -1)
var speed := 24.0
var damage := 10
var critical := false
var hostile := false
var bullet_tags: Array[String] = []
var bullet_color := Color(0.45, 0.88, 1.0)
var shooter: Node3D = null
var _lifetime := 0.0
var _bounces_left := 0
var _pierces_left := 0
var _built := false


func configure(config: Dictionary) -> void:
	direction = (config.get("direction", direction) as Vector3).normalized()
	speed = float(config.get("speed", speed))
	damage = int(config.get("damage", damage))
	critical = bool(config.get("critical", critical))
	hostile = bool(config.get("hostile", hostile))
	bullet_tags.assign(config.get("tags", []))
	bullet_color = config.get("color", bullet_color) as Color
	shooter = config.get("shooter", shooter) as Node3D
	_bounces_left = 2 if bullet_tags.has("bounce") else 0
	_pierces_left = 2 if bullet_tags.has("piercing") else 0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 if hostile else 5
	if shooter is PhysicsBody3D:
		add_collision_exception_with(shooter as PhysicsBody3D)
	_build_visual()
	_built = true


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= 5.0:
		expired.emit()
		queue_free()
		return
	if bullet_tags.has("homing") and not hostile:
		var target := _nearest_target()
		if target != null:
			var desired := (target.global_position - global_position).normalized()
			direction = direction.slerp(desired, minf(1.0, delta * 2.8)).normalized()
	velocity = direction * speed
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	var collider := collision.get_collider() as Node
	if collider == shooter:
		return
	if collider != null and collider.has_method("take_damage"):
		collider.call("take_damage", damage, critical, direction)
		_apply_secondary_effect(collider)
		hit_confirmed.emit(collider, damage, critical)
		_spawn_effect("impact", global_position, bullet_color, 1.0)
		if _pierces_left > 0:
			_pierces_left -= 1
			if collider is PhysicsBody3D:
				add_collision_exception_with(collider as PhysicsBody3D)
			global_position += direction * 0.28
			return
		if bullet_tags.has("explosive") or bullet_tags.has("blackhole") or bullet_tags.has("balloon"):
			_explode()
		queue_free()
		return
	if _bounces_left > 0:
		direction = direction.bounce(collision.get_normal()).normalized()
		_bounces_left -= 1
		_spawn_effect("impact", global_position, bullet_color, 0.55)
		return
	if bullet_tags.has("explosive"):
		_explode()
	_spawn_effect("impact", global_position, bullet_color, 0.7)
	queue_free()


func _apply_secondary_effect(target: Node) -> void:
	if bullet_tags.has("sticky") or bullet_tags.has("slow") or bullet_tags.has("balloon"):
		if target.has_method("apply_slow"):
			target.call("apply_slow", 0.62, 2.0)
	if bullet_tags.has("sticky") and target.has_method("apply_damage_over_time"):
		target.call("apply_damage_over_time", maxi(2, damage / 3), 2.4)


func _explode() -> void:
	var radius := 3.0
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
		target.call("take_damage", maxi(1, int(damage * falloff * 0.72)), false, hit_direction)
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
		var distance := global_position.distance_to(candidate_3d.global_position)
		if distance < best_distance:
			best = candidate_3d
			best_distance = distance
	return best


func _build_visual() -> void:
	var scale_factor := 1.55 if bullet_tags.has("balloon") else 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.10 * scale_factor
	mesh.height = 0.20 * scale_factor
	mesh.radial_segments = 10
	mesh.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = bullet_color
	material.emission_enabled = true
	material.emission = bullet_color
	material.emission_energy_multiplier = 2.2
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.035 * scale_factor, 0.035 * scale_factor, 0.65 * scale_factor)
	var trail_material := material.duplicate() as StandardMaterial3D
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.albedo_color.a = 0.36
	trail_mesh.material = trail_material
	var trail := MeshInstance3D.new()
	trail.position = Vector3(0, 0, 0.34)
	trail.mesh = trail_mesh
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	var shape := SphereShape3D.new()
	shape.radius = 0.12 * scale_factor
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)


func _spawn_effect(kind: String, world_position: Vector3, color: Color, size: float) -> void:
	if get_tree().current_scene == null:
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure(kind, color, size)
	get_tree().current_scene.add_child(effect)
	effect.global_position = world_position
