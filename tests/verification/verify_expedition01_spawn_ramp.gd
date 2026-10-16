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
	"room_05": 31, "room_07": 16, "room_08": 17,
}
## ⚠ 2026-10-16：`room_04` / `room_06` / `room_09` / `room_10` 已按业主口径改成
## **踩点触发式遭遇**（`encounter.trigger` 满宽带），**已无刷怪盒**。它们从本曲线
## 的 `RAMP_*` 三张表里全部移出 —— 曲线量的是「逐盒加量」，盒数 0 的房留在链上只会恒红。
## 取而代之的是 `TRIGGER_EXPECTED`（逐房波次编成 + 触发带形状 + 端口朝向），
## 保证「数据 ↔ 运行时」的契约不因为移出曲线而失守。
## 单调不减校验的房序列（room_03 起）。**room_05 已被摘出** —— 见 `RAMP_TARGET` 上方的注：
## 峰值房不参与相邻比较，但「链上其余房单调不减」这条不许松。
const RAMP_MONOTONE_ORDER: Array[String] = [
	"room_07", "room_08",
]
## 曲线目标的房序列（room_03 起，**含**峰值房 room_05）—— 用于「盒数 / 逐实例增量 / 逐房总量」核对。
const RAMP_ORDER: Array[String] = [
	"room_05", "room_07", "room_08",
]
## 这 8 房的逐实例 `count_bonus` 期望值（数据面唯一真源的镜像，改数据必须同步这里）。
const EXPECTED_BONUS := {
	# room_05：第 5 个实例是 `box_bridge_center`（桥心压制盒），靠自带 16 只出量、不吃增量。
	"room_05": [1, 0, 2, 2, 0],
	"room_07": [6, 2, 2],
	"room_08": [1, 1, 1, 2, 0],
}
## 逐实例 `count_multiplier` 期望值（**与 `count_bonus` 同一条隐形契约**：数据层写、
## 运行层读，归一在 `_box_placement_at`）。
##
## `room_01`：业主 2026-09-29 口径「每个盒子里数量翻倍」⇒ 全盒 ×2。
## `room_02`：**2026-10-14 业主改布局** —— 由 4 盒改为 **5 盒的「中心 + 四角」**，
##   并为「任一群进战斗、其余四群一起围上来」加了 `encounter.monster_ai.alert_share_radius_m=60`。
##   ⚠ 四角**不能**沿用全盒 ×2：本房真实可通行区只有一条横带（`z ∈ {-7.5,-2.5,2.5}`，
##   `z=±12.5` 被家具吃掉），四角砖心的**原地容量只有 2~4 只**，×2 会越容量触发落地平移。
##   故只有「中心主力盒」与「西南角」保留 ×2，其余保留盒资产原始量（1）—— 见下方实测容量注释。
const EXPECTED_MULTIPLIER := {
	"room_01": [2, 2, 2],
	"room_02": [2, 1, 1, 2, 1],
}
## 未加量房：逐实例 `count_bonus` 必须 0，防「顺手也加了」。
## （`room_01` / `room_02` 的翻倍走 `count_multiplier`，不在此判据内 —— 见 `EXPECTED_MULTIPLIER`。）
const UNTOUCHED_ROOMS: Array[String] = ["room_01", "room_02", "boss"]

