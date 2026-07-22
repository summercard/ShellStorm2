class_name RoomKeyPickup3D
extends Area3D
## 清房奖励钥匙。与 2D 一致，玩家接触后自动拾取。

signal collected(room_id: String)

var room_id := ""
var _picked := false
var _visual: Node3D


func configure(p_room_id: String) -> void:
	room_id = p_room_id


func _ready() -> void:
	add_to_group("room_key_pickup_3d")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	_build_visual()


func _process(delta: float) -> void:
	if _visual != null:
		_visual.rotation.y += delta * 1.8
		_visual.position.y = 0.72 + sin(Time.get_ticks_msec() * 0.004) * 0.10


func _on_body_entered(body: Node3D) -> void:
	if _picked or not body.is_in_group("player_3d"):
		return
	_picked = true
	collected.emit(room_id)
	queue_free()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "KeyVisual"
	add_child(_visual)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.72, 0.14)
	material.metallic = 0.62
	material.roughness = 0.28
	material.emission_enabled = true
	material.emission = Color(0.80, 0.42, 0.05)
	material.emission_energy_multiplier = 1.4
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.15
	ring_mesh.outer_radius = 0.28
	ring_mesh.rings = 12
	ring_mesh.ring_segments = 8
	ring_mesh.material = material
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.rotation_degrees.x = 90.0
	_visual.add_child(ring)
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.72, 0.12, 0.12)
	shaft_mesh.material = material
	var shaft := MeshInstance3D.new()
	shaft.position.x = 0.44
	shaft.mesh = shaft_mesh
	_visual.add_child(shaft)
	for x in [0.63, 0.80]:
		var tooth_mesh := BoxMesh.new()
		tooth_mesh.size = Vector3(0.11, 0.25, 0.12)
		tooth_mesh.material = material
		var tooth := MeshInstance3D.new()
		tooth.position = Vector3(x, -0.10, 0)
		tooth.mesh = tooth_mesh
		_visual.add_child(tooth)
	var shape := SphereShape3D.new()
	shape.radius = 0.95
	var collision := CollisionShape3D.new()
	collision.position.y = 0.72
	collision.shape = shape
	add_child(collision)
	var label := Label3D.new()
	label.position = Vector3(0.35, 1.35, 0)
	label.text = "房间钥匙"
	label.font_size = 34
	label.pixel_size = 0.011
	label.outline_size = 8
	label.modulate = Color(1.0, 0.84, 0.32)
	add_child(label)
