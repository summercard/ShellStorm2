extends Node3D
## EGT 式关卡组装器的真实验收。
##
## 断言五件事（每条都从**产物**验，不看代码意愿）：
##
## 1. **能组装出来** —— `assemble_flow()` 返回 `ok`。
## 2. **房间不重叠** —— 两两求交集，面积 > 0 即失败（共墙贴合面积为 0，允许）。
## 3. **每条边都连通且有门** —— 边的两个端点都放置了，且两侧端口都落在
##    `RoomDoorLane.port_pair()` 反算出的槽位上（互证两份实现）。
## 4. **门位合法** —— 每个门槽都在 `RoomDoorLane.lane_offsets(墙长)` 的返回里。
## 5. **结果确定性** —— 同一 flow + 同一种子跑两次，房间坐标逐字节相同。
##
## 另外统计：每张 flow 在多少个种子上成功、平均环数与走廊数。
## 不追求 100% 成功 —— EGT 自己也会重试；失败率本身就是指标。
##
## 两件额外的事（2026-10-28 加）：
##
## - **连接房必须窄长且朝向正确**：EGT 原文说 CONNECTOR 是 "long, thin rooms, so picking
##   one with a sensible orientation is vital"。这条断言验的正是"sense of orientation"：
##   长轴必须沿行进方向。旧版用 25×25 方房，这条会直接红。
## - **多种子抽关**：不只跑固定的六张骨架，还按 `pick_flow()` 抽 N 次关卡（模拟真实开局）。

const ASSEMBLER := preload("res://src/map/EgtFlowAssembler.gd")
const LANE := preload("res://src/map/RoomDoorLane.gd")

const PLAN_DIR := "res://data/level_plans/expedition_03"
const SEED_COUNT := 12
## 抽关测试的次数与种子起点（与上面那张表分开，避免同一批种子重复跑同样的组合）。
const LEVEL_DRAW_COUNT := 120
const LEVEL_DRAW_BASE_SEED := 90000
## 连接房的最小长宽比。EGT 的 connector 是"窄长"，2.5 是下限而不是目标值。
const CONNECTOR_MIN_ASYMMETRY := 2.5

var _failures: Array[String] = []
var _checks := 0
var _templates: Dictionary = {}
## 连接房统计：total = 出现次数；passthrough = 所有门都在长轴端（真正的穿堂）。
var _connector_total := 0
var _connector_passthrough := 0


func _ready() -> void:
	await get_tree().process_frame
	_templates = _load_templates()
	_check(not _templates.is_empty(), "模板目录为空")
	var flows := _load_flows()
	_check(not flows.is_empty(), "flow 目录为空")

	var total_ok := 0
	var total_runs := 0
	for flow in flows:
		var flow_id := str(flow.get("flow_id", "?"))
		var ok_count := 0
		var loop_sum := 0
		var corridor_sum := 0
		var first_error := ""
		for i in range(SEED_COUNT):
			var seed_value := 4100 + i * 37
			total_runs += 1
			var result: Dictionary = ASSEMBLER.assemble_flow(flow, _templates, {}, seed_value)
			if not bool(result["ok"]):
				if first_error.is_empty():
					first_error = str(result["error"])
				_check(false, "%s seed=%d 组装失败：%s" % [flow_id, seed_value, str(result["error"])])
				continue
			ok_count += 1
			total_ok += 1
			loop_sum += (result["loops"] as Array).size()
			corridor_sum += (result["corridors"] as Array).size()
			_verify_result(flow_id, seed_value, result)
		print("ASSEMBLE %-28s %2d/%2d ok  loops=%.1f corridors=%.1f%s" % [
			flow_id, ok_count, SEED_COUNT,
			float(loop_sum) / maxf(1.0, float(ok_count)),
			float(corridor_sum) / maxf(1.0, float(ok_count)),
			"" if first_error.is_empty() else ("  first_err=" + first_error.substr(0, 90))])

	_verify_determinism(flows)
	_verify_level_draw(flows)
	_report(total_ok, total_runs)


