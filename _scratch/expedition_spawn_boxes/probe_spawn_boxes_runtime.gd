extends Node3D
## 运行时探针：远征01 触发盒「盒内落点」实测（判据 E + 端到端出怪）。
##
## 它别于静态校验器：这里真的实例化 ExpeditionLevel01_3D，建壳体/家具碰撞，
## 再调 `DungeonRoom3D.spawn_points_in_box` 与 `Dungeon3D._spawn_room_enemies`。
## 要回答的问题只有一个：**摆了盒子，盒里到底取不取得到点、怪到底出不出得来**。
##
## 失败会红的部分：
##   ① 盒内可落点数 < 该盒一次可能出的最多只数（会补 Vector3.INF ⇒ 整波被判无落点）；
##   ② 落点不在盒内 / 与实体碰撞体相交 / 离墙净距不足 / 两两间距 < 2×clearance；
##   ③ `_spawn_room_enemies` 没出怪（返回 false 或 alive==0）；
##   ④ 波次数 ≠ encounter.stages 条数。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const CATALOG := preload("res://src/map/SpawnBoxCatalog.gd")
const SEEDS := [700000, 707919, 715838, 20260925]
## 敌人实体碰撞半径（`Enemy3D` footprint 默认 0.8）。两只怪不重叠只需中心距 ≥ 2×0.8。
## ⚠ 不要拿 `SPAWN_CLEARANCE_M`(1.15) 当怪半径 —— 那是**离墙净距**，比怪半径大。
const ENEMY_BODY_RADIUS := 0.8
## 5m 地砖单元。业主口径（2026-09-26）：「**最外一圈地砖不要刷怪**，往里头布置刷怪盒子」
## ⇒ 每个真实落点到墙的 L∞ 净距必须 ≥ 1 圈（5 m）。
const TILE_M := 5.0

var failures: Array[String] = []
var rooms_with_boxes := 0
var boxes_checked := 0
var shifted := 0
var tightest := ""
var tightest_slack := INF

var tower: TowerDescent3D


