extends Node

## 枚举探针：把远征01 **每一间房**上「可以布暗门的位置」全过一遍，
## 输出可行/不可行的槽位清单，并给出不可行原因。
##
## 为什么不能静态算：运行时房位由 `FloorPlanGenerator` 重排、房间还会被转姿态，
## 设计源的 `center_m` / `connection_ports` 都不是最终答案。所以本探针一律用
## **运行时房间节点的本地系**表达 (wall, lane)，世界坐标由 `to_global` 现算。
##
## 判据（三条全过才算「可布」）：
##   1. 槽位在模板 `wall_lane_table` 里（合法门洞位置，含门板半宽出界检查）；
##   2. 与场上任一主路门扇（`Door_*`）水平距离 ≥ MIN_GAP_M —— 不堵路、不重叠；
##   3. 朝外 0.5 / 1.5 / 3.0m 三个探针都不落进**别的房间**内部 —— 是真外墙。
##
## 用法：bash scripts/run_verification_suite.sh scene probe_secret_site_candidates
## 输出：SECRET_SITE_CANDIDATE_PROBE_OK（只出数，不判红绿）。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const FLOOR_PATH := "res://data/level_plans/expedition_01/floors/floor_00.json"
## 多跑几个种子：固定槽位的意义就是「换布局也不撞」，候选集应当跨种子一致。
const SEEDS := [77001199, 20261018, 1234]

## 门板 2.2m 宽；两块门状物件中心距 < 2.3m 就会重叠。
const MIN_GAP_M := 2.3
## 朝外净空探针深度。
const PROBE_DEPTHS := [0.5, 1.5, 3.0]

var _doors: Array = []
var _sites: Array = []
var _rooms: Dictionary = {}
var _template_of: Dictionary = {}
## room_id -> 运行时 `rotation_deg`（模板旋转 + 整层旋转 + 端口对接链带来的旋转）。
## 90/180/270 都会出现：房间会被端口对接链整体转向，不只是 0/180。
var _rotation_of: Dictionary = {}


func _ready() -> void:
	_load_templates()
	var runs: Array = []
	for seed_value in SEEDS:
		var result := await _probe_seed(int(seed_value))
		if not result.is_empty():
			runs.append(result)
	if runs.is_empty():
		print("SECRET_SITE_CANDIDATE_PROBE_MISS 所有种子都没跑起来")
		get_tree().quit(0)
		return

	_report_detail(runs[0])
	_report_cross_seed(runs)
	get_tree().quit(0)


## 只读房间 → 模板 id 的映射（用于过滤子图房、并在输出里标模板名）。
## lane 不从这里取 —— 见 `_scan_room` 的说明。
func _load_templates() -> void:
	var raw := FileAccess.get_file_as_string(FLOOR_PATH)
	if raw.is_empty():
		push_error("[probe] 读不到 %s" % FLOOR_PATH)
		return
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		push_error("[probe] %s 不是合法 JSON" % FLOOR_PATH)
		return
	for value in (data as Dictionary).get("rooms", []) as Array:
		var record := value as Dictionary
		_template_of[str(record.get("key", ""))] = str(record.get("template_id", ""))


func _probe_seed(seed_value: int) -> Dictionary:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		print("[probe] 远征场景加载失败 seed=%d" % seed_value)
		return {}
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		print("[probe] 远征场景实例化失败 seed=%d" % seed_value)
		return {}
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_doors = []
	_sites = []
	_rooms = {}
	_rotation_of = {}
	_collect(tower)
	var records: Variant = tower.get("_records")
	if records is Array:
		for value in records as Array:
			var record := value as Dictionary
			_rotation_of[str(record.get("id", ""))] = float(record.get("rotation_deg", 0.0))

	var rows: Array = []
	for room_id in _rooms.keys():
		# 只扫本层设计源声明的房间。子图房（`secret_*`）也在树里，但它们不是
		# 「可以在哪里布暗门」的候选，混进来会虚增房间数并污染朝外探针。
		if not _template_of.has(str(room_id)):
			continue
		var room := _rooms[room_id] as Node3D
		if room == null:
			continue
		rows.append(_scan_room(str(room_id), room))
	rows.sort_custom(func(a, b): return str((a as Dictionary).get("room_id", "")) < str((b as Dictionary).get("room_id", "")))

	var result := {
		"seed": seed_value,
		"rows": rows,
		"door_count": _doors.size(),
		"sites": _sites.duplicate(),
		"site_audit": _audit_sites(rows),
	}
	if seed_value == int(SEEDS[0]):
		_dump_records(tower)
	tower.queue_free()
	await get_tree().process_frame
	return result