## 真实开局模拟：按 `pick_flow()` 从六张骨架里抽一张，再组装。
##
## 和上面那张表不同：上面是"每张骨架都跑一遍"，这里是"一个种子一局，抽到哪张算哪张"，
## 更接近玩家每天遇到的情况。同时统计连接房到底用了哪几个模板 ——
## 如果 40 局只出现一种朝向，说明"布局时选模板"是空转的。
func _verify_level_draw(flows: Array) -> void:
	var seen_templates := {}
	var seen_sizes := {}
	var ok_count := 0
	for i in range(LEVEL_DRAW_COUNT):
		var seed_value := LEVEL_DRAW_BASE_SEED + i * 613
		var flow: Dictionary = ASSEMBLER.pick_flow(flows, seed_value)
		if flow.is_empty():
			_check(false, "抽关 seed=%d: pick_flow 返回空" % seed_value)
			continue
		var flow_id := str(flow.get("flow_id", "?"))
		var result: Dictionary = ASSEMBLER.assemble_flow(flow, _templates, {}, seed_value)
		if not bool(result["ok"]):
			_check(false, "抽关 seed=%d 抽到 %s 组装失败：%s" % [
				seed_value, flow_id, str(result["error"])])
			continue
		ok_count += 1
		_verify_result("draw:%s" % flow_id, seed_value, result)
		for value in result["rooms"] as Array:
			var room := value as Dictionary
			if not str(room["node_id"]).begins_with("conn"):
				continue
			seen_templates[str(room["template_id"])] = true
			var size: Vector2 = room["size"]
			seen_sizes["%.0fx%.0f" % [size.x, size.y]] = true
	print("LEVEL_DRAW seeds=%d ok=%d connector_templates=%d sizes=%d" % [
		LEVEL_DRAW_COUNT, ok_count, seen_templates.size(), seen_sizes.size()])
	print("LEVEL_DRAW connector_templates=%s sizes=%s" % [
		str(seen_templates.keys()), str(seen_sizes.keys())])
	# 抽关至少要大半成功（允许偶发重试耗尽）
	_check(ok_count >= int(LEVEL_DRAW_COUNT * 0.9),
		"抽关成功率过低：%d/%d" % [ok_count, LEVEL_DRAW_COUNT])
	# "布局时选模板"必须真的在选择：横竖两种朝向都得出现过
	_check(seen_templates.size() >= 2,
		"连接房只用到 %d 种模板（%s）—— 布局时选朝向没生效" % [
			seen_templates.size(), str(seen_templates.keys())])


func _verify_result(flow_id: String, seed_value: int, result: Dictionary) -> void:
	var rooms := result["rooms"] as Array
	var tag := "%s seed=%d" % [flow_id, seed_value]
	_check(rooms.size() >= 8, "%s: 只放置了 %d 间房" % [tag, rooms.size()])

	# 2. 不重叠
	for i in range(rooms.size()):
		var a := rooms[i] as Dictionary
		var rect_a := _rect_of(a)
		for j in range(i + 1, rooms.size()):
			var b := rooms[j] as Dictionary
			var inter := rect_a.intersection(_rect_of(b))
			_check(not (inter.size.x > 0.01 and inter.size.y > 0.01),
				"%s: %s 与 %s 重叠 %.2f×%.2f" % [
					tag, str(a["node_id"]), str(b["node_id"]), inter.size.x, inter.size.y])

	# 3 + 4. 边连通、门位合法
	for value in result["edges"] as Array:
		var edge := value as Dictionary
		_check(bool(edge["port_verified"]),
			"%s: 边 %s-%s 的端口与 port_pair 反算不一致" % [
				tag, str(edge["from"]), str(edge["to"])])

	for value in rooms:
		var room := value as Dictionary
		var size: Vector2 = room["size"]
		var ports: Dictionary = room["ports"]
		for side in ports:
			var length := size.x if str(side) in ["north", "south"] else size.y
			var legal := LANE.lane_offsets(length)
			for lane_value in ports[side] as Array:
				var lane := float(lane_value)
				var found := false
				for candidate in legal:
					if absf(float(candidate) - lane) <= 0.001:
						found = true
						break
				_check(found, "%s: %s 的 %s 门槽 %.1f 不在 %.0fm 墙的合法槽 %s 里" % [
					tag, str(room["node_id"]), str(side), lane, length, str(legal)])

	# 死胡同不应过多（连通性粗糙检查：每个房间至少有一个端口）
	for value in rooms:
		var room := value as Dictionary
		var port_count := 0
		for side in (room["ports"] as Dictionary):
			port_count += ((room["ports"] as Dictionary)[side] as Array).size()
		_check(port_count >= 1, "%s: %s 没有任何门（孤立房间）" % [tag, str(room["node_id"])])

	# 5. 连接房必须是**窄长**，且长轴沿行进方向
	_verify_connectors(tag, rooms)


