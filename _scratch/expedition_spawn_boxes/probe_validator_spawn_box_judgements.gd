extends Node
## 负向对照探针：证明「触发器刷怪·放置层」新判据 **G/H/I/J/K 真的会红**，不是空转。
##
## 为什么必须专门证明「会红」：校验器里这五条在正常数据上恒为「不报错」，
## 而「不报错」有两种可能 —— ①判据生效且数据合法；②判据压根没跑（被门控跳过、
## 或条件写反）。静态跑一遍远征 01 只会得到「全绿」，无法区分这两者。
##
## 做法：
##   1. 拿生成器在**固定种子**下的真几何产出（`geometry_authoritative = true`）当基线，
##      断言基线零错 —— 这是「判据生效且数据合法」那一半；
##   2. 逐条注入一个「只犯这一条」的错，断言**恰好命中**对应错误码 —— 这是「判据会红」。
##
## ⚠ 为什么基线必须用**生成器产出**而不是 `LevelPlanLoader.normalize_floor` 的文件结构：
## `mode = "constrained"` 的文件几何是样例（`geometry_authoritative = false`），
## B / G / H 三条被门控跳过。拿文件结构跑负向对照，G/H 注入的错**不会红**，
## 于是「门控正确」会被误读成「判据失效」—— 这正是本探针要避免的混淆。
##
## 运行：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . \
##     res://_scratch/expedition_spawn_boxes/probe_validator_spawn_box_judgements.tscn
##
## 判据：PROBE_SPAWN_BOX_JUDGEMENTS_OK baseline=0 judges=N
## 失败：PROBE_SPAWN_BOX_JUDGEMENTS_FAILED failures=N

const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")
const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const CATALOG := preload("res://src/map/SpawnBoxCatalog.gd")

const LEVEL_ID := "expedition_01"
const FLOOR := 0
## 与 `verify_level_plan_design_source.RUNTIME_GUARD_SEED` 同值：探针验证的就是门禁
## 实际跑的那个种子，避免「我验的种子和门禁验的不是同一个」。
const SEED := 20260919
## 5m 砖格单元（与 RoomDoorLane.GRID_UNIT_M 同值；本脚本独立重写是刻意的，
## 避免「探针与被测共用常量 ⇒ 常量写错两边一起错」）。
const TILE := 5.0

var _failures := 0


func _ready() -> void:
	var level_plan := LOADER.load_level_plan(LEVEL_ID)
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL_ID)
	var normalized := LOADER.normalize_floor(LEVEL_ID, FLOOR)
	print(
		"PROBE floor_from_file auth=%s mode=%s"
		% [str(normalized.get("geometry_authoritative")), str(normalized.get("mode"))]
	)
	# 直接调生成器的 constrained 分支取**真几何**（`generate_from_level_plan` 不暴露中间结构）。
	var floor_source := GENERATOR._generate_constrained_floor(
		LEVEL_ID, FLOOR, SEED, normalized, policy, templates
	)
	if floor_source.is_empty():
		print("PROBE_SPAWN_BOX_JUDGEMENTS_FAILED failures=1 (生成器未产出楼层结构)")
		get_tree().quit(1)
		return
	var auth := bool(floor_source.get("geometry_authoritative", false))
	var room_count := (floor_source.get("rooms", []) as Array).size()
	print("PROBE generated auth=%s rooms=%d" % [str(auth), room_count])
	if not auth:
		# 断言生成器真的置了真几何标记 —— 否则下面 G/H 的「命中」全靠运气。
		print("PROBE_SPAWN_BOX_JUDGEMENTS_FAILED failures=1 (geometry_authoritative 未置真)")
		get_tree().quit(1)
		return

	var baseline := _errors(floor_source, policy, templates)
	print("PROBE baseline errors=%d %s" % [baseline.size(), str(baseline)])
	if not baseline.is_empty():
		_failures += 1

	# —— 逐条负向对照：注入一个「只犯这一条」的错 ——
	_judge("G 盒心非砖心相位", "spawn_placement_not_tile_center", floor_source, policy, templates)
	_judge("H 盒心贴墙（内缩不足 1 圈）", "spawn_placement_wall_recess_short", floor_source, policy, templates)
	# 2026-09-26 收紧 H（改判**盒边**）的针对性反向对照：盒心达标但盒边压最外一圈。
	# 这一条在**旧版判据下不会红** —— 它的存在就是为了证明收紧真的改变了判定，而不是白改。
	_judge("H 盒心够但盒边压最外圈", "spawn_placement_wall_recess_short", floor_source, policy, templates)
	_judge("I 盒心重合", "spawn_placement_center_duplicate", floor_source, policy, templates)
	_judge("I 盒 AABB 互叠", "spawn_placement_overlap", floor_source, policy, templates)
	_judge("J 逐实例尺寸 < 2×2", "spawn_placement_size_below_minimum", floor_source, policy, templates)
	_judge("K 旋转非 90° 整数倍", "spawn_placement_rotation_invalid", floor_source, policy, templates)
	# 反向对照：把 geometry_authoritative 打回 false，G/H/B 应**不再**报 —— 证明门控真的在拦，
	# 而不是「判据碰巧不报」。这一步很关键：没有它，「G/H 会红」也可能是无条件恒红。
	_judge_gated_off(floor_source, policy, templates)

	if _failures == 0:
		print("PROBE_SPAWN_BOX_JUDGEMENTS_OK baseline=0 judges=8")
		get_tree().quit(0)
		return
	print("PROBE_SPAWN_BOX_JUDGEMENTS_FAILED failures=%d" % _failures)
	get_tree().quit(1)


