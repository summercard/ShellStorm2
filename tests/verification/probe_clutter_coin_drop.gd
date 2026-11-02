extends Node3D
## 易碎陈设破碎掉币（设计 r7）专项探针。
##
## 覆盖：掷骰确定性 / 概率区间 / 金额区间 / 只掷一次 / 恢复不重掷 /
## 原地偏移 / 房间账记账 / 落地后 0.5 s 拾取锁 / 端到端落在房间里。
##
## 不走 `verify_*` 套件：本探针只需要一个房间和一次真实 `shatter()`，
## 不必拉起整关，也不占 `core_scenes` 的预算。手动跑：
##   godot --headless --path <project> res://tests/verification/probe_clutter_coin_drop.tscn

const ROOM_ID := "qa_clutter_coin_drop"
## 概率、金额区间、锁时长**一律读 Dungeon3D 的常量**，不在探针里复刻数字。
## 业主一天内改过三次（8% → 60% → 10%）；硬编码的结果是每次调参都要改测试，
## 而「测试自己写错了阈值」是最容易把真故障放过去的一种绿。
const CHANCE := Dungeon3D.CLUTTER_COIN_DROP_CHANCE
const MIN_AMOUNT := Dungeon3D.CLUTTER_COIN_DROP_MIN
const MAX_AMOUNT := Dungeon3D.CLUTTER_COIN_DROP_MAX

var failures: Array[String] = []
var report := {}


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("CLUTTER_COIN: " + message)


func _ready() -> void:
	await _verify_roll_determinism()
	await _verify_roll_distribution()
	await _verify_planar_offset()
	await _verify_room_ledger_single_roll()
	await _verify_pickup_lockout()
	await _verify_end_to_end_drop()
	report["failures"] = failures
	var out := OS.get_environment("CLUTTER_COIN_QA_DIR")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out + "/probe.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if failures.is_empty():
		print("CLUTTER_COIN_DROP_PROBE_OK")
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- A1 / 纯函数

func _verify_roll_determinism() -> void:
	var first: Dictionary = Dungeon3D.resolve_clutter_coin_drop(12345, CHANCE, MIN_AMOUNT, MAX_AMOUNT)
	var second: Dictionary = Dungeon3D.resolve_clutter_coin_drop(12345, CHANCE, MIN_AMOUNT, MAX_AMOUNT)
	check(
		bool(first["hit"]) == bool(second["hit"]) and int(first["amount"]) == int(second["amount"]),
		"同一 seed 两次结果不同：%s vs %s" % [first, second]
	)
	# 概率边界：0 恒不中、1 恒中。这两条钉住「命中判定方向没写反」。
	var never := 0
	var always := 0
	for index in range(200):
		if bool(Dungeon3D.resolve_clutter_coin_drop(index, 0.0, 1, 10)["hit"]):
			never += 1
		if bool(Dungeon3D.resolve_clutter_coin_drop(index, 1.0, 1, 10)["hit"]):
			always += 1
	check(never == 0, "chance=0 仍命中 %d 次" % never)
	check(always == 200, "chance=1 未全中（%d/200）" % always)
	report["determinism"] = {"hit": bool(first["hit"]), "amount": int(first["amount"])}
	await get_tree().process_frame


# ---------------------------------------------------------------- A2 / A3

func _verify_roll_distribution() -> void:
	var samples := 10000
	var hits := 0
	var buckets := {}
	var min_amount := 99
	var max_amount := -1
	for index in range(samples):
		var result: Dictionary = Dungeon3D.resolve_clutter_coin_drop(
			hash("dist|%d" % index), CHANCE, MIN_AMOUNT, MAX_AMOUNT
		)
		if not bool(result["hit"]):
			continue
		hits += 1
		var amount := int(result["amount"])
		min_amount = mini(min_amount, amount)
		max_amount = maxi(max_amount, amount)
		buckets[amount] = int(buckets.get(amount, 0)) + 1
	var rate := float(hits) / float(samples)
	# 容差按二项分布现算：σ = sqrt(p(1-p)/n)，取 3σ。
	# 好处是「改成 10% 或 60% 都不用改测试」；坏处是 p 写错成 0.55 之类仍会被抓住。
	var sigma := sqrt(maxf(CHANCE * (1.0 - CHANCE), 1e-9) / float(samples))
	var tolerance := 3.0 * sigma
	check(
		absf(rate - CHANCE) <= tolerance,
		"命中率偏离 %0.3f 超过 3σ(±%0.4f)：%0.4f" % [CHANCE, tolerance, rate]
	)
	check(
		min_amount >= MIN_AMOUNT and max_amount <= MAX_AMOUNT,
		"金额越界 [%d, %d]，应在 [%d, %d]" % [min_amount, max_amount, MIN_AMOUNT, MAX_AMOUNT]
	)
	check(buckets.size() == 10, "金额档位不是 10 档：%d" % buckets.size())
	var per_bucket := float(hits) / float(maxi(1, int(MAX_AMOUNT) - int(MIN_AMOUNT) + 1))
	# 阈值取期望的 60%：容忍噪声，又能抓住「区间被写窄 / 某档永远抽不到」。
	for amount in range(MIN_AMOUNT, MAX_AMOUNT + 1):
		check(
			float(buckets.get(amount, 0)) >= per_bucket * 0.60,
			"金额 %d 档偏少：%d（期望 %0.0f）" % [amount, int(buckets.get(amount, 0)), per_bucket]
		)
	report["distribution"] = {
		"samples": samples, "hits": hits, "rate": snappedf(rate, 0.0001),
		"min_amount": min_amount, "max_amount": max_amount,
	}
	await get_tree().process_frame


func _verify_planar_offset() -> void:
	var worst := 0.0
	for index in range(500):
		var offset: Vector3 = Dungeon3D.clutter_coin_planar_offset("authored_Jar_%02d" % index)
		check(is_zero_approx(offset.y), "偏移带了竖直分量 %s" % offset)
		worst = maxf(worst, Vector2(offset.x, offset.z).length())
	check(worst <= Dungeon3D.CLUTTER_COIN_OFFSET_RADIUS_M + 0.0001, "偏移越界 %0.3f" % worst)
	var repeat_a: Vector3 = Dungeon3D.clutter_coin_planar_offset("authored_Jar_07")
	var repeat_b: Vector3 = Dungeon3D.clutter_coin_planar_offset("authored_Jar_07")
	check(repeat_a.is_equal_approx(repeat_b), "同一 id 偏移不确定：%s vs %s" % [repeat_a, repeat_b])
	report["offset_max_m"] = snappedf(worst, 0.001)
	await get_tree().process_frame


# ---------------------------------------------------------------- B1 / B2

func _verify_room_ledger_single_roll() -> void:
	var room: DungeonRoom3D = await _new_room()
	var emitted: Array[String] = []
	room.clutter_broken.connect(func(_room: DungeonRoom3D, _position: Vector3, id: String) -> void:
		emitted.append(id)
	)
	var clutter := room.find_children("*", "BreakableClutter3D", true, false)
	check(not clutter.is_empty(), "房间没有易碎件")
	if clutter.is_empty():
		return
	var target := clutter[0] as BreakableClutter3D
	var clutter_id := str(target.get_meta("clutter_id", ""))
	check(not clutter_id.is_empty(), "易碎件没有稳定 clutter_id")
	check(target.shatter(Vector3.RIGHT), "首次破碎失败")
	check(not target.shatter(Vector3.RIGHT), "重复破碎未被幂等挡下")
	await get_tree().process_frame
	check(emitted.size() == 1, "破碎信号发了 %d 次（应恰好 1 次）" % emitted.size())
	# B2：`restore_broken()` 走的是另一条路径，**不发** `broken`，因此不可能重掷。
	# 这条必须由断言钉住，不能只靠读代码。
	var second := clutter[clutter.size() - 1] as BreakableClutter3D
	second.restore_broken(Vector3.RIGHT)
	await get_tree().process_frame
	check(emitted.size() == 1, "restore_broken 之后又发了信号（%d）" % emitted.size())
	report["signal_emissions"] = emitted.size()
	room.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- G1~G5

func _verify_pickup_lockout() -> void:
	var currency := {
		"id": "__currency__", "name": "金币", "type": "currency",
		"count": 5, "is_currency": true,
	}
	# G1/G2/G3：动画期间 + 落地后 0.5 s 内都不可拾取；之后无需离场即可拾取。
	var locked := GroundLootPickup3D.new()
	locked.configure(currency, Color.WHITE)
	add_child(locked)
	locked.lock_pickup_after_spawn(Dungeon3D.CLUTTER_COIN_PICKUP_LOCKOUT_S)
	locked.begin_spawn_animation()
	await get_tree().process_frame
	check(not locked.is_pickup_available(), "G1 动画期间就可拾取")
	await get_tree().create_timer(0.30).timeout
	check(not locked.is_pickup_available(), "G1b 动画中段就可拾取")
	# 动画 0.81 s 结束后锁 0.5 s ⇒ 总计 1.31 s。1.10 s 处必须仍锁着。
	await get_tree().create_timer(0.80).timeout
	check(not locked.is_pickup_available(), "G2 落地 0.29s 后就解锁了（锁没生效）")
	await get_tree().create_timer(0.30).timeout
	check(locked.is_pickup_available(), "G3 锁到期后仍不可拾取（多锁了或误设离场要求）")
	# G3 反证：全过程玩家没离开过，说明没误用 `_pickup_requires_player_exit`。
	var snapshot := locked.get_model_snapshot()
	check(
		not bool(snapshot.get("pickup_requires_player_exit", true)),
		"G3b 误设了离场要求：玩家站着就永远捡不到"
	)
	check(
		is_equal_approx(float(snapshot.get("post_spawn_lockout_s", 0.0)), Dungeon3D.CLUTTER_COIN_PICKUP_LOCKOUT_S),
		"G2b 锁时长没写进实体：%s" % snapshot.get("post_spawn_lockout_s")
	)
	locked.queue_free()

	# G4：怪物掉落（延迟 0）照旧 —— 动画一结束就能捡，控制组必须是绿的。
	var immediate := GroundLootPickup3D.new()
	immediate.configure(currency, Color.WHITE)
	add_child(immediate)
	immediate.begin_spawn_animation()
	await get_tree().create_timer(1.00).timeout
	check(immediate.is_pickup_available(), "G4 怪物掉落的即时拾取被误伤")
	immediate.queue_free()

	# G5：没有视觉的掉落不许绕锁（`begin_spawn_animation` 的提前 return 分支）。
	var shapeless := GroundLootPickup3D.new()
	add_child(shapeless)
	shapeless.lock_pickup_after_spawn(0.4)
	shapeless.begin_spawn_animation()
	await get_tree().process_frame
	check(not shapeless.is_pickup_available(), "G5 无视觉掉落绕过了拾取锁")
	await get_tree().create_timer(0.50).timeout
	check(shapeless.is_pickup_available(), "G5b 无视觉掉落的锁没到期")
	shapeless.queue_free()
	await get_tree().process_frame
	report["pickup_lockout_s"] = Dungeon3D.CLUTTER_COIN_PICKUP_LOCKOUT_S


# ---------------------------------------------------------------- 端到端

