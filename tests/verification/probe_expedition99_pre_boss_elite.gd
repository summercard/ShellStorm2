extends Node3D
## 探针：真实加载 `ExpeditionLevel99_3D.tscn`，确认 boss 前置房 `room_01`
## 真的**同时**出普通怪与夺械者“收租人”。
##
## 为什么必须另开一篇而不只靠 `verify_expedition99_pre_boss_elite`：
## 那篇验的是「数据 → record → room 字段」这条链，**不跑房间的敌人生成**。
## 而本改动的失败形态恰恰是「字段全对、运行时房间里没有这只怪」——
## 因为 `_spawn_room_enemies` 里还有「只认盒子」「触发式遭遇」「空房降级」等多道
## 早退分支，任何一道先返回，追加逻辑就永远走不到，且**不打任何日志**。
##
## godot --headless --path . res://tests/verification/probe_expedition99_pre_boss_elite.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const ROOM_ID := "room_01"
const ELITE_ID := "elite_arms_taker"
const ASSET_ID := "ENM-ELITE-ARMS-TAKER-3D"


func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		print("EXP99_ELITE_PROBE_FAIL: 关卡场景加载失败")
		get_tree().quit(1)
		return
	var scene := packed.instantiate()
	add_child(scene)
	# 等房间装配完成：`_rooms` 至少 4 间（entry / room_01 / boss / extraction）。
	var rooms: Array = []
	for _i in range(400):
		await get_tree().process_frame
		var value: Variant = scene.get("_rooms")
		if value is Array and (value as Array).size() >= 4:
			rooms = value as Array
			break
	if rooms.is_empty():
		print("EXP99_ELITE_PROBE_FAIL: 房间未装配（_rooms 为空）")
		get_tree().quit(1)
		return
	var target: DungeonRoom3D = null
	var names: Array[String] = []
	for room in rooms:
		var typed := room as DungeonRoom3D
		if typed == null:
			continue
		names.append(typed.room_id)
		if typed.room_id == ROOM_ID:
			target = typed
	print("EXP99_ELITE_PROBE rooms=%s" % str(names))
	if target == null:
		print("EXP99_ELITE_PROBE_FAIL: 找不到 %s" % ROOM_ID)
		get_tree().quit(1)
		return
	# 房间字段是否真的落到了运行时房间上（探针先自证前置条件）。
	print("EXP99_ELITE_PROBE target room_id=%s room_type=%s elite_id='%s'" % [
		target.room_id, target.room_type, target.elite_id,
	])
	if target.elite_id != ELITE_ID:
		print("EXP99_ELITE_PROBE_FAIL: 运行时房间没拿到 elite_id（得到 '%s'）" % target.elite_id)
		get_tree().quit(1)
		return

	# 真正跑一次该房的敌人生成。
	var ok: Variant = scene.call("_spawn_room_enemies", target)
	await get_tree().process_frame
	await get_tree().process_frame
	var by_room: Dictionary = scene.get("_enemy_nodes_by_room") as Dictionary
	var nodes: Array = by_room.get(ROOM_ID, []) as Array
	var total := 0
	var elites: Array[String] = []
	var ordinary := 0
	for node in nodes:
		var enemy := node as Enemy3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		total += 1
		var data := enemy.get_enemy_data()
		if bool(data.get("is_elite", false)):
			elites.append("%s/%s" % [
				str(data.get("elite_id", "")), str(data.get("presentation_asset_id", "")),
			])
		else:
			ordinary += 1
	print("EXP99_ELITE_PROBE spawn_ok=%s total=%d ordinary=%d elites=%s" % [
		str(ok), total, ordinary, str(elites),
	])
	if total <= 0:
		print("EXP99_ELITE_PROBE_FAIL: %s 没有生成任何敌人" % ROOM_ID)
		get_tree().quit(1)
		return
	if elites.size() != 1:
		print("EXP99_ELITE_PROBE_FAIL: 精英数 %d（期望恰好 1）" % elites.size())
		get_tree().quit(1)
		return
	if elites[0] != "%s/%s" % [ELITE_ID, ASSET_ID]:
		print("EXP99_ELITE_PROBE_FAIL: 精英身份不符：%s" % elites[0])
		get_tree().quit(1)
		return
	# 「保留普通战斗」是本需求的一半，必须断言普通怪仍然在。
	if ordinary <= 0:
		print("EXP99_ELITE_PROBE_FAIL: 普通编成被替换了（ordinary=0），本需求要求保留普通战斗")
		get_tree().quit(1)
		return
	print("EXP99_ELITE_PROBE_OK: room_01 同时生成普通怪(%d)与 %s，普通战斗未被替换" % [ordinary, ELITE_ID])
	get_tree().quit(0)
