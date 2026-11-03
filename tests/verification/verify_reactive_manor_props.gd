extends Node3D
## Run with isolated APPDATA before Autoload. Real colliders, bullets, actors and rooms.

const ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/common_components/"
const FIXTURE := "res://tests/fixtures/reactive_manor_room.tscn"
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []
var checks := 0

class Victim extends CharacterBody3D:
	var current_hp := 500
	var damage_events := 0
	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO) -> void:
		current_hp -= amount
		damage_events += 1


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("REACTIVE_CHECK " + message)


func settle(frames := 3) -> void:
	for index in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func prefab(slug: String) -> ReactiveProp3D:
	return (load(ROOT + slug + "/env_" + slug + "_root_top3d.tscn") as PackedScene).instantiate() as ReactiveProp3D


func room() -> DungeonRoom3D:
	var result := DungeonRoom3D.new()
	result.configure({"room_id": "reactive_fixture", "room_type": "COMBAT", "size_class": "large",
		"custom_dimensions": Vector2(25, 25), "static_layout_scene_path": FIXTURE, "procedural_shell": true})
	add_child(result)
	result.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await settle()
	return result


func shoot(prop: ReactiveProp3D, amount: int, piercing := false) -> float:
	var bullet := Projectile3D.new()
	add_child(bullet)
	var origin := prop.global_position + Vector3(0, 0.7, 2.0)
	bullet.activate({"direction": Vector3.FORWARD, "speed": 20.0, "damage": amount, "hostile": false, "fate_behavior": {"pierce_level": 2 if piercing else 0}}, origin)
	var peak := 0.0
	for index in 16:
		await settle(1)
		peak = maxf(peak, prop._pivot.rotation.length())
	if is_instance_valid(bullet):
		bullet.queue_free()
	return peak


func victim(point: Vector3) -> Victim:
	var result := Victim.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.0
	collision.shape = capsule
	collision.position.y = 0.5
	result.add_child(collision)
	result.collision_layer = 4
	result.collision_mask = 1
	add_child(result)
	result.global_position = point
	return result


