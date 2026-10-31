extends Node
## 受控实验：**远征03 特例 —— 公馆结构件留在美术层，并按覆盖接管程序化壳体**
##
## 业主 2026-10-31：「结构要进美术层，作为远征03的特例，然后……让这些资产都能在
## 远征03 使用拼装」。本探针验证两件必须同时成立的事：
##
##   · 结构件**不被剥掉**（否则工坊里摆的公馆护墙会静默消失）；
##   · 铺满时**程序化地板/墙被跳过**（否则两层地板叠在一起、墙也重复）。
##
## 并且验证「摆不满就不接管」：只放一件墙时，程序化壳体必须原样保留，
## 否则房间会漏风 —— 这是这个例外唯一真正危险的地方。
##
## 全程只写临时烘焙文件，结束自动删除。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const SEED := 77003244
const MANOR_BASE := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"
const FLOOR_PREFAB := MANOR_BASE + "/manor_floor_wood/env_manor_floor_wood_root_top3d.tscn"
const WALL_PREFAB := MANOR_BASE + "/manor_wall_standard/env_manor_wall_standard_root_top3d.tscn"
const DOOR_WALL_PREFAB := MANOR_BASE + "/manor_wall_door/env_manor_wall_door_root_top3d.tscn"
const DECOR_PREFAB := MANOR_BASE + "/manor_sofa/env_manor_sofa_root_top3d.tscn"
const GRID := 5.0

var _failures: Array[String] = []
var _written := ""
## 正式美术的原内容（用于测后恢复）。空 = 原本没有文件，测完删掉即可。
var _backup_text := ""
var _backup_path := ""


