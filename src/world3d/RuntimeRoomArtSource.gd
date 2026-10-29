@tool
extends RefCounted
## Shared identity for a generated room and its editable local-space art scene.
const SCHEMA := "shellstorm2.runtime_room_art.v1"

static func supports(room: Node3D) -> bool:
	if bool(room.get("tower_module_shell")) or str(room.get("static_layout_scene_path")).is_empty():
		return false
	for port in room.get("connection_ports"):
		if port is Dictionary and port.has("door_width_m"):
			return true
	return false

static func describe(room: Node3D) -> Dictionary:
	var dimensions: Vector2 = room.call("get_dimensions")
	var ports: Array = []
	for value in room.get("connection_ports"):
		var port := value as Dictionary
		ports.append([str(port.get("side", "")), port.get("position_m", []),
			float(port.get("lane_m", 0)), float(port.get("door_width_m", 0)),
			float(port.get("height_m", 0)), bool(port.get("open_passage", false)),
			str(port.get("target", port.get("target_room_id", ""))).is_empty()])
	ports.sort_custom(func(a, b): return JSON.stringify(a) < JSON.stringify(b))
	var doors: Array = []
	for value in room.get("doors"):
		doors.append(str(value))
	doors.sort()
	var open_sides: Array = []
	for value in room.get("open_wall_directions"):
		open_sides.append(str(value))
	open_sides.sort()
	var geometry := {"schema": SCHEMA, "size": [dimensions.x, dimensions.y],
		"type": str(room.get("room_type")), "ports": ports, "doors": doors,
		"open_sides": open_sides, "module_shell": bool(room.get("tower_module_shell")),
		"size_class": str(room.get("size_class")), "safe_corner": bool(room.get("safe_room_corner_l"))}
	return {"signature": JSON.stringify(geometry, "", true).sha256_text(), "geometry": geometry,
		"room_id": str(room.get("room_id")), "size_m": [dimensions.x, dimensions.y]}

static func art_path(base_static_path: String, descriptor: Dictionary) -> String:
	if base_static_path.is_empty() or descriptor.is_empty():
		return ""
	var room_id := str(descriptor["room_id"]).validate_filename()
	return base_static_path.get_base_dir().path_join("runtime_rooms/%s_%s.tscn" %
		[room_id, str(descriptor["signature"]).substr(0, 20)])

static func matching_path(room: Node3D, base_static_path: String) -> String:
	if not supports(room):
		return ""
	var descriptor := describe(room)
	var path := art_path(base_static_path, descriptor)
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return ""
	var packed := load(path) as PackedScene
	if packed == null:
		return ""
	var state := packed.get_state()
	for index in range(state.get_node_property_count(0)):
		if str(state.get_node_property_name(0, index)) == "metadata/runtime_room_signature":
			return path if str(state.get_node_property_value(0, index)) == str(descriptor["signature"]) else ""
	return ""
