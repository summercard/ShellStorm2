extends Node
## 关卡设计源（L1/L2/L3）命令行校验器。
##
## 纯只读：不写任何文件，只读设计源并打印结论。校验规则全部走
## LevelPlanValidator 唯一实现（本脚本不含任何几何/门槽判断）。
##
## 运行：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . \
##     res://tests/verification/verify_level_plan_design_source.tscn -- --level=expedition_01
##   省略 --level 时校验 TARGET_LEVELS 全部。
##
## 判据：LEVEL_PLAN_VALIDATE_OK levels=N checks=K rooms=R templates=T
##       LEVEL_PLAN_RUNTIME_GUARD_OK levels=N rooms=R checks=K
## 失败：LEVEL_PLAN_VALIDATE_FAILED <level_id> errors=<n> 并逐条打印
##       LEVEL_PLAN_ERROR <level_id> <error>
##       LEVEL_PLAN_RUNTIME_GUARD_FAILED <level_id> errors=<n>
##       LEVEL_PLAN_RUNTIME_ERROR <level_id> <reason>
##
## 端口取数模式（只读，给写 L2 的作者用，避免任何人在第二种语言里手算门槽）：
##   ... -- --emit-ports --level=expedition_01
## 逐个房间打印可直接粘进 L2 的 ports 数组 + 该房当前的声明值：
##   PORT_JSON <level> <floor> <key> <derived ports compact json>
##   PORT_DATA <level> <floor> <key> derived|declared <ports compact json>

const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")

## 默认校验目标。新增关卡只需在此登记（或运行时 --level=xxx 指定）。
const TARGET_LEVELS := ["expedition_01", "battle_level01", "99"]

## 运行时产出护栏用的固定种子（确定性，不随调用时机变化）。
const RUNTIME_GUARD_SEED := 20260919
## 功能房 role → 运行时必须拿到的 type。与 FloorPlanGenerator._default_type_for_role
## 同口径，但这里**独立重写一遍**是刻意的：两侧共用一个常量会让断言失去意义。
const ROLE_EXPECTED_TYPE := {
	"stair_entry": "STAIR_LOBBY",
	"stair_exit": "STAIR_LOBBY",
	"extraction": "EXTRACTION",
	"boss": "BOSS",
}
const FUNCTIONAL_ROLES := ["stair_entry", "stair_exit", "extraction", "boss", "boss_prep"]
const CONTENT_ROLES := ["hub", "main", "branch"]


func _ready() -> void:
	var targets := _targets()
	if _has_flag("--emit-ports"):
		_emit_ports(targets)
		get_tree().quit(0)
		return
	var failures := 0
	var check_total := 0
	var room_total := 0
	var template_total := 0
	for level_id in targets:
		var report := VALIDATOR.validate_level(level_id)
		check_total += int(report.get("checks", 0))
		room_total += int(report.get("rooms", 0))
		template_total += int(report.get("templates", 0))
		var errors: Array = report.get("errors", [])
		if bool(report.get("ok", false)):
			print(
				"LEVEL_PLAN_LEVEL_OK %s floors=%d rooms=%d templates=%d checks=%d"
				% [
					level_id,
					int(report.get("floors", 0)),
					int(report.get("rooms", 0)),
					int(report.get("templates", 0)),
					int(report.get("checks", 0)),
				]
			)
		else:
			failures += 1
			print("LEVEL_PLAN_LEVEL_FAILED %s errors=%d" % [level_id, errors.size()])
			for error in errors:
				print("LEVEL_PLAN_ERROR %s %s" % [level_id, str(error)])
	if failures == 0:
		print(
			"LEVEL_PLAN_VALIDATE_OK levels=%d checks=%d rooms=%d templates=%d"
			% [targets.size(), check_total, room_total, template_total]
		)
		var guard_failed := _verify_runtime_outputs(targets)
		if guard_failed > 0:
			print("LEVEL_PLAN_RUNTIME_GUARD_FAILED levels=%d failed=%d" % [targets.size(), guard_failed])
			get_tree().quit(1)
			return
		get_tree().quit(0)
		return
	print(
		"LEVEL_PLAN_VALIDATE_FAILED levels=%d failed=%d checks=%d"
		% [targets.size(), failures, check_total]
	)
	get_tree().quit(1)


