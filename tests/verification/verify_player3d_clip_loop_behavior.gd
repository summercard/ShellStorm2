extends Node3D
## 剪辑**循环行为**端到端验收 · 只读工程。
##
## 主人 2026-11-07 报：「跑步动作会留在最后一帧，不是重复的」。
##
## 根因：GLB 导入无 post-import 脚本 ⇒ 128 段 Animation 全 `LOOP_NONE`，
## `AnimationPlayer.play()` 播完**定格末帧**。修复见 `ClipMotionLibrary3D._apply_loop_flags()`
## （从老通道 JSON 库把 `loop` 标记抄回 Animation）。
##
## ## 为什么不能只验 `loop_mode` 标记
## 标记对了不代表**播放路径**真的循环 —— `seek()` 钉帧、`speed_scale = 0`、
## 被打断的淡化都可能让画面停在末帧，而 `loop_mode` 读出来仍是 LOOP_LINEAR。
## 唯一可信的判据是**跨真帧观察骨骼是否回到起点附近**：
##
##   循环剪辑：播过一个完整周期后，骨骼位置必须回到周期起点附近（差 < 阈值）
##   定格剪辑：位置会停在末帧，与起点差一大截
##
## ## 判据设计
## 用 `Hips`（身体根骨）作观测点，因为它每个剪辑都在动。
## 判据两段：
##   ① **回归性**：跑过 clip_length + ε 后，位置与起点距离 < 阈值（证明循环了）
##   ② **活性**：整个过程中位置摆幅 > 阈值（证明不是静止）
## 两条同时满足才算「真的在循环」——只看 ① 会把「完全静止」误判成循环。
##
## 用法：godot --headless --path . res://tests/verification/verify_player3d_clip_loop_behavior.tscn

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
## 抽样剪辑：覆盖三种关键场景（基础运动 / 持枪运动 / 待机）。
## 「跑步留在最后一帧」报告对应的就是 *_moving_forward 这一类。
##
## ⚠️ `speed` 必须与剪辑语义匹配：`ClipMotionLibrary3D` 按
## `0.05 < planar_speed < 3.2` 选 `walking`，否则选 `moving`。
## 首版给 walking 探针也填了 4.2 ⇒ 实际命中 `sidearm_moving_forward`，
## 断言名与实测剪辑对不上（读 `actual_clip` 才发现）。
const LOOPING_PROBES := [
	{"clip": "idle", "state": "idle", "weapon": "bp_pistol", "direction": Vector3.ZERO, "speed": 0.0},
	{"clip": "sidearm_idle", "state": "idle", "weapon": "bp_pistol", "direction": Vector3.ZERO, "speed": 0.0},
	{"clip": "sidearm_moving_forward", "state": "moving", "weapon": "bp_pistol", "direction": Vector3(0, 0, -1), "speed": 4.2},
	{"clip": "longgun_moving_forward", "state": "moving", "weapon": "bp_rifle", "direction": Vector3(0, 0, -1), "speed": 4.2},
	{"clip": "machinegun_moving_forward", "state": "moving", "weapon": "bp_machinegun", "direction": Vector3(0, 0, -1), "speed": 4.2},
	{"clip": "sidearm_walking_forward", "state": "moving", "weapon": "bp_pistol", "direction": Vector3(0, 0, -1), "speed": 2.0},
	{"clip": "sidearm_walking_strafe_left", "state": "moving", "weapon": "bp_pistol", "direction": Vector3(-1, 0, 0), "speed": 2.0},
]
## 一次性剪辑做**反向对照**：它们播完就该停在末帧，不能循环。
## 只验「不在起点附近」——若这里也判成循环，说明 loop 标记被误设成全员循环。
const ONESHOT_PROBES := [
	{"clip": "hurt", "weapon": "bp_pistol"},
	{"clip": "dead", "weapon": "bp_pistol"},
]
## 一个周期后位置与起点的允许偏差（米）。
## 定为 0.045 而不是更小：采样是**离散帧**，一周期结束点几乎不可能正好落在
## 起始相位上；运动越快的剪辑错位越大（实测 `sidearm_walking_forward` 0.0269）。
## 而「定格在末帧」的偏差是**整段动作幅度**量级（跑步 0.3 m 以上），
## 两者差一个数量级，这个阈值足以区分。
const LOOP_RETURN_TOLERANCE_M := 0.045
## 过程中必须有这么多摆幅，否则算静止（不能只看"回到起点"）。
## 0.002 是照着**待机类**剪辑定的：`sidearm_idle` 实测 0.0038 m，
## 本就是呼吸级微动；原定 0.010 会把它误判成「没动」。
## 而「骨架没被驱动」的摆幅是**严格 0**（首版实测 0.0000），
## 所以 0.002 依然能干净地把冻结与微动分开。
const ACTIVE_AMPLITUDE_M := 0.002
## 模拟步长与额外帧数（保证跑过一整个 clip 长度还有富余）。
const STEP_S := 1.0 / 60.0
const EXTRA_FRAMES := 4

