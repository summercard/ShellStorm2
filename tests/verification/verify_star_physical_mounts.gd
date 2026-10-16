extends Node3D

class Target extends Node3D:
	var hits := 0
	var pushes := 0
	var push_direction := Vector3.ZERO
	func take_damage(_amount: int, _critical := false, _direction := Vector3.ZERO, _knockback := 0.0) -> void:
		hits += 1
	func apply_melee_knockback(direction: Vector3, strength: float, _duration := 0.20) -> void:
		pushes += 1
		push_direction = direction * strength

var failures: Array[String] = []
var samples := 0
var shots: Array[Projectile3D] = []
var shooter: Node3D
var owned_trees: Array[WeaponAssemblyTree] = []

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	samples += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func tree(gun := "bp_rifle") -> WeaponAssemblyTree:
	var result := BlueprintRegistry.build_weapon_tree(gun)
	owned_trees.append(result)
	return result

func apply(target: WeaponAssemblyTree, id: String, source: AssemblyNode = null, reversed := false) -> void:
	for card in FateCardPresets.playable_presets():
		if card.get_stable_card_id() != id:
			continue
		card.set_orientation(FateCard.Orientation.REVERSED if reversed else FateCard.Orientation.UPRIGHT, 0.75 if reversed else 0.25)
		var targets: Array[AssemblyNode] = []
		if source != null:
			targets = [target.root.slots[AssemblyNode.SlotType.BULLET] if id == "fate_bullet_carry_gun" else target.root, source]
		var result := FateCardEngine.apply_card(card, target, targets)
		check(result.success, id + " apply " + result.message)
		return
	check(false, "missing card")

func weapon(source: WeaponAssemblyTree) -> WeaponModel3D:
	var result := WeaponModel3D.new()
	add_child(result)
	result.configure_from_tree(source)
	result.global_position = Vector3(4, 1, 2)
	result.projectile_spawned.connect(func(p: Projectile3D):
		shots.append(p)
		p.set_physics_process(false))
	return result

func fire(gun: WeaponModel3D) -> Projectile3D:
	shots.clear()
	gun._cooldown = 0.0
	gun.try_fire(Vector3.FORWARD, shooter)
	return shots[0] if not shots.is_empty() else null

