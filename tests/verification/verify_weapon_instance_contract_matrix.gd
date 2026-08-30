extends Node

const RANGED_WEAPONS := {
	"weapon_pistol": ["bp_pistol", "GunBody_Pistol"],
	"weapon_shotgun": ["bp_shotgun", "GunBody_Shotgun"],
	"weapon_rifle": ["bp_rifle", "GunBody_Rifle"],
	"weapon_machinegun": ["bp_machinegun", "GunBody_Machinegun"],
	"weapon_sniper": ["bp_sniper", "GunBody_Sniper"],
	"weapon_launcher": ["bp_launcher", "GunBody_Launcher"],
	"weapon_charge": ["bp_charge", "GunBody_Charge"],
}

const BULLETS := {
	"mod_bullet_standard": "Bullet_Standard",
	"mod_bullet_sticky": "Bullet_Sticky",
	"mod_bullet_bounce": "Bullet_Bounce",
	"mod_bullet_piercing": "Bullet_Piercing",
	"mod_bullet_explosive": "Bullet_Explosive",
	"mod_bullet_homing": "Bullet_Homing",
	"mod_bullet_blackhole": "Bullet_Blackhole",
	"mod_bullet_balloon": "Bullet_Balloon",
}

const MELEE_WEAPONS := {
	"weapon_baseball_bat": ["bp_baseball_bat", "Melee_BaseballBat"],
	"weapon_greatblade": ["bp_greatblade", "Melee_Greatblade"],
	"weapon_waraxe": ["bp_waraxe", "Melee_Waraxe"],
}


func _ready() -> void:
	var failures: Array[String] = []
	for content_id in RANGED_WEAPONS.keys():
		var expected := RANGED_WEAPONS[content_id] as Array
		for bullet_id in BULLETS.keys():
			_verify_contract(
				str(content_id), str(expected[0]), str(expected[1]), str(bullet_id),
				str(BULLETS[bullet_id]), false, failures
			)
	for content_id in MELEE_WEAPONS.keys():
		var expected := MELEE_WEAPONS[content_id] as Array
		_verify_contract(
			str(content_id), str(expected[0]), str(expected[1]), "", "", true, failures
		)
	if failures.is_empty():
		print("WEAPON_INSTANCE_CONTRACT_MATRIX_OK: 7 gun bodies x 8 bullets and 3 melee roots round-trip through ItemRegistry, WeaponInstance and BlueprintRegistry")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_contract(
	content_id: String,
	expected_assembly_id: String,
	expected_root_name: String,
	bullet_id: String,
	expected_bullet_name: String,
	expect_melee: bool,
	failures: Array[String]
) -> void:
	var item := ItemRegistry.get_instance().get_item(content_id)
	if item.is_empty():
		failures.append("ItemRegistry is missing %s" % content_id)
		return
	if not bullet_id.is_empty():
		item["bullet_module_id"] = bullet_id
	var instance := WeaponInstance.from_item(item)
	if instance == null:
		failures.append("WeaponInstance.from_item rejected %s" % content_id)
		return
	if instance.weapon_content_id != content_id:
		failures.append("%s content ID became %s" % [content_id, instance.weapon_content_id])
	if instance.assembly_id != expected_assembly_id:
		failures.append("%s assembly ID became %s; expected %s" % [content_id, instance.assembly_id, expected_assembly_id])
	var tree := instance.build_runtime_tree()
	if tree == null or tree.get_root() == null:
		failures.append("%s cannot rebuild root %s; snapshot=%s" % [content_id, expected_root_name, instance.assembly_snapshot])
		if tree != null:
			tree.free()
		return
	var root := tree.get_root()
	if root.node_name != expected_root_name:
		failures.append("%s rebuilt %s; expected %s; snapshot=%s" % [content_id, root.node_name, expected_root_name, instance.assembly_snapshot])
	if ("melee" in root.tags) != expect_melee:
		failures.append("%s melee tag contract is incorrect: %s" % [content_id, root.tags])
	var bullet := root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	if expect_melee and bullet != null:
		failures.append("%s incorrectly rebuilt with bullet %s" % [content_id, bullet.node_name])
	elif not expect_melee and (bullet == null or bullet.node_name != expected_bullet_name):
		failures.append("%s + %s rebuilt bullet %s; expected %s" % [content_id, bullet_id, bullet.node_name if bullet != null else "<null>", expected_bullet_name])
	var round_trip := WeaponInstance.from_item(instance.to_item_dictionary(), tree)
	if round_trip == null:
		failures.append("%s failed item-instance-tree round trip" % content_id)
	else:
		if round_trip.weapon_instance_id != instance.weapon_instance_id:
			failures.append("%s changed instance ID during round trip" % content_id)
		if round_trip.weapon_content_id != content_id or round_trip.assembly_id != expected_assembly_id:
			failures.append("%s changed stable IDs during round trip" % content_id)
	tree.free()
