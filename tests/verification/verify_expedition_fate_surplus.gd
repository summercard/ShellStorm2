extends Node3D
## 验收：远征「编成外增援」——怪变多，但卡片价格与抽牌逻辑一个字不变。
##
## 业主口径 2026-10-18：「可以加怪，但是不要影响卡片价格和本身逻辑」。
## 本门禁把两件事同时钉住：
##   ① 战斗房存活账真的按 25% 变多（否则「加怪」是空承诺）；
##   ② 参考收益 / 逐门价表在开关前后**完全相同**（否则加怪会同步抬高卡价，等于白干）。
##
## 关键机制：增援在 `_commit_room_waves` 里并入第一波，**不写回关卡计划**，
## 所以 `FateEconomyService.configure_from_runtime` 看不见它。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77100118
const RATIO := 0.25
const SURPLUS_MIN := 1
const SURPLUS_MAX := 8

var failures: Array[String] = []
var checks := 0


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var off := await _probe_room(false)
	var on := await _probe_room(true)
	var on_again := await _probe_room(true)

	# ① 开关默认必须是开的（生产口径），这里用实例默认值验证。
	var probe := SCENE.instantiate() as TowerDescent3D
	_check(bool(probe.expedition_surplus_enabled), "增援默认未开启")
	probe.free()

	# ② 指定房总量必须精确：room_01 = 15、room_02 = 12（业主 2026-10-19 口径）。
	#    其余战斗房沿用 25% 比例，Boss 与交通房不加。
	var totals := {"room_01": 15, "room_02": 12}
	for room_id in totals.keys():
		var base: int = int(off["alive"].get(room_id, -1))
		var plus: int = int(on["alive"].get(room_id, -1))
		print(
			"ROOM %s type=%s base=%d plus=%d target=%d" % [
				room_id, str(on["types"].get(room_id, "")), base, plus, int(totals[room_id])
			]
		)
		_check(base > 0, "%s 关闭增援后没有敌人，用例前提不成立" % room_id)
		_check(plus == int(totals[room_id]), "%s 总量应为 %d，实得 %d" % [room_id, int(totals[room_id]), plus])

	# ③ Boss 房不加：前后完全一致
	var boss_base: int = int(off["alive"].get("boss", -1))
	var boss_plus: int = int(on["alive"].get("boss", -1))
	print("ROOM boss base=%d plus=%d" % [boss_base, boss_plus])
	_check(boss_base > 0 and boss_plus == boss_base, "Boss 房被加了增援（%d -> %d）" % [boss_base, boss_plus])

	# ④ 卡价与参考收益一字不变
	_check(
		JSON.stringify(off["segments"]) == JSON.stringify(on["segments"]),
		"增援改变了参考收益：%s vs %s" % [JSON.stringify(off["segments"]), JSON.stringify(on["segments"])]
	)
	_check(
		JSON.stringify(off["prices"]) == JSON.stringify(on["prices"]),
		"增援改变了逐门价表"
	)
	print("SEGMENTS_ON=", JSON.stringify(on["segments"]))
	print("PRICE_TABLE_ON=", JSON.stringify(on["prices"]))

	# ⑤ 可复现：同种子两次开启，敌人数与价表完全一致
	_check(
		JSON.stringify(on["alive"]) == JSON.stringify(on_again["alive"]),
		"同种子两次增援结果不同，随机流未隔离：%s vs %s" % [JSON.stringify(on["alive"]), JSON.stringify(on_again["alive"])]
	)
	_check(
		JSON.stringify(on["prices"]) == JSON.stringify(on_again["prices"]),
		"同种子两次价表不同"
	)

	print("EXPEDITION_FATE_SURPLUS_%s checks=%d failures=%d" % [
		"OK" if failures.is_empty() else "FAILED", checks, failures.size()
	])
	get_tree().quit(0 if failures.is_empty() else 1)


## 起一个远征实例，按开关跑 room_01 / room_02 / boss 的第一波，回收数据。
func _probe_room(enabled: bool) -> Dictionary:
	var dungeon := SCENE.instantiate() as TowerDescent3D
	dungeon.test_mode = true
	dungeon.run_seed_override = SEED_VALUE
	dungeon.expedition_surplus_enabled = enabled
	add_child(dungeon)
	for i in range(6):
		await get_tree().process_frame
	var economy: RefCounted = dungeon.get("_fate_economy")
	var snapshot: Dictionary = economy.get_snapshot()
	var alive: Dictionary = {}
	var types: Dictionary = {}
	var rooms: Dictionary = dungeon.get("_room_by_id")
	for room_id in ["room_01", "room_02", "boss"]:
		var room: DungeonRoom3D = rooms.get(room_id)
		if room == null:
			continue
		types[room_id] = str(room.room_type)
		dungeon.player.global_position = room.global_position + Vector3.UP * 0.1
		dungeon.force_enter_room_for_test(room_id)
		for i in range(4):
			await get_tree().process_frame
		alive[room_id] = int((dungeon.get("_alive_by_room") as Dictionary).get(room_id, -1))
	var result := {
		"alive": alive,
		"types": types,
		"segments": snapshot.get("segment_income_expected", []),
		"prices": snapshot.get("door_price_table", []),
	}
	dungeon.queue_free()
	for i in range(3):
		await get_tree().process_frame
	return result
