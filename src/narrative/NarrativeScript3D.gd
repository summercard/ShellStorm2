class_name NarrativeScript3D
extends RefCounted
## 一段剧本的**解析 + 校验**结果。剧本是 JSON（有序 + 时刻结构，扁表无法表达）。
##
## 本类只做「文件 → 校验过的数据结构」，不碰场景树、不播放、不改任何游戏状态。
## 播放由 NarrativeDirector3D 负责。契约见 docs/v0.1/08_技术施工_剧情触发.md §3.2 / §4。
##
## 校验原则：**能提前判死的绝不放到运行时**。radius 下限、cue 字段齐全、`at` 单调、
## 指令名形如 `域.动作` 都在这里判；判不过就整体拒绝加载（不半播）。

const SCHEMA_VERSION := 1

## 位置触发半径下限。理由：位置判定是**轮询**不是事件（见 08 文档 §4.2）。
## 按 0.1s 轮询、玩家最快约 8m/s 计，单次间隔位移约 0.8m，radius >= 1.0 才不会漏触发。
const MIN_POINT_RADIUS_M := 1.0
## 位置触发的垂直带默认容差：防止「在楼上走过、脚下正下方就是触发点」时误触发。
const DEFAULT_HEIGHT_TOLERANCE_M := 2.0

const TRIGGER_KIND_EVENT := "event"
const TRIGGER_KIND_POINT := "point"
## 缺省 = 只能被代码手动触发（NarrativeDirector.arm()）。
const TRIGGER_KIND_MANUAL := "manual"

const ONCE_RUN := "run"
const ONCE_FOREVER := "forever"
const ONCE_NEVER := "never"

var narrative_id := ""
var schema_version := 0
var duration := 0.0
var priority := 0
var trigger: Dictionary = {}
var cues: Array[Dictionary] = []

var errors: Array[String] = []
var warnings: Array[String] = []


func is_valid() -> bool:
	return errors.is_empty() and not cues.is_empty()


func describe() -> String:
	return "剧情『%s』 duration=%.2fs cues=%d trigger=%s" % [
		narrative_id, duration, cues.size(), str(trigger.get("kind", TRIGGER_KIND_MANUAL)),
	]


## 从目录登记处加载并校验。**不做任何兜底**：id 未登记、文件缺失、JSON 坏、
## 校验不过，一律返回带 errors 的对象，调用方按 errors 判死。
static func load_from_id(narrative_id: String) -> NarrativeScript3D:
	var result := NarrativeScript3D.new()
	result.narrative_id = narrative_id
	if not NarrativeCatalog.has_id(narrative_id):
		result.errors.append("剧本 id 『%s』未登记在 NarrativeCatalog。新增剧本必须同时登记 id → 路径。" % narrative_id)
		return result
	var path := NarrativeCatalog.path_for(narrative_id)
	if not FileAccess.file_exists(path):
		result.errors.append("剧本文件不存在：%s" % path)
		return result
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		result.errors.append("剧本文件为空或不可读：%s" % path)
		return result
	var decoded: Variant = JSON.parse_string(raw)
	if not (decoded is Dictionary):
		result.errors.append("剧本 JSON 顶层必须是对象：%s" % path)
		return result
	result._ingest(decoded as Dictionary, path)
	return result


## 直接用字典构造（验收与触发脚本自建剧本时用，不走文件）。
static func from_dictionary(source: Dictionary) -> NarrativeScript3D:
	var result := NarrativeScript3D.new()
	# 先认领 id 再校验：否则内存剧本一定撞上「narrative_id 与登记 id 不一致」，
	# 导致**任何**内存剧本都校验不过（验收与触发脚本自建剧本都走这条路）。
	result.narrative_id = str(source.get("narrative_id", ""))
	result._ingest(source, "<memory>")
	return result


