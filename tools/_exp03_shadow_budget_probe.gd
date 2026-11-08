extends Node
## 远征03 阴影灯预算探针（headless 可跑，秒级）。
##
## 判据：**DATA_ONLY 房间里的灯一辆都不许开阴影**（玩家进不去，影子看不见），
## 并且全局阴影灯数不超过上限。
##
## 为什么不按 `energy == 0` 判：玩家手电 `ForwardBeam` 平时 energy 也是 0，
## 但它必须一直开着阴影 —— 否则按 F 开灯的那一帧要现建阴影管线。它挂在玩家身上、
## 不属于任何房间，用「房间归属」判据天然把它排除。
##
## 用法
##
##   godot --headless --path . res://tools/_exp03_shadow_budget_probe.tscn --quit-after 2000
##
## 期望：`SHADOW_BUDGET_OK`，且 `data_only_shadow` 为 0。
## 只读。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED := 77003244
## 进房后真正该有的阴影灯上限：太阳 + 手电 + 当前房主灯 + 当前房室内补光。
## 超出这个数就说明有房间没把阴影收回去。
const SHADOW_LIGHT_LIMIT := 6


func _ready() -> void:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _i in 120:
		await get_tree().process_frame
	tower.call("_update_room_streaming", "start")
	for _i in 30:
		await get_tree().process_frame

	var shadow_total := 0
	var data_only_shadow := 0
	var offenders: Array[String] = []
	for node in tower.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if not light.shadow_enabled:
			continue
		shadow_total += 1
		var room := _owning_room(light)
		if room == null:
			continue
		if room.get_stream_state() != DungeonRoom3D.STREAM_DATA_ONLY:
			continue
		data_only_shadow += 1
		if offenders.size() < 8:
			offenders.append("%s/%s(energy=%.2f)" % [room.room_id, light.name, light.light_energy])

	print("SHADOW_BUDGET shadow_lights=%d data_only_shadow=%d limit=%d" % [
		shadow_total, data_only_shadow, SHADOW_LIGHT_LIMIT])
	if not offenders.is_empty():
		print("SHADOW_BUDGET offenders=%s" % ", ".join(offenders))

	var failures: Array[String] = []
	if data_only_shadow > 0:
		failures.append("%d 盏灯属于 DATA_ONLY 房间却仍开着阴影（每盏每帧多渲染一遍阴影贴图）" % data_only_shadow)
	if shadow_total > SHADOW_LIGHT_LIMIT:
		failures.append("阴影灯 %d 盏，超过上限 %d" % [shadow_total, SHADOW_LIGHT_LIMIT])
	if failures.is_empty():
		print("SHADOW_BUDGET_OK")
		get_tree().quit(0)
		return
	for reason in failures:
		print("SHADOW_BUDGET_FAIL %s" % reason)
	get_tree().quit(1)


func _owning_room(node: Node) -> DungeonRoom3D:
	var p := node.get_parent()
	while p != null:
		if p is DungeonRoom3D:
			return p as DungeonRoom3D
		p = p.get_parent()
	return null
