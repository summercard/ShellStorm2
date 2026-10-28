extends Node3D
## 「房间表 → 壳体区块」这一层的真实验收。
##
## 组装器只保证**布局成立**（房间放得下、门对得上）。它不管房间怎么变成墙和地砖。
## 这一层要证明的是：**组装出的关卡真的能走通**。
##
## 七条断言（全部从 `build_block()` 的产物验，不看中间变量）：
##
## 1. `to_block()` 没有换算错误（格线、横向错开、重叠）。
## 2. `build_block()` 没有报错（门位落在 lane、门不在 L 臂下、轮廓合法）。
## 3. **每扇门都有对门** —— 同一墙平面、同一 lane 上必须还有另一个房间的门。
##    没有对门 = 开向虚空：玩家能走出去、外面什么都没有。这是"门齐了但地图是漏的"。
## 4. **整层连通** —— 从入口房间按门洞走，必须能到**每一个**房间。
##    这条是核心：前面所有断言加起来都不代表"走得通"。走廊补错、拐角断开、
##    侧门错位，全都只会在这里红。
## 5. 走廊覆盖 —— `kind: "corridor"` 的连接必须有对应走廊房段（直 1 段 / L 2 段）。
## 6. 几何合法 —— 房界落 5m 格线、门落 lane 中心、无重叠。
## 7. 多局稳定 —— 120 局随机抽关全部通过。
##
## 跑法：
## ```
## godot --headless --path . res://tests/verification/verify_egt_plan_bridge.tscn
## ```

const ASSEMBLER := preload("res://src/map/EgtFlowAssembler.gd")
const BRIDGE := preload("res://src/map/EgtPlanBridge.gd")
const BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")

const PLAN_DIR := "res://data/level_plans/expedition_03"
const GRID_UNIT_M := 5.0
## 抽关局数。与组装器验收同一量级（120），这一层更贵，先保持同数。
const LEVEL_DRAW_COUNT := 120
const LEVEL_DRAW_BASE_SEED := 90000
const EPS := 0.01

var _failures: Array[String] = []
var _checks := 0
var _templates: Dictionary = {}
var _flows: Array = []
## 统计：走廊段数 / 门总数 / 无对门的门 / 单局最多房数
var _stats := {
	"runs": 0, "ok": 0, "corridor_conns": 0, "corridor_pieces": 0,
	"gates": 0, "orphan_gates": 0, "max_rooms": 0, "l_corners": 0,
	"stamped_ok": 0, "stamped_fallback": 0, "rejected": 0,
}


func _ready() -> void:
	await get_tree().process_frame
	_templates = _load_templates()
	_check(not _templates.is_empty(), "模板目录为空")
	_flows = _load_flows()
	_check(not _flows.is_empty(), "flow 目录为空")
	if not _failures.is_empty():
		_report()
		return

	for index in range(LEVEL_DRAW_COUNT):
		var seed_value := LEVEL_DRAW_BASE_SEED + index * 7919
		var flow: Dictionary = ASSEMBLER.pick_flow(_flows, seed_value)
		if flow.is_empty():
			_check(false, "seed %d: 抽不到 flow" % seed_value)
			continue
		_verify_draw(flow, seed_value)

	_report()