func _ingest(source: Dictionary, source_label: String) -> void:
	var declared_id := str(source.get("narrative_id", ""))
	if declared_id.is_empty():
		errors.append("%s：缺少必填字段 narrative_id。" % source_label)
	elif declared_id != narrative_id:
		errors.append(
			"%s：文件内 narrative_id『%s』与登记 id『%s』不一致 —— 改名必须同时改登记表，"
			% [source_label, declared_id, narrative_id]
			+ "否则存档与触发注册会指向两个不同实体。"
		)

	schema_version = int(source.get("schema_version", 0))
	if schema_version != SCHEMA_VERSION:
		errors.append(
			"%s：schema_version=%d，本版只接受 %d。" % [source_label, schema_version, SCHEMA_VERSION]
		)

	priority = int(source.get("priority", 0))

	var raw_cues: Variant = source.get("cues", [])
	if not (raw_cues is Array) or (raw_cues as Array).is_empty():
		errors.append("%s：cues 必填且必须是非空数组。" % source_label)
		return
	var pending: Array[Dictionary] = []
	for index in range((raw_cues as Array).size()):
		var entry: Variant = (raw_cues as Array)[index]
		if not (entry is Dictionary):
			errors.append("%s：cues[%d] 不是对象。" % [source_label, index])
			continue
		var cue := (entry as Dictionary).duplicate(true)
		var at_raw: Variant = cue.get("at", null)
		if at_raw == null:
			errors.append("%s：cues[%d] 缺少必填字段 at。" % [source_label, index])
			continue
		# JSON 里数字解析成 float / int 都有可能，统一收成 float。
		if not (at_raw is float or at_raw is int):
			errors.append("%s：cues[%d].at 必须是数字。" % [source_label, index])
			continue
		var at := float(at_raw)
		if not is_finite(at) or at < 0.0:
			errors.append("%s：cues[%d].at=%s 必须 >= 0。" % [source_label, index, str(at_raw)])
			continue
		var verb := str(cue.get("do", ""))
		if verb.is_empty():
			errors.append("%s：cues[%d] 缺少必填字段 do。" % [source_label, index])
			continue
		if not verb.contains("."):
			errors.append(
				"%s：cues[%d].do=『%s』不是『域.动作』形式。" % [source_label, index, verb]
			)
			continue
		cue["at"] = at
		cue["do"] = verb
		pending.append(cue)

	if pending.is_empty():
		errors.append("%s：没有一条合法 cue。" % source_label)
		return

	# 按 at 升序稳定排序：同一 at 的 cue 保持**数组书写顺序**（作者按顺序表达同帧先后）。
	var stable: Array[Dictionary] = []
	for order in range(pending.size()):
		var item := pending[order]
		item["_order"] = order
		stable.append(item)
	stable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["at"]), float(b["at"])):
			return float(a["at"]) < float(b["at"])
		return int(a["_order"]) < int(b["_order"])
	)
	cues.clear()
	for item in stable:
		var clean := item.duplicate(true)
		clean.erase("_order")
		cues.append(clean)

	var declared_duration: Variant = source.get("duration", null)
	var last_at := float(cues[cues.size() - 1]["at"])
	if declared_duration == null:
		duration = last_at
	else:
		duration = float(declared_duration)
		if duration < last_at:
			errors.append(
				"%s：duration=%.2f 小于最后一条 cue 的 at=%.2f —— 收口时刻早于最后一步，"
				% [source_label, duration, last_at]
				+ "那条 cue 永远没有机会执行。"
			)

	_ingest_trigger(source, source_label)

	if not warnings.is_empty():
		for warning in warnings:
			push_warning("[NarrativeScript3D] %s" % warning)


func _ingest_trigger(source: Dictionary, source_label: String) -> void:
	var raw_trigger: Variant = source.get("trigger", null)
	if raw_trigger == null:
		trigger = {"kind": TRIGGER_KIND_MANUAL}
		return
	if not (raw_trigger is Dictionary):
		errors.append("%s：trigger 必须是对象。" % source_label)
		trigger = {"kind": TRIGGER_KIND_MANUAL}
		return
	var declared := (raw_trigger as Dictionary).duplicate(true)
	var kind := str(declared.get("kind", TRIGGER_KIND_MANUAL))
	declared["kind"] = kind
	match kind:
		TRIGGER_KIND_POINT:
			declared = _validate_point_trigger(declared, source_label)
		TRIGGER_KIND_EVENT:
			var on := str(declared.get("on", ""))
			if on.is_empty():
				errors.append("%s：event 触发必须写 on（事件名）。" % source_label)
			declared["on"] = on
			var filter: Variant = declared.get("filter", {})
			declared["filter"] = filter if filter is Dictionary else {}
		TRIGGER_KIND_MANUAL:
			pass
		_:
			errors.append(
				"%s：未知 trigger.kind『%s』（可选 event / point / manual）。" % [source_label, kind]
			)
	var once := str(declared.get("once", ONCE_RUN))
	if once not in [ONCE_RUN, ONCE_FOREVER, ONCE_NEVER]:
		errors.append(
			"%s：trigger.once『%s』非法（可选 run / forever / never）。" % [source_label, once]
		)
		once = ONCE_RUN
	declared["once"] = once
	declared["cooldown"] = maxf(0.0, float(declared.get("cooldown", 0.0)))
	trigger = declared


func _validate_point_trigger(declared: Dictionary, source_label: String) -> Dictionary:
	var point_raw: Variant = declared.get("point", null)
	if not (point_raw is Array) or (point_raw as Array).size() != 3:
		errors.append("%s：point 触发必须提供 point:[x, y, z]。" % source_label)
	else:
		var coordinates: Array = point_raw
		declared["point"] = Vector3(
			float(coordinates[0]), float(coordinates[1]), float(coordinates[2])
		)
	var radius := float(declared.get("radius", MIN_POINT_RADIUS_M))
	if radius < MIN_POINT_RADIUS_M:
		errors.append(
			"%s：radius=%.2f 小于下限 %.2f —— 位置判定是轮询，半径太小会在玩家快速"
			% [source_label, radius, MIN_POINT_RADIUS_M]
			+ "通过时漏触发（见 08 文档 §4.2）。"
		)
	declared["radius"] = radius
	var tolerance := float(declared.get("height_tolerance", DEFAULT_HEIGHT_TOLERANCE_M))
	if tolerance <= 0.0:
		errors.append("%s：height_tolerance 必须 > 0。" % source_label)
	declared["height_tolerance"] = tolerance
	return declared
