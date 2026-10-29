extends SceneTree

const MODEL := preload("res://tools/scene_builder/layout_model.gd")

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var catalog := MODEL.catalog()
	var rows := {}
	for row in catalog["rows"]:
		rows[row["component_id"]] = row
	var room := MODEL.create_room(MODEL.WHITEBOX_DIR.path_join("rt_std_25x25_static_layout.tscn"))
	root.add_child(room)
	room.name = "ComponentRoomDemo"
	var group := room.get_node("ArtComponents")
	for x in range(5):
		for z in range(5):
			var id := "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C0%d" % (1 + (x + z) % 2)
			_add(room, group, rows[id], Vector3(-10 + x * 5, 0.08, -10 + z * 5))
	for x in [-7.5, -2.5, 2.5, 7.5]:
		_add(room, group, rows["ENV-SHARED-GENERIC-WALL-STANDARD-5M"], Vector3(x, 0.08, 12.5))
	# Two recognizable existing props, without creating any new production asset.
	for row in catalog["rows"]:
		if str(row.get("slug", "")) in ["work_cluster", "water_and_supply_corner"]:
			_add(room, group, row, Vector3(-5 if str(row["slug"]) == "work_cluster" else 6, 0.08, 3))
	var light := OmniLight3D.new()
	light.name = "WarmRoomLight"
	light.position = Vector3(0, 7, 0)
	light.omni_range = 20
	light.light_energy = 2.5
	light.light_color = Color(1, 0.86, 0.7)
	room.get_node("Lighting").add_child(light)
	light.owner = room
	room.set_meta("layout_instance_total", MODEL.managed_components(room).size())
	var packed := PackedScene.new()
	var error := packed.pack(room)
	if error == OK:
		DirAccess.make_dir_recursive_absolute("res://tools/scene_builder/examples")
		error = ResourceSaver.save(packed, "res://tools/scene_builder/examples/component_room_demo.tscn")
	print("SCENE_BUILDER_DEMO error=%d components=%d" % [error, MODEL.managed_components(room).size()])
	room.free()
	quit(0 if error == OK else 1)

func _add(room: Node3D, parent: Node, row: Dictionary, point: Vector3) -> void:
	var node := MODEL.instantiate_component(row)
	node.position = point
	parent.add_child(node, true)
	node.owner = room