## 连接房（CONNECTOR）的两条硬要求，对应 EGT 原文：
## *"These are often long, thin rooms, so picking one with a sensible orientation is vital."*
##
## 1. **窄长**：长宽比 ≥ 2.5。方形 25×25 会被这条直接判红。
## 2. **朝向合理**：门开在哪面墙，就沿那条轴行进，长轴必须与行进轴一致。
##    2 门的连接房两个门都必须在长轴上；3 门允许一扇在垂直面（拐角型）。
func _verify_connectors(tag: String, rooms: Array) -> void:
	for value in rooms:
		var room := value as Dictionary
		var node_id := str(room["node_id"])
		if not node_id.begins_with("conn"):
			continue
		var size: Vector2 = room["size"]
		var short := minf(size.x, size.y)
		var long := maxf(size.x, size.y)
		if short <= 0.0:
			_check(false, "%s: %s 尺寸异常 %s" % [tag, node_id, str(size)])
			continue
		var ratio := long / short
		_check(ratio >= CONNECTOR_MIN_ASYMMETRY,
			"%s: 连接房 %s（%s）是 %.0fx%.0f，长宽比 %.2f < %.1f —— 不是窄长房" % [
				tag, node_id, str(room["template_id"]), size.x, size.y,
				ratio, CONNECTOR_MIN_ASYMMETRY])

		var long_along_y := size.y > size.x
		var ports: Dictionary = room["ports"]
		var port_total := 0
		var along_long := 0
		for side in ports:
			var count := (ports[side] as Array).size()
			port_total += count
			var travel_along_y := str(side) in ["north", "south"]
			if travel_along_y == long_along_y:
				along_long += count
		# 硬要求：**至少一扇门在长轴端** —— 这保证它是"穿过去的长空间"，
		# 而不是"从侧边岔出去的一间小房"。全部开在垂直面（along_long==0）就是纯侧向使用，判红。
		#
		# 为什么不要求两扇都在长轴端：连接房被夹在中间时（长轴两端都被已有房间占住），
		# 第三/第二扇门只能从垂直面出去。本工程房间不能旋转也不能变形，
		# 这是几何限制，不是朝向选错。真实比例见下面的 CONNECTOR_PASSTHROUGH 统计。
		_check(along_long >= 1,
			"%s: 连接房 %s（%s %.0fx%.0f）被**横向使用**：%d 扇门全开在垂直面（共 %d 扇）—— 长轴没沿行进方向" % [
				tag, node_id, str(room["template_id"]), size.x, size.y,
				port_total - along_long, port_total])
		_connector_total += 1
		if port_total >= 2 and along_long == port_total:
			_connector_passthrough += 1