func _errors(floor_source: Dictionary, policy: Dictionary, templates: Dictionary) -> Array[String]:
	return VALIDATOR.validate_normalized(LEVEL_ID, FLOOR, floor_source, policy, templates)


## 注入 kind 对应的单点错误 → 断言命中 `expected` 错误码。
func _judge(
	label: String,
	expected: String,
	floor_source: Dictionary,
	policy: Dictionary,
	templates: Dictionary
) -> void:
	var copy := floor_source.duplicate(true)
	if not _mutate(label, copy):
		print("PROBE JUDGE_SKIP %s（本关卡无适用样本）" % label)
		return
	var errs := _errors(copy, policy, templates)
	for error in errs:
		if str(error).begins_with(expected):
			print("PROBE JUDGE_OK %s → %s (errors=%d)" % [label, expected, errs.size()])
			return
	print("PROBE JUDGE_FAIL %s 期望 %s 未命中，实得 errors=%d %s"
		% [label, expected, errs.size(), str(errs)])
	_failures += 1


## 门控反向对照：把几何标记打回 false 后，同一处 G/H 违规**必须不再报**。
func _judge_gated_off(floor_source: Dictionary, policy: Dictionary, templates: Dictionary) -> void:
	var copy := floor_source.duplicate(true)
	if not _mutate("G 盒心非砖心相位", copy):
		print("PROBE JUDGE_SKIP 门控对照")
		return
	copy["geometry_authoritative"] = false
	var errs := _errors(copy, policy, templates)
	for error in errs:
		if str(error).begins_with("spawn_placement_not_tile_center"):
			print("PROBE JUDGE_FAIL 门控对照失效：geometry_authoritative=false 仍报砖心相位")
			_failures += 1
			return
	print("PROBE JUDGE_OK 门控对照 → geometry_authoritative=false 时 G/B/H 静默（errors=%d）" % errs.size())


## 按 label 定位目标房 + 注入错误。返回 false = 本关卡没有可用样本。
func _mutate(label: String, floor_source: Dictionary) -> bool:
	if label.begins_with("I 盒 AABB"):
		return _mutate_overlap(floor_source)
	if label.begins_with("H 盒心够但盒边"):
		return _mutate_edge_recess(floor_source)
	var room := _first_hostile_room(floor_source)
	if room.is_empty():
		return false
	var placements := room.get("spawn_placements", []) as Array
	if placements.is_empty():
		return false
	var placement := placements[0] as Dictionary
	var size := room.get("size", Vector2.ZERO) as Vector2
	var cx := _tile_axis(size.x, true)
	var cz := _tile_axis(size.y, true)
	match label:
		"G 盒心非砖心相位":
			# 内部砖心 + 1 m ⇒ 相位跑掉；内缩仍充足 ⇒ 只犯 G。
			placement["center_m"] = [cx + 1.0, cz]
		"H 盒心贴墙（内缩不足 1 圈）":
			# 最外圈砖心 ⇒ 净距 2.5 < 5；相位仍对 ⇒ 只犯 H。
			placement["center_m"] = [_tile_axis(size.x, false), cz]
		"I 盒心重合":
			placements.append(placement.duplicate(true))
		"J 逐实例尺寸 < 2×2":
			placement["size_m"] = [1.0, 1.0]
		"K 旋转非 90° 整数倍":
			placement["rotation_deg"] = 45.0
		_:
			return false
	return true


