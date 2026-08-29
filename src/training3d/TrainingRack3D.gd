class_name TrainingRack3D
extends Area3D

signal selected(rack: TrainingRack3D, item_id: String, category: String)

@export_enum("gunbody", "bullet") var category := "gunbody"
var item_id := ""
var display_name := ""
var tags: Array[String] = []
var _player_in_range := false
var _prompt: Label3D
var _glow_material: StandardMaterial3D


func configure(entry: Dictionary, category_id: String) -> void:
	category = category_id
	item_id = str(entry.get("item_id", entry.get("id", "")))
	display_name = str(entry.get("display_name", entry.get("name", item_id)))
	tags.assign(entry.get("tags", []))


func _ready() -> void:
	add_to_group("training_rack_3d")
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func get_interaction_candidate(_player: Player3D) -> Dictionary:
	if not _player_in_range:
		return {}
	return {
		"available": true,
		"interaction_id": "training_rack:%s:%s" % [category, item_id],
		"position": global_position,
		"priority": 60,
		"prompt": _prompt.text if _prompt != null else "[E] %s" % display_name,
	}


func set_interaction_focus(_candidate: Dictionary, focused: bool) -> void:
	if _prompt != null:
		_prompt.visible = focused and _player_in_range


func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
	if not _player_in_range:
		return false
	selected.emit(self, item_id, category)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 1.12, 0.08)
	tween.tween_property(self, "scale", Vector3.ONE, 0.12)
	return true


func get_snapshot() -> Dictionary:
	return {"item_id": item_id, "category": category, "display_name": display_name, "tags": tags.duplicate(), "is_3d": true}


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_3d"):
		_player_in_range = false
		_prompt.visible = false


func _build_visual() -> void:
	var base_material := _material(Color(0.10, 0.12, 0.12), 0.72, 0.44)
	var accent_color := Color(0.28, 0.76, 1.0) if category == "gunbody" else Color(1.0, 0.56, 0.18)
	_glow_material = _material(accent_color, 0.18, 0.28, true)
	_add_box("Pedestal", Vector3(0, 0.35, 0), Vector3(1.7, 0.7, 1.0), base_material)
	_add_box("GlowStrip", Vector3(0, 0.60, -0.52), Vector3(1.28, 0.10, 0.05), _glow_material)
	if category == "gunbody":
		var weapon_scene := load("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn") as PackedScene
		var weapon := weapon_scene.instantiate() as WeaponModel3D
		weapon.display_only = true
		weapon.gun_id = item_id
		weapon.bullet_id = "mod_bullet_standard"
		weapon.position = Vector3(0, 1.05, 0.28)
		weapon.rotation.y = PI * 0.5
		weapon.scale = Vector3.ONE * 0.62
		add_child(weapon)
	else:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.16
		mesh.bottom_radius = 0.16
		mesh.height = 0.58
		mesh.radial_segments = 12
		mesh.material = _glow_material
		var cartridge := MeshInstance3D.new()
		cartridge.name = "BulletModule"
		cartridge.position = Vector3(0, 1.0, 0)
		cartridge.rotation_degrees.z = 90.0
		cartridge.mesh = mesh
		add_child(cartridge)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 2.2, 2.0)
	var collision := CollisionShape3D.new()
	collision.position.y = 0.9
	collision.shape = shape
	add_child(collision)
	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 1.85, 0)
	_prompt.text = "[E] %s" % display_name
	_prompt.font_size = 34
	_prompt.pixel_size = 0.011
	_prompt.modulate = accent_color.lightened(0.18)
	_prompt.outline_size = 7
	_prompt.visible = false
	add_child(_prompt)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	add_child(instance)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.7
	return material
