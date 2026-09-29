extends Node
## 探针：远征01 逐房 / 逐波 / 逐盒的**实到**刷怪数量（判定「加量是否生效」）。
##
## 为什么不能只看数据：`Dungeon3D._collect_box_stage_entries` 在盒内排不下时会
## **静默截断**（尾部补的 `Vector3.INF` 被丢弃），表现为「数据改了游戏里没变多」。
## 本探针复刻 `_spawn_box_waves` 的 rng 序列（同 seed `run_seed ^ room.hash ^ 0x424f5831`、
## 同 stages 调用顺序），逐盒调用 `_collect_box_stage_entries` 并对**追加的条目数**计数；
## 条目数即真机实到数。再把「设计区间 [min,max]」与实到数并排输出，差 > 0 即截断。
##
## `designed` 口径：盒资产 `spawns[]` 各条 `count_max` 求和，再给**首条非
## elite/boss 条目**加 `count_bonus`（与运行时 §3.2 同口径）。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
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
	print("ROOM|wave|idx|box|bonus|design_min|design_max|realized|short|id_entries|trunc")
	var grand_realized := 0
	var grand_design_max := 0
	var grand_trunc := 0
	for key in ROOM_KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("%s|MISSING" % key)
			continue
		var agg := _replay_room(room)
		grand_realized += int(agg["realized"])
		grand_design_max += int(agg["design_max"])
		grand_trunc += int(agg["trunc"])
	print("TOTAL|realized=%d|design_max=%d|trunc=%d" % [
		grand_realized, grand_design_max, grand_trunc,
	])
	print("PROBE_DONE")
	get_tree().quit(0)


func _replay_room(room: DungeonRoom3D) -> Dictionary:
	var placements := room.spawn_placements
	var realized_sum := 0
	var design_max_sum := 0
	var trunc_sum := 0
	if placements.is_empty():
		print("# %s no placements" % room.room_id)
		return {"realized": 0, "design_max": 0, "trunc": 0}
	var stages := tower._resolve_encounter_stages(room.encounter, placements.size())
	var floor_number := maxi(1, tower.visual_theme.difficulty_rank)
	var denom := maxf(1.0, float(tower._records.size() - 1))
	var floor_level := clampi(int(float(tower._record_index(room.room_id)) / denom * 3.0), 0, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = tower.run_seed ^ room.room_id.hash() ^ 0x424f5831
	print("# %s boxes=%d waves=%d" % [room.room_id, placements.size(), stages.size()])
	var wave := 0
	for stage_value in stages:
		wave += 1
		for instance_value in (stage_value as Array):
			var idx := int(instance_value)
			if idx < 0 or idx >= placements.size():
				continue
			var placement := placements[idx] as Dictionary
			var box_id := str(placement.get("box", ""))
			var bonus := int(placement.get("count_bonus", 0))
			var box := SpawnBoxCatalog.load_box(box_id)
			var bounds := _design_bounds(box, bonus)
			var entries: Array[Dictionary] = []
			tower._collect_box_stage_entries(
				room, placements, idx, floor_number, floor_level, rng, entries
			)
			var realized := entries.size()
			realized_sum += realized
			design_max_sum += int(bounds["hi"])
			# `id_entries` = 本盒设计里 elite/boss **身份条目**数。headless 探针里
			# EliteRosterService 未开局预约、Boss 内容未就绪 ⇒ `_make_box_enemy` 返回 {}，
			# 这类条目**必然**落不下来，属探针环境产物，不是盒容量截断。
			# `trunc = short - id_entries` 才是「普通怪被盒容量截断」的真指标。
			var id_entries := int(bounds["id"])
			var short := int(bounds["hi"]) - realized
			# `trunc` = 真·容量截断：实到跌破**普通怪**设计下限。两条口径都要扣掉
			# 身份条目：`design_min` 里含 elite/boss 条目的 count，而 headless 下它们
			# 必然落不下来，不扣就会把「探针环境产物」误报成「盒容量截断」。
			# 落在 [design_min, design_max] 内的差额只是区间随机（如 `box_wall_arc` 的 1~2）。
			var trunc := maxi(0, (int(bounds["lo"]) - id_entries) - (realized - _id_realized(entries)))
			trunc_sum += trunc
			print("%s|%d|%d|%s|%d|%d|%d|%d|%d|%d|%d" % [
				room.room_id, wave, idx, box_id.replace("box_", ""), bonus,
				int(bounds["lo"]), int(bounds["hi"]), realized, short,
				id_entries, trunc,
			])
	return {"realized": realized_sum, "design_max": design_max_sum, "trunc": trunc_sum}


## [lo,hi] 出怪总数：各条 count_min/max 求和，再给首条非 elite/boss 条目加 bonus。
## `id` = 设计里 elite/boss 身份条目数（headless 探针中必然落不下来）。
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


## 实到条目里的 elite/boss 身份条目数（环境就绪时它们会真的落下来，要从实到里扣掉）。
func _id_realized(entries: Array[Dictionary]) -> int:
	var count := 0
	for entry in entries:
		var type_id := str((entry as Dictionary).get("type", ""))
		if type_id == "elite" or type_id == "boss":
			count += 1
	return count