func _run() -> void:
	shooter = Node3D.new()
	add_child(shooter)
	var source := tree("bp_pistol")
	var source_before := WeaponInstance._serialize_node(source.root)
	for reversed in [false, true]:
		var carrier_tree := tree()
		apply(carrier_tree, "fate_bullet_carry_gun", source.root, reversed)
		var gun := weapon(carrier_tree)
		var p := fire(gun)
		check(p != null and is_instance_valid(p._carried_weapon), "real carried weapon")
		if p == null or not is_instance_valid(p._carried_weapon): continue
		check(p._carried_weapon.gun_id == "bp_pistol", "selected source model")
		var muzzle := p._carried_weapon._muzzle
		var forward := -muzzle.global_basis.z.normalized()
		check(forward.dot(p.direction) < -0.99 if reversed else forward.dot(p.direction) > 0.99, "carried muzzle orientation")
		var emitted: Array[Projectile3D] = []
		p._carried_weapon.projectile_spawned.connect(func(child: Projectile3D): emitted.append(child); child.set_physics_process(false))
		var origin := muzzle.global_position
		p._tick_attached_gun(1.0)
		check(emitted.size() == 1, "autofire without target")
		if not emitted.is_empty():
			check(emitted[0].global_position.distance_to(origin) < 0.001, "actual carried muzzle origin")
			check(emitted[0].direction.dot(forward) > 0.999, "shot follows carried muzzle")
		p.activate({"direction": Vector3.FORWARD, "behavior": {}}, Vector3(3, 1, 2))
		p.set_physics_process(false)
		check(not is_instance_valid(p._carried_weapon), "reuse clears mount")
	check(WeaponInstance._serialize_node(source.root) == source_before, "source unmodified")
	var mounts := tree()
	for index in range(3): apply(mounts, "fate_gun_on_gun", source.root)
	var main := weapon(mounts)
	check(main._fate_mounts.size() == 3, "three physical mount points")
	var last_x := -INF
	for entry in main._fate_mounts:
		var point := entry["point"] as Marker3D
		check(point.position.x > last_x and is_equal_approx(point.scale.x, 0.22), "horizontal order and idle scale")
		last_x = point.position.x
	fire(main)
	check(shots.size() == 4, "main plus three independent guns")
	if shots.size() == 4:
		for index in range(3):
			var mounted := main._fate_mounts[index]["weapon"] as WeaponModel3D
			check(shots[index + 1].global_position.distance_to(mounted._muzzle.global_position) < 0.001, "identical copies use distinct muzzles")
		check(shots[1].global_position.distance_to(shots[3].global_position) > 0.5, "three origins really spread horizontally")
	for entry in main._fate_mounts: check(is_equal_approx(entry["point"].scale.x, 0.65), "firing expands mounts")
	main._process(0.2)
	check(is_equal_approx(main._fate_mounts[0]["point"].scale.x, 0.22), "idle shrinks mount")
	main.display_only = true
	main._mount_pulse = 1.0
	main._update_fate_mounts()
	check(is_equal_approx(main._fate_mounts[0]["point"].scale.x, 0.22), "stowed shrinks mount")
	var player := preload("res://scenes/Player3D.tscn").instantiate() as Player3D
	add_child(player)
	player.set_physics_process(false)
	var rear_tree := tree()
	apply(rear_tree, "fate_gun_on_gun", source.root, true)
	var rear_gun := weapon(rear_tree)
	rear_gun.reparent(player)
	player.global_position = Vector3(12, -20, 8)
	player.rotation.y = PI * 0.5
	rear_gun._update_fate_mounts()
	var rear_point := rear_gun._fate_mounts[0]["point"] as Marker3D
	check(player.to_local(rear_point.global_position).distance_to(Vector3(0, 0.85, 0.65)) < 0.001, "reverse mount follows rotated player back")
	player.global_position += Vector3(3, 0, 4)
	rear_gun._update_fate_mounts()
	check(player.to_local(rear_point.global_position).distance_to(Vector3(0, 0.85, 0.65)) < 0.001, "rear mount follows walking")
	player.free()
	var pool := VfxPool3D.new()
	add_child(pool)
	var burst := pool.acquire(VfxPool3D.FX01_FATE_ROCK_SHATTER, Vector3(4, -20, 2), Color.WHITE, 1.0)
	check(burst.get_child_count() == 8 and burst.find_children("*", "CollisionObject3D").is_empty() and burst.find_children("*", "Light3D").is_empty(), "shatter has eight shards, no collision or lights")
	burst._process(0.6)
	check(not burst.visible, "shatter retires after lifetime")
	var reused := pool.acquire(VfxPool3D.FX01_FATE_ROCK_SHATTER, Vector3(1, -20, 1), Color.WHITE, 0.5)
	check(reused == burst and reused.get_child(0).position.length() < 0.001 and reused.scale.is_equal_approx(Vector3.ONE * 0.5), "shatter reuse resets positions and scale")
	var restored := WeaponAssemblyTree.new()
	owned_trees.append(restored)
	restored.set_root(WeaponInstance._deserialize_node(WeaponInstance._serialize_node(mounts.root)))
	check(weapon(restored)._fate_mounts.size() == 3, "serialization retains mount slots")
	var melee := tree("bp_baseball_bat")
	var melee_carrier := tree()
	apply(melee_carrier, "fate_bullet_carry_gun", melee.root)
	var melee_p := fire(weapon(melee_carrier))
	var target := Target.new()
	add_child(target)
	target.add_to_group("enemies")
	target.global_position = melee_p.global_position + Vector3(0, 0, -0.5)
	melee_p._tick_attached_gun(1.0)
	check(melee_p._carried_weapon.is_melee_weapon() and target.hits == 1, "carried melee attacks")
	check(melee_p._carried_weapon._mounted_melee_time > 0.0, "melee swing active")
	var base := weapon(tree())
	for reversed in [false, true]:
		var rock_tree := tree()
		apply(rock_tree, "fate_armor_pierce", null, reversed)
		var rock_gun := weapon(rock_tree)
		check(is_equal_approx(rock_gun.bullet_speed, base.bullet_speed * 0.5), "rock speed half")
		check(is_equal_approx(rock_gun.fire_rate, base.fire_rate * 0.5), "rock rate half")
		var p := fire(rock_gun)
		check(p._visual.get_meta("asset_id") == "VFX-FATE-ROCK-3D", "rock prefab routed")
		check(bool(p.fate_behavior.get("rock_shatter", false)) == reversed, "rock orientation semantics")
		if reversed:
			target.global_position = p.global_position + Vector3(1, 0, 0)
			var far := Target.new()
			add_child(far)
			far.add_to_group("enemies")
			far.global_position = p.global_position + Vector3(3.1, 0, 0)
			p._shatter_rock()
			p._shatter_rock()
			check(target.pushes == 1 and far.pushes == 0, "shatter once, bounded radius")
			check(target.push_direction.x > 5.9, "radial knockback outward")
		else:
			var floor := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(30, 0.2, 30)
			shape.shape = box
			floor.add_child(shape)
			add_child(floor)
			floor.position = Vector3(0, -12.1, 0)
			p.global_position = Vector3(0, -11.4, 2)
			await get_tree().physics_frame
			for step in range(40): p._physics_process(0.016)
			check(p._active and p.global_position.y > -12.01 and p.global_position.y < -11.7, "rock rolls on nonzero floor")
			check(p.global_position.z < 0.0, "rolling travels forward")
			check(absf(p._visual.get_node("Rock").rotation.x) > 0.01, "stone visibly rotates")
			p.activate({"behavior": {}}, Vector3.ZERO)
			p.set_physics_process(false)
			check(p._visual.get_meta("asset_id") != "VFX-FATE-ROCK-3D", "pool reuse clears stone visual")
	var deep := tree()
	var parent := deep.root
	for index in range(5):
		var child := AssemblyNode.new(AssemblyNode.NodeType.GUN_BODY, "GunBody_Pistol")
		check(parent.mount(AssemblyNode.SlotType.MOUNT, child), "deep fixture mount")
		parent = child
	var destination := tree()
	var before := WeaponInstance._serialize_node(destination.root)
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for c in FateCardPresets.playable_presets():
		if c.get_stable_card_id() != "fate_bullet_carry_gun": continue
		var selected: Array[AssemblyNode] = [destination.root.slots[AssemblyNode.SlotType.BULLET], deep.root]
		var rejected := FateCardEngine.apply_card(c, destination, selected)
		check(not rejected.success, "over-depth source rejected")
	check(WeaponInstance._serialize_node(destination.root) == before, "failed mount leaves destination intact")
	check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes_before, "failed mount releases whole copied subtree")
	check(samples >= 40, "sample sentinel")
	for item in owned_trees: item.free()
	print("STAR_PHYSICAL_OK samples=", samples) if failures.is_empty() else print("STAR_PHYSICAL_FAILED ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
