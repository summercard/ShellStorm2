extends Node
## 探针：远征01 每个触发盒实例的**真实容量上限**（盒内能排出多少只怪）。
##
## 目的：为「刷怪数量递进」改动提供数据侧上限依据 —— 单盒容量 = 盒面积 ∩ 可通行区 ∩
## 离墙净距 ∩ 无障碍，再按「怪体间距硬下限」首适配取点。若目标数量 > 容量，运行时会
## 按有限点**静默截断**（`Dungeon3D._collect_box_stage_entries`），表现为「改了没生效」。
##
## 口径与设计 §7.3-R1 一致：`cap_declared` = 声明盒心原地能排出的最大只数；
## `cap_shifted` = 允许运行时「落地平移」（`SPAWN_BOX_SHIFT_RADIUS_M`）后能排出的最大只数。
## ⚠ 只测「声明位置」，因为落地平移会让漂移量 ≠ 0、并可能让两盒互叠（判据 I）。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const PROBE_MAX_COUNT := 48
const ROOM_KEYS: Array[String] = [
	"room_01", "room_02", "room_03", "room_04", "room_05",
	"room_06", "room_07", "room_08", "room_09", "room_10", "boss",
]

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
	print("ROOT|key|idx|box_id|size|spacing|cap_declared|cap_shifted|drift_at_cap")
	for key in ROOM_KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("%s|MISSING" % key)
			continue
		_probe_room(room)
	print("PROBE_DONE")
	get_tree().quit(0)


func _probe_room(room: DungeonRoom3D) -> void:
	var placements := room.spawn_placements
	print("# %s dim=%s boxes=%d tile_cells=%d" % [
		room.room_id, str(room.get_dimensions()), placements.size(),
		room._authored_tile_cells.size(),
	])
	for index in range(placements.size()):
		var placement := placements[index] as Dictionary
		var box_id := str(placement.get("box", ""))
		var box := SpawnBoxCatalog.load_box(box_id)
		if box.is_empty():
			print("%s|%d|%s|INVALID_BOX" % [room.room_id, index, box_id])
			continue
		var size := box.get("size_m", Vector2.ZERO) as Vector2
		var raw_size: Variant = placement.get("size_m", null)
		if raw_size is Array and (raw_size as Array).size() >= 2:
			size = Vector2(float((raw_size as Array)[0]), float((raw_size as Array)[1]))
		var center := _vec2(placement.get("center_m", []))
		var rotation := float(placement.get("rotation_deg", 0.0))
		var spacing := float(box.get("min_spacing_m", 0.0))
		var recess := int(box.get("wall_recess_tiles", SpawnBoxCatalog.DEFAULT_WALL_RECESS_TILES))
		var declared_cap := _max_count_at(room, center, size, rotation, spacing, recess, true)
		var shifted_cap := _max_count_at(room, center, size, rotation, spacing, recess, false)
		var drift := room.resolve_spawn_box_center_local(
			center, size, maxi(1, declared_cap), rotation, spacing, recess
		)
		print("%s|%d|%s|%s|%.1f|%d|%d|%.2f" % [
			room.room_id, index, box_id.replace("box_", ""),
			str(size), spacing, declared_cap, shifted_cap, drift.distance_to(center),
		])


## 求「该盒原地（`declared_only=true`）或允许平移后能排出的最大只数」。
## 逐 N 试探：`spawn_points_in_box` 取不满时尾部补 `Vector3.INF`，故数有限点即得容量；
## 但 `required` 过大时 `_resolve_box_pool` 会**整体平移**盒心去找容量 ⇒ 分别测两条口径。
func _max_count_at(
	room: DungeonRoom3D,
	center: Vector2,
	size: Vector2,
	rotation: float,
	spacing: float,
	recess: int,
	declared_only: bool
) -> int:
	var best := 0
	for count in range(1, PROBE_MAX_COUNT + 1):
		var resolved := room.resolve_spawn_box_center_local(
			center, size, count, rotation, spacing, recess
		)
		if declared_only and resolved.distance_to(center) > 0.001:
			break
		var points := room.spawn_points_in_box(center, size, count, rotation, spacing, recess)
		var finite := 0
		for point in points:
			if (point as Vector3).is_finite():
				finite += 1
		if finite < count:
			break
		best = count
	return best


func _vec2(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO
