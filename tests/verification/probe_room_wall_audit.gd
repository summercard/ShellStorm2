extends Node

## 一次性探针（业主 2026-10-21）：「08 号房间有一边墙的位置错位了。」
##
## 前两支探针都答不了这个问题：
##   · 墙剖面（`probe_room_wall_profile`）打的是物理射线，先撞到家具/管件就停，
##     偏移 +2/+3/+5 全是噪声；
##   · 布局文件对比（room_01 vs room_08）用的是**烘焙帧**坐标，而运行时
##     `_align_static_layout_to_room()` 会整体转壳、还会搬门墙件，文件帧 ≠ 运行帧。
##
## 这一支换个口径：**在房间帧里量「实例级」墙件的世界 AABB**。
##   ⚠️ 两个口径坑（前一版都踩了）：
##   ① 必须按**实例**聚合，不能按 MeshInstance3D 逐片量 —— 一片 5 m 墙里塞了
##      `部件00/04/05` 三块子网格（面板 + 两根立柱），逐片量会得到三份「偏 2.5 m 的墙」；
##   ② 判走向必须看**薄轴**，不能取「最近的边界」—— 转角件离两条边一样近，
##      按最近边界判会把纵向墙算到横向面上，偏移量直接算错 20 m。
##      薄轴 = X 向薄 ⇒ 墙沿 Z 跑（东/西面）；Z 向薄 ⇒ 墙沿 X 跑（南/北面）。
##
##   ① 逐件列出墙件：实例名、走向、所在面、离该面边界多少米、沿墙覆盖区间；
##   ② 每条边按 0.5 m 分格统计覆盖，把没被任何墙件盖住的格子打成缺口；
##   ③ 只要某件墙离它所在的那一面超过 `MISPLACED_TOLERANCE_M` 就点名。
##      ⚠️ L 型房型的**内转角墙**本来就不在矩形边界上（实测 l_turn 的内墙在边界内
##      15 m），所以点名分两档：`INNER`（内转角/隔断，可能合法）/ 其余视为错位。
##
## 用法：
##   SS2_ROOM=room_08 godot --headless --path . res://tests/verification/probe_room_wall_audit.tscn
##   SS2_ROOM=room_01 godot --headless --path . res://tests/verification/probe_room_wall_audit.tscn
##   SS2_ROOM=room_04 ...（同房型 u_turn，另一个对照组）

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
## 超过这个偏移就点名（正常值 0.00 ~ 0.15：半墙厚）。
const MISPLACED_TOLERANCE_M := 0.30
## 覆盖统计的分格宽度。
const BIN_M := 0.5
## 判定「这是墙」的最小高度 —— 家具/管件都比它矮。
const MIN_WALL_HEIGHT_M := 2.0
## 判定「这是墙」的最大薄边 —— 更厚的是房间体块不是墙板。
const MAX_WALL_THICKNESS_M := 3.0
## 一件墙至少要沿墙铺这么长才参与覆盖统计（排除立柱式小块）。
const MIN_ALONG_M := 1.0
## 俯视覆盖图的格宽。
const MAP_CELL_M := 2.0
## 覆盖图的向外放宽量（格心采样 → 邻域采样）。
const MAP_DILATE_M := 0.9

var _room: DungeonRoom3D = null


func _ready() -> void:
	var want := OS.get_environment("SS2_ROOM")
	if want.is_empty():
		want = "room_08"
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			for _i in range(6):
				await get_tree().process_frame
			break

	for node in tower.find_children("*", "", true, false):
		if node is DungeonRoom3D and str((node as DungeonRoom3D).room_id) == want:
			_room = node as DungeonRoom3D
			break
	if _room == null:
		print("找不到房间 %s" % want)
		get_tree().quit(1)
		return
	if _room.get("_shell_built") is bool and not bool(_room.get("_shell_built")):
		_room.ensure_shell_built()
		for _i in range(4):
			await get_tree().process_frame

	# SS2_FORCE_ROT：把美术根强转到指定角度再量 —— 用来判定「换个朝向能不能对上」。
	var forced := OS.get_environment("SS2_FORCE_ROT")
	if not forced.is_empty():
		var art := _art_root()
		if art != null:
			art.rotation.y = deg_to_rad(float(forced))
			for _i in range(3):
				await get_tree().process_frame
			print("  [强制] 美术根已转到 %s°" % forced)

	_audit(want)
	print("")
	print("ROOM_WALL_AUDIT_END")
	get_tree().quit(0)


