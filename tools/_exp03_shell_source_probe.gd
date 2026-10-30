extends Node
## 远征03「房间壳体到底是哪来的」探针。
##
## 回答一件事：**每间房最终用的是烘焙 TSCN 静态场景，还是程序化壳体？**
## 判据全部取运行时实例与 meta，不读配置推。
##
## 用法：
##   godot --headless --path . --scene res://tools/_exp03_shell_source_probe.tscn
##
## 为什么要这个探针：`DungeonRoom3D._build_shell()` 会**先**尝试
## `_expedition_static_layout_path()`（其中优先 `runtime_rooms/<room_id>_<签名>.tscn`），
## 命中就用静态场景并跳过程序化分支。所以「关卡是 flow 模式」只说明配置意图，
## 不说明运行时实际走了哪条路 —— 必须看实例。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const BAKED_DIR := (
	"res://assets/art/environments/tower_zones/expedition/runtime/"
	+ "room_instances/expedition_03/runtime_rooms"
)
const SEEDS: Array[int] = [77003244, 100990, 42, 123456]


func _ready() -> void:
	var totals := {"static": 0, "procedural": 0, "unknown": 0}
	for seed_value in SEEDS:
		await _probe_seed(seed_value, totals)
	print("PROBE_SUMMARY static=%d procedural=%d unknown=%d"
		% [totals["static"], totals["procedural"], totals["unknown"]])
	_report_baked_files()
	get_tree().quit(0)


func _probe_seed(seed_value: int, totals: Dictionary) -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("PROBE_FAIL 不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame

	var rooms: Array = tower.get("_rooms") as Array
	print("PROBE_SEED %d rooms=%d" % [seed_value, rooms.size()])

	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame

	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		var declared := str(room.get("static_layout_scene_path"))
		var baked := ""
		if not declared.is_empty():
			baked = CONTRACT.matching_path(room, declared)
		var loaded := bool(room.get_meta("static_layout_scene_loaded", false))
		var owns_walls := bool(room.get_meta("room_owns_walls", false))
		var source := "unknown"
		if loaded:
			source = "static"
		elif owns_walls:
			source = "procedural"
		totals[source] = int(totals[source]) + 1
		print("  ROOM seed=%d id=%-12s source=%-10s declared=%-6s baked=%-6s owns_walls=%s module_shell=%s"
			% [
				seed_value, room.room_id, source,
				"-" if declared.is_empty() else declared.get_file(),
				"-" if baked.is_empty() else baked.get_file(),
				owns_walls, bool(room.get("tower_module_shell")),
			])
		if room.room_id == "n04":
			var descriptor := CONTRACT.describe(room)
			print("  N04_RUNTIME_SIGNATURE %s" % str(descriptor["signature"]).substr(0, 20))
			print("  N04_RUNTIME_GEOMETRY %s" % JSON.stringify(descriptor["geometry"]))
		if seed_value == SEEDS[0]:
			var desc := CONTRACT.describe(room)
			var wanted := CONTRACT.art_path(declared, desc)
			print("  EXPECT seed=%d id=%-12s sig=%s file=%s exists=%s"
				% [
					seed_value, room.room_id, str(desc["signature"]).substr(0, 20),
					wanted.get_file(), FileAccess.file_exists(wanted),
				])

	if seed_value == SEEDS[0]:
		_dump_shell_owner(rooms)
	tower.queue_free()
	await get_tree().process_frame


## 入口安全房 `start` 既没走静态布局、也没走程序化 —— 它走的是
## `DungeonRoom3D._build_safe_room_shell()`（art_root + 墙槽 + 地砖 + 出口标牌）。
## 这里把它的子节点清点一遍，证明它确实是第三套壳。
func _dump_shell_owner(rooms: Array) -> void:
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		if room.room_id not in ["start", "n04"]:
			continue
		var counts := {}
		for child in room.get_children():
			var key := "%s <%s>" % [child.name, child.get_class()]
			counts[key] = int(counts.get(key, 0)) + 1
		print("SHELL_CHILDREN %s type=%s dims=%s kinds=%d"
			% [room.room_id, room.room_type, room.get_dimensions(), counts.size()])
		for key in counts.keys():
			print("    CHILD %-56s x%d" % [key, counts[key]])


## 磁盘上有一份 `runtime_rooms/n04_<hash>.tscn` 烘焙壳。它到底能不能被认领，
## 取决于运行时算出的签名前 20 位是否与文件名一致。
func _report_baked_files() -> void:
	var dir := DirAccess.open(BAKED_DIR)
	if dir == null:
		print("BAKED_DIR missing")
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tscn"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	print("BAKED_FILES count=%d %s" % [files.size(), str(files)])
	for file_name in files:
		var packed := load(BAKED_DIR.path_join(file_name)) as PackedScene
		if packed == null:
			print("    BAKED %s 无法加载" % file_name)
			continue
		var state := packed.get_state()
		var signature := ""
		for index in range(state.get_node_property_count(0)):
			if str(state.get_node_property_name(0, index)) == "metadata/runtime_room_signature":
				signature = str(state.get_node_property_value(0, index))
		print("    BAKED %s signature=%s" % [file_name, signature.substr(0, 20)])
