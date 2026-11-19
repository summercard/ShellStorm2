class_name PlatformSentinelWeakPoint3D
extends StaticBody3D

signal damaged(current: int)
signal destroyed

var max_hp := 1
var current_hp := 1
var ai_state := "dead"
var _enabled := false
const RELAY_LAMP := preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/soft_emission.tres")
var _indicator: MeshInstance3D
var _wrist: CollisionShape3D
var _wrist_lamp: MeshInstance3D

func configure(hp: int, radius: float) -> void:
	max_hp = hp
	current_hp = hp
	collision_layer = 0
	collision_mask = 0
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var collision := CollisionShape3D.new()
	collision.shape = sphere
	add_child(collision)
	var cage := SphereMesh.new()
	cage.radius = radius * 0.85
	cage.height = cage.radius * 2.0
	cage.radial_segments = 8
	cage.rings = 4
	_indicator = MeshInstance3D.new()
	_indicator.mesh = PlatformSentinelDeck3D.palette_mesh(cage, Vector2(0.95, 0.45))
	_indicator.material_override = RELAY_LAMP
	add_child(_indicator)
	_indicator.hide()
	add_to_group("damageable_3d")
	add_to_group("aim_assist_target_3d")

func set_open(enabled: bool) -> void:
	_enabled = enabled and current_hp > 0
	ai_state = "idle" if _enabled else "dead"
	set_deferred("collision_layer", 4 if _enabled else 0)
	_indicator.visible = _enabled
	if not _enabled:
		hide_wrist()


func add_wrist() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.72
	_wrist = CollisionShape3D.new()
	_wrist.shape = sphere
	_wrist.disabled = true
	add_child(_wrist)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.54
	ring.bottom_radius = 0.56
	ring.height = 0.44
	ring.radial_segments = 8
	_wrist_lamp = MeshInstance3D.new()
	_wrist_lamp.mesh = PlatformSentinelDeck3D.palette_mesh(ring, Vector2(0.45, 0.25))
	_wrist_lamp.material_override = RELAY_LAMP
	_wrist.add_child(_wrist_lamp)
	_wrist_lamp.hide()


func expose_wrist(point: Vector3) -> void:
	if not _enabled or _wrist == null:
		return
	_wrist.global_position = point
	if not _wrist_lamp.visible:
		_wrist.set_deferred("disabled", false)
		_wrist_lamp.show()


func hide_wrist() -> void:
	if _wrist != null and _wrist_lamp.visible:
		_wrist.set_deferred("disabled", true)
		_wrist_lamp.hide()


func get_melee_hit_points() -> Array[Vector3]:
	var points: Array[Vector3] = [global_position]
	if is_instance_valid(_wrist_lamp) and _wrist_lamp.visible:
		points.append(_wrist.global_position)
	return points


func get_aim_assist_points() -> Array[Vector3]:
	return get_melee_hit_points() if _enabled else []


func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO, _knockback := 0.0) -> void:
	if not _enabled or amount <= 0:
		return
	current_hp = maxi(0, current_hp - amount)
	damaged.emit(current_hp)
	if current_hp == 0:
		set_open(false)
		destroyed.emit()
