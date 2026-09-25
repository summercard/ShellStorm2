extends Node
## 远征关卡01 通道桥房「长边不连、只在短边开门」守卫探针（#42-B · 方案 A）。
##
## 业主口径（逐字）：「通道桥房间，这个房间只会有短边的地方会有门，因为中间是一个长的过道，
## 所以长边不能去连接。」⇒ 桥房的**长边不连任何房**，父边与全部子边都只能落在**短边**上。
##
## 落地方式（取向随连接方向）：桥房**只有一张模板** `bridge_60x50`，两种取向是同一张模板的
## 两种旋转（0° 长轴沿 x / 90° 转置长轴沿 y，占位尺寸两分量互换 —— 业主裁定 2026-09-25
## 「不要两批代号」，见 05.2 §3.4/§3.6），生成器**落位时**按贴合方向二选一 ——
## 门因此永远落在短墙上，而桥房仍能在水平 / 垂直两种排列之间自由选择，
## 不必被单一轴钉死（单一轴实测 24 种子回落 18 个 = 75%，见 `memory/0112`）。
##
## 判据（逐桥房、逐条连接）：
##   设桥房尺寸 (w, h)，长轴 = max(w, h) 所在的那个轴，**短边法向 = 长轴方向**。
##   一条连接（父边或子边）合规 ⟺ 连接方向属于短边法向：
##     · 长轴沿 x（w > h）⇒ 短边是东/西墙 ⇒ 方向须是 east / west
##     · 长轴沿 y（h > w）⇒ 短边是南/北墙 ⇒ 方向须是 north / south
##   桥房是「贴墙对」（净距 0），判据按**包围盒接触面法向**取，与 `RoomDoorLane` 同源。
##
## 同时统计：回落种子数（生成器整体失效的标志）、两种取向的使用次数
## （证明取向机制真被触发，而不是恒用本体 —— 只断言"不违规"在恒用本体时也会全绿）。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")

const LEVEL := "expedition_01"
## 与 `memory/0112` 的实测口径对齐，便于直接对照「单一轴硬约束」的 75% 回落基线。
const BASE_SEED := 310000
const BASE_STEP := 7919
const BASE_SAMPLES := 24
## 更长的一轮，用于确认不是「这批种子恰好可行」。
const WIDE_BASE_SEED := 700000
const WIDE_STEP := 7919
const WIDE_SAMPLES := 300


func _ready() -> void:
	var failures: Array[String] = []
	var level_plan := LOADER.load_level_plan(LEVEL)
	if level_plan.is_empty():
		print("PROBE_FAIL: level_plan 加载失败")
		get_tree().quit(1)
		return
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	if not templates.has("bridge_60x50"):
		print("PROBE_FAIL: 桥房模板缺失（bridge_60x50）")
		get_tree().quit(1)
		return
	# 反向断言：转置姿态必须用旋转表达，不得另建模板 id（否则「两批代号」又回来了）。
	if templates.has("bridge_50x60"):
		print("PROBE_FAIL: 模板目录里出现了 bridge_50x60 —— 转置姿态只许用 template_rotation_deg 表达")
		get_tree().quit(1)
		return

	var totals := {
		"ok": 0, "fallback": 0, "invalid": 0,
		"bridge_rooms": 0, "links": 0, "violations": 0,
		"pose_native": 0, "pose_transposed": 0,
		"fallback_seeds": [],
	}
	_run_batch(BASE_SEED, BASE_STEP, BASE_SAMPLES, normalized, policy, templates, totals, failures, true)
	_run_batch(WIDE_BASE_SEED, WIDE_STEP, WIDE_SAMPLES, normalized, policy, templates, totals, failures, false)

	print("\n=== 累计（%d + %d 个种子）===" % [BASE_SAMPLES, WIDE_SAMPLES])
	print("成功=%d 回落=%d 校验不通过=%d" % [
		int(totals["ok"]), int(totals["fallback"]), int(totals["invalid"]),
	])
	print("桥房实例=%d 连接条数=%d 长边违规=%d" % [
		int(totals["bridge_rooms"]), int(totals["links"]), int(totals["violations"]),
	])
	print("取向使用：本体(长轴x)=%d 转置(长轴y)=%d" % [
		int(totals["pose_native"]), int(totals["pose_transposed"]),
	])

	# 回落率阈值。**回落不是长边违规**：它退到设计源兜底样例，几何仍合法。
	# 但回落率是「取向机制整体退化」的灵敏指标 —— 删掉短边约束或把它误用到全体房型时，
	# 回落率会从个位数百分比直接跳到 90%+（实测：误用 `orientable` 时 300/300）。
	# 阈值放到 5%：抓住整体退化，又不因个别结构性无解的种子误报。
	var total_samples := BASE_SAMPLES + WIDE_SAMPLES
	var fallback_ratio := float(int(totals["fallback"])) / float(total_samples)
	if fallback_ratio > 0.05:
		failures.append(
			"回落率 %.1f%% 超过 5%% 阈值（回落 %d / %d）—— 取向机制可能整体退化"
			% [fallback_ratio * 100.0, int(totals["fallback"]), total_samples]
		)
	else:
		print("回落种子（≤5%% 阈值，退设计源兜底样例，非失败）：%s" % str(totals["fallback_seeds"]))

	if failures.is_empty():
		print(
			"\nBRIDGE_SHORT_EDGE_OK seeds=%d bridge_rooms=%d links=%d violations=0 "
			% [BASE_SAMPLES + WIDE_SAMPLES, int(totals["bridge_rooms"]), int(totals["links"])]
			+ "fallback=%d native=%d transposed=%d"
			% [
				int(totals["fallback"]),
				int(totals["pose_native"]), int(totals["pose_transposed"]),
			]
		)
		get_tree().quit(0)
		return
	print("\n失败项（%d）：" % failures.size())
	for line in failures:
		print("  FAIL: %s" % line)
	print("\nBRIDGE_SHORT_EDGE_FAIL failures=%d" % failures.size())
	get_tree().quit(1)


