class_name TrainingTarget3D
extends AnimatableBody3D

signal damaged(target: TrainingTarget3D, applied: int, critical: bool)
signal destroyed(target: TrainingTarget3D)

@export_enum("standard", "armored", "runner") var target_type := "standard"
var max_hp := 100
var current_hp := 100
var _origin := Vector3.ZERO
var _elapsed := 0.0
var _active := true
var _body_material: StandardMaterial3D
var _label: Label3D


func configure(type_id: String) -> void:
	target_type = type_id


func _ready() -> void:
	add_to_group("training_target_3d")
	add_to_group("enemy_3d")
	collision_layer = 4
	collision_mask = 0
	max_hp = 160 if target_type == "armored" else 100
	current_hp = max_hp
	_origin = position
	_build_visual()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if target_type == "runner" and _active:
		position.x = _origin.x + sin(_elapsed * 1.55) * 3.2


func take_damage(amount: int, critical := false, _hit_direction := Vector3.ZERO) -> void:
	if not _active:
		return
	var applied := maxi(1, int(amount * 0.58)) if target_type == "armored" else amount
	if critical:
		applied = int(applied * 1.5)
	current_hp = maxi(0, current_hp - applied)
	damaged.emit(self, applied, critical)
	_body_material.albedo_color = Color.WHITE
	_label.text = "%s\n%d/%d" % [target_type.to_upper(), current_hp, max_hp]
	if current_hp <= 0:
		_active = false
		destroyed.emit(self)
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3(1.25, 0.08, 1.25), 0.18)
		tween.tween_interval(0.65)
		tween.tween_callback(reset_target)


func apply_slow(_factor: float, _duration: float) -> void:
	pass


func reset_target() -> void:
	current_hp = max_hp
	_active = true
	scale = Vector3.ONE
	position = _origin
	_body_material.albedo_color = _target_color()
	_label.text = "%s\n%d/%d" % [target_type.to_upper(), current_hp, max_hp]


func get_snapshot() -> Dictionary:
	return {"target_type": target_type, "hp": current_hp, "max_hp": max_hp, "active": _active, "is_3d": true}


func _build_visual() -> void:
	_body_material = _material(_target_color(), 0.45 if target_type == "armored" else 0.16, 0.52)
	var glow := _material(Color(1.0, 0.28, 0.12), 0.1, 0.3, true)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.5
	body_mesh.radial_segments = 12
	body_mesh.rings = 6
	body_mesh.material = _body_material
	var body := MeshInstance3D.new()
	body.position.y = 0.78
	body.mesh = body_mesh
	add_child(body)
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.22
	core_mesh.height = 0.44
	core_mesh.radial_segments = 10
	core_mesh.rings = 5
	core_mesh.material = glow
	var core := MeshInstance3D.new()
	core.position = Vector3(0, 0.95, -0.55)
	core.mesh = core_mesh
	add_child(core)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.58
	shape.height = 1.5
	var collision := CollisionShape3D.new()
	collision.position.y = 0.78
	collision.shape = shape
	add_child(collision)
	_label = Label3D.new()
	_label.position = Vector3(0, 2.0, 0)
	_label.text = "%s\n%d/%d" % [target_type.to_upper(), current_hp, max_hp]
	_label.font_size = 38
	_label.pixel_size = 0.011
	_label.outline_size = 8
	_label.modulate = _target_color().lightened(0.22)
	add_child(_label)


func _target_color() -> Color:
	return {"standard": Color(0.30, 0.72, 0.82), "armored": Color(0.78, 0.44, 0.16), "runner": Color(0.50, 0.78, 0.30)}.get(target_type, Color.WHITE)


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