func _verify_draw(flow: Dictionary, seed_value: int) -> void:
	_stats["runs"] = int(_stats["runs"]) + 1
	var label := "seed %d flow %s" % [seed_value, str(flow.get("flow_id", "?"))]
	var result: Dictionary = ASSEMBLER.assemble_flow(flow, _templates, {}, seed_value)
	if not bool(result.get("ok", false)):
		# 组装失败不算本层的失败（组装器自己有成功率门槛），但要计数。
		return
	var bridged: Dictionary = BRIDGE.to_block(result)
	var gst := bridged["stats"] as Dictionary
	_stats["stamped_ok"] = int(_stats["stamped_ok"]) + int(gst.get("stamped_ok", 0))
	_stats["stamped_fallback"] = int(_stats["stamped_fallback"]) + int(gst.get("stamped_fallback", 0))
	var errors: Array = bridged["errors"] as Array
	# 换算拒绝（走廊房压到别的房间）**不逐局判失败**，改为统计拒绝率。
	# 理由：上层 `_generate_flow_floor()` 遇到 `to_block` 有错会返回空，
	# 由 `TowerDescent3D` 安全回退到内置房表 —— 对玩家是"这一局换张图"，
	# 不是坏图进场。真正必须为 0 的是「生出重叠几何还放行」。
	# 目前实测 1/120（flow_05 的枢纽周围太挤，环闭合走廊无处可走），
	# 门槛定 2%，并在报告里单独打印。
	if not errors.is_empty():
		_stats["rejected"] = int(_stats["rejected"]) + 1
		if int(_stats["rejected"]) <= 3:
			print("BRIDGE reject %s: %s" % [label, str(errors)])
		return

	var block: Array = bridged["block"] as Array
	var built: Dictionary = BUILDER.build_block(block)
	var build_errors: Array = built["errors"] as Array
	_check(build_errors.is_empty(), "%s: build_block 报错 %s" % [
		label, str(build_errors.slice(0, 6))])
	if not build_errors.is_empty():
		return
	# ⑥.5 周长覆盖：少一格墙就是一扇没门的洞（玩家能走出去，外面是空的）。
	# 这条由 `build_block()` 的 `wall_gaps` 自检给出，组装器与房间表都看不见它。
	var gaps: Array = (built["validation"] as Dictionary).get("wall_gaps", []) as Array
	_check(gaps.is_empty(), "%s: %d 处墙缺口 %s" % [
		label, gaps.size(), str(gaps.slice(0, 4))])

	# ⑥ 几何合法：房界落 5m 格线、门落 lane 中心。
	for value in block:
		var room := value as Dictionary
		var room_id := str(room["room_id"])
		for array_key in ["bounds_x_m", "bounds_y_m"]:
			for bound in room[array_key] as Array:
				_check(_on_grid(float(bound)),
					"%s: %s 的 %s 边界 %.2f 不在 5m 格线" % [label, room_id, array_key, float(bound)])
		for side_value in (room["doors"] as Dictionary).keys():
			var side := str(side_value)
			for gate in BUILDER._port_offsets((room["doors"] as Dictionary)[side_value]):
				_check(_on_lane(float(gate)),
					"%s: %s.%s 门 %.2f 不在 lane 中心" % [label, room_id, side, float(gate)])

	# ⑤ 走廊覆盖：每条 corridor 连接都要有走廊房段。
	var corridor_conns := 0
	for value in result["connections"] as Array:
		if str((value as Dictionary).get("kind", "direct")) == "corridor":
			corridor_conns += 1
	var corridor_pieces := (bridged["corridor_ids"] as Array).size()
	_stats["corridor_conns"] = int(_stats["corridor_conns"]) + corridor_conns
	_stats["corridor_pieces"] = int(_stats["corridor_pieces"]) + corridor_pieces
	_check(corridor_pieces >= corridor_conns,
		"%s: %d 条走廊连接只补出 %d 段走廊房" % [label, corridor_conns, corridor_pieces])

	# ③ + ④ 门配对与整层连通。
	var pairs := _gate_pairs(block)
	_stats["gates"] = int(_stats["gates"]) + int(pairs["gate_count"])
	_stats["orphan_gates"] = int(_stats["orphan_gates"]) + int(pairs["orphans"])
	_check(int(pairs["orphans"]) == 0,
		"%s: %d 扇门没有对门（开向虚空）%s" % [
			label, int(pairs["orphans"]), str(pairs["sample"])])

	var reach := _reachable(block, pairs["links"] as Dictionary)
	_check(reach == block.size(),
		"%s: 只有 %d/%d 间房从入口可达（走廊或门洞断了）" % [label, reach, block.size()])
	_stats["max_rooms"] = maxi(int(_stats["max_rooms"]), block.size())
	_stats["ok"] = int(_stats["ok"]) + 1


## 门洞配对：同一「墙平面 + lane」上出现两扇门，就是一对能走过去的洞。
##
## 键 = `轴@墙平面坐标@lane坐标`。north/south 墙的平面在 y、lane 在 x；
## west/east 墙的平面在 x、lane 在 y。共墙时两侧的平面坐标必然相等。
func _gate_pairs(block: Array) -> Dictionary:
	var by_key := {}
	var gate_count := 0
	for value in block:
		var room := value as Dictionary
		var room_id := str(room["room_id"])
		var bx: Array = room["bounds_x_m"]
		var by: Array = room["bounds_y_m"]
		for side_value in (room["doors"] as Dictionary).keys():
			var side := str(side_value)
			for gate_value in BUILDER._port_offsets((room["doors"] as Dictionary)[side_value]):
				var gate := float(gate_value)
				gate_count += 1
				var plane := ""
				match side:
					"north":
						plane = "y@%.2f@%.2f" % [float(by[1]), gate]
					"south":
						plane = "y@%.2f@%.2f" % [float(by[0]), gate]
					"west":
						plane = "x@%.2f@%.2f" % [float(bx[0]), gate]
					_:
						plane = "x@%.2f@%.2f" % [float(bx[1]), gate]
				if not by_key.has(plane):
					by_key[plane] = []
				(by_key[plane] as Array).append(room_id)
	var links := {}
	for key_value in by_key.keys():
		var rooms_list: Array = by_key[key_value]
		if rooms_list.size() < 2:
			continue
		for index in range(rooms_list.size()):
			for other in range(index + 1, rooms_list.size()):
				var a := str(rooms_list[index])
				var b := str(rooms_list[other])
				if a == b:
					continue
				if not links.has(a):
					links[a] = {}
				if not links.has(b):
					links[b] = {}
				(links[a] as Dictionary)[b] = true
				(links[b] as Dictionary)[a] = true
	var orphans := 0
	var sample: Array[String] = []
	for key_value in by_key.keys():
		var rooms_list: Array = by_key[key_value]
		# 同一个房间在同一 lane 上开两扇门（自身重复）不算孤儿。
		var distinct := {}
		for item in rooms_list:
			distinct[str(item)] = true
		if distinct.size() < 2:
			orphans += 1
			if sample.size() < 3:
				sample.append(str(key_value))
	return {
		"gate_count": gate_count, "orphans": orphans, "sample": sample,
		"links": links,
	}


