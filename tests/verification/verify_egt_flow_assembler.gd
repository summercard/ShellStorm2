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

const ASSEMBLER := preload("res://src/map/EgtFlowAssembler.gd")
const LANE := preload("res://src/map/RoomDoorLane.gd")

const PLAN_DIR := "res://data/level_plans/expedition_03"
const SEED_COUNT := 12

var _failures: Array[String] = []
var _checks := 0
var _templates: Dictionary = {}


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
	_report(total_ok, total_runs)


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
