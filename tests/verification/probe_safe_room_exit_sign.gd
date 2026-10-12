extends Node
## 只读探针：安全房「退出门内侧地面 EXIT 霓虹灯标牌」（ENV-BATTLE-EXIT-NEON-SIGN v001）。
##
## 覆盖四件事：
##   1. 退出门识别：door_targets 该侧为空串的那扇（east）必须被测到，且只此一扇；
##   2. 摆位几何：牌顶边朝门、落在门内侧地面，与门洞所在网格线保持 INSET 退让，不穿插墙体；
##   3. 姿态：绕 X +90° 放平 ⇒ 发光面（本地 -Z）朝上；长边平行门洞（世界 Z 向 1.84m）；
##   4. 契约：visual_only / 无 StaticBody3D（不得在走行面制造隐形台阶）。
##   godot --headless --path . --scene res://tests/verification/probe_safe_room_exit_sign.tscn

const SIGN_NODE_NAME := "SafeRoomExitSign"
const EXPECTED_ASSET_ID := "ENV-BATTLE-EXIT-NEON-SIGN"
const EXPECTED_SIZE_M := Vector3(1.84, 0.76, 0.09)
const SIZE_TOLERANCE_M := 0.03
const UP_TOLERANCE := 0.02
const GROUND_TOLERANCE_M := 0.02

var failures: Array[String] = []


func _ready() -> void:
	print("=== 探针：安全房退出门 EXIT 霓虹灯标牌 ===")
	var room := DungeonRoom3D.new()
	room.configure({
		"room_id": "probe_exit_sign",
		"room_type": "STAIR_LOBBY",
		"size_class": "tower_cell",
		"doors": ["north", "east"],
		"door_targets": {"north": "probe_a", "east": ""},
		"seed": 4242,
		"custom_dimensions": Vector2(15.0, 15.0),
		"tower_module_shell": true,
	})
	add_child(room)
	room.ensure_shell_built()
	room.ensure_detail_built()
	await get_tree().physics_frame

	if room.call("_safe_room_retreat_direction") != "east":
		failures.append("退出门识别错误：%s（应为 east）" % room.call("_safe_room_retreat_direction"))
	if not bool(room.get_meta("safe_room_exit_sign", false)):
		failures.append("room meta safe_room_exit_sign 未置真")

	var sign_node := room.get_node_or_null(SIGN_NODE_NAME) as Node3D
	if sign_node == null:
		failures.append("找不到 %s 节点" % SIGN_NODE_NAME)
		_finish(room)
		return

	if str(sign_node.get_meta("exit_sign_direction", "")) != "east":
		failures.append("牌上 exit_sign_direction 不是 east")
	if str(sign_node.get_meta("exit_sign_asset_id", "")) != EXPECTED_ASSET_ID:
		failures.append("牌上 exit_sign_asset_id 不符")
	if not bool(sign_node.get_meta("visual_only", false)):
		failures.append("牌未声明 visual_only=true")

	var bodies := sign_node.find_children("*", "StaticBody3D", true, false)
	if not bodies.is_empty():
		failures.append("标牌带 StaticBody3D ×%d（会在走行面制造隐形台阶）" % bodies.size())

	# —— 世界 AABB（用网格 AABB 的 8 个角点过 global_transform）——
	var xform := sign_node.global_transform
	var mn := Vector3.INF
	var mx := -Vector3.INF
	var mesh_count := 0
	for value in sign_node.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mesh_count += 1
		var bb := mi.mesh.get_aabb()
		for i in range(8):
			var local := bb.get_endpoint(i)
			var world: Vector3 = xform * local
			mn = mn.min(world)
			mx = mx.max(world)
	if mesh_count == 0:
		failures.append("标牌内没有网格")
		_finish(room)
		return
	var size := mx - mn
	print("AABB min=%s max=%s size=%s" % [_v(mn), _v(mx), _v(size)])

	# 姿态：发光面（本地 -Z）朝上
	var facing: Vector3 = -(xform.basis.z).normalized()
	print("facing(local -Z -> world) = %s" % _v(facing))
	if absf(facing.y - 1.0) > UP_TOLERANCE:
		failures.append("发光面未朝上：local -Z 世界方向=%s" % _v(facing))

	# 长边平行门洞（east 门洞沿 Z）⇒ 世界 Z 向尺寸应是 1.84、X 向是 0.76
	if absf(size.z - EXPECTED_SIZE_M.x) > SIZE_TOLERANCE_M:
		failures.append("长边未平行门洞：世界 Z 向 %.3f（应 %.3f）" % [size.z, EXPECTED_SIZE_M.x])
	if absf(size.x - EXPECTED_SIZE_M.y) > SIZE_TOLERANCE_M:
		failures.append("门的法向占地 %.3f（应 %.3f）" % [size.x, EXPECTED_SIZE_M.y])
	if absf(size.y - EXPECTED_SIZE_M.z) > SIZE_TOLERANCE_M:
		failures.append("牌厚度 %.3f（应 %.3f）" % [size.y, EXPECTED_SIZE_M.z])

	# 背面贴地：AABB 底面必须落在走行面（y=0）
	print("牌底面 y=%.4f 顶面 y=%.4f" % [mn.y, mx.y])
	if absf(mn.y) > GROUND_TOLERANCE_M:
		failures.append("牌背面未贴走行面：底面 y=%.4f" % mn.y)

	# 落在门内侧地面（x>0 侧、且不顶到门洞所在网格线 x=7.5）
	print("牌 X 区间 [%.3f, %.3f]（门洞网格线 x=7.5）" % [mn.x, mx.x])
	if mn.x <= 0.0 or mx.x >= 7.5:
		failures.append("牌未落在东门内侧地面：x∈[%.3f, %.3f]" % [mn.x, mx.x])

	_finish(room)


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _finish(room: Node) -> void:
	room.queue_free()
	if failures.is_empty():
		print("PROBE_SAFE_ROOM_EXIT_SIGN_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("PROBE_FAIL %s" % failure)
		print("PROBE_SAFE_ROOM_EXIT_SIGN_FAIL count=%d" % failures.size())
		get_tree().quit(1)
