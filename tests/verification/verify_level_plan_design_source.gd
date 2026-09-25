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
##       LEVEL_PLAN_RUNTIME_GUARD_OK levels=N rooms=R checks=K plans=P boss_ids=B rewards=W
##   plans=P    = 设计源里填了 enemy_spawn_plan 的房数（真的带到运行时的条数）
##   boss_ids=B = 设计源里填了 boss_content_id 的房数
##   rewards=W  = 设计源里填了 reward_plan 的**槽位数**（trigger 条数，真的带到运行时的条数）
## 三个样本计数为 0 时另打 LEVEL_PLAN_RUNTIME_NOTE，避免「0 样本」伪装成通过
## （透传机制由 verify_test_level_99_flow 的手写 patch 探针单独覆盖）。
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
	var guard_plans := 0
	# 首领指派的**样本数**：当前没有任何关卡在数据里写 boss_content_id，此值会是 0，
	# 意味着「设计源 → 运行时」的透传断言是空跑。必须把它打出来，别让 0 样本
	# 伪装成通过；透传机制本身由 verify_test_level_99_flow 的手写 patch 探针单独覆盖。
	var guard_boss_ids := 0
	# 掉落计划的样本数（槽位数）。与 boss_ids 同理：0 样本必须显式声明。
	var guard_reward_slots := 0
	for level_id in targets:
		var level_plan := LOADER.load_level_plan(level_id)
		if level_plan.is_empty():
			continue  # 静态校验已报缺失，不重复
		var errors: Array[String] = []
		var level_rooms := 0
		var level_plans := 0
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
			var source_plans := _source_spawn_plans(level_id, floor_number)
			var source_boss_ids := _source_boss_content_ids(level_id, floor_number)
			var source_rewards := _source_reward_plans(level_id, floor_number)
			level_plans += source_plans.size()
			guard_plans += source_plans.size()
			guard_boss_ids += source_boss_ids.size()
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
				errors.append_array(
					_verify_spawn_plan_carried(floor_number, key, room, source_plans)
				)
				errors.append_array(
					_verify_boss_content_id_carried(floor_number, key, room, source_boss_ids)
				)
				errors.append_array(
					_verify_reward_plan_carried(floor_number, key, room, source_rewards)
				)
				# 计数器只数「真的带到了运行时」的槽位：源写了、运行时也有、且逐值一致。
				# 不一致时上面那条断言已经会让本关判失败，这里不需要再重复计错。
				guard_reward_slots += _carried_reward_slot_count(room, source_rewards)
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
				"LEVEL_PLAN_RUNTIME_LEVEL_OK %s rooms=%d plans=%d"
				% [level_id, level_rooms, level_plans]
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
			"LEVEL_PLAN_RUNTIME_GUARD_OK levels=%d rooms=%d checks=%d plans=%d boss_ids=%d rewards=%d"
			% [targets.size(), guard_rooms, guard_checks, guard_plans, guard_boss_ids, guard_reward_slots]
		)
		if guard_boss_ids == 0:
			print(
				"LEVEL_PLAN_RUNTIME_NOTE 设计源暂无 boss_content_id 样本，"
				+ "该字段的透传由 verify_test_level_99_flow 的手写 patch 探针覆盖"
			)
		if guard_reward_slots == 0:
			print(
				"LEVEL_PLAN_RUNTIME_NOTE 设计源暂无 reward_plan 样本，"
				+ "该字段的透传由 verify_test_level_99_flow 的手写 patch 探针覆盖"
			)
	return failed_levels


## 读该层设计源里每个房间的 enemy_spawn_plan（按 key 索引），用于下面的透传断言。
func _source_spawn_plans(level_id: String, floor_number: int) -> Dictionary:
	var out: Dictionary = {}
	var floor_plan := LOADER.load_floor_plan(level_id, floor_number)
	for value in floor_plan.get("rooms", []):
		if not (value is Dictionary):
			continue
		var raw := value as Dictionary
		var plan_value: Variant = raw.get("enemy_spawn_plan", {})
		if plan_value is Dictionary and not (plan_value as Dictionary).is_empty():
			out[str(raw.get("key", ""))] = (plan_value as Dictionary).duplicate(true)
	return out


