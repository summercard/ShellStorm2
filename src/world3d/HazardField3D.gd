class_name HazardField3D
extends Area3D

@export var hazard_color := Color(1.0, 0.24, 0.08)
@export_range(1.0, 6.0, 0.25) var radius := 2.2
@export_range(1, 50, 1) var damage := 9

var _cooldowns: Dictionary = {}
var _elapsed := 0.0


func configure(color: Color, p_radius: float, p_damage: int) -> void:
	hazard_color = color
	radius = p_radius
	damage = p_damage


func _ready() -> void:
	add_to_group("hazard_3d")
	collision_layer = 0
	collision_mask = 1
	_build_visual()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	rotation.y += delta * 0.22
	for body in get_overlapping_bodies():
		if not body.is_in_group("player_3d"):
			continue
		var next_time := float(_cooldowns.get(body, 0.0))
		if _elapsed >= next_time and body.has_method("take_damage"):
			body.call("take_damage", damage)
			_cooldowns[body] = _elapsed + 0.85


func _build_visual() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.35
	var collision := CollisionShape3D.new()
	collision.position.y = 0.12
	collision.shape = shape
	add_child(collision)
	for index in range(3):
		var mesh := TorusMesh.new()
		mesh.inner_radius = radius * (0.42 + index * 0.15)
		mesh.outer_radius = mesh.inner_radius + 0.08
		mesh.rings = 24
		mesh.ring_segments = 6
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(hazard_color.r, hazard_color.g, hazard_color.b, 0.52 - index * 0.09)
		material.emission_enabled = true
		material.emission = hazard_color
		material.emission_energy_multiplier = 1.4
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		var ring := MeshInstance3D.new()
		ring.position.y = 0.05 + index * 0.025
		ring.mesh = mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