## —— 踩点触发式遭遇房（2026-10-16 起**不再是盒子房**）——
##
## 业主口径：去掉进门后的所有刷怪盒；`room_03` 在房间中心放触发点、走到中间开始 60 秒倒计时；
## 随后追加 `room_04`（60 s）/ `room_06`（60 s）/ `room_09`（90 s）/ `room_10`（105 s），
## 并把这四房的触发区改成**满宽带**（"横向铺开，不要让玩家可以绕开"）。
##
## 为什么它们必须**移出** `RAMP_*` 系列：那条曲线量的是「逐盒加量」，
## 这些房已无盒子，留在链上只会恒红（实测：盒数 0 ≠ 曲线口径 4）。
## 但「数据 ↔ 运行时」的契约不能因此失守，故另立 `TRIGGER_EXPECTED` 盯住
## **波次编成 + 触发形状 + 端口朝向**三者。
const TRIGGER_ROOM_KEYS: Array[String] = [
	"room_03", "room_04", "room_06", "room_09", "room_10",
]
## 逐房期望：时长 / 触发形状 / 端口朝向 / 逐波编成。
##
## **端口朝向必须钉住**：触发带的厚度轴要和**入口门的法线**同轴，从入口进来才必然穿带。
## 一旦端口对接链改了朝向（布局里 `template_rotation_deg` 全是 0 ≠ 运行时没转过 ——
## 实测 room_04 布局写 45×40、运行时是 40×45），带子就会与通行方向平行、
## 玩家**贴着墙就能绕过去**，而数据看起来毫无异常。所以这里的朝向断言是功能的守卫，
## 不是"顺便记一笔"。
##
## 轴约定（`DungeonRoom3D` 门位表）：北 = -z、南 = +z、东 = +x、西 = -x。
const TRIGGER_EXPECTED := {
	"room_03": {
		"duration": 60.0, "shape": "circle",
		"entry": "west", "entry_target": "room_02",
		"exit": "east", "exit_target": "room_04",
		"waves": [
			{"fat_zombie03": 1, "melee_chaser": 5},
			{"fat_zombie03": 1, "melee_chaser": 3, "ranged_caster": 2},
			{"fat_zombie03": 1, "melee_chaser": 5, "strong_random": 1},
			{"fat_zombie03": 2, "melee_chaser": 5, "ranged_caster": 2, "strong_random": 1},
			{"fat_zombie03": 2, "melee_chaser": 6, "ranged_caster": 3, "strong_random": 2},
			{"fat_zombie03": 2, "melee_chaser": 6, "ranged_caster": 4, "strong_random": 2},
		],
	},
	"room_04": {
		"duration": 60.0, "shape": "band",
		"entry": "west", "entry_target": "room_03",
		"exit": "north", "exit_target": "room_05",
		"waves": [
			{"fat_zombie03": 1, "melee_chaser": 5},
			{"fat_zombie03": 1, "melee_chaser": 4, "ranged_caster": 2},
			{"fat_zombie03": 1, "melee_chaser": 5, "strong_random": 1},
			{"fat_zombie03": 2, "melee_chaser": 5, "ranged_caster": 2, "strong_random": 1},
			{"fat_zombie03": 2, "melee_chaser": 6, "ranged_caster": 3, "strong_random": 2},
			{"fat_zombie03": 2, "melee_chaser": 7, "ranged_caster": 4, "strong_random": 2},
		],
	},
	"room_06": {
		"duration": 60.0, "shape": "band",
		"entry": "south", "entry_target": "room_05",
		"exit": "north", "exit_target": "room_07",
		"waves": [
			{"fat_zombie03": 1, "melee_chaser": 5},
			{"fat_zombie03": 1, "melee_chaser": 4, "ranged_caster": 3},
			{"fat_zombie03": 2, "melee_chaser": 5, "strong_random": 1},
			{"fat_zombie03": 2, "melee_chaser": 6, "ranged_caster": 3, "strong_random": 1},
			{"fat_zombie03": 2, "melee_chaser": 6, "ranged_caster": 4, "strong_random": 2},
			{"fat_zombie03": 2, "melee_chaser": 7, "ranged_caster": 4, "strong_random": 2},
		],
	},
	"room_09": {
		"duration": 90.0, "shape": "band",
		"entry": "east", "entry_target": "room_08",
		"exit": "west", "exit_target": "room_10",
		"waves": [
			{"fat_zombie03": 1, "melee_chaser": 5},
			{"fat_zombie03": 2, "melee_chaser": 4, "ranged_caster": 3},
			{"fat_zombie03": 2, "melee_chaser": 6, "strong_random": 2},
			{"fat_zombie03": 2, "melee_chaser": 6, "ranged_caster": 4, "strong_random": 2},
			{"fat_zombie03": 2, "melee_chaser": 7, "ranged_caster": 4, "strong_random": 2},
			{"fat_zombie03": 3, "melee_chaser": 7, "ranged_caster": 5, "strong_random": 3},
		],
	},
	"room_10": {
		"duration": 105.0, "shape": "band",
		"entry": "east", "entry_target": "room_09",
		"exit": "north", "exit_target": "boss",
		"waves": [
			{"fat_zombie03": 1, "melee_chaser": 6},
			{"fat_zombie03": 2, "melee_chaser": 4, "ranged_caster": 3},
			{"fat_zombie03": 2, "melee_chaser": 6, "strong_random": 2},
			{"fat_zombie03": 2, "melee_chaser": 7, "ranged_caster": 4, "strong_random": 2},
			{"fat_zombie03": 3, "melee_chaser": 7, "ranged_caster": 4, "strong_random": 2},
			{"fat_zombie03": 3, "melee_chaser": 8, "ranged_caster": 5, "strong_random": 3},
		],
	},
}
## 触发带厚度（米）：四房统一，与数据里 `thickness_m` 同值。
const TRIGGER_BAND_THICKNESS := 6.0
## 已知存量欠账：声明盒心容量为 0、只能靠「落地平移」出怪的盒（**非本次改动引入**）。
## 逐条 = 房 key → {实例下标: 漂移米}。任何一条消失要缩表，任何一条新增要红。
##
## ⚠ `boss` 三条是 2026-10-14 刷新：快照过期为 `{1: 0.63}`，与实测不符。
##   **已用对照实验证明与本轮改动无关** —— 把 `floor_00.json` 还原到 HEAD 后重跑，boss
##   漂移照旧是 `{0: 11.07, 3: 4.81}`、`#1` 照旧不漂移。属既有几何欠账（Boss 房
##   `tile_cells=0`、无授权砖格 ⇒ 盒心原样返回、靠落地平移），非新增回归。
const PINNED_DRIFT := {
	# `room_04` 的 `{3: 5.00}` 于 2026-10-16 缩表：该房已改成触发式遭遇、再无刷怪盒，
	# 不存在「盒心漂移」这件事。缩表是**改动的必然结果**，不是把红项抹掉。
	"room_08": {4: 20.00},
	"boss": {0: 11.07, 3: 4.81},
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
	_verify_trigger_encounters()
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


# ============================================================
# 踩点触发式遭遇（room_03）：数据 ↔ 运行时契约
# ============================================================

## 盯四件事：房间里**没有盒子**、触发器在、波次编成与总时长逐值相符、清算门控与两个表现开关没被改掉。
func _verify_trigger_encounters() -> void:
	for key in TRIGGER_ROOM_KEYS:
		var expected := TRIGGER_EXPECTED[key] as Dictionary
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			_check(false, "踩点遭遇房 %s 在运行时不存在" % key)
			continue
		_check(
			room.spawn_placements.is_empty(),
			"%s 已改为踩点遭遇，仍残留 %d 个刷怪盒" % [key, room.spawn_placements.size()]
		)
		var encounter := room.encounter
		var trigger := encounter.get("trigger", {}) as Dictionary
		_check(not trigger.is_empty(), "%s 缺 encounter.trigger（进房会退回公式刷怪）" % key)
		_verify_trigger_shape(key, room, trigger, expected)
		_check(
			is_equal_approx(float(encounter.get("duration_sec", 0.0)), float(expected["duration"])),
			"%s 总时长 %s ≠ %s"
				% [key, str(encounter.get("duration_sec", 0.0)), str(expected["duration"])]
		)
		_check(
			str(encounter.get("stage_advance", "")) == "clear",
			"%s stage_advance 不是 clear ⇒ 会变成「按时间叠加」而不是「清完才出下一波」" % key
		)
		_check(bool(encounter.get("seal_room", false)), "%s 未开启落门封房（seal_room）" % key)
		_check(
			bool(encounter.get("light_on_finish", false)),
			"%s 未开启到点开灯（light_on_finish）" % key
		)
		# 两个"把玩家关进房里打"才需要的开关：怪要主动围过来、右上角要有倒计时。
		# 行为断言在 `verify_encounter_trigger_room_flow`，这里只钉"数据面有没有开"——
		# 数据没说、行为测试却要它成立，是最容易两头都过不了的一类失配。
		_check(
			bool(encounter.get("hunt_player", false)),
			"%s 未开启事件猎杀（hunt_player）⇒ 房里的怪不会主动围过来" % key
		)
		_check(
			bool(encounter.get("hud_countdown", false)),
			"%s 未开启右上角倒计时环（hud_countdown）" % key
		)
		var expected_waves := expected["waves"] as Array
		var stages := encounter.get("stages", []) as Array
		_check(
			stages.size() == expected_waves.size(),
			"%s 波数 %d ≠ %d" % [key, stages.size(), expected_waves.size()]
		)
		for index in mini(stages.size(), expected_waves.size()):
			var actual := {}
			for value in (stages[index] as Dictionary).get("monsters", []) as Array:
				var monster := value as Dictionary
				var type_id := str(monster.get("type", ""))
				actual[type_id] = int(actual.get(type_id, 0)) + int(monster.get("count", 0))
			_check(
				actual == expected_waves[index],
				"%s 第 %d 波编成 %s ≠ %s" % [key, index + 1, str(actual), str(expected_waves[index])]
			)


## 触发形状 + 朝向：**这是"不让绕开"的守卫**（见 `TRIGGER_EXPECTED` 上方注）。
##
## 三件事逐个钉：
##   ① 形状与数据一致（`circle` / `band`）；
##   ② **入口门的法线轴 == 带子的厚度轴** —— 拿运行时 `door_targets` 判定，
##      不用布局里的 `outward`（那是示例版图口径，实测与运行时朝向不一致）；
##   ③ 带子铺满的那根轴，其房间跨度 > 厚度 ⇒ 它是"带"而不是"盖住整间"。
func _verify_trigger_shape(
	key: String, room: DungeonRoom3D, trigger: Dictionary, expected: Dictionary
) -> void:
	var shape := str(trigger.get("shape", "circle"))
	_check(
		shape == str(expected["shape"]),
		"%s 触发形状 %s ≠ 期望 %s" % [key, shape, str(expected["shape"])]
	)
	# 端口朝向：入口 / 出口各钉一条。朝向变了 ⇒ 带子会与通行方向平行、可以贴墙绕过去。
	var entry := str(expected["entry"])
	var exit := str(expected["exit"])
	_check(
		str(room.door_targets.get(entry, "")) == str(expected["entry_target"]),
		"%s 入口侧 %s 通向 %s ≠ 期望 %s（端口对接链改了朝向）"
			% [key, entry, str(room.door_targets.get(entry, "<无>")), str(expected["entry_target"])]
	)
	_check(
		str(room.door_targets.get(exit, "")) == str(expected["exit_target"]),
		"%s 出口侧 %s 通向 %s ≠ 期望 %s"
			% [key, exit, str(room.door_targets.get(exit, "<无>")), str(expected["exit_target"])]
	)
	if shape != "band":
		return
	# 入口在东西墙 ⇒ 进门沿 x 走 ⇒ 带子必须薄在 x、铺满 z；南北墙同理。
	var entry_on_x_wall := entry in ["east", "west"]
	var thin_axis := "x" if entry_on_x_wall else "z"
	var span_axis := "z" if entry_on_x_wall else "x"
	_check(
		str(trigger.get("axis", "")) == span_axis,
		"%s 带子铺满 %s 轴 ≠ 期望 %s ⇒ 厚度轴（%s）与入口门法线（%s）不同轴，玩家能贴墙绕开"
			% [key, str(trigger.get("axis", "")), span_axis, thin_axis, thin_axis]
	)
	var thickness := float(trigger.get("thickness_m", 0.0))
	_check(
		is_equal_approx(thickness, TRIGGER_BAND_THICKNESS),
		"%s 带子厚度 %s ≠ 口径 %s" % [key, str(thickness), str(TRIGGER_BAND_THICKNESS)]
	)
	var dimensions := room.get_dimensions()
	var thin_extent := dimensions.x if thin_axis == "x" else dimensions.y
	_check(
		thickness > 0.0 and thickness < thin_extent,
		"%s 带子厚度 %s 不小于房间在 %s 轴上的跨度 %s ⇒ 退化成「进房即触发」"
			% [key, str(thickness), thin_axis, str(thin_extent)]
	)
	var offset := trigger.get("offset_m", [0.0, 0.0]) as Array
	_check(
		offset.size() == 2 and is_zero_approx(float(offset[0])) and is_zero_approx(float(offset[1])),
		"%s 带子偏移 %s ≠ [0,0]（口径是房心，改了要同步本门禁）" % [key, str(offset)]
	)
