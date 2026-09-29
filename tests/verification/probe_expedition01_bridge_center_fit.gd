extends Node
## 探针：给 room_05（桥房）**中间**找「能原地装下 16 只怪、且漂移为 0」的盒心与盒尺寸。
##
## 背景：业主 2026-09-29 要在桥房中间新增一个触发盒（总量 16 只：壳甲×4 + 小僵尸×8 + 警察×4）。
## 桥房两端（`y=±22.5`）已有 4 个盒，中间是空的。
##
## 本探针要回答三个数据问题：
##   ① 桥心可走面到底长什么样（`_authored_tile_cells` 的**真实**刻度，不假设房表 `size_m`）；
##   ② 合法盒心只能取砖心 ⇒ 在窄桥上哪些砖心可用；
##   ③ 要装 16 只，盒面最小多少、放哪个砖心，才能 **漂移 = 0**（不触发运行时静默平移）。
##
## ⚠ 两条实测踩过的坑：
##   (a) `_authored_tile_cells` 的坐标带 ~1e-5 浮点抖动、同一砖重复出现多次 ⇒ 一律取整到 0.1 m 再归并；
##   (b) 默认 `wall_recess_tiles=1` 要求盒心砖周围有 5.01 m 净距（10.02 m 见方全铺砖）——
##       桥心只有 10 m 宽，**任何砖心都不达标**，于是 cap 恒为 0。桥心盒必须 `wall_recess_tiles=0`。
##
## 用法：`godot --headless --path . res://tests/verification/probe_expedition01_bridge_center_fit.tscn`

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const ROOM_KEY := "room_05"
const TARGET := 16
const MAX_PROBE := 24
## 拟合表用的怪体间距（米）。1.7 = `ENEMY_BODY_RADIUS_M*2+0.1`，即运行时**最宽松**口径，
## 用来找「能不能装下」的可行上界；实际盒子用多少由盒子文件的 `min_spacing_m` 定。
const FIT_SPACING := 1.7
## 候选盒面 [宽x, 长z]（米）。正方形用来找面积下界；矩形用来贴合「10 m 宽窄桥」的几何。
const CANDIDATE_SIZES: Array = [
	[10.0, 10.0], [12.0, 12.0],
	[10.0, 12.0], [10.0, 14.0], [10.0, 16.0], [10.0, 18.0],
	[15.0, 10.0], [12.0, 10.0],
]
## 桥心候选砖心（局部坐标，恒为 5k+2.5 相位）。x 只取桥上两列，y 取桥身 6 行。
const CANDIDATE_CENTERS: Array = [
	[2.5, -2.5], [-2.5, -2.5], [2.5, 2.5], [-2.5, 2.5],
	[2.5, -7.5], [-2.5, -7.5], [2.5, 7.5], [-2.5, 7.5],
	[2.5, -12.5], [-2.5, -12.5], [2.5, 12.5], [-2.5, 12.5],
]

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var room := tower._room_by_id.get(ROOM_KEY) as DungeonRoom3D
	if room == null:
		print("ROOM_MISSING %s" % ROOM_KEY)
		get_tree().quit(1)
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	print("SEED=%d" % SEED_VALUE)
	print("ROOM=%s dim=%.1fx%.1f cells=%d" % [
		ROOM_KEY, room.get_dimensions().x, room.get_dimensions().y,
		room._authored_tile_cells.size(),
	])
	_dump_grid(room)
	_dump_existing_boxes(room)
	# ⚠ 拟合表很贵（每格 1~2 次盒池搜索，组合数是 中心×尺寸×recess×spacing）。
	# 默认只跑「地形 + 现状」，拟合表用环境变量 `FIT=1` 显式打开，否则会被 watchdog 杀。
	if OS.get_environment("FIT") == "1":
		_dump_fit(room)
	print("PROBE_DONE")
	get_tree().quit(0)


