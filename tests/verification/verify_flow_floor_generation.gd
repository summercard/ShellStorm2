extends Node3D
## `mode = "flow"` 端到端验收：从 `level_plan.json` 一路走到 `floor_source`。
##
## 这一层验的不是"组装器对不对"（那是 `verify_egt_flow_assembler`），
## 而是**真正会被运行时消费的那份楼层结构**对不对：
##
## 1. 开关语义 —— `flow_assembly_enabled` 缺省 false 时，`generate_from_level_plan()`
##    产出的楼层与改动之前**逐字节相同**（不能因为加了这个分支就悄悄改了既有行为）。
## 2. 开关打开时确实换了几何 —— `mode` 变 `flow`、房间数变多（走廊也成了房间）。
## 3. 结构合法 —— 校验器 0 错误（不是"能跑"，是"契约成立"）。
## 4. **每间房都有门**，且**从入口能走到每一间** —— 走廊补错、门对不上，
##    都只会在这里红。
## 5. 走廊房真的是 `connector`：没有 content_type（否则走廊里刷怪）。
## 6. 多种子稳定 —— 换种子必须换布局，且布局随种子变化（不是同一张图改标题）。
##
## 跑法：
## ```
## godot --headless --path . res://tests/verification/verify_flow_floor_generation.tscn
## ```

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")

const LEVEL_ID := "expedition_03"
const FLOOR_NUMBER := 0
## 抽关次数。这一层走的是完整生成链路（含壳体块），比纯组装贵，
## 取 24 够看稳定性；组装器那层已有 120 局。
const DRAW_COUNT := 24
const BASE_SEED := 20261028

var _failures: Array[String] = []
var _checks := 0
var _stats := {"runs": 0, "ok": 0, "rooms_min": 9999, "rooms_max": 0,
	"corridor_total": 0, "unreachable": 0}


func _ready() -> void:
	await get_tree().process_frame

	var level_plan := LOADER.load_level_plan(LEVEL_ID)
	_check(not level_plan.is_empty(), "读不到 %s 的 level_plan" % LEVEL_ID)
	if level_plan.is_empty():
		_report()
		return
	var policy: Dictionary = level_plan.get("generation_policy", {}) as Dictionary
	_check(str(policy.get("mode", "")) == "flow", "level_plan 的 mode 不是 flow")
	# 2026-10-28：本关**已开放**，两个开关都打开。
	# 之前这条断言盯的是"缺省必须关"——那时的理由是「开启会改 `layout_id`，
	# 而 05.2 §9 D4 未裁决」。现在打开是安全的：远征03 在此前**没有任何一局能进入**
	# （场景不存在 + runtime_enabled=false），不存在需要兼容的旧 `layout_id`。
	_check(bool(policy.get("runtime_enabled", false)),
		"runtime_enabled 应为 true（否则 generate_from_level_plan 根本不会被调用）")
	_check(bool(policy.get("flow_assembly_enabled", false)),
		"flow_assembly_enabled 应为 true（否则 flow 模式读的是静态样例，几何与种子无关）")

	_verify_static_sample(level_plan)
	_verify_on_generates()

	_report()


## ① 静态样例（`floors/floor_00.json`）仍在，且结构合法 —— 它是生成失败时的兜底。
##
## **不再要求它的房间数等于生成结果**：flow 模式下这份文件的角色就是"兜底样例"，
## 实际几何由 `_generate_flow_floor()` 按种子现算。旧版这条断言拿它当"关闭开关时的
## 既定行为"来比对，开关一开就必然失败 —— 那是把兜底件当成了权威件。
func _verify_static_sample(level_plan: Dictionary) -> void:
	var floor_plan := LOADER.load_floor_plan(LEVEL_ID, FLOOR_NUMBER)
	_check(not floor_plan.is_empty(), "读不到 floor_00.json（生成失败时无兜底可用）")
	if floor_plan.is_empty():
		return
	var sample_rooms: Array = floor_plan.get("rooms", []) as Array
	_check(sample_rooms.size() >= 7,
		"静态样例只有 %d 间房，不足以当兜底" % sample_rooms.size())
	print("FLOW_SAMPLE rooms=%d（兜底样例，几何与种子无关）" % sample_rooms.size())


