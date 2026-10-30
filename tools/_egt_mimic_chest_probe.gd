extends Node
## 宝箱拟态探针（2026-10-30 接回拟态）。
##
## 分三层，**每层只验一件事**，因为这三件事的失败方式完全不同：
##
## | 层 | 验什么 | 失败长什么样 |
## |---|---|---|
## | A 生成器掷骰（不建地牢） | 品质按权重真的出现、拟态率 ≈ `chance`、同盐幂等 | 一层里每只箱子都是 common（旧实现就是这样，且**不报错**） |
## | B 字段透传 | `chest_placements` 的 `mimic` 能活着穿过 `room_from_source()` 白名单 | 数据里有、运行时全是 false（宝箱那次就栽在这一步） |
## | C 运行时全链路 | 开箱 → 箱子消失 / 钥匙照扣 / 不掉物 / 刷怪 → 击杀掉回 / **不算清房** | 开箱直接掉东西（拟态等于白送一只怪）；或宝箱房被记成「已清」 |
##
## 用法：godot --headless --path . --scene res://tools/_egt_mimic_chest_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const PLAN_PATH := "res://data/level_plans/expedition_03/level_plan.json"
const SEED_VALUE := 77003244
const FATE_BRIDGE_PATH := "/root/FateCardGameBridge"

## A 层的虚拟房间数。4000 次时最常见的 common 也有 2480 次，
## 允许 ±1.5 个百分点的绝对偏差足够挡住"权重没生效"，又不会被正常抖动打红。
const ROLL_SAMPLES := 4000
const ROLL_TOLERANCE := 0.015

## 拟态从开箱到消失的动画时长（`TreasureChest3D.MIMIC_SHAKE_SECONDS` + 0.34）。
## 按时间等而不是按帧等 —— 改动画时长时这里会自动跟上。
const REVEAL_SETTLE_SEC := TreasureChest3D.MIMIC_SHAKE_SECONDS + 0.34 + 0.1

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _ready() -> void:
	print("=== EGT_MIMIC_CHEST_PROBE 宝箱拟态 ===")
	_verify_rolls()
	await _verify_runtime()
	_finish()


# ---------------------------------------------------------------------------
# A. 生成器掷骰
# ---------------------------------------------------------------------------

