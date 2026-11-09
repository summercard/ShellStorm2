class_name MainStoryPedestal3D
extends Node3D
## 永久进度的只读表现：不负责领取、安装或解锁事务。

const SLOT_COUNT := 4
const SLOT_SPACING_M := 0.46
const PULSE_SECONDS := 1.25
const KEY_PATH := "res://assets/art/props/main_story/runtime/rare_earth_key.tscn"
const KEY_IDS := ["mq_key_rare_earth", "mq_key_manor", "mq_key_hotel", "mq_key_sector_04"]
const KEY_COLORS := [Color(0.96, 0.62, 0.12), Color(0.2, 0.78, 0.95), Color(0.72, 0.35, 0.95), Color(0.92, 0.24, 0.3)]

var _facility: Node3D
var _host: Node
var _slots: Array[MeshInstance3D] = []
var _slot_lights: Array[OmniLight3D] = []
var _keys: Array[Node3D] = []
var _ring: Array[MeshInstance3D] = []
var _lines: Array[MeshInstance3D] = []
var _center: MeshInstance3D
var _pulse: MeshInstance3D
var _pulse_tween: Tween
var _installed_count := 0
var _poll := 0.0
var _built := false

func _ready() -> void:
	_build()
	refresh_main_story_key_visuals()

func setup(facility: Node3D, host: Node) -> void:
	_facility = facility
	_host = host
	_place_outside_facility()
	_build()
	refresh_main_story_key_visuals()

func _place_outside_facility() -> void:
	if _facility == null:
		return
	var center := _facility.global_position
	var shape: CollisionShape3D = null
	if _facility.has_method("_find_primary_body_shape"):
		shape = _facility.call("_find_primary_body_shape") as CollisionShape3D
	if shape != null:
		center = shape.global_position
	var front := -_facility.global_basis.z
	if _host != null and _host.has_method("get_main_story_room"):
		var room := _host.call("get_main_story_room", "facility") as Node3D
		if room != null:
			# 选真实旋转碰撞盒面向室内的一面，而非沿模型斜角猜前侧。
			var toward := room.global_position - center
			if shape != null:
				var local := shape.global_basis.inverse() * toward
				front = shape.global_basis.x * signf(local.x) if absf(local.x) > absf(local.z) else shape.global_basis.z * signf(local.z)
			else:
				front = toward
	front.y = 0.0
	if front.length_squared() < 0.001:
		front = Vector3.FORWARD
	front = front.normalized()
	var extent := 1.0
	if shape != null and shape.shape is BoxShape3D:
		var half := (shape.shape as BoxShape3D).size * 0.5
		extent = absf(front.dot(shape.global_basis.x)) * half.x + absf(front.dot(shape.global_basis.z)) * half.z
	var origin := center + front * (extent + 0.55)
	origin.y = _facility.global_position.y
	global_transform = Transform3D(Basis.looking_at(front, Vector3.UP), origin)

func _build() -> void:
	if _built:
		return
	_built = true
	_box("PedestalBase", Vector3(2.65, 0.14, 0.72), Vector3(0, 0.07, 0), Color(0.10, 0.07, 0.17))
	_box("PedestalStem", Vector3(0.32, 0.66, 0.30), Vector3(0, 0.42, 0.12), Color(0.16, 0.09, 0.24))
	_box("SocketConsole", Vector3(2.35, 0.12, 0.68), Vector3(0, 0.82, 0), Color(0.09, 0.23, 0.25))
	for index in SLOT_COUNT:
		var x := (float(index) - 1.5) * SLOT_SPACING_M
		var slot := _box("KeySlot_%d" % index, Vector3(0.34, 0.035, 0.46), Vector3(x, 0.9, 0), Color(0.22, 0.06, 0.10))
		_slots.append(slot)
		var line := _box("EnergyLine_%d" % index, Vector3(0.022, 0.72, 0.022), Vector3(x, 1.25, 0.26), Color(0.16, 0.08, 0.11))
		_lines.append(line)
		var lamp := OmniLight3D.new()
		lamp.name = "KeySlotLight_%d" % index
		lamp.light_color = KEY_COLORS[index]
		lamp.light_energy = 0.0
		lamp.omni_range = 1.4
		lamp.position = slot.position + Vector3.UP * 0.2
		add_child(lamp)
		_slot_lights.append(lamp)
		# 只有第一把已制作，后三槽不假造后续钥匙资产。
		var key: Node3D = null
		if index == 0:
			var scene := load(KEY_PATH) as PackedScene
			key = scene.instantiate() as Node3D
			key.name = "PersistentRareEarthKey"
			add_child(key)
			key.position = slot.position + Vector3(0, 0.07, 0.14)
			key.scale = Vector3.ONE * 0.72
			key.hide()
		_keys.append(key)
	for index in 32:
		var angle := TAU * float(index) / 32.0
		var segment := _box("QuarterRing_%02d" % index, Vector3(0.12, 0.024, 0.045), Vector3(sin(angle) * 0.62, 1.62, cos(angle) * 0.62), Color(0.21, 0.05, 0.09))
		segment.rotation.y = angle
		_ring.append(segment)
	_center = MeshInstance3D.new()
	_center.name = "MainStoryCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.16
	core_mesh.bottom_radius = 0.24
	core_mesh.height = 0.34
	core_mesh.radial_segments = 6
	_center.mesh = core_mesh
	_center.position = Vector3(0, 1.62, 0)
	_center.material_override = _material(Color(0.12, 0.18, 0.24), Color(0.05, 0.2, 0.25), 0.3)
	add_child(_center)
	_pulse = MeshInstance3D.new()
	_pulse.name = "DepositExpansionPulse"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.49
	torus.rings = 32
	torus.ring_segments = 6
	_pulse.mesh = torus
	_pulse.position = Vector3(0, 1.62, 0)
	_pulse.material_override = _material(KEY_COLORS[0], KEY_COLORS[0], 1.2)
	_pulse.hide()
	add_child(_pulse)

