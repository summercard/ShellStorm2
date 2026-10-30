extends SceneTree
## Run only in a separate process with isolated user data, never inside the editor.
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
var options := {}
var status_path := ""

func _initialize() -> void:
	for value in OS.get_cmdline_user_args():
		var pair := str(value).split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	status_path = str(options.get("status", ""))
	_run.call_deferred()

func _status(label: String, current: int = 0, total: int = 0) -> void:
	var file := FileAccess.open(status_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"state": "running", "label": label, "current": current, "total": total}))

func _run() -> void:
	var scene_path := str(options.get("scene", "res://scenes/ExpeditionLevel03_3D.tscn"))
	_status("正在运行正式关卡生成链…")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		quit(2)
		return
	var level = packed.instantiate()
	if level == null or not level.has_method("get_expedition_level_id"):
		if level != null:
			level.free()
		printerr("RUNTIME_CAPTURE_INVALID_LEVEL 正式关卡脚本未能加载，或场景不支持房间采集。")
		quit(2)
		return
	level.set("test_mode", true)
	level.set("run_seed_override", int(options.get("seed", "77003244")))
	root.add_child(level)
	for i in range(12):
		await process_frame
	var rooms: Array = level.get("_rooms")
	var records: Array = level.get("_records")
	var level_id: String = level.call("get_expedition_level_id")
	var rows: Array = []
	var cache_dir := "res://.godot/editor/scene_builder_runtime/" + level_id
	DirAccess.make_dir_recursive_absolute(cache_dir)
	for i in range(rooms.size()):
		var room := rooms[i] as Node3D
		if not CONTRACT.supports(room):
			continue
		_status("读取真实房间 %s" % str(room.get("room_id")), i, rooms.size())
		room.call("ensure_shell_built")
		var descriptor := CONTRACT.describe(room)
		var wall_height := _wall_height(room)
		var base_path := str(room.get("static_layout_scene_path"))
		var art_path := CONTRACT.art_path(base_path, descriptor)
		var reference_path := cache_dir.path_join(art_path.get_file())
		var record := {}
		for value in records:
			if str(value.get("id", "")) == str(descriptor["room_id"]):
				record = value
				break
		var matched := CONTRACT.matching_path(room, base_path)
		if matched.is_empty():
			var snapshot := _snapshot(room, descriptor, level_id, scene_path, record, wall_height)
			var scene := PackedScene.new()
			var error := scene.pack(snapshot)
			if error == OK:
				error = ResourceSaver.save(scene, reference_path)
			snapshot.free()
			if error != OK:
				printerr("RUNTIME_CAPTURE_SAVE_FAILED ", reference_path, " ", error)
				quit(3)
				return
		else:
			reference_path = matched
		var types := {"STAIR_LOBBY": "入口安全房", "BOSS": "Boss房", "COMBAT": "战斗房",
			"UPGRADE": "准备房", "EXTRACTION": "撤离房", "SHOP": "商店", "": "连接房"}
		var kind := str(room.get("room_type"))
		var title := "远征%s-%s（%s）" % [level_id.trim_prefix("expedition_"), types.get(kind, kind), descriptor["room_id"]]
		rows.append({"path": reference_path, "art_path": art_path, "runtime_source": true,
			"room_id": descriptor["room_id"], "template_id": str(descriptor.get("template_id", "")),
			"signature": descriptor["signature"], "level": "远征" + level_id.trim_prefix("expedition_"),
			"kit": "游戏内房间 · 种子 %s" % str(level.get("run_seed")),
			"label": title,
			"size_m": descriptor["size_m"], "wall_height_m": wall_height,
			"source_label": "正式关卡运行生成 · 实测墙高%.2fm" % wall_height, "whitebox": false,
			"search": (title + " " + str(record.get("floor_plan_key", "")) + " " + level_id).to_lower()})
		await process_frame
	var output := FileAccess.open(str(options["index"]), FileAccess.WRITE)
	output.store_string(JSON.stringify({"schema": CONTRACT.SCHEMA, "level_id": level_id,
		"scene": scene_path, "seed": level.get("run_seed"), "rows": rows}, "\t"))
	print("RUNTIME_CAPTURE_OK rooms=", rows.size(), " seed=", level.get("run_seed"))
	level.queue_free()
	await process_frame
	quit(0 if not rows.is_empty() else 4)

func _snapshot(room: Node3D, descriptor: Dictionary, level_id: String, scene_path: String, record: Dictionary, wall_height: float) -> Node3D:
	var result := Node3D.new()
	result.name = "Room_" + str(descriptor["room_id"])
	var dimensions: Array = descriptor["size_m"]
	for pair in [["scene_builder_schema", "shellstorm2.component_scene.v1"], ["runtime_room_source_schema", CONTRACT.SCHEMA],
		["runtime_room_signature", descriptor["signature"]], ["runtime_room_geometry", descriptor["geometry"]],
		["runtime_source_scene", scene_path], ["runtime_source_seed", int(options.get("seed", "0"))],
		["runtime_source_room_id", descriptor["room_id"]], ["level_id", level_id], ["room_id", descriptor["room_id"]],
		["display_name", "远征%s-%s房" % [level_id.trim_prefix("expedition_"), descriptor["room_id"]]],
		["size_m", dimensions], ["grid_unit_m", 5.0], ["wall_height_m", wall_height],
		["template_id", str(descriptor.get("template_id", descriptor["room_id"]))], ["footprint_is_rect", true],
		["footprint_polygon_m", [[0, 0], [dimensions[0], 0], dimensions, [0, dimensions[1]]]]]:
		result.set_meta(pair[0], pair[1])
	for name in ["WhiteboxShell", "ArtComponents", "Lighting", "ConnectionPorts"]:
		var group := Node3D.new()
		group.name = name
		result.add_child(group)
		group.owner = result
	for child in room.get_children():
		if not child is Node3D or not _safe_shell(child):
			continue
		if not child is GeometryInstance3D and not child is StaticBody3D and child.find_children("*", "GeometryInstance3D", true, false).is_empty():
			continue
		# Runtime instances retain editor-unrelated SceneState/unique-id history.
		# Re-instance the same stable prefab and transfer actual runtime overrides.
		var copy := _copy_shell(child)
		copy.name = "ShellPart_%03d" % result.get_node("WhiteboxShell").get_child_count()
		result.get_node("WhiteboxShell").add_child(copy)
		_own(copy, result)
	# **不写连接端口**：端口是几何层（决定门开在哪、通向谁），由运行时按本局算。
	# 2026-10-31 之前这里把端口写进快照，于是同一份美术被不同门位的房间复用时，
	# 端口必然互相矛盾 —— 而端口已经不进复用键，写进来只会误导。
	return result

func _wall_height(room: Node3D) -> float:
	var height := 0.0
	for mesh in room.find_children("*", "MeshInstance3D", true, false):
		# 结构件判据统一走契约（2026-10-31）。**只认墙**：
		# 角柱做到 2.9m、门楣在墙顶之上，混进来量出来的就不是墙高。
		# 原来这里靠「名字里含 wall」绕开，那是随资产改名就失效的判据。
		var node: Node = mesh
		var is_wall := false
		while node != room and node != null:
			if CONTRACT.is_wall_prefab(str(node.scene_file_path)):
				is_wall = true
				break
			node = node.get_parent()
		if is_wall:
			var bounds: AABB = room.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			height = maxf(height, bounds.end.y)
	return height

func _safe_shell(node: Node) -> bool:
	if node.get_script() != null or node is Area3D or node is Light3D or node is AudioStreamPlayer3D:
		return false
	for child in node.get_children():
		if not _safe_shell(child):
			return false
	return true

func _copy_shell(source: Node) -> Node:
	var target: Node
	if not source.scene_file_path.is_empty():
		target = (load(source.scene_file_path) as PackedScene).instantiate()
	elif source is MeshInstance3D:
		target = MeshInstance3D.new()
	elif source is StaticBody3D:
		target = StaticBody3D.new()
	elif source is CollisionShape3D:
		target = CollisionShape3D.new()
	else:
		target = Node3D.new()
	_transfer_shell(source, target)
	return target

func _transfer_shell(source: Node, target: Node) -> void:
	var properties := {}
	for property in target.get_property_list():
		properties[str(property["name"])] = true
	for property in ["transform", "visible", "mesh", "material_override", "material_overlay", "cast_shadow",
		"layers", "collision_layer", "collision_mask", "physics_material_override", "shape", "disabled"]:
		if properties.has(property):
			target.set(property, source.get(property))
	for key in source.get_meta_list():
		target.set_meta(key, source.get_meta(key))
	for child in source.get_children():
		var counterpart := target.get_node_or_null(NodePath(str(child.name)))
		if counterpart == null:
			counterpart = _copy_shell(child)
			counterpart.name = child.name
			counterpart.set_meta("runtime_captured_extra", true)
			target.add_child(counterpart)
		else:
			_transfer_shell(child, counterpart)

func _own(node: Node, owner_root: Node) -> void:
	node.owner = owner_root
	if not node.scene_file_path.is_empty():
		for child in node.get_children():
			if bool(child.get_meta("runtime_captured_extra", false)):
				_own(child, owner_root)
		return
	for child in node.get_children():
		_own(child, owner_root)
