class_name WeaponModel3D
extends Node3D
## 现有 BlueprintRegistry 的 3D 表现与射击适配层。目录、数值和 56 组枪弹组合仍只有一份来源。

signal shot_fired(projectile_count: int)
signal projectile_spawned(projectile: Projectile3D)
signal ammo_changed(current: int, maximum: int)
signal loadout_changed(gun_id: String, bullet_id: String)

const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")
const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")

const GUN_PROFILES := {
	"bp_pistol": {"length": 0.72, "barrel": 0.32, "width": 0.18, "height": 0.22, "color": Color(0.28, 0.34, 0.34)},
	"bp_shotgun": {"length": 1.02, "barrel": 0.78, "width": 0.25, "height": 0.25, "color": Color(0.36, 0.25, 0.16)},
	"bp_rifle": {"length": 1.10, "barrel": 0.62, "width": 0.21, "height": 0.24, "color": Color(0.20, 0.30, 0.27)},
	"bp_machinegun": {"length": 1.18, "barrel": 0.58, "width": 0.31, "height": 0.30, "color": Color(0.27, 0.29, 0.20)},
	"bp_sniper": {"length": 1.30, "barrel": 1.02, "width": 0.19, "height": 0.22, "color": Color(0.18, 0.24, 0.30)},
	"bp_launcher": {"length": 1.08, "barrel": 0.72, "width": 0.38, "height": 0.36, "color": Color(0.30, 0.22, 0.16)},
	"bp_charge": {"length": 1.12, "barrel": 0.62, "width": 0.32, "height": 0.34, "color": Color(0.28, 0.18, 0.34)},
}

const BULLET_COLORS := {
	"mod_bullet_standard": Color(0.76, 0.86, 0.92),
	"mod_bullet_sticky": Color(0.32, 0.92, 0.62),
	"mod_bullet_bounce": Color(0.30, 0.70, 1.0),
	"mod_bullet_piercing": Color(1.0, 0.78, 0.22),
	"mod_bullet_explosive": Color(1.0, 0.28, 0.08),
	"mod_bullet_homing": Color(0.50, 1.0, 0.42),
	"mod_bullet_blackhole": Color(0.68, 0.25, 0.95),
	"mod_bullet_balloon": Color(0.98, 0.35, 0.72),
}

@export var gun_id := "bp_pistol"
@export var bullet_id := "mod_bullet_standard"
@export var display_only := false

var damage := 20
var fire_rate := 3.5
var projectile_count := 1
var spread := 0.03
var reload_time := 1.5
var magazine_size := 12
var current_ammo := 12
var bullet_speed := 24.0
var bullet_tags: Array[String] = []
var bullet_color := Color(0.76, 0.86, 0.92)

var _cooldown := 0.0
var _reload_remaining := 0.0
var _recoil := 0.0
var _visual_root: Node3D
var _muzzle: Marker3D


func _ready() -> void:
	if not gun_id.is_empty():
		configure(gun_id, bullet_id)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_remaining > 0.0:
		_reload_remaining = maxf(0.0, _reload_remaining - delta)
		if _reload_remaining <= 0.0:
			current_ammo = magazine_size
			ammo_changed.emit(current_ammo, magazine_size)
	_recoil = lerpf(_recoil, 0.0, minf(1.0, delta * 15.0))
	if _visual_root != null:
		_visual_root.position.z = _recoil
		_visual_root.rotation.x = _recoil * 0.22


func configure(p_gun_id: String, p_bullet_id: String) -> bool:
	var gun_node := BlueprintRegistry.create_assembly_node(p_gun_id)
	var bullet_node := BlueprintRegistry.create_assembly_node(p_bullet_id)
	if gun_node == null or bullet_node == null:
		if gun_node != null:
			gun_node.free()
		if bullet_node != null:
			bullet_node.free()
		return false
	gun_id = p_gun_id
	bullet_id = p_bullet_id
	var gun_stats := gun_node.get_base_stats()
	var bullet_stats := bullet_node.get_base_stats()
	bullet_tags.assign(bullet_node.tags)
	damage = int(gun_stats.get("damage", 10)) + int(bullet_stats.get("bullet_damage", 5))
	fire_rate = maxf(0.2, float(gun_stats.get("fire_rate", 3.0)))
	projectile_count = maxi(1, int(gun_stats.get("bullet_count", 1)))
	spread = maxf(0.0, float(gun_stats.get("spread", 0.0)))
	reload_time = maxf(0.25, float(gun_stats.get("reload_time", 1.5)))
	magazine_size = maxi(1, int(gun_stats.get("magazine_size", 12)))
	current_ammo = magazine_size
	bullet_speed = 23.0 * float(bullet_stats.get("bullet_speed", 1.0))
	bullet_color = BULLET_COLORS.get(bullet_id, Color(0.76, 0.86, 0.92))
	gun_node.free()
	bullet_node.free()
	_rebuild_visual()
	loadout_changed.emit(gun_id, bullet_id)
	ammo_changed.emit(current_ammo, magazine_size)
	return true