## 断言设计源的刷怪计划**原样透传到运行时计划**。
##
## 这条断言存在的理由：LevelPlanLoader.normalize_floor 是白名单重建，设计源里
## 新增的字段若忘了在 Loader 登记，会被静默丢掉 —— 不报错、不警告、运行时回退
## 全局公式，表现为「我明明填了却没生效」。此处按 key 比对 `波次数|每波数量` 签名，
## 漏字段或中途被改写都会红。
func _verify_spawn_plan_carried(
	floor_number: int, key: String, room: Dictionary, source_plans: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	if not source_plans.has(key):
		return errors
	var expected := _spawn_plan_signature(source_plans[key] as Dictionary)
	var carried := room.get("enemy_spawn_plan", {}) as Dictionary
	if carried.is_empty():
		errors.append(
			"floor %d room %s: enemy_spawn_plan 未透传到运行时计划（应为 %s）"
			% [floor_number, key, expected]
		)
		return errors
	var actual := _spawn_plan_signature(carried)
	if actual != expected:
		errors.append(
			"floor %d room %s: enemy_spawn_plan 透传后被改写 %s -> %s"
			% [floor_number, key, expected, actual]
		)
	return errors


## 刷怪计划的紧凑签名：`波次数|每波签名,每波签名`。用于比对"填的"与"到的"是否一致。
## 两种写法各有签名形态（签名只需**对同一份数据稳定**，不必表达抽取结果）：
##   · 逐值固定（monsters）→ 该波数量之和（如 `3`）；
##   · 半钉死（pool）      → `p<种类数下界>-<上界>:<数量下界>-<上界>`（抽前无法定值，用声明区间）。
func _spawn_plan_signature(plan: Dictionary) -> String:
	var waves: Array = plan.get("waves", []) as Array
	var parts: Array[String] = []
	for wave_value in waves:
		var wave := wave_value as Dictionary
		if wave.has("pool"):
			var kinds := wave.get("kinds", {}) as Dictionary
			var count := wave.get("count", {}) as Dictionary
			parts.append("p%d-%d:%d-%d" % [
				int(kinds.get("min", -1)), int(kinds.get("max", -1)),
				int(count.get("min", 0)), int(count.get("max", 0)),
			])
			continue
		var wave_total := 0
		for monster_value in (wave.get("monsters", []) as Array):
			wave_total += int((monster_value as Dictionary).get("count", 0))
		parts.append(str(wave_total))
	return "%d|%s" % [waves.size(), ",".join(parts)]


## 读该层设计源里每个房间的 `boss_content_id`（按 key 索引），用于下面的透传断言。
func _source_boss_content_ids(level_id: String, floor_number: int) -> Dictionary:
	var out: Dictionary = {}
	var floor_plan := LOADER.load_floor_plan(level_id, floor_number)
	for value in floor_plan.get("rooms", []):
		if not (value is Dictionary):
			continue
		var raw := value as Dictionary
		var content_id := str(raw.get("boss_content_id", ""))
		if not content_id.is_empty():
			out[str(raw.get("key", ""))] = content_id
	return out


## 断言设计源的首领指派 `boss_content_id` **原样透传到运行时计划**。
##
## 与 `_verify_spawn_plan_carried` 同源理由：`LevelPlanLoader.normalize_floor` 是白名单
## 重建，房间级新字段忘登记就会被静默丢掉 —— 不报错、不警告，运行时退化成
## 「按层号取首领」或「不出首领」，表现为「我明明指定了却没生效」。此处逐房比对。
func _verify_boss_content_id_carried(
	floor_number: int, key: String, room: Dictionary, source_boss_ids: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	if not source_boss_ids.has(key):
		return errors
	var expected := str(source_boss_ids[key])
	var carried := str(room.get("boss_content_id", ""))
	if carried.is_empty():
		errors.append(
			"floor %d room %s: boss_content_id 未透传到运行时计划（应为 %s）"
			% [floor_number, key, expected]
		)
	elif carried != expected:
		errors.append(
			"floor %d room %s: boss_content_id 透传后被改写 %s -> %s"
			% [floor_number, key, expected, carried]
		)
	return errors


## 读该层设计源里每个房间的 `reward_plan`（按 key 索引），用于下面的透传断言。
func _source_reward_plans(level_id: String, floor_number: int) -> Dictionary:
	var out: Dictionary = {}
	var floor_plan := LOADER.load_floor_plan(level_id, floor_number)
	for value in floor_plan.get("rooms", []):
		if not (value is Dictionary):
			continue
		var raw := value as Dictionary
		var plan_value: Variant = raw.get("reward_plan", {})
		if plan_value is Dictionary and not (plan_value as Dictionary).is_empty():
			out[str(raw.get("key", ""))] = (plan_value as Dictionary).duplicate(true)
	return out


## 断言设计源的掉落计划 `reward_plan` **原样透传到运行时计划**。
##
## 与 `_verify_spawn_plan_carried` 同源理由：`LevelPlanLoader.normalize_floor` 是白名单
## 重建，房间级新字段忘登记就会被静默丢掉 —— 不报错、不警告，运行时退化成
## 「按全局默认公式抽奖」，表现为「我明明填了却没生效」。此处按 trigger 逐槽比对签名。
##
## 签名不含顺序、只含每个 trigger 的引用形态（spec_id / pool_id+draws+chance /
## inline+条目种类），因此「字段被中途改写」与「槽位被整条丢」都会红。
func _verify_reward_plan_carried(
	floor_number: int, key: String, room: Dictionary, source_rewards: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	if not source_rewards.has(key):
		return errors
	var expected := _reward_plan_signature(source_rewards[key] as Dictionary)
	var carried := room.get("reward_plan", {}) as Dictionary
	if carried.is_empty():
		errors.append(
			"floor %d room %s: reward_plan 未透传到运行时计划（应为 %s）"
			% [floor_number, key, expected]
		)
		return errors
	var actual := _reward_plan_signature(carried)
	if actual != expected:
		errors.append(
			"floor %d room %s: reward_plan 透传后被改写 %s -> %s"
			% [floor_number, key, expected, actual]
		)
	return errors


## 真的带到了运行时的槽位数：源里有、运行时也有、且引用签名逐值一致的 trigger 条数。
## 这是 `LEVEL_PLAN_RUNTIME_GUARD_OK ... rewards=W` 里 W 的口径 ——
## 「1.9 填了几条，这里就该是几」，填了却是 0 说明没接通。
func _carried_reward_slot_count(room: Dictionary, source_rewards: Dictionary) -> int:
	var key := str(room.get("key", ""))
	if not source_rewards.has(key):
		return 0
	var source := source_rewards[key] as Dictionary
	var carried := room.get("reward_plan", {}) as Dictionary
	var count := 0
	for trigger_value in source.keys():
		if not carried.has(trigger_value):
			continue
		if _reward_slot_signature(carried[trigger_value]) == _reward_slot_signature(source[trigger_value]):
			count += 1
	return count


## 掉落计划的紧凑签名：`trigger=引用形态,...,trigger=引用形态`（trigger 已排序，与书写顺序无关）。
func _reward_plan_signature(plan: Dictionary) -> String:
	var triggers: Array = plan.keys()
	triggers.sort()
	var parts: Array[String] = []
	for trigger_value in triggers:
		parts.append("%s=%s" % [str(trigger_value), _reward_slot_signature(plan[trigger_value])])
	return ",".join(parts)


## 单个 trigger 槽位的引用形态签名。四种合法写法各给一个可区分的形态：
##   {spec_id}          -> spec:<id>
##   {pool_id[,draws][,chance]} -> pool:<id>[/d=<n>][/c=<chance>]
##   {entries|fallback} -> inline:<条数>[<各条 kind>][|fb=<fallback 形态>]
## 其它 -> <unknown>/<not-object>/<empty>（静态校验另行拦住，这里只保证签名可区分）。
func _reward_slot_signature(slot_value: Variant) -> String:
	if not (slot_value is Dictionary):
		return "<not-object>"
	var slot := slot_value as Dictionary
	if slot.is_empty():
		return "<empty>"
	if slot.has("spec_id"):
		return "spec:%s" % [str(slot["spec_id"])]
	if slot.has("pool_id"):
		var pool_text := "pool:%s" % [str(slot["pool_id"])]
		if slot.has("draws"):
			pool_text += "/d=%d" % int(slot["draws"])
		if slot.has("chance"):
			pool_text += "/c=%.4f" % float(slot["chance"])
		return pool_text
	if slot.has("entries") or slot.has("fallback"):
		var raw_entries: Variant = slot.get("entries", [])
		var kinds: Array[String] = []
		if raw_entries is Array:
			for entry_value in (raw_entries as Array):
				if entry_value is Dictionary:
					kinds.append(str((entry_value as Dictionary).get("kind", "?")))
				else:
					kinds.append("<not-object>")
		var inline_text := "inline:%d[%s]" % [kinds.size(), ",".join(kinds)]
		if slot.has("fallback"):
			inline_text += "|fb=%s" % _reward_slot_signature(slot["fallback"])
		return inline_text
	return "<unknown>"


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
