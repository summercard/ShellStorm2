extends Node
## 远征01「逐盒加量曲线」回归门禁。
##
## 背景：业主 2026-09-29 要求「从 room_03 起第一波每盒多刷、第二波每盒再多刷，
## 到 room_10 第二波每盒 10 只」。原口径（每盒线性加 2/4）总需求 244 只，超出
## 实测物理容量 159 只 —— 超出部分会被 `_collect_box_stage_entries` 按有限落点
## **静默截断**（「改了数据游戏里没变多」）。裁定改走**单调平滑曲线**：逐房总量
## T = [13,14,15,16,16,17,17,17]（合计 125），按波容量比分配、逐盒夹到容量、单调修复。
##
## 本门禁盯的是**跨文件契约**（数据 `floor_00.json` ↔ 运行时 `Dungeon3D`）。
## 契约断了必须红：
##   A `spawn_placements[].count_bonus`（数据）→ `_box_placement_at` 的
##     `box_count_bonus`（运行时）归一。少这一处映射，增量就静默失效。
##   B 增量只落在**首条非 elite/boss 条目**。加到身份条目上会把「1 只精英」变
##     N 只，是阶跃式难度跳变，不是「多刷几只怪」。
##   C 逐盒实到普通怪 ∈ [设计下限, 设计上限]。跌破下限 = 盒容量不足、运行时
##     静默截断；超出上限 = 增量重复叠加。
##   D 数据侧曲线：逐房设计总量（含身份条目）= 曲线目标，且 room_03 起单调不减。
##   E 加量盒必须**原地排得下**（drift == 0）—— 曲线是容量夹出来的，若某个加量盒
##     靠「落地平移」才排得下，就说明曲线越了容量，落地后盒心漂移、可能与邻盒互叠。
##   F 全关 drift>0 的盒**恰好**是已知存量欠账三条（见 `PINNED_DRIFT`）。新增一条即红。
##
## 口径：seed = `run_seed ^ room.hash ^ 0x424f5831`，复刻 `_spawn_box_waves` 的 rng 消费顺序。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199

## 曲线目标：逐房设计总量（含 elite/boss 身份条目），room_01/02 不在加量范围。
##
## ⚠ **room_05 = 31 是刻意的峰值，不是曲线破口**：业主 2026-09-29 点名在桥心加
## `box_bridge_center`（一次压 16 只，见 `data/spawn_boxes/box_bridge_center.json`），
## 于是本房 15 → 31。桥房是本关唯一的立体战斗空间、主路必经的窄口，**本来该是难度尖峰**，
## 故它**从单调链里摘出**（见 `RAMP_MONOTONE_ORDER`），单独钉目标值。
const RAMP_TARGET := {
	"room_03": 13, "room_04": 14, "room_05": 31, "room_06": 16,
	"room_07": 16, "room_08": 17, "room_09": 17, "room_10": 17,
}
## 单调不减校验的房序列（room_03 起）。**room_05 已被摘出** —— 见 `RAMP_TARGET` 上方的注：
## 峰值房不参与相邻比较，但「链上其余房单调不减」这条不许松。
const RAMP_MONOTONE_ORDER: Array[String] = [
	"room_03", "room_04", "room_06",
	"room_07", "room_08", "room_09", "room_10",
]
## 曲线目标的房序列（room_03 起，**含**峰值房 room_05）—— 用于「盒数 / 逐实例增量 / 逐房总量」核对。
const RAMP_ORDER: Array[String] = [
	"room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10",
]
## 这 8 房的逐实例 `count_bonus` 期望值（数据面唯一真源的镜像，改数据必须同步这里）。
const EXPECTED_BONUS := {
	"room_03": [1, 0, 1, 1],
	"room_04": [2, 1, 1, 0],
	# room_05：第 5 个实例是 `box_bridge_center`（桥心压制盒），靠自带 16 只出量、不吃增量。
	"room_05": [1, 0, 2, 2, 0],
	"room_06": [1, 2, 3, 0],
	"room_07": [6, 2, 2],
	"room_08": [1, 1, 1, 2, 0],
	"room_09": [0, 0, 3, 4],
	"room_10": [0, 5, 3, 0],
}
## 逐实例 `count_multiplier` 期望值（**与 `count_bonus` 同一条隐形契约**：数据层写、
## 运行层读，归一在 `_box_placement_at`）。room_01/02 业主 2026-09-29 口径「每个盒子里数量翻倍」
## ⇒ 全盒 ×2；其余房不得顺手写（UNTOUCHED_ROOMS 侧并查 0）。
const EXPECTED_MULTIPLIER := {
	"room_01": [2, 2, 2],
	"room_02": [2, 2, 2, 2],
}
## 未加量房：逐实例 `count_bonus` 必须 0，防「顺手也加了」。
## （`room_01` / `room_02` 的翻倍走 `count_multiplier`，不在此判据内 —— 见 `EXPECTED_MULTIPLIER`。）
const UNTOUCHED_ROOMS: Array[String] = ["room_01", "room_02", "boss"]
## 已知存量欠账：声明盒心容量为 0、只能靠「落地平移」出怪的盒（**非本次改动引入**）。
## 逐条 = 房 key → {实例下标: 漂移米}。任何一条消失要缩表，任何一条新增要红。
const PINNED_DRIFT := {
	"room_04": {3: 5.00},
	"room_08": {4: 20.00},
	"boss": {1: 0.63},
}

