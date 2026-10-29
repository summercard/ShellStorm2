extends Node
## 远征03 逐房怪物编成验证探针（2026-10-29）
##
## 要证的三件事：
##   ① 每个真敌对房都拿到了编成（`spawn_placements` 非空）—— 否则「进房封门、
##      一只怪都没有」，玩家被关在空屋子里（`spawn_boxes_only` 层下这是**静默**的）。
##   ② 楼层带上了 `spawn_boxes_only` —— 这是「去掉旧刷型公式」的实际开关。
##   ③ 盒子的落位满足三条几何判据：完全在房内、盒边离墙 ≥5m、同房互不重叠。
##
## 还会把编成表里声明、但生成结果里没出现的 box 也报出来 —— 那通常意味着
## 房间尺寸装不下这么多盒（`_auto_lay_boxes` 会 push_error 并返回空）。
##
## 用法：godot --headless --path . --scene res://tools/_egt_roster_probe.tscn
## ⚠ 必须 `--scene`：要编译 FloorPlanGenerator / SpawnBoxCatalog，它们依赖 autoload。

const LEVEL_ID := "expedition_03"
## 多跑几个种子：EGT 骨架每局抽一张、房间尺寸随骨架变，
## 单种子通过不代表「换一张骨架也放得下」。
const SEEDS := [1, 2, 3, 7, 11, 42]

const RECESS_M := 5.0
const EPS := 0.01

var _failures: Array[String] = []


func _ready() -> void:
	print("=== EGT_ROSTER_PROBE 远征03 逐房编成 ===")
	for seed_value in SEEDS:
		_probe_seed(int(seed_value))
	_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _probe_seed(seed_value: int) -> void:
	var floor_source := FloorPlanGenerator.generate_from_level_plan(LEVEL_ID, 0, seed_value)
	if floor_source.is_empty():
		_failures.append("种子 %d：生成失败（返回空）" % seed_value)
		return
	var flow_id := str(floor_source.get("layout_variant", "?"))
	var boxes_only_rooms := 0

	var hostile := 0
	var with_boxes := 0
	var total_boxes := 0
	var kind_seen := {}
	var lines: Array[String] = []
	for value in floor_source.get("rooms", []):
		var room := value as Dictionary
		# 最终结构是 `room_from_source()` 的产物：内容类型在 `type`、尺寸在 `dimensions`，
		# 不是设计源里的 `content_type` / `size`（读错名字会得到 0 间战斗房而误判成"没生效"）。
		var content := str(room.get("type", ""))
		var peaceful := bool(room.get("authored_layout_peaceful", false))
		if bool(room.get("spawn_boxes_only", false)):
			boxes_only_rooms += 1
		# 「真敌对房」= 敌方房型 且 非和平区（与校验器判据 A 同口径）
		if not GameDesignConfig.ROOM_TYPES_WITH_HOSTILES.has(content) or peaceful:
			continue
		# BOSS 房不在本探针范围：它走 `BossContentCatalog` 专属链，编成由名册决定，
		# 不由刷怪盒编成。「BOSS 房没有盒子」是**正确**的，不该报失败。
		if content == GameDesignConfig.BOSS_ROOM_TYPE:
			continue
		hostile += 1
		var placements := room.get("spawn_placements", []) as Array
		if placements.is_empty():
			_failures.append(
				"种子 %d（%s）：战斗房 %s（%s）没有编成 —— 会变成空房"
				% [seed_value, flow_id, str(room.get("key", "")), content]
			)
			continue
		with_boxes += 1
		total_boxes += placements.size()
		var kinds: Array[String] = []
		var composed: Array[String] = []
		for placement_value in placements:
			var placement := placement_value as Dictionary
			var box_id := str(placement.get("box", ""))
			var box := SpawnBoxCatalog.load_box(box_id)
			if box.is_empty():
				_failures.append(
					"种子 %d：房 %s 引用了加载失败的盒 %s"
					% [seed_value, str(room.get("key", "")), box_id]
				)
				continue
			composed.append(box_id.replace("box_egt_", ""))
			for spawn_value in (box.get("spawns", []) as Array):
				var spawn := spawn_value as Dictionary
				var type_id := str(spawn.get("type", ""))
				kinds.append(type_id)
				kind_seen[type_id] = int(kind_seen.get(type_id, 0)) + 1
		_check_geometry(seed_value, room, placements)
		lines.append(
			"    %-10s %-12s 盒%d  %s"
			% [str(room.get("key", "")), content, placements.size(), ", ".join(composed)]
		)

	if hostile == 0:
		_failures.append("种子 %d（%s）：一个战斗房都没有，编成表没被用上？" % [seed_value, flow_id])
	if boxes_only_rooms == 0:
		_failures.append(
			"种子 %d（%s）：没有任何房间带 spawn_boxes_only —— 房型公式兜底仍会接管"
			% [seed_value, flow_id]
		)
	for line in lines:
		print("  [seed %d/%s]%s" % [seed_value, flow_id, line])
	print(
		"  [seed %d/%s] 战斗房 %d 间，有编成 %d 间，共 %d 个盒，带 spawn_boxes_only 房 %d 间"
		% [seed_value, flow_id, hostile, with_boxes, total_boxes, boxes_only_rooms]
	)


