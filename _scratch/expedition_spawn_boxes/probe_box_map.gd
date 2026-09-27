extends Node3D
## 只读探针：dump 远征01「触发盒刷怪」**运行时长什么样**。
##
## 与 `probe_spawn_boxes_runtime.gd`（判据/门禁）分工不同 —— 本探针不判失败，
## 只把运行时真值倒出来给渲染器画图：
##   · 每房盒子实例（声明盒心 / **落地**盒心 / 漂移 / 尺寸 / 旋转 / 编成 / 容量）；
##   · `encounter.stages` 的调用序（第 N 波调哪几个实例）；
##   · **逐波逐只**的实际出怪（怪种 / 落点 / 延迟）—— 直接调 `Dungeon3D._spawn_box_waves`，
##     与真机 `_spawn_room_enemies` 走的是同一个函数、同一套 rng 种子，故逐字同口径。
##
## 输出：res://_scratch/expedition_spawn_boxes/spawn_box_map.json

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const CATALOG := preload("res://src/map/SpawnBoxCatalog.gd")
const OUT_PATH := "res://_scratch/expedition_spawn_boxes/spawn_box_map.json"
## 与旧机制落点图（`_scratch/expedition_spawn_map/spawn_map.json`）**同一个种子**，
## 这样「旧 vs 新」两张图才可比。
## 可用环境变量 `BOXMAP_SEED` 覆盖（多跑几个种子复核「钉死房型后砖格是否稳定」）。
const SEED_DEFAULT := 77001199
## 敌人实体碰撞半径（`Enemy3D` footprint 默认 0.8）。容量口径 = 间距硬下限
## `max(怪体直径 1.7, 盒 min_spacing_m)` —— 与出怪侧同一条规则。
const ENEMY_BODY_RADIUS := 0.8

var tower: TowerDescent3D


func _ready() -> void:
	var SEED := SEED_DEFAULT
	# 优先取 `-- 12345` 之后的用户参数（本机 bash 导出的环境变量 Godot 读不到），
	# 其次 `BOXMAP_SEED`，都没有则用默认种子（与旧落点图同种子，便于新旧对比）。
	var seed_text := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		seed_text = str(user_args[0])
	else:
		seed_text = OS.get_environment("BOXMAP_SEED")
	if not seed_text.is_empty() and seed_text.is_valid_int():
		SEED = int(seed_text)
	print("[probe] boot seed=%d" % SEED)
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	# 先把全部壳体/暗装建好 —— 否则 `_spawn_obstacle_free` 看不到家具碰撞，
	# 落点会比真机乐观（真机房里家具是实打实的障碍）。
	for room_value in tower._room_by_id.values():
		var room := room_value as DungeonRoom3D
		room.ensure_shell_built()
		room.ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var floor: int = maxi(1, int(tower.visual_theme.difficulty_rank))
	var rooms_out: Array = []
	var total_boxes := 0
	var total_points := 0
	var total_shifted := 0
	for room_value in tower._room_by_id.values():
		var room := room_value as DungeonRoom3D
		var dumped := _dump_room(room, floor)
		rooms_out.append(dumped)
		total_boxes += int(dumped["placements"].size())
		for wave_value in (dumped["waves"] as Array):
			total_points += int((wave_value as Array).size())
		for placement_value in (dumped["placements"] as Array):
			if float((placement_value as Dictionary)["shift"]) > 0.01:
				total_shifted += 1
		print("[probe]   room %s done (boxes=%d)" % [room.room_id, (dumped["placements"] as Array).size()])

	var payload := {
		"seed": SEED,
		"level_id": "expedition_01",
		"difficulty_rank": floor,
		"room_count": rooms_out.size(),
		"box_total": total_boxes,
		"point_total": total_points,
		"shifted_total": total_shifted,
		"rooms": rooms_out,
	}
	var out_path := OUT_PATH
	if SEED != SEED_DEFAULT:
		out_path = OUT_PATH.get_basename() + "_%d.json" % SEED
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 %s" % out_path)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("BOX_MAP_SUMMARY rooms=%d boxes=%d points=%d shifted=%d"
		% [rooms_out.size(), total_boxes, total_points, total_shifted])
	print("BOX_MAP_DONE %s" % out_path)
	get_tree().quit(0)


func _dump_room(room: DungeonRoom3D, floor: int) -> Dictionary:
	var rid := room.room_id
	var dimensions := room.get_dimensions()
	var record_index := int(tower.call("_record_index", rid))
	var floor_level := clampi(
		int(float(record_index) / maxf(1.0, float(tower._records.size() - 1)) * 3.0), 0, 3
	)

	var tile_cells: Array = []
	for value in room._authored_tile_cells:
		var cell := value as Vector3
		tile_cells.append([snappedf(cell.x, 0.001), snappedf(cell.z, 0.001)])

	var doors: Array = []
	var door_nodes: Dictionary = room._door_nodes
	var door_targets: Dictionary = room.door_targets
	for direction in room.doors:
		var node := door_nodes.get(str(direction)) as Node3D
		var door_local := Vector3.ZERO
		if node != null:
			door_local = node.position
		doors.append({
			"dir": str(direction),
			"target": str(door_targets.get(str(direction), "")),
			"local": [snappedf(door_local.x, 0.001), snappedf(door_local.z, 0.001)],
		})

	var stages := tower.call("_resolve_encounter_stages", room.encounter, room.spawn_placements.size()) as Array
	var stages_out: Array = []
	for stage_value in stages:
		var indices: Array = []
		for index_value in (stage_value as Array):
			indices.append(int(index_value))
		stages_out.append(indices)

	# —— 盒子实例（含落地盒心）——
	var placements_out: Array = []
	var landed_boxes: Array = []
	for index in range(room.spawn_placements.size()):
		var placement := tower.call("_box_placement_at", room.spawn_placements, index) as Dictionary
		if placement.is_empty():
			placements_out.append({"index": index, "box": str((room.spawn_placements[index] as Dictionary).get("box", "")), "error": "resolve_failed"})
			continue
		var box_id := str(placement["box"])
		var box := CATALOG.load_box(box_id)
		var center := placement["box_center"] as Vector2
		var size := placement["box_size"] as Vector2
		var rotation := float(placement["box_rotation"])
		var min_spacing := float(box.get("min_spacing_m", 0.0))
		var recess := int(box.get("wall_recess_tiles", 1))
		var demand := _demand(box)
		var landing := room.resolve_spawn_box_center_local(
			center, size, demand, rotation, min_spacing, recess
		)
		var shift := (landing - center).length()
		var spawns_out: Array = []
		for spawn_value in (box.get("spawns", []) as Array):
			var spawn := spawn_value as Dictionary
			spawns_out.append({
				"type": str(spawn.get("type", "")),
				"count_min": int(spawn.get("count_min", 0)),
				"count_max": int(spawn.get("count_max", int(spawn.get("count_min", 0)))),
				"delay_sec": float(spawn.get("delay_sec", 0.0)),
			})
		var capacity := _capacity(room, landing, size, rotation, min_spacing)
		# —— 声明位置侧诊断（绝对砖心口径的核验）——
		# 为什么要单独量：`shift > 0` 有两种可能 —— ①声明值不是真砖心、被吸附挪走；
		# ②声明砖心合法，但**容量不足**触发落地平移。两者处置完全不同（前者改坐标、
		# 后者改尺寸/编成/家具），必须分开。
		var snapped := room.snap_box_center_to_tile(center, recess)
		var snap_delta := (snapped - center).length()
		var declared_is_tile := false
		for cell in room._authored_tile_cells:
			if Vector2(cell.x, cell.z).distance_to(center) <= 0.01:
				declared_is_tile = true
				break
		var declared_half := size * 0.5
		var declared_seed := room._box_pick_seed(snapped, declared_half)
		var declared_spacing := maxf(ENEMY_BODY_RADIUS * 2.0 + 0.1, min_spacing)
		var declared_pool := room._box_sample_points(
			snapped, declared_half, cos(deg_to_rad(rotation)), sin(deg_to_rad(rotation)),
			room._spawn_clearance()
		)
		var declared_fits := room._fits_in_box(
			declared_pool, declared_spacing, demand, declared_seed
		)
		# 候选池的几何：用来区分「点挤成一列」的两种根因 ——
		#   ① 池本来就窄（盒底下有家具/柱/凹口）⇒ 数据侧问题，该挪盒或缩盒；
		#   ② 池很宽但选点挤成一线 ⇒ 选点规则问题（机制）。
		var pool := room._box_sample_points(
			landing, size * 0.5, cos(deg_to_rad(rotation)), sin(deg_to_rad(rotation)),
			room._spawn_clearance()
		)
		var pool_span := _span(pool)
		placements_out.append({
			"index": index,
			"box": box_id,
			"center_declared": [snappedf(center.x, 0.001), snappedf(center.y, 0.001)],
			"center_landed": [snappedf(landing.x, 0.001), snappedf(landing.y, 0.001)],
			"shift": snappedf(shift, 0.001),
			"size": [snappedf(size.x, 0.001), snappedf(size.y, 0.001)],
			"rotation_deg": snappedf(rotation, 0.01),
			"wall_recess_tiles": recess,
			"min_spacing_m": min_spacing,
			"box_delay_sec": float(placement.get("box_delay", 0.0)),
			"demand_max": demand,
			"capacity": capacity,
			"pool_count": pool.size(),
			"pool_span": pool_span,
			# 声明侧诊断三件套（见上方注释）
			"declared_is_tile": declared_is_tile,
			"snap_delta": snappedf(snap_delta, 0.001),
			"declared_pool_count": declared_pool.size(),
			"declared_fits": declared_fits,
			"spawns": spawns_out,
		})
		landed_boxes.append([landing, size, rotation])

	# —— 逐波逐只实际出怪（与真机同一条函数）——
	var waves := tower.call("_spawn_box_waves", room, floor, floor_level) as Array
	var waves_out: Array = []
	for wave_value in waves:
		var entries: Array = []
		for entry_value in (wave_value as Array):
			var config := entry_value as Dictionary
			var position := config.get("spawn_position", Vector3.INF) as Vector3
			var local := room.to_local(position)
			entries.append({
				"type": str(config.get("enemy_type", "?")),
				"world": [snappedf(position.x, 0.001), snappedf(position.z, 0.001)],
				"local": [snappedf(local.x, 0.001), snappedf(local.z, 0.001)],
				"delay_sec": snappedf(float(config.get("spawn_delay_sec", 0.0)), 0.01),
				"box_index": _which_box(Vector2(local.x, local.z), landed_boxes),
			})
		waves_out.append(entries)

	# —— 旧机制落点（同房、同种子）：供「旧 vs 新」对比 ——
	var legacy_points: Array = []
	for point_index in range(16):
		var point := room.spawn_point_for_index(point_index)
		if not point.is_finite():
			break
		var local := room.to_local(point)
		legacy_points.append([snappedf(local.x, 0.001), snappedf(local.z, 0.001)])

	return {
		"room_id": rid,
		"room_type": room.room_type,
		"size_class": room.size_class,
		"is_main_path": room.is_main_path,
		"peaceful": room.authored_layout_peaceful,
		"spawn_boxes_only": room.spawn_boxes_only,
		"authored_layout_room_id": room.authored_layout_room_id,
		"authored_instance_total": room.authored_layout_instances.size(),
		"floor_level": floor_level,
		"dimensions": [snappedf(dimensions.x, 0.001), snappedf(dimensions.y, 0.001)],
		"origin": [snappedf(room.global_position.x, 0.001), snappedf(room.global_position.z, 0.001)],
		"yaw_deg": snappedf(rad_to_deg(room.global_rotation.y), 0.01),
		"tile_cells_local": tile_cells,
		"doors": doors,
		"stages": stages_out,
		"placements": placements_out,
		"waves": waves_out,
		"legacy_points": legacy_points,
	}