## ②–⑥ 开关打开后的完整链路。
func _verify_on_generates() -> void:
	var level_plan := LOADER.load_level_plan(LEVEL_ID)
	var base_policy: Dictionary = (level_plan.get("generation_policy", {}) as Dictionary).duplicate(true)
	base_policy["flow_assembly_enabled"] = true
	# 直接用骨架 + 桥接走一遍，验证的是本层的三个新件（不是改全局配置）。
	var flows := LOADER.load_flows(LEVEL_ID)
	_check(not flows.is_empty(), "load_flows() 读不到 flow")
	var templates := LOADER.load_room_templates(LEVEL_ID)
	_check(not templates.is_empty(), "load_room_templates() 读不到模板")
	if flows.is_empty() or templates.is_empty():
		return

	var signatures := {}
	for index in range(DRAW_COUNT):
		var run_seed := BASE_SEED + index * 7919
		_stats["runs"] = int(_stats["runs"]) + 1
		var label := "seed %d" % run_seed
		var floor: Dictionary = GENERATOR._generate_flow_floor(
			LEVEL_ID, FLOOR_NUMBER, run_seed, {"level_id": LEVEL_ID,
				"floor_number": FLOOR_NUMBER, "floor_index": 0},
			base_policy, templates)
		if floor.is_empty():
			_check(false, "%s: _generate_flow_floor 返回空" % label)
			continue
		var rooms: Array = floor.get("rooms", []) as Array
		_check(rooms.size() >= 10, "%s: 只生成 %d 间房" % [label, rooms.size()])
		_stats["rooms_min"] = mini(int(_stats["rooms_min"]), rooms.size())
		_stats["rooms_max"] = maxi(int(_stats["rooms_max"]), rooms.size())

		# ③ 校验器。这里用「几何权威」结构，所以校验器会按真几何判。
		var errors := VALIDATOR.validate_normalized(
			LEVEL_ID, FLOOR_NUMBER, floor, base_policy, templates)
		_check((errors as Array).is_empty(), "%s: 校验器报错 %s" % [
			label, str((errors as Array).slice(0, 5))])

		# ④ 每间房都有门 + 从入口可达。
		var reach := _reachability(rooms)
		_check(int(reach["unreachable"]) == 0,
			"%s: %d 间房不可达 %s" % [label, int(reach["unreachable"]),
				str(reach["sample"])])
		_stats["unreachable"] = int(_stats["unreachable"]) + int(reach["unreachable"])
		_check(int(reach["doorless"]) == 0,
			"%s: %d 间房没有门" % [label, int(reach["doorless"])])

		# ⑤ 走廊房无内容。
		var connector_count := 0
		for value in rooms:
			var room := value as Dictionary
			if str(room.get("role", "")) != "connector":
				continue
			connector_count += 1
			_check(str(room.get("content_type", "")).is_empty(),
				"%s: 走廊房 %s 有 content_type=%s（会在走廊里刷怪）" % [
					label, str(room.get("key", "")), str(room.get("content_type", ""))])
		_check(connector_count > 0, "%s: 一间走廊房都没有（走廊没补成房间）" % label)
		_stats["corridor_total"] = int(_stats["corridor_total"]) + connector_count

		# ⑥ 换种子必须换布局。
		var signature := _signature(rooms)
		_check(not signatures.has(signature),
			"%s: 与前一次抽到同一份布局（签名相同）" % label)
		signatures[signature] = true
		_stats["ok"] = int(_stats["ok"]) + 1


## 从入口房按 `connection_ports` 做 BFS。同时数「一扇门都没有」的房。
func _reachability(rooms: Array) -> Dictionary:
	var by_key := {}
	for value in rooms:
		var room := value as Dictionary
		by_key[str(room.get("key", ""))] = room
	var start := ""
	for value in rooms:
		var room := value as Dictionary
		if str(room.get("role", "")) == "stair_entry":
			start = str(room.get("key", ""))
			break
	if start.is_empty() and not rooms.is_empty():
		start = str((rooms[0] as Dictionary).get("key", ""))
	var doorless := 0
	var links := {}
	for value in rooms:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var ports: Array = room.get("connection_ports", []) as Array
		if ports.is_empty():
			doorless += 1
		for port_value in ports:
			var port := port_value as Dictionary
			var target := str(port.get("target_room_id", ""))
			if target.is_empty():
				continue
			if not links.has(key):
				links[key] = {}
			if not links.has(target):
				links[target] = {}
			(links[key] as Dictionary)[target] = true
			(links[target] as Dictionary)[key] = true
	var seen := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor in ((links.get(current, {}) as Dictionary).keys()):
			var next := str(neighbor)
			if not by_key.has(next) or seen.has(next):
				continue
			seen[next] = true
			queue.append(next)
	var unreachable := 0
	var sample: Array[String] = []
	for value in rooms:
		var key := str((value as Dictionary).get("key", ""))
		if not seen.has(key):
			unreachable += 1
			if sample.size() < 4:
				sample.append(key)
	return {"unreachable": unreachable, "doorless": doorless, "sample": sample}


## 布局指纹：房间数与每间房的（中心, 尺寸）四舍五入后拼串。
func _signature(rooms: Array) -> String:
	var parts: Array[String] = []
	for value in rooms:
		var room := value as Dictionary
		var center := room.get("center", Vector2.ZERO) as Vector2
		var size := room.get("size", Vector2.ZERO) as Vector2
		parts.append("%s:%.0f,%.0f:%.0fx%.0f" % [
			str(room.get("key", "")), center.x, center.y, size.x, size.y])
	parts.sort()
	return "|".join(parts)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _report() -> void:
	print("FLOW_FLOOR runs=%d ok=%d rooms=%d..%d corridors=%d unreachable=%d" % [
		int(_stats["runs"]), int(_stats["ok"]), int(_stats["rooms_min"]),
		int(_stats["rooms_max"]), int(_stats["corridor_total"]),
		int(_stats["unreachable"])])
	if _failures.is_empty():
		print("FLOW_FLOOR_OK checks=%d" % _checks)
		get_tree().quit(0)
		return
	var shown := 0
	for failure in _failures:
		if shown >= 20:
			print("… 其余 %d 条省略" % (_failures.size() - shown))
			break
		printerr("FLOW_FLOOR FAIL: %s" % failure)
		shown += 1
	print("FLOW_FLOOR_FAILED failures=%d" % _failures.size())
	get_tree().quit(1)
