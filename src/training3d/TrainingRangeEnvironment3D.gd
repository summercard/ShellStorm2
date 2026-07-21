class_name TrainingRangeEnvironment3D
extends Node3D
## 靶场空间资产：射击区、装备墙、三条射击道、掩体、工作台和废土灯光一次组合。

const LIGHT_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_wasteland_light_root_top3d_v001.tscn")

var _metal: StandardMaterial3D
var _floor: StandardMaterial3D
var _accent: StandardMaterial3D


func _ready() -> void:
	add_to_group("training_environment_3d")
	_metal = _material(Color(0.16, 0.18, 0.18), 0.66, 0.52)
	_floor = _material(Color(0.12, 0.14, 0.14), 0.42, 0.76)
	_accent = _material(Color(0.88, 0.48, 0.13), 0.50, 0.38, true)
	_build_architecture()
	_build_lighting()
	_build_furniture()


func get_snapshot() -> Dictionary:
	return {
		"has_shooting_lanes": get_node_or_null("ShootingLanes") != null,
		"has_equipment_wall": get_node_or_null("EquipmentWall") != null,
		"has_workbench": get_node_or_null("Workbench") != null,
		"light_count": get_tree().get_nodes_in_group("training_light_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"is_3d": true,
	}


func _build_architecture() -> void:
	_add_static_box("Floor", Vector3(0, -0.2, -9), Vector3(34, 0.4, 32), _floor)
	_add_static_box("BackWall", Vector3(0, 2.8, -25), Vector3(34, 5.6, 0.42), _metal)
	_add_static_box("LeftWall", Vector3(-17, 2.8, -9), Vector3(0.42, 5.6, 32), _metal)
	_add_static_box("RightWall", Vector3(17, 2.8, -9), Vector3(0.42, 5.6, 32), _metal)
	var lanes := Node3D.new()
	lanes.name = "ShootingLanes"
	add_child(lanes)
	for x in [-8.0, 0.0, 8.0]:
		_add_box("LaneStripe", Vector3(x, 0.025, -15.0), Vector3(0.08, 0.025, 18.0), _accent, lanes)
		_add_box("FiringLine", Vector3(x, 0.035, -5.9), Vector3(5.7, 0.035, 0.16), _accent, lanes)
	var wall := Node3D.new()
	wall.name = "EquipmentWall"
	add_child(wall)
	_add_static_box("RackBacking", Vector3(-10.8, 1.65, 3.8), Vector3(10.8, 3.3, 0.42), _metal, wall)
	for x in range(-15, -5, 2):
		_add_box("RackRail", Vector3(float(x), 1.65, 3.55), Vector3(0.06, 2.7, 0.08), _accent, wall)


func _build_lighting() -> void:
	for index in range(6):
		var light := LIGHT_SCENE.instantiate() as WastelandLight3D
		var column := index % 3
		var row := index / 3
		light.position = Vector3(-10.0 + column * 10.0, 0, -18.5 + row * 14.0)
		light.rotation.y = PI * 0.5 if column < 2 else -PI * 0.5
		light.configure(Color(1.0, 0.58, 0.24) if row == 0 else Color(0.34, 0.72, 0.90), 2.5, 8.5, 700 + index, index == 2, index in [1, 4])
		add_child(light)
		light.add_to_group("training_light_3d")


func _build_furniture() -> void:
	var workbench := Node3D.new()
	workbench.name = "Workbench"
	add_child(workbench)
	_add_static_box("BenchTop", Vector3(10.5, 0.92, 2.8), Vector3(6.2, 0.22, 1.7), _metal, workbench)
	for x in [8.0, 13.0]:
		_add_static_box("BenchLeg", Vector3(x, 0.42, 2.8), Vector3(0.22, 0.84, 1.35), _metal, workbench)
	_add_box("BenchGlow", Vector3(10.5, 1.05, 2.2), Vector3(4.8, 0.06, 0.08), _accent, workbench)
	for x in [-12.0, 12.0]:
		_add_static_box("Cover", Vector3(x, 0.65, -10.5), Vector3(2.4, 1.3, 1.2), _metal)


func _add_static_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D = self) -> void:
	var body := StaticBody3D.new()
	body.name = "%sBody" % node_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D = self) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	parent.add_child(instance)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.55
	return material
