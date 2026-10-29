extends SceneTree

const MODEL := preload("res://tools/scene_builder/layout_model.gd")
const DOCK := preload("res://tools/scene_builder/builder_dock.gd")
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _run() -> void:
	var catalog := MODEL.catalog()
	_check((catalog["errors"] as Array).is_empty(), "catalog errors: %s" % str(catalog["errors"]))
	var rows: Array[Dictionary] = catalog["rows"]
	_check(rows.size() >= 218, "shared catalog lost components")
	var floor_row: Dictionary = {}
	var wall_row: Dictionary = {}
	var door_row: Dictionary = {}
	for row in rows:
		if str(row["component_id"]) == "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C01":
			floor_row = row
		if str(row["component_id"]) == "ENV-SHARED-GENERIC-WALL-STANDARD-5M":
			wall_row = row
		if str(row["component_id"]) == "ENV-SHARED-GENERIC-WALL-DOOR-5M":
			door_row = row
	_check(not floor_row.is_empty(), "missing production floor tile")
	if floor_row.is_empty():
		_finish()
		return
	var rooms: Array[Node3D] = []
	for sample in [["std_25x25", 25], ["corridor_45x40_l_turn", 42], ["corridor_45x40_u_turn", 60]]:
		var path := MODEL.WHITEBOX_DIR.path_join("rt_%s_static_layout.tscn" % sample[0])
		var room := MODEL.create_room(path)
		_check(room != null, "cannot build authoring room: " + path)
		if room == null:
			continue
		root.add_child(room)
		rooms.append(room)
		var size: Variant = room.get_meta("size_m")
		var phase := MODEL.phase(room, 5, true)
		var points := MODEL.rectangle_points(Vector3(phase.x, 0.08, phase.y),
			Vector3(float(size[0]) / 2 - 2.5, 0.08, float(size[1]) / 2 - 2.5), 5)
		var accepted := 0
		for point in points:
			if MODEL.fits(point, floor_row, 0, MODEL.polygon(room)):
				accepted += 1
		_check(accepted == int(sample[1]), "%s clipped floor cells %d != %d" % [sample[0], accepted, sample[1]])
		_check(room.get_node("ConnectionPorts").get_child_count() > 0, "reference ports lost")
	# Fast mouse motion must interpolate each grid cell, including reverse and diagonal drags.
	_check(MODEL.line_points(Vector3.ZERO, Vector3(25, 0, 0), 5).size() == 6, "brush stroke has gaps")
	_check(MODEL.line_points(Vector3(25, 0, 0), Vector3.ZERO, 5).back() == Vector3.ZERO, "reverse stroke misses endpoint")
	_check(MODEL.line_points(Vector3.ZERO, Vector3(25, 0, 15), 5).size() == 6, "diagonal brush wrong")
	_check(MODEL.rectangle_points(Vector3.ZERO, Vector3(500, 0, 500), 5).is_empty(), "batch overflow silently truncated")
	_check(MODEL.line_points(Vector3.ZERO, Vector3(50000, 0, 0), 5).is_empty(), "line overflow accepted")
	_check(MODEL.brush_points(Vector3.ZERO, 3, 5).size() == 9, "brush footprint wrong")
	_check(MODEL.snap_point(Vector3(2.6, 3.1, 7.4), 5, Vector2(2.5, 2.5)) == Vector3(2.5, 3.1, 7.5), "half-grid phase or elevation lost")
	if not rooms.is_empty():
		var standard := rooms[0]
		_check(MODEL.component_phase(standard, 5, true, wall_row, 0).is_equal_approx(Vector2(-10, -12.5)), "wall normal not snapped to tile boundary")
		_check(MODEL.component_phase(standard, 5, true, wall_row, PI / 2).is_equal_approx(Vector2(-12.5, -10)), "rotated wall phase wrong")
		_check(MODEL.fits(Vector3(5, 0.08, -12.5), wall_row, 0, MODEL.polygon(standard)), "perimeter wall rejected due to thickness")
		_check(MODEL.blocks_port(standard, Vector3(0, 0.08, -12.5), wall_row, 0), "solid wall may block reference door")
		_check(not MODEL.blocks_port(standard, Vector3(0, 0.08, -12.5), door_row, 0), "door frame cannot be placed at door")
		_verify_persistence(rooms[0], floor_row)
	_verify_whiteboxes()
	var dock := DOCK.new()
	root.add_child(dock)
	dock.set_catalog(rows, [])
	dock.set_whiteboxes(MODEL.whiteboxes())
	_check(dock.visible_rows.size() == rows.size(), "dock hides catalog entries")
	dock.search.text = "FLOOR-TILE-R01-C01"
	dock.refresh_list()
	_check(dock.visible_rows.size() == 1, "component search failed")
	dock.favorites = [floor_row["component_id"]]
	dock.search.text = ""
	dock.favorites_only.button_pressed = true
	_check(dock.visible_rows.size() == 1, "favorites filter failed")
	_check(not dock.snap_enabled.button_pressed and dock.cell_centers.disabled, "free placement not the default")
	dock.snap_enabled.button_pressed = true
	_check(not dock.cell_centers.disabled, "tile phase unavailable when snapping enabled")
	dock.favorites_only.button_pressed = false
	dock.library_tabs.current_tab = 1
	dock._select_suite(0)
	_check(not dock.visible_rows.is_empty() and dock.library_tabs.current_tab == 0, "suite card did not open components")
	var suite := str(dock.suite_rows[0]["group"])
	for visible in dock.visible_rows:
		_check(visible["group"] == suite, "suite filter mixed kits")
	dock.type_filter.select(1)
	dock.refresh_list()
	_check(not dock.visible_rows.is_empty(), "minor type filter empty")
	for visible in dock.visible_rows:
		_check(visible["type_tag"] == dock.type_filter.get_item_text(1), "minor tag filter mixed types")
	_check(dock.shelf.get_item_icon(0) != null, "cards have no placeholder during loading")
	var scene_index = load("res://tools/scene_builder/scene_index.gd")
	var scenes: Array[Dictionary] = scene_index.scan(["res://tools/scene_builder/examples/component_room_demo.tscn"])
	var known_room := false
	var generated_art := false
	var aliases := 0
	for entry in scenes:
		if str(entry["path"]).ends_with("expedition_01/f00_room_01_static_layout.tscn"):
			known_room = entry["label"] == "远征01-走廊01房" and not entry["whitebox"]
		if str(entry["path"]).ends_with("scene_builder/examples/component_room_demo.tscn"):
			generated_art = not entry["whitebox"]
		if str(entry["path"]).ends_with("/f00_room_01/room_static_layout.tscn"):
			aliases += 1
	_check(known_room, "canonical room name / suite not indexed")
	_check(generated_art, "new editor art scene missing or classified as whitebox")
	_check(aliases == 0, "legacy scene alias duplicated canonical room")
	_check(load("res://tools/scene_builder/thumbnail_service.gd") != null, "thumbnail service cannot compile")
	var browser = load("res://tools/scene_builder/scene_browser.gd").new()
	root.add_child(browser)
	browser.refresh_index()
	var art_count: int = browser.displayed_count
	browser.show_whiteboxes.button_pressed = true
	_check(browser.displayed_count > art_count, "whitebox toggle does not distinguish references")
	browser.search.text = "远征01-走廊01房"
	browser.rebuild()
	_check(browser.displayed_count == 1, "room name search not unique")
	var leaf: TreeItem = browser.tree.get_root().get_first_child().get_first_child().get_first_child()
	var requested: Array[String] = []
	browser.scene_requested.connect(func(path): requested.append(path))
	leaf.select(0)
	browser._open_selected()
	_check(requested.size() == 1 and requested[0].ends_with("expedition_01/f00_room_01_static_layout.tscn"), "room activation emitted the wrong file")
	browser.purpose = "new_whitebox"
	browser.search.text = "远征03"
	browser.refresh_index()
	_check(browser.displayed_count == MODEL.whiteboxes().size(), "whitebox browser hides expedition03 / EGT sources")
	browser.search.text = "egt_entrance_S1_static_layout.tscn"
	browser.rebuild()
	_check(browser.displayed_count == 1, "EGT whitebox cannot be found by its source ID")
	var whitebox_requests: Array[String] = []
	browser.whitebox_requested.connect(func(path): whitebox_requests.append(path))
	leaf = browser.tree.get_root().get_first_child().get_first_child().get_first_child()
	leaf.select(0)
	browser._open_selected()
	_check(whitebox_requests.size() == 1 and requested.size() == 1, "whitebox selection opened the source as an art scene")
	print("SCENE_BUILDER_INDEX scenes=%d art=%d kits=%d" % [scenes.size(), art_count, dock.suite_rows.size()])
	browser.free()
	dock.free()
	for room in rooms:
		room.free()
	_finish()

func _verify_whiteboxes() -> void:
	var choices := MODEL.whiteboxes()
	var found := {}
	for entry in choices:
		found[str(entry["path"])] = true
		var room := MODEL.create_room(str(entry["path"]))
		_check(room != null and room.has_meta("size_m") and room.get_node("ConnectionPorts").get_child_count() > 0,
			"cannot create whitebox reference with geometry / ports: " + str(entry["path"]))
		if room != null:
			_check(not room.has_meta("whitebox"), "authored art inherited the source whitebox flag")
			room.free()
	for directory in [MODEL.WHITEBOX_DIR, MODEL.SCENE_INDEX.ROOT.path_join("egt_room_types")]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".tscn") and (file.begins_with("rt_") or file.begins_with("cr_") or file.begins_with("egt_")):
				_check(found.has(directory.path_join(file)), "whitebox discovery missed " + file)
	var egt_path := MODEL.SCENE_INDEX.ROOT.path_join("egt_room_types/egt_entrance_S1_static_layout.tscn")
	var egt_room := MODEL.create_room(egt_path)
	_check(egt_room != null and egt_room.get_meta("template_id", "") == "egt_entrance_S1" and egt_room.get_meta("shell_id", "") == "egt_entrance_S1", "EGT shell identity lost")
	_check(MODEL.default_art_path(egt_path).begins_with(MODEL.WHITEBOX_DIR + "/art_egt_"), "EGT art output contaminates the shared whitebox directory")
	if egt_room != null:
		var args := OS.get_cmdline_user_args()
		var output := (args[0] if not args.is_empty() else OS.get_user_data_dir()).path_join("egt_reference_roundtrip_art.tscn")
		var packed := PackedScene.new()
		_check(packed.pack(egt_room) == OK and ResourceSaver.save(packed, output) == OK, "EGT-derived room could not save")
		var projected := false
		for entry in MODEL.SCENE_INDEX.scan([output]):
			if entry["path"] == output:
				projected = not entry["whitebox"] and entry["level"] == "远征03" and entry["template_id"] == "egt_entrance_S1"
		_check(projected, "saved EGT art was hidden as a whitebox")
		egt_room.free()
	print("SCENE_BUILDER_WHITEBOX sources=%d all_loaded=%d" % [choices.size(), found.size()])

func _verify_persistence(room: Node3D, row: Dictionary) -> void:
	var instance := MODEL.instantiate_component(row)
	_check(instance != null, "cannot instantiate real prefab")
	if instance == null:
		return
	room.get_node("ArtComponents").add_child(instance)
	instance.owner = room
	instance.position = Vector3(-10, 0.08, -10)
	var inner := instance.get_child(0)
	_check(inner.owner != room, "prefab internals unpacked into room")
	var reference := Node3D.new()
	reference.name = "_EditorOnlyWhitebox"
	room.add_child(reference, false, Node.INTERNAL_MODE_BACK)
	var light := OmniLight3D.new()
	light.name = "AuthoredOmni"
	light.light_energy = 3.4
	light.position = Vector3(4, 7, -3)
	room.get_node("Lighting").add_child(light)
	light.owner = room
	var packed := PackedScene.new()
	_check(packed.pack(room) == OK, "cannot pack authoring room")
	var args := OS.get_cmdline_user_args()
	var directory := args[0] if not args.is_empty() else OS.get_user_data_dir()
	var path := directory.path_join("scene_builder_roundtrip.tscn")
	_check(ResourceSaver.save(packed, path) == OK, "cannot save layout")
	var text := FileAccess.get_file_as_string(path)
	_check(text.contains(str(row["prefab_path"])), "saved layout has no stable prefab reference")
	_check(not text.contains("_EditorOnlyWhitebox"), "editor-only reference leaked into saved scene")
	_check(not text.contains("ImportedModel"), "prefab descendants serialized inside layout")
	var restored := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	root.add_child(restored)
	_check(MODEL.managed_components(restored).size() == 1, "component lost on reopen")
	var loaded_instance := MODEL.managed_components(restored)[0]
	_check(loaded_instance.scene_file_path == str(row["prefab_path"]), "reference no longer instanced")
	_check(loaded_instance.position.is_equal_approx(instance.position), "authored transform lost")
	var loaded_light := restored.get_node("Lighting/AuthoredOmni") as OmniLight3D
	_check(is_equal_approx(loaded_light.light_energy, 3.4) and loaded_light.position == light.position, "light settings lost on reopen")
	_check(MODEL.validate(restored).is_empty(), "roundtrip validation failed")
	restored.free()

func _finish() -> void:
	for failure in _failures:
		printerr("SCENE_BUILDER_FAIL " + failure)
	print("SCENE_BUILDER_MODEL_%s checks=%d failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