func _verify_rolls() -> void:
	var plan := _load_json(PLAN_PATH)
	var cfg := plan.get("treasure_chests", {}) as Dictionary
	if cfg.is_empty():
		_check(false, "level_plan 里没有 treasure_chests")
		return
	var weights := cfg.get("quality_weights", {}) as Dictionary
	var mimic_chance := float((cfg.get("mimic", {}) as Dictionary).get("chance", 0.0))
	var total_weight := 0.0
	for value in weights.values():
		total_weight += maxf(0.0, float(value))
	print("\n--- A 生成器掷骰（%d 个虚拟房间）---" % ROLL_SAMPLES)
	print("  配置：权重 %s（合计 %.0f），拟态 %.0f%%" % [str(weights), total_weight, mimic_chance * 100.0])

	var counts := {}
	var mimic_hits := 0
	for index in range(ROLL_SAMPLES):
		# 盐模拟真实调用：房号会重复出现（每张骨架都有 reward_01），层种子每局不同。
		var salt := "reward_%02d#%d" % [index % 7, 900000 + index]
		var placements := FloorPlanGenerator._chest_placements_for(
			Vector2(40.0, 30.0), cfg, salt
		)
		if placements.is_empty():
			_check(false, "盐『%s』算不出任何宝箱" % salt)
			return
		var entry := placements[0] as Dictionary
		var quality := str(entry.get("quality", ""))
		counts[quality] = int(counts.get(quality, 0)) + 1
		if bool(entry.get("mimic", false)):
			mimic_hits += 1

	for quality in weights.keys():
		var key := str(quality)
		var expected := maxf(0.0, float(weights[quality])) / maxf(1.0, total_weight)
		var actual := float(counts.get(key, 0)) / float(ROLL_SAMPLES)
		print(
			"  %-10s 期望 %5.1f%%  实测 %5.1f%%  %s"
			% [key, expected * 100.0, actual * 100.0, "✓" if absf(actual - expected) <= ROLL_TOLERANCE else "✗"]
		)
		# 期望为 0 的档位只要求"真的没出现"，不做区间比较。
		if expected <= 0.0:
			_check(int(counts.get(key, 0)) == 0, "%s 权重为 0 却出现了 %d 次" % [key, int(counts.get(key, 0))])
			continue
		_check(
			absf(actual - expected) <= ROLL_TOLERANCE,
			"%s 实测出现率 %.1f%%，配置期望 %.1f%%（容差 ±%.1f 个百分点）"
			% [key, actual * 100.0, expected * 100.0, ROLL_TOLERANCE * 100.0]
		)

	# 旧实现（按箱序号轮转）在这里会得到 epic 0 次、rare 0 次 —— 这条断言就是给它的墓碑。
	_check(int(counts.get("epic", 0)) > 0, "epic 一次都没出现（权重是死配置）")
	_check(int(counts.get("rare", 0)) > 0, "rare 一次都没出现（权重是死配置）")

	var mimic_rate := float(mimic_hits) / float(ROLL_SAMPLES)
	print(
		"  拟态      期望 %5.1f%%  实测 %5.1f%%  %s"
		% [mimic_chance * 100.0, mimic_rate * 100.0,
		   "✓" if absf(mimic_rate - mimic_chance) <= ROLL_TOLERANCE else "✗"]
	)
	_check(
		absf(mimic_rate - mimic_chance) <= ROLL_TOLERANCE,
		"拟态率实测 %.1f%%，配置 %.1f%%" % [mimic_rate * 100.0, mimic_chance * 100.0]
	)

	# 幂等：同一个盐调用两次必须逐字段相同 —— 否则流送卸载重建、读档重进会让箱子换品质/换身份。
	var salt_a := "reward_01#77003244"
	var first := FloorPlanGenerator._chest_placements_for(Vector2(40.0, 30.0), cfg, salt_a)
	var second := FloorPlanGenerator._chest_placements_for(Vector2(40.0, 30.0), cfg, salt_a)
	_check(first == second, "同一个盐两次生成结果不一致（掷骰不是纯函数）")
	print("  同盐幂等：%s ✓" % str(first))


# ---------------------------------------------------------------------------
# B + C. 运行时全链路
# ---------------------------------------------------------------------------