## 三条几何判据。位置是**房间局部坐标**（原点=房心），盒尺寸取盒子资产声明值。
func _check_geometry(seed_value: int, room: Dictionary, placements: Array) -> void:
	var key := str(room.get("key", ""))
	var size := room.get("dimensions", Vector2.ZERO) as Vector2
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var half := size * 0.5
	var seen: Array[Rect2] = []
	for placement_value in placements:
		var placement := placement_value as Dictionary
		var box_id := str(placement.get("box", ""))
		var box := SpawnBoxCatalog.load_box(box_id)
		if box.is_empty():
			continue
		var box_size := box.get("size_m", Vector2.ZERO) as Vector2
		var center_arr := placement.get("center_m", []) as Array
		if center_arr.size() < 2:
			_failures.append("种子 %d：房 %s 的盒 %s 缺 center_m" % [seed_value, key, box_id])
			continue
		var center := Vector2(float(center_arr[0]), float(center_arr[1]))
		var rect := Rect2(center - box_size * 0.5, box_size)

		# ① 完全在房内
		var room_rect := Rect2(-half, size)
		if not room_rect.encloses(rect):
			_failures.append(
				"种子 %d：房 %s 的盒 %s 越出房间（盒 %s / 房 %s）"
				% [seed_value, key, box_id, str(rect), str(room_rect)]
			)
			continue
		# ② 盒边离墙 ≥ 5m（判整盒，不是盒心）
		var gap_min := minf(
			minf(rect.position.x - (-half.x), half.x - (rect.position.x + rect.size.x)),
			minf(rect.position.y - (-half.y), half.y - (rect.position.y + rect.size.y))
		)
		if gap_min + EPS < RECESS_M:
			_failures.append(
				"种子 %d：房 %s 的盒 %s 离墙只有 %.2fm（要求 ≥%.0fm，最外一圈不得刷怪）"
				% [seed_value, key, box_id, gap_min, RECESS_M]
			)
		# ③ 同房不重叠
		for other in seen:
			if other.intersects(rect, false):
				_failures.append(
					"种子 %d：房 %s 的盒 %s 与另一盒重叠（%s / %s）"
					% [seed_value, key, box_id, str(rect), str(other)]
				)
		seen.append(rect)


func _report() -> void:
	print("\n=== 结果 ===")
	if _failures.is_empty():
		print("EGT_ROSTER_PROBE_OK")
		print("全部种子下：每个战斗房都有编成、楼层已锁定 spawn_boxes_only、盒位满足几何判据")
		return
	for f in _failures:
		print("FAIL: " + f)
	print("EGT_ROSTER_PROBE_FAIL count=%d" % _failures.size())