func _run_batch(
	base_seed: int, step: int, samples: int,
	normalized: Dictionary, policy: Dictionary, templates: Dictionary,
	totals: Dictionary, failures: Array[String], verbose: bool
) -> void:
	for index in range(samples):
		var run_seed := base_seed + index * step
		var generated := GENERATOR._generate_constrained_floor(
			LEVEL, 0, run_seed, normalized, policy, templates
		)
		if generated.is_empty():
			totals["fallback"] = int(totals["fallback"]) + 1
			# 回落**不是失败**：`generate_from_level_plan` 会退到设计源兜底样例
			# （`used_fallback=true`），那份几何由 `validate_normalized` 单独把关。
			# 版图是现算的，不宣称 100% —— 只记录种子号，最后按回落率做阈值断言。
			(totals["fallback_seeds"] as Array).append(run_seed)
			continue
		var errors := VALIDATOR.validate_normalized(LEVEL, 0, generated, policy, templates)
		if not errors.is_empty():
			totals["invalid"] = int(totals["invalid"]) + 1
			failures.append("种子 %d 校验不通过：%s" % [run_seed, str(errors)])
			continue
		totals["ok"] = int(totals["ok"]) + 1
		_audit_bridge_links(run_seed, generated, templates, totals, failures, verbose)


## 逐桥房审计它的**全部连接**（父边 + 子边）是否都落在短边上。
func _audit_bridge_links(
	run_seed: int, generated: Dictionary, templates: Dictionary,
	totals: Dictionary, failures: Array[String], verbose: bool
) -> void:
	var rooms := generated.get("rooms", []) as Array
	var by_key: Dictionary = {}
	for value in rooms:
		var room := value as Dictionary
		by_key[str(room.get("key", ""))] = room
	var bridge_count := 0
	var link_count := 0
	var violation_count := 0
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var template_id := str(room.get("template_id", ""))
		if not _is_bridge_template(templates, template_id):
			continue
		bridge_count += 1
		var size := room.get("size", Vector2.ZERO) as Vector2
		var long_axis_x := size.x > size.y
		var pose_key := "pose_native" if long_axis_x else "pose_transposed"
		totals[pose_key] = int(totals[pose_key]) + 1
		var center := room.get("center", Vector2.ZERO) as Vector2
		# 连接方 = 父房 + 全部子房（子房是 parent_key 指向本房的那批）。
		var neighbours: Array[String] = []
		var parent_key := str(room.get("parent_key", ""))
		if not parent_key.is_empty() and by_key.has(parent_key):
			neighbours.append(parent_key)
		for other_value in rooms:
			var other := other_value as Dictionary
			if str(other.get("parent_key", "")) == key:
				neighbours.append(str(other.get("key", "")))
		for neighbour_key in neighbours:
			link_count += 1
			var neighbour := by_key[neighbour_key] as Dictionary
			var delta := (neighbour.get("center", Vector2.ZERO) as Vector2) - center
			var along_x := absf(delta.x) >= absf(delta.y)
			if along_x == long_axis_x:
				continue
			violation_count += 1
			if verbose:
				var axis := "x" if along_x else "y"
				var long_axis := "x" if long_axis_x else "y"
				failures.append(
					"种子 %d 桥房 %s（%s，长轴 %s）在**长边**接了 %s（方向沿 %s）"
					% [run_seed, key, str(size), long_axis, neighbour_key, axis]
				)
	totals["bridge_rooms"] = int(totals["bridge_rooms"]) + bridge_count
	totals["links"] = int(totals["links"]) + link_count
	if violation_count > 0:
		totals["violations"] = int(totals["violations"]) + violation_count
		if not verbose:
			failures.append(
				"种子 %d 有 %d 条桥房连接落在长边（本批 %d 个种子）"
				% [run_seed, violation_count, WIDE_SAMPLES]
			)


## 模板是否属通道桥房族：声明了 `sunken_pit`（本关唯一多层几何房型，两个取向共用该标记）。
func _is_bridge_template(templates: Dictionary, template_id: String) -> bool:
	if template_id.is_empty() or not templates.has(template_id):
		return false
	return (templates[template_id] as Dictionary).has("sunken_pit")
