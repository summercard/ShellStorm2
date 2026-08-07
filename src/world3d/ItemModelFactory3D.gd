class_name ItemModelFactory3D
extends RefCounted
## 世界拾取与背包图标共用的 3D 道具模型工厂，避免维护两套外观。

const WEAPON_SCENE: PackedScene = preload("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn")


static func create_model(item: Dictionary, _tint := Color(0.38, 0.88, 0.72)) -> Node3D:
	var root := Node3D.new()
	root.name = "ItemModel3D"
	var kind := get_model_kind(item)
	var model_tint := get_item_color(item)
	if item.has("display_color") and item["display_color"] is Color:
		model_tint = item["display_color"] as Color
	match kind:
		"weapon":
			_build_weapon(root, item)
		"backpack":
			_build_backpack(root, item, model_tint)
		"bullet":
			_build_bullet(root, item, model_tint)
		"attachment":
			_build_attachment(root, model_tint)
		"key":
			_build_key(root)
		"heal":
			_build_canister(root, Color(0.30, 0.92, 0.52), "heal")
		"ammo":
			_build_canister(root, Color(0.30, 0.72, 1.0), "ammo")
		"beacon":
			_build_beacon(root)
		"blueprint":
			_build_blueprint(root)
		"currency":
			_build_currency(root)
		_:
			_build_crate(root, model_tint)
	root.set_meta("model_kind", kind)
	return root


static func get_item_color(item: Dictionary) -> Color:
	var kind := get_model_kind(item)
	var type_color := {
		"weapon": Color(0.96, 0.52, 0.12),
		"backpack": Color(0.16, 0.78, 0.72),
		"bullet": Color(0.26, 0.66, 1.0),
		"attachment": Color(0.70, 0.40, 1.0),
		"key": Color(1.0, 0.72, 0.16),
		"heal": Color(0.24, 0.94, 0.50),
		"ammo": Color(0.20, 0.68, 1.0),
		"beacon": Color(1.0, 0.34, 0.10),
		"blueprint": Color(0.20, 0.76, 1.0),
		"currency": Color(1.0, 0.72, 0.12),
		"crate": Color(0.80, 0.56, 0.22),
	}.get(kind, Color(0.34, 0.86, 0.72)) as Color
	var rarity_color := {
		"uncommon": Color(0.28, 0.90, 0.48),
		"rare": Color(0.22, 0.60, 1.0),
		"epic": Color(0.68, 0.34, 1.0),
		"legendary": Color(1.0, 0.48, 0.10),
	}.get(str(item.get("rarity", "common")), type_color) as Color
	return type_color.lerp(rarity_color, 0.42).lightened(0.08)


static func get_model_kind(item: Dictionary) -> String:
	var item_id := str(item.get("id", ""))
	var item_type := str(item.get("type", ""))
	var subtype := str(item.get("subtype", ""))
	if bool(item.get("is_currency", false)) or item_id == "__currency__":
		return "currency"
	if item_id == "item_room_key" or subtype == "key":
		return "key"
	if item_type == "weapon" or subtype == "gun_body":
		return "weapon"
	if item_type == "equipment" and subtype == "backpack":
		return "backpack"
	if subtype == "bullet":
		return "bullet"
	if item_type == "attachment" or subtype in ["muzzle", "magazine", "mount"]:
		return "attachment"
	if str(item.get("use_action", "")) == "heal":
		return "heal"
	if str(item.get("use_action", "")) == "refill_ammo":
		return "ammo"
	if item_id == "item_beacon":
		return "beacon"
	if item_type == "blueprint":
		return "blueprint"
	return "crate"


static func count_mesh_instances(root: Node) -> int:
	var count := 1 if root is MeshInstance3D else 0
	for child in root.get_children():
		count += count_mesh_instances(child)
	return count


static func _build_weapon(root: Node3D, item: Dictionary) -> void:
	var weapon := WEAPON_SCENE.instantiate() as WeaponModel3D
	weapon.name = "WeaponModel"
	weapon.display_only = true
	weapon.gun_id = str(item.get("assembly_id", "bp_pistol"))
	weapon.bullet_id = "mod_bullet_standard"
	if str(item.get("type", "")) == "weapon":
		weapon.set_meta("weapon_item_data", item.duplicate(true))
		var upgrades: Variant = item.get("fate_upgrades", [])
		weapon.set_meta("fate_slot_used", upgrades.size() if upgrades is Array else 0)
	weapon.rotation_degrees = Vector3(-12.0, -32.0, 0.0)
	weapon.scale = Vector3.ONE * 0.88
	root.add_child(weapon)


