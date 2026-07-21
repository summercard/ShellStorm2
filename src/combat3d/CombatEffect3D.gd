class_name CombatEffect3D
extends Node3D
## 枪口、命中、爆炸和伤害数字共用的短生命周期表现资产。

@export_enum("muzzle", "impact", "explosion", "damage", "heal") var effect_kind := "impact"
@export var effect_color := Color(0.45, 0.88, 1.0)
@export_range(0.1, 8.0, 0.1) var effect_size := 1.0
@export var text_value := ""

var _elapsed := 0.0
var _lifetime := 0.34
var _materials: Array[StandardMaterial3D] = []


func configure(kind: String, color: Color, size: float = 1.0, value := "") -> void:
	effect_kind = kind
	effect_color = color
	effect_size = size
	text_value = str(value)


func _ready() -> void:
	_build_effect()


func _process(delta: float) -> void:
	_elapsed += delta
	var ratio := clampf(_elapsed / maxf(0.01, _lifetime), 0.0, 1.0)
	match effect_kind:
		"muzzle":
			scale = Vector3.ONE * lerpf(0.35, 1.75, ratio)
		"explosion":
			scale = Vector3.ONE * lerpf(0.28, 2.8, ratio)
		"damage", "heal":
			position.y += delta * 1.25
		_:
			scale = Vector3.ONE * lerpf(0.65, 1.55, ratio)
	for material in _materials:
		var color := material.albedo_color
		color.a = 1.0 - ratio
		material.albedo_color = color
	if _elapsed >= _lifetime:
		queue_free()


func _build_effect() -> void:
	match effect_kind:
		"muzzle":
			_lifetime = 0.12
			_add_sphere("Flash", 0.18 * effect_size, effect_color, 2.8)
			_add_ring("MuzzleRing", 0.18 * effect_size, 0.045 * effect_size, effect_color.lightened(0.18))
		"explosion":
			_lifetime = 0.46
			_add_sphere("Core", 0.42 * effect_size, effect_color.lightened(0.28), 3.1)
			_add_ring("Shockwave", 0.55 * effect_size, 0.08 * effect_size, effect_color)
			_add_ring("OuterWave", 0.82 * effect_size, 0.055 * effect_size, effect_color.darkened(0.18))
		"damage", "heal":
			_lifetime = 0.72
			var label := Label3D.new()
			label.text = text_value
			label.font_size = 54
			label.pixel_size = 0.010
			label.modulate = effect_color
			label.outline_size = 10
			label.no_depth_test = true
			add_child(label)
		_:
			_lifetime = 0.24
			_add_sphere("ImpactCore", 0.16 * effect_size, effect_color, 2.2)
			_add_ring("ImpactRing", 0.28 * effect_size, 0.045 * effect_size, effect_color.lightened(0.22))


func _add_sphere(node_name: String, radius: float, color: Color, emission_energy: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var material := _effect_material(color, emission_energy)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _add_ring(node_name: String, radius: float, thickness: float, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius
	mesh.outer_radius = radius + thickness
	mesh.rings = 24
	mesh.ring_segments = 6
	var material := _effect_material(color, 2.0)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position.y = 0.04
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _effect_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = emission_energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials.append(material)
	return material