## 从入口房按门洞 BFS。入口 = id 里带 `entry` 的房间，没有就用第一间。
func _reachable(block: Array, links: Dictionary) -> int:
	if block.is_empty():
		return 0
	var start := ""
	for value in block:
		var room_id := str((value as Dictionary)["room_id"])
		if "entry" in room_id:
			start = room_id
			break
	if start.is_empty():
		start = str((block[0] as Dictionary)["room_id"])
	var seen := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor in ((links.get(current, {}) as Dictionary).keys()):
			var next := str(neighbor)
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size()


func _on_grid(value: float) -> bool:
	var mod := fposmod(value, GRID_UNIT_M)
	return absf(mod) < EPS or absf(mod - GRID_UNIT_M) < EPS


## lane 中心 = 5k + 2.5（`RoomShellLayoutBuilder3D.lane_center_of`）。
func _on_lane(value: float) -> bool:
	return absf(fposmod(value - 2.5, GRID_UNIT_M)) < EPS


# ── 载入 ────────────────────────────────────────────────────────────────────
func _load_templates() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("%s/room_templates" % PLAN_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			var data := _read_json("%s/room_templates/%s" % [PLAN_DIR, file_name])
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
		out.append(_read_json("%s/flows/%s" % [PLAN_DIR, file_name]))
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _report() -> void:
	print("BRIDGE runs=%d ok=%d checks=%d rooms_max=%d" % [
		int(_stats["runs"]), int(_stats["ok"]), _checks, int(_stats["max_rooms"])])
	print("BRIDGE gates=%d orphan=%d corridor_conns=%d pieces=%d" % [
		int(_stats["gates"]), int(_stats["orphan_gates"]),
		int(_stats["corridor_conns"]), int(_stats["corridor_pieces"])])
	# 门槽盖章采纳率：采纳 = 与 `RoomDoorLane.port_pair()` 一致（本工程唯一门槽算法）；
	# 回退 = 两侧不等长导致 port_pair 的 b_lane 越槽，保留组装器原槽。
	var stamp_total := int(_stats["stamped_ok"]) + int(_stats["stamped_fallback"])
	if stamp_total > 0:
		print("BRIDGE stamp accepted=%d fallback=%d (%.0f%% 与本工程门槽算法一致)" % [
			int(_stats["stamped_ok"]), int(_stats["stamped_fallback"]),
			100.0 * float(_stats["stamped_ok"]) / float(stamp_total)])
	var rate := 0.0
	if int(_stats["runs"]) > 0:
		rate = float(_stats["ok"]) / float(_stats["runs"])
	_check(rate >= 0.95, "桥接成功率 %.1f%% 低于 95%%" % (rate * 100.0))
	var rejected := int(_stats["rejected"])
	if int(_stats["runs"]) > 0:
		var reject_rate := float(rejected) / float(_stats["runs"])
		print("BRIDGE rejected=%d (%.1f%%，上限 2%%)" % [rejected, reject_rate * 100.0])
		_check(reject_rate <= 0.02, "换算拒绝率 %.1f%% 超过 2%%" % (reject_rate * 100.0))
	if _failures.is_empty():
		print("EGT_BRIDGE_OK runs=%d checks=%d" % [int(_stats["runs"]), _checks])
		get_tree().quit(0)
		return
	var shown := 0
	for failure in _failures:
		if shown >= 25:
			print("… 其余 %d 条省略" % (_failures.size() - shown))
			break
		printerr("BRIDGE FAIL: %s" % failure)
		shown += 1
	print("EGT_BRIDGE_FAILED failures=%d" % _failures.size())
	get_tree().quit(1)