func _ready() -> void:
	print("USER_DATA ", OS.get_user_data_dir())
	var safety := OS.get_environment("REACTIVE_PROP_QA_DIR")
	if safety.is_empty() or not OS.get_user_data_dir().begins_with(safety.replace("\\", "/") + "/userdata/"):
		push_error("REACTIVE isolation must precede Autoload")
		get_tree().quit(1)
		return
	if OS.get_cmdline_user_args().has("--lighting-only"):
		await _default_light_persistence()
		print("REACTIVE_DEFAULT_LIGHTS_OK" if failures.is_empty() else "REACTIVE_DEFAULT_LIGHTS_FAILED", " checks=", checks)
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	if OS.get_cmdline_user_args().has("--checkpoint-only"):
		await _exit_checkpoint()
		print("REACTIVE_CHECKPOINT_OK" if failures.is_empty() else "REACTIVE_CHECKPOINT_FAILED", " checks=", checks)
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	if OS.get_cmdline_user_args().has("--gallery-only"):
		await _render()
		get_tree().quit()
		return
	await _plants()
	await _shelves()
	await _blocked_ejection()
	await _persistence()
	await _exit_checkpoint()
	await _default_light_persistence()
	await _formal_layouts()
	if DisplayServer.get_name() != "headless":
		await _render()
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		pool.clear_all()
	await settle()
	var file := FileAccess.open(safety + "/reactive_" + DisplayServer.get_name() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	file.close()
	if failures.is_empty():
		print("REACTIVE_MANOR_PROPS_OK checks=%d" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)


func _plants() -> void:
	for slug in ["manor_plant_large", "manor_plant_compact", "manor_flower_arrangement"]:
		var prop := prefab(slug)
		add_child(prop)
		var walker := victim(Vector3(0, 0, 1.0))
		await settle()
		walker.move_and_collide(Vector3(0, 0, -2))
		await settle()
		check(prop.current_hp == prop.max_hp and prop.state == "intact", slug + " walking does not break or damage")
		walker.queue_free()
		await settle()
		var reaction: float = await shoot(prop, 1)
		check(prop.current_hp == prop.max_hp - 1, slug + " real bullet damage")
		check(reaction > 0.0001, slug + " elastic hit reaction")
		prop.take_damage(0)
		check(prop.hit_count == 1, slug + " zero damage rejected")
		await shoot(prop, 1, true)
		check(prop.hit_count == 2 and prop.current_hp == prop.max_hp - 2, slug + " piercing round damages this prop once")
		await settle(90)
		check(prop._pivot.rotation.length() < 0.001, slug + " spring settles")
		prop.take_damage(999)
		await settle(55)
		check(prop.state == "broken" and not prop._visual.visible, slug + " sufficient damage breaks")
		check(prop._body.collision_layer == 0 and prop._receiver.collision_layer == 0, slug + " broken has no blocker/receiver")
		check(prop._debris.size() == 5, slug + " ceramic debris")
		var copy := prefab(slug)
		add_child(copy)
		copy.restore_prop_state(prop.export_prop_state())
		await settle()
		check(copy.state == "broken" and copy._debris.size() == 5, slug + " restore settled broken state")
		copy.queue_free()
		prop.queue_free()
		await settle()


func _shelves() -> void:
	var prop := prefab("manor_bookcase")
	prop.scale = Vector3(1.5, 1.2507, 1)
	prop.rotation.y = 0.6
	add_child(prop)
	prop.take_damage(1, false, -prop.global_basis.z)
	prop.take_damage(1, false, -prop.global_basis.z)
	check(prop.books_dropped == 2 and prop.current_hp == 298, "repeated hits drop books")
	await settle(90)
	check(prop.state == "intact", "nonlethal spring returns upright")
	# Fresh interval breaks the consecutive-hit counter, not accumulated damage.
	prop.take_damage(1, false, -prop.global_basis.z)
	check(prop._combo == 1 and prop.current_hp == 297, "combo expires without healing")
	prop.take_damage(999, false, -prop.global_basis.z)
	var landing := prop.get_landing_box()
	var frame: Transform3D = landing.frame
	var bounds: AABB = landing.bounds
	var midpoint := bounds.get_center()
	midpoint.y = bounds.position.y + 0.02
	var survivor := victim(frame * midpoint)
	var outside := victim(frame * (midpoint + Vector3(bounds.size.x + 0.5, 0, 0)))
	var enemy := ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.current_hp = 1
	enemy.global_position = frame * (midpoint + Vector3(0.5, 0, 0))
	var dead_origin := enemy.global_position
	var death := {}
	enemy.killed.connect(func(killed: Enemy3D, _loot: Dictionary):
		death["hp"] = killed.current_hp
		death["state"] = killed.ai_state
		death["position"] = killed.global_position
	)
	await settle(65)
	check(prop.state == "fallen", "scaled rotated shelf lands")
	check(survivor.damage_events == 1 and survivor.current_hp == 450, "single impact damage")
	check(outside.damage_events == 0, "outside footprint unhurt")
	var local := frame.affine_inverse() * survivor.global_position
	check(local.x < bounds.position.x or local.x > bounds.end.x or local.z < bounds.position.z or local.z > bounds.end.z, "survivor ejected outside footprint")
	check(death.get("hp", 1) == 0 and death.get("state", "") == "dead", "lethal impact uses real Enemy3D death")
	check(death.has("position") and (death.position as Vector3).distance_to(dead_origin) < 0.1, "dead actor skips survivor ejection")
	var final_box := prop._pivot.global_transform * prop._box
	check(absf(final_box.position.y - (prop._base * prop._box.position).y) < 0.02, "fallen underside rests on floor")
	prop.take_damage(999)
	await settle(30)
	check(survivor.damage_events == 1, "fallen shelf cannot retrigger damage")
	var snapshot := prop.export_prop_state()
	var copy := prefab("manor_bookcase")
	copy.transform = prop.transform
	add_child(copy)
	copy.restore_prop_state(snapshot)
	await settle()
	check(copy.state == "fallen" and survivor.damage_events == 1, "restore never reapplies impact")
	copy.queue_free()
	prop.queue_free()
	survivor.queue_free()
	outside.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	await settle()
	var combo := prefab("manor_bookcase")
	add_child(combo)
	for index in 10:
		combo.take_damage(1)
	check(combo.state == "falling" and combo.current_hp == 290, "sustained weak fire topples before hp exhausted")
	combo.queue_free()
	await settle()


func _persistence() -> void:
	var source: DungeonRoom3D = await room()
	var props: Array[ReactiveProp3D] = []
	for value in source.find_children("*", "", true, false):
		if value is ReactiveProp3D:
			props.append(value)
	check(props.size() == 4, "room adopts all four prefabs")
	for prop in props:
		prop.take_damage(7)
	var data := source.get_persistent_detail_state("reactive_props")
	check(data.size() == 4, "each instance persisted independently")
	# Capture through the production map owner, including while detail is unloaded.
	var dungeon := (load("res://scenes/Dungeon3D.tscn") as PackedScene).instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	dungeon.set_process(false)
	dungeon.set_physics_process(false)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	dungeon._room_by_id[source.room_id] = source
	dungeon._capture_room_runtime_state(source.room_id)
	check(dungeon._segment_runtime_state[source.room_id].get("reactive_props", {}) == data, "production dungeon snapshot includes props")
	source.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	await settle()
	source.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await settle()
	check(source.get_persistent_detail_state("reactive_props") == data, "streaming retains room ledger")
	dungeon._capture_room_runtime_state(source.room_id)
	check(dungeon._segment_runtime_state[source.room_id].get("reactive_props", {}) == data, "unloaded detail snapshot keeps prop ledger")
	dungeon.queue_free()
	source.queue_free()
	await settle()
	var copy: DungeonRoom3D = await room()
	copy.apply_runtime_detail_state({"reactive_props": JSON.parse_string(JSON.stringify(data))})
	for value in copy.find_children("*", "", true, false):
		if value is ReactiveProp3D:
			var prop := value as ReactiveProp3D
			check(prop.current_hp == prop.max_hp - 7, "serialized state restores hp " + str(prop.name))
	copy.queue_free()
	await settle()


## A partial furnishing/container ledger must never supply an implicit light command.
func _default_light_persistence() -> void:
	var dungeon := (load("res://scenes/Dungeon3D.tscn") as PackedScene).instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	var cases: Array[Dictionary] = [
		{"type": "FACILITY", "authored_on": false, "expected_on": true},
		{"type": "STAIR_LOBBY", "authored_on": false, "expected_on": true},
		{"type": "BOSS", "authored_on": false, "expected_on": true},
		{"type": "COMBAT", "authored_on": true, "expected_on": true},
		{"type": "COMBAT", "authored_on": false, "expected_on": false},
	]
	for index in cases.size():
		var sample := cases[index]
		var source := DungeonRoom3D.new()
		var id := "default_light_%d" % index
		source.configure({"room_id": id, "room_type": sample.type,
			"size_class": "large", "custom_dimensions": Vector2(25, 25),
			"procedural_shell": true, "authored_room_light_on": sample.authored_on})
		add_child(source)
		check(source.get_persistent_detail_state("reactive_props").is_empty(), "no furnishing state before detail " + id)
		source.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		await settle()
		var expected_on: bool = sample.expected_on
		check(source.is_room_light_on() == expected_on, "room kind/authored default survives initial capture " + id)
		source.apply_runtime_detail_state({"reactive_props": {}})
		check(source.is_room_light_on() == expected_on, "empty furnishing ledger preserves default " + id)
		dungeon._room_by_id[id] = source
		dungeon._segment_runtime_state[id] = {"containers": {}}
		dungeon._restore_room_runtime_state(id)
		check(source.is_room_light_on() == expected_on, "legacy snapshot without light key preserves default " + id)
		source.set_room_light_on(not expected_on)
		source.apply_runtime_detail_state({"containers": {}})
		check(source.is_room_light_on() == not expected_on, "unrelated partial restore preserves live switch " + id)
		source.apply_runtime_detail_state({"room_light_on": false})
		check(not source.is_room_light_on(), "explicit saved blackout remains off " + id)
		source.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
		source.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		await settle()
		check(not source.is_room_light_on(), "saved blackout survives detail rebuild " + id)
		source.apply_runtime_detail_state({"room_light_on": true})
		check(source.is_room_light_on(), "explicit saved on state is restored " + id)
		check(dungeon.apply_narrative_light_state(id, false), "narrative light command accepted " + id)
		source.apply_runtime_detail_state({"reactive_props": {}})
		check(not source.is_room_light_on(), "narrative blackout survives furnishing restore " + id)
		dungeon._restore_room_runtime_state(id)
		check(not source.is_room_light_on(), "narrative blackout survives room snapshot restore " + id)
		source.queue_free()
		await settle()
	dungeon.queue_free()
	await settle()


## Exercise real scene removal with persistence enabled, before the debounce fires.
func _exit_checkpoint() -> void:
	var original_path := BaseManager.save_path
	var original_data := BaseManager.data
	BaseManager.save_path = "user://reactive_exit_checkpoint.json"
	BaseManager.data = BaseData.new()
	var dungeon := (load("res://scenes/Dungeon3D.tscn") as PackedScene).instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	dungeon.test_mode = false
	dungeon._activate_runtime_persistence()
	# Add a persistent subtree after activation: runtime additions also exit after the save.
	var source: DungeonRoom3D = await room()
	source.reparent(dungeon)
	dungeon._rooms.append(source)
	dungeon._room_by_id[source.room_id] = source
	dungeon._spawned_rooms[source.room_id] = true
	var prop := source.find_child("LargePlant", true, false) as ReactiveProp3D
	check(prop != null, "exit fixture has a reactive furnishing")
	var expected_checkpoint: Dictionary = {}
	if prop != null:
		prop.take_damage(7)
		check(BaseManager.flush_runtime_checkpoint("exit_probe_initial"), "initial checkpoint commits")
		var revision := BaseManager.data.save_revision
		# A moving prop's pose changes without another state_changed signal.
		prop.position.x += 0.375
		var expected := prop.export_prop_state()
		var key := str(prop.get_meta("reactive_prop_id"))
		remove_child(dungeon)
		var stored := BaseManager.get_active_run_checkpoint()
		expected_checkpoint = stored.duplicate(true)
		var world: Dictionary = stored.get("world_state", {})
		var rooms: Dictionary = world.get("segment_runtime_state", {})
		var detail: Dictionary = (rooms.get(source.room_id, {}) as Dictionary).get("reactive_props", {})
		check(detail.get(key, {}) == expected, "scene unload commits final live furnishing pose")
		check(BaseManager.data.save_revision == revision + 1, "scene unload writes exactly once")
		var ledger := source.get_persistent_detail_state("reactive_props")
		source.capture_reactive_prop_states()
		check(source.get_persistent_detail_state("reactive_props") == ledger, "detached capture preserves cached ledger")
		dungeon._capture_room_runtime_state(source.room_id)
		check(dungeon._segment_runtime_state[source.room_id].get("reactive_props", {}) == ledger, "detached room preserves last runtime snapshot")
	else:
		remove_child(dungeon)
	dungeon.free()
	BaseManager.load_base()
	check(not expected_checkpoint.is_empty() and BaseManager.get_active_run_checkpoint() == JSON.parse_string(JSON.stringify(expected_checkpoint)), "unload checkpoint reloads from disk")
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	await settle()


func _blocked_ejection() -> void:
	var prop := prefab("manor_bookcase")
	add_child(prop)
	prop.take_damage(999, false, Vector3.FORWARD)
	var landing := prop.get_landing_box()
	var bounds: AABB = landing.bounds
	var frame: Transform3D = landing.frame
	var center := bounds.get_center()
	center.y = bounds.position.y + 0.02
	var player := (load("res://scenes/Player3D.tscn") as PackedScene).instantiate() as Player3D
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.max_hp = 500
	player.current_hp = 500
	player.is_invincible = false
	player.global_position = frame * Vector3(bounds.position.x + 0.28, center.y, center.z)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.25, 3, 6)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.position = Vector3(bounds.position.x - 0.24, 1.5, center.z)
	await settle(58)
	check(player.current_hp == 450, "real Player3D receives collapse damage")
	check(player.global_position.x > wall.position.x + 0.125, "ejection cannot cross adjacent wall")
	var local := frame.affine_inverse() * player.global_position
	check(local.x > bounds.end.x or local.z < bounds.position.z or local.z > bounds.end.z, "blocked nearest edge chooses another edge")
	check((prop._body.get_node("Shape").shape as BoxShape3D).size.is_equal_approx(bounds.size), "wreckage collider matches final bounds")
	player.queue_free()
	wall.queue_free()
	prop.queue_free()
	await settle()