## 该盒一次可能出的**最大**只数（各条目 count_max 之和）—— 容量判据的分子。
func _demand(box: Dictionary) -> int:
	var total := 0
	for spawn_value in (box.get("spawns", []) as Array):
		var spawn := spawn_value as Dictionary
		total += int(spawn.get("count_max", int(spawn.get("count_min", 0))))
	return total


## 盒内**真正能排下多少只**（含间距硬下限），与出怪同一 `min_spacing` 口径。
## 直接在给定盒心处采样，**不触发落地平移**（否则量的就不是这个位置了）——
## 故这里不能用 `spawn_points_in_box`（它内部会再解析落地盒）。
func _capacity(room: DungeonRoom3D, center: Vector2, size: Vector2, rotation: float, min_spacing: float) -> int:
	var half := size * 0.5
	var radians := deg_to_rad(rotation)
	var pool := room._box_sample_points(center, half, cos(radians), sin(radians), room._spawn_clearance())
	var spacing := maxf(ENEMY_BODY_RADIUS * 2.0 + 0.1, min_spacing)
	var seed_value := room._box_pick_seed(center, half)
	return room._scatter_box_pick(pool, spacing, 64, seed_value).size()


## 点在哪个**落地盒**里（盒可绕 Y 旋转 ⇒ 先转回盒局部系再比半尺寸）。
## 与出怪侧 `_box_sample_points` 的「盒局部系 → 房间局部系」互为逆变换。
func _which_box(local: Vector2, boxes: Array) -> int:
	for index in range(boxes.size()):
		var entry := boxes[index] as Array
		var center := entry[0] as Vector2
		var size := entry[1] as Vector2
		var radians := deg_to_rad(float(entry[2]))
		var cos_r := cos(radians)
		var sin_r := sin(radians)
		var dx := local.x - center.x
		var dz := local.y - center.y
		var lx := dx * cos_r + dz * sin_r
		var lz := -dx * sin_r + dz * cos_r
		if absf(lx) <= size.x * 0.5 + 0.02 and absf(lz) <= size.y * 0.5 + 0.02:
			return index
	return -1


## 候选池在 x/z 两轴上的跨度（米）。窄池 ⇒ 盒底下有家具/凹口。
func _span(pool: Array[Vector3]) -> Array:
	if pool.is_empty():
		return [0.0, 0.0]
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in pool:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	return [snappedf(max_x - min_x, 0.001), snappedf(max_z - min_z, 0.001)]