func _verify_runtime() -> void:
	print("\n--- B/C 运行时 ---")
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		_check(false, "场景不是 TowerDescent3D")
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	# 找一间宝箱房。判据与 `_egt_chest_probe` 同：**有 `chest_placements` 的房就是宝箱房**
	# （flow 的 kind 不写进运行时 `room_type`，按 REWARD 找会是 0 间）。
	var room: DungeonRoom3D = null
	for value in tower._rooms:
		var candidate := value as DungeonRoom3D
		if candidate != null and not (candidate.chest_placements as Array).is_empty():
			room = candidate
			break
	if room == null:
		_check(false, "全层没有宝箱房")
		return
	await _enter_room(tower, room)
	var chests := room.get_treasure_chests()
	if chests.is_empty():
		_check(false, "%s 没有建出宝箱" % room.room_id)
		return
	var chest := chests[0]
	if chest == null:
		_check(false, "%s 取不到 TreasureChest3D" % room.room_id)
		return

	# —— B 字段透传 ——
	var placement := (room.chest_placements[0] as Dictionary)
	_check(placement.has("mimic"), "chest_placements 条目里没有 `mimic` 字段（生成器没写，或被白名单吃掉）")
	_check(
		placement.has("mimic_monster_kind"),
		"chest_placements 条目里没有 `mimic_monster_kind` 字段"
	)
	_check(
		chest.mimic == bool(placement.get("mimic", false)),
		"透传不一致：数据 mimic=%s，实例 mimic=%s"
		% [str(placement.get("mimic", false)), str(chest.mimic)]
	)
	_check(
		chest.mimic_monster_kind == str(placement.get("mimic_monster_kind", "")),
		"透传不一致：数据 kind=%s，实例 kind=%s"
		% [str(placement.get("mimic_monster_kind", "")), chest.mimic_monster_kind]
	)
	print(
		"  透传：数据 mimic=%s kind=%s → 实例 mimic=%s kind=%s"
		% [
			str(placement.get("mimic", false)), str(placement.get("mimic_monster_kind", "")),
			str(chest.mimic), chest.mimic_monster_kind,
		]
	)

	# —— C 运行时 ——
	# 本 seed 的这只箱子未必是拟态（每箱 20%），所以**显式置真**。
	# 这不是绕过数据：A 层已证明掷骰按 20% 出拟态、B 层已证明字段确实落到实例上，
	# 这里要测的是"标记为真之后那条分支对不对"。反过来依赖 seed 撞上拟态，
	# 会让这条探针的结论随种子飘。
	chest.mimic = true
	chest.mimic_monster_kind = "egt_mimic"

	tower._room_key_count = 1
	tower._temporary_room_keys = 0
	var loot_before := _count_ground_loot()
	var cards_before := _fate_card_count()
	var cleared_rooms_before := tower._count_cleared_content_rooms()
	var room_cleared_before := room.cleared
	chest._player_in_range = true

	tower._on_chest_open_requested(room, chest)

	# ⚠ **不 await 就取怪**：`_spawn_enemy_batch` 是同步 `add_child`，怪当帧就在索引里。
	# 而伪装位必须在**同一帧**读 —— 晚一帧 `_tick_egt_disguise` 会按
	# `reveal_radius_m = 3.4` 自己解除（我们刷在 3.0m 处），于是「忘了调
	# `reveal_disguise_now()`」会被探针自己的等待掩盖掉。
	# 这不是假设：把那一行删掉之后，"晚一帧再检查"的版本**仍然全绿**（实测）。
	var mimicked: Enemy3D = null
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and enemy.get_meta("chest_mimic", false):
			mimicked = enemy
			break
	if mimicked == null:
		_check(false, "开拟态箱没有刷出带 `chest_mimic` 标记的怪")
		return
	_check(
		not mimicked._disguised,
		"拟态出生仍是伪装态（静止 / 不攻击 / 不吃伤害）—— `reveal_disguise_now()` 没调或没生效"
	)

	await get_tree().process_frame
	await get_tree().process_frame

	_check(chest.is_opened(), "拟态箱没有进入已开状态（会变成无限次触发的刷怪点）")
	_check(tower._get_total_room_keys() == 0, "开拟态箱没有扣钥匙（这条机制的恶意就在这，别顺手改掉）")
	_check(
		_count_ground_loot() == loot_before,
		"开拟态箱就直接掉了物资（%d → %d）—— 物资应该在怪肚子里"
		% [loot_before, _count_ground_loot()]
	)
	_check(
		tower.status_label.text.contains("拟态"),
		"开拟态箱后状态栏没有提示拟态（实际：『%s』）" % tower.status_label.text
	)

	# 刷出来的怪：必须是配置的 kind、必须在本房索引里、必须不与玩家重叠。
	_check(
		mimicked.enemy_kind == "egt_mimic",
		"刷出的怪 kind=%s，配置是 egt_mimic" % mimicked.enemy_kind
	)
	var gap := Vector2(
		mimicked.global_position.x - tower.player.global_position.x,
		mimicked.global_position.z - tower.player.global_position.z
	).length()
	_check(
		gap >= Dungeon3D.CHEST_MIMIC_MIN_SPAWN_DISTANCE_M - 0.05,
		"拟态贴脸刷出（离玩家 %.2fm，下限 %.2fm）—— 生成当帧就会结算接触伤害"
		% [gap, Dungeon3D.CHEST_MIMIC_MIN_SPAWN_DISTANCE_M]
	)
	var half := room.get_dimensions() * 0.5
	var local := room.global_transform.affine_inverse() * mimicked.global_position
	_check(
		absf(local.x) <= half.x and absf(local.z) <= half.y,
		"拟态刷在房间外（局部 %s，房半尺寸 %s）" % [str(local), str(half)]
	)
	_check(not mimicked._disguised, "拟态在刷出两帧后又回到伪装态")
	print(
		"  刷怪：%s @ %s，离玩家 %.2fm，伪装=%s"
		% [mimicked.enemy_kind, str(mimicked.global_position), gap, str(mimicked._disguised)]
	)

	# —— AI 活性：拟态是"怪"，不是一尊雕像 ——
	#
	# 判据是「**离开过** dormant/idle」，不是「一直在动」：拟态 `range = 9m`、
	# 玩家就在 3m 处，它完全可能站着开火一步不挪。要求位移会误报。
	# 这一条是从业主上一次报单学来的 —— 那只瞬移怪"双向都打不中"时，
	# 在状态机上看起来也完全正常，所以这里的下限必须低到只有"真的接入战斗"才过。
	var observed := {}
	var elapsed := 0.0
	while elapsed < 2.4:
		await get_tree().create_timer(0.2).timeout
		elapsed += 0.2
		observed[str(mimicked.ai_state)] = true
	var engaged := false
	for state_name in observed.keys():
		if str(state_name) not in ["dormant", "idle", "patrol"]:
			engaged = true
			break
	_check(
		engaged,
		"拟态出生 2.4s 内一直停在 %s —— 没进入战斗（会变成站在那不动、也打不还手的雕像）"
		% str(observed.keys())
	)
	print("  2.4s 内状态：%s" % str(observed.keys()))

	# 等现形动画播完：箱子视觉与碰撞都得收掉，否则房间中央留一块看不见的挡路石头。
	await get_tree().create_timer(REVEAL_SETTLE_SEC).timeout
	var snapshot := chest.get_chest_snapshot()
	_check(
		not bool(snapshot.get("visual_visible", true)),
		"拟态现形后箱子视觉还在（应该整体消失，把舞台让给怪）"
	)
	_check(
		bool(snapshot.get("collision_disabled", false)),
		"拟态现形后箱子碰撞没关（房间中央留了一块看不见的挡路石头）"
	)
	print("  现形后：箱子视觉=%s 碰撞已关=%s" % [str(snapshot.get("visual_visible")), str(snapshot.get("collision_disabled"))])

	# —— 流送重建：卸载 detail 再重建，箱子不能变回一只「已开/可开」的普通箱 ——
	#
	# 这是最容易漏的一条：房间流送出去再进来是常态，而 `_restore_treasure_chests()`
	# 在改造前只认 `true/false` 两种状态。若拟态箱重建后变成一只「已开启的空箱子」，
	# 玩家会看到房间中央凭空多出一只被开过的箱子（怪却已经没了）。
	var expected_drops := chest.drop_count
	room._unload_runtime_detail()
	room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	var rebuilt_list := room.get_treasure_chests()
	_check(not rebuilt_list.is_empty(), "detail 重建后宝箱节点直接消失了（应该隐藏，不是删除）")
	if not rebuilt_list.is_empty():
		var rebuilt := rebuilt_list[0]
		var rebuilt_snapshot := rebuilt.get_chest_snapshot()
		_check(rebuilt.is_opened(), "detail 重建后拟态箱变回未开（可以再开一次 = 刷钥匙 / 刷怪的漏洞）")
		_check(
			not bool(rebuilt_snapshot.get("visual_visible", true)),
			"detail 重建后箱子视觉又出现了（房间里凭空多出一只箱子）"
		)
		_check(
			bool(rebuilt_snapshot.get("collision_disabled", false)),
			"detail 重建后箱子碰撞又回来了（看不见的挡路石头）"
		)
		print(
			"  流送重建：已开=%s 视觉=%s 碰撞已关=%s"
			% [
				str(rebuilt.is_opened()), str(rebuilt_snapshot.get("visual_visible")),
				str(rebuilt_snapshot.get("collision_disabled")),
			]
		)

	# —— 击杀：物资与命运卡这时才该出现 ——
	var loot_at_kill := _count_ground_loot()
	var cards_at_kill := _fate_card_count()
	for _index in range(6):
		if mimicked.ai_state == "dead":
			break
		mimicked.take_damage(999999)
		for _frame in 3:
			await get_tree().process_frame
	_check(mimicked.ai_state == "dead", "拟态打不死（take_damage 后状态仍是 %s）" % mimicked.ai_state)
	await get_tree().process_frame
	await get_tree().process_frame

	var loot_gained := _count_ground_loot() - loot_at_kill
	var cards_gained := _fate_card_count() - cards_at_kill
	print(
		"  击杀后：物资 +%d 件（箱内 %d + 拟态自身击杀掉落），命运卡 +%d 张，status=%s"
		% [loot_gained, expected_drops, cards_gained, tower.status_label.text]
	)
	# ⚠ 判据是 `>=` 而不是 `==`：拟态**同时也是一只普通怪**，击杀会再走一次怪物掉落表，
	# 所以地面上会多出 1 件。要求 `== drop_count` 等于要求"拟态不许掉自己的东西"，
	# 那会让它比同族怪凭空少一档收益。
	_check(
		loot_gained >= expected_drops,
		"拟态击杀只掉了 %d 件，箱内配置 %d 件 —— 箱内物资没补齐" % [loot_gained, expected_drops]
	)
	_check(cards_gained >= 1, "拟态击杀没有给命运卡")

	# —— 关键：拟态死了**不算清房** ——
	_check(
		room.cleared == room_cleared_before,
		"击杀拟态把宝箱房标成了已清（%s → %s）" % [str(room_cleared_before), str(room.cleared)]
	)
	_check(
		tower._count_cleared_content_rooms() == cleared_rooms_before,
		"击杀拟态让「已清内容房数」涨了（%d → %d）—— 会提前满足撤离门 / 支线的解锁条件"
		% [cleared_rooms_before, tower._count_cleared_content_rooms()]
	)

	# —— 重复结算：再调一次击杀不得再掉一遍 ——
	var loot_after := _count_ground_loot()
	tower._on_enemy_killed(mimicked, mimicked.get_enemy_data())
	await get_tree().process_frame
	_check(
		_count_ground_loot() == loot_after,
		"重复结算又掉了一份物资（%d → %d）" % [loot_after, _count_ground_loot()]
	)

	tower.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _finish() -> void:
	if failures.is_empty():
		print(
			"\nEGT_MIMIC_CHEST_PROBE_OK 掷骰分布 / 字段透传 / 现形 / 刷怪不贴脸 / 击杀掉回 / 不算清房"
		)
		get_tree().quit(0)
		return
	print("\nEGT_MIMIC_CHEST_PROBE_FAIL count=%d" % failures.size())
	for message in failures:
		print("  - %s" % message)
	get_tree().quit(1)


func _enter_room(tower: TowerDescent3D, room: DungeonRoom3D) -> void:
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(room.room_id)
	for _frame in 4:
		await get_tree().process_frame


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _count_ground_loot() -> int:
	return get_tree().get_nodes_in_group("ground_loot_3d").size()


func _fate_card_count() -> int:
	var bridge := get_node_or_null(FATE_BRIDGE_PATH)
	if bridge == null:
		return 0
	var cards: Variant = bridge.call("get_cards")
	return (cards as Array).size() if cards is Array else 0
