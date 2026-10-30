extends Node3D
## 探针：远征03 房间级状态的**存档往返**验证。
##
## 覆盖三件事（业主 2026-10-30 报「下线再上线门不见 / 存档大部分缺失」）：
##   A 门态 —— 气闸门恒关、连通门按 `room.cleared` 派生（不另存一份门态）
##   B 宝箱 —— 开过的箱子跨 detail 重建、跨存档都保持已开
##   C 杂物 —— 砸碎的罐子同理
##
## 关键手法：`_unload_runtime_detail()` + `ensure_detail_built()` 模拟**流送卸载重建**
## （与"走远再走回来"同一条路径），新旧实例是不同对象，能真正验证回灌有没有生效；
## 在同一个实例上反复断言是验不出来的。
##
## godot --headless --path . res://tests/verification/probe_expedition03_save_roundtrip.tscn
## ⚠️ 必须隔离用户目录：APPDATA=/tmp/godot_iso

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"

var _scene: Node
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		print("STATE_PROBE FAIL: 场景加载失败")
		get_tree().quit(1)
		return
	_scene = packed.instantiate()
	add_child(_scene)
	for i in range(900):
		await get_tree().process_frame
		if (_scene.get("_rooms") as Array).size() >= 10:
			break
	await get_tree().process_frame
	_check(bool(_scene.get("_flow_rules_active")), "远征03 必须走 flow 规则")

	await _verify_doors()
	await _verify_chest_roundtrip()
	await _verify_clutter_roundtrip()
	_verify_snapshot_carries_state()

	print("STATE_PROBE %s" % ("OK" if _failed == 0 else "FAIL count=%d" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------------------
# A 门态
# ---------------------------------------------------------------------------
func _verify_doors() -> void:
	var rooms: Dictionary = _scene.get("_room_by_id") as Dictionary
	var start: Node = rooms.get("start") as Node
	if start == null:
		_check(false, "找不到入口安全屋 start")
		return
	# 安全屋东墙是封闭抵达门（target 为空串）：退局气闸，任何路径都不得推开。
	var gate: Node = start.call("get_door_node", "east")
	_check(gate != null, "安全屋东墙必须有退局气闸门扇")
	if gate != null:
		_check(not bool(gate.get("is_open")), "A1 退局气闸门必须是关的（门板留在门洞里）")
		_check(bool((gate.call("get_snapshot") as Dictionary).get("blocks_passage", false)),
			"A2 退局气闸关着时必须挡路")
	# 北向是通往 01 号房的连通门：**可开启**但门板留在门洞里（走近才感应开）。
	# 2026-10-30 业主口径：「可开启状态，人走近了会自动打开，然后再关闭。」
	var north: Node = start.call("get_door_node", "north")
	if north != null:
		_check(bool(north.get("openable")), "A3 安全屋→01 号的连通门必须可开启")
		# 开门由**玩家距离**驱动（走远会自己关回去），不是被谁永久推开 ——
		# 出生点本来就贴着这扇门，所以这里查驱动方式而不是查当下开没开。
		_check(bool((north.call("get_snapshot") as Dictionary).get("proximity_auto", false)),
			"A3b 可开启的门必须由感应驱动（走远会自动关上）")

	# 续局语义：进一间"已清房"时门必须恢复**可开启**。
	# `_open_all_flow_doors()` 只挂在加载圈收尾里，续局根本不跑它。
	var r01: Node = rooms.get("room_01") as Node
	if r01 == null:
		_check(false, "找不到 room_01")
		return
	r01.set("cleared", true)
	for dir_value in (r01.get("door_targets") as Dictionary).keys():
		var door: Node = r01.call("get_door_node", str(dir_value))
		if door != null:
			door.call("set_openable", false, true)
	var before := _unopenable_door_count(r01)
	_scene.call("_apply_flow_room_seal", r01)
	var after := _unopenable_door_count(r01)
	_check(before > 0, "A4 前置：已把 room_01 的门全部置为不可开启（unopenable=%d）" % before)
	_check(after == 0, "A5 进已清房后连通门必须恢复可开启（before=%d after=%d）" % [before, after])


## 本房**不可开启**的门扇数。门板位置（`is_open`）不再是通行判据 ——
## 关着但可开启的门，玩家走近就开；关着且不可开启的门，走近纹丝不动。
func _unopenable_door_count(room: Node) -> int:
	var count := 0
	for dir_value in (room.get("door_targets") as Dictionary).keys():
		var door: Node = room.call("get_door_node", str(dir_value))
		if door != null and not bool(door.get("openable")):
			count += 1
	return count


# ---------------------------------------------------------------------------
# B 宝箱
# ---------------------------------------------------------------------------
func _verify_chest_roundtrip() -> void:
	var chest_room := _find_room_with(func(room: Node) -> bool:
		return not (room.get("chest_placements") as Array).is_empty())
	if chest_room == null:
		_check(false, "找不到带 chest_placements 的房间")
		return
	# 直接建 detail（`ensure_detail_built()` 就是进房时走的那条路径），
	# 再用 `_capture_room_runtime_state()` 采集 —— 与 `_capture_loaded_runtime_rooms()`
	# 对当前房做的事逐字相同。不走 `_update_room_streaming()`：无头场景里玩家坐标
	# 不在房里，流送状态推不上 ACTIVE，会被 `resolve_stream_state` 判成 DATA_ONLY。
	_scene.set("_current_room_id", str(chest_room.get("room_id")))
	chest_room.call("ensure_detail_built")
	await _settle(4)
	var chests: Array = chest_room.call("get_treasure_chests")
	print("STATE_PROBE DIAG chest_room=%s placements=%d detail_built=%s chests=%d" % [
		str(chest_room.get("room_id")),
		(chest_room.get("chest_placements") as Array).size(),
		str(chest_room.get("_detail_built")),
		chests.size(),
	])
	_check(chests.size() > 0, "B1 宝箱房进房后必须建出箱子（actual=%d）" % chests.size())
	if chests.is_empty():
		return
	var chest: Node = chests[0]
	var chest_id := str(chest.get("chest_id"))
	_check(not chest_id.is_empty(), "B2 宝箱必须有稳定 chest_id（否则记不进账）")

	# 走真实收口路径：`commit_opened()` 发 `opened` → 房间记账。
	chest.call("commit_opened")
	var ledger: Dictionary = chest_room.call("get_persistent_detail_state", "treasure_chests")
	# 账里存的是字典 `{"opened": true, "mimic": false}`，不是布尔。
	# Godot 4.6 起 `bool(Dictionary)` 无构造函数（`Nonexistent 'bool' constructor`），
	# 这里显式判"这条记录在且非空"。
	var ledger_entry: Variant = ledger.get(chest_id, false)
	_check(
		ledger_entry is Dictionary and not (ledger_entry as Dictionary).is_empty(),
		"B3 开箱后房间账必须记下（ledger=%s）" % str(ledger)
	)
	# 采集入口与 `_capture_loaded_runtime_rooms()` 对当前房调的是同一个函数。
	_scene.call("_capture_room_runtime_state", str(chest_room.get("room_id")))

	# 模拟流送卸载重建：新实例默认未开，回灌必须把它拉回已开。
	chest_room.call("_unload_runtime_detail")
	await _settle(2)
	chest_room.call("ensure_detail_built")
	await _settle(6)
	var rebuilt: Array = chest_room.call("get_treasure_chests")
	_check(rebuilt.size() > 0, "B4 detail 重建后箱子必须重新建出")
	if rebuilt.is_empty():
		return
	_check(rebuilt[0] != chest, "B5 重建后必须是新实例（旧实例已卸载）")
	_check(bool(rebuilt[0].call("is_opened")), "B6 重建后宝箱必须仍是已开（不能复原成可再开）")


# ---------------------------------------------------------------------------
# C 易碎杂物
# ---------------------------------------------------------------------------
func _verify_clutter_roundtrip() -> void:
	var clutter := _first_live_clutter()
	if clutter == null:
		_check(false, "场景里找不到任何建出来的易碎杂物")
		return
	var room := _owning_room(clutter)
	if room == null:
		_check(false, "杂物找不到所属房间")
		return
	var clutter_id := str(clutter.get_meta("clutter_id", ""))
	_check(not clutter_id.is_empty(), "C1 杂物必须有 clutter_id")

	clutter.call("shatter", Vector3.FORWARD)
	var ledger: Dictionary = room.call("get_persistent_detail_state", "breakable_clutter")
	_check(bool((ledger.get(clutter_id, {}) as Dictionary).get("broken", false)),
		"C2 砸碎后房间账必须记下（ledger_keys=%s）" % str(ledger.keys()))

	room.call("_unload_runtime_detail")
	await _settle(2)
	room.call("ensure_detail_built")
	await _settle(6)
	var restored := _clutter_by_id(room, clutter_id)
	_check(restored != null, "C3 重建后必须重新建出同一 clutter_id 的物件")
	if restored != null:
		_check(restored != clutter, "C4 重建后必须是新实例")
		_check(bool(restored.call("is_broken")), "C5 重建后杂物必须仍是已碎")
	# 与宝箱同一条采集入口：`_capture_loaded_runtime_rooms()` 对"当前房"就是调它。
	_scene.call("_capture_room_runtime_state", str(room.get("room_id")))


func _first_live_clutter() -> BreakableClutter3D:
	for value in get_tree().get_nodes_in_group("breakable_clutter_3d"):
		var clutter := value as BreakableClutter3D
		if clutter != null and is_instance_valid(clutter) and not clutter.is_queued_for_deletion():
			if _owning_room(clutter) != null:
				return clutter
	return null


func _clutter_by_id(room: Node, clutter_id: String) -> BreakableClutter3D:
	for value in get_tree().get_nodes_in_group("breakable_clutter_3d"):
		var clutter := value as BreakableClutter3D
		if clutter == null or clutter.is_queued_for_deletion():
			continue
		if str(clutter.get_meta("clutter_id", "")) != clutter_id:
			continue
		if room.is_ancestor_of(clutter):
			return clutter
	return null


func _owning_room(node: Node) -> Node:
	var rooms: Dictionary = _scene.get("_room_by_id") as Dictionary
	for room_value in rooms.values():
		var room := room_value as Node
		if room != null and room.is_ancestor_of(node):
			return room
	return null


# ---------------------------------------------------------------------------
# 存档：这两本账必须真的进快照
# ---------------------------------------------------------------------------
func _verify_snapshot_carries_state() -> void:
	var snap: Dictionary = _scene.call("build_runtime_save_snapshot")
	if snap.is_empty():
		_check(false, "快照为空（test_mode 下不采集）")
		return
	var segment: Dictionary = (
		(snap.get("world_state", {}) as Dictionary).get("segment_runtime_state", {}) as Dictionary
	)
	var with_chests := 0
	var with_clutter := 0
	for room_value in segment.values():
		var state := room_value as Dictionary
		if not (state.get("treasure_chests", {}) as Dictionary).is_empty():
			with_chests += 1
		if not (state.get("breakable_clutter", {}) as Dictionary).is_empty():
			with_clutter += 1
	_check(with_chests > 0, "D1 快照里必须有 treasure_chests 账（rooms=%d）" % segment.size())
	_check(with_clutter > 0, "D2 快照里必须有 breakable_clutter 账")


# ---------------------------------------------------------------------------
func _find_room_with(predicate: Callable) -> Node:
	var rooms: Dictionary = _scene.get("_room_by_id") as Dictionary
	for room_value in rooms.values():
		var room := room_value as Node
		if room != null and bool(predicate.call(room)):
			return room
	return null


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed += 1
	print("STATE_PROBE %s %s" % ["PASS" if ok else "FAIL", label])
