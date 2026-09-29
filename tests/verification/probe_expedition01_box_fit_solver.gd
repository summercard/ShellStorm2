extends Node
## 求解器：给定目标出怪数，为房间里的每个触发盒找**声明位置**，
## 使「原地容量 ≥ 目标」（即漂移 = 0），且满足判据 H（盒边离墙 ≥ 5×recess）与
## 判据 I（盒 AABB 互不叠）。
##
## 为什么需要它：运行时为了塞下目标数量会**把整个盒子平移**（`SPAWN_BOX_SHIFT_RADIUS_M`
## = 30 m）。平移后声明坐标 ≠ 实际坐标、且可能压到邻盒 —— 设计 §4.1 的
## 「468 盒全部 shift=0」口径就破了。业主 2026-09-29 要把 room_01/room_02 逐盒翻倍
## 并**手动调位置**，故先把「摆哪能原地装下」算出来。
##
## 用法：`godot --headless --path . res://tests/verification/probe_expedition01_box_fit_solver.tscn`
## 输出：ROOM|box|target|cur_runtime|cur_json|cur_cap|pick_runtime|pick_json|pick_cap|moved_m
##
## ⚠ **两套坐标系**：`floor_00.json` 里的 `center_m` 是**设计源帧**；运行时
## `FloorPlanGenerator._rotated_spawn_placements()` 会按落位阶段定的 `rotation_deg`
## 把它转一次（房型占位会有 90° 转置）。故**改 JSON 必须用 JSON 帧坐标** ——
## 直接把运行时坐标抄进 JSON，盒子会转到别处去。本探针两帧都打，并自带一致性断言。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const FLOOR_JSON := "res://source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json"
const SEED_VALUE := 77001199
const GRID_UNIT_M := 5.0
const MAP_OUT := "res://_scratch/expedition_spawn_boxes/room_box_fit_map.json"
const MAX_PROBE := 24

## 目标：房间 → [[盒 id, 目标只数], ...]。顺序 = 房内实例顺序，与 `spawn_placements` 对齐。
## 用二维数组而非字典：GDScript 常量表达式里嵌套字典字面量的类型推断会告警成错误。
const TARGETS := {
	"room_02": [
		["box_corner_ambush", 4],
		["box_wall_arc", 4],
		["box_room_spread", 6],
		["box_corridor_column", 6],
	],
	"room_01": [
		["box_room_spread", 6],
		["box_corner_ambush", 4],
		["box_wall_arc", 4],
	],
}

var tower: TowerDescent3D
## 设计源房表（JSON 帧的 `center_m` 出处）。运行时坐标是它按房姿态转一次的结果。
var _json_rooms: Dictionary = {}
## 求解结果：`"<room>|<box>"` → 建议盒心（运行时帧），供定位图渲染时叠加显示。
var _recommended: Dictionary = {}


func _ready() -> void:
	var raw := _read_json(FLOOR_JSON)
	for room_value in (raw.get("rooms", []) as Array):
		var room_row := room_value as Dictionary
		_json_rooms[str(room_row.get("key", ""))] = room_row
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("SEED=%d" % SEED_VALUE)
	print("ROOM|box|target|cur_runtime|cur_json|cur_cap|pick_runtime|pick_json|pick_cap|moved_m")
	for key in TARGETS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("%s|MISSING" % key)
			continue
		_solve_room(room, TARGETS[key])
	print("PROBE_DONE")
	# 同步导出机器可读的定位图数据，供 `render_room_box_fit.py` 画 PNG。
	_dump_map()
	get_tree().quit(0)


