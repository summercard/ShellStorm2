class_name CombatEffect3D
extends Node3D
## 枪口、命中、爆炸和伤害数字共用的短生命周期表现资产。

signal retired(effect: CombatEffect3D)

@export_enum("muzzle", "impact", "explosion", "damage", "heal") var effect_kind := "impact"
@export var effect_color := Color(0.45, 0.88, 1.0)
@export_range(0.1, 8.0, 0.1) var effect_size := 1.0
@export var text_value := ""

var _elapsed := 0.0
var _lifetime := 0.34
var _materials: Array[StandardMaterial3D] = []
var _active := true
var _built := false
var _value_label: Label3D


func configure(kind: String, color: Color, size: float = 1.0, value := "") -> void:
	effect_kind = kind
	effect_color = color
	effect_size = size
	text_value = str(value)
	_elapsed = 0.0


func activate(kind: String, color: Color, size: float, world_position: Vector3, value := "") -> void:
	configure(kind, color, size, value)
	_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	global_position = world_position
	scale = Vector3.ONE * effect_size
	if _value_label != null:
		_value_label.text = text_value
		_value_label.modulate = effect_color
	for material in _materials:
		material.albedo_color = effect_color
		material.emission = Color(effect_color.r, effect_color.g, effect_color.b, 1.0)


func _ready() -> void:
	_build_effect()
	_built = true


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var ratio := clampf(_elapsed / maxf(0.01, _lifetime), 0.0, 1.0)
	match effect_kind:
		"muzzle":
			scale = Vector3.ONE * effect_size * lerpf(0.35, 1.75, ratio)
		"explosion":
			scale = Vector3.ONE * effect_size * lerpf(0.28, 2.8, ratio)
		"damage", "heal":
			position.y += delta * 1.25
		_:
			scale = Vector3.ONE * effect_size * lerpf(0.65, 1.55, ratio)
	for material in _materials:
		var color := material.albedo_color
		color.a = 1.0 - ratio
		material.albedo_color = color
	if _elapsed >= _lifetime:
		_retire()


func _build_effect() -> void:
	match effect_kind:
		"muzzle":
			_lifetime = 0.12
			_add_sphere("Flash", 0.18, effect_color, 2.8)
			_add_ring("MuzzleRing", 0.18, 0.045, effect_color.lightened(0.18))
		"explosion":
			_lifetime = 0.46
			_add_sphere("Core", 0.42, effect_color.lightened(0.28), 3.1)
			_add_ring("Shockwave", 0.55, 0.08, effect_color)
			_add_ring("OuterWave", 0.82, 0.055, effect_color.darkened(0.18))
		"damage", "heal":
			_lifetime = 0.72
			_value_label = Label3D.new()
			_value_label.text = text_value
			_value_label.font_size = 54
			_value_label.pixel_size = 0.010
			_value_label.modulate = effect_color
			_value_label.outline_size = 10
			_value_label.no_depth_test = true
			add_child(_value_label)
		_:
			_lifetime = 0.24
			_add_sphere("ImpactCore", 0.16, effect_color, 2.2)
			_add_ring("ImpactRing", 0.28, 0.045, effect_color.lightened(0.22))


func _retire() -> void:
	if not _active:
		return
	_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if retired.get_connections().is_empty():
		queue_free()
	else:
		retired.emit(self)


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
