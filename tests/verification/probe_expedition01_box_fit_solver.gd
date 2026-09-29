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
## 用法：`godot --headless --path . --scene res://tests/verification/probe_expedition01_box_fit_solver.tscn`
## 输出：ROOM|box|target|current_center|current_cap|picked_center|picked_cap|dist_moved

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const GRID_UNIT_M := 5.0
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


func _ready() -> void:
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
	print("ROOM|box|target|current_center|current_cap|picked_center|picked_cap|moved_m")
	for key in TARGETS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("%s|MISSING" % key)
			continue
		_solve_room(room, TARGETS[key])
	print("PROBE_DONE")
	get_tree().quit(0)


func _solve_room(room: DungeonRoom3D, targets: Array) -> void:
	var dim := room.get_dimensions()
	print("# %s dim=%sx%s" % [room.room_id, str(dim.x), str(dim.y)])
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
		# 显式标 Variant：`_current_center` 返回 Variant（找不到时 null），
		# 用 `:=` 会被推断成 Variant 而触发「warning treated as error」。
		var current: Variant = _current_center(room, box_id)
		var current_cap := -1
		if current != null:
			current_cap = _declared_cap(room, current as Vector2, size, spacing, recess)
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
			if _fits_at(room, center, size, spacing, recess, target):
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
			print("%s|%s|%d|%s|%d|NO_FIT|-" % [
				room.room_id, box_id, target, str(current), current_cap,
			])
			continue
		var picked := best as Vector2
		taken.append(Rect2(picked - size * 0.5, size))
		var moved := -1.0
		if current != null:
			moved = picked.distance_to(current as Vector2)
		print("%s|%s|%d|%s|%d|%s|%d|%.2f" % [
			room.room_id, box_id, target,
			_center_str(current), current_cap,
			_center_str(picked),
			_declared_cap(room, picked, size, spacing, recess),
			moved,
		])

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
	target: int
) -> bool:
	if target <= 0:
		return true
	if room.resolve_spawn_box_center_local(
		center, size, target, 0.0, spacing, recess
	).distance_to(center) > 0.001:
		return false
	var points := room.spawn_points_in_box(center, size, target, 0.0, spacing, recess)
	var finite := 0
	for point in points:
		if (point as Vector3).is_finite():
			finite += 1
			if finite >= target:
				return true
	return false


## 原地容量（用于报告原位的上限）。逐 1..MAX_PROBE 递增，仅在**少量**候选上调用。
func _declared_cap(
	room: DungeonRoom3D, center: Vector2, size: Vector2, spacing: float, recess: int
) -> int:
	var best := 0
	for count in range(1, MAX_PROBE + 1):
		if not _fits_at(room, center, size, spacing, recess, count):
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
