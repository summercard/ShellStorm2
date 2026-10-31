extends Node3D

## 远征03 逐只 AI 流畅度体检（2026-10-31）。
##
## ## 为什么要另起一个探针
## 现有 `_egt_cadence_probe` 走真实关卡 → 依赖刷怪链（实测 `test_mode` 下 hub_02 刷出 0 只，
## 且 `_egt_enemy_motion_probe` 在"12 个房全部无怪"的情况下仍然报 OK —— 那是假绿）。
## 本探针**不依赖关卡生成**：自己搭一块带墙与柱的场地，逐只 new 一个 Enemy3D，
## 跑真实 `_physics_process` 状态机，于是每一只都能拿到自己的数。
##
## ## 量什么（对应业主体感「AI 行动逻辑和状态机不流畅、攻击节奏不好」）
## | 指标 | 定义 | 「不流畅」长什么样 |
## |---|---|---|
## | 周期 | 相邻两次进入 `attack` 的间隔 | 与配置表对不上（实际 = telegraph + max(cd, recovery)） |
## | 前摇占比 | telegraph 时长 / 周期 | 高 ⇒ 每轮有一大段时间站着不动 |
## | 后摇占比 | recovery 时长 / 周期 | 同上 |
## | 静止占比 | 水平速度 < 12% 移速 的帧占比 | 高 ⇒ 木桩感 |
## | 路径效率 | 首尾直线距离 / 实际路程 | 低 ⇒ 打转、来回横跳 |
## | 方向反转 | 每 0.25 s 采样，航向夹角 > 120° 记一次 | 高 ⇒ 抽搐 |
## | 顶墙卡住 | 有明确朝向玩家的位移意图、但 0.5 s 内位移 < 0.06 m | > 0 ⇒ 贴着墙原地磨 |
##
## ## 已知的非普遍项
## 一次性怪（rush / explode / grab / flee）6 秒内只会出手 0~1 次，**周期列为 `—`**，
## 不能用「没周期」判它有问题。伪装型（mimic）出生即现形，否则测得的是「静止」。

## **必须用正式 prefab，不能用裸 `Enemy3D.new()`。**
##
## 裸 new 出来的怪缺 `CollisionShape3D` 与 `Avatar` 两个子节点（源码 1124 行注释已写明）：
## `@onready` 解析为空 ⇒ `apply_profile()` 里 `if collision_shape != null` 整段跳过
## ⇒ 怪没有碰撞体 ⇒ 直接穿过地板、自由落体到 `FALL_DEATH_DROP_M` 以下
## ⇒ `_die_from_fall_out()` 把它搬回出生点判死。实测每只只跑 26~27 帧（≈0.43s）就 dead，
## 而打印出来的血量和位置全都"正常"（满血、就在出生点）—— 最难查的一种假数据。
const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
## 假玩家：只提供 AI 会读的 `current_hp` 与 `take_damage`，别把真玩家整套逻辑带进来。
const TARGET_SCRIPT: GDScript = preload("res://tools/_probe_target_body.gd")
const OBSERVE_SEC := 6.0
## 观测时长按 **墙钟** 计。
##
## ⚠ 这里踩过一个把全部周期读数放大 2 倍的坑：原来是每 `await physics_frame`
## 就给 `t` 加 `1/30`，而 `physics_frame` 在 60 Hz 下每帧触发一次 ⇒ `t` 走得比真实时间
## 快一倍，"周期 2.77 s"其实是 1.39 s。**周期类指标只能用真实时间戳算**，
## 帧数只用来算占比（静帧率、状态分布）。
## 场地尺寸（米）。房间比远征03 最小房（25×25）略小，让怪真的会碰墙。
const ARENA_HALF := 9.0

var _rows: Array[Dictionary] = []
var _target: CharacterBody3D