var failures: Array[String] = []
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

	_verify_bonus_field()
	_verify_multiplier_field()
	_verify_counts()
	_verify_drift()
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("EXPEDITION01_SPAWN_RAMP_OK ramped_rooms=%d" % RAMP_ORDER.size())
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
		print("  EXPEDITION01_SPAWN_RAMP_FAIL %s" % failure)
	get_tree().quit(1)


# ============================================================
# A / B：数据字段 → 运行时归一 + 增量落点
# ============================================================

func _verify_bonus_field() -> void:
	for key in RAMP_ORDER:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			_check(false, "找不到 %s" % key)
			continue
		var placements := room.spawn_placements
		var expected := EXPECTED_BONUS[key] as Array
		_check(
			placements.size() == expected.size(),
			"%s 盒数 %d ≠ 曲线口径 %d（改盒 = 改放置层，必须同步曲线与本门禁）"
				% [key, placements.size(), expected.size()]
		)
		for index in range(mini(placements.size(), expected.size())):
			var raw := placements[index] as Dictionary
			var want := int(expected[index])
			_check(
				int(raw.get("count_bonus", 0)) == want,
				"%s#%d 数据 count_bonus=%d ≠ 曲线 %d"
					% [key, index, int(raw.get("count_bonus", 0)), want]
			)
			# A：归一映射 —— 运行时只读 `box_count_bonus`。
			var resolved := tower._box_placement_at(placements, index)
			_check(
				int(resolved.get("box_count_bonus", -1)) == want,
				"%s#%d 运行时 box_count_bonus=%s ≠ %d（`_box_placement_at` 归一映射断了）"
					% [key, index, str(resolved.get("box_count_bonus", "<缺>")), want]
			)
			# B：增量必须落在首条非 elite/boss 条目上。
			_verify_bonus_lands_on_grunt(key, index, raw, resolved)
	for key in UNTOUCHED_ROOMS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			continue
		for index in range((room.spawn_placements as Array).size()):
			var raw := room.spawn_placements[index] as Dictionary
			_check(
				int(raw.get("count_bonus", 0)) == 0,
				"%s#%d 不在加量范围却有 count_bonus=%s"
					% [key, index, str(raw.get("count_bonus"))]
			)


## 复刻运行时的「加量落点」判定：增量只能吃在首条 type 非 elite/boss 的条目上。
func _verify_bonus_lands_on_grunt(
	key: String, index: int, raw: Dictionary, resolved: Dictionary
) -> void:
	var bonus := int(resolved.get("box_count_bonus", 0))
	if bonus <= 0:
		return
	var box := SpawnBoxCatalog.load_box(str(raw.get("box", "")))
	var grunt := -1
	for i in range((box.get("spawns", []) as Array).size()):
		var spawn := (box.get("spawns", []) as Array)[i] as Dictionary
		var type_id := str(spawn.get("type", ""))
		if type_id == "elite" or type_id == "boss":
			continue
		if int(spawn.get("count_max", spawn.get("count_min", 0))) > 0:
			grunt = i
			break
	_check(
		grunt >= 0,
		"%s#%d 有增量 %d 却没有可承载的普通怪条目（增量会静默丢失）" % [key, index, bonus]
	)