func _art_root() -> Node3D:
	for child in _room.get_children():
		if child is Node3D and str(child.name) in ["AuthoredLayoutArtRoot", "SafeRoomArtRoot"]:
			return child as Node3D
	return null


## 三个帧各是什么姿态、美术到底铺在哪 —— 一次打印齐。
## 只报「美术实测足迹」不够：`_align_static_layout_to_room()` 会把**美术根整体转 90°**，
## 转完美术还是 45×40，但已经不在房间帧的方位上了 ⇒ 必须把「根转了没」单独量出来。
func _print_frames(to_local: Transform3D, dims: Vector2) -> void:
	print("")
	print("  ── 帧姿态 ──")
	print("    房间 global：pos=(%.2f, %.2f)  rot=%.1f°  尺寸=%.1fx%.1f" % [
		_room.global_position.x, _room.global_position.z,
		rad_to_deg(_room.global_rotation.y), dims.x, dims.y,
	])
	var art_root: Node3D = null
	for child in _room.get_children():
		if child is Node3D and str(child.name) in ["AuthoredLayoutArtRoot", "SafeRoomArtRoot"]:
			art_root = child as Node3D
			break
	if art_root == null:
		print("    美术根：<未找到>")
		return
	print("    美术根：rot=%.1f°  pos=(%.2f, %.2f, %.2f)" % [
		rad_to_deg(art_root.rotation.y), art_root.position.x, art_root.position.y, art_root.position.z,
	])
	# 美术整体足迹（房间帧）
	var box := AABB()
	var first := true
	for node in _room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or _under_preview_only(mesh):
			continue
		var world := _world_aabb(mesh)
		var local_min := to_local * world.position
		var local_max := to_local * (world.position + world.size)
		var local := AABB(
			Vector3(minf(local_min.x, local_max.x), minf(local_min.y, local_max.y), minf(local_min.z, local_max.z)),
			Vector3(absf(local_max.x - local_min.x), absf(local_max.y - local_min.y), absf(local_max.z - local_min.z))
		)
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	print("    美术足迹（房间帧）：x %.1f~%.1f（%.1f）  z %.1f~%.1f（%.1f）" % [
		box.position.x, box.position.x + box.size.x, box.size.x,
		box.position.z, box.position.z + box.size.z, box.size.z,
	])
	print("    房间边界应占：          x %.1f~%.1f（%.1f）  z %.1f~%.1f（%.1f）" % [
		-dims.x * 0.5, dims.x * 0.5, dims.x, -dims.y * 0.5, dims.y * 0.5, dims.y,
	])


## 门位的**运行时真源**是 `tower_wall_door_offset_<side>`（`_authored_wall_connection_side`
## 与 `_align_static_layout_to_room` 都读它）；`wall_door_lane_<side>` 是程序化壳
## 那条路径的 meta，远征静态布局房上通常是空的（读它会得到 0 ⇒ 把所有缺口都误判成
## 「不是门位」）。两个都读只是兜底，优先前者。
func _door_lanes() -> Dictionary:
	var lanes := {}
	for side in ["north", "south", "east", "west"]:
		if not _room.doors.has(side):
			continue
		lanes[side] = float(_room.get_meta(
			"tower_wall_door_offset_%s" % side,
			_room.get_meta("wall_door_lane_%s" % side, 0.0)
		))
	return lanes