## 导出：房尺寸 + 可走砖格 + 每盒（现状 / 建议）的盒心、尺寸、姿态、容量。
## 坐标一律给**设计源帧**与**运行时帧**两份 —— 改 JSON 只用前者，看图只信后者。
func _dump_map() -> void:
	var out := {"seed": SEED_VALUE, "rooms": []}
	for key in TARGETS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			continue
		var rot := _resolve_rotation(room)
		var dim := room.get_dimensions()
		var tiles: Array = []
		for cell in room._authored_tile_cells:
			var v := cell as Vector3
			tiles.append([v.x, v.z])
		var boxes: Array = []
		for placement_value in room.spawn_placements:
			var placement := placement_value as Dictionary
			var box_id := str(placement.get("box", ""))
			var box := SpawnBoxCatalog.load_box(box_id)
			if box.is_empty():
				continue
			var size := box.get("size_m", Vector2.ZERO) as Vector2
			var center := _vec2(placement.get("center_m", []))
			var recommendation: Variant = _recommended.get("%s|%s" % [room.room_id, box_id])
			boxes.append({
				"box": box_id,
				"size": [size.x, size.y],
				"rotation_deg": float(placement.get("rotation_deg", 0.0)),
				"center_runtime": [center.x, center.y],
				"center_json": _json_pair(_to_json_frame(center, rot)),
				"cap": _declared_cap(
					room, center, size,
					float(box.get("min_spacing_m", 0.0)),
					int(box.get("wall_recess_tiles", SpawnBoxCatalog.DEFAULT_WALL_RECESS_TILES)),
					float(placement.get("rotation_deg", 0.0))
				),
				"recommend_runtime": (
					(recommendation as Dictionary).get("center_runtime")
					if recommendation != null else null
				),
				"recommend_json": (
					(recommendation as Dictionary).get("center_json")
					if recommendation != null else null
				),
				"recommend_cap": (
					int((recommendation as Dictionary).get("cap", -1))
					if recommendation != null else -1
				),
			})
		out["rooms"].append({
			"key": key,
			"rotation_resolved_deg": rot,
			"dim_runtime": [dim.x, dim.y],
			"tiles": tiles,
			"boxes": boxes,
		})
	var file := FileAccess.open(MAP_OUT, FileAccess.WRITE)
	if file == null:
		push_warning("[fit] 写不出 %s" % MAP_OUT)
		return
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	print("MAP_WRITTEN %s" % MAP_OUT)


func _json_pair(value: Variant) -> Variant:
	if value == null:
		return null
	var v := value as Vector2
	return [v.x, v.y]


func _solve_room(room: DungeonRoom3D, targets: Array) -> void:
	var dim := room.get_dimensions()
	# 反解设计源 → 运行时的旋转角（落位阶段定的，JSON 里读不到），见 `_resolve_rotation`。
	var rot := _resolve_rotation(room)
	print("# %s dim=%sx%s rot=%d" % [
		room.room_id, str(dim.x), str(dim.y), int(rot),
	])
	var candidates := _candidate_centers(dim)
	var taken: Array[Rect2] = []
	for entry_value in targets:
		var entry := entry_value as Array
		var box_id := str(entry[0])
		var target := int(entry[1])
		var box := SpawnBoxCatalog.load_box(box_id)
		if box.is_empty():
			print("%s|%s|INVALID_BOX" % [room.room_id, box_id])
			continue
		var size := box.get("size_m", Vector2.ZERO) as Vector2
		var spacing := float(box.get("min_spacing_m", 0.0))
		var recess := int(box.get("wall_recess_tiles", SpawnBoxCatalog.DEFAULT_WALL_RECESS_TILES))
		# 盒自身姿态取**运行时**口径（= 设计源 rotation_deg + 房姿态），否则方形以外的盒
		# 容量会算错（`box_corridor_column` 2×4 转 90° 后长边方向不同）。
		var box_rot := _runtime_rotation(room, box_id)
		var current: Variant = _current_center(room, box_id)
		var current_cap := -1
		if current != null:
			current_cap = _declared_cap(
				room, current as Vector2, size, spacing, recess, box_rot
			)
		# 选点：满足 wall-recess 与不叠的前提下，取「容量够且离原位置最近」的候选。
		var best: Variant = null
		var best_score := INF
		for center in candidates:
			if not _edge_clearance_ok(center, size, dim, recess):
				continue
			var rect := Rect2(center - size * 0.5, size)
			var overlaps := false
			for prior in taken:
				if (prior as Rect2).intersects(rect):
					overlaps = true
					break
			if overlaps:
				continue
			var cap := 0
			if _fits_at(room, center, size, spacing, recess, target, box_rot):
				cap = target
			if cap < target:
				continue
			var origin := Vector2.ZERO
			if current != null:
				origin = current as Vector2
			var score := center.distance_to(origin)
			if score < best_score:
				best_score = score
				best = center
		if best == null:
			print("%s|%s|%d|%s|%s|%d|NO_FIT|-|-|-" % [
				room.room_id, box_id, target,
				_center_str(current), _center_str(_to_json_frame(current, rot)), current_cap,
			])
			continue
		var picked := best as Vector2
		taken.append(Rect2(picked - size * 0.5, size))
		var moved := -1.0
		if current != null:
			moved = picked.distance_to(current as Vector2)
		var picked_cap := _declared_cap(room, picked, size, spacing, recess, box_rot)
		_recommended["%s|%s" % [room.room_id, box_id]] = {
			"center_runtime": [picked.x, picked.y],
			"center_json": _json_pair(_to_json_frame(picked, rot)),
			"cap": picked_cap,
		}
		print("%s|%s|%d|%s|%s|%d|%s|%s|%d|%.2f" % [
			room.room_id, box_id, target,
			_center_str(current), _center_str(_to_json_frame(current, rot)), current_cap,
			_center_str(picked), _center_str(_to_json_frame(picked, rot)),
			picked_cap, moved,
		])