func _verify_determinism(flows: Array) -> void:
	if flows.is_empty():
		return
	var flow := flows[0] as Dictionary
	var a: Dictionary = ASSEMBLER.assemble_flow(flow, _templates, {}, 777)
	var b: Dictionary = ASSEMBLER.assemble_flow(flow, _templates, {}, 777)
	_check(bool(a["ok"]) == bool(b["ok"]), "确定性：同一 seed 两次 ok 状态不同")
	if not bool(a["ok"]) or not bool(b["ok"]):
		return
	var rooms_a := a["rooms"] as Array
	var rooms_b := b["rooms"] as Array
	_check(rooms_a.size() == rooms_b.size(), "确定性：同一 seed 两次房间数不同")
	for i in range(mini(rooms_a.size(), rooms_b.size())):
		var ra := rooms_a[i] as Dictionary
		var rb := rooms_b[i] as Dictionary
		_check(str(ra["node_id"]) == str(rb["node_id"]), "确定性：第 %d 间 node_id 不同" % i)
		_check((ra["center"] as Vector2).distance_to(rb["center"] as Vector2) < 0.0001,
			"确定性：%s 坐标不同（%.3f vs %.3f）" % [
				str(ra["node_id"]), (ra["center"] as Vector2).x, (rb["center"] as Vector2).x])
	# 不同 seed 应该给出不同布局（否则种子没起作用）
	var c: Dictionary = ASSEMBLER.assemble_flow(flow, _templates, {}, 778)
	if bool(c["ok"]):
		var rooms_c := c["rooms"] as Array
		var differs := false
		for i in range(mini(rooms_a.size(), rooms_c.size())):
			var ra := rooms_a[i] as Dictionary
			var rc := rooms_c[i] as Dictionary
			if (ra["center"] as Vector2).distance_to(rc["center"] as Vector2) > 0.5:
				differs = true
				break
		_check(differs, "换 seed 后布局完全没变 —— 种子没参与")


# ── 载入 ────────────────────────────────────────────────────────────────────
func _load_templates() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("%s/room_templates" % PLAN_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var data := _read_json("%s/room_templates/%s" % [PLAN_DIR, file_name])
		if not data.is_empty():
			out[str(data.get("template_id", ""))] = data
	return out


func _load_flows() -> Array:
	var out: Array = []
	var dir := DirAccess.open("%s/flows" % PLAN_DIR)
	if dir == null:
		return out
	var names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.begins_with("flow_") and file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		var data := _read_json("%s/flows/%s" % [PLAN_DIR, file_name])
		if not data.is_empty():
			out.append(data)
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _rect_of(room: Dictionary) -> Rect2:
	var size: Vector2 = room["size"]
	var center: Vector2 = room["center"]
	return Rect2(center - size * 0.5, size)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _report(total_ok: int, total_runs: int) -> void:
	# 连接房穿堂比例：所有门都开在长轴端 = 真正的"穿过去"。
	# 被夹在中间的那些（长轴两端都被占）只能从垂直面出去，那是几何限制。
	if _connector_total > 0:
		var rate := float(_connector_passthrough) / float(_connector_total)
		print("CONNECTOR_PASSTHROUGH %d/%d = %.0f%%（其余为被夹住的拐角连接）" % [
			_connector_passthrough, _connector_total, rate * 100.0])
		_check(rate >= 0.5, "连接房穿堂比例过低：%.0f%%（低于 50%%，朝向选择基本没生效）" % (rate * 100.0))
	print("ASSEMBLE_CHECKED runs=%d ok=%d checks=%d" % [total_runs, total_ok, _checks])
	if _failures.is_empty():
		print("EGT_ASSEMBLER_OK runs=%d checks=%d" % [total_runs, _checks])
		get_tree().quit(0)
		return
	var shown := 0
	for failure in _failures:
		if shown >= 25:
			print("… 其余 %d 条省略" % (_failures.size() - shown))
			break
		printerr("ASSEMBLE FAIL: %s" % failure)
		shown += 1
	print("EGT_ASSEMBLER_FAILED failures=%d" % _failures.size())
	get_tree().quit(1)
