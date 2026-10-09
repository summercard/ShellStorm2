extends Node
## 探针：剧本 2.5 触发点是否覆盖**真人会走的两种走法**。
##
## 背景（业主真机反馈「剧本2.5好像用不了」）：折角平台是 8m × 2.887m 的矩形，两端边相距 2.887m。
##   · 沿作者路径走（`[06]→[05]→[04]→[03]`）会绕到**外缘**（z = −18.5071）；
##   · 真人抄近道走（`[06]→[03]` 直连）贴着**内缘**（z = −15.6203）。
## 旧触发点 (42.501, −18.0, −18.5071) 在外缘上，离内缘线 2.887m > 半径 2.5 ⇒ **抄近道不触发**。
## 现触发点取平台几何中心 (42.501, −18.0, −17.0637)：两侧各 1.443m，都在半径内。
##
## 本探针不驱动物理行走（楼梯爬升用 set_test_move_direction 不可靠），而是
##   ① 纯几何核对三种代表点到触发点的距离；
##   ② 把玩家瞬移到**内缘线中点**（抄近道者最远离触发点的位置），确认真的会触发。
##
## 运行：
##   godot --headless --path . res://tests/verification/probe_stairwell_walk_blackout.tscn

const SEED := 990099
const BLACKOUT_ID := "nar_tower_opening_02_5_stairwell_blackout"
const RADIUS := 2.5

var _failures: Array[String] = []
var _checks := 0
var _facility: DungeonRoom3D = null
var _tower: TowerDescent3D = null


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	_tower = scene.instantiate() as TowerDescent3D
	_tower.test_mode = true
	_tower.run_seed_override = SEED
	add_child(_tower)
	await _settle()

	_facility = (_tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	var player := _tower.get("player") as Player3D
	_check(_facility != null and player != null, "样本哨兵：facility 与玩家存在")
	if _facility == null or player == null:
		_finish()
		return

	var points: Array = _find_stair_points()
	_check(points.size() == 11, "找到楼梯的 11 个路径点（实际 %d）" % points.size())
	if points.size() != 11:
		_finish()
		return

	var trigger_variant: Variant = NarrativeDirector.point_origin_for_test(BLACKOUT_ID)
	_check(trigger_variant is Vector3, "剧本 2.5 触发点可解析")
	if not (trigger_variant is Vector3):
		_finish()
		return
	var trigger := trigger_variant as Vector3

	# 三种代表点：内缘中点（抄近道）、外缘中点（作者路径）、平台几何中心。
	var outer_mid := (points[5] as Vector3 + points[4] as Vector3) * 0.5  # z = −18.5071
	var inner_mid := (points[6] as Vector3 + points[3] as Vector3) * 0.5  # z = −15.6203
	var center_mid := (points[6] as Vector3 + points[4] as Vector3) * 0.5  # 几何中心

	print("\n########## 几何核对 ##########")
	print("-- 剧本触发点        = %s（半径 %.1f）" % [str(trigger), RADIUS])
	print("-- 内缘线中点(抄近道) = %s  距触发点 %.3f" % [str(inner_mid), _planar(inner_mid, trigger)])
	print("-- 外缘线中点(作者路) = %s  距触发点 %.3f" % [str(outer_mid), _planar(outer_mid, trigger)])
	print("-- 平台几何中心      = %s  距触发点 %.3f" % [str(center_mid), _planar(center_mid, trigger)])
	_check(
		_planar(inner_mid, trigger) < RADIUS,
		"抄近道的内缘线在半径内（%.2f < %.1f）" % [_planar(inner_mid, trigger), RADIUS]
	)
	_check(
		_planar(outer_mid, trigger) < RADIUS,
		"作者路径的外缘线在半径内（%.2f < %.1f）" % [_planar(outer_mid, trigger), RADIUS]
	)

	# 瞬移到「抄近道者离触发点最远的位置」——内缘线中点。若这里能触发，抄近道也必触发。
	print("\n########## 瞬移到内缘线中点（抄近道最不利位置） ##########")
	var stand := inner_mid + Vector3.UP * 0.05
	player.global_position = stand
	player.velocity = Vector3.ZERO
	await _settle()
	var fired := false
	for i in 25:
		player.global_position = stand
		player.velocity = Vector3.ZERO
		await get_tree().process_frame
		if NarrativeDirector.active_id() == BLACKOUT_ID:
			fired = true
			break

	print("-- 剧本 2.5 起播 = %s" % str(fired))
	# 触发那一帧 cue 还没派发（导演下一帧才派发），给一个观察窗再读灯态。
	for i in 12:
		await get_tree().process_frame
		if not bool(_facility.call("is_room_light_on")):
			break
	print("-- 灯态 = %s （期望 false）" % str(_facility.call("is_room_light_on")))
	_check(fired, "抄近道走法（内缘线）也会触发剧本 2.5")
	_check(not bool(_facility.call("is_room_light_on")), "触发后基地灯转暗")

	print("\n########## DISPATCH LOG ##########")
	for line in NarrativeDirector.dispatch_log():
		print("   %s" % line)
	print("\n########## DIAGNOSTICS ##########")
	for line in NarrativeDirector.diagnostics():
		print("   %s" % line)

	_finish()


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _find_stair_points() -> Array:
	for connector_value in (_tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null or not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		var ids := [
			str(connector.get_meta("from_room_id", "")),
			str(connector.get_meta("to_room_id", "")),
		]
		if "facility" in ids and "floor_01_entry" in ids:
			return connector.get_meta("path_points", []) as Array
	return []


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PROBE_OK   %s" % label)
	else:
		printerr("  PROBE_FAIL %s" % label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("\nPROBE_STAIRWELL_WALK_BLACKOUT_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		printerr(
			"\nPROBE_STAIRWELL_WALK_BLACKOUT_FAILED checks=%d failures=%d"
			% [_checks, _failures.size()]
		)
		get_tree().quit(1)