func _ready() -> void:
	_build_arena()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 场地哨兵：从空中往下打一条射线，必须命中 Floor。
	# 没有这条，场地建歪了会让 33 只怪全部"掉出世界"，而探针只是安静地少跑几帧。
	var probe_hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(0, 8, 0), Vector3(0, -8, 0), 1, [])
	)
	print("场地检查：向下射线命中=%s（应为 Floor）"
		% (str((probe_hit.get("collider") as Node).name) if probe_hit else "无"))
	var kinds: Array = Enemy3D.PROFILES.keys().filter(
		func(key): return str(key).begins_with("egt_")
	)
	kinds.sort()
	print("=== 远征03 逐只 AI 流畅度（%d 只 × %.0fs）===" % [kinds.size(), OBSERVE_SEC])
	for kind in kinds:
		await _probe(str(kind))
	_report()
	_check_room_rotation()
	get_tree().quit(0)


## 场地：地板 + 四面墙 + 中央柱。柱子的作用是让「避障绕行」这件事真的发生 ——
## 空地测出来的路径效率恒为 1.0，看不出任何寻路问题。
func _build_arena() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(ARENA_HALF * 2, 1.0, ARENA_HALF * 2), "Floor")
	var t := 0.4
	_add_box(Vector3(ARENA_HALF, 1.5, 0), Vector3(t, 3.0, ARENA_HALF * 2), "WallE")
	_add_box(Vector3(-ARENA_HALF, 1.5, 0), Vector3(t, 3.0, ARENA_HALF * 2), "WallW")
	_add_box(Vector3(0, 1.5, ARENA_HALF), Vector3(ARENA_HALF * 2, 3.0, t), "WallS")
	_add_box(Vector3(0, 1.5, -ARENA_HALF), Vector3(ARENA_HALF * 2, 3.0, t), "WallN")
	# 柱子**不能放在怪与目标的正中间**：第一次就把 2×2×3 的柱子摆在 (0,0)，
	# 结果 `_has_line_of_sight` 全被它挡住 ⇒ 33 只全部「静止 100% / 出手 0」，
	# 而探针照样跑完 —— 典型的"测了个空房间还是绿的"。现在摆到侧后方：
	# 直线视线通、绕圈与走位时才会撞上它，避障质量仍测得到。
	_add_box(Vector3(4.5, 1.5, 5.5), Vector3(2.0, 3.0, 2.0), "Pillar")
	# 目标：真 CharacterBody3D（`_predict_target_position` 会读速度），
	# 加进 player_3d 组（`_get_player_in_proximity` 靠组查找）。
	_target = TARGET_SCRIPT.new() as CharacterBody3D
	_target.name = "ProbeTarget"
	_target.collision_layer = 0
	_target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	_target.add_child(shape)
	add_child(_target)
	_target.add_to_group("player_3d")


