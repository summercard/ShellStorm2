class_name MeleeWeaponVisual3D
extends Node3D
## 大型近战武器的可替换程序原型。玩法命中不读取这些 Mesh，也不创建碰撞体。

@export_enum("baseball_bat", "greatblade", "waraxe") var weapon_style := "greatblade"

var _render_layers := 2


func _ready() -> void:
	_rebuild()


func configure(render_layers: int) -> void:
	_render_layers = render_layers
	if is_inside_tree():
		_rebuild()


func get_authored_bounds() -> Vector3:
	match weapon_style:
		"baseball_bat": return Vector3(0.28, 0.28, 1.48)
		"waraxe": return Vector3(1.18, 0.34, 2.62)
		_: return Vector3(0.82, 0.30, 2.42)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	match weapon_style:
		"baseball_bat": _build_baseball_bat()
		"waraxe": _build_waraxe()
		_: _build_greatblade()


func _build_baseball_bat() -> void:
	var wood := _material(Color(0.55, 0.31, 0.13), 0.02, 0.72)
	var worn_wood := _material(Color(0.32, 0.16, 0.065), 0.01, 0.86)
	var tape := _material(Color(0.055, 0.060, 0.066), 0.04, 0.74)
	var metal := _material(Color(0.38, 0.43, 0.45), 0.76, 0.34)
	_add_tapered_cylinder("BatBarrel", Vector3(0.0, 0.0, -0.48), 0.075, 0.145, 1.18, wood)
	_add_tapered_cylinder("Handle", Vector3(0.0, 0.0, 0.34), 0.050, 0.062, 0.48, worn_wood)
	_add_cylinder("GripTape", Vector3(0.0, 0.0, 0.35), 0.058, 0.34, tape)
	_add_cylinder("Knob", Vector3(0.0, 0.0, 0.62), 0.085, 0.09, wood)
	_add_cylinder("ReinforcementBand", Vector3(0.0, 0.0, -1.01), 0.151, 0.075, metal)


func _build_greatblade() -> void:
	var grip := _material(Color(0.055, 0.065, 0.075), 0.20, 0.78)
	var steel := _material(Color(0.31, 0.38, 0.43), 0.86, 0.25)
	var edge := _material(Color(0.73, 0.88, 0.96), 0.94, 0.14)
	var energy := _material(Color(0.08, 0.82, 0.94), 0.45, 0.20, true)
	_add_cylinder("Grip", Vector3(0.0, 0.0, 0.02), 0.055, 0.70, grip)
	_add_box("Pommel", Vector3(0.0, 0.0, 0.40), Vector3(0.18, 0.14, 0.16), steel)
	_add_box("Guard", Vector3(0.0, 0.0, -0.39), Vector3(0.72, 0.15, 0.16), steel)
	_add_box("BladeSpine", Vector3(0.0, 0.0, -1.34), Vector3(0.34, 0.12, 1.78), steel)
	_add_box("BladeEdgeL", Vector3(-0.21, 0.0, -1.35), Vector3(0.10, 0.09, 1.72), edge)
	_add_box("BrokenTip", Vector3(0.08, 0.0, -2.25), Vector3(0.48, 0.13, 0.24), steel, Vector3(0.0, -0.32, 0.0))
	_add_box("EnergyChannel", Vector3(0.02, -0.075, -1.38), Vector3(0.08, 0.035, 1.32), energy)


func _build_waraxe() -> void:
	var grip := _material(Color(0.11, 0.075, 0.045), 0.10, 0.84)
	var iron := _material(Color(0.24, 0.27, 0.28), 0.88, 0.31)
	var edge := _material(Color(0.82, 0.74, 0.48), 0.90, 0.18)
	var energy := _material(Color(1.0, 0.34, 0.06), 0.38, 0.24, true)
	_add_cylinder("LongHaft", Vector3(0.0, 0.0, -0.72), 0.065, 2.24, grip)
	_add_cylinder("Pommel", Vector3(0.0, 0.0, 0.43), 0.11, 0.18, iron)
	_add_box("AxeShoulder", Vector3(0.0, 0.0, -1.86), Vector3(0.48, 0.20, 0.50), iron)
	_add_box("AxeHeadL", Vector3(-0.40, 0.0, -1.91), Vector3(0.50, 0.16, 0.76), iron, Vector3(0.0, 0.0, -0.18))
	_add_box("AxeEdgeL", Vector3(-0.70, 0.0, -1.94), Vector3(0.12, 0.13, 0.82), edge, Vector3(0.0, 0.0, -0.18))
	_add_box("CounterSpike", Vector3(0.38, 0.0, -1.88), Vector3(0.46, 0.14, 0.22), iron, Vector3(0.0, -0.48, 0.0))
	_add_box("ImpactCore", Vector3(0.0, -0.12, -1.87), Vector3(0.20, 0.05, 0.30), energy)


func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	rotation := Vector3.ZERO
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.rotation = rotation
	instance.mesh = mesh
	_prepare_instance(instance)
	add_child(instance)


func _add_cylinder(
	node_name: String,
	position: Vector3,
	radius: float,
	length: float,
	material: StandardMaterial3D
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees.x = 90.0
	instance.mesh = mesh
	_prepare_instance(instance)
	add_child(instance)


func _add_tapered_cylinder(
	node_name: String,
	position: Vector3,
	top_radius: float,
	bottom_radius: float,
	length: float,
	material: StandardMaterial3D
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = length
	mesh.radial_segments = 20
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees.x = 90.0
	instance.mesh = mesh
	_prepare_instance(instance)
	add_child(instance)


func _prepare_instance(instance: MeshInstance3D) -> void:
	instance.layers = _render_layers
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _material(
	color: Color,
	metallic: float,
	roughness: float,
	emission := false
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
	return material