## 反解「设计源 → 运行时」的旋转角：拿房表里每个实例的设计源 `center_m` 与运行时
## `center_m` 对照，四个候选角里唯一能逐盒对上的那个即为真值。对不上就返回 0
## 并告警 —— 绝不猜一个「差不多」的角度去算坐标。
func _resolve_rotation(room: DungeonRoom3D) -> float:
	var json_key := _json_key_for(room)
	if json_key.is_empty():
		push_warning("[fit] 设计源里找不到房间 %s，按 0° 处理" % room.room_id)
		return 0.0
	var json_row := _json_rooms[json_key] as Dictionary
	var json_pls := json_row.get("spawn_placements", []) as Array
	var rt_pls := room.spawn_placements
	if json_pls.is_empty() or json_pls.size() != rt_pls.size():
		push_warning("[fit] %s 设计源与运行时盒数不一致，按 0° 处理" % room.room_id)
		return 0.0
	for candidate in [0.0, 90.0, 180.0, 270.0]:
		var ok := true
		for i in range(json_pls.size()):
			var a := _vec2(((json_pls[i] as Dictionary).get("center_m", [])))
			var b := _vec2(((rt_pls[i] as Dictionary).get("center_m", [])))
			if _rotate(a, candidate).distance_to(b) > 0.001:
				ok = false
				break
		if ok:
			return candidate
	push_warning("[fit] %s 无法反解旋转角（设计源与运行时逐盒都对不上）" % room.room_id)
	return 0.0


## 运行时坐标 → 设计源坐标（施加逆旋转）。
func _to_json_frame(runtime_center: Variant, rotation_deg: float) -> Variant:
	if runtime_center == null:
		return null
	return _rotate(runtime_center as Vector2, fposmod(360.0 - rotation_deg, 360.0))


## 与 `FloorPlanGenerator._rotate_port_vector` 同式：(x,y) 逐 90° 步进为 (y,-x)。
func _rotate(value: Vector2, rotation_deg: float) -> Vector2:
	var steps := posmod(int(round(rotation_deg / 90.0)), 4)
	var result := value
	for _step in range(steps):
		result = Vector2(result.y, -result.x)
	return result


## 运行时盒姿态（度）。盒姿态与房姿态一起转，故直接读运行时实例上的 `rotation_deg`。
func _runtime_rotation(room: DungeonRoom3D, box_id: String) -> float:
	for placement_value in room.spawn_placements:
		var placement := placement_value as Dictionary
		if str(placement.get("box", "")) == box_id:
			return float(placement.get("rotation_deg", 0.0))
	return 0.0