## ASCII 网格。取整到 0.1 m 归并（见文件头坑 (a)）。
func _dump_grid(room: DungeonRoom3D) -> void:
	var owned := {}
	for cell_value in room._authored_tile_cells:
		var v := cell_value as Vector3
		owned[_snap(v.x, v.z)] = true
	var xs: Array[float] = []
	var ys: Array[float] = []
	for key_value in owned:
		var key := key_value as Vector2
		if not xs.has(key.x):
			xs.append(key.x)
		if not ys.has(key.y):
			ys.append(key.y)
	xs.sort()
	ys.sort()
	print("GRID cols=%d rows=%d tiles=%d  列=x 行=y  `.`=授权砖" % [
		xs.size(), ys.size(), owned.size(),
	])
	var header := "        "
	for x in xs:
		header += "%6.1f" % x
	print(header)
	for index in range(ys.size() - 1, -1, -1):
		var y := ys[index]
		var line := "%6.1f  " % y
		for x in xs:
			line += "%6s" % ("." if owned.has(Vector2(x, y)) else "#")
		print(line)


## 桥房现有 4 个盒的声明位与原地容量（用各自盒子的真实 min_spacing / recess）。
## ⚠ `_box_placement_at` 在 `Dungeon3D` 上，不在 `DungeonRoom3D` 上。
func _dump_existing_boxes(room: DungeonRoom3D) -> void:
	print("EXIST|idx|box|center|size|recess|cap")
	var placements := room.spawn_placements
	for index in range(placements.size()):
		var norm: Dictionary = tower._box_placement_at(placements, index)
		var box_id := str(norm.get("box_id", ""))
		var box := SpawnBoxCatalog.load_box(box_id)
		var center := norm.get("box_center", Vector2.ZERO) as Vector2
		var size := norm.get("box_size", Vector2.ZERO) as Vector2
		var recess := int(norm.get("box_wall_recess_tiles", 1))
		var spacing := float(box.get("min_spacing_m", 0.0))
		var rotation := float(norm.get("box_rotation", 0.0))
		print("EXIST|%d|%s|%s|%.0fx%.0f|%d|%d" % [
			index, box_id.replace("box_", ""), _center_str(center), size.x, size.y,
			recess, _cap(room, center, size, spacing, recess, rotation),
		])


## 主表：候选砖心 × 候选盒面，报「装 16 只」的成败与 cap。
## recess 只试 0（见文件头坑 (b)：桥心唯一可行取值）；
## spacing 只试 1.7（怪体间距硬下限，最宽松口径）—— 组合数一多就会慢到被 watchdog 杀。
func _dump_fit(room: DungeonRoom3D) -> void:
	print("FIT|center_m|size|drift|fits%d|cap" % TARGET)
	for center_raw in CANDIDATE_CENTERS:
		var center := Vector2(float(center_raw[0]), float(center_raw[1]))
		for size_raw in CANDIDATE_SIZES:
			var pair := size_raw as Array
			var size := Vector2(float(pair[0]), float(pair[1]))
			var drift := room.resolve_spawn_box_center_local(
				center, size, TARGET, 0.0, FIT_SPACING, 0
			).distance_to(center)
			var fits := drift <= 0.001
			print("FIT|%s|%.0fx%.0f|%.2f|%s|%d" % [
				_center_str(center), size.x, size.y, drift,
				"OK" if fits else "no",
				_cap(room, center, size, FIT_SPACING, 0, 0.0) if fits else -1,
			])


## 盒心**不被吸附**时原地能排满 target 吗（直接拿声明盒心撒点，不走 snap）。
func _fits_direct(
	room: DungeonRoom3D, center: Vector2, size: Vector2, spacing: float, recess: int
) -> bool:
	var finite := 0
	for point in room.spawn_points_in_box(center, size, TARGET, 0.0, spacing, recess):
		if (point as Vector3).is_finite():
			finite += 1
	return finite >= TARGET


func _cap(
	room: DungeonRoom3D,
	center: Vector2,
	size: Vector2,
	spacing: float,
	recess: int,
	rotation: float
) -> int:
	var best := 0
	for count in range(1, MAX_PROBE + 1):
		if room.resolve_spawn_box_center_local(
			center, size, count, rotation, spacing, recess
		).distance_to(center) > 0.001:
			break
		var finite := 0
		for point in room.spawn_points_in_box(center, size, count, rotation, spacing, recess):
			if (point as Vector3).is_finite():
				finite += 1
		if finite < count:
			break
		best = count
	return best


func _snap(x: float, y: float) -> Vector2:
	return Vector2(roundf(x * 10.0) / 10.0, roundf(y * 10.0) / 10.0)


func _center_str(v: Vector2) -> String:
	return "[%.1f, %.1f]" % [v.x, v.y]
