extends Node
## 打印每间真房间的 template_id / signature / 门位，用于确认结构层该按什么分文件。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const SEED := 77003244


func _ready() -> void:
	var tower := await _spawn()
	var rooms: Array = []
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		if room.room_id.begins_with("cr") or room.room_id.begins_with("conn_"):
			continue
		rooms.append(room)
	rooms.sort_custom(func(a, b): return str(a.room_id) < str(b.room_id))
	var by_key := {}
	for value in rooms:
		var room := value as DungeonRoom3D
		var d := CONTRACT.describe(room)
		var sig := str(d["signature"])
		var base := str(room.get("static_layout_scene_path"))
		var path := CONTRACT.art_path(base, d)
		var key := path.get_file()
		var sides: Array[String] = []
		for port_value in room.get("connection_ports"):
			var port := port_value as Dictionary
			sides.append("%s@%.1f" % [str(port.get("side", "")), float(port.get("lane_m", 0.0))])
		sides.sort()
		print("KEY room=%-22s tmpl=%-16s sig=%s file=%s portals=%s"
			% [room.room_id, str(d["template_id"]), sig.substr(0, 12), key, str(sides)])
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append(room.room_id)
	print("--- 同文件名冲突 ---")
	for key in by_key.keys():
		var members: Array = by_key[key]
		if members.size() > 1:
			print("  COLLIDE %s <- %s" % [key, str(members)])
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _spawn() -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower
