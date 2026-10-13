extends Node
## 探针：Boss房02「玩家真的走得上去吗」—— 用**真身移动代码**跑三条线，查是否卡住。
##
## 为什么不能只看射线：业主的诉求是「不卡人」，那是**角色控制器**在走面上的行为，
## 不是「有没有碰撞面」。竖直面 0.12 m 的台阶射线照样能命中，但胶囊会被它顶住。
## 所以这里用 `Player3D.begin_narrative_walk()` + `tick_narrative_walk()` —— 它内部走的是
## `move_grounded()` → `move_and_slide()`，与玩家自己按 W 完全同一条链路。
##
## 三条线（房间局部坐标）：
##   A `stair_up`           梯脚 (0,-12) → 梯顶/高台 (0,38)      ← 业主报的「从下往上走被台阶卡住」
##   B `bridge_to_platform` 东走道 (30,-22.5) → 平台心 (0,-22.5)  ← 业主报的「走道到台子卡人」
##   C `platform_to_bridge` 平台心 (0,-22.5) → 东走道 (30,-22.5)  ← 反向
##
## 判定：到达目标（水平距离 ≤ 0.15 m）= PASS；连续 0.5 s 位移 < 2 mm = 卡住（FAIL）。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_traverse'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_boss_room02_walk_traverse.tscn

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel99_3D.tscn")
const SPEED_MPS := 3.2
const ARRIVE_M := 0.15
const STALL_MOVE_M := 0.002
const STALL_FRAMES := 30          # 30 帧 ≈ 0.5 s
const MAX_SECONDS := 90.0
const START_LIFT_M := 0.25        # 落点抬一点，避免生成时嵌进甲板

var _root: Window
var _failures: Array[String] = []


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	var tower: TowerDescent3D = EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 20260919
	_root.add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var room: DungeonRoom3D = tower._room_by_id["boss"]
	room.ensure_shell_built()
	room.ensure_detail_built()
	await get_tree().process_frame
	await get_tree().physics_frame

	await _run(tower, room, "stair_up", Vector3(0.0, 0.0, -12.0), Vector3(0.0, 0.0, 38.0))
	await _run(tower, room, "bridge_to_platform", Vector3(30.0, 0.0, -22.5), Vector3(0.0, 0.0, -22.5))
	await _run(tower, room, "platform_to_bridge", Vector3(0.0, 0.0, -22.5), Vector3(30.0, 0.0, -22.5))

	for failure in _failures:
		print("FAIL ", failure)
	print("BOSS_ROOM02_TRAVERSE_", "OK" if _failures.is_empty() else "FAILED",
		" runs=3 failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _run(
	tower: TowerDescent3D, room: DungeonRoom3D, label: String,
	from_local: Vector3, to_local: Vector3
) -> void:
	var player: Player3D = tower.player
	player.input_locked = true
	var start_world := room.to_global(from_local + Vector3.UP * START_LIFT_M)
	player.global_position = start_world
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var target_world := room.to_global(to_local + Vector3.UP * START_LIFT_M)
	target_world.y = player.global_position.y        # 只比水平，与 tick 的口径一致
	var start_gp := player.global_position
	var straight_m := Vector2(target_world.x - start_gp.x, target_world.z - start_gp.z).length()

	player.begin_narrative_walk(target_world, MAX_SECONDS, SPEED_MPS)
	var frames := int(MAX_SECONDS * 60.0)
	var stall := 0
	var last := player.global_position
	var low := player.global_position
	var reached := false
	var stalled_at := Vector3.ZERO
	var elapsed := 0.0
	for i in range(frames):
		player.tick_narrative_walk(1.0 / 60.0)
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		var gp := player.global_position
		if gp.y < low.y:
			low = gp
		if Vector2(gp.x - last.x, gp.z - last.z).length() < STALL_MOVE_M:
			stall += 1
		else:
			stall = 0
		last = gp
		if Vector2(gp.x - target_world.x, gp.z - target_world.z).length() <= ARRIVE_M:
			reached = true
			break
		if stall >= STALL_FRAMES:
			stalled_at = gp
			break
	player.end_narrative_walk()

	var travelled := Vector2(last.x - start_gp.x, last.z - start_gp.z).length()
	var remaining := Vector2(last.x - target_world.x, last.z - target_world.z).length()
	var dropped := start_gp.y - low.y
	print("TRAVERSE %-20s straight=%6.2fm travelled=%6.2fm remaining=%6.2fm " % [
		label, straight_m, travelled, remaining,
	], "t=%.1fs reached=%s dropped=%.3fm " % [elapsed, str(reached), dropped],
	"start=%s end=%s" % [vec_txt(start_gp), vec_txt(last)])
	if not reached:
		_failures.append("%s 未到达：走 %.2f/%.2f m 后%s（剩余 %.2f m，位置 %s）" % [
			label, travelled, straight_m,
			"卡在 %s" % vec_txt(stalled_at) if stalled_at != Vector3.ZERO else "超时",
			remaining, vec_txt(last),
		])
	if dropped > 0.6:
		_failures.append("%s 中途下坠 %.3f m（走面有洞）" % [label, dropped])


func vec_txt(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