var _player: Node3D
var _failures: Array[String] = []
var _checks := 0


func _say(line: String) -> void:
	print("CLIP_LOOP| " + line)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		_say("OK   " + label)
	else:
		_say("FAIL " + label)
		_failures.append(label)


func _ready() -> void:
	## 实体地板：没它角色永远 falling（首版踩过）。
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80.0, 0.4, 80.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.2, 0.0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	await get_tree().process_frame
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_player.set("combat_enabled", false)
	_player.get_node_or_null("Camera3D").set("current", false)
	var avatar := _player.get_node_or_null("Avatar3D") as Node3D
	var motion: Variant = avatar.get("_authored_motion")
	if motion == null:
		_say("FAIL 找不到运动库")
		get_tree().quit(1)
		return
	_say("装配 motion_driver=%s loop_source=%s applied=%s/%s" % [
		str(avatar.get_meta("motion_driver", "")), str(motion.get("loop_source")),
		str(motion.get("loop_flags_applied")), str(motion.get("loop_flags_total"))])

	for probe in LOOPING_PROBES:
		await _check_loops(avatar, probe)
	for probe in ONESHOT_PROBES:
		await _check_oneshot(avatar, probe)

	_say("==== 结论：%s（检查 %d 项，失败 %d）====" % [
		"通过" if _failures.is_empty() else "未通过", _checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


## 把角色置于目标剪辑对应的玩法状态，连续推进，观察骨骼是否周期性回归。
##
## ⚠️ **必须 await 真帧，不能紧循环手动调 `avatar._process()`**。
## `AnimationPlayer` 是引擎节点，靠自己每帧的 `_process` 推进 `current_animation_time`；
## 手动调 avatar 的 `_process` 只会重跑运动库的采样逻辑（它读的是
## AnimationPlayer **当前**姿态），而 AnimationPlayer 的时间**一步都没走** ⇒
## 骨骼永远停在同一姿态，摆幅恒为 0.0000（首版实测，差点把 bug 误判成"没循环"）。
func _check_loops(avatar: Node3D, probe: Dictionary) -> void:
	var clip := str(probe["clip"])
	_setup(probe)
	var player_node := avatar.get_node_or_null("VisualRoot/BunnyRig/Model")
	var anim := _find_first(player_node, "AnimationPlayer") as AnimationPlayer
	if anim == null or not anim.has_animation(clip):
		_check(false, "%s：找不到剪辑" % clip)
		return
	var clip_length := anim.get_animation(clip).length
	if clip_length <= 0.001:
		_check(false, "%s：剪辑长度为 0" % clip)
		return
	## 先跑一段让状态机与淡化稳定（真帧），再取起点。
	await _settle(probe, 40)
	var start := _bone_position(avatar, "mixamorig_Hips")
	if _is_missing(start):
		_check(false, "%s：取不到 Hips" % clip)
		return
	## 跑过一整个剪辑长度 + 富余，**逐真帧**采摆幅。
	## 用墙钟计时而不是「帧数 × 标称 dt」：真帧的 delta 受帧率影响，不等分。
	var want := clip_length + 0.10
	var elapsed := 0.0
	var lowest := start
	var highest := start
	while elapsed < want:
		var delta := await _next_frame(probe)
		elapsed += delta
		var now := _bone_position(avatar, "mixamorig_Hips")
		if _is_missing(now):
			continue
		lowest = lowest.min(now)
		highest = highest.max(now)
	var end := _bone_position(avatar, "mixamorig_Hips")
	if _is_missing(end):
		_check(false, "%s：末帧取不到 Hips" % clip)
		return
	var amplitude := highest.distance_to(lowest)
	var return_error := end.distance_to(start)
	var actual_clip := str(avatar.get("_authored_motion").get("active_clip"))
	_check(
		amplitude > ACTIVE_AMPLITUDE_M,
		"%s：过程中有动作（摆幅 %.4f m > %.3f）" % [clip, amplitude, ACTIVE_AMPLITUDE_M]
	)
	_check(
		return_error < LOOP_RETURN_TOLERANCE_M,
		"%s：一个周期后回到起点（偏差 %.4f m < %.3f）actual_clip=%s" % [
			clip, return_error, LOOP_RETURN_TOLERANCE_M, actual_clip]
	)


## 一次性剪辑的反向对照：播完应停在末帧（**不**周期性回归）。
func _check_oneshot(avatar: Node3D, probe: Dictionary) -> void:
	var clip := str(probe["clip"])
	var setup := probe.duplicate()
	setup["state"] = "idle"
	setup["direction"] = Vector3.ZERO
	_setup(setup)
	var model := avatar.get_node_or_null("VisualRoot/BunnyRig/Model")
	var anim := _find_first(model, "AnimationPlayer") as AnimationPlayer
	if anim == null or not anim.has_animation(clip):
		_check(false, "%s：找不到剪辑" % clip)
		return
	var clip_length := anim.get_animation(clip).length
	## 触发一次性动作。
	if clip == "hurt":
		_player.set("is_invincible", false)
		_player.set("_invincible_remaining", 0.0)
		_player.call("take_damage", 12)
	elif clip == "dead":
		_player.set("is_invincible", false)
		_player.set("_invincible_remaining", 0.0)
		_player.call("take_damage", int(_player.get("max_hp")) + 1)
	else:
		_check(false, "%s：未实现触发方式" % clip)
		return
	var first := _bone_position(avatar, "mixamorig_Hips")
	if _is_missing(first):
		_check(false, "%s：取不到 Hips" % clip)
		return
	## 跑到剪辑结束（真帧 + 墙钟），取末帧姿态。
	var elapsed := 0.0
	var want := clip_length + 0.10
	while elapsed < want:
		elapsed += await _next_frame(setup)
	var settled := _bone_position(avatar, "mixamorig_Hips")
	if _is_missing(settled):
		_check(false, "%s：末帧取不到 Hips" % clip)
		return
	## 再跑一个完整周期：若它真的**不**循环，位置应保持不动（定格）。
	var before_extra := settled
	elapsed = 0.0
	while elapsed < clip_length:
		elapsed += await _next_frame(setup)
	var after_extra := _bone_position(avatar, "mixamorig_Hips")
	if _is_missing(after_extra):
		_check(false, "%s：追加周期后取不到 Hips" % clip)
		return
	var drift := before_extra.distance_to(after_extra)
	_check(
		drift < LOOP_RETURN_TOLERANCE_M,
		"%s：一次性动作末帧保持定格（追加一个周期后漂移 %.4f m）" % [clip, drift]
	)
	## 复位，免得影响后续用例。
	_player.set("is_invincible", true)
	_player.set("_invincible_remaining", 999.0)
	_player.set("current_hp", int(_player.get("max_hp")))


func _setup(probe: Dictionary) -> void:
	var weapon := str(probe["weapon"])
	if not weapon.is_empty():
		_player.call("equip_weapon", weapon, "mod_bullet_standard")
	var state := str(probe.get("state", "idle"))
	_player.set("_presentation_state", state)
	_position_player(probe)


func _position_player(probe: Dictionary) -> void:
	var direction: Vector3 = probe.get("direction", Vector3.ZERO)
	var state := str(probe.get("state", "idle"))
	if state == "moving" and direction != Vector3.ZERO:
		var speed := float(probe.get("speed", 4.2))
		_player.set("velocity", direction.normalized() * speed)
	else:
		_player.set("velocity", Vector3.ZERO)
	## 钉住位置与朝向：本验收只看骨骼周期，不要角色真的跑出画面。
	_player.global_position = Vector3.ZERO
	_player.set("aim_yaw", 0.0)
	var avatar := _player.get_node_or_null("Avatar3D") as Node3D
	if avatar != null:
		var visual_root := avatar.get_node_or_null("VisualRoot") as Node3D
		if visual_root != null:
			visual_root.rotation.y = 0.0


## 取骨骼当前位置。返回 Vector3；**取不到时返回 `Vector3.INF`** 作哨兵
## （不能用 `null`/Variant：GDScript 会把后续所有运算的类型推断拖成 Variant，
## 而本工程的告警即错误设置会直接拒绝编译 —— 首版踩过）。
const NO_BONE := Vector3(INF, INF, INF)


## `Vector3` 没有 `is_infinite()`（那个方法在 float 上）；用 `is_finite()` 取反。
func _is_missing(point: Vector3) -> bool:
	return not point.is_finite()


## 推进一个**真**渲染帧：`AnimationPlayer`、淡化、物理都在这时前进。
## 返回该帧的 delta（秒），供墙钟累计。
func _next_frame(probe: Dictionary) -> float:
	_position_player(probe)
	var delta := get_process_delta_time()
	await get_tree().process_frame
	return maxf(0.0001, delta)


## 先跑若干真帧让状态机、武器装配、动画淡化稳定下来。
func _settle(probe: Dictionary, frames: int) -> void:
	for _index in range(frames):
		await _next_frame(probe)


func _bone_position(avatar: Node3D, bone_name: String) -> Vector3:
	var skeleton := _find_first(avatar, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		return NO_BONE
	for index in range(skeleton.get_bone_count()):
		if skeleton.get_bone_name(index) == bone_name:
			## ⚠️ 必须用 `get_bone_global_pose()` 而不是 `get_bone_pose_position()`：
			## 后者读的是骨骼的**静止姿态**（rest pose），AnimationPlayer 播什么都**
			## 不会变** —— 首版用它量，摆幅恒为 0.0000，差点把「没循环」误判成
			## 「读不到动作」。前者才是当前帧的实际姿态。
			return skeleton.get_bone_global_pose(index).origin
	return NO_BONE


func _find_first(root_node: Node, cls: String) -> Node:
	if root_node == null:
		return null
	if root_node.is_class(cls):
		return root_node
	for child in root_node.get_children():
		var found := _find_first(child, cls)
		if found != null:
			return found
	return null