func _collect(root: Node) -> void:
	for child in root.get_children():
		var node := child as Node
		if node == null:
			continue
		var name_text := str(node.name)
		if name_text.begins_with("SecretDoor_"):
			var site_pos := (node as Node3D).global_position if node is Node3D else Vector3.ZERO
			# 子图整体偏 +1000m，它的门也叫 `SecretDoor_*`；只留主图上的。
			if absf(site_pos.x) < 900.0:
				_sites.append({"name": name_text, "pos": site_pos})
		elif name_text.begins_with("Door_"):
			_doors.append({
				"name": name_text,
				"pos": (node as Node3D).global_position if node is Node3D else Vector3.ZERO,
				"parent": str(node.get_parent().name if node.get_parent() else "?"),
			})
		elif node.get("room_id") != null:
			var room_key := str(node.get("room_id"))
			# `entry` 房的 `room_id` 可能是默认值（`room_00`），按节点名兜底，
			# 否则 13 间里会少统计一间。
			if not _template_of.has(room_key) and _template_of.has(name_text):
				room_key = name_text
			_rooms[room_key] = node
		_collect(node)


## 打印房间记录的旋转与尺寸：这是「墙的语义到底以谁为准」的唯一证据。
## `rotation_deg` = 模板旋转 + 整层旋转 + 端口对接链带来的追加旋转（若有）。
## `secret_site` 是内存里**已被 FloorPlanGenerator 旋转过**的声明。
func _dump_records(tower: Node) -> void:
	var records: Variant = tower.get("_records")
	if not (records is Array):
		return
	print("")
	print("=== 房间记录（rotation_deg / custom_dimensions / secret_site）===")
	for value in records as Array:
		var record := value as Dictionary
		var room_key := str(record.get("id", ""))
		if not _template_of.has(room_key):
			continue
		var site := record.get("secret_site", {}) as Dictionary
		var site_text := "无"
		if not site.is_empty():
			site_text = "%s%+.1f" % [str(site.get("wall", "")), float(site.get("lane", 0.0))]
		print("  %-9s rotation=%6.1f° dims=%-12s site=%s" % [
			room_key,
			float(record.get("rotation_deg", 0.0)),
			str(record.get("custom_dimensions", Vector2.ZERO)),
			site_text,
		])


## 扫一间房：按**运行时墙长**枚举 lane，逐个过判据。
##
## lane 规则与模板 `wall_lane_table` 同源，公式是 `±(墙半长 - 7.5)`、步长 5m
## （八份模板逐值验证过：corridor 45→±15、db 40→±12.5、bridge 60→±22.5、
## boss_deep 100→±42.5、safe 15→0）。用公式而不是照抄模板，是因为运行时房间会被
## **转置**（room_01 写 45×40、实机 40×45），模板的 lane 值是旧尺寸下的数，
## 直接套会算到墙外或错位。
func _scan_room(room_id: String, room: Node3D) -> Dictionary:
	var dims: Vector2 = room.call("get_dimensions")
	var half := dims * 0.5
	var template_id := str(_template_of.get(room_id, ""))
	var rotation := float(_rotation_of.get(room_id, 0.0))
	var occupied: Array = _occupied_slots(room, half, rotation)
	var accepted: Array = []
	var rejected: Array = []
	for wall in ["north", "south", "east", "west"]:
		var half_along := half.x if wall == "north" or wall == "south" else half.y
		for lane_value in _lane_grid(half_along):
			var lane := float(lane_value)
			var world := room.to_global(_local_on_wall(wall, lane, half))
			var normal_local := _wall_normal(wall)
			var normal_world := (room.global_transform.basis * normal_local).normalized()
			normal_world.y = 0.0
			normal_world = normal_world.normalized()

			# 判据 2：不压主路门洞。
			var nearest := _nearest_door(world)
			var door_gap := float(nearest.get("dist", INF))
			if door_gap < MIN_GAP_M:
				rejected.append({
					"wall": wall, "lane": lane, "reason": "door",
					"authored": _to_authored(wall, lane, rotation),
					"why": "压主路门 %s（%.2fm）" % [str(nearest.get("name", "?")), door_gap],
				})
				continue

			# 判据 3：朝外是真外墙。
			var blocked := _outward_blocker(room_id, world, normal_world)
			if not blocked.is_empty():
				rejected.append({
					"wall": wall, "lane": lane, "reason": "neighbor",
					"authored": _to_authored(wall, lane, rotation),
					"why": "朝外 %.1fm 撞进 %s" % [
						float(blocked.get("depth", 0.0)), str(blocked.get("room", "?")),
					],
				})
				continue

			accepted.append({
				"wall": wall, "lane": lane,
				"authored": _to_authored(wall, lane, rotation),
				"world": world,
				"door_gap": door_gap,
				"nearest_door": str(nearest.get("name", "")),
				"clear": _clearance(room_id, world, normal_world),
			})

	return {
		"room_id": room_id,
		"template": template_id,
		"type": str(room.get("room_type")),
		"main": bool(room.get("is_main_path")),
		"dims": dims,
		"yaw_deg": rad_to_deg(room.global_rotation.y),
		"center": room.global_position,
		"node": room,
		"doors": occupied,
		"accepted": accepted,
		"rejected": rejected,
	}


