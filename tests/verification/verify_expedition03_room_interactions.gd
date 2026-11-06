extends Node3D

const LEVEL := preload("res://scenes/ExpeditionLevel03_3D.tscn")
const DIR := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms/"
var _checks := 0
var _failures := 0
var _contracts := {}
var _shot_dir := ""


func _ready() -> void:
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	_shot_dir = OS.get_environment("SS_EXP03_INTERACTION_SHOTS")
	if not _shot_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	_check_saved_shells()
	var tower := LEVEL.instantiate() as TowerDescent3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", 77003244)
	add_child(tower)
	await _settle(20)
	tower.set_process(false)
	var rooms := tower.get("_room_by_id") as Dictionary
	for room_id in ["n03", "n06", "reward_01", "shop"]:
		var room := rooms[room_id] as DungeonRoom3D
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
	await _settle(4)
	for room_id in ["n03", "n06", "reward_01", "shop"]:
		var room := rooms[room_id] as DungeonRoom3D
		var art := room.get_node("AuthoredLayoutArtRoot") as Node3D
		_check_inherited_interactions(art)
		if room_id in ["n03", "n06"]:
			await _check_passage_interaction(tower, room, art)
		else:
			var shelf := _first_prop(art, "bookcase")
			_check(shelf != null, room_id + " has reactive shelf")
			if shelf != null:
				shelf._receiver.call("take_damage", 1, false, Vector3.RIGHT)
				await _settle(3)
				_check(shelf.hit_count == 1 and shelf.current_hp == shelf.max_hp - 1 and shelf._pivot.rotation.length() > .0001, room_id + " shelf hit feedback")
	if not _shot_dir.is_empty():
		await _capture_editor_source()
	tower.queue_free()
	await _settle(3)
	print("EXP03_ROOM_INTERACTIONS %s checks=%d failures=%d" % ["OK" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _check_saved_shells() -> void:
	for file in ["combat_40x30_18c0881f3934_e86e98", "combat_30x40_5fbbae7662fe_e86e98", "storage_15x15_94b04661833c_3e5f15", "merchant_20x15_327ac0ee6b3c_d77c54"]:
		var source := (load(DIR + file + ".tscn") as PackedScene).instantiate() as Node3D
		var preview := source.get_node_or_null("ArtComponents/EditorShellPreview")
		var expected := 21 if str(file).begins_with("storage") else 26 if str(file).begins_with("merchant") else 76
		_check(preview != null and preview.get_child_count() == expected, str(file) + " saved editor floor/walls complete")
		_check(not FileAccess.get_file_as_string(DIR + file + ".tscn").contains("script = null"), str(file) + " never removes component scripts")
		source.free()


func _check_inherited_interactions(art: Node3D) -> void:
	var count := 0
	for node in art.find_children("*", "Node3D", true, false):
		var path := str(node.scene_file_path)
		if not path.contains("/common_components/manor_") or not path.ends_with("_root_top3d.tscn"):
			continue
		if not _contracts.has(path):
			var original := (load(path) as PackedScene).instantiate()
			_contracts[path] = original is ReactiveProp3D
			original.free()
		if not bool(_contracts[path]):
			continue
		count += 1
		if not _check(node is ReactiveProp3D, "component interaction inherited " + str(node.name)):
			continue
		var prop := node as ReactiveProp3D
		_check(prop._receiver != null and prop._receiver.has_method("take_damage") and (prop._receiver.collision_layer & 4) != 0, "hit receiver active " + str(prop.name))
		var active := 0
		for body in prop.find_children("*", "StaticBody3D", true, false):
			if body.collision_layer & 5 != 0:
				active += 1
		_check(active == 1, "one collision owner " + str(prop.name))
	_check(count > 5, "room retains interactive furnishing family")
	print("EXP03_REACTIVE_ROOM ", art.get_parent().name, " components=", count)


func _check_passage_interaction(tower: TowerDescent3D, room: DungeonRoom3D, art: Node3D) -> void:
	var shelf := art.get_node("ArtComponents/ReadingAlcoves/LibrarySpine_1_2") as ReactiveProp3D
	if not _check(shelf != null, room.room_id + " library shelf keeps original script"):
		return
	if not _shot_dir.is_empty():
		await _capture_room(tower, room, "before")
	var peak := await _shoot(shelf)
	_check(shelf.hit_count == 1 and shelf.current_hp == 299 and peak > .0001, room.room_id + " real bullet shakes shelf")
	await _shoot(shelf)
	_check(shelf.hit_count == 2 and shelf.books_dropped == 2, room.room_id + " repeated real bullets release books")
	var previous: Array = room.get_meta("furnishing_navigation_polygons").duplicate(true)
	var refresh := int(room.get_meta("furnishing_navigation_refresh_count", 0))
	var upright: AABB = shelf._body.global_transform * shelf._body.get_node("Shape").shape.get_debug_mesh().get_aabb()
	shelf._receiver.call("take_damage", 9999, false, shelf.global_basis.z.normalized())
	await _settle(65)
	_check(shelf.state == "fallen" and shelf.books_dropped == 8, room.room_id + " shelf collapses with original behavior")
	var landed: AABB = shelf._body.global_transform * shelf._body.get_node("Shape").shape.get_debug_mesh().get_aabb()
	_check(shelf._body.collision_layer == 1 and landed.size.y < upright.size.y * .7, room.room_id + " collider follows fallen wreckage")
	_check(int(room.get_meta("furnishing_navigation_refresh_count", 0)) > refresh and room.get_meta("furnishing_navigation_polygons") != previous, room.room_id + " navigation follows changed furniture")
	_check(room.find_children("RuntimeNavigationRegion3D", "NavigationRegion3D", true, false).size() == 1, room.room_id + " navigation region updated without duplication")
	room.capture_reactive_prop_states()
	var states := room.get_persistent_detail_state("reactive_props")
	var key := str(shelf.get_meta("reactive_prop_id"))
	_check(states.has(key) and states[key].state == "fallen", room.room_id + " fallen state recorded for restore")
	var plant := _first_prop(art, "planter")
	_check(plant != null, room.room_id + " planter interaction present")
	if plant != null:
		plant._receiver.call("take_damage", 9999, false, Vector3.RIGHT)
		await _settle(6)
		_check(plant.state == "broken" and plant._body.collision_layer == 0, room.room_id + " planter breaks and stops blocking")
	if not _shot_dir.is_empty():
		await _capture_room(tower, room, "after")


func _shoot(prop: ReactiveProp3D) -> float:
	var normal := prop.global_basis.z.normalized()
	var bullet := Projectile3D.new()
	add_child(bullet)
	bullet.activate({"direction": -normal, "speed": 20.0, "damage": 1, "hostile": false}, prop.global_position + normal * 2.0 + Vector3.UP * .7)
	var peak := 0.0
	for frame in 15:
		await _settle(1)
		peak = maxf(peak, prop._pivot.rotation.length())
	if is_instance_valid(bullet):
		bullet.queue_free()
	return peak


func _first_prop(art: Node3D, kind: String) -> ReactiveProp3D:
	for node in art.find_children("*", "", true, false):
		if node is ReactiveProp3D and node.prop_kind == kind:
			return node
	return null


func _capture_room(tower: TowerDescent3D, room: DungeonRoom3D, suffix: String) -> void:
	for world in tower.find_children("*", "WorldEnvironment", true, false):
		world.environment.fog_enabled = false
		world.environment.volumetric_fog_enabled = false
	for layer in tower.find_children("*", "CanvasLayer", true, false):
		layer.hide()
	for wall in tower.find_children("FlowViewWalls*", "Node3D", true, false):
		wall.hide()
	room.set_room_light_on(true)
	await _take_frame(room.global_position, 46.0, room.room_id + "_" + suffix)


func _capture_editor_source() -> void:
	var source := (load(DIR + "storage_15x15_94b04661833c_3e5f15.tscn") as PackedScene).instantiate() as Node3D
	source.position = Vector3(-20000, 0, 0)
	add_child(source)
	await _take_frame(source.global_position, 22.0, "storage_saved_editor_source")
	source.queue_free()


func _take_frame(at: Vector3, size: float, name: String) -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.global_position = at + Vector3(11, 37, 17)
	camera.look_at(at)
	camera.make_current()
	var light := OmniLight3D.new()
	add_child(light)
	light.light_energy = 10
	light.omni_range = 60
	light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	light.global_position = at + Vector3(0, 8, 0)
	await _settle(3)
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(_shot_dir.path_join(name + ".png")) == OK, "saved " + name)
	camera.queue_free()
	light.queue_free()


func _settle(frames := 3) -> void:
	for frame in frames:
		await get_tree().process_frame
		await get_tree().physics_frame


func _check(ok: bool, message: String) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("EXP03_INTERACTION_FAIL " + message)
	return ok