func _ready() -> void:
	# ── 取一间 25×25 的程序化房间 ──────────────────────────────────────────
	#
	# **不要用 `Wall_north` 是否存在来认房间**：铺装落地后美术层已覆盖四面，
	# 程序化墙被跳过，`Wall_north` 根本不存在 —— 第一版判据因此永远找不到房间、
	# 静默 SKIP（表现为"探针没报错也没生效"）。
	# 改用 `procedural_shell` + 尺寸，这才是房间的稳定属性。
	var tower_a := await _spawn()
	var target: DungeonRoom3D = null
	for value in tower_a.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		var size: Vector2 = room.call("get_dimensions")
		if is_equal_approx(size.x, 25.0) and is_equal_approx(size.y, 25.0):
			target = room
			break
	if target == null:
		print("MANOR_SKIP 这个种子里没有 25×25 的程序化房间")
		get_tree().quit(2)
		return
	var descriptor := CONTRACT.describe(target)
	var signature := str(descriptor["signature"])
	var target_path := CONTRACT.art_path(str(target.get("static_layout_scene_path")), descriptor)
	var room_name := target.room_id
	print("MANOR_KEY %s  room=%s  file=%s" % [signature.substr(0, 12), room_name, target_path.get_file()])
	print("MANOR_FLAG keep_structure=%s" % target.art_layer_keep_structure)
	_check(target.art_layer_keep_structure,
		"远征03 房间没有打开 art_layer_keep_structure（公馆结构件会被剥掉）")
	# **备份正式美术**：本探针要往同一个路径写临时场景来测两条分支，
	# 若该路径已有正式铺装（`_exp03_manor_shell_builder` 的产出），
	# 直接写就是覆盖别人的成果。先读进内存，结束（含异常退出）时写回。
	if FileAccess.file_exists(target_path):
		_backup_text = FileAccess.get_file_as_string(target_path)
		_backup_path = target_path
		print("MANOR_BACKUP 已有正式美术，测试后将原样恢复")
	tower_a.queue_free()
	await get_tree().process_frame

	# ── 一、铺满：25 块地砖 + 四面各 5 块护墙 ─────────────────────────────
	_write(target_path, _art_scene(signature, 25.0, 25.0, true, true))
	var tower_b := await _spawn()
	var full := _find(tower_b, room_name)
	if full == null:
		print("MANOR_FAIL 重新实例化后找不到 %s" % room_name)
		get_tree().quit(1)
		return
	_report("FULL", full)
	_check(bool(full.get_meta("art_layer_loaded", false)), "铺满时没有加载美术层")
	_check(int(full.get_meta("art_layer_structure_kept", 0)) == 45,
		"铺满时应保留 45 件结构（25 地砖 + 20 护墙），实得 %d"
		% int(full.get_meta("art_layer_structure_kept", 0)))
	_check(int(full.get_meta("art_layer_geometry_stripped", -1)) == 0,
		"铺满时结构件被剥掉了（stripped=%d），特例没生效"
		% int(full.get_meta("art_layer_geometry_stripped", -1)))
	_check(bool(full.get_meta("art_layer_floor_complete", false)), "铺满时地板覆盖判定为未满")
	_check((full.get_meta("art_layer_covered_sides", []) as Array).size() == 4,
		"铺满时应覆盖 4 面墙，实得 %s" % str(full.get_meta("art_layer_covered_sides", [])))
	_check(bool(full.get_meta("procedural_floor_skipped", false)), "铺满时没有跳过程序化地板")
	for side in ["north", "south", "west", "east"]:
		_check(full.get_node_or_null("Wall_%s" % side) == null,
			"铺满时 %s 面仍有程序化墙（美术墙与程序化墙重叠）" % side)
	_check(full.get_node_or_null("Floor") == null, "铺满时仍有程序化地板 Floor")
	_check(full.find_children("manor_sofa*", "Node3D", true, false).size() > 0,
		"装饰件（沙发）在铺满场景里丢了")
	var art_root := full.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	_check(art_root != null, "铺满时没有 AuthoredLayoutArtRoot（美术层没挂上）")
	if art_root != null:
		_check(_count_prefab(art_root, "env_manor_wall_standard") == 19,
			"美术层里的护墙件数量不对（应 19，实得 %d）"
			% _count_prefab(art_root, "env_manor_wall_standard"))
		_check(_count_prefab(art_root, "env_manor_wall_door") == 1,
			"北面中段的门墙模块丢了（门洞要靠它）")
		_check(_count_prefab(art_root, "env_manor_floor_wood") == 25,
			"美术层里的地砖数量不对（应 25，实得 %d）"
			% _count_prefab(art_root, "env_manor_floor_wood"))
	var door_count := full.find_children("*", "RoomDoor3D", true, false).size()
	print("MANOR_DOORS %d" % door_count)
	_check(door_count > 0, "跳过程序化墙之后门扇也没了（门洞归美术、门扇归程序化，缺一不可）")
	tower_b.queue_free()
	await get_tree().process_frame
	_remove(target_path)

	# ── 二、只摆一件墙：必须**不**接管 ───────────────────────────────────
	_write(target_path, _art_scene(signature, 25.0, 25.0, false, false))
	var tower_c := await _spawn()
	var partial := _find(tower_c, room_name)
	if partial == null:
		print("MANOR_FAIL 重新实例化后找不到 %s" % room_name)
		get_tree().quit(1)
		return
	_report("PARTIAL", partial)
	_check(int(partial.get_meta("art_layer_structure_kept", 0)) == 1,
		"只摆一件墙时应保留 1 件结构，实得 %d"
		% int(partial.get_meta("art_layer_structure_kept", 0)))
	_check(not bool(partial.get_meta("art_layer_floor_complete", true)), "只摆一件墙时地板被误判为铺满")
	_check(not bool(partial.get_meta("procedural_floor_skipped", false)),
		"只摆一件墙时跳过了程序化地板（房间会没有地板）")
	for side in ["north", "south", "west", "east"]:
		_check(partial.get_node_or_null("Wall_%s" % side) != null,
			"只摆一件墙时 %s 面的程序化墙被跳过了（房间会漏风）" % side)
	tower_c.queue_free()
	await get_tree().process_frame
	_remove(target_path)

	print("MANOR_ART_PROBE_%s failures=%d"
		% ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("MANOR_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _report(label: String, room: DungeonRoom3D) -> void:
	print("MANOR_%s kept=%d stripped=%d floor_full=%s sides=%s floor_skip=%s wall_n=%s"
		% [label,
			int(room.get_meta("art_layer_structure_kept", 0)),
			int(room.get_meta("art_layer_geometry_stripped", 0)),
			bool(room.get_meta("art_layer_floor_complete", false)),
			str(room.get_meta("art_layer_covered_sides", [])),
			bool(room.get_meta("procedural_floor_skipped", false)),
			"no" if room.get_node_or_null("Wall_north") == null else "yes"])


## 生成一份「公馆拼装」的美术场景文本。
##   · `full` = true：地砖铺满 5×5 格、四面各 5 块护墙（其中北面中段用门墙模块）
##   · `full` = false：只放 1 块护墙 + 1 件沙发（模拟"刚开始摆"）
func _art_scene(signature: String, width: float, height: float, full: bool, _unused: bool) -> String:
	var lines: Array[String] = []
	lines.append("[gd_scene load_steps=5 format=3]")
	lines.append("")
	lines.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"floor\"]" % FLOOR_PREFAB)
	lines.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"wall\"]" % WALL_PREFAB)
	lines.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"doorwall\"]" % DOOR_WALL_PREFAB)
	lines.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"decor\"]" % DECOR_PREFAB)
	lines.append("")
	lines.append("[node name=\"manor_art\" type=\"Node3D\"]")
	lines.append("metadata/runtime_room_signature = \"%s\"" % signature)
	lines.append("")
	lines.append("[node name=\"ArtComponents\" type=\"Node3D\" parent=\".\"]")
	lines.append("")
	var cols := int(round(width / GRID))
	var rows := int(round(height / GRID))
	if not full:
		lines.append(_instance("Wall_0", "wall", Vector3(-width * 0.5, 0.0, -height * 0.5 + GRID * 0.5), 0.0))
		lines.append(_instance("Sofa_0", "decor", Vector3(0.0, 0.0, 0.0), 0.0))
		return "\n".join(lines) + "\n"
	for row in range(rows):
		for col in range(cols):
			lines.append(_instance("Floor_%d_%d" % [col, row], "floor",
				Vector3(-width * 0.5 + (float(col) + 0.5) * GRID, 0.0,
					-height * 0.5 + (float(row) + 0.5) * GRID), 0.0))
	for index in range(cols):
		var x := -width * 0.5 + (float(index) + 0.5) * GRID
		# 北面中段用门墙模块，验证「门洞归美术」
		var north_kind := "doorwall" if index == cols / 2 else "wall"
		lines.append(_instance("Wall_north_%d" % index, north_kind, Vector3(x, 0.0, -height * 0.5), 0.0))
		lines.append(_instance("Wall_south_%d" % index, "wall", Vector3(x, 0.0, height * 0.5), 180.0))
	for index in range(rows):
		var z := -height * 0.5 + (float(index) + 0.5) * GRID
		lines.append(_instance("Wall_west_%d" % index, "wall", Vector3(-width * 0.5, 0.0, z), 90.0))
		lines.append(_instance("Wall_east_%d" % index, "wall", Vector3(width * 0.5, 0.0, z), 90.0))
	lines.append(_instance("Sofa_0", "decor", Vector3(0.0, 0.0, 0.0), 0.0))
	return "\n".join(lines) + "\n"


