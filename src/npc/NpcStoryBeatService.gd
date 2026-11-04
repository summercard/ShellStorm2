class_name NpcStoryBeatService
extends RefCounted
## 基地 NPC 的**剧情节拍**判定与落盘：某句话该不该说、说过没有。
##
## 为什么单开一个服务而不是塞进 `NpcCharacter3D`：
##   - 实体只该负责"怎么站、怎么转头、怎么把气泡打开"（表现）；
##   - "该不该开口"要读两类**别人拥有的**事实：精英是否真的遭遇过
##     （`EliteRosterService`）、这句是否已经播过（`BaseManager` 跨局档案）。
##     把这两条塞进实体，等于在场景节点里复制一份状态判定，验收时没法单独跑。
##   - 与 `EliteRosterService` 同规格：内容在 `NpcCatalog`，事实在服务，实体只消费结论。
##
## 落盘口径（**不改存档 schema**）：
##   复用 `BaseData.narrative_history` —— 它本来就是「跨局剧情事实」的唯一容器，
##   由 `BaseManager.commit_narrative_completion()` / `has_narrative_completed()` 读写，
##   已在 09 号存档文档登记、已有 `once = run` 剧本在用。本服务只占用一个**命名空间**：
##   键为 `npc_beat:<npc_id>:<beat_id>`。
##
##   为什么不另开 `BaseData` 字段：新增字段就是存档格式变更，收益只是一句迎宾，
##   不值得动全工程最敏感的那份数据（见 SOUL 的存档边界）。代价是
##   `narrative_history` 里会混进非剧本键 —— 所以键前缀是硬约定，验收与文档都盯它。
##
## 失败语义：
##   - `BaseManager` 不在（裸场景 / 工具脚本）⇒ 视为"没播过"，不崩；
##   - 写盘失败 ⇒ `mark_beat_played()` 返回 false，但**本局内仍不重播**
##     （静态内存表兜住），下次启动可能再提醒一次 —— 与 08 号文档对 `once` 剧本的
##     处置同一量级，不静默吞掉失败。

## 历史键命名空间。改它等于让所有玩家"以前看过的节拍重新播一遍"，不要轻改。
const HISTORY_KEY_PREFIX := "npc_beat:"

## 本局已播过的节拍（含"写盘失败但仍要压住重播"的情况）。
## 键 = 完整历史键；值 = true。进程级，不参与存档。
static var _session_played: Dictionary = {}


## 该 NPC 当前**该播且未播**的第一条节拍（含 `beat_id`）。没有则返回空字典。
##
## 求值顺序 = `NpcCatalog` 里的书写顺序。同一 NPC 有多条节拍时，先满足条件的那条先播；
## 一条播完后下次上线才会轮到下一条 —— 不做排队连播（玩家站在基地里被连说三段很怪）。
static func get_pending_beat(npc_id: String) -> Dictionary:
	for beat_id in NpcCatalog.get_story_beat_ids(npc_id):
		var beat := NpcCatalog.get_story_beat(npc_id, beat_id)
		if beat.is_empty():
			continue
		if not _requirements_met(beat):
			continue
		if is_beat_played(npc_id, beat_id):
			continue
		beat["beat_id"] = beat_id
		return beat
	return {}


## 该 NPC 当前是否还有任何"条件成立但没播"的节拍（装配器/验收用）。
static func has_pending_beat(npc_id: String) -> bool:
	return not get_pending_beat(npc_id).is_empty()


static func history_key(npc_id: String, beat_id: String) -> String:
	return "%s%s:%s" % [HISTORY_KEY_PREFIX, npc_id, beat_id]


## 已经播过没有。三处任一成立即算播过：本局内存表、跨局档案、显式测试覆写。
static func is_beat_played(npc_id: String, beat_id: String) -> bool:
	var key := history_key(npc_id, beat_id)
	if bool(_session_played.get(key, false)):
		return true
	if BaseManager == null:
		return false
	return BaseManager.has_narrative_completed(key)


## 记一次"已经说出口"。返回是否**成功落盘**；本局内存态无论如何都会压住重播。
static func mark_beat_played(npc_id: String, beat_id: String) -> bool:
	var key := history_key(npc_id, beat_id)
	_session_played[key] = true
	if BaseManager == null:
		push_warning("[NpcStoryBeatService] BaseManager 不可用，节拍『%s』只在本局生效。" % key)
		return false
	# `duration` = 这段台词播到了收口时刻（对白气泡播完即算，与时间轴剧本同一口径）。
	if not BaseManager.commit_narrative_completion(key, "duration"):
		push_warning("[NpcStoryBeatService] 节拍『%s』写盘失败，下次启动可能重复提醒。" % key)
		return false
	return true


## 台词（多条 lines 合成一段）。
static func get_beat_text(npc_id: String, beat_id: String) -> String:
	return NpcCatalog.get_story_beat_text(npc_id, beat_id)


# —— 事实求值 ——

## 逐条求值 `requires_*`。当前只有一种条件：精英已确认遭遇。
## 新增条件时在这里加分支，并同步 20 号文档的「节拍条件表」。
static func _requirements_met(beat: Dictionary) -> bool:
	var elite_id := str(beat.get("requires_elite_encountered", ""))
	if not elite_id.is_empty():
		return _has_encountered_elite(elite_id)
	return true


## "遇到"的口径：`encounter_count > 0`。
##
## 不是 `reserved_encounter_id` 非空 —— 预约发生在**这局抽到它**的时候（还没见面），
## 拿预约当"遇到过"会让还没踏进门的玩家就收到"你遇到收租人啦"。
## 也不是 `last_encounter_at_unix > 0` —— 脱离/清档后的旧记录可能只剩时间戳。
static func _has_encountered_elite(elite_id: String) -> bool:
	if EliteRosterService == null:
		return false
	var record := EliteRosterService.get_record(elite_id)
	if record.is_empty():
		return false
	if int(record.get("encounter_count", 0)) > 0:
		return true
	# 兜底：老档可能只有击杀/逃脱计数而没有遭遇计数（历史数据不完整）。
	return int(record.get("escape_count", 0)) > 0 or int(record.get("death_count", 0)) > 0


## 验收用：清掉本局内存表与跨局历史，回到"什么都没播过"。
static func reset_for_test() -> void:
	_session_played.clear()
	if BaseManager != null:
		BaseManager.replace_narrative_history_for_test({})
