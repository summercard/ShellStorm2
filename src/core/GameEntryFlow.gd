extends Node
## 主场景入口意图的唯一所有者。
##
## TowerDescent3D 同时承载启动展示、99F 基地和塔楼行动，不能再用
## “主场景被加载”推断应显示启动页。所有局内跳转必须先登记一次性入口意图；
## 未登记的首次进程入口是冷启动，后续未登记重载则按普通游戏恢复处理。

signal entry_requested(context: Dictionary)
signal entry_consumed(context: Dictionary)

const KIND_MAIN_ENTRY := "main_entry"
const KIND_GAMEPLAY := "gameplay"

const REASON_COLD_START := "cold_start"
const REASON_EXPLICIT_MAIN_ENTRY := "explicit_main_entry"
const REASON_NEW_GAME_RESET := "new_game_reset"
const REASON_DEATH_RETURN_99F := "death_return_99f"
const REASON_SUCCESSFUL_RETURN_99F := "successful_return_99f"
const REASON_SCENE_REENTRY := "scene_reentry"

const SPAWN_SAVED_PROGRESS := "saved_progress"
const SPAWN_BASE_99F := "base_99f"

var _startup_entry_consumed := false
var _pending_context: Dictionary = {}
var _next_request_id := 1


func request_main_entry(reason := REASON_EXPLICIT_MAIN_ENTRY) -> int:
	return _set_pending(KIND_MAIN_ENTRY, reason, SPAWN_SAVED_PROGRESS)


func request_gameplay_entry(reason: String, spawn_target := SPAWN_SAVED_PROGRESS) -> int:
	return _set_pending(KIND_GAMEPLAY, reason, spawn_target)


func consume_main_scene_entry() -> Dictionary:
	var context: Dictionary
	if not _pending_context.is_empty():
		context = _pending_context.duplicate(true)
		_pending_context.clear()
	elif not _startup_entry_consumed:
		context = _make_context(0, KIND_MAIN_ENTRY, REASON_COLD_START, SPAWN_SAVED_PROGRESS)
	else:
		context = _make_context(0, KIND_GAMEPLAY, REASON_SCENE_REENTRY, SPAWN_SAVED_PROGRESS)
	_startup_entry_consumed = true
	context["show_main_entry"] = str(context.get("kind", "")) == KIND_MAIN_ENTRY
	entry_consumed.emit(context.duplicate(true))
	return context


func cancel_request(request_id: int) -> bool:
	if request_id <= 0 or int(_pending_context.get("request_id", -1)) != request_id:
		return false
	_pending_context.clear()
	return true


func peek_pending_entry() -> Dictionary:
	return _pending_context.duplicate(true)


func _set_pending(kind: String, reason: String, spawn_target: String) -> int:
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		normalized_reason = REASON_SCENE_REENTRY if kind == KIND_GAMEPLAY else REASON_EXPLICIT_MAIN_ENTRY
	var request_id := _next_request_id
	_next_request_id += 1
	_pending_context = _make_context(request_id, kind, normalized_reason, spawn_target)
	entry_requested.emit(_pending_context.duplicate(true))
	return request_id


func _make_context(request_id: int, kind: String, reason: String, spawn_target: String) -> Dictionary:
	return {
		"request_id": request_id,
		"kind": kind,
		"reason": reason,
		"spawn_target": spawn_target,
		"show_main_entry": kind == KIND_MAIN_ENTRY,
	}