## 「盒心达标、盒边压最外圈」—— 2026-09-26 把判据 H 从「判盒心」收紧成「判盒边」的
## 针对性反向对照。这种摆法在**旧版判据下不报错**（盒心净距够），收紧后必须报。
##
## 摆法：取一枚**盒宽 > 5 m** 的盒（全关只有 boss 台的 8×8 满足），挪到「离墙 7.5 m 的砖心」：
##   盒心净距 = 7.5 ≥ 5（旧判据放行）；盒边净距 = 7.5 − 4.0 = 3.5 < 5（新判据拦下）。
## 挑 7.5 m 而不是别的值：它仍是**合法砖心**（G 不报）、盒仍完全在房内（B 不报），
## 于是「命中 H」干净地归因到收紧本身。
##
## ⚠ 本注入可能**连带**触发判据 I（挪位后与邻盒 AABB 相交，boss 房另有三盒）——
## `_judge` 只断言目标错误码**出现**，不要求「只犯这一条」。在此写明，免得后人
## 看到 errors 里混着 I 误以为 I 判据坏了。
func _mutate_edge_recess(floor_source: Dictionary) -> bool:
	for value in floor_source.get("rooms", []):
		var room := value as Dictionary
		var size := room.get("size", Vector2.ZERO) as Vector2
		var placements := room.get("spawn_placements", []) as Array
		for placement_value in placements:
			var placement := placement_value as Dictionary
			var effective := _effective_size(placement)
			# 需要 7.5 − half < 5 ⇔ half > 2.5 ⇔ 盒宽 > 5 m。
			if effective.x * 0.5 <= 2.5 + 0.001:
				continue
			var center := placement.get("center_m", []) as Array
			if center.size() < 2:
				continue
			placement["center_m"] = [-size.x * 0.5 + TILE * 1.5, float(center[1])]
			return true
	return false


## AABB 互叠：复制一个盒实例、沿 x 平移 5 m（相位不变、仍是砖心、内缩不变），
## 只有当**盒宽 > 5 m** 时两个 AABB 才真的重叠 —— 全关卡只有 boss 台的 8×8 盒满足。
## ⚠ 必须平移**那一枚宽盒本身**，不能拿「有宽盒的房」的第 0 枚代替：第 0 枚可能
## 是 4×2 的小盒，平移 5 m 后两个 AABB 根本不相交，对照会假绿。
func _mutate_overlap(floor_source: Dictionary) -> bool:
	for value in floor_source.get("rooms", []):
		var room := value as Dictionary
		var placements := room.get("spawn_placements", []) as Array
		for placement_value in placements:
			var placement := placement_value as Dictionary
			if _effective_size(placement).x <= TILE + 0.001:
				continue
			var center := placement.get("center_m", []) as Array
			if center.size() < 2:
				continue
			var clone := placement.duplicate(true)
			clone["center_m"] = [float(center[0]) + TILE, float(center[1])]
			placements.append(clone)
			return true
	return false


## 第一间「敌对且有盒实例」的房。判据只认「有实例」——校验器自己会判敌对性。
func _first_hostile_room(floor_source: Dictionary) -> Dictionary:
	for value in floor_source.get("rooms", []):
		var room := value as Dictionary
		if (room.get("spawn_placements", []) as Array).is_empty():
			continue
		if str(room.get("authored_layout_room_id", "")).is_empty():
			continue
		return room
	return {}


## 逐实例生效尺寸（`size_m` 覆盖优先，否则资产缺省）。与校验器同口径。
func _effective_size(placement: Dictionary) -> Vector2:
	var box := CATALOG.load_box(str(placement.get("box", "")))
	var size := box.get("size_m", Vector2.ZERO) as Vector2
	var raw: Variant = placement.get("size_m", null)
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return size


## 该轴上的一枚**合法砖心**（房局部坐标）。
## `interior = true` ⇒ 取离房心最近的一枚；`false` ⇒ 取最外圈的一枚（净距 2.5 m）。
## 砖心集合 = `-size/2 + 2.5 + 5k`（奇数格宽时含 0、偶数格宽时含 ±2.5，两种都覆盖）。
func _tile_axis(size: float, interior: bool) -> float:
	var count := maxi(1, int(round(size / TILE)))
	var first := -size * 0.5 + TILE * 0.5
	if not interior:
		return first
	var index := clampi(int(round((0.0 - first) / TILE)), 0, count - 1)
	return first + TILE * float(index)
