extends Node3D

const SUPPORT = preload("res://src/world3d/FurnishingSupport3D.gd")
const FIXTURE := "res://tests/fixtures/lamp_furniture_room.tscn"
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []
var checks := 0
var out := ""

class Actor extends CharacterBody3D:
	var current_hp := 10000
	var hits := 0
	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO) -> void:
		current_hp -= amount
		hits += 1

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("LAMP_CHECK " + message)

func settle(frames := 3) -> void:
	for step in frames:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	out = OS.get_environment("LAMP_QA_DIR").replace("\\", "/")
	print("USER_DATA ", OS.get_user_data_dir())
	if out.is_empty() or not OS.get_user_data_dir().begins_with(out + "/userdata/"):
		push_error("LAMP_CHECK isolate APPDATA before Autoload")
		get_tree().quit(1)
		return
	await _chain()
	await _direct_and_fire()
	await _formal_layouts()
	if DisplayServer.get_name() != "headless":
		var gallery: DungeonRoom3D = await _room()
		var gallery_lamp := gallery.find_child("Lamp", true, false) as ReactiveLamp3D
		await _capture(gallery, gallery_lamp, "furniture_intact")
		var gallery_table := gallery.find_child("Table", true, false) as ReactiveProp3D
		for hit in 3:gallery_table.take_damage(1)
		await settle(50)
		await _capture(gallery, gallery_lamp, "furniture_lamp_fire")
		gallery.queue_free()
		await settle()
	var file := FileAccess.open(out + "/lamp_" + DisplayServer.get_name() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	file.close()
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		pool.clear_all()
	await settle()
	if failures.is_empty():
		print("LAMP_FURNITURE_CHAIN_OK checks=%d" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _room() -> DungeonRoom3D:
	var room := DungeonRoom3D.new()
	room.position.y = -72.0
	room.configure({"room_id":"lamp_fixture", "room_type":"COMBAT", "custom_dimensions":Vector2(20,20),
		"static_layout_scene_path":FIXTURE, "procedural_shell":true})
	add_child(room)
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await settle()
	return room

func shoot(prop: ReactiveProp3D, height: float) -> void:
	var hits_before := prop.hit_count
	var state_before := prop.state
	var bullet := Projectile3D.new()
	add_child(bullet)
	var point := prop.global_position + Vector3(0, height, 2.0)
	bullet.activate({"direction": Vector3.FORWARD,"speed":20.0,"damage":1,"hostile":false},point)
	for step in 30:
		await settle(1)
		if prop.hit_count > hits_before or prop.state != state_before:
			break
	if is_instance_valid(bullet):bullet.queue_free()

func _chain() -> void:
	var room: DungeonRoom3D = await _room()
	var table := room.find_child("Table", true, false) as ReactiveProp3D
	var lamp := room.find_child("Lamp", true, false) as ReactiveLamp3D
	var flower := room.find_child("Flower", true, false) as ReactiveProp3D
	var documents := room.find_child("Documents", true, false) as ReactiveProp3D
	var other := room.find_child("OtherLamp", true, false) as ReactiveLamp3D
	var ground := room.find_child("GroundFlower", true, false) as ReactiveProp3D
	check(table.supported_items.size() == 4, "support captures four real tabletop props")
	check(lamp.supporting_furniture == table and other.supporting_furniture != table, "other table not linked")
	check(ground.supporting_furniture == null, "ground prop excluded from support")
	await shoot(table, 0.5)
	check(lamp.state == "shaking" and lamp.current_hp == lamp.max_hp and lamp._fire == null, "one furniture hit shakes lamp without damage or explosion")
	await settle(2)
	check(lamp._pivot.rotation.length() > 0.0001, "supported lamp visibly oscillates")
	await get_tree().create_timer(1.4).timeout
	await shoot(table, 0.5)
	check(table._combo == 1, "slow hits restart furniture combo")
	await shoot(table, 0.5)
	check(lamp.state in ["intact", "shaking"] and lamp._fire == null, "two consecutive hits keep contents")
	await shoot(table, 0.5)
	check(lamp.state == "dropping", "third real bullet releases lamp")
	check(table.contents_released and flower.state == "dropping", "all tabletop props fall together")
	check(other.state == "intact" and ground.state == "intact", "unrelated props stay intact")
	await settle(1)
	room.capture_reactive_prop_states()
	var records := room.get_persistent_detail_state("reactive_props")
	var key := str(lamp.get_meta("reactive_prop_id"))
	check(float(records[key].get("drop_elapsed", 0)) > 0, "save captures current flight progress")
	await settle(50)
	check(lamp.state == "burning", "dropped lamp explodes on landing")
	check(flower.state == "broken" and documents.state == "dropped", "plant breaks and documents settle")
	print("LAMP_FLOOR room=",room.global_position," lamp=",lamp.global_position," target=",lamp._drop_target," fire=",lamp._fire.global_position if lamp._fire != null else Vector3.ZERO)
	var ray := PhysicsRayQueryParameters3D.create(lamp.global_position + Vector3.UP * 0.3, lamp.global_position - Vector3.UP * 2.0, 1)
	ray.exclude = [table._body.get_rid(), lamp._body.get_rid()]
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
	check(lamp._fire != null and not floor_hit.is_empty() and absf(lamp._fire.global_position.y - (floor_hit.position as Vector3).y) < 0.03 and lamp._fire.global_position.y < -60, "fire matches actual nonzero floor collider")
	var remaining := lamp.fire_expires_at
	for hit in 5:table.take_damage(1)
	check(lamp.fire_expires_at == remaining, "repeat furniture hits cannot restart flame")
	var light := room.find_child("LampLight", true, false) as OmniLight3D
	room.set_room_light_on(true)
	check(not light.visible and light.light_energy == 0, "destroyed lamp light cannot switch on")
	room.capture_reactive_prop_states()
	var data := room.get_persistent_detail_state("reactive_props")
	room.queue_free()
	await settle()
	var copy: DungeonRoom3D = await _room()
	copy.apply_runtime_detail_state({"reactive_props": JSON.parse_string(JSON.stringify(data))})
	var restored := copy.find_child("Lamp", true, false) as ReactiveLamp3D
	check(restored.fire_expires_at == remaining, "restore preserves original fire deadline")
	check(restored.state == "burning" and restored._fire != null, "active fire restores remaining time")
	var restored_doc := copy.find_child("Documents", true, false) as ReactiveProp3D
	check(restored_doc.state == "dropped", "fallen tabletop prop does not reappear on table")
	copy.queue_free()
	await settle()

func actor(point: Vector3, layer: int) -> Actor:
	var body := Actor.new()
	body.collision_layer = layer
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.14
	capsule.height = 1.0
	collision.shape = capsule
	collision.position.y = 0.5
	body.add_child(collision)
	add_child(body)
	body.global_position = point
	return body

func _direct_and_fire() -> void:
	var room: DungeonRoom3D = await _room()
	var lamp := room.find_child("Lamp", true, false) as ReactiveLamp3D
	lamp.take_damage(0)
	check(lamp.state == "intact", "non-positive damage rejected")
	await shoot(lamp, 0.35)
	check(lamp.state == "burning" and not lamp._visual.visible, "direct real bullet explodes lamp immediately")
	check(not (room.find_child("Table", true, false) as ReactiveProp3D).contents_released, "direct lamp hit leaves support contents")
	var patch := lamp._fire
	if patch == null:
		check(false, "direct explosion creates damage patch")
		room.queue_free()
		return
	var point := patch.global_position
	var friendly := actor(point + Vector3(0.6, 0.02, 0.6), 1)
	var hostile := actor(point + Vector3(-0.6, 0.02, 0.6), 4)
	var outside := actor(point + Vector3(2.3, 0.02, 0), 4)
	var enemy := ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.current_hp = 1
	enemy.global_position = point + Vector3(0.2,0.02,0.8)
	var death := {}
	enemy.killed.connect(func(killed: Enemy3D, _loot: Dictionary):death["dead"] = killed.ai_state == "dead")
	await settle(12)
	check(friendly.hits >= 1 and hostile.hits >= 1, "flame damages both actor layers")
	check(outside.hits == 0, "outside burn radius is safe")
	check(bool(death.get("dead",false)), "flame uses real enemy death chain")
	check(patch.get_children().filter(func(node):return node is CollisionShape3D).size() == 1, "damage collision remains outside visual prefab")
	var flames := patch._effects.duplicate()
	check(flames.size() == 5, "visible flames cover the ground area")
	var lit := 0
	for value in flames:
		var flame := value as VfxEffectBase3D
		if (flame.get_node("FireLight") as OmniLight3D).light_energy > 0.0:lit += 1
		check(flame.get_node("Embers").visible, "ground flames emit rising embers")
	check(lit == 1, "one warm light per fire patch")
	var ember := (flames[0] as Node3D).get_node("Embers/E0") as Node3D
	var ember_start := ember.position
	var prior_hits := friendly.hits
	var tick_start := Time.get_unix_time_from_system()
	await get_tree().create_timer(0.7).timeout
	var tick_elapsed := Time.get_unix_time_from_system() - tick_start
	check(ember.position.distance_to(ember_start) > 0.02, "embers move while burning")
	check(friendly.hits > prior_hits and friendly.hits - prior_hits <= ceili(tick_elapsed / 0.5) + 1, "burn tick rate is bounded")
	# This is an absolute deadline, independent of hibernating rooms or loading saves.
	room.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(5.0).timeout
	check(lamp.state == "spent" and not is_instance_valid(patch), "fire disappears after five seconds even in inactive room")
	var count := friendly.hits
	await get_tree().create_timer(0.6).timeout
	check(friendly.hits == count, "no lingering damage after expiry")
	for value in flames:
		var effect := value as VfxEffectBase3D
		check(not is_instance_valid(effect) or not effect._active, "flame visual returned to pool")
		if is_instance_valid(effect):
			check((effect.get_node("FireLight") as OmniLight3D).light_energy == 0.0, "returned flame light is extinguished")
	room.process_mode = Node.PROCESS_MODE_INHERIT
	if DisplayServer.get_name() != "headless":await _capture(room, lamp, "lamp_fire_expired")
	var data := lamp.export_prop_state()
	var scene := load("res://assets/art/environments/tower_zones/expedition/runtime/common_components/manor_table_lamp/env_manor_table_lamp_root_top3d.tscn") as PackedScene
	var restored := scene.instantiate() as ReactiveLamp3D
	add_child(restored)
	restored.restore_prop_state(data)
	check(restored.state == "spent" and restored._fire == null, "expired saved flame cannot reignite")
	restored.queue_free()
	friendly.queue_free()
	hostile.queue_free()
	outside.queue_free()
	if is_instance_valid(enemy):enemy.queue_free()
	room.queue_free()
	await settle()

func _formal_layouts() -> void:
	var directory := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms/"
	var lamps := 0
	var types := {}
	for file in DirAccess.get_files_at(directory):
		if not file.ends_with(".tscn"):continue
		var layout := (load(directory + file) as PackedScene).instantiate() as Node3D
		add_child(layout)
		SUPPORT.bind_layout(layout)
		for node in layout.find_children("*", "", true, false):
			if not node is ReactiveLamp3D:continue
			var lamp := node as ReactiveLamp3D
			lamps += 1
			check(lamp.supporting_furniture != null, "formal lamp has real support " + file + "/" + str(lamp.name))
			if lamp.supporting_furniture != null:
				types[str(lamp.supporting_furniture.get_meta("asset_id"))] = true
				lamp.supporting_furniture.take_damage(1)
				lamp.supporting_furniture.take_damage(1)
				lamp.supporting_furniture.take_damage(1)
				check(lamp.state == "dropping", "formal furniture drops actual lamp")
		layout.queue_free()
		await settle()
	# Source inventory 2026-11-06: 178 before this repair; B rooms change 6/10 to
	# 32/32 authored lamps, giving 226. Every one must retain support and drop behavior.
	check(lamps == 226 and types.size() == 4, "all 226 current table lamps and four real support types")
	print("LAMP_FORMAL_INSTANCES ",lamps," supports=",types.size())

func _capture(room: DungeonRoom3D, lamp: ReactiveLamp3D, name: String) -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("252e38")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 48.0
	camera.global_position = lamp.global_position + Vector3(3.8,5.2,6.0)
	camera.look_at(lamp.global_position - Vector3(0,0.4,0))
	camera.make_current()
	await settle(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	camera.queue_free()
	world.queue_free()
	await settle()