## 这间房墙上**实际**被主路门占掉的槽（按门扇世界位置反推本地系 wall/lane）。
func _occupied_slots(room: Node3D, half: Vector2, rotation_deg: float) -> Array:
	var out: Array = []
	for value in _doors:
		var row := value as Dictionary
		var world := row.get("pos", Vector3.ZERO) as Vector3
		var local := room.to_local(world)
		if absf(local.y) > 8.0:
			continue
		var wall := ""
		var lane := 0.0
		if absf(local.x + half.x) <= 0.8:
			wall = "west"
			lane = local.z
		elif absf(local.x - half.x) <= 0.8:
			wall = "east"
			lane = local.z
		elif absf(local.z + half.y) <= 0.8:
			wall = "north"
			lane = local.x
		elif absf(local.z - half.y) <= 0.8:
			wall = "south"
			lane = local.x
		if wall.is_empty():
			continue
		var half_along := half.x if wall == "north" or wall == "south" else half.y
		if absf(lane) > half_along + 0.2:
			continue
		out.append({
			"wall": wall,
			"lane": snappedf(lane, 0.1),
			"authored": _to_authored(wall, lane, rotation_deg),
			"name": str(row.get("name", "")),
			"parent": str(row.get("parent", "")),
		})
	return out


func _local_on_wall(wall: String, lane: float, half: Vector2) -> Vector3:
	match wall:
		"north": return Vector3(lane, 0.0, -half.y)
		"south": return Vector3(lane, 0.0, half.y)
		"west": return Vector3(-half.x, 0.0, lane)
		"east": return Vector3(half.x, 0.0, lane)
	return Vector3.ZERO


static func _wall_normal(wall: String) -> Vector3:
	match wall:
		"north": return Vector3(0, 0, -1)
		"south": return Vector3(0, 0, 1)
		"west": return Vector3(-1, 0, 0)
		"east": return Vector3(1, 0, 0)
	return Vector3.ZERO


static func _wall_from_normal(normal: Vector3) -> String:
	if normal.z < -0.5:
		return "north"
	if normal.z > 0.5:
		return "south"
	if normal.x > 0.5:
		return "east"
	if normal.x < -0.5:
		return "west"
	return ""


## 把**运行时槽**反算回**作者系**（设计源里写的那个 wall/lane）。
##
## 为什么要这一步：`record.rotation_deg` 在远征01 是 90/180/270（端口对接链会把房间
## 整体转向），所以同一个作者槽在不同种子/不同对接姿态下，运行时标签完全不同。
## 拿运行时标签跨种子比会得到一堆假波动；只有作者系标签才是「写死一个位置」的坐标系。
static func _to_authored(wall: String, lane: float, rotation_deg: float) -> Array:
	if is_zero_approx(fposmod(rotation_deg, 360.0)):
		return [wall, lane]
	var normal := _wall_normal(wall)
	var tangent := (
		Vector3(1, 0, 0) if wall == "north" or wall == "south" else Vector3(0, 0, 1)
	)
	var back := deg_to_rad(-rotation_deg)
	var authored_wall := _wall_from_normal(normal.rotated(Vector3.UP, back))
	if authored_wall.is_empty():
		return [wall, lane]
	var authored_tangent := tangent.rotated(Vector3.UP, back)
	var base_tangent := (
		Vector3(1, 0, 0)
		if authored_wall == "north" or authored_wall == "south"
		else Vector3(0, 0, 1)
	)
	var sign := 1.0 if authored_tangent.dot(base_tangent) >= 0.0 else -1.0
	var value := lane * sign
	if is_zero_approx(value):
		value = 0.0  # 消掉 `0.0 * -1.0 = -0.0`：负零会当成另一个 key，制造假波动
	return [authored_wall, value]


