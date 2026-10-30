extends Node

## 远征03 出手节奏实测探针（2026-10-30）。
##
## 业主体感：「怪物会连续攻击玩家、没有间隔，很奇怪」。
## 这个探针**不猜**，直接进远征03 的真实战斗房，让玩家站桩挨打，把每只怪
## 的出手时刻逐次记下来，算出：
##   ① 每只怪的**攻击间隔序列**（attack→attack）
##   ② **同屏同时处于攻击状态**的怪数峰值（这就是「没有间隔」的直接证据）
##   ③ **每秒出手总次数**与**每秒子弹总数**（弹幕密度）
##
## 用法：
##   godot --path . --scene res://tools/_egt_cadence_probe.tscn
##
## ## 为什么用 `ai_state` 的跃迁而不是 `_attack_timer`
## `_attack_timer` 在 `_perform_attack()` 里被设成 `attack_cooldown`，之后逐帧递减 ——
## 它同时受 `get_attack_frequency_multiplier()`（人工光照 ×0.40）影响，
## 读它算出来的"间隔"会把光照倍率混进去，那是另一个变量。
## `telegraph → attack` 的跃迁是**唯一一次真正开火**的瞬间，与冷却算法无关。
##
## ## 为什么玩家必须站桩且不开枪
## 怪开火的前置是「距离 ≤ attack_range」。玩家一跑就反复进出射程，
## 统计出来的间隔会混入"玩家跑开"的时间，读不出节奏本身。
## 站桩 = 恒定在射程内 ⇒ 测到的间隔就是**冷却决定的间隔**。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED_VALUE := 77003244
## 观察时长（秒）。取 20s：
##   最慢的怪（cooldown 3.6 + telegraph 0.38）在 20s 内也有 5 轮；
##   最快的（cooldown 1.05）有 14 轮。两者都能算出稳定间隔。
const OBSERVE_SEC := 20.0

var _attacks: Dictionary = {}        # enemy_id -> Array[float]（出手时刻）
var _kinds: Dictionary = {}          # enemy_id -> kind
var _max_concurrent := 0             # 同屏同时攻击的峰值
var _concurrent_sum := 0.0
var _concurrent_samples := 0
var _prev_state: Dictionary = {}     # enemy_id -> 上一帧 ai_state
var _bullet_samples: Array[int] = [] # 每 0.5s 采样的屏幕子弹数
var _elapsed := 0.0
var _room_id := ""
var _room_type := ""
var _spawned := 0


func _ready() -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("EGT_CADENCE_FAIL 场景不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	# 挑**编成最重**的房（盒数最多）—— 那才是业主抱怨"连续攻击"的场景。
	# 挑空房或单盒房测出来的节奏没意义。
	var target: DungeonRoom3D = null
	var best_boxes := -1
	for room in tower._rooms:
		var candidate := room as DungeonRoom3D
		if candidate == null:
			continue
		if str(candidate.room_type) not in Dungeon3D.HOSTILE_ROOM_TYPES:
			continue
		if str(candidate.room_type) == "BOSS":
			continue
		var boxes := (candidate.spawn_placements as Array).size()
		if boxes <= 0:
			continue
		if boxes > best_boxes:
			best_boxes = boxes
			target = candidate
	if target == null:
		print("EGT_CADENCE_FAIL 没有找到有编成的敌对房")
		get_tree().quit(1)
		return

	_room_id = target.room_id
	_room_type = str(target.room_type)
	tower.player.global_position = target.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(target.room_id)
	await get_tree().create_timer(
		TowerDescent3D.FLOW_ROOM_SEAL_DELAY_S + TowerDescent3D.FLOW_ROOM_SPAWN_PAUSE_S + 1.2
	).timeout
	for _frame in 10:
		await get_tree().process_frame

	_spawned = _alive_enemies(tower, target).size()
	print("EGT_CADENCE_ROOM id=%s type=%s boxes=%d spawned=%d observe=%.0fs"
		% [_room_id, _room_type, best_boxes, _spawned, OBSERVE_SEC])
	for enemy in _alive_enemies(tower, target):
		_kinds[enemy.get_instance_id()] = enemy.enemy_kind
		print("  ENEMY %-22s hp=%-5d speed=%.2f range=%.1f cd=%.2f style=%s"
			% [enemy.enemy_kind, enemy.max_hp, enemy.move_speed, enemy.attack_range,
			   enemy.attack_cooldown, str(enemy._active_profile.get("attack_style", "-"))])

	# 玩家站桩：清零输入、关掉玩家武器的自动开火（若有），只挨打。
	if tower.player != null:
		if tower.player.has_method("set_physics_process"):
			tower.player.set_physics_process(false)

	var sample_accum := 0.0
	var last_tick := Time.get_ticks_msec()
	while _elapsed < OBSERVE_SEC:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var dt := float(now - last_tick) / 1000.0
		last_tick = now
		_elapsed += dt
		sample_accum += dt
		var concurrent := 0
		for enemy in _alive_enemies(tower, target):
			var eid: int = enemy.get_instance_id()
			var state: String = str(enemy.ai_state)
			if not _kinds.has(eid):
				_kinds[eid] = enemy.enemy_kind
			# 只在**真实存活**时统计；死亡后同一 id 不会再出手
			if state == "attack":
				concurrent += 1
			if str(_prev_state.get(eid, "")) != "attack" and state == "attack":
				if not _attacks.has(eid):
					_attacks[eid] = []
				(_attacks[eid] as Array).append(_elapsed)
			_prev_state[eid] = state
		_max_concurrent = maxi(_max_concurrent, concurrent)
		_concurrent_sum += float(concurrent)
		_concurrent_samples += 1
		if sample_accum >= 0.5:
			sample_accum = 0.0
			_bullet_samples.append(_count_hostile_projectiles())

	_report()
	get_tree().quit(0)


func _alive_enemies(tower, room) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var e := value as Enemy3D
		if e != null and e.ai_state != "dead" and e.current_hp > 0:
			out.append(e)
	return out


## 屏幕上的敌方子弹数。
##
## `Projectile3D` **不在任何组里**（子弹靠池化管理，逐颗 `get_nodes_in_group` 会持续分配），
## 所以唯一可读的活弹数是 `ProjectilePool3D.get_snapshot()["active"]`。
## 局限要说清：这个数是**敌我合计** —— 玩家这一轮站桩不开枪，所以此时它约等于敌弹。
func _count_hostile_projectiles() -> int:
	for pool in get_tree().get_nodes_in_group("projectile_pool_3d"):
		if pool is ProjectilePool3D:
			return int((pool as ProjectilePool3D).get_snapshot().get("active", 0))
	return 0


func _report() -> void:
	print("\n=== 逐只出手间隔 ===")
	var all_intervals: Array[float] = []
	var rows: Array = []
	for eid in _attacks.keys():
		var times: Array = _attacks[eid]
		var kind := str(_kinds.get(eid, "?"))
		var gaps: Array[float] = []
		for i in range(1, times.size()):
			gaps.append(float(times[i]) - float(times[i - 1]))
		var gap_text := "-"
		if not gaps.is_empty():
			var lo: float = gaps.min()
			var hi: float = gaps.max()
			var mean := 0.0
			for g in gaps:
				mean += g
				all_intervals.append(g)
			mean /= float(gaps.size())
			gap_text = "min %.2fs / avg %.2fs / max %.2fs" % [lo, mean, hi]
		rows.append([kind, times.size(), gap_text])
	# 按攻击次数降序：打得最多的排前面，一眼看出"谁在刷屏"
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for r in rows:
		print("  %-22s 出手 %2d 次   间隔 %s" % [str(r[0]), int(r[1]), str(r[2])])

	print("\n=== 全房汇总 ===")
	var total_attacks := 0
	for eid in _attacks.keys():
		total_attacks += (_attacks[eid] as Array).size()
	var avg_concurrent := 0.0
	if _concurrent_samples > 0:
		avg_concurrent = _concurrent_sum / float(_concurrent_samples)
	print("  存活怪数           %d" % _spawned)
	print("  总出手次数         %d" % total_attacks)
	print("  平均出手频率       %.2f 次/秒（全房合计）" % (float(total_attacks) / OBSERVE_SEC))
	print("  同屏同时攻击峰值   %d 只" % _max_concurrent)
	print("  同屏同时攻击均值   %.2f 只" % avg_concurrent)
	if not all_intervals.is_empty():
		var s := 0.0
		var lo: float = all_intervals.min()
		var hi: float = all_intervals.max()
		for g in all_intervals:
			s += g
		print("  单只攻击间隔       min %.2fs / avg %.2fs / max %.2fs（n=%d）"
			% [lo, s / float(all_intervals.size()), hi, all_intervals.size()])
	if not _bullet_samples.is_empty():
		var bs := 0
		var bmax := 0
		for b in _bullet_samples:
			bs += b
			bmax = maxi(bmax, b)
		print("  屏幕敌弹均值       %.1f 发（峰值 %d 发）"
			% [float(bs) / float(_bullet_samples.size()), bmax])
		# 弹幕"从不断档"的判据：如果屏幕敌弹的最小值也 >0，说明玩家**任何时候**都有子弹在飞。
		var bmin := 99999
		for b in _bullet_samples:
			bmin = mini(bmin, b)
		print("  屏幕敌弹最小值     %d 发（>0 ⇒ 全程没有空窗）" % bmin)
	# 节拍器读数：`blocked` 是「怪想打但被房间节奏挡下」的次数。
	# 它必须 > 0，否则说明节拍器根本没生效（房间 id 为空？规则没下发？）——
	# 那种情况下上面的数字会一起"看起来正常"，是最容易骗过自己的失败方式。
	if MonsterAIManager != null:
		var gate: Dictionary = MonsterAIManager.get_room_gate_stats()
		print("  房间节拍器         gap=%dms 挡下=%d 次 已跟踪房间=%d"
			% [int(gate.get("gap_msec", 0)), int(gate.get("blocked", 0)),
			   int(gate.get("rooms_tracked", 0))])
	print("EGT_CADENCE_DONE")