## 运行时 `room_id`（`f00_room_02`）→ 设计源 `key`（`room_02`）。
## `DungeonRoom3D` 上没有 `legacy_room_id` 属性，故按前缀剥：`f00_` 之后即 key。
func _json_key_for(room: DungeonRoom3D) -> String:
	var id := room.room_id
	var underscore := id.find("_")
	if underscore >= 0:
		var suffix := id.substr(underscore + 1)
		if _json_rooms.has(suffix):
			return suffix
	return id if _json_rooms.has(id) else ""


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}

## 候选盒心 = 房内全部砖心（格心）。砖心相位是判据 G 的硬要求，故只在砖心上选。
func _candidate_centers(dim: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var half := GRID_UNIT_M * 0.5
	var nx := int(floor(dim.x / GRID_UNIT_M))
	var ny := int(floor(dim.y / GRID_UNIT_M))
	for ix in range(nx):
		for iy in range(ny):
			out.append(Vector2(
				-dim.x * 0.5 + half + float(ix) * GRID_UNIT_M,
				-dim.y * 0.5 + half + float(iy) * GRID_UNIT_M
			))
	return out


## 盒边到四面房墙的净距 ≥ 5×recess（与判据 H 同口径）。
func _edge_clearance_ok(
	center: Vector2, size: Vector2, dim: Vector2, recess: int
) -> bool:
	var need := GRID_UNIT_M * float(maxi(0, recess))
	var half := dim * 0.5
	return (
		center.x - size.x * 0.5 - (-half.x) >= need - 0.001
		and half.x - (center.x + size.x * 0.5) >= need - 0.001
		and center.y - size.y * 0.5 - (-half.y) >= need - 0.001
		and half.y - (center.y + size.y * 0.5) >= need - 0.001
	)


## 「原地装得下 target 只吗」——判据：盒心不漂移 且 盒内能排出 target 个有限落点。
##
## ⚠ 只探 target 一次，不逐 1..MAX 递增。递增版每候选要跑 target 次
## `resolve_spawn_box_center_local`（内含盒池搜索），48 候选 × 4 盒 × 最多次 ⇒
## 实测 240 s 都跑不完（被 watchdog 杀掉）。单点判定把调用数从 O(48·target) 降到 O(48)。
func _fits_at(
	room: DungeonRoom3D,
	center: Vector2,
	size: Vector2,
	spacing: float,
	recess: int,
	target: int,
	box_rotation: float = 0.0
) -> bool:
	if target <= 0:
		return true
	if room.resolve_spawn_box_center_local(
		center, size, target, box_rotation, spacing, recess
	).distance_to(center) > 0.001:
		return false
	var points := room.spawn_points_in_box(
		center, size, target, box_rotation, spacing, recess
	)
	var finite := 0
	for point in points:
		if (point as Vector3).is_finite():
			finite += 1
			if finite >= target:
				return true
	return false


## 原地容量（用于报告原位的上限）。逐 1..MAX_PROBE 递增，仅在**少量**候选上调用。
func _declared_cap(
	room: DungeonRoom3D,
	center: Vector2,
	size: Vector2,
	spacing: float,
	recess: int,
	box_rotation: float = 0.0
) -> int:
	var best := 0
	for count in range(1, MAX_PROBE + 1):
		if not _fits_at(room, center, size, spacing, recess, count, box_rotation):
			break
		best = count
	return best


func _current_center(room: DungeonRoom3D, box_id: String) -> Variant:
	for placement_value in room.spawn_placements:
		var placement := placement_value as Dictionary
		if str(placement.get("box", "")) != box_id:
			continue
		return _vec2(placement.get("center_m", []))
	return null


func _center_str(value: Variant) -> String:
	if value == null:
		return "-"
	var v := value as Vector2
	return "[%.1f, %.1f]" % [v.x, v.y]


func _vec2(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO
