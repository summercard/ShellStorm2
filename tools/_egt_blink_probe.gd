extends Node
## 远征03 瞬移怪（空尖弹 / 枪法师）机制实测（2026-10-30）。
##
## 业主报单：「瞬移后就无法被子弹打中，而且它的子弹也无法击中玩家。」
## **双向都失能**这一条本身就是病灶线索：单方向打不中可以是命中盒问题，
## 双向同时失效通常意味着"这只怪已经不在玩家所在的那个空间里了"。
##
## 本探针验两件事：
##   ① **瞬移落点是否还在房间里** —— `_is_point_inside_room_hint()` 用的是一个
##      「以出生点为圆心、半径 = 当前到出生点距离 + 6」的**圆形近似**，而房间是**矩形**。
##      这个近似有两个致命性质：判不出矩形角落（半径够大时房外也算"内"）、
##      且半径随当前位置**自增**（越走越远是自促进的，一路能飘到房外）。
##   ② 瞬移后玩家子弹能否命中它（物理射线，走真实碰撞层）。
##
## 用法：godot --headless --path . --scene res://tools/_egt_blink_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED_VALUE := 77003244
## 敌人场景与 `Dungeon3D.ENEMY_SCENE` **必须是同一份**：构造补测要跟真实刷怪
## 用同一个预制体，否则测的是"另一个东西"。这里重写一遍而不是引用
## `Dungeon3D.ENEMY_SCENE` —— 那个常量叫 `const` 但不是 `class_name` 可见的静态公开量。
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
## 单只怪瞬移多少次。空尖弹原间隔 2.8s，跑真实时间太慢 —— 直接调函数，
## 这测的是**落点算法**而不是计时器。
const BLINK_SAMPLES := 600

var _failures: Array[String] = []


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _ready() -> void:
	print("=== EGT_BLINK_PROBE 瞬移落点与命中 ===")
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("EGT_BLINK_PROBE_FAIL 场景不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	# 找**所有**刷出了「选点类」怪（blink / wander）的战斗房，**逐房测完再进下一房**。
	#
	# ⚠ 三个坑叠在一起，都是第一版踩过的：
	#   ① 不能在第一个命中房间就 break —— 空尖弹在 n02、枪精灵（wander）在 n08，
	#      位于不同房间；break 掉就等于 gun_fairy 的游荡从未被测到，而它恰好是
	#      "以出生点为圆心画圆、出生点在墙角"那个 bug 的唯一受害者。
	#   ② 不能先收集引用、最后统一测 —— 玩家离开房间后那里的敌人会被回收，
	#      拿旧引用去 cast 会报 `Trying to cast a freed object` 然后整只探针挂掉。
	#   ③ 必须按**时间**等出怪：flow 关卡把刷怪推到落门之后
	#      （`FLOW_ROOM_SEAL_DELAY_S` + `FLOW_ROOM_SPAWN_PAUSE_S`），按帧数等读到的是中间态。
	var tested := 0
	for room in tower._rooms:
		var candidate := room as DungeonRoom3D
		if candidate == null:
			continue
		if str(candidate.room_type) not in Dungeon3D.HOSTILE_ROOM_TYPES:
			continue
		if str(candidate.room_type) == "BOSS":
			continue
		if (candidate.spawn_placements as Array).is_empty():
			continue
		tower.player.global_position = candidate.global_position + Vector3(0.0, 0.5, 0.0)
		tower.force_enter_room_for_test(candidate.room_id)
		await get_tree().create_timer(
			TowerDescent3D.FLOW_ROOM_SEAL_DELAY_S
			+ TowerDescent3D.FLOW_ROOM_SPAWN_PAUSE_S + 0.6
		).timeout
		for _frame in 6:
			await get_tree().process_frame

		var picked: Array[Enemy3D] = []
		for value in tower._enemy_nodes_by_room.get(candidate.room_id, []):
			var enemy := value as Enemy3D
			if enemy == null or not is_instance_valid(enemy) or enemy.ai_state == "dead":
				continue
			var prof: Dictionary = enemy._active_profile
			if prof.has("blink") or prof.has("wander"):
				picked.append(enemy)
		for enemy in picked:
			if not is_instance_valid(enemy):
				continue
			print("\n[房间 %s] 选点怪 %s" % [candidate.room_id, enemy.enemy_kind])
			await _probe_enemy(enemy, candidate)
			tested += 1

	_check(tested > 0, "翻遍所有战斗房都没有刷出带 blink/wander 的怪")
	if tested == 0:
		_finish()
		return
	print("\n共测 %d 只选点类怪（真实刷出的）" % tested)

	# —— 构造式补测：保证**每一个声明了选点机制的 kind 都被覆盖** ——
	#
	# 真实刷怪受种子与 flow 抽签影响：`egt_gun_fairy`（wander）在 `box_egt_confirmed_cell`，
	# 只有抽到含 n08 的骨架才会出现。只测"碰巧刷出来的那几只"等于给覆盖面开了个后门 ——
	# 而这次的 bug 恰恰就藏在一只没被刷出来的怪身上（gun_fairy 的游荡）。
	await _probe_synthetic(tower, tested)
	_finish()


## 对声明了 blink/wander 但没在真实场景里测到的 kind，构造一只来测。
func _probe_synthetic(tower: TowerDescent3D, already: int) -> void:
	var injector := preload("res://src/map/MonsterInjector.gd").new()
	# 用一间确定的战斗房（25×25 那类），几何从房表里挑。
	var room: DungeonRoom3D = null
	for value in tower._rooms:
		var candidate := value as DungeonRoom3D
		if candidate == null:
			continue
		if str(candidate.room_type) in Dungeon3D.HOSTILE_ROOM_TYPES:
			room = candidate
			break
	if room == null:
		return

	var tested_kinds := {}
	for kind in injector.BASE_ENEMY_TYPES.keys():
		var profile: Dictionary = Enemy3D.profile_for(str(kind))
		if profile.is_empty():
			continue
		if not (profile.has("blink") or profile.has("wander")):
			continue
		if tested_kinds.has(str(kind)):
			continue
		var data := injector.generate_box_enemy(str(kind), 1, 1)
		if data.is_empty():
			continue
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		if enemy == null:
			continue
		enemy.room_id = room.room_id
		# 摆到**墙角**再测 —— 这正是 wander 出界的触发条件（圆周从角落里画出去）。
		var half := room.get_dimensions() * 0.5
		enemy.global_position = room.global_transform * Vector3(-half.x + 2.0, 0.0, -half.y + 2.0)
		tower.add_child(enemy)
		enemy.configure_from_enemy_data(data)
		enemy.set_room_bounds(room.global_transform, half)
		enemy._home_position = enemy.global_position
		enemy._home_initialized = true
		await get_tree().physics_frame
		print("\n[构造补测·墙角] %s" % str(kind))
		await _probe_enemy(enemy, room)
		enemy.queue_free()
		await get_tree().process_frame
		already += 1
	print("\n合计覆盖 %d 只（含构造补测）" % already)


func _probe_enemy(enemy: Enemy3D, room: DungeonRoom3D) -> void:
	var profile: Dictionary = enemy._active_profile
	if profile.has("blink"):
		await _probe_blink(enemy, room, profile)
		_probe_blink_cadence(enemy, profile)
	if profile.has("wander"):
		await _probe_wander(enemy, room, profile)


## 瞬移**频率**与**冷却**（2026-10-30 第二轮，业主报单「不然会一直闪」）。
##
## 落点正确只解决"闪到墙外"，解决不了"闪得太勤"。这一条测的是**节拍**：
## 按真实的 `_tick_egt_blink()` 推进 30 秒虚拟时间，数它到底闪了几次、每次间隔多少。
##
## 两条判据：
##   ① 任何两次瞬移之间 ≥ `blink.cooldown` —— 这是"不会连续闪"的硬保证；
##   ② 周期性怪的次数 ≈ 30 / interval（±1）—— 防止 interval 写了但没被消费。
##
## 为什么不跑真实时间：30 秒 × 5 只 = 2.5 分钟，探针跑不起；
## 而这里测的是**计时逻辑**，不是物理/渲染，喂 delta 和真跑等价。
func _probe_blink_cadence(enemy: Enemy3D, profile: Dictionary) -> void:
	var cfg: Dictionary = profile.get("blink", {}) as Dictionary
	if cfg.is_empty():
		return
	var interval := float(cfg.get("interval", 0.0))
	var cooldown := float(cfg.get("cooldown", 0.0))
	var on_attack := bool(cfg.get("on_attack", false))
	var step := 1.0 / 60.0
	var steps := int(30.0 / step)
	var blinks := 0
	var since := 0.0
	var min_gap := 1e9
	var prev_cd: float = enemy._blink_cooldown
	for index in range(steps):
		# 出手型：模拟"每 2.2 秒打一轮"，看冷却会不会把连闪压住。
		if on_attack and index % int(2.2 / step) == 0:
			enemy.call("request_blink_after_attack", 0.0)
		enemy._tick_egt_blink(step)
		since += step
		# 冷却被"刚闪完"重置 ⇒ 这一帧发生了一次瞬移。
		if enemy._blink_cooldown > prev_cd + 0.001:
			blinks += 1
			# ⚠ `since` 对第一次是「从开始到首闪」，不是「两次闪之间」——
			# 把它算进最短间隔会得到 0.47s 的假红（= after_attack_delay + telegraph）。
			# 只有第 2 次起才是真间隔。
			if blinks >= 2 and since < min_gap:
				min_gap = since
			since = 0.0
		prev_cd = enemy._blink_cooldown
	# 冷却必须是正的 —— 否则下面第 ① 条判据恒真，等于没测。
	_check(
		cooldown > 0.0,
		"%s 的 blink.cooldown 没配（=%.1f）—— 没有冷却就挡不住连闪" % [enemy.enemy_kind, cooldown]
	)
	if blinks >= 2 and min_gap < cooldown - 0.02:
		_failures.append(
			"%s 30 秒内闪了 %d 次，最短间隔 %.2fs < cooldown %.2fs —— 会读成「一直在闪」"
			% [enemy.enemy_kind, blinks, min_gap, cooldown]
		)
	if interval > 0.0:
		var expected := 30.0 / interval
		_check(
			absf(float(blinks) - expected) <= 1.5,
			"%s 周期瞬移 30 秒闪了 %d 次，按 interval=%.1fs 应约 %.1f 次 —— 节拍没被消费"
			% [enemy.enemy_kind, blinks, interval, expected]
		)
	else:
		_check(
			blinks > 0,
			"%s 声明了 blink.on_attack 但 30 秒一次都没闪 —— 这个键没有被实现" % enemy.enemy_kind
		)
	print("  瞬移节拍：30 秒 %d 次，最短间隔 %.2fs（cooldown %.2fs，interval %.1fs）"
		% [blinks, min_gap if blinks >= 2 else 0.0, cooldown, interval])


## 瞬移：直接调 `_blink_to_random()` 压测落点。
##
## ⚠ 必须走**真实落点函数**而不是复算一遍公式 —— 复算只能验证"我理解的算法不出界"，
## 验证不了"代码里实现的算法"。第一版复算过一遍是绿的，实际函数在飘。
func _probe_blink(enemy: Enemy3D, room: DungeonRoom3D, profile: Dictionary) -> void:
	var radius_m := float((profile.get("blink", {}) as Dictionary).get("radius_m", 8.0))
	print("\n--- %s 瞬移（radius=%.1fm）---" % [enemy.enemy_kind, radius_m])

	var start := enemy.global_position
	var outside := 0
	var max_overshoot := 0.0
	var worst := ""
	var samples: Array[Vector3] = []
	for index in range(BLINK_SAMPLES):
		enemy._blink_to_random(radius_m)
		var overflow := _room_overflow_m(enemy.global_position, room)
		if overflow > 0.01:
			outside += 1
			if overflow > max_overshoot:
				max_overshoot = overflow
				worst = str(enemy.global_position)
		if index < 8:
			samples.append(enemy.global_position)
	var rate := float(outside) / float(BLINK_SAMPLES)
	print("  瞬移 %d 次：**出房 %d 次（%.0f%%）**，最远超界 %.2fm %s"
		% [BLINK_SAMPLES, outside, rate * 100.0, max_overshoot, worst])
	print("  前几次落点：%s" % str(samples))
	if outside > 0:
		_failures.append(
			"%s 瞬移有 %.0f%% 落在房间外（最多超界 %.2fm）—— 出房后玩家子弹被墙挡、它的子弹也被墙挡"
			% [enemy.enemy_kind, rate * 100.0, max_overshoot]
			+ "，正是「双向都打不中」"
		)

	# 命中链路：把怪摆回房内中心，从一侧打一条真实物理射线。
	# 若这里打不中，说明问题不在瞬移落点而在命中盒/碰撞层。
	#
	# ⚠ **必须先把玩家挪开**：进房时玩家就站在房心，而这里又把怪摆到房心 ——
	# 两者重叠，射线先撞到 Player3D。第一版诊断打出的就是
	# 「命中 Player3D（期望 egt_hollowpoint）」，那是探针自己制造的遮挡。
	var half := room.get_dimensions() * 0.5
	var corner := room.global_transform * Vector3(-half.x + 2.0, 0.0, -half.y + 2.0)
	enemy.get_tree().call_group("player_3d", "set", "global_position", corner)
	enemy.global_position = Vector3(
		room.global_position.x, enemy.global_position.y, room.global_position.z
	)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hits_inside := _ray_hits_enemy(enemy, room)
	_check(hits_inside, "%s 摆回房内中心后玩家射线仍打不中（命中盒/碰撞层有问题）" % enemy.enemy_kind)
	print("  %s" % ("房内中心可命中 ✓" if hits_inside else "房内中心打不中 ✗"))

	enemy.global_position = start


## 游荡：`_wander_target` 是"以出生点为圆心画随机圆"，出生点在墙角时半圆在墙外。
## 落点虽然不直接穿墙（怪是走过去的），但会让怪**一直朝墙外那个点走**，
## 表现为贴着墙原地抽搐、永远到不了 —— 机制等于失效，而且是静默的。
func _probe_wander(enemy: Enemy3D, room: DungeonRoom3D, profile: Dictionary) -> void:
	var cfg: Dictionary = profile.get("wander", {}) as Dictionary
	var radius_m := float(cfg.get("radius_m", 8.0))
	print("\n--- %s 游荡（radius=%.1fm）---" % [enemy.enemy_kind, radius_m])

	var start := enemy.global_position
	var home := enemy._home_position
	var outside := 0
	var max_overshoot := 0.0
	var worst := ""
	for index in range(BLINK_SAMPLES):
		# 每次强制重算目标：清计时器 + 清目标点，让 `_tick_egt_wander` 走"选新点"分支。
		enemy._wander_timer = 0.0
		enemy._wander_target = Vector3.ZERO
		enemy._tick_egt_wander(0.0)
		var overflow := _room_overflow_m(enemy._wander_target, room)
		if overflow > 0.01:
			outside += 1
			if overflow > max_overshoot:
				max_overshoot = overflow
				worst = str(enemy._wander_target)
	var rate := float(outside) / float(BLINK_SAMPLES)
	print("  取 %d 个游荡目标点：**出房 %d 个（%.0f%%）**，最远超界 %.2fm %s"
		% [BLINK_SAMPLES, outside, rate * 100.0, max_overshoot, worst])
	if outside > 0:
		_failures.append(
			"%s 有 %.0f%% 的游荡目标点在房间外（最多 %.2fm）—— 会一直朝墙外走、贴墙抽搐"
			% [enemy.enemy_kind, rate * 100.0, max_overshoot]
		)
	enemy.global_position = start
	enemy._home_position = home
	enemy._wander_target = Vector3.ZERO
	enemy._wander_timer = 0.0


## 落点超出房间矩形多少米（0 = 在房内）。用房间的**真实矩形**，不是圆形近似。
func _room_overflow_m(point: Vector3, room: DungeonRoom3D) -> float:
	var local := room.global_transform.affine_inverse() * point
	var half := room.get_dimensions() * 0.5
	# 1cm 容差吸收浮点误差（与 `PORT_BOUNDARY_EPS` 同口径）。
	var over_x := maxf(0.0, absf(local.x) - half.x)
	var over_z := maxf(0.0, absf(local.z) - half.y)
	return maxf(over_x, over_z)


## 从房间内一侧朝怪打一条物理射线，看第一个命中是不是这只怪。
## 走真实碰撞层（默认 0xFFFFFFFF），所以"墙挡在前面"会体现出来。
##
## ⚠ 射线必须有**水平分量**。第一版把 `from` 放在房间中心正上方（与怪同一 x/z），
## 得到一条几乎垂直的射线，打中的是地板而不是怪 —— 于是"房内中心也打不中"，
## 那是探针自己的错，不是游戏的。
func _ray_hits_enemy(enemy: Enemy3D, room: DungeonRoom3D) -> bool:
	# ⚠ 射线高度必须跟着**怪自己的位置**走，不能写死 1.0。
	# 空尖弹是浮空怪（`hover: true`，脚部 y≈1.5），碰撞柱在它上方约 0.9m；
	# 写死 y=1.0 的射线是从它脚底穿过去的，结果"未命中任何物体" ——
	# 那是探针的错，不是命中盒的错（第二版诊断打出来的就是这个）。
	#
	# ⚠⚠ **2026-10-30 第二轮再修**：上面这条"跟着怪的高度走"本身也是错判据 ——
	# 它只能证明"在怪自己的高度上打得中"，证明不了"玩家打得中"。玩家的枪口是**恒定的
	# 0.44m**（射击没有俯仰），所以射线高度必须由**玩家的枪口**决定。
	# 本轮的 7 只浮空怪都是靠这个判据被误判成绿的。
	# 命中判定已由 `_egt_combat_plane_probe` 统一负责，这里保留同一个口径，避免两套判据打架。
	var aim_y := room.global_position.y + Enemy3D.PLAYER_MUZZLE_HEIGHT_M
	var to := Vector3(enemy.global_position.x, aim_y, enemy.global_position.z)
	var from := to + Vector3(6.0, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	var hit := enemy.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		print("    [ray] from=%s to=%s → 未命中任何物体" % [str(from), str(to)])
		return false
	var collider: Variant = hit.get("collider", null)
	print("    [ray] from=%s to=%s → 命中 %s（期望 %s）"
		% [str(from), str(to), str(collider), str(enemy)])
	return collider == enemy


func _finish() -> void:
	if _failures.is_empty():
		print("\nEGT_BLINK_PROBE_OK 瞬移落点全部在房内，命中链路正常")
		get_tree().quit(0)
		return
	print("\nEGT_BLINK_PROBE_FAIL 共 %d 项：" % _failures.size())
	for line in _failures:
		print("  - %s" % line)
	get_tree().quit(1)