func _audit(want: String) -> void:
	var dims := _room.get_dimensions()
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var to_local := _room.global_transform.affine_inverse()
	var layout_delta := float(_room.get_meta("template_rotation_deg", 0.0))
	print("")
	print("=== 墙件审计  room=%s  尺寸=%.1fx%.1f  rot=%.1f°  template_rotation=%.1f°  doors=%s ===" % [
		want, dims.x, dims.y, rad_to_deg(_room.global_rotation.y), layout_delta, str(_room.doors),
	])
	print("  口径：把每件「实例」下所有可见网格合并成一个 AABB，再折算进房间帧")
	print("        偏移 = 该件中心离它所在那一面边界的米数（正 = 往外，负 = 往里）")
	_print_frames(to_local, dims)

	var pieces := _collect_pieces(to_local)
	if pieces.is_empty():
		print("  （一件墙都没量到 —— 房间可能还没建壳）")
		return

	print("")
	print("  %-46s %-3s %-6s %8s %8s %8s" % ["件名", "走向", "所在面", "偏移m", "沿墙起", "沿墙止"])
	for piece in pieces:
		var mark := ""
		if absf(float(piece["offset"])) > MISPLACED_TOLERANCE_M:
			mark = "  ← 内缩 %.2f m" % absf(float(piece["offset"]))
		print("  %-46s %-3s %-6s %+8.2f %8.1f %8.1f%s" % [
			str(piece["name"]), str(piece["axis"]), str(piece["side"]),
			float(piece["offset"]), float(piece["along_min"]), float(piece["along_max"]), mark,
		])

	print("")
	for side in ["north", "south", "east", "west"]:
		_print_coverage(side, pieces, dims)

	# 边界墙 = 贴边（|offset| ≤ 容差）；其余都是**内墙**（L 型内转角 / 隔断）。
	var on_boundary := 0
	var inner: Array[String] = []
	for piece in pieces:
		if absf(float(piece["offset"])) <= MISPLACED_TOLERANCE_M:
			on_boundary += 1
			continue
		inner.append("%s（%s 面，内缩 %.2f m，沿墙 %.1f~%.1f）" % [
			str(piece["name"]), str(piece["side"]),
			absf(float(piece["offset"])),
			float(piece["along_min"]), float(piece["along_max"]),
		])
	print("")
	print("  边界墙 %d 件；内墙（不在矩形边界上）%d 件" % [on_boundary, inner.size()])
	for line in inner:
		print("     · %s" % line)

	_print_ascii_map(dims, to_local)
	_print_vertical(to_local)
	_print_suspects(dims, to_local)
	_print_door_accounting(dims)
	_maybe_dump(want, dims, pieces)


## 立面：每件墙的 Y 区间（底面 / 顶面）与厚度。
##
## 平面位置全对、业主仍说「一边墙错位」时，剩下的那一维就是**高度**：
## 一件墙如果比其他墙矮半截、或者底面离开地面悬在半空，俯视图完全看不出来，
## 但站在房里一眼就能看到「那一面墙和别人不一样」。
func _print_vertical(to_local: Transform3D) -> void:
	var art := _art_root()
	if art == null:
		return
	print("")
	print("  ── 立面（底面 / 顶面 / 厚度）──")
	var rows: Array[Dictionary] = []
	for node in art.find_children("*", "", true, false):
		var node3d := node as Node3D
		if node3d == null or not str(node3d.name).to_upper().contains("WALL"):
			continue
		if node3d.get_parent() != art:
			continue
		var box := _world_aabb_of(node3d)
		if box.size.y < 0.5:
			continue
		var base_y := box.position.y - art.global_position.y
		var top_y := box.position.y + box.size.y - art.global_position.y
		rows.append({
			"name": str(node3d.name),
			"base": base_y,
			"top": top_y,
			"thick": minf(box.size.x, box.size.z),
		})
	if rows.is_empty():
		print("    （没量到墙）")
		return
	var tops: Array[float] = []
	var bases: Array[float] = []
	for row in rows:
		tops.append(float(row["top"]))
		bases.append(float(row["base"]))
	tops.sort()
	bases.sort()
	var median_top := tops[tops.size() / 2]
	var median_base := bases[bases.size() / 2]
	print("    墙 %d 件｜顶面中位 %.2f m｜底面中位 %.2f m" % [rows.size(), median_top, median_base])
	var odd: Array[String] = []
	for row in rows:
		if absf(float(row["top"]) - median_top) > 0.25 or absf(float(row["base"]) - median_base) > 0.25:
			odd.append("%s 底面 %+.2f 顶面 %+.2f 厚 %.2f" % [
				str(row["name"]), float(row["base"]), float(row["top"]), float(row["thick"]),
			])
	if odd.is_empty():
		print("    ✅ 所有墙高度一致（无悬空/矮墙）")
	else:
		print("    🔴 高度与同房其他墙不一致 %d 件：" % odd.size())
		for line in odd:
			print("      · %s" % line)