# ============================================================
# G：逐实例倍率 —— room_01 / room_02 的「翻倍」靠它，不靠 `count_bonus`
# ============================================================

## 与 A 同构：数据 `count_multiplier` → 运行时 `box_count_multiplier` 的归一映射必须通，
## 且「倍率要生效就必须有可承载的普通怪条目」（否则乘了也没条目可乘 ⇒ 静默失效）。
## 这一族与 `LevelPlanValidator` 的判据 L② 互补：那里管**取值范围**，这里管**设计意图值**。
func _verify_multiplier_field() -> void:
	for key in EXPECTED_MULTIPLIER.keys():
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			_check(false, "找不到 %s" % key)
			continue
		var placements := room.spawn_placements
		var expected := EXPECTED_MULTIPLIER[key] as Array
		_check(
			placements.size() == expected.size(),
			"%s 盒数 %d ≠ 倍率口径 %d（改盒 = 改放置层，必须同步本门禁）"
				% [key, placements.size(), expected.size()]
		)
		for index in range(mini(placements.size(), expected.size())):
			var raw := placements[index] as Dictionary
			var want := int(expected[index])
			_check(
				int(raw.get("count_multiplier", 1)) == want,
				"%s#%d 数据 count_multiplier=%d ≠ 口径 %d"
					% [key, index, int(raw.get("count_multiplier", 1)), want]
			)
			var resolved := tower._box_placement_at(placements, index)
			_check(
				int(resolved.get("box_count_multiplier", -1)) == want,
				"%s#%d 运行时 box_count_multiplier=%s ≠ %d（`_box_placement_at` 归一映射断了）"
					% [key, index, str(resolved.get("box_count_multiplier", "<缺>")), want]
			)
			_check(
				_box_has_grunt(SpawnBoxCatalog.load_box(str(raw.get("box", "")))),
				"%s#%d 有倍率 %d 却没有可承载的普通怪条目（倍率会静默丢失）" % [key, index, want]
			)
	# 其余房不得「顺手也乘了」。
	for room_key in tower._room_by_id.keys():
		var other := tower._room_by_id.get(room_key) as DungeonRoom3D
		if other == null or EXPECTED_MULTIPLIER.has(str(room_key)):
			continue
		for index in range((other.spawn_placements as Array).size()):
			var raw := other.spawn_placements[index] as Dictionary
			_check(
				int(raw.get("count_multiplier", 1)) == 1,
				"%s#%d 不在翻倍范围却有 count_multiplier=%s"
					% [room_key, index, str(raw.get("count_multiplier"))]
			)


## 盒内是否有可承载增量/倍率的**普通怪条目**（首条非 elite/boss 且计数 > 0）。
func _box_has_grunt(box: Dictionary) -> bool:
	for spawn_value in (box.get("spawns", []) as Array):
		var spawn := spawn_value as Dictionary
		var type_id := str(spawn.get("type", ""))
		if type_id == "elite" or type_id == "boss":
			continue
		if int(spawn.get("count_max", spawn.get("count_min", 0))) > 0:
			return true
	return false


# ============================================================
# C / D：逐盒实到数 + 数据侧曲线
# ============================================================

func _verify_counts() -> void:
	var totals := {}
	for key in RAMP_ORDER:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			continue
		var agg := _replay_room(room, key)
		# D：数据侧曲线（确定性，与 rng 无关）。
		var design := int(agg["design_total"])
		totals[key] = design
		_check(
			design == int(RAMP_TARGET[key]),
			"%s 数据侧设计总量 %d ≠ 曲线目标 %d" % [key, design, int(RAMP_TARGET[key])]
		)
		# C 的汇总口径：实到普通怪必须落在数据侧区间带内。
		_check(
			int(agg["realized"]) >= int(agg["grunt_lo_total"]),
			"%s 实到普通怪 %d < 区间带下限 %d（盒容量不足，运行时静默截断）"
				% [key, int(agg["realized"]), int(agg["grunt_lo_total"])]
		)
		_check(
			int(agg["realized"]) <= int(agg["grunt_hi_total"]),
			"%s 实到普通怪 %d > 区间带上限 %d（增量重复叠加？）"
				% [key, int(agg["realized"]), int(agg["grunt_hi_total"])]
		)
	# D：单调不减 —— 只跑 `RAMP_MONOTONE_ORDER`（峰值房 room_05 已摘出，见常量注释）。
	var previous_design := -1
	var previous_key := "—"
	for key in RAMP_MONOTONE_ORDER:
		var design := int(totals.get(key, -1))
		_check(
			design >= previous_design,
			"%s 设计总量 %d 比前一房 %s 的 %d 低（曲线必须单调不减）"
				% [key, design, previous_key, previous_design]
		)
		previous_design = design
		previous_key = key


