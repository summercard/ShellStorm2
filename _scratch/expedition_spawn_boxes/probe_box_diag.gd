extends Node3D
## 定点诊断：为什么「声明盒心」容量判定为假（触发落地平移）。
##
## 对每个盒实例逐项倒出：声明心 / 吸附心 / 池点（房局部）/ 采样步 / 净距 / 间距硬下限 /
## 需求量 / 种子 / 「声明心能否排下 demand 只」。用于分辨两类根因：
##   ① 池点几何本身不够（家具/凹口把池压窄）→ 数据侧挪盒或缩盒；
##   ② 池点够宽，但贪心因随机序取不满 → 机制侧。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const CATALOG := preload("res://src/map/SpawnBoxCatalog.gd")
const ENEMY_BODY_RADIUS := 0.8

var tower: TowerDescent3D


func _ready() -> void:
	var seed_text := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		seed_text = str(user_args[0])
	var SEED := 77001199
	if not seed_text.is_empty() and seed_text.is_valid_int():
		SEED = int(seed_text)
	print("[diag] boot seed=%d" % SEED)
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	for room_value in tower._room_by_id.values():
		var room := room_value as DungeonRoom3D
		room.ensure_shell_built()
		room.ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	for room_value in tower._room_by_id.values():
		var room := room_value as DungeonRoom3D
		if room.spawn_placements.is_empty():
			continue
		# 与真机同序：先把本房实体障碍收集齐（`resolve_spawn_box_center_local` 内部会做，
		# 直接调 `_box_sample_points` 则不会）—— 否则池点会比真机乐观。
		if room._spawn_candidates.is_empty():
			room._build_spawn_points()
		room._collect_spawn_blockers()
		for index in range(room.spawn_placements.size()):
			var placement := tower.call("_box_placement_at", room.spawn_placements, index) as Dictionary
			if placement.is_empty():
				continue
			var box_id := str(placement["box"])
			var box := CATALOG.load_box(box_id)
			var center := placement["box_center"] as Vector2
			var size := placement["box_size"] as Vector2
			var rotation := float(placement["box_rotation"])
			var min_spacing := float(box.get("min_spacing_m", 0.0))
			var recess := int(box.get("wall_recess_tiles", 1))
			var demand := _demand(box)
			var snapped := room.snap_box_center_to_tile(center, recess)
			var half := size * 0.5
			var radians := deg_to_rad(rotation)
			var cos_r := cos(radians)
			var sin_r := sin(radians)
			var clearance := room._spawn_clearance()
			var pool := room._box_sample_points(snapped, half, cos_r, sin_r, clearance)
			var spacing := maxf(ENEMY_BODY_RADIUS * 2.0 + 0.1, min_spacing)
			var seed_value := room._box_pick_seed(snapped, half)
			var fits := room._fits_in_box(pool, spacing, demand, seed_value)
			if fits and (snapped - center).length() < 0.01:
				continue  # 正常盒，不打印
			var pts := ""
			for p in pool:
				pts += "(%.1f,%.1f)" % [p.x, p.z]
			var picked := room._scatter_box_pick(pool, spacing, demand, seed_value)
			var pick_n := picked.size()
			var chosen_txt := ""
			for p in picked:
				chosen_txt += "(%.1f,%.1f)" % [p.x, p.z]
			var max_pair := 0.0
			for a in range(pool.size()):
				for b in range(a + 1, pool.size()):
					max_pair = maxf(max_pair, pool[a].distance_to(pool[b]))
			print("[diag] %-10s #%-2d %-20s decl=(%.1f,%.1f) snapped=(%.1f,%.1f) size=(%.1f,%.1f) rot=%.0f"
				% [room.room_id, index, box_id, center.x, center.y, snapped.x, snapped.y, size.x, size.y, rotation])
			print("        clearance=%.2f spacing=%.2f demand=%d fits=%s pick=%d pool=%d maxpair=%.2f chosen=%s"
				% [clearance, spacing, demand, str(fits), pick_n, pool.size(), max_pair, chosen_txt])
			print("        pool=%s" % pts)
	get_tree().quit(0)


func _demand(box: Dictionary) -> int:
	var total := 0
	for spawn_value in (box.get("spawns", []) as Array):
		var spawn := spawn_value as Dictionary
		total += int(spawn.get("count_max", int(spawn.get("count_min", 0))))
	return total
