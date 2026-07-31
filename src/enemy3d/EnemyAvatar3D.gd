class_name EnemyAvatar3D
extends Node3D
## 七类敌人的共用模块化外壳。核心、护甲、附肢和状态特效均为独立组件，
## 运行时只改变组合与材质，避免为每个关卡复制模型。

const COLORS := {
	"melee_chaser": Color(0.58, 0.19, 0.12),
	"ranged_caster": Color(0.18, 0.44, 0.50),
	"summoner": Color(0.42, 0.22, 0.52),
	"shielded": Color(0.28, 0.34, 0.30),
	"exploder": Color(0.72, 0.30, 0.08),
	"ambusher": Color(0.14, 0.20, 0.18),
	"boss": Color(0.37, 0.12, 0.09),
}

# 与实际模块化模型的最大横向轮廓同源；Enemy3D 直接读取该表生成受击/物理体积。
const FOOTPRINT_PROFILES := {
	"melee_chaser": {"radius": 1.02, "height": 1.30},
	"ranged_caster": {"radius": 1.10, "height": 1.62},
	"summoner": {"radius": 1.22, "height": 1.82},
	"shielded": {"radius": 0.98, "height": 1.42},
	"exploder": {"radius": 0.88, "height": 1.28},
	"ambusher": {"radius": 1.22, "height": 0.86},
	"boss": {"radius": 1.92, "height": 2.30},
}

var enemy_kind := "melee_chaser"
var ai_state := "idle"
var _elapsed := 0.0
var _root: Node3D
var _core: MeshInstance3D
var _shell: MeshInstance3D
var _appendages: Node3D
var _tell_ring: MeshInstance3D
var _base_color := Color.WHITE
var _core_material: StandardMaterial3D
var _shell_material: StandardMaterial3D
var _ambush_revealed := true


func configure(kind: String) -> void:
	enemy_kind = kind if COLORS.has(kind) else "melee_chaser"
	_rebuild()


func set_ai_state(state_id: String) -> void:
	ai_state = state_id


func set_ambush_revealed(revealed: bool) -> void:
	_ambush_revealed = revealed


static func get_footprint_profile(kind: String) -> Dictionary:
	return (FOOTPRINT_PROFILES.get(kind, FOOTPRINT_PROFILES["melee_chaser"]) as Dictionary).duplicate()


func flash_hit() -> void:
	if _shell_material != null:
		_shell_material.albedo_color = Color(1.0, 0.78, 0.60)


func get_component_snapshot() -> Dictionary:
	return {
		"enemy_kind": enemy_kind,
		"ai_state": ai_state,
		"components": ["core", "shell", "appendages", "state_vfx"],
		"component_count": 4,
		"footprint": get_footprint_profile(enemy_kind),
		"ambush_revealed": _ambush_revealed,
		"is_3d": true,
	}


func _process(delta: float) -> void:
	_elapsed += delta
	if _root == null:
		return
	var bob := sin(_elapsed * 3.3 + float(get_instance_id() % 11)) * 0.07
	var hidden_offset := -0.58 if enemy_kind == "ambusher" and not _ambush_revealed else 0.0
	_root.position.y = lerpf(_root.position.y, bob + hidden_offset, minf(1.0, delta * 12.0))
	var target_scale := Vector3(1.0, 0.24, 1.0) if enemy_kind == "ambusher" and not _ambush_revealed else Vector3.ONE
	_root.scale = _root.scale.lerp(target_scale, minf(1.0, delta * 14.0))
	_appendages.rotation.y += delta * (1.5 if ai_state == "attack" else 0.35)
	_tell_ring.visible = ai_state == "telegraph"
	if _tell_ring.visible:
		_tell_ring.scale = Vector3.ONE * (1.0 + sin(_elapsed * 8.0) * 0.14)
		_tell_ring.rotation.y += delta * 2.5
	var target_color := _base_color
	if ai_state == "dead":
		target_color = _base_color.darkened(0.72)
	elif ai_state == "stagger":
		target_color = Color(1.0, 0.55, 0.34)
	if _shell_material != null:
		_shell_material.albedo_color = _shell_material.albedo_color.lerp(target_color, minf(1.0, delta * 13.0))
	if _core_material != null:
		var pulse := 1.7 + sin(_elapsed * (7.0 if ai_state == "telegraph" else 2.4)) * 0.45
		_core_material.emission_energy_multiplier = pulse


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_root = Node3D.new()
	_root.name = "VisualRoot"
	add_child(_root)
	_base_color = COLORS[enemy_kind]
	_shell_material = _material(_base_color, 0.42, 0.66)
	_core_material = _material(_base_color.lightened(0.42), 0.18, 0.32, true)
	_appendages = Node3D.new()
	_appendages.name = "Appendages"
	_root.add_child(_appendages)

	var body_size := Vector3(1.25, 1.15, 1.25)
	if enemy_kind == "boss":
		body_size = Vector3(2.3, 2.1, 2.3)
	elif enemy_kind in ["ranged_caster", "summoner"]:
		body_size = Vector3(1.05, 1.5, 1.05)
	elif enemy_kind == "ambusher":
		body_size = Vector3(1.45, 0.72, 1.45)
	_shell = _add_capsule("Shell", Vector3(0, body_size.y * 0.54, 0), body_size, _shell_material, _root)
	_core = _add_sphere("Core", Vector3(0, body_size.y * 0.75, -body_size.z * 0.48), body_size.x * 0.20, _core_material, _root)

	match enemy_kind:
		"melee_chaser":
			_add_claws(0.84, 0.50)
		"ranged_caster":
			_add_orbitals(3, 0.90)
		"summoner":
			_add_orbitals(4, 1.02)
			_add_cylinder("Crown", Vector3(0, 1.72, 0), 0.42, 0.12, _core_material, _appendages)
		"shielded":
			_add_box("FrontShield", Vector3(0, 0.82, -0.84), Vector3(1.65, 1.25, 0.15), _material(Color(0.20, 0.28, 0.25), 0.78, 0.28), _appendages)
		"exploder":
			for side in [-1.0, 1.0]:
				_add_cylinder("Tank", Vector3(side * 0.56, 0.75, 0.18), 0.25, 0.86, _core_material, _appendages)
		"ambusher":
			_add_claws(1.05, 0.32)
		"boss":
			_add_claws(1.45, 0.82)
			_add_orbitals(5, 1.72)
			_add_box("BossPlate", Vector3(0, 1.33, -1.18), Vector3(1.6, 0.72, 0.16), _material(Color(0.10, 0.12, 0.11), 0.82, 0.26), _appendages)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = body_size.x * 0.62
	ring_mesh.outer_radius = body_size.x * 0.72
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 5
	ring_mesh.material = _material(Color(1.0, 0.20, 0.08, 0.76), 0.0, 0.55, true, true)
	_tell_ring = MeshInstance3D.new()
	_tell_ring.name = "StateVFX"
	_tell_ring.position.y = 0.055
	_tell_ring.mesh = ring_mesh
	_tell_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_root.add_child(_tell_ring)


func _add_claws(radius: float, height: float) -> void:
	for side in [-1.0, 1.0]:
		var claw := _add_box("Claw", Vector3(side * radius, height, -0.34), Vector3(0.34, 0.32, 0.94), _shell_material, _appendages)
		claw.rotation.y = side * 0.34


func _add_orbitals(count: int, radius: float) -> void:
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		_add_sphere("Orbital", Vector3(cos(angle) * radius, 1.05 + sin(angle * 2.0) * 0.18, sin(angle) * radius), 0.18, _core_material, _appendages)


func _add_capsule(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = size.x * 0.5
	mesh.height = size.y
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _add_sphere(node_name: String, position: Vector3, radius: float, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _add_cylinder(node_name: String, position: Vector3, radius: float, height: float, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _mesh_instance(node_name: String, position: Vector3, mesh: PrimitiveMesh, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _material(color: Color, metallic: float, roughness: float, emission := false, alpha := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.7
	if alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