func clear_weapon() -> void:
	gun_id = ""
	bullet_id = ""
	current_ammo = 0
	magazine_size = 0
	if _visual_root != null:
		_visual_root.queue_free()
		_visual_root = null
	_muzzle = null
	loadout_changed.emit("", "")
	ammo_changed.emit(0, 0)


func try_fire(aim_direction: Vector3, shooter: Node3D) -> bool:
	if display_only or gun_id.is_empty() or _cooldown > 0.0 or _reload_remaining > 0.0:
		return false
	if current_ammo <= 0:
		request_reload()
		return false
	var world := get_tree().current_scene
	if world == null:
		return false
	_cooldown = 1.0 / fire_rate
	current_ammo -= 1
	_recoil = 0.16 if gun_id == "bp_shotgun" or gun_id == "bp_launcher" else 0.09
	for index in range(projectile_count):
		var angle := 0.0
		if projectile_count > 1:
			angle = lerpf(-spread * 0.5, spread * 0.5, float(index) / float(projectile_count - 1))
		elif spread > 0.0:
			angle = randf_range(-spread * 0.5, spread * 0.5)
		var shot_direction := aim_direction.rotated(Vector3.UP, angle).normalized()
		var projectile := PROJECTILE_SCRIPT.new() as Projectile3D
		projectile.configure({
			"direction": shot_direction,
			"speed": bullet_speed,
			"damage": damage,
			"critical": randf() < 0.10,
			"hostile": false,
			"tags": bullet_tags,
			"color": bullet_color,
			"shooter": shooter,
		})
		world.add_child(projectile)
		projectile.global_position = _muzzle.global_position if _muzzle != null else global_position
		projectile_spawned.emit(projectile)
	_spawn_muzzle_effect(world)
	shot_fired.emit(projectile_count)
	ammo_changed.emit(current_ammo, magazine_size)
	if current_ammo <= 0:
		request_reload()
	return true


func request_reload() -> bool:
	if display_only or gun_id.is_empty() or _reload_remaining > 0.0 or current_ammo >= magazine_size:
		return false
	_reload_remaining = reload_time
	return true


func is_reloading() -> bool:
	return _reload_remaining > 0.0


func get_snapshot() -> Dictionary:
	return {
		"gun_id": gun_id,
		"bullet_id": bullet_id,
		"damage": damage,
		"fire_rate": fire_rate,
		"projectile_count": projectile_count,
		"magazine_size": magazine_size,
		"current_ammo": current_ammo,
		"bullet_tags": bullet_tags.duplicate(),
		"has_model": _visual_root != null,
		"is_3d": true,
	}


func _rebuild_visual() -> void:
	if not is_inside_tree():
		return
	if _visual_root != null:
		_visual_root.queue_free()
	_visual_root = Node3D.new()
	_visual_root.name = "GunVisual"
	add_child(_visual_root)
	var profile: Dictionary = GUN_PROFILES.get(gun_id, GUN_PROFILES["bp_pistol"])
	var length := float(profile["length"])
	var barrel := float(profile["barrel"])
	var width := float(profile["width"])
	var height := float(profile["height"])
	var body_color := profile["color"] as Color
	var body_material := _material(body_color, 0.72, 0.34)
	var dark_material := _material(Color(0.055, 0.07, 0.07), 0.84, 0.28)
	var accent_material := _material(bullet_color.darkened(0.14), 0.32, 0.30, true)
	_add_box("Receiver", Vector3(0, 0, -length * 0.42), Vector3(width, height, length), body_material)
	_add_box("Stock", Vector3(0, -0.03, 0.14), Vector3(width * 0.82, height * 0.82, length * 0.34), dark_material)
	_add_box("Grip", Vector3(0, -height * 0.55, -length * 0.30), Vector3(width * 0.48, height * 0.75, 0.18), dark_material)
	_add_cylinder("Barrel", Vector3(0, 0.01, -length - barrel * 0.48), width * (0.26 if gun_id != "bp_launcher" else 0.52), barrel, dark_material)
	if gun_id in ["bp_sniper", "bp_charge"]:
		_add_cylinder("Optic", Vector3(0, height * 0.72, -length * 0.55), width * 0.22, length * 0.48, accent_material)
	if gun_id == "bp_machinegun":
		_add_box("AmmoBox", Vector3(width * 0.70, -height * 0.18, -length * 0.45), Vector3(width * 0.72, height * 1.05, length * 0.42), accent_material)
	if gun_id == "bp_charge":
		for side in [-1.0, 1.0]:
			_add_cylinder("ChargeCoil", Vector3(width * side, 0, -length * 0.72), width * 0.18, length * 0.52, accent_material)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0, -length - barrel)
	_visual_root.add_child(_muzzle)


func _spawn_muzzle_effect(world: Node) -> void:
	if _muzzle == null:
		return
	var effect := EFFECT_SCENE.instantiate() as CombatEffect3D
	effect.configure("muzzle", bullet_color, 1.0)
	world.add_child(effect)
	effect.global_position = _muzzle.global_position


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	_visual_root.add_child(instance)


func _add_cylinder(node_name: String, position: Vector3, radius: float, length: float, material: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 14
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees.x = 90.0
	instance.mesh = mesh
	_visual_root.add_child(instance)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	return material
