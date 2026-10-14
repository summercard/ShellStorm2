extends Node
## 探针：Boss房02 的**竞技场门控 + 过场镜头**逐项实测。
##
## 业主 2026-10-13 的需求拆成可证伪的断言：
##   ① 过场镜头：进楼梯后 3 m（z ≤ 37，且只在楼梯通道内）才触发，之前不触发；
##      过渡结束后镜头姿态 = 面板里那一帧（俯仰 −30° / 前后 +1.2 m / 平移 0）。
##   ② 封场线：平台内进 2 m（z ≤ −12，横贯平台宽度）才升护栏；之前不升。
##   ③ 封场后**真的走不出去**：用真身 `move_and_slide` 分别冲三个出口，全部被拦。
##   ④ 对照组：**把门控整个摘掉**后同样三条线走得出去 —— 否则③可能是被别的几何挡的假绿。
##   ⑤ 离开房间 → 镜头复位、重新武装（此刻首领仍活着，才有「下次还要打」这回事）。
##   ⑥ **首领一死即开闸**（业主 2026-10-14 裁定）：走**真实击杀路径**杀首领，
##      并刻意**留一只残留小怪** ⇒ 此刻 `room.cleared` 仍是 false。护栏照样落下、
##      照样走得出去 —— 这一条正是「首领一死就开闸」与旧「房间肃清才开闸」的分界。
##   ⑦ 首领已死 ⇒ 重进楼梯不重演过场、再越激活线不重新封场。
##
## ⚠️ 首领**只在⑥才刷**：它落在平台正中 `(0,0,−22.5)`，正是「冲出口」的起点，
##    早刷会让③的拦截变成「被首领身体挡住」的假绿、④的对照组直接变红（实测过）。
##
## ⚠️ 两个必须踩对的点（都曾把探针带沟里）：
##   · **落点要落在真实走面上**：楼梯是斜坡 `y=0.24z+2.505`，按 `y=0` 落点等于把玩家
##     扔进 12 m 深的井里，之后一切判定都不可信。
##   · **对照组不能只是「先不封场」**：东西桥在 z=−22.5，而激活线在 z=−12 ——
##     去桥**必然**越线，所以「封场前冲桥」这种对照组根本不可构造。
##     正确做法是另起一个实例、把门控节点整个 free 掉，再验证三处口子本来通。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_arenagate'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_boss_room02_arena_gate.tscn

## 关卡选择：默认 99；`SS_BOSS_LEVEL=expedition_01` 可把同一套断言原样跑到远征01。
## 两关的 boss 房是**同一张共享房图**（Boss房02），房内几何常量因此通用。
const EXP99_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel99_3D.tscn")
const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")


func _level_scene() -> PackedScene:
	return EXP01_SCENE if OS.get_environment("SS_BOSS_LEVEL").strip_edges() == "expedition_01" else EXP99_SCENE
const SPEED_MPS := 3.2
const ARRIVE_M := 0.60
const STALL_MOVE_M := 0.002
const STALL_FRAMES := 30
const MAX_SECONDS := 18.0
const START_LIFT_M := 0.25
## 镜头过渡 6 s，留余量再读数。
const CAMERA_SETTLE_SECONDS := 7.2

## 走面几何（与 `boss_room_02_walk_surface.tscn` 同源）。
const STAIR_HALF_WIDTH_M := 2.5
const STAIR_FOOT_Z := -10.0
const STAIR_HEAD_Z := 40.0
const STAIR_SLOPE := 0.24
const STAIR_INTERCEPT := 2.505
const FOOT_BLEND_Z := -10.44
const FOOT_BLEND_Y := 0.105
const LANDING_TOP_Y := 11.965
const HEAD_BLEND_Z := 41.0

## 三个出口的「走出去」目标（房间局部）。
const ESCAPES := {
	"stair_north": Vector3(0.0, 0.0, 6.0),
	"bridge_west": Vector3(-26.0, 0.0, -22.5),
	"bridge_east": Vector3(26.0, 0.0, -22.5),
}

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


## 走面高度（房间局部 y）。
func _surface_y(x: float, z: float) -> float:
	if absf(x) <= STAIR_HALF_WIDTH_M:
		if FOOT_BLEND_Z <= z and z <= STAIR_FOOT_Z:
			return lerpf(0.0, FOOT_BLEND_Y, (z - FOOT_BLEND_Z) / (STAIR_FOOT_Z - FOOT_BLEND_Z))
		if STAIR_FOOT_Z <= z and z <= STAIR_HEAD_Z:
			return STAIR_SLOPE * z + STAIR_INTERCEPT
		if STAIR_HEAD_Z <= z and z <= HEAD_BLEND_Z:
			return lerpf(STAIR_SLOPE * STAIR_HEAD_Z + STAIR_INTERCEPT, LANDING_TOP_Y,
				(z - STAIR_HEAD_Z) / (HEAD_BLEND_Z - STAIR_HEAD_Z))
		if z >= HEAD_BLEND_Z:
			return LANDING_TOP_Y
	return 0.0


func _spawn(label: String) -> Array:
	var tower: TowerDescent3D = _level_scene().instantiate() as TowerDescent3D
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
	tower.player.input_locked = true
	print("--- 实例 ", label, " ---")
	return [tower, room]


func probe() -> void:
	await _phase_gate()
	await _phase_boss_death()
	await _phase_control()
	_finish()


# ── 主实例：镜头 → 封场 → 冲出口 → 开闸 → 离房复位 ─────────────────────────
func _phase_gate() -> void:
	var pair := await _spawn("gate")
	var tower: TowerDescent3D = pair[0]
	var room: DungeonRoom3D = pair[1]
	var player: Player3D = tower.player
	var gate := room.find_child("ArenaGate", true, false) as BossRoom02ArenaGate3D
	if gate == null:
		_check(false, "房间找不到 ArenaGate 节点")
		return
	print("GATE snapshot=", gate.arena_gate_snapshot())
	_check(gate.gate_count() == 3, "护栏应有 3 道，实得 %d" % gate.gate_count())

	# ① 镜头触发线
	await _place(player, room, Vector3(0.0, 0.0, 39.0))
	_check(not gate.camera_descent_triggered(), "楼梯 1 m 处不该触发镜头（实得已触发）")
	await _place(player, room, Vector3(0.0, 0.0, 37.5))
	_check(not gate.camera_descent_triggered(), "楼梯 2.5 m 处不该触发镜头（实得已触发）")
	await _place(player, room, Vector3(8.0, 0.0, 30.0))
	_check(not gate.camera_descent_triggered(), "楼梯通道外不该触发镜头（实得已触发）")
	await _place(player, room, Vector3(0.0, 0.0, 36.5))
	_check(gate.camera_descent_triggered(), "楼梯 3.5 m 处应已触发镜头（实得未触发）")

	await get_tree().create_timer(CAMERA_SETTLE_SECONDS).timeout
	var pose: Dictionary = player.get_camera_pose_offsets()
	print("CAMERA pose=", pose, "  camera_above_player=%.3f m" % (
		player.camera.global_position.y - player.global_position.y))
	_check(absf(float(pose["pitch_deg"]) + 30.0) <= 0.5,
		"镜头俯仰应为 −30°，实得 %.2f°" % float(pose["pitch_deg"]))
	_check(absf(float(pose["trailing_m"]) - 1.2) <= 0.05,
		"镜头前后应为 +1.2 m，实得 %.3f m" % float(pose["trailing_m"]))
	_check((pose["pan_m"] as Vector3).length() <= 0.01, "镜头平移应为 0，实得 %s" % str(pose["pan_m"]))

	# ② 封场线：线前不封、线后封（必须放在任何「深入平台」动作之前）
	await _place(player, room, Vector3(0.0, 0.0, -11.5))
	_check(not gate.is_arena_sealed(), "平台内 1.5 m 处不该封场（实得已封）")
	_check(not room.cleared, "未击杀 Boss 时房间不该是已肃清")
	_check(not tower.is_room_boss_defeated(room.room_id), "未击杀首领时不该判首领阵亡")
	await _place(player, room, Vector3(6.0, 0.0, -12.6))
	_check(gate.is_arena_sealed(), "平台内 2.6 m 处应已封场（实得未封）")
	await get_tree().create_timer(1.8).timeout
	var heights := gate.gate_local_heights()
	print("GATE raised heights=", heights)
	for h in heights:
		_check(absf(h) <= 0.01, "护栏应升到 y=0（与走面齐平），实得 %.3f" % h)

	# ③ 封场后冲三个出口
	for key in ESCAPES.keys():
		var reached := await _try_escape(player, room, ESCAPES[key])
		_check(not reached, "封场后仍能从 %s 走出去（护栏没拦住）" % key)

	# ⑤ 离开房间 → 镜头复位 + 重新武装（此刻首领**尚未**阵亡，才该重新武装）
	# ⚠️ 必须走到**房间足迹之外**（本房局部 z ∈ [−50, 50]，高位平台 z≤50 仍在房里）；
	#    落在 z=44 这种「还在房内的高台」不会复位 —— 曾经这么写过，白红一条。
	await _place(player, room, Vector3(0.0, 0.0, 52.0))
	await get_tree().create_timer(1.8).timeout
	print("CAMERA after leaving pose=", player.get_camera_pose_offsets())
	_check(not player.has_camera_pose_offset(),
		"离开房间后镜头应复位，实得 %s" % str(player.get_camera_pose_offsets()))
	_check(not gate.camera_descent_triggered(), "离开房间后应重新武装镜头")
	_check(bool(gate.arena_gate_snapshot().get("camera_armed", false)),
		"首领仍活着时，离开房间应重新武装过场（快照 camera_armed 应为 true）")

	tower.free()
	await get_tree().process_frame