## 走真实接线：房间发 `clutter_broken` → `Dungeon3D` 掷骰 → 金币落进房间。
func _verify_end_to_end_drop() -> void:
	var dungeon: Dungeon3D = (load("res://scenes/Dungeon3D.tscn") as PackedScene).instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed = 100990
	add_child(dungeon)
	await get_tree().process_frame
	var room: DungeonRoom3D = await _new_room()
	# 直接接上正式处理函数（正式运行由房间创建处统一接，见 Dungeon3D:2763）。
	if not room.clutter_broken.is_connected(dungeon._on_clutter_broken):
		room.clutter_broken.connect(dungeon._on_clutter_broken)

	# 概率降到 10% 后，「这一间房的 5 件恰好掉一枚」不再是大概率事件
	# （5 件全不中的概率还有 59%）。所以**不赌运气**：先在本地扫描 run_seed，
	# 挑一个能让本房至少命中一件的种子，再进真实链路。
	# 这样断言从「至少掉一枚」升级成「掉几枚必须等于算出来的几枚」——更硬且更稳。
	var clutter_nodes := room.find_children("*", "BreakableClutter3D", true, false)
	check(clutter_nodes.size() == 5, "本房易碎件数不是 5：%d" % clutter_nodes.size())
	var ids: Array[String] = []
	for value in clutter_nodes:
		ids.append(str((value as BreakableClutter3D).get_meta("clutter_id", "")))
	var expected_coins := 0
	var picked_seed := -1
	for seed_candidate in range(100990, 100990 + 4000):
		dungeon.run_seed = seed_candidate
		var candidate_hits := 0
		for clutter_id in ids:
			if bool(Dungeon3D.resolve_clutter_coin_drop(
				dungeon.clutter_coin_seed(clutter_id), CHANCE, MIN_AMOUNT, MAX_AMOUNT
			)["hit"]):
				candidate_hits += 1
		if candidate_hits > 0:
			picked_seed = seed_candidate
			expected_coins = candidate_hits
			break
	check(picked_seed > 0, "4000 个种子内找不到任何命中，掷骰或种子派生有问题")
	if picked_seed <= 0:
		room.queue_free()
		dungeon.queue_free()
		return
	report["end_to_end_seed"] = picked_seed

	# 逐件打碎，统计实际落地金币数与房间账。
	var broken := 0
	for value in clutter_nodes:
		if (value as BreakableClutter3D).shatter(Vector3.RIGHT):
			broken += 1
	await get_tree().process_frame
	await get_tree().process_frame
	var coins := 0
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and room.is_ancestor_of(value):
			var data := (value as GroundLootPickup3D).item_data
			if bool(data.get("is_currency", false)):
				coins += 1
				var count := int(data.get("count", 0))
				check(
					count >= MIN_AMOUNT and count <= MAX_AMOUNT,
					"金币数量越界 %d，应在 [%d, %d]" % [count, MIN_AMOUNT, MAX_AMOUNT]
				)
	# 房间账：每一件都要有 `broken`，且 `coin_dropped` 与实际落地一致。
	var ledger_coins := 0
	for value in clutter_nodes:
		var clutter_id := str((value as BreakableClutter3D).get_meta("clutter_id", ""))
		var state: Dictionary = room.get_clutter_runtime_state(clutter_id)
		check(bool(state.get("broken", false)), "%s 没进房间账" % clutter_id)
		if bool(state.get("coin_dropped", false)):
			ledger_coins += 1
	check(ledger_coins == coins, "账上掉币 %d 件，地上 %d 枚" % [ledger_coins, coins])
	# 比「至少一枚」更硬：地上枚数必须**等于**用同一套种子与参数预先算出的命中件数。
	# 少一枚 = 发放路径丢了；多一枚 = 重复掷骰。两种都能抓。
	check(
		coins == expected_coins,
		"地上 %d 枚，但按 seed=%d 应命中 %d 件" % [coins, picked_seed, expected_coins]
	)
	report["end_to_end"] = {
		"clutter_total": broken, "coins_dropped": coins,
		"ledger_coins": ledger_coins, "expected_coins": expected_coins,
	}
	room.queue_free()
	dungeon.queue_free()
	await get_tree().process_frame


func _new_room() -> DungeonRoom3D:
	var room := DungeonRoom3D.new()
	room.configure({
		"room_id": ROOM_ID, "room_type": "STAIR_LOBBY", "size_class": "tower_cell",
		"doors": ["south"], "door_targets": {"south": "next"},
		"custom_dimensions": Vector2(15, 15), "tower_module_shell": true,
	})
	add_child(room)
	room.ensure_shell_built()
	room.ensure_detail_built()
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return room
