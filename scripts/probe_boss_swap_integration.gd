extends Node
## 集成探针：远征01 换房后，**玩家能不能真的从 room_10 走进 Boss 房、再走下楼梯**。
##
## 为什么必须实测：Boss 房的美术是手工烘焙的静态场景，而它的连接端口在
## `mode = constrained` + 全局 180° 旋转下由生成器**现算**。两者一旦差 180°，
## 端口说「门在这儿」而美术里那儿是实墙 —— 表现就是玩家在门口走不进去。
## 靠读代码判不出这个（plan 帧与世界帧的换算容易差一个号），只能真跑。
##
## 三条线：
##   ① room_10 中心 → Boss 高位平台（Boss 局部 (0,12,45)）—— 验「进得去」
##   ② 高位平台 → 楼梯中段（Boss 局部 (0,6,15)）—— 验「下得去坡、不卡人」
##   ③ 楼梯中段 → 平台中心（Boss 局部 (0,0,-22.5)）—— 验「落得到 BOSS 战场」
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_integration'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_boss_swap_integration.tscn

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SPEED_MPS := 3.2
const ARRIVE_M := 1.2
const STALL_MOVE_M := 0.002
const STALL_FRAMES := 40
const MAX_SECONDS := 22.0
const RUN_SEED := 77001199

var _root: Window
var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func _check(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(text)
		push_error(text)


func probe() -> void:
	var tower: TowerDescent3D = EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	_root.add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var room := tower._room_by_id.get("boss") as DungeonRoom3D
	if room == null:
		_check(false, "远征01 里找不到 boss 房")
		_finish()
		return
	var room_10 := tower._room_by_id.get("room_10") as DungeonRoom3D
	_check(room_10 != null, "找不到 room_10")
	room.ensure_shell_built()
	room.ensure_detail_built()
	await get_tree().physics_frame

	print("BOSS pos=%s dims=%s type=%s" % [
		_vec(room.global_position), str(room.get_dimensions()), room.room_type,
	])
	print("BOSS static_path=%s" % str(room.get("static_layout_scene_path")))
	print("BOSS meta: owner=%s scene=%s light_switch=%s" % [
		str(room.get_meta("walk_surface_owner", "<无>")),
		str(room.get_meta("walk_surface_scene", "<无>")),
		str(room.get_meta("authored_room_light_switch", "<无>")),
	])
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art_root == null:
		art_root = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	print("BOSS art_root=%s transform=%s yaw=%.1f°" % [
		str(art_root != null), str(art_root.transform) if art_root != null else "-",
		rad_to_deg(art_root.global_rotation.y) if art_root != null else 0.0,
	])
	var gate := room.find_child("ArenaGate", true, false) as BossRoom02ArenaGate3D
	if gate == null:
		_check(false, "换房后 Boss 房找不到 ArenaGate（门控没带过来）")
	else:
		print("BOSS arena_gate=%s" % str(gate.arena_gate_snapshot()))
		_check(gate.gate_count() == 3, "门控应有 3 道护栏，实得 %d" % gate.gate_count())
	# 走面碰撞是否随房带过来
	var walk_collision := room.find_child("BossRoom02WalkSurface", true, false)
	_check(walk_collision != null, "换房后找不到一体化走面碰撞 BossRoom02WalkSurface")

	var player: Player3D = tower.player
	player.input_locked = true

	# ①a 先验「门洞是不是真的开着」：从 room_10 门口内侧朝门外打一条射线。
	# ⚠️ 不能只看能不能走 —— room_10 房心常有家具，人会被家具卡住，那是探针起点选错，
	#    不是门的问题（第一版就栽在这儿：人只挪了 1 m 就被推开）。
	var space := _root.get_world_3d().direct_space_state
	var door_local := Vector3(2.5, 0.6, 15.0)
	var door_world := room_10.to_global(door_local)
	var door_hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(door_world, door_world + Vector3(0.0, 0.0, 3.0), 1)
	)
	print("DOOR room_10→boss 射线 %s → %s" % [
		_vec(door_world),
		"空（门洞通）" if door_hit.is_empty() else "命中 %s" % str((door_hit.collider as Node).name),
	])
	_check(door_hit.is_empty(), "①a room_10 通往 Boss 的门洞是堵的（美术帧与端口帧没对齐）")

	# ①a2 把人挡在门线上的那扇门打开。**门扇默认是关的**（本作的门要走交互开），
	# 挡在门线是预期行为，不是换房的问题 —— 第一版没开就判 FAIL，是探针自己的错。
	for side in ["north", "south", "east", "west"]:
		for probe_room in [room, room_10]:
			if probe_room == null:
				continue
			var door: Node3D = probe_room.get_door_node(side) as Node3D
			if door != null:
				door.set_open(true, true)
	await get_tree().physics_frame
	var door_after := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(door_world, door_world + Vector3(0.0, 0.0, 3.0), 1)
	)
	_check(door_after.is_empty(), "①a2 开门后门洞仍被挡（门扇没让位）")

	# ①b 从门口内侧 3 m 起步走进 Boss 房、走到高位平台
	var landing := room.to_global(Vector3(0.0, 12.0, 45.0))
	var from := room_10.to_global(Vector3(2.5, 0.0, 10.0)) + Vector3.UP * 0.25
	var ok_a := await _walk(player, from, landing, "room_10 → Boss 高位平台")
	_check(ok_a, "①b 从 room_10 走不进 Boss 房（门口不通/方向不符）")

	# ② 高位平台 → 楼梯中段
	var mid := room.to_global(Vector3(0.0, 6.0, 15.0))
	var ok_b := await _walk(player, player.global_position, mid, "高位平台 → 楼梯中段")
	_check(ok_b, "② 从高位平台下不去（楼梯接不上）")

	# ③ 楼梯中段 → 平台中心
	var platform := room.to_global(Vector3(0.0, 0.0, -22.5))
	var ok_c := await _walk(player, player.global_position, platform, "楼梯中段 → 平台中心")
	_check(ok_c, "③ 走不到 BOSS 战场平台")
	if ok_c:
		var local := room.to_local(player.global_position)
		print("BOSS platform_reached local=(%.2f, %.2f, %.2f)" % [local.x, local.y, local.z])
		_check(absf(local.y) < 0.6, "平台落脚高度异常：局部 y=%.2f（应≈0）" % local.y)

	_finish()


func _finish() -> void:
	for failure in _failures:
		print("FAIL ", failure)
	print("BOSS_SWAP_INTEGRATION_", "OK" if _failures.is_empty() else "FAILED",
		" checks=", _checks, " failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _walk(player: Player3D, from: Vector3, to: Vector3, label: String) -> bool:
	player.global_position = from
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var target := to
	target.y = player.global_position.y
	player.begin_narrative_walk(target, MAX_SECONDS, SPEED_MPS)
	var stall := 0
	var last := player.global_position
	var reached := false
	for i in range(int(MAX_SECONDS * 60.0)):
		player.tick_narrative_walk(1.0 / 60.0)
		await get_tree().physics_frame
		var gp := player.global_position
		if Vector2(gp.x - last.x, gp.z - last.z).length() < STALL_MOVE_M:
			stall += 1
		else:
			stall = 0
		last = gp
		if Vector2(gp.x - target.x, gp.z - target.z).length() <= ARRIVE_M:
			reached = true
			break
		if stall >= STALL_FRAMES:
			break
	player.end_narrative_walk()
	print("  WALK %-26s reached=%s from=%s end=%s" % [
		label, str(reached), _vec(from), _vec(last),
	])
	return reached


func _vec(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