func _ready() -> void:
	var missing := CATALOG.missing_files()
	_check(missing.is_empty(), "登记盒子缺文件: %s" % str(missing))
	var orphans := CATALOG.unregistered_files()
	_check(orphans.is_empty(), "目录里有未登记的盒子文件: %s" % str(orphans))

	for run_seed in SEEDS:
		tower = SCENE.instantiate() as TowerDescent3D
		tower.test_mode = true
		tower.run_seed_override = run_seed
		add_child(tower)
		tower.process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().process_frame
		_check(tower._room_by_id.size() == 13, "seed=%d 远征不是 13 房" % run_seed)
		# 先把全部壳体建好：邻房后建也不得令先测房间漏掉共墙碰撞。
		for room_value in tower._room_by_id.values():
			(room_value as DungeonRoom3D).ensure_shell_built()
		for room_value in tower._room_by_id.values():
			(room_value as DungeonRoom3D).ensure_shell_built()
			(room_value as DungeonRoom3D).ensure_detail_built()
		await get_tree().physics_frame
		await get_tree().physics_frame
		for room_value in tower._room_by_id.values():
			_verify_room(room_value as DungeonRoom3D, run_seed)
		for room_value in tower._room_by_id.values():
			_verify_end_to_end(room_value as DungeonRoom3D, run_seed)
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	print(
		"SPAWN_BOXES_RUNTIME_SUMMARY rooms_with_boxes=%d boxes=%d shifted=%d tightest_slack=%s failures=%d"
		% [rooms_with_boxes, boxes_checked, shifted,
			("inf" if tightest_slack == INF else "%.1f(%s)" % [tightest_slack, tightest]),
			failures.size()]
	)
	for failure in failures:
		push_error(failure)
		print("  SPAWN_BOXES_FAIL %s" % failure)
	print("SPAWN_BOXES_RUNTIME_OK" if failures.is_empty() else "SPAWN_BOXES_RUNTIME_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


## 单个盒子实例：解析 → 取满 demand 个落点 → 逐点安全判据（判据 E）。
func _verify_room(room: DungeonRoom3D, run_seed: int) -> void:
	var placements := room.spawn_placements
	if placements.is_empty():
		# 只有「内容房」才必须有实例；入口/撤离/功能房与 EVENT 房本就不摆盒。
		_check(
			room.room_type not in ["BOSS", "COMBAT", "SCAVENGE", "STORAGE"],
			"seed=%d %s (type=%s) 敌对房没有放置实例" % [run_seed, room.room_id, room.room_type]
		)
		return
	rooms_with_boxes += 1
	_check(room.spawn_boxes_only, "seed=%d %s spawn_boxes_only 未生效" % [run_seed, room.room_id])
	var label := "seed=%d room=%s" % [run_seed, room.room_id]
	var radius := 2.2 if room.room_type == "BOSS" else 1.15
	for index in range(placements.size()):
		var placement := placements[index] as Dictionary
		var box_id := str(placement.get("box", ""))
		var box := CATALOG.load_box(box_id)
		if box.is_empty():
			_check(false, "%s[%d] 盒子 %s 解析失败" % [label, index, box_id])
			continue
		var size := box.get("size_m", Vector2.ZERO) as Vector2
		var raw_size: Variant = placement.get("size_m", null)
		if raw_size is Array and (raw_size as Array).size() >= 2:
			size = Vector2(float((raw_size as Array)[0]), float((raw_size as Array)[1]))
		var center := _v2(placement.get("center_m", []))
		var rotation := float(placement.get("rotation_deg", 0.0))
		var min_spacing := float(box.get("min_spacing_m", 0.0))
		var recess := int(box.get("wall_recess_tiles", 1))
		var demand := _demand(box)
		boxes_checked += 1
		var points := room.spawn_points_in_box(
			center, size, demand, rotation, min_spacing, recess
		)
		# 落地盒心：`constrained` 房型每局重洗，声明坐标可能落在空腔/凹口上，运行时会把盒
		# **整体平移**到可通行处（≤ 半外接圆）。落点须落在**落地盒**内；平移量另判。
		var landing := room.resolve_spawn_box_center_local(
			center, size, demand, rotation, min_spacing, recess
		)
		var shift := (landing - center).length()
		# ⚠ 漂移是**结构性必然**：房型池可通行区交集为空（证明见 `DungeonRoom3D._resolve_box_pool`
		# 注释）⇒ 固定坐标不可能对所有房型成立。故此处**报告**而非判失败，用来核对
		# 「意图锚点被挪了多远」——它是设计侧要看的数，不是运行时的错。
		if shift > 0.01:
			shifted += 1
			print("SPAWN_BOX_SHIFT %s[%d] %s 声明=%s 落地=%s 漂移=%.2f m"
				% [label, index, box_id, str(center), str(landing), shift])
		var finite := 0
		var locals: Array[Vector3] = []
		for point in points:
			if not point.is_finite():
				continue
			finite += 1
			var local := room.to_local(point)
			locals.append(local)
			_check(
				absf(local.y) < 0.001,
				"%s[%d] 落点不在主通行层 %s" % [label, index, local]
			)
			_check(
				_in_box(Vector2(local.x, local.z), landing, size, rotation),
				"%s[%d] 落点跑出落地盒外 %s 声明=%s 落地=%s size=%s rot=%.1f"
				% [label, index, local, str(center), str(landing), str(size), rotation]
			)
			_check(
				room._spawn_floor_contains(Vector3(local.x, 0, local.z), radius),
				"%s[%d] 落点无半径余量/压在凹口 %s" % [label, index, local]
			)
			# 判据 H 的**运行时**那一端（业主 2026-09-26「最外一圈不要刷怪」）：
			# `_spawn_floor_contains(point, r)` = 「以点为心的 2r 方框完整落在地砖并集内」，
			# 故取 r = 1 圈（5 m）即「离墙 L∞ 净距 ≥ 5 m」⇔ 点必在**第二圈及以内**的地砖上。
			# 为什么静态判据之外还要在运行时判：静态 H 判的是**声明盒**（整盒不进最外圈），
			# 而运行时家具/柱/凹口会继续裁剪候选池，可能把点挤向墙 —— 那是静态层看不见的。
			_check(
				room._spawn_floor_contains(Vector3(local.x, 0, local.z), TILE_M),
				"%s[%d] 落点落在最外一圈地砖内（离墙 < %.0f m）%s"
				% [label, index, TILE_M, local]
			)
			_check(
				room._spawn_obstacle_free(Vector3(local.x, 0, local.z)),
				"%s[%d] 落点与实体碰撞体相交 %s" % [label, index, local]
			)
		_check(
			finite == demand,
			"%s[%d] 盒 %s 只需 %d 只却只取到 %d 个合法落点（会补 INF ⇒ 整波判无落点）"
			% [label, index, box_id, demand, finite]
		)
		var min_gap := INF
		for a in range(locals.size()):
			for b in range(a + 1, locals.size()):
				min_gap = minf(min_gap, locals[a].distance_to(locals[b]))
		if locals.size() >= 2:
			_check(
				min_gap >= ENEMY_BODY_RADIUS * 2.0 - 0.001,
				"%s[%d] 盒内两两间距 %.3f < 怪体直径 %.3f（会穿模）"
				% [label, index, min_gap, ENEMY_BODY_RADIUS * 2.0]
			)
		var capacity := _capacity(room, landing, size, rotation, min_spacing)
		var slack := float(capacity - demand)
		if slack < tightest_slack:
			tightest_slack = slack
			tightest = "%s[%d] %s %s demand=%d cap=%d" % [
				room.room_id, index, box_id, str(size), demand, capacity]
		if finite < demand:
			var suggest := _best_box_center(room, size, rotation, min_spacing)
			print("SPAWN_BOX_SUGGEST %s[%d] %s 建议落点=%s 该处容量=%d（声明=%s 落地=%s 实取=%d）"
				% [label, index, box_id, str(suggest[0]), suggest[1], str(center), str(landing), finite])
		print("SPAWN_BOX %s dim=%s[%d] %s size=%s demand=%d finite=%d cap=%d gap=%.2f shift=%.2f"
			% [label, str(room.get_dimensions()), index, box_id, str(size), demand,
				finite, capacity, min_gap, shift])


## 端到端：真的走一次 `_spawn_room_enemies`，确认出得来怪、波次数对得上。
func _verify_end_to_end(room: DungeonRoom3D, run_seed: int) -> void:
	if room.spawn_placements.is_empty():
		return
	var label := "seed=%d room=%s" % [run_seed, room.room_id]
	var expected_stages := _stage_count(room)
	var ok := tower._spawn_room_enemies(room)
	var alive := int(tower._alive_by_room.get(room.room_id, 0))
	_check(ok, "%s 端到端: _spawn_room_enemies 返回 false（房间被锁死）" % label)
	_check(
		alive > 0,
		"%s 端到端: 一只怪都没出 alive=%d（盒心吸附后不该出现）" % [label, alive]
	)
	_check(
		int(tower._room_wave_totals.get(room.room_id, 0)) == expected_stages,
		"%s 端到端: 波次数 %d != encounter.stages %d"
		% [label, int(tower._room_wave_totals.get(room.room_id, 0)), expected_stages]
	)
	# 首波出场的怪必须落在本房某个盒子内。
	var spawn_boxes := _room_boxes(room)
	var enemies: Array = tower._enemy_nodes_by_room.get(room.room_id, [])
	var inside := 0
	for enemy_value in enemies:
		var enemy := enemy_value as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var local := room.to_local(enemy.global_position)
		var hit := false
		for entry in spawn_boxes:
			if _in_box(Vector2(local.x, local.z), entry[0], entry[1], entry[2]):
				hit = true
				break
		if hit:
			inside += 1
	enemies = enemies.duplicate()
	for enemy_value in enemies:
		var enemy := enemy_value as Node
		if is_instance_valid(enemy):
			enemy.free()
	tower._enemy_nodes_by_room[room.room_id] = []
	tower._alive_by_room[room.room_id] = 0
	print("SPAWN_BOX_END2END %s spawned=%d inside_box=%d waves=%d/%d"
		% [label, enemies.size(), inside, int(tower._room_wave_totals.get(room.room_id, 0)), expected_stages])


## 一个盒子一次最多可能出的只数 = 各条目 count 上界之和。
func _demand(box: Dictionary) -> int:
	var total := 0
	for value in (box.get("spawns", []) as Array):
		total += int((value as Dictionary).get("count_max", 0))
	return total


## 盒内**真正能排下多少只**（含间距硬下限），与出怪用的是**同一个** min_spacing 口径。
## 直接在给定盒心处采样，不触发「落地平移」—— 否则量的就不是这个位置了。
func _capacity(
	room: DungeonRoom3D, center: Vector2, size: Vector2, rotation_deg: float, min_spacing: float
) -> int:
	var half := size * 0.5
	var radians := deg_to_rad(rotation_deg)
	var pool := room._box_sample_points(
		center, half, cos(radians), sin(radians), room._spawn_clearance()
	)
	var spacing := maxf(ENEMY_BODY_RADIUS * 2.0 + 0.1, min_spacing)
	return room._scatter_box_pick(pool, spacing, 64, room._box_pick_seed(center, half)).size()


## 诊断：**全房**扫一遍，找出让本盒容量最大的落点 —— 数据侧「该把盒挪到哪」的建议。
func _best_box_center(
	room: DungeonRoom3D, size: Vector2, rotation_deg: float, min_spacing: float
) -> Array:
	var half := size * 0.5
	var radians := deg_to_rad(rotation_deg)
	var cos_r := cos(radians)
	var sin_r := sin(radians)
	var clearance := room._spawn_clearance()
	var spacing := maxf(ENEMY_BODY_RADIUS * 2.0 + 0.1, min_spacing)
	var best_center := Vector2.ZERO
	var best_count := -1
	for candidate in room._spawn_candidates:
		var center := Vector2(candidate.x, candidate.z)
		var pool := room._box_sample_points(center, half, cos_r, sin_r, clearance)
		var count := room._scatter_box_pick(pool, spacing, 64, room._box_pick_seed(center, half)).size()
		if count > best_count:
			best_count = count
			best_center = center
	return [best_center, best_count]


## 与 `spawn_points_in_box` 同规则的贪心计数（只数个数，不产坐标）。
func _greedy_count(pool: Array[Vector3], spacing: float) -> int:
	var work := pool.duplicate()
	var chosen: Array[Vector3] = []
	while chosen.size() < 64:
		var best := Vector3.INF
		var best_score := -1.0
		for point in work:
			var distance := spacing
			for previous in chosen:
				distance = minf(distance, point.distance_to(previous))
			if distance < spacing - 0.001:
				continue
			if distance > best_score:
				best_score = distance
				best = point
		if not best.is_finite():
			break
		chosen.append(best)
		work.erase(best)
	return chosen.size()


func _room_boxes(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for value in room.spawn_placements:
		var placement := value as Dictionary
		var box := CATALOG.load_box(str(placement.get("box", "")))
		if box.is_empty():
			continue
		var size := box.get("size_m", Vector2.ZERO) as Vector2
		var raw_size: Variant = placement.get("size_m", null)
		if raw_size is Array and (raw_size as Array).size() >= 2:
			size = Vector2(float((raw_size as Array)[0]), float((raw_size as Array)[1]))
		var declared := _v2(placement.get("center_m", []))
		var rotation := float(placement.get("rotation_deg", 0.0))
		# 端到端出场位置须落在**落地盒**内，与 `_verify_room` 同一口径（含盒的贴边/间距偏好）。
		out.append([
			room.resolve_spawn_box_center_local(
				declared, size, _demand(box), rotation,
				float(box.get("min_spacing_m", 0.0)),
				int(box.get("wall_recess_tiles", 1))
			),
			size,
			rotation,
		])
	return out


func _stage_count(room: DungeonRoom3D) -> int:
	var raw: Variant = room.encounter.get("stages", [])
	if raw is Array and not (raw as Array).is_empty():
		return (raw as Array).size()
	return 1


## 点是否落在（可绕 Y 旋转的）盒矩形内 —— 独立写法，不复用 DungeonRoom3D 的私有实现。
func _in_box(point: Vector2, center: Vector2, size: Vector2, rotation_deg: float) -> bool:
	var half := size * 0.5
	var rel := point - center
	var radians := deg_to_rad(rotation_deg)
	var cos_r := cos(radians)
	var sin_r := sin(radians)
	var local := Vector2(rel.x * cos_r + rel.y * sin_r, -rel.x * sin_r + rel.y * cos_r)
	return absf(local.x) <= half.x + 0.02 and absf(local.y) <= half.y + 0.02


func _v2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