## 复刻 `_spawn_box_waves`：逐盒调 `_collect_box_stage_entries`，逐盒比对设计区间。
func _replay_room(room: DungeonRoom3D, key: String) -> Dictionary:
	var placements := room.spawn_placements
	var stages := tower._resolve_encounter_stages(room.encounter, placements.size())
	var floor_number := maxi(1, tower.visual_theme.difficulty_rank)
	var denom := maxf(1.0, float(tower._records.size() - 1))
	var floor_level := clampi(int(float(tower._record_index(room.room_id)) / denom * 3.0), 0, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = tower.run_seed ^ room.room_id.hash() ^ 0x424f5831
	var realized := 0
	var design_total := 0
	var grunt_lo_total := 0
	var grunt_hi_total := 0
	# 先算一遍逐盒设计区间（含未进任何波的盒：也算进曲线，盒摆着就是容量预算）。
	for raw_value in placements:
		var raw := raw_value as Dictionary
		var bounds := _design_bounds(
			SpawnBoxCatalog.load_box(str(raw.get("box", ""))), int(raw.get("count_bonus", 0))
		)
		design_total += int(bounds["hi"])
		grunt_lo_total += int(bounds["lo"]) - int(bounds["id"])
		grunt_hi_total += int(bounds["hi"]) - int(bounds["id"])
	for stage_value in stages:
		for instance_value in (stage_value as Array):
			var idx := int(instance_value)
			if idx < 0 or idx >= placements.size():
				continue
			var placement := placements[idx] as Dictionary
			var bounds := _design_bounds(
				SpawnBoxCatalog.load_box(str(placement.get("box", ""))),
				int(placement.get("count_bonus", 0))
			)
			var entries: Array[Dictionary] = []
			tower._collect_box_stage_entries(
				room, placements, idx, floor_number, floor_level, rng, entries
			)
			var got := entries.size() - _id_realized(entries)
			realized += got
			var grunt_lo := int(bounds["lo"]) - int(bounds["id"])
			var grunt_hi := int(bounds["hi"]) - int(bounds["id"])
			_check(
				got >= grunt_lo,
				"%s#%d 实到普通怪 %d < 设计下限 %d —— 盒容量不足，运行时静默截断"
					% [key, idx, got, grunt_lo]
			)
			_check(
				got <= grunt_hi,
				"%s#%d 实到普通怪 %d > 设计上限 %d（增量重复叠加？）"
					% [key, idx, got, grunt_hi]
			)
	return {
		"realized": realized,
		"design_total": design_total,
		"grunt_lo_total": grunt_lo_total,
		"grunt_hi_total": grunt_hi_total,
	}


# ============================================================
# E / F：加量盒必须原地排得下；drift 集合必须恰好是存量欠账
# ============================================================

func _verify_drift() -> void:
	var drifted := {}
	for room_key in tower._room_by_id.keys():
		var room := tower._room_by_id.get(room_key) as DungeonRoom3D
		if room == null:
			continue
		var placements := room.spawn_placements
		for index in range(placements.size()):
			var placement := placements[index] as Dictionary
			var box := SpawnBoxCatalog.load_box(str(placement.get("box", "")))
			if box.is_empty():
				continue
			var size := box.get("size_m", Vector2.ZERO) as Vector2
			var raw_size: Variant = placement.get("size_m", null)
			if raw_size is Array and (raw_size as Array).size() >= 2:
				size = Vector2(float((raw_size as Array)[0]), float((raw_size as Array)[1]))
			var center := _vec2(placement.get("center_m", []))
			var rotation := float(placement.get("rotation_deg", 0.0))
			var spacing := float(box.get("min_spacing_m", 0.0))
			var recess := int(box.get("wall_recess_tiles", SpawnBoxCatalog.DEFAULT_WALL_RECESS_TILES))
			# 用「本盒在该房的设计出怪量」问一次：原地放得下吗？
			var want := maxi(1, int(placement.get("count_bonus", 0)) + 1)
			var resolved := room.resolve_spawn_box_center_local(
				center, size, want, rotation, spacing, recess
			)
			var drift := resolved.distance_to(center)
			if drift <= 0.001:
				continue
			if not drifted.has(room_key):
				drifted[room_key] = {}
			(drifted[room_key] as Dictionary)[index] = drift
			# E：**加量盒**（count_bonus > 0）靠平移才排得下 ⇒ 曲线越容量，必红。
			_check(
				int(placement.get("count_bonus", 0)) == 0,
				"%s#%d 是加量盒（bonus=%d）却要平移 %.2f m 才排得下 —— 曲线越了容量"
					% [room_key, index, int(placement.get("count_bonus", 0)), drift]
			)
	# F：drift 集合与存量欠账逐条对齐 —— 少了要缩表，多了要红。
	var pinned_keys := PINNED_DRIFT.keys()
	for room_key in drifted.keys():
		_check(
			pinned_keys.has(room_key),
			"新出现漂移盒：%s（不在已知欠账清单里，实测 %s）"
				% [room_key, JSON.stringify(drifted[room_key])]
		)
		if not pinned_keys.has(room_key):
			continue
		var expected := PINNED_DRIFT[room_key] as Dictionary
		for index in (drifted[room_key] as Dictionary).keys():
			_check(
				expected.has(index),
				"新出现漂移盒：%s#%d（不在已知欠账清单里，实测 %.2f m）"
					% [room_key, index, float((drifted[room_key] as Dictionary)[index])]
			)
		for index in expected.keys():
			_check(
				(drifted[room_key] as Dictionary).has(index),
				"已知欠账 %s#%d 不再漂移 —— 请缩减 PINNED_DRIFT 快照（实测 %s）"
					% [room_key, index, JSON.stringify(drifted[room_key])]
			)
			if not (drifted[room_key] as Dictionary).has(index):
				continue
			_check(
				absf(float((drifted[room_key] as Dictionary)[index]) - float(expected[index])) <= 0.01,
				"已知欠账 %s#%d 漂移量变了：快照 %.2f m ≠ 实测 %.2f m（几何/盒位改过就要刷快照）"
					% [room_key, index, float(expected[index]),
						float((drifted[room_key] as Dictionary)[index])]
			)
	for room_key in pinned_keys:
		var expected := PINNED_DRIFT[room_key] as Dictionary
		for index in expected.keys():
			_check(
				drifted.has(room_key) and (drifted[room_key] as Dictionary).has(index),
				"已知欠账 %s#%d 不再漂移 —— 请缩减 PINNED_DRIFT 快照" % [room_key, index]
			)
	# 快照同步入口：把这一行 JSON 直接改写成 PINNED_DRIFT（键是 String 房名、值是 {下标: 米}）。
	print("SPAWN_RAMP_DRIFT_SNAPSHOT=%s" % JSON.stringify(drifted))


# ============================================================
# 辅助
# ============================================================

## [lo,hi] 出怪总数（各条 count_min/max 求和 + 首条非身份条目吃 bonus），
## `id` = elite/boss 身份条目数。含身份条目 ⇒ `hi` 即「设计总量」曲线口径。
func _design_bounds(box: Dictionary, bonus: int) -> Dictionary:
	var lo := 0
	var hi := 0
	var id_entries := 0
	var bonus_used := false
	for spawn_value in (box.get("spawns", []) as Array):
		var spawn := spawn_value as Dictionary
		var type_id := str(spawn.get("type", ""))
		var c_min := int(spawn.get("count_min", 0))
		var c_max := int(spawn.get("count_max", c_min))
		if type_id == "elite" or type_id == "boss":
			id_entries += c_max
		elif bonus > 0 and not bonus_used:
			c_min += bonus
			c_max += bonus
			bonus_used = true
		lo += c_min
		hi += c_max
	return {"lo": lo, "hi": hi, "id": id_entries}


## 实到条目里的 elite/boss 身份条目数（环境就绪时会真的落下来，要从实到里扣掉）。
func _id_realized(entries: Array[Dictionary]) -> int:
	var count := 0
	for entry in entries:
		var type_id := str((entry as Dictionary).get("type", ""))
		if type_id == "elite" or type_id == "boss":
			count += 1
	return count


func _vec2(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