func _world_aabb_of(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree():
			continue
		var world := _world_aabb(mesh)
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
	return box



## 逐件墙体的**双帧坐标**：美术帧（TSCN 原始 `position`，未经对齐旋转）× 房间帧（实测）。
##
## 为什么需要双帧：`_align_static_layout_to_room()` 会把美术根整体转 90° 整数倍。
## 只看房间帧，一件「没跟着转的墙」和一件「本来就该在那儿的墙」长得一样；
## 把两帧并排摆出来，`(房间帧) ≠ R(delta) · (美术帧)` 的件就是没归位的件。
func _print_suspects(dims: Vector2, to_local: Transform3D) -> void:
	var art := _art_root()
	if art == null:
		return
	print("")
	print("  ── 双帧坐标（美术帧 = TSCN 原始位置；房间帧 = 实测）──")
	var bad: Array[String] = []
	for node in art.find_children("*", "", true, false):
		var node3d := node as Node3D
		if node3d == null or not str(node3d.name).to_upper().contains("WALL"):
			continue
		if node3d.get_parent() != art:
			continue
		var art_pos := node3d.position
		var room_pos := to_local * node3d.global_position
		# 期望：房间帧 = R(art 根转角) · 美术帧
		var expected := Basis(Vector3.UP, art.rotation.y) * art_pos
		var drift := Vector2(room_pos.x - expected.x, room_pos.z - expected.z).length()
		if drift > 0.35:
			bad.append("%s 美术帧 (%.1f, %.1f) → 期望 (%.1f, %.1f) 实测 (%.1f, %.1f) 偏 %.2f m" % [
				str(node3d.name), art_pos.x, art_pos.z,
				expected.x, expected.z, room_pos.x, room_pos.z, drift,
			])
	if bad.is_empty():
		print("    全部墙件都跟着美术根一起转了（无未归位件）")
	else:
		print("    🔴 有 %d 件没跟着美术根走：" % bad.size())
		for line in bad:
			print("      · %s" % line)



## 门墙件的账：本房只有**一件**带门洞的墙件（`_is_door_wall_piece`），
## 门却有两扇（与父房共享的那扇由父端提供）。运行时 `_rehome_static_layout_door()`
## 会把它搬到自持侧，原位由 `_backfill_rehomed_door_spot()` 补一段同侧实墙。
##   只报三件事：门墙件现在在哪、原位有没有补上、每扇门的 lane 处是不是通透的。
func _print_door_accounting(dims: Vector2) -> void:
	print("")
	print("  ── 门墙件账 ──")
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var door_pieces: Array[String] = []
	var fills: Array[String] = []
	for node in _room.find_children("*", "", true, false):
		var node3d := node as Node3D
		if node3d == null:
			continue
		var path := node3d.scene_file_path
		if path.contains("wall_door") or path.contains("door_wall"):
			var local := _room.global_transform.affine_inverse() * node3d.global_position
			var piece_side := _declared_side(node3d)
			door_pieces.append("%s 自称=%s @ (%.1f, %.1f)" % [
				str(node3d.name), piece_side if not piece_side.is_empty() else "—", local.x, local.z,
			])
		if str(node3d.name).contains("RehomeFill"):
			var local := _room.global_transform.affine_inverse() * node3d.global_position
			fills.append("%s @ (%.1f, %.1f)" % [str(node3d.name), local.x, local.z])
	for line in door_pieces:
		print("    门墙件：%s" % line)
	if door_pieces.is_empty():
		print("    门墙件：<一件都没有 —— 有一扇门没有墙框>")
	for line in fills:
		print("    搬走后补墙：%s" % line)
	if fills.is_empty():
		print("    搬走后补墙：<没有>")
	for side in ["north", "south", "east", "west"]:
		if not _room.doors.has(side):
			continue
		var lane := float(_room.get_meta(
			"tower_wall_door_offset_%s" % side,
			_room.get_meta("wall_door_lane_%s" % side, 0.0)
		))
		var owner := "自持" if _room.owns_door_endpoint(side) else "委派给对面"
		var target := str(_room.door_targets.get(side, ""))
		print("    门 %-5s lane=%+6.1f  %s  → %s" % [
			side, lane, owner, target if not target.is_empty() else "（死口）",
		])
	# 门墙件（唯一一件）应当落在**本房自持**的那扇门上。
	var piece_side := ""
	for node in _room.find_children("*", "", true, false):
		var node3d := node as Node3D
		if node3d == null or node3d.get_parent() == null:
			continue
		if not DungeonRoom3D._is_door_wall_piece(node3d):
			continue
		piece_side = _room._authored_wall_side_from_position(
			_room.global_transform.affine_inverse() * node3d.global_position, dims * 0.5
		)
		break
	if piece_side.is_empty():
		print("    🔴 本房没有门墙件（门框那 5m 墙）")
	elif _room.owns_door_endpoint(piece_side):
		print("    ✅ 门墙件在 %s 门上（本房自持，位置正确）" % piece_side)
	else:
		print("    🔴 门墙件在 %s 门上 —— 那是**对面板**负责的门，应在本房自持的那扇门上" % piece_side)



## `SS2_DUMP=<绝对路径>` 时把墙段导出成 JSON，供 `scripts/plot_room_wall_overlay.py`
## 画「设计轮廓 vs 实测墙位」对照图。探针只负责量，画图不在这里做。
func _maybe_dump(want: String, dims: Vector2, pieces: Array[Dictionary]) -> void:
	var path := OS.get_environment("SS2_DUMP")
	if path.is_empty():
		return
	var rows: Array = []
	for piece in pieces:
		rows.append({
			"name": str(piece["name"]),
			"side": str(piece["side"]),
			"axis": str(piece["axis"]),
			"offset": float(piece["offset"]),
			"along_min": float(piece["along_min"]),
			"along_max": float(piece["along_max"]),
		})
	var floors: Array = []
	for node in _room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or _under_preview_only(mesh):
			continue
		var upper := str(_instance_root(mesh).name).to_upper()
		if not (upper.contains("TILE") or upper.contains("FLOOR")):
			continue
		var world := _world_aabb(mesh)
		var local_min := _room.global_transform.affine_inverse() * world.position
		var local_max := _room.global_transform.affine_inverse() * (world.position + world.size)
		floors.append({
			"x_min": minf(local_min.x, local_max.x),
			"x_max": maxf(local_min.x, local_max.x),
			"z_min": minf(local_min.z, local_max.z),
			"z_max": maxf(local_min.z, local_max.z),
		})
	var art := _art_root()
	var payload := {
		"room": want,
		"dims": [dims.x, dims.y],
		"art_rotation_deg": rad_to_deg(art.rotation.y) if art != null else 0.0,
		"template_rotation_deg": float(_room.get_meta("template_rotation_deg", 0.0)),
		"doors": _room.doors.duplicate(),
		"door_lanes": _door_lanes(),
		"pieces": rows,
		"floors": floors,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("  [导出失败] %s" % path)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("  [导出] %s" % path)


## 按「实例根」聚合：一个 MeshInstance3D 往上走到「父节点是房间或布局根」为止，
## 那一层才是美术布局里的一件东西（墙 / 家具 / 灯）。
func _collect_pieces(to_local: Transform3D) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for node in _room.find_children("*", "", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or _under_preview_only(mesh):
			continue
		var top := _instance_root(mesh)
		var key := top.get_instance_id()
		var box: AABB = _world_aabb(mesh)
		if groups.has(key):
			var existing: AABB = groups[key]["box"] as AABB
			groups[key]["box"] = existing.merge(box)
		else:
			groups[key] = {"node": top, "box": box}

	var dims := _room.get_dimensions()
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var pieces: Array[Dictionary] = []
	for key in groups.keys():
		var entry: Dictionary = groups[key]
		var top: Node = entry["node"] as Node
		var box: AABB = entry["box"] as AABB
		# 只认名字里带 WALL 的件 —— 服务器机柜/控制台/吊线也都高过 2 m，
		# 靠尺寸筛不掉，靠命名才筛得掉（布局里墙件一律叫 ...-WALL_<轴>_<序号>...）。
		if not str(top.name).to_upper().contains("WALL"):
			continue
		if box.size.y < MIN_WALL_HEIGHT_M:
			continue
		var thin := minf(box.size.x, box.size.z)
		if thin > MAX_WALL_THICKNESS_M:
			continue
		var center_local := to_local * box.get_center()
		# 薄轴定走向：Z 向薄 ⇒ 沿 X 跑（南/北面）；X 向薄 ⇒ 沿 Z 跑（东/西面）。
		var runs_along_x := box.size.x > box.size.z
		var side := ""
		var offset := 0.0
		var along_min := 0.0
		var along_max := 0.0
		if runs_along_x:
			side = "south" if center_local.z > 0.0 else "north"
			offset = center_local.z - half_z if center_local.z > 0.0 else -(center_local.z + half_z)
			along_min = center_local.x - box.size.x * 0.5
			along_max = center_local.x + box.size.x * 0.5
		else:
			side = "east" if center_local.x > 0.0 else "west"
			offset = center_local.x - half_x if center_local.x > 0.0 else -(center_local.x + half_x)
			along_min = center_local.z - box.size.z * 0.5
			along_max = center_local.z + box.size.z * 0.5
		if along_max - along_min < MIN_ALONG_M:
			continue
		pieces.append({
			"name": str(top.name),
			"declared": _declared_side(top),
			"side": side,
			"axis": "X" if runs_along_x else "Z",
			"offset": offset,
			"center": center_local,
			"size": box.size,
			"along_min": along_min,
			"along_max": along_max,
		})
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := "%s/%s" % [str(a["side"]), str(a["axis"])]
		var sb := "%s/%s" % [str(b["side"]), str(b["axis"])]
		if sa != sb:
			return sa < sb
		var oa := float(a["offset"])
		var ob := float(b["offset"])
		if absf(oa - ob) > 0.05:
			return oa < ob
		return float(a["along_min"]) < float(b["along_min"])
	)
	return pieces


## 俯视 ASCII 图：墙 / 地板覆盖一眼看清房间到底是「哪种 L」。
##   `#` = 这一格被墙件压住   `+` = 只有地板   `.` = 都没有（虚空/凹口）
## 北在上、东在右，格宽 `MAP_CELL_M`。
func _print_ascii_map(dims: Vector2, to_local: Transform3D) -> void:
	var wall_boxes: Array[AABB] = []
	var floor_boxes: Array[AABB] = []
	for node in _room.find_children("*", "", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or _under_preview_only(mesh):
			continue
		var upper := str(_instance_root(mesh).name).to_upper()
		var is_wall := upper.contains("WALL")
		var is_floor := upper.contains("TILE") or upper.contains("FLOOR")
		if not is_wall and not is_floor:
			continue
		var world := _world_aabb(mesh)
		var local_min := to_local * world.position
		var local_max := to_local * (world.position + world.size)
		var box := AABB(
			Vector3(minf(local_min.x, local_max.x), 0.0, minf(local_min.z, local_max.z)),
			Vector3(absf(local_max.x - local_min.x), 1.0, absf(local_max.z - local_min.z))
		)
		# 采样点落在格心，而墙常常**贴边压在边界上**（半墙厚在界外），点采样会整排漏掉。
		# 按 `MAP_DILATE_M` 向外放宽，让「墙在不在这一格」变成「墙有没有进入这一格附近」。
		box = box.grow(MAP_DILATE_M)
		if is_wall:
			wall_boxes.append(box)
		else:
			floor_boxes.append(box)

	var columns := int(ceil(dims.x / MAP_CELL_M))
	var rows := int(ceil(dims.y / MAP_CELL_M))
	print("")
	print("  俯视覆盖图（%d×%.0f m，格宽 %.1f m；# 墙  + 只有地板  . 都没有）" % [
		columns, dims.y, MAP_CELL_M,
	])
	print("       西 " + " ".repeat(maxi(0, columns - 3)) + " 东")
	for row in range(rows):
		var z := -dims.y * 0.5 + (float(row) + 0.5) * MAP_CELL_M
		var line := ""
		for column in range(columns):
			var x := -dims.x * 0.5 + (float(column) + 0.5) * MAP_CELL_M
			var point := AABB(Vector3(x - 0.05, 0.0, z - 0.05), Vector3(0.1, 1.0, 0.1))
			if _any_overlap(wall_boxes, point):
				line += "#"
			elif _any_overlap(floor_boxes, point):
				line += "+"
			else:
				line += "."
		print("        %s" % line)


func _any_overlap(boxes: Array[AABB], point: AABB) -> bool:
	for box in boxes:
		if box.intersects(point):
			return true
	return false


## L 形（`l_turn`）/ 凹字形（`u_turn`）这类**非矩形房**的凹口矩形（房间帧）。
##
## 为什么必须有这个：探针按**包围盒**四条边统计覆盖，凹口那两面本来就没有墙
## （那里是房间外），于是会报出「south −22.5~7.5 不是门位 ⇒ 实墙该在而没有」这种假警报。
## 凹口的边界由**内墙线**给出 —— 内墙（`|offset| > 1`）正是设计里围出凹口的那两排墙，
## 它们的垂距就是凹口的内缩量。取「离边界最近的那道内墙」，凹口 = 该内墙到该角。
func _alcove_rects(dims: Vector2, pieces: Array[Dictionary]) -> Array[AABB]:
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var inset_x := 0.0
	var inset_z := 0.0
	for piece in pieces:
		var offset := absf(float(piece["offset"]))
		if offset <= 1.0:
			continue
		if str(piece["axis"]) == "Z" and (inset_x <= 0.0 or offset < inset_x):
			inset_x = offset
		elif str(piece["axis"]) == "X" and (inset_z <= 0.0 or offset < inset_z):
			inset_z = offset
	if inset_x <= 0.0 or inset_z <= 0.0:
		return []
	# 凹口占掉的那个角：看内墙落在哪一侧（`side` 已是「离它最近的那面」）。
	# ⚠️ 迭代变量必须显式标 `: float` —— 否则 `sign_x * half_x` 是 Variant，
	# `:=` 推不出类型，整个脚本解析失败。
	var rects: Array[AABB] = []
	var signs: Array[float] = [1.0, -1.0]
	for sign_x in signs:
		for sign_z in signs:
			var x_edge: float = sign_x * half_x
			var z_edge: float = sign_z * half_z
			var inner_x: float = x_edge - sign_x * inset_x
			var inner_z: float = z_edge - sign_z * inset_z
			var has_v := false
			var has_h := false
			for piece in pieces:
				if absf(absf(float(piece["offset"])) - inset_x) > 0.3:
					continue
				if str(piece["axis"]) != "Z":
					continue
				var along := (float(piece["along_min"]) + float(piece["along_max"])) * 0.5
				if sign_z > 0.0 and along > inner_z - 0.6:
					has_v = true
				elif sign_z < 0.0 and along < inner_z + 0.6:
					has_v = true
			for piece in pieces:
				if absf(absf(float(piece["offset"])) - inset_z) > 0.3:
					continue
				if str(piece["axis"]) != "X":
					continue
				var along := (float(piece["along_min"]) + float(piece["along_max"])) * 0.5
				if sign_x > 0.0 and along > inner_x - 0.6:
					has_h = true
				elif sign_x < 0.0 and along < inner_x + 0.6:
					has_h = true
			if not (has_v and has_h):
				continue
			var lo_x := minf(inner_x, x_edge)
			var hi_x := maxf(inner_x, x_edge)
			var lo_z := minf(inner_z, z_edge)
			var hi_z := maxf(inner_z, z_edge)
			rects.append(AABB(
				Vector3(lo_x, 0.0, lo_z), Vector3(hi_x - lo_x, 1.0, hi_z - lo_z)
			))
	return rects


## 这个采样点是不是落在凹口（房间外）里。
## ⚠️ GDScript **没有反斜杠续行** —— 长条件一律用括号包起来跨行。
## 写成 `... \` 会让整个脚本解析失败，而场景根仍是裸 Node3D ⇒ `_ready` 不存在
## ⇒ 探针不跑也不退出，看起来像「卡死」（实测白等 6 分钟）。
func _in_alcove(rects: Array[AABB], point_x: float, point_z: float) -> bool:
	for rect in rects:
		var inside_x := (
			point_x >= rect.position.x - 0.2
			and point_x <= rect.position.x + rect.size.x + 0.2
		)
		var inside_z := (
			point_z >= rect.position.z - 0.2
			and point_z <= rect.position.z + rect.size.z + 0.2
		)
		if inside_x and inside_z:
			return true
	return false


## 只统计**贴边**的墙（|偏移| ≤ 容差）。内转角墙和内墙不参与边界覆盖 ——
## 它们本来就不盖边界，混进来会把「缺口」抹平，正好盖住要找的那个洞。
func _print_coverage(side: String, pieces: Array[Dictionary], dims: Vector2) -> void:
	var alcoves := _alcove_rects(dims, pieces)
	var span := dims.x if (side == "north" or side == "south") else dims.y
	var count := maxi(1, int(round(span / BIN_M)))
	var covered: Array[bool] = []
	covered.resize(count)
	covered.fill(false)
	var on_side := 0
	var skipped := 0
	for piece in pieces:
		if str(piece["side"]) != side:
			continue
		if absf(float(piece["offset"])) > MISPLACED_TOLERANCE_M:
			skipped += 1
			continue
		on_side += 1
		var from := int(floor((float(piece["along_min"]) + span * 0.5) / BIN_M))
		var to := int(ceil((float(piece["along_max"]) + span * 0.5) / BIN_M))
		for index in range(maxi(0, from), mini(count, to)):
			covered[index] = true
	var line := ""
	var gap_ranges: Array = []
	var run_start := -1
	for index in range(count):
		if covered[index]:
			line += "#"
			if run_start >= 0:
				gap_ranges.append(_bin_range(run_start, index, span))
				run_start = -1
		else:
			line += "."
			if run_start < 0:
				run_start = index
	if run_start >= 0:
		gap_ranges.append(_bin_range(run_start, count, span))
	var missing := 0
	for value in covered:
		if not value:
			missing += 1
	print("  %-5s 贴边墙 %d 件（另有 %d 件内墙不计入）覆盖 %5.1f/%.1f m" % [
		side, on_side, skipped, (count - missing) * BIN_M, span,
	])
	print("        %s" % line)
	if not gap_ranges.is_empty():
		var texts: Array[String] = []
		for gap in gap_ranges:
			texts.append("%.1f~%.1f（%.1f m）" % [float(gap[0]), float(gap[1]), float(gap[1]) - float(gap[0])])
		print("        缺口：%s" % "、".join(texts))
		# 缺口是不是「本局活门」？门位 lane 处本来就不该有实墙，压门的缺口不算缺。
		# 门位的**运行时真源**是 `tower_wall_door_offset_<side>`（`_authored_wall_connection_side`
		# 与 `_align_static_layout_to_room` 都读它）；`wall_door_lane_<side>` 是程序化壳
		# 那条路径的 meta，远征静态布局房上通常是空的（读它会得到 0 ⇒ 把所有缺口都误判成
		# 「不是门位」）。两个都读只是兜底，优先前者。
		var door_lane := float(_room.get_meta(
			"tower_wall_door_offset_%s" % side,
			_room.get_meta("wall_door_lane_%s" % side, 0.0)
		))
		var has_door := _room.doors.has(side)
		var half_x := dims.x * 0.5
		var half_z := dims.y * 0.5
		for gap in gap_ranges:
			var from_value := float(gap[0])
			var to_value := float(gap[1])
			if to_value - from_value < 0.05:
				continue
			# 凹口（房间外）那一段本来就没有墙，不算缺口。
			var mid := (from_value + to_value) * 0.5
			var probe_x := mid if (side == "north" or side == "south") else (
				half_x if side == "east" else -half_x
			)
			var probe_z := mid if (side == "east" or side == "west") else (
				half_z if side == "south" else -half_z
			)
			if _in_alcove(alcoves, probe_x, probe_z):
				print("          · %.1f~%.1f 落在 L 形凹口（房间外）⇒ 这里本来就没有墙" % [
					from_value, to_value,
				])
			elif has_door and door_lane >= from_value - 1.2 and door_lane <= to_value + 1.2:
				print("          · %.1f~%.1f 盖住本局 %s 门（lane %.1f）⇒ 门洞，合理" % [
					from_value, to_value, side, door_lane,
				])
			else:
				print("          · %.1f~%.1f **不是门位、也不在凹口** ⇒ 实墙该在而没有" % [
					from_value, to_value,
				])


func _bin_range(from_bin: int, to_bin: int, span: float) -> Array:
	return [float(from_bin) * BIN_M - span * 0.5, float(to_bin) * BIN_M - span * 0.5]


func _instance_root(mesh: Node) -> Node:
	var cursor: Node = mesh
	while true:
		var parent := cursor.get_parent()
		if parent == null or parent == _room:
			return cursor
		if parent.get_parent() == _room or parent.get_parent() == null:
			return cursor
		cursor = parent
	return cursor


func _world_aabb(mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	var xform := mesh.global_transform
	var box := AABB(xform * local.position, Vector3.ZERO)
	var first := true
	for index in range(8):
		var corner := local.position + Vector3(
			local.size.x if (index & 1) else 0.0,
			local.size.y if (index & 2) else 0.0,
			local.size.z if (index & 4) else 0.0,
		)
		var point := xform * corner
		if first:
			box = AABB(point, Vector3.ZERO)
			first = false
		else:
			box = box.expand(point)
	return box


func _declared_side(node: Node) -> String:
	var cursor: Node = node
	while cursor != null and cursor != _room:
		if cursor.has_meta("tower_wall_direction"):
			return str(cursor.get_meta("tower_wall_direction"))
		cursor = cursor.get_parent()
	return ""


func _under_preview_only(node: Node) -> bool:
	var cursor: Node = node
	while cursor != null and cursor != _room:
		if cursor.has_meta("editor_preview_only"):
			return true
		var spatial := cursor as Node3D
		if spatial != null and not spatial.visible:
			return true
		cursor = cursor.get_parent()
	return false