func _formal_layouts() -> void:
	var directory := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms/"
	var count := 0
	for filename in DirAccess.get_files_at(directory):
		if not filename.ends_with(".tscn"):
			continue
		var layout := (load(directory + filename) as PackedScene).instantiate() as Node3D
		add_child(layout)
		for value in layout.find_children("*", "", true, false):
			if not value is ReactiveProp3D:
				continue
			var prop := value as ReactiveProp3D
			if prop.prop_kind not in ["bookcase", "planter"]:
				continue
			count += 1
			check(prop._box.size.y > 1.0, "formal visual bounds " + filename + "/" + str(prop.name))
			var old := prop.get_node_or_null("LayoutCollision") as StaticBody3D
			if old != null:
				check(old.collision_layer == 0, "authored blocker retired " + str(prop.name))
			prop.take_damage(9999)
			if prop.prop_kind == "planter":
				check(prop.state == "broken", "formal planter reacts")
			else:
				check(prop.state == "falling", "formal shelf reacts")
		layout.queue_free()
		await settle()
	check(count > 100, "formal layouts contain target furnishings")
	print("REACTIVE_FORMAL_INSTANCES ", count)


func _render() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("252e38")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-50, 25, 0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 40.0
	camera.position = Vector3(5, 6, 10)
	camera.look_at(Vector3(0, 0.7, 0))
	camera.make_current()
	var props: Array[ReactiveProp3D] = []
	for index in 4:
		var prop := prefab(["manor_bookcase", "manor_plant_large", "manor_plant_compact", "manor_flower_arrangement"][index])
		prop.position.x = index * 2.2 - 3.3
		add_child(prop)
		props.append(prop)
	await settle(8)
	await _capture("intact")
	for prop in props:
		prop.take_damage(1)
		prop.take_damage(1)
	await settle(8)
	await _capture("hit_books")
	for prop in props:
		prop.take_damage(9999)
	await settle(28)
	await _capture("falling")
	await settle(45)
	await _capture("fallen_broken")
	for prop in props:
		prop.queue_free()
	camera.queue_free()
	world.queue_free()
	light.queue_free()
	await settle()


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OS.get_environment("REACTIVE_PROP_QA_DIR") + "/" + label + ".png")
	print("REACTIVE_RENDER ", label)