## 沿墙 lane 网格：`±(墙半长 − 7.5 − 5k)`。
##
## 与八份模板 `wall_lane_table` 逐值同源（safe 15→0、extraction 25→±5、bridge 30→±7.5、
## office/db 40→±12.5、corridor 45→±15、boss 50→±17.5、boss_deep 100→±42.5），
## 但按**运行时**墙长现算 —— 房间会被端口对接链转置，模板里那组数是旧尺寸下的，
## 照抄会落到墙外或与真实门槽错半格。
static func _lane_grid(half_along: float) -> Array:
	var out: Array = []
	var max_lane := half_along - 7.5
	var step := 0
	while max_lane - float(step) * 5.0 >= -0.001:
		var value := max_lane - float(step) * 5.0
		if is_zero_approx(value):
			out.append(0.0)
		else:
			out.append(value)
			out.append(-value)
		step += 1
	out.sort()
	return out


func _nearest_door(world: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for value in _doors:
		var row := value as Dictionary
		var other := row.get("pos", Vector3.ZERO) as Vector3
		var d := Vector2(world.x - other.x, world.z - other.z).length()
		if d < best_dist:
			best_dist = d
			best = row
	if best.is_empty():
		return best
	var copy := best.duplicate()
	copy["dist"] = best_dist
	return copy


## 朝外探针：返回第一个撞进别的房间的深度；干净返回空字典。
func _outward_blocker(self_id: String, world: Vector3, normal: Vector3) -> Dictionary:
	for depth_value in PROBE_DEPTHS:
		var depth := float(depth_value)
		var probe := world + normal * depth
		for room_id in _rooms.keys():
			if str(room_id) == self_id:
				continue
			var other := _rooms[room_id] as Node3D
			if other == null:
				continue
			if _inside_room(other, probe):
				return {"depth": depth, "room": str(room_id)}
	return {}


func _inside_room(room: Node3D, world: Vector3) -> bool:
	var dims: Vector2 = room.call("get_dimensions")
	var local := room.to_local(world)
	return (
		absf(local.x) < dims.x * 0.5 - 0.05
		and absf(local.z) < dims.y * 0.5 - 0.05
	)


## 朝外到底能空多远：返回 3.0 / 1.5 / 0.5 三个档，全通则 3.0。
func _clearance(self_id: String, world: Vector3, normal: Vector3) -> float:
	for depth_value in PROBE_DEPTHS:
		var depth := float(depth_value)
		var probe := world + normal * depth
		for room_id in _rooms.keys():
			if str(room_id) == self_id:
				continue
			var other := _rooms[room_id] as Node3D
			if other == null:
				continue
			if _inside_room(other, probe):
				return maxf(0.0, depth - 0.5)
	return 3.0


## 现有 4 个位点复检：它们落在哪间房的哪个 runtime 槽上，该槽在新口径下是否可布。
## 这一步回答的是「按固定槽位重做之后，原来的四个位置还站不站得住」。
## 世界点 → 该房间的「墙 + 沿墙 lane」。不贴墙或超出墙段长度时返回空。
static func _slot_of(room: Node3D, pos: Vector3) -> Dictionary:
	var dims: Vector2 = room.call("get_dimensions")
	var half := dims * 0.5
	var local := room.to_local(pos)
	var candidates := [
		{"wall": "north", "dist": absf(local.z + half.y), "lane": local.x, "half": half.x},
		{"wall": "south", "dist": absf(local.z - half.y), "lane": local.x, "half": half.x},
		{"wall": "west", "dist": absf(local.x + half.x), "lane": local.z, "half": half.y},
		{"wall": "east", "dist": absf(local.x - half.x), "lane": local.z, "half": half.y},
	]
	var best: Dictionary = {}
	for value in candidates:
		var row := value as Dictionary
		# 沿墙坐标必须落在墙段内 —— 否则这个点只是「和这面墙同一个平面」，
		# 不属于这间房（S3 曾被错归到 room_06 的 west 墙就是因为漏了这一步）。
		if absf(float(row["lane"])) > float(row["half"]) + 0.25:
			continue
		if best.is_empty() or float(row["dist"]) < float(best["dist"]):
			best = row
	if best.is_empty():
		return {}
	if float(best["dist"]) > 0.8:
		return {}
	return {"wall": str(best["wall"]), "lane": float(best["lane"]), "dist": float(best["dist"])}


## 现有 4 个位点复检：它们落在哪间房的哪个槽上，该槽在新口径下是否可布。
func _audit_sites(rows: Array) -> Array:
	var out: Array = []
	for site_value in _sites:
		var site := site_value as Dictionary
		var pos := site.get("pos", Vector3.ZERO) as Vector3
		var best_row: Dictionary = {}
		var best_slot: Dictionary = {}
		var best_dist := INF
		for row_value in rows:
			var row := row_value as Dictionary
			var room := row.get("node") as Node3D
			if room == null:
				continue
			var slot := _slot_of(room, pos)
			if slot.is_empty():
				continue
			if float(slot["dist"]) < best_dist:
				best_dist = float(slot["dist"])
				best_slot = slot
				best_row = row
		if best_row.is_empty():
			out.append({
				"name": str(site.get("name", "")), "room": "?", "wall": "?",
				"lane": 0.0, "ok": false, "verdict": "不贴任何房间的墙",
			})
			continue
		var room_id := str(best_row.get("room_id", ""))
		var wall := str(best_slot["wall"])
		var lane := float(best_slot["lane"])
		var authored := _to_authored(wall, lane, float(_rotation_of.get(room_id, 0.0)))
		var authored_wall := str(authored[0])
		var authored_lane := float(authored[1])
		var ok := false
		var reason := ""
		for slot_value in best_row.get("accepted", []) as Array:
			var slot := slot_value as Dictionary
			var slot_authored: Array = slot.get("authored", [slot.get("wall", ""), slot.get("lane", 0.0)])
			if str(slot_authored[0]) == authored_wall and absf(float(slot_authored[1]) - authored_lane) < 1.2:
				ok = true
				break
		if not ok:
			for slot_value in best_row.get("rejected", []) as Array:
				var slot := slot_value as Dictionary
				var slot_authored: Array = slot.get("authored", [slot.get("wall", ""), slot.get("lane", 0.0)])
				if str(slot_authored[0]) == authored_wall and absf(float(slot_authored[1]) - authored_lane) < 1.2:
					reason = str(slot.get("why", ""))
					break
		var verdict := "可布"
		if not ok:
			verdict = "不可布：%s" % reason if not reason.is_empty() else "不在 5m 槽上"
		out.append({
			"name": str(site.get("name", "")),
			"room": room_id,
			"wall": wall,
			"lane": lane,
			"authored_wall": authored_wall,
			"authored_lane": authored_lane,
			"ok": ok,
			"verdict": verdict,
		})
	return out


func _report_detail(run: Dictionary) -> void:
	print("")
	print("=== 远征01 暗门可选位点枚举 seed=%d（主路门=%d）===" % [
		int(run.get("seed", 0)), int(run.get("door_count", 0)),
	])
	var total_accepted := 0
	var rooms_with_slot := 0
	for value in run.get("rows", []) as Array:
		var row := value as Dictionary
		var accepted: Array = row.get("accepted", []) as Array
		var rejected: Array = row.get("rejected", []) as Array
		total_accepted += accepted.size()
		if not accepted.is_empty():
			rooms_with_slot += 1
		var dims := row.get("dims", Vector2.ZERO) as Vector2
		var center := row.get("center", Vector3.ZERO) as Vector3
		print("")
		print("[%s] 模板=%s 类型=%s 主路=%s 尺寸=%.1f×%.1f 朝向=%.0f° 中心=(%.1f, %.1f)" % [
			str(row.get("room_id", "")), str(row.get("template", "")),
			str(row.get("type", "")), "是" if bool(row.get("main", false)) else "否",
			dims.x, dims.y, float(row.get("yaw_deg", 0.0)), center.x, center.z,
		])
		var doors: Array = row.get("doors", []) as Array
		if doors.is_empty():
			print("   已有门：无")
		else:
			var parts: Array = []
			for door_value in doors:
				var door := door_value as Dictionary
				parts.append("%s%+.1f(%s)" % [
					str(door.get("wall", "")), float(door.get("lane", 0.0)),
					str(door.get("name", "")),
				])
			print("   已有门：%s" % " ".join(parts))
		if accepted.is_empty():
			print("   可布：无")
		else:
			var lines: Array = []
			for slot_value in accepted:
				var slot := slot_value as Dictionary
				var world := slot.get("world", Vector3.ZERO) as Vector3
				lines.append("%s%+.1f → (%.1f, %.1f) 离门 %.1fm 净空 %.1fm" % [
					str(slot.get("wall", "")), float(slot.get("lane", 0.0)),
					world.x, world.z,
					float(slot.get("door_gap", 0.0)), float(slot.get("clear", 0.0)),
				])
			print("   可布 %d 处：" % accepted.size())
			for line in lines:
				print("     %s" % str(line))
		if not rejected.is_empty():
			print("   不可布 %d 处：" % rejected.size())
			for slot_value in rejected:
				var slot := slot_value as Dictionary
				print("     %s%+.1f  ← %s" % [
					str(slot.get("wall", "")), float(slot.get("lane", 0.0)),
					str(slot.get("why", "")),
				])
	print("")
	var audit: Array = run.get("site_audit", []) as Array
	if audit.is_empty():
		print("=== 现有位点复检：本种子没刷出任何暗门 ===")
	else:
		print("=== 现有位点复检（%d 个）===" % audit.size())
		for value in audit:
			var row := value as Dictionary
			print("  %-14s 房间=%-8s 实机=%s%+.1f 作者系=%s%+.1f   %s" % [
				str(row.get("name", "")), str(row.get("room", "")),
				str(row.get("wall", "")), float(row.get("lane", 0.0)),
				str(row.get("authored_wall", "?")), float(row.get("authored_lane", 0.0)),
				str(row.get("verdict", "")),
			])
	print("")
	print("SECRET_SITE_CANDIDATE_PROBE_OK seed=%d 房间=%d 有可布槽的房=%d 可布位点合计=%d" % [
		int(run.get("seed", 0)),
		(run.get("rows", []) as Array).size(),
		rooms_with_slot, total_accepted,
	])


## 跨种子比对：固定槽位方案的意义就是「换布局也不撞」。
## 比的是**同一个 (房间, 墙, lane) 在每种子里是否仍然可行**，而不是世界坐标 ——
## 布局变了坐标当然会变，但可行性必须稳定，否则「写死一个位置」就没有保证。
func _report_cross_seed(runs: Array) -> void:
	if runs.size() < 2:
		return
	print("")
	print("=== 跨种子可行性稳定性 ===")
	for value in runs:
		var run := value as Dictionary
		print("  seed=%-10d 房间=%d 可布位点=%d 主路门=%d" % [
			int(run.get("seed", 0)),
			(run.get("rows", []) as Array).size(),
			_count_slots(run), int(run.get("door_count", 0)),
		])

	# key -> 每个种子下的判定（"ok" 可布 / "door" 压门 / "neighbor" 贴邻房）。
	var table: Dictionary = {}
	for value in runs:
		var run := value as Dictionary
		var seed_key := str(int(run.get("seed", 0)))
		for row_value in run.get("rows", []) as Array:
			var row := row_value as Dictionary
			var room_id := str(row.get("room_id", ""))
			for slot_value in row.get("accepted", []) as Array:
				var slot := slot_value as Dictionary
				# 用**作者系**做 key：运行时标签会随房间旋转变，作者系不随。
				var authored: Array = slot.get("authored", [slot.get("wall", ""), slot.get("lane", 0.0)])
				var key := "%s|%s|%+.1f" % [
					room_id, str(authored[0]), float(authored[1]),
				]
				if not table.has(key):
					table[key] = {}
				var verdicts_ok := table[key] as Dictionary
				verdicts_ok[seed_key] = "ok"
			for slot_value in row.get("rejected", []) as Array:
				var slot := slot_value as Dictionary
				# 用**作者系**做 key：运行时标签会随房间旋转变，作者系不随。
				var authored: Array = slot.get("authored", [slot.get("wall", ""), slot.get("lane", 0.0)])
				var key := "%s|%s|%+.1f" % [
					room_id, str(authored[0]), float(authored[1]),
				]
				if not table.has(key):
					table[key] = {}
				var verdicts_bad := table[key] as Dictionary
				if not verdicts_bad.has(seed_key):
					verdicts_bad[seed_key] = str(slot.get("reason", "?"))

	var stable_ok := 0
	var stable_no := 0
	var flaky_door: Array = []
	var flaky_neighbor: Array = []
	for key in table.keys():
		var verdicts := table[key] as Dictionary
		var all_ok := verdicts.size() == runs.size()
		var all_no := true
		for seed_key in verdicts.keys():
			if str(verdicts[seed_key]) == "ok":
				all_no = false
			else:
				all_ok = false
		if all_ok:
			stable_ok += 1
		elif all_no:
			stable_no += 1
		else:
			# 波动项按「有没有出现过压门」分类：压门是硬伤，贴邻房只是不美观。
			var has_door := false
			for seed_key in verdicts.keys():
				if str(verdicts[seed_key]) == "door":
					has_door = true
			if has_door:
				flaky_door.append(key)
			else:
				flaky_neighbor.append(key)

	print("  稳定可布 %d 项 / 稳定不可布 %d 项 / 波动 %d 项（压门 %d · 贴邻房 %d）" % [
		stable_ok, stable_no, flaky_door.size() + flaky_neighbor.size(),
		flaky_door.size(), flaky_neighbor.size(),
	])
	_report_flaky(flaky_door, table, runs, "压门波动（真问题：某种子下会堵路）")
	_report_flaky(flaky_neighbor, table, runs, "贴邻房波动（不堵路，但门板会嵌在共享墙上）")

	_report_door_slots(runs)


func _report_flaky(keys: Array, table: Dictionary, runs: Array, title: String) -> void:
	if keys.is_empty():
		print("  %s：无 ✔" % title)
		return
	keys.sort()
	print("  %s：%d 项" % [title, keys.size()])
	for index in range(mini(keys.size(), 8)):
		var key := str(keys[index])
		var verdicts := table[key] as Dictionary
		var parts: Array = []
		for value in runs:
			var seed_key := str(int((value as Dictionary).get("seed", 0)))
			parts.append("%s=%s" % [seed_key, str(verdicts.get(seed_key, "未扫描"))])
		print("    %-24s %s" % [key, "  ".join(parts)])
	if keys.size() > 8:
		print("    …另有 %d 项未列出" % (keys.size() - 8))


## 主路门槽跨种子对比：门槽若在「房间本地系」里稳定，「写死一个槽」才真的不撞门。
func _report_door_slots(runs: Array) -> void:
	print("")
	print("=== 主路门槽跨种子对比（房间本地系）===")
	var inconsistent := 0
	var checked := 0
	for row_value in (runs[0] as Dictionary).get("rows", []) as Array:
		var room_id := str((row_value as Dictionary).get("room_id", ""))
		var signatures: Array = []
		var parts: Array = []
		for value in runs:
			var run := value as Dictionary
			var sig := _door_signature(run, room_id)
			signatures.append(sig)
			parts.append("seed%s[%s]" % [str(int(run.get("seed", 0))), sig])
		checked += 1
		var same := true
		for index in range(1, signatures.size()):
			if str(signatures[index]) != str(signatures[0]):
				same = false
		if not same:
			inconsistent += 1
		print("  %-12s %s  %s" % [
			room_id, "一致 ✔" if same else "**不一致 ✘**", "  ".join(parts),
		])
	print("  房间=%d 门槽跨种子不一致=%d" % [checked, inconsistent])


func _door_signature(run: Dictionary, room_id: String) -> String:
	for row_value in run.get("rows", []) as Array:
		var row := row_value as Dictionary
		if str(row.get("room_id", "")) != room_id:
			continue
		var parts: Array = []
		for door_value in row.get("doors", []) as Array:
			var door := door_value as Dictionary
			var authored: Array = door.get("authored", [door.get("wall", ""), door.get("lane", 0.0)])
			parts.append("%s%+.1f" % [str(authored[0]), float(authored[1])])
		parts.sort()
		return " ".join(parts)
	return "未扫描"


func _count_slots(run: Dictionary) -> int:
	var total := 0
	for value in run.get("rows", []) as Array:
		total += ((value as Dictionary).get("accepted", []) as Array).size()
	return total