func get_anchor(anchor_id: String) -> Variant:
	match anchor_id:
		"mission_operations", "operations", "pedestal_focus":
			return to_global(Vector3(0, 1.15, 0))
		"key_slot_rare_earth":
			return to_global(Vector3(-1.5 * SLOT_SPACING_M, 0.97, 0.14))
		"pedestal_stand":
			return to_global(Vector3(-1.5 * SLOT_SPACING_M, 0, -0.72))
	return null

func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.4:
		_poll = 0.0
		refresh_main_story_key_visuals()

func _snapshot() -> Dictionary:
	if not is_inside_tree():
		return {}
	var base := get_tree().root.get_node_or_null(NodePath("BaseManager"))
	if base != null and base.has_method("get_main_story_snapshot"):
		return base.call("get_main_story_snapshot") as Dictionary
	return {}

func refresh_main_story_key_visuals() -> void:
	if not _built:
		return
	var keys: Dictionary = _snapshot().get("keys", {})
	_installed_count = 0
	for index in SLOT_COUNT:
		var row: Dictionary = keys.get(KEY_IDS[index], {})
		var installed := str(row.get("state", "")) == "deposited" or bool(row.get("deposited", false))
		if installed:
			_installed_count += 1
		var color: Color = KEY_COLORS[index] if installed else Color(0.3, 0.055, 0.09)
		_set_color(_slots[index], color, 0.8 if installed else 0.15)
		_set_color(_lines[index], color, 0.9 if installed else 0.05)
		if _pulse_tween == null or not _pulse_tween.is_running():
			_slot_lights[index].light_energy = 0.18 if installed else 0.0
		if _keys[index] != null:
			_keys[index].visible = installed
	for index in _ring.size():
		var lit := index < _installed_count * 8
		_set_color(_ring[index], KEY_COLORS[0] if lit else Color(0.22, 0.05, 0.09), 1.0 if lit else 0.08)
	_set_color(_center, Color(0.15, 0.65, 0.64) if _installed_count > 0 else Color(0.12, 0.18, 0.24), 0.8 if _installed_count > 0 else 0.1)

func apply_main_story_key_visual(key_id: String) -> void:
	refresh_main_story_key_visuals()
	var index := KEY_IDS.find(key_id)
	if index >= 0 and _installed_count > 0:
		_play_pulse(index)

func get_snapshot() -> Dictionary:
	return {"installed_count": _installed_count, "slot_count": SLOT_COUNT,
		"ring_fraction": float(_installed_count) / 4.0,
		"persistent_key_visible": _keys[0].visible if not _keys.is_empty() else false,
		"anchor_ids": ["mission_operations", "key_slot_rare_earth", "pedestal_stand", "pedestal_focus"]}

func _play_pulse(index: int) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse.show()
	_pulse.scale = Vector3.ONE * 0.3
	_slot_lights[index].light_energy = 0.8
	var line := _lines[index]
	line.scale.y = 0.05
	line.position.y = 0.91
	_pulse_tween = create_tween().set_parallel(true)
	_pulse_tween.tween_property(_pulse, "scale", Vector3.ONE * 2.4, PULSE_SECONDS)
	_pulse_tween.tween_property(_slot_lights[index], "light_energy", 0.18, PULSE_SECONDS)
	_pulse_tween.tween_property(line, "scale:y", 1.0, 0.65)
	_pulse_tween.tween_property(line, "position:y", 1.25, 0.65)
	_pulse_tween.chain().tween_callback(_pulse.hide)

func _box(node_name: String, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color, color, 0.1)
	node.position = point
	add_child(node)
	return node

func _set_color(mesh: MeshInstance3D, color: Color, energy: float) -> void:
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	material.emission_energy_multiplier = energy

func _material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = 0.8
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material