## 运行时产出护栏（05.2 §8 S3 的配套断言）。
##
## 为什么需要：**设计源静态自洽 ≠ 生成器产出可用**。功能房（入口 / 出口楼梯厅 /
## 撤离房 / Boss）的 type 是运行时认房的依据 —— 它既不是「内容类型」、不写在设计源里，
## 也过不了任何几何校验。实测曾把 entry 与 extraction 的 type 产成空串，而全部静态
## 校验仍然通过、生成器也说 valid=true。故此处直接调生成器，把这条隐形契约钉成
## 一条真会失败的断言。
##
## 返回失败关卡数。
func _verify_runtime_outputs(targets: Array[String]) -> int:
	var failed_levels := 0
	var guard_checks := 0
	var guard_rooms := 0
	for level_id in targets:
		var level_plan := LOADER.load_level_plan(level_id)
		if level_plan.is_empty():
			continue  # 静态校验已报缺失，不重复
		var errors: Array[String] = []
		var level_rooms := 0
		for entry in LOADER.list_floors(level_plan):
			var floor_number := int(entry.get("floor_number", 0))
			var plan := GENERATOR.generate_from_level_plan(
				level_id, floor_number, RUNTIME_GUARD_SEED
			)
			if plan.is_empty():
				errors.append("floor %d: 生成器返回空计划" % floor_number)
				continue
			if not bool(plan.get("valid", false)):
				errors.append("floor %d: 生成器自校验未通过" % floor_number)
			var rooms: Array = plan.get("rooms", [])
			level_rooms += rooms.size()
			var content_rooms := 0
			for value in rooms:
				var room := value as Dictionary
				var key := str(room.get("key", ""))
				var role := str(room.get("role", ""))
				var room_type := str(room.get("type", ""))
				var shown_type := room_type if not room_type.is_empty() else "<空>"
				if key.is_empty() or str(room.get("id", "")).is_empty():
					errors.append("floor %d room '%s': key 或运行时 id 为空" % [floor_number, key])
				var dimensions := room.get("dimensions", Vector2.ZERO) as Vector2
				if dimensions.x <= 0.0 or dimensions.y <= 0.0:
					errors.append(
						"floor %d room %s: 尺寸缺失 %s" % [floor_number, key, str(dimensions)]
					)
				if ROLE_EXPECTED_TYPE.has(role):
					var expected := str(ROLE_EXPECTED_TYPE[role])
					if room_type != expected:
						errors.append(
							"floor %d room %s: role=%s 的 type 应为 %s，实为 %s"
							% [floor_number, key, role, expected, shown_type]
						)
				elif role in CONTENT_ROLES:
					content_rooms += 1
					if room_type.is_empty():
						errors.append(
							"floor %d room %s: role=%s 未分配到内容类型"
							% [floor_number, key, role]
						)
					elif ROLE_EXPECTED_TYPE.values().has(room_type):
						errors.append(
							"floor %d room %s: 内容房被赋成功能类型 %s"
							% [floor_number, key, room_type]
						)
				elif room_type.is_empty():
					errors.append(
						"floor %d room %s: role=%s 未分配到类型" % [floor_number, key, role]
					)
			var declared_count := int(plan.get("content_room_count", -1))
			if declared_count != content_rooms:
				errors.append(
					"floor %d: content_room_count=%d 与实际内容房 %d 间不符"
					% [floor_number, declared_count, content_rooms]
				)
			guard_checks += 1
		guard_rooms += level_rooms
		if errors.is_empty():
			print(
				"LEVEL_PLAN_RUNTIME_LEVEL_OK %s rooms=%d" % [level_id, level_rooms]
			)
		else:
			failed_levels += 1
			print(
				"LEVEL_PLAN_RUNTIME_LEVEL_FAILED %s rooms=%d errors=%d"
				% [level_id, level_rooms, errors.size()]
			)
			for error in errors:
				print("LEVEL_PLAN_RUNTIME_ERROR %s %s" % [level_id, str(error)])
	if failed_levels == 0:
		print(
			"LEVEL_PLAN_RUNTIME_GUARD_OK levels=%d rooms=%d checks=%d"
			% [targets.size(), guard_rooms, guard_checks]
		)
	return failed_levels


## 支持 --level=<id> 覆盖默认目标；无参数时校验 TARGET_LEVELS。
func _targets() -> Array[String]:
	var out: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--level="):
			var level_id := text.substr("--level=".length())
			if not level_id.is_empty():
				out.append(level_id)
	if out.is_empty():
		for level_id in TARGET_LEVELS:
			out.append(str(level_id))
	return out


func _has_flag(flag: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if str(argument) == flag:
			return true
	return false


## 端口取数：把 RoomDoorLane 的推导结果打成可粘贴的 JSON。
## 只读，不写文件 —— 写入由作者/技能按设计源格式完成。
func _emit_ports(targets: Array[String]) -> void:
	for level_id in targets:
		var level_plan := LOADER.load_level_plan(level_id)
		if level_plan.is_empty():
			print("PORT_LEVEL_MISSING %s" % level_id)
			continue
		for entry in LOADER.list_floors(level_plan):
			var floor_number := int(entry.get("floor_number", 0))
			var normalized := LOADER.normalize_floor(level_id, floor_number)
			if normalized.is_empty():
				print("PORT_FLOOR_MISSING %s %d" % [level_id, floor_number])
				continue
			for value in normalized.get("rooms", []):
				var room := value as Dictionary
				var key := str(room.get("key", ""))
				var derived := room.get("derived_ports", []) as Array
				var declared := room.get("ports", []) as Array
				print(
					"PORT_JSON %s %d %s %s" % [level_id, floor_number, key, _compact(derived)]
				)
				print(
					"PORT_DATA %s %d %s %s %s"
					% [level_id, floor_number, key, "derived", _compact(derived)]
				)
				print(
					"PORT_DATA %s %d %s %s %s"
					% [level_id, floor_number, key, "declared", _compact(declared)]
				)


## 紧凑 JSON：块内不换行，块之间才缩进，便于整段粘进 L2。
func _compact(ports: Array) -> String:
	var rows: Array = []
	for value in ports:
		var port := value as Dictionary
		rows.append(
			{
				"port_id": str(port.get("port_id", "")),
				"target": str(port.get("target", "")),
				"side": str(port.get("side", "")),
				"lane_m": float(port.get("lane_m", 0.0)),
				"wall_length_m": float(port.get("wall_length_m", 0.0)),
			}
		)
	return JSON.stringify(rows)