func _add_box(center: Vector3, size: Vector3, node_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _probe(kind: String) -> void:
	# 每只怪一个独立 room_id：房间节拍器按 room 记账，共用一个会把上一只的窗口带过来。
	var room := "probe_" + kind
	# 目标放在 +X 侧、怪在 -X 侧且**朝向 +X**（默认朝 -Z，不转身就看不见目标 ⇒
	# `MonsterVisionSystem3D` 的视野锥会让 33 只全部"看不到玩家"）。
	# 距离必须落在**黑暗视野**（8.5 m）以内：headless 场地没有光源，
	# `MonsterVisionSystem3D` 判 DARKNESS ⇒ 视距只有 8.5 m。第一次摆 12.5 m，
	# 33 只全是 `awareness=unaware`，测出来的是"看不见"而不是"不流畅"。
	_target.global_position = Vector3(1.0, 0.1, 0.0)
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		print("    ✖ %s 实例化失败（场景根不是 Enemy3D）" % kind)
		return
	enemy.enemy_kind = kind
	enemy.room_id = room
	add_child(enemy)
	# **必须贴地出生**：`_physics_process` 会把首帧位置记成 `_home_position`，
	# 再从 1.2m 落到地面时差 1.15m > `FALL_DEATH_DROP_M` ⇒ `_die_from_fall_out()`
	# 直接把怪判死。第一次实测每只只跑了 27 帧（≈落地时间）就 break，全是这个原因。
	enemy.global_position = Vector3(-6.0, 0.05, 0.0)
	# 默认 basis 朝 -Z；目标在 +X ⇒ 朝 +X 就是绕 Y 转 -90°。
	enemy.rotation.y = -PI * 0.5
	await get_tree().physics_frame
	enemy.apply_profile(kind)
	enemy.configure_from_enemy_data({})
	enemy.set_runtime_active(true)
	# 伪装型不现形就永远是"静止"的 —— 那测的是伪装机制，不是 AI。
	if enemy._active_profile.has("disguise"):
		enemy.reveal_disguise_now()
	# 抓握大师的 `die_when_others_dead`：原作是「房里别的怪都死了它就自己死」。
	# 单只探针永远满足"没有别人" ⇒ 第 1 帧就 `_die()`，一个数据都测不到。
	# 这里临时摘掉这个键，等价于"房里还有同伴"，才能看到它真正的抓取节奏。
	if enemy._active_profile.has("die_when_others_dead"):
		enemy._active_profile.erase("die_when_others_dead")
	# `_target` 是 AI 的目标缓存；`MonsterAIManager` 每 110ms 重算并写回，
	# 这里先手动给一次，避免第一帧空转。
	enemy._target = _target
	# 落地稳定期：从 1.2m 落到地板约 0.5s。不先等这段，
	# 「静止占比」会把下落前的那几帧算进来，且第一帧 LOS 会被地板判负。
	for _frame in range(40):
		await get_tree().physics_frame
	if not is_instance_valid(enemy):
		print("    ✖ %s 落地稳定期后已失效（%s）" % [kind, str(enemy.ai_state) if is_instance_valid(enemy) else "freed"])
		return
	enemy._target = _target

	var samples: Array[Dictionary] = []
	var states_seen: Dictionary = {}
	var attack_times: Array[float] = []
	var telegraph_frames := 0
	var recovery_frames := 0
	var total_frames := 0
	var still_frames := 0
	var stuck_events := 0
	var heading_turns := 0
	var prev_heading := Vector3.ZERO
	var sample_accum := 0.0
	var path_len := 0.0
	var last_pos := enemy.global_position
	# 顶墙判定用：持续"想走但没走"的时长
	var stall_time := 0.0
	var saw_target_frames := 0
	var first_check_done := false
	var prev_state := ""
	var start_msec := Time.get_ticks_msec()
	var t := 0.0
	while true:
		await get_tree().physics_frame
		if t >= OBSERVE_SEC:
			break
		if not is_instance_valid(enemy) or enemy.ai_state == "dead":
			# 一次性型（冲撞 / 自爆 / 逃跑 / 抓住即走）本来就会在观测期内消失，
			# 那不是缺陷。其余骨架中途 dead 说明这一只的读数不完整，必须显式标出来。
			if str(enemy._egt_attack_style()) in ["rush", "explode", "flee"]:
				print("    · %s 第 %d 帧按设计消失（一次性型，属预期）" % [kind, total_frames])
			else:
				print("    ✖ %s 第 %d 帧死亡/失效（读数不完整）" % [kind, total_frames])
			break
		var dt := 1.0 / 60.0
		t = float(Time.get_ticks_msec() - start_msec) / 1000.0
		sample_accum += dt
		total_frames += 1
		var state := str(enemy.ai_state)
		states_seen[state] = int(states_seen.get(state, 0)) + 1
		if state == "telegraph":
			telegraph_frames += 1
		elif state == "recovery":
			recovery_frames += 1
		if state == "attack" and prev_state != "attack":
			attack_times.append(t)
		prev_state = state

		if is_instance_valid(enemy._target):
			saw_target_frames += 1
		elif t > 1.0 and not first_check_done:
			first_check_done = true
			print(
				"    ⚠ %s 在 1s 后仍无目标（awareness=%s visible=%s）：本只读数不可信"
				% [kind, str(enemy._ai_decision.get("awareness", "?")),
				   str(enemy._ai_decision.get("target_visible", "?"))]
			)

		var pos := enemy.global_position
		var planar := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
		var step := Vector3(pos.x - last_pos.x, 0.0, pos.z - last_pos.z).length()
		path_len += step
		last_pos = pos
		var speed := planar.length()
		if speed < enemy.move_speed * 0.12:
			still_frames += 1
		# 顶墙卡住：状态在移动语义里、想走（速度指令存在）、但实际几乎没动。
		var wants_move := state in ["chase", "search", "patrol", "return"]
		if wants_move and speed > enemy.move_speed * 0.30 and step < 0.002:
			stall_time += dt
			if stall_time >= 0.5:
				stuck_events += 1
				stall_time = 0.0
		else:
			stall_time = 0.0
		# 航向反转：只在真的在动时采样，静止时方向没有意义。
		if speed > enemy.move_speed * 0.25:
			var heading := planar.normalized()
			if prev_heading != Vector3.ZERO and heading.dot(prev_heading) < -0.5:
				heading_turns += 1
			prev_heading = heading
		else:
			prev_heading = Vector3.ZERO
		sample_accum += 0.0

	var periods: Array[float] = []
	for i in range(1, attack_times.size()):
		periods.append(attack_times[i] - attack_times[i - 1])
	var period_avg := 0.0
	for p in periods:
		period_avg += p
	if not periods.is_empty():
		period_avg /= float(periods.size())

	var frame_denom := maxf(1.0, float(total_frames))
	var row := {
		"kind": kind,
		"style": enemy._egt_attack_style(),
		"cd": enemy.attack_cooldown,
		"telegraph_cfg": (
			float(enemy._active_profile["telegraph"]) if enemy._active_profile.has("telegraph") else -1.0
		),
		"recovery_cfg": (
			float(enemy._active_profile["recovery"]) if enemy._active_profile.has("recovery") else -1.0
		),
		"telegraph_actual": enemy._telegraph_duration(),
		"recovery_actual": enemy._recovery_duration(),
		"attacks": attack_times.size(),
		"period_avg": period_avg,
		"period_min": periods.min() if not periods.is_empty() else 0.0,
		"period_max": periods.max() if not periods.is_empty() else 0.0,
		"telegraph_share": float(telegraph_frames) / frame_denom,
		"recovery_share": float(recovery_frames) / frame_denom,
		"still_share": float(still_frames) / frame_denom,
		"path_len": path_len,
		"straight": Vector3(
			enemy.global_position.x - (-6.0), 0.0, enemy.global_position.z - 0.0
		).length(),
		"stuck": stuck_events,
		"turns": heading_turns,
		"states": states_seen,
		## 目标可见帧数占比。低于 90% 说明这一只的读数混入了"丢目标"的静止，
		## 不能拿它判断"AI 不流畅"。
		"target_share": float(saw_target_frames) / maxf(1.0, float(total_frames)),
	}
	_rows.append(row)
	print(
		"  %-22s %-8s 出手%2d  周期%5s  前摇%4.2fs 后摇%4.2fs  静止%3.0f%%  路程%5.1fm  卡%2d  反转%2d  目标%3d/%3d  状态%s"
		% [
			kind, row["style"], int(row["attacks"]),
			("—" if periods.is_empty() else "%.2fs" % period_avg),
			float(row["telegraph_actual"]), float(row["recovery_actual"]),
			float(row["still_share"]) * 100.0, path_len, stuck_events, heading_turns,
			saw_target_frames, total_frames,
			str(_top_states(states_seen)),
		]
	)
	enemy.queue_free()
	await get_tree().process_frame


## 出现最多的两个状态，用来一眼看出「它到底在干什么」。
func _top_states(states: Dictionary) -> String:
	var items: Array = states.keys()
	items.sort_custom(func(a, b): return int(states[a]) > int(states[b]))
	var out: Array[String] = []
	for i in range(mini(2, items.size())):
		out.append("%s:%d" % [str(items[i]), int(states[items[i]])])
	return "/".join(out)


## 房间节拍器的**轮转**：同一只怪不得连续吃两个窗口。
##
## 这条断言针对的是「先到先得 + 每帧重试」退化成「节点顺序先到先得」那个缺陷：
## 修之前，树里靠前的怪会把窗口全吃掉，靠后的整场开不了一次火。
func _check_room_rotation() -> void:
	print("\n=== 房间节拍器轮转 ===")
	if MonsterAIManager == null:
		print("  跳过：没有 MonsterAIManager 单例")
		return
	MonsterAIManager.set_room_attack_gap_sec(0.001)
	var proxies: Array = []
	for index in range(3):
		var proxy := TARGET_SCRIPT.new() as Node
		proxy.set("room_id", "rotation_probe")
		proxy.set("current_hp", 100)
		add_child(proxy)
		MonsterAIManager.register_enemy(proxy)
		proxies.append(proxy)
	var sequence: Array = []
	for _round in range(9):
		for proxy in proxies:
			# 手动把窗口置为"已开放"，于是这一轮测的是轮转规则本身，不是等待时间。
			MonsterAIManager._room_next_slot_msec["rotation_probe"] = 0
			if MonsterAIManager.request_attack_token(proxy, _target, "ranged"):
				sequence.append((proxy as Node).get_instance_id())
				MonsterAIManager.release_attack_token(proxy)
	var repeats := 0
	for index in range(1, sequence.size()):
		if sequence[index] == sequence[index - 1]:
			repeats += 1
	var distinct := {}
	for id in sequence:
		distinct[id] = true
	print("  拿到窗口 %d 次，涉及 %d 只（期望 3），相邻重复 %d 次（期望 0）"
		% [sequence.size(), distinct.size(), repeats])
	if repeats > 0:
		print("  ✖ 同一只怪连续拿了窗口：轮转没生效")
	elif distinct.size() < 3:
		print("  ✖ 有怪整场拿不到窗口（只 %d 只有份）" % distinct.size())
	else:
		print("  ✔ 三只怪轮流拿到窗口")
	for proxy in proxies:
		MonsterAIManager.unregister_enemy(proxy)
		(proxy as Node).queue_free()
	MonsterAIManager.set_room_attack_gap_sec(0.0)


func _report() -> void:
	print("\n=== 汇总 ===")
	var dir_set := {}
	for row in _rows:
		dir_set[str(row["style"])] = true
	var no_cfg := 0
	var still_sum := 0.0
	var stuck_sum := 0
	for row in _rows:
		if float(row["telegraph_cfg"]) < 0.0:
			no_cfg += 1
		still_sum += float(row["still_share"])
		stuck_sum += int(row["stuck"])
	var untestable := Enemy3D.PROFILES.keys().filter(
		func(k): return str(k).begins_with("egt_")
	).size() - _rows.size()
	print(
		"  怪种数             %d（骨架 %d 类）%s"
		% [_rows.size(), dir_set.size(),
		   ("；另有 %d 只在单只环境下按设计自毁、测不到" % untestable) if untestable > 0 else ""]
	)
	# 表里没有逐只声明 `telegraph`/`recovery`，但**不等于**走通用缺省 ——
	# 复刻怪由 `_egt_telegraph_seconds()` / `_egt_recovery_seconds()` 按骨架派生。
	print("  表内未逐只声明前摇 %d 只（走 `_egt_telegraph_seconds()` 的骨架派生档）" % no_cfg)
	print("  平均静止占比       %.1f%%" % (still_sum / maxf(1.0, float(_rows.size())) * 100.0))
	print("  顶墙卡住合计       %d 次" % stuck_sum)
	# 周期 vs 配置：真实周期 = telegraph + max(cd, recovery)。
	# 这一列是「表里写的数被固定死时间稀释了多少」的直接证据。
	print("\n=== 周期与配置对照（实际 = 前摇 + max(冷却, 后摇)）===")
	for row in _rows:
		if float(row["period_avg"]) <= 0.0:
			continue
		var cd := float(row["cd"])
		if cd >= 90.0:
			continue
		var predicted := float(row["telegraph_actual"]) + maxf(cd, float(row["recovery_actual"]))
		print(
			"  %-22s 配置冷却 %4.2fs → 实际 %4.2fs（预期 %4.2fs，膨胀 %+.0f%%）"
			% [row["kind"], cd, float(row["period_avg"]), predicted,
			   (predicted / cd - 1.0) * 100.0]
		)
	print("EGT_AI_FLOW_DONE")