# ── 首领之死实例：**首领一死即开闸**（含「残留增援仍在场」这条分界）──────────
##
## 为什么另起一个实例：首领落在平台正中 `(0,0,−22.5)`，而「冲出口」的起点正好也是
## `(0,0,−22.5)` —— 首领在场会把冲出口变成「被首领身体挡住」的假绿（实测过）。
## 本实例里首领**在被封场后立即击杀**，走线只在首领已死之后才用，两条互不干扰。
func _phase_boss_death() -> void:
	var pair := await _spawn("boss_death")
	var tower: TowerDescent3D = pair[0]
	var room: DungeonRoom3D = pair[1]
	var player: Player3D = tower.player
	var gate := room.find_child("ArenaGate", true, false) as BossRoom02ArenaGate3D
	if gate == null:
		_check(false, "房间找不到 ArenaGate 节点")
		return
	# ⚠️ 首领必须**趁早**刷：一旦玩家进过房、房间被「揭示」，再调
	#    `_prepare_revealed_hostile_room` 会因已刷过而空手而归（节点已散、存活账仍在）。
	tower._prepare_revealed_hostile_room(room)
	var boss := tower._boss_reinforcement_boss(room.room_id)
	_check(boss != null, "[首领之死] 应能拿到首领 —— 开闸判据要真实可测，不能只靠改标志位")
	if boss == null:
		tower.free()
		return
	_check(not tower.is_room_boss_defeated(room.room_id), "[首领之死] 首领还在时不该判阵亡")

	# 封场（首领在场也照样封 —— 这正是实战里的样子）
	await _place(player, room, Vector3(0.0, 0.0, -11.5))
	_check(not gate.is_arena_sealed(), "[首领之死] 激活线前不该封场")
	await _place(player, room, Vector3(6.0, 0.0, -12.6))
	_check(gate.is_arena_sealed(), "[首领之死] 越过激活线应封场")

	# 补 1 只残留小怪 ⇒ 首领死后 `room.cleared` **仍为 false**。
	# 没有这一步，新旧两种口径（看首领死 / 看清房）在断言上完全等价、区分不开。
	var survivor := tower.narrative_spawn_enemies(
		"boss", "melee_chaser", 1, _to_world(room, Vector3(-9.0, 0.0, -31.0))
	)
	_check(survivor == 1, "[首领之死] 应能补刷 1 只残留小怪（实得 %d）" % survivor)

	# 走**真实击杀路径**：验 `_on_enemy_killed` 的首领分支有没有真的登记。
	tower._on_enemy_killed(boss, boss.get_enemy_data())
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(tower.is_room_boss_defeated(room.room_id), "[首领之死] 击杀后应标记首领阵亡")
	_check(
		not room.cleared,
		"[首领之死] 残留小怪仍在 ⇒ 房间不该是已肃清（这正是新旧口径的分界）"
	)
	_check(
		int(tower._alive_by_room.get(room.room_id, 0)) > 0,
		"[首领之死] 残留小怪应仍在存活账上，实得 %d"
			% int(tower._alive_by_room.get(room.room_id, 0))
	)
	await get_tree().create_timer(1.8).timeout
	var heights := gate.gate_local_heights()
	print("BOSSDEATH heights=", heights)
	_check(not gate.is_arena_sealed(), "[首领之死] 首领阵亡后应开闸（实得仍封着）")
	for h in heights:
		_check(h < -2.0, "[首领之死] 护栏应降回井下，实得 %.3f" % h)
	_check(
		await _try_escape(player, room, ESCAPES["bridge_east"]),
		"[首领之死] 开闸后应能走出去（残留小怪还在场也照样走得出去）"
	)

	# 首领已死 ⇒ 重进不重演过场、再越激活线不重新封场
	await _place(player, room, Vector3(0.0, 0.0, 36.5))
	await get_tree().process_frame
	_check(not gate.camera_descent_triggered(), "[首领之死] 首领已死，重进楼梯不该重演过场")
	await _place(player, room, Vector3(6.0, 0.0, -12.6))
	_check(not gate.is_arena_sealed(), "[首领之死] 首领已死，再次越过激活线不该重新封场")
	tower.free()
	await get_tree().process_frame