func _instance(node_name: String, resource_id: String, position: Vector3, degrees: float) -> String:
	var radians := deg_to_rad(degrees)
	var basis := Basis(Vector3.UP, radians)
	var text := (
		"[node name=\"%s\" parent=\"ArtComponents\" instance=ExtResource(\"%s\")]\n"
		+ "transform = Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)\n"
	)
	return text % [node_name, resource_id,
		_fmt(basis.x.x), _fmt(basis.x.y), _fmt(basis.x.z),
		_fmt(basis.y.x), _fmt(basis.y.y), _fmt(basis.y.z),
		_fmt(basis.z.x), _fmt(basis.z.y), _fmt(basis.z.z),
		_fmt(position.x), _fmt(position.y), _fmt(position.z)]


func _fmt(value: float) -> String:
	if is_zero_approx(value):
		return "0"
	if is_equal_approx(value, 1.0):
		return "1"
	if is_equal_approx(value, -1.0):
		return "-1"
	return "%.5f" % value


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("MANOR_FAIL 写不进 %s" % path)
		return
	file.store_string(text)
	file.close()
	_written = path
	print("MANOR_WROTE %s" % path.get_file())


## 结束收尾：**恢复**正式美术（有备份）或删除临时文件（原本没有）。
##
## 不能简单地"删掉"：如果这个路径本来就有正式铺装，删掉等于把别人的成果清了。
## 备份在 `_ready()` 里读取，这里无条件写回。
func _remove(path: String) -> void:
	if path.is_empty():
		return
	if not _backup_text.is_empty() and _backup_path == path:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup_text)
			file.close()
			print("MANOR_RESTORED %s（已恢复正式美术）" % path.get_file())
			return
		printerr("MANOR_FAIL 恢复失败，正式美术可能已被覆盖：", path)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MANOR_CLEANED %s" % path.get_file())


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


func _count_prefab(root: Node, slug_prefix: String) -> int:
	var count := 0
	for node in root.find_children("*", "Node3D", true, false):
		var file := str(node.scene_file_path).get_file()
		if file.begins_with(slug_prefix) and file.contains("_root_top3d"):
			count += 1
	return count


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
