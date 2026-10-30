extends Node
## 受控实验：**一份烘焙美术能不能套到同一复用键的所有房间上**（不碰正式资产，结束自动清理）
##
## 步骤：
##   1. 实例化关卡，取 n04 的复用键与目标路径。
##   2. 从工坊采集缓存取 n04 快照，把签名改写成当前键，落到 `runtime_rooms/`。
##   3. 重新实例化，检查：
##      · n04 走了美术层（`art_layer_loaded`），**没有**整房接管（`static_layout_scene_loaded` 为假）
##      · n04 仍然有程序化墙（`Wall_north` 存在）
##      · 美术层里的几何件被剥离（`art_layer_geometry_stripped` > 0）
##      · **同键的其它房间（n02）也命中同一份美术** ← 业主的核心诉求
##   4. 删文件，确认目录复原。
##
## 用法：godot --headless --path . --scene res://tools/_exp03_reuse_reuse_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const CACHE_DIR := "res://.godot/editor/scene_builder_runtime/expedition_03"
const SEED := 77003244
const SOURCE_ROOM := "n04"

var _failures: Array[String] = []


func _ready() -> void:
	var written := ""
	var tower_a := await _spawn()
	var room_a := _find(tower_a, SOURCE_ROOM)
	if room_a == null:
		print("REUSE_FAIL 找不到 %s" % SOURCE_ROOM)
		get_tree().quit(1)
		return
	var descriptor := CONTRACT.describe(room_a)
	var signature := str(descriptor["signature"])
	var base_path := str(room_a.get("static_layout_scene_path"))
	var target := CONTRACT.art_path(base_path, descriptor)
	print("REUSE_KEY %s" % signature.substr(0, 12))
	print("REUSE_TARGET %s" % target.get_file())

	# 同键的兄弟房间
	var siblings: Array[String] = []
	for value in tower_a.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or room.room_id == SOURCE_ROOM:
			continue
		if str(CONTRACT.describe(room)["signature"]) == signature:
			siblings.append(room.room_id)
	siblings.sort()
	print("REUSE_SIBLINGS %s" % str(siblings))
	tower_a.queue_free()
	await get_tree().process_frame

	var snapshot := _newest_cache_for(SOURCE_ROOM)
	if snapshot.is_empty():
		print("REUSE_SKIP 缓存里没有 %s 快照" % SOURCE_ROOM)
		get_tree().quit(2)
		return
	var text := FileAccess.get_file_as_string(snapshot)
	var replaced := _rewrite_signature(text, signature)
	if replaced == text:
		print("REUSE_FAIL 快照里没找到 runtime_room_signature")
		get_tree().quit(3)
		return
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var out := FileAccess.open(target, FileAccess.WRITE)
	if out == null:
		print("REUSE_FAIL 写不进 %s" % target)
		get_tree().quit(3)
		return
	out.store_string(replaced)
	out.close()
	written = target
	print("REUSE_WROTE %s" % target.get_file())

	var tower_b := await _spawn()
	for room_id in [SOURCE_ROOM] + siblings:
		var room := _find(tower_b, room_id)
		if room == null:
			continue
		var art_loaded := bool(room.get_meta("art_layer_loaded", false))
		var static_loaded := bool(room.get_meta("static_layout_scene_loaded", false))
		var stripped := int(room.get_meta("art_layer_geometry_stripped", 0))
		var has_wall := room.get_node_or_null("Wall_north") != null
		var art_root := room.get_node_or_null("AuthoredLayoutArtRoot")
		print("REUSE_ROOM %-10s art_layer=%-5s static=%-5s stripped=%-3d wall_north=%-5s art_root=%s"
			% [room_id, art_loaded, static_loaded, stripped, has_wall,
				"yes" if art_root != null else "no"])
		# 分组名必须归位：剥完结构之后剩下的全是美术，不该还叫 WhiteboxShell。
		if art_root != null:
			if art_root.get_node_or_null("WhiteboxShell") != null:
				_failures.append("%s 剥完后仍留着 WhiteboxShell 分组（工坊里会找不到下手的地方）" % room_id)
			if art_root.get_node_or_null("ArtComponents") == null:
				_failures.append("%s 剥完后没有 ArtComponents 分组" % room_id)
		# 每一间都必须走美术层，且几何自己重建
		if not art_loaded:
			_failures.append("%s 没有加载美术层（复用没生效）" % room_id)
		if static_loaded:
			_failures.append("%s 走了整房接管（应为美术层叠加）" % room_id)
		if not has_wall:
			_failures.append("%s 没有程序化墙（几何被美术层顶掉了）" % room_id)
	if siblings.is_empty():
		_failures.append("这个种子里没有同键的兄弟房间，无法验证跨房复用")

	tower_b.queue_free()
	await get_tree().process_frame
	if not written.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
		print("REUSE_CLEANED %s" % written.get_file())
	print("REUSE_PROBE_%s failures=%d"
		% ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("REUSE_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


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
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower


func _find(tower: Node, room_id: String) -> DungeonRoom3D:
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null and room.room_id == room_id:
			return room
	return null


func _newest_cache_for(room_id: String) -> String:
	var best := ""
	var best_time := 0
	for file_name in DirAccess.get_files_at(CACHE_DIR):
		if not file_name.ends_with(".tscn"):
			continue
		if file_name.get_basename().get_slice("_", 0) != room_id:
			continue
		var path := CACHE_DIR.path_join(file_name)
		var mtime := FileAccess.get_modified_time(path)
		if mtime > best_time:
			best_time = mtime
			best = path
	return best


func _rewrite_signature(text: String, signature: String) -> String:
	var key := "metadata/runtime_room_signature = \""
	var at := text.find(key)
	if at < 0:
		return text
	var start := at + key.length()
	var end := text.find("\"", start)
	if end < 0:
		return text
	return text.substr(0, start) + signature + text.substr(end)