static func _build_backpack(root: Node3D, item: Dictionary, tint: Color) -> void:
	var extra_slots := clampi(int(item.get("extra_slots", 2)), 2, 8)
	var size_by_slots := {
		2: Vector3(0.56, 0.60, 0.28),
		4: Vector3(0.66, 0.74, 0.33),
		8: Vector3(0.76, 0.88, 0.38),
	}
	var body_size := size_by_slots.get(extra_slots, size_by_slots[2]) as Vector3
	var shell := _material(tint.darkened(0.12), 0.18, 0.68)
	var panel := _material(tint, 0.24, 0.62, 0.10)
	var strap := _material(tint.darkened(0.48), 0.10, 0.82)
	_add_box(root, "BackpackBody", Vector3.ZERO, body_size, shell)
	_add_box(
		root, "TopFlap",
		Vector3(0, body_size.y * 0.34, -body_size.z * 0.54),
		Vector3(body_size.x * 0.88, body_size.y * 0.24, body_size.z * 0.12), panel
	)
	for side in [-1.0, 1.0]:
		_add_box(
			root, "ShoulderStrapL" if side < 0.0 else "ShoulderStrapR",
			Vector3(side * body_size.x * 0.31, 0.02, body_size.z * 0.56),
			Vector3(body_size.x * 0.12, body_size.y * 0.92, body_size.z * 0.08), strap
		)
	var pocket_count := 1 if extra_slots == 2 else 2 if extra_slots == 4 else 3
	for pocket_index in range(pocket_count):
		var pocket_x := (float(pocket_index) - float(pocket_count - 1) * 0.5) * body_size.x * 0.31
		_add_box(
			root, "CapacityPocket_%d" % pocket_index,
			Vector3(pocket_x, -body_size.y * 0.30, -body_size.z * 0.56),
			Vector3(body_size.x * (0.48 if pocket_count == 1 else 0.27), body_size.y * 0.25, body_size.z * 0.18),
			panel
		)
	root.set_meta("backpack_extra_slots", extra_slots)


static func _build_bullet(root: Node3D, item: Dictionary, fallback: Color) -> void:
	var bullet_color := fallback
	var assembly_id := str(item.get("assembly_id", item.get("id", "")))
	if WeaponModel3D.BULLET_COLORS.has(assembly_id):
		bullet_color = WeaponModel3D.BULLET_COLORS[assembly_id]
	_add_cylinder(root, "Casing", Vector3(0, 0.12, 0), 0.16, 0.78, _material(Color(0.68, 0.56, 0.30), 0.82, 0.28))
	_add_sphere(root, "Tip", Vector3(0, 0.55, 0), Vector3(0.16, 0.24, 0.16), _material(bullet_color, 0.30, 0.32, 0.55))
	root.rotation_degrees.z = -28.0


static func _build_attachment(root: Node3D, tint: Color) -> void:
	var metal := _material(tint.darkened(0.32), 0.76, 0.28)
	var accent := _material(tint, 0.42, 0.30, 0.32)
	_add_box(root, "Mount", Vector3.ZERO, Vector3(0.62, 0.24, 0.34), metal)
	_add_cylinder(root, "Optic", Vector3(0, 0.24, 0), 0.13, 0.64, accent, Vector3(90, 0, 0))


static func _build_key(root: Node3D) -> void:
	var gold := _material(Color(1.0, 0.72, 0.18), 0.72, 0.26, 0.38)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.19
	ring_mesh.outer_radius = 0.30
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 10
	ring_mesh.material = gold
	var ring := MeshInstance3D.new()
	ring.name = "KeyRing"
	ring.position = Vector3(0, 0.36, 0)
	ring.rotation_degrees.x = 90.0
	ring.mesh = ring_mesh
	root.add_child(ring)
	_add_box(root, "KeyStem", Vector3(0, -0.05, 0), Vector3(0.14, 0.64, 0.12), gold)
	_add_box(root, "KeyToothA", Vector3(0.15, -0.34, 0), Vector3(0.38, 0.13, 0.12), gold)
	_add_box(root, "KeyToothB", Vector3(0.10, -0.20, 0), Vector3(0.28, 0.12, 0.12), gold)
	root.rotation_degrees.z = -24.0


static func _build_canister(root: Node3D, color: Color, kind: String) -> void:
	var shell := _material(Color(0.13, 0.17, 0.18), 0.68, 0.32)
	var glow := _material(color, 0.18, 0.26, 0.62)
	_add_cylinder(root, "Canister", Vector3.ZERO, 0.28, 0.82, shell)
	_add_cylinder(root, "Core", Vector3(0, 0.02, 0), 0.20, 0.54, glow)
	_add_box(root, "MarkA", Vector3(0, 0.02, -0.285), Vector3(0.10 if kind == "heal" else 0.24, 0.38 if kind == "heal" else 0.08, 0.025), glow)
	if kind == "heal":
		_add_box(root, "MarkB", Vector3(0, 0.02, -0.30), Vector3(0.38, 0.10, 0.025), glow)


static func _build_beacon(root: Node3D) -> void:
	var dark := _material(Color(0.08, 0.11, 0.12), 0.78, 0.30)
	var glow := _material(Color(0.98, 0.42, 0.12), 0.20, 0.22, 0.85)
	_add_cylinder(root, "Base", Vector3(0, -0.30, 0), 0.42, 0.24, dark)
	_add_cylinder(root, "Antenna", Vector3(0, 0.12, 0), 0.08, 0.76, dark)
	_add_sphere(root, "Signal", Vector3(0, 0.60, 0), Vector3.ONE * 0.18, glow)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.30
	ring_mesh.outer_radius = 0.34
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	ring_mesh.material = glow
	var ring := MeshInstance3D.new()
	ring.name = "SignalRing"
	ring.position.y = 0.58
	ring.mesh = ring_mesh
	root.add_child(ring)


static func _build_blueprint(root: Node3D) -> void:
	var paper := _material(Color(0.18, 0.54, 0.78), 0.08, 0.72, 0.28)
	var ink := _material(Color(0.66, 0.92, 1.0), 0.05, 0.76, 0.42)
	_add_box(root, "Card", Vector3.ZERO, Vector3(0.82, 0.06, 1.02), paper)
	_add_box(root, "LineA", Vector3(0, -0.045, -0.18), Vector3(0.58, 0.025, 0.06), ink)
	_add_box(root, "LineB", Vector3(-0.12, -0.045, 0.05), Vector3(0.34, 0.025, 0.06), ink)
	root.rotation_degrees = Vector3(-18, 18, -10)


static func _build_currency(root: Node3D) -> void:
	var gold := _material(Color(1.0, 0.70, 0.14), 0.78, 0.24, 0.42)
	_add_cylinder(root, "SoulCoin", Vector3.ZERO, 0.38, 0.13, gold, Vector3(90, 0, 0))
	_add_sphere(root, "SoulCore", Vector3(0, 0, -0.10), Vector3.ONE * 0.18, gold)


static func _build_crate(root: Node3D, tint: Color) -> void:
	var shell := _material(tint.darkened(0.26), 0.48, 0.48)
	var accent := _material(tint, 0.26, 0.36, 0.35)
	_add_box(root, "Crate", Vector3.ZERO, Vector3(0.72, 0.62, 0.72), shell)
	_add_box(root, "BandA", Vector3(0, 0, -0.37), Vector3(0.12, 0.66, 0.035), accent)
	_add_box(root, "BandB", Vector3(0, 0, -0.385), Vector3(0.76, 0.12, 0.035), accent)


static func _add_box(root: Node3D, node_name: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	root.add_child(instance)
	return instance


static func _add_cylinder(root: Node3D, node_name: String, position: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.mesh = mesh
	root.add_child(instance)
	return instance


static func _add_sphere(root: Node3D, node_name: String, position: Vector3, scale: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 18
	mesh.rings = 10
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.scale = scale
	instance.mesh = mesh
	root.add_child(instance)
	return instance


static func _material(color: Color, metallic: float, roughness: float, emission_energy := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