# ── 对照实例：把门控整个摘掉，三处口子本来应该通 ───────────────────────────
func _phase_control() -> void:
	var pair := await _spawn("control: 无门控")
	var tower: TowerDescent3D = pair[0]
	var room: DungeonRoom3D = pair[1]
	var player: Player3D = tower.player
	var gate := room.find_child("ArenaGate", true, false)
	_check(gate != null, "对照实例里应能定位到 ArenaGate（用于摘除）")
	if gate != null:
		gate.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame
	for key in ESCAPES.keys():
		var reached := await _try_escape(player, room, ESCAPES[key])
		_check(reached, "无门控时 %s 本来应该走得出去（说明③是被护栏挡的，不是别的几何）" % key)
	tower.free()
	await get_tree().process_frame


func _finish() -> void:
	for failure in _failures:
		print("FAIL ", failure)
	print("BOSS_ROOM02_ARENA_GATE_", "OK" if _failures.is_empty() else "FAILED",
		" checks=", _checks, " failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


## 美术帧 → 世界。
##
## 🔴 本探针的所有常量（楼梯 z∈[−10,40]、平台 z∈[−35,−10]、三个出口、两处触发线）
## 都是照 Boss房02 的**烘焙坐标**写的。远征01 的绑定壳会按 `template_rotation_deg`
## 把整房转过 180°（同一关不同种子实测都会出现），此时房间帧与美术帧相差 180° ——
## 用房间帧摆点等于把玩家扔到房间另一头，探针会报一堆「本该触发却没触发」。
func _to_world(room: DungeonRoom3D, local: Vector3) -> Vector3:
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art == null:
		art = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	if art == null:
		return room.to_global(local)
	return art.global_transform * local


func _place(player: Player3D, room: DungeonRoom3D, local: Vector3) -> void:
	var y := _surface_y(local.x, local.z)
	player.global_position = _to_world(room, Vector3(local.x, y, local.z) + Vector3.UP * START_LIFT_M)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


## 用真身控制器冲向目标；到达返回 true，被拦住/超时返回 false。
func _try_escape(player: Player3D, room: DungeonRoom3D, target_local: Vector3) -> bool:
	var start := (
		Vector3(0.0, 0.0, -22.5) if absf(target_local.x) > 5.0 else Vector3(0.0, 0.0, -16.0)
	)
	await _place(player, room, start)
	var target := _to_world(room, Vector3(
		target_local.x, _surface_y(target_local.x, target_local.z), target_local.z
	) + Vector3.UP * START_LIFT_M)
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
	var end_local := room.to_local(last)
	print("  ESCAPE %-14s → local=(%7.2f, %7.2f, %7.2f) reached=%s" % [
		str(target_local), end_local.x, end_local.y, end_local.z, str(reached)])
	return reached
