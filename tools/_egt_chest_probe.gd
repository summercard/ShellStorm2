extends Node
## 宝箱房探针（2026-10-29；2026-11-05 按业主两轮新口径重写）。
##
## 验的是**业主那几条需求**：
##   ① 宝箱房要真的有宝箱（不是只在数据里写了一句）；
##   ② 开箱**不需要钥匙、直接开启**，把物品掉到地上、并弹出命运卡购买界面；
##   ③ **开箱有前置与后置过渡**：按下 E 先抖两下 → 蓄力 → 砰 → 余韵，弹窗在余韵里淡入。
##      「不要突然打开完全没有过渡」这句话必须落成断言，否则改动画时没人会发现它退化了。
## 外加几条「不写就会静默错」的边界：
##   ④ 本关没有钥匙经济：开局 0 把、开箱也不扣（钥匙全退役）；
##   ⑤ 同一只箱子只能开一次（`commit_opened()` 幂等 + 上层不重复结算）；
##   ⑥ 掉落数量 = `drop_count`，且**必须晚于「砰」**（不能从关着的箱子里冒出来）；
##   ⑦ **不再自动发卡**：命运卡只能从购买界面用本局金币买（`fate_card_per_open = 0`）；
##   ⑧ **走真实交互链路**（`perform_interaction() → chest.open_requested → room →
##      dungeon._on_chest_open_requested()`）再开一只。
##
## ⑧ 是这份探针最重要的一条，也是 2026-11-05 之前一直缺的那条：
## 前面所有断言都是**直接调** `tower._on_chest_open_requested(room, chest)`，
## 而真实玩法要先经过两个信号。`TowerDescent3D` 有自己的建房间循环，漏接了
## `room.chest_open_requested` ⇒ 远征里按 E **箱子抖完什么都不发生**，且不报错。
## 直接调处理函数的写法正好绕过这条断链，于是前几轮验收全绿而功能是死的。
## **凡是「信号 → 处理函数」的链路，必须至少有一条走信号的断言。**
##
## 时间断言用 `create_timer` 按真实时长等，不按帧 —— 动画是时间驱动的，
## 按帧等会在不同帧率下变成两种结论（这个文件里曾经栽过一次同类问题）。
##
## 用法：godot --headless --path . --scene res://tools/_egt_chest_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED_VALUE := 77003244
const FATE_BRIDGE_PATH := "/root/FateCardGameBridge"
## 「砰」之后留给掉落物的露脸时间 + 弹窗淡入的余量。
## 与 `Dungeon3D.CHEST_BURST_TO_OVERLAY_SECONDS` 同源：从 README 级常量读不到私有 const，
## 所以这里显式写 0.30 + 0.12 缓冲，改那边时这条会先红，提醒同步。
const CHEST_OVERLAY_WAIT_SEC := 0.42

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## 等真实时长（`process_always = false`：与箱子 tween 一样受暂停影响）。
func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(seconds, false).timeout


func _ready() -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("EGT_CHEST_PROBE_FAIL 场景不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	# —— ① 每间宝箱房都要有箱子 ——
	#
	# ⚠ **不能按 `room_type == "REWARD"` 找**：flow 的 kind 不写进运行时 `room_type`
	# （`_flow_room_type()` 只区分 SAFE_ROOM / EXTRACTION_ROOM / BOSS_ROOM / COMMON_ROOM），
	# REWARD 房在运行时就是一间 `COMMON_ROOM`。第一版探针按 REWARD 找，结果「0 张宝箱房」，
	# 而实际上 `reward_01` / `reward_02` 都在。
	#
	# 正确判据：**有 `chest_placements` 的房就是宝箱房** —— 生成器只给 REWARD 房写这个字段，
	# 所以这条等价于"宝箱房"，而且不依赖任何房型命名。
	var chest_rooms: Array[DungeonRoom3D] = []
	for room in tower._rooms:
		var candidate := room as DungeonRoom3D
		if candidate != null and not (candidate.chest_placements as Array).is_empty():
			chest_rooms.append(candidate)
	print("宝箱房数量：%d → %s" % [chest_rooms.size(), str(chest_rooms.map(func(r): return r.room_id))])
	_check(not chest_rooms.is_empty(), "远征03 一张宝箱房都没有（生成期没给 REWARD 房写 chest_placements）")

	var total_chests := 0
	for room in chest_rooms:
		var declared := (room.chest_placements as Array).size()
		# ⚠ **必须先让房间建内容再数箱子**：flow 房间的细节（家具 / 摆件 / 宝箱）
		# 是「进房时按需构建」的，开局所有房的 `_build_content()` 都还没跑。
		# 第一版探针在进入房间之前就数实例，恒得 0 —— 那是探针的错，不是箱子没建。
		await _enter_room(tower, room)
		var built := room.get_treasure_chests().size()
		total_chests += built
		print("  %s chest_placements=%d 实例化=%d" % [room.room_id, declared, built])
		_check(built == declared, "%s 声明 %d 只箱子但只建出 %d 只" % [room.room_id, declared, built])
		# 宝箱房必须是「无怪房」—— 原作 REWARD 是 enemyless，摆怪会让开箱变成战斗中断。
		_check(
			(room.spawn_placements as Array).is_empty(),
			"%s 是宝箱房但还摆了刷怪盒（宝箱房应当无怪）" % room.room_id
		)
	_check(total_chests > 0, "全层一只宝箱都没建出来")

	if chest_rooms.is_empty() or total_chests == 0:
		_finish()
		return

	var room := chest_rooms[0]
	# 前面已经进过每间宝箱房，这里重新进第一间以确保它当前是"在场"状态。
	await _enter_room(tower, room)
	var chest := room.get_treasure_chests()[0]
	if chest == null:
		_check(false, "%s 取不到 TreasureChest3D 实例" % room.room_id)
		_finish()
		return
	print(
		"目标箱：%s quality=%s 拟态=%s drop_count=%d fate=%d"
		% [
			chest.chest_id, chest.quality, str(chest.mimic),
			chest.drop_count, chest.fate_card_per_open,
		]
	)
	# ⚠ **本探针只测「普通箱」的掉落分支**，拟态箱开箱是不掉东西的（物资在怪肚子里）。
	# 每箱有 20% 是拟态，若不在这里清掉标记，这条断言会随种子随机红/绿 ——
	# 那是探针里最坏的一种失败：同一个命令跑两次结论不同。
	# 拟态全链路（现形 / 刷怪 / 击杀掉回 / 不算清房）在 `_egt_mimic_chest_probe` 单独验。
	chest.mimic = false

	# —— ③ 本关没有钥匙经济（业主 2026-11-05「远征03 的钥匙掉落全部去掉」）——
	_check(not tower._room_key_economy_enabled(), "远征03 仍开着房间钥匙经济（业主：钥匙全退役）")
	_check(
		tower._room_key_count == 0,
		"远征03 开局仍发初始钥匙（actual=%d）" % tower._room_key_count
	)
	await _enter_room(tower, room)
	chest._player_in_range = true
	var loot_before := _count_ground_loot()
	var cards_before := _fate_card_count()

	# —— ② 免钥匙直开：按下 E 的当帧只「认领 + 起手」，不许已经开完 ——
	#
	# 业主 2026-11-05：「点击之后宝箱会抖两下，然后箱子砰的一下打开，然后才会弹出
	# 命运卡界面。整个过程中需要有前置和后置，不要突然打开完全没有过渡。」
	# 这一段的断言就是那句话的可执行版本：
	#   T+0            已认领（记账）、动画在抖动段、**还没有掉落、没有弹窗**
	#   T+burst-0.06   仍在抖动/蓄力、仍然没有掉落
	#   T+burst+0.06   掉落在「砰」之后出现，但弹窗还没来（后置留白）
	#   T+burst+0.40   弹窗才出现
	tower._on_chest_open_requested(room, chest)
	var burst_delay := chest.get_open_burst_delay()
	print(
		"  按下 E：opened=%s phase=%s 掉落 +%d 弹窗=%s"
		% [
			str(chest.is_opened()), chest.get_chest_snapshot().get("open_phase_name", "?"),
			_count_ground_loot() - loot_before, str(tower._door_fate_active),
		]
	)
	_check(chest.is_opened(), "直接开箱却没认领（业主：开启方式是直接开启，不需要使用钥匙）")
	_check(
		tower._get_total_room_keys() == 0,
		"开箱消耗了钥匙（本关钥匙已退役，不该有任何扣减）"
	)
	_check(
		chest.get_open_phase() != TreasureChest3D.OpenPhase.OPENED,
		"按下 E 的当帧箱子就已经开完了 —— 没有前置动画（业主：不要突然打开）"
	)
	_check(
		_count_ground_loot() == loot_before,
		"按下 E 的当帧物资就已经落地（应该等「砰」）"
	)
	_check(not tower._door_fate_active, "按下 E 的当帧就弹了购买界面（应该等开箱动画走完）")

	# 砰之前的 60ms：仍在过渡里，掉落不能出现。
	await _wait(maxf(0.0, burst_delay - 0.06))
	_check(
		_count_ground_loot() == loot_before,
		"「砰」之前物资就落地了（掉落必须对齐爆点，否则会看到东西从关着的箱子里冒出来）"
	)
	var mid_phase := chest.get_open_phase()
	_check(
		mid_phase == TreasureChest3D.OpenPhase.SHAKING
			or mid_phase == TreasureChest3D.OpenPhase.CHARGING,
		"「砰」之前动画阶段是 %s，期望 SHAKING / CHARGING"
			% chest.get_chest_snapshot().get("open_phase_name", "?")
	)

	# 砰之后：物资落地，但弹窗还在「后置留白」里没出现。
	await _wait(0.12)
	var loot_at_burst := _count_ground_loot() - loot_before
	print("  「砰」之后：掉落 +%d 件，弹窗=%s" % [loot_at_burst, str(tower._door_fate_active)])
	_check(loot_at_burst >= 1, "「砰」之后没有掉出任何物资")
	_check(
		loot_at_burst == chest.drop_count,
		"开箱掉出 %d 件，配置是 %d 件" % [loot_at_burst, chest.drop_count]
	)
	_check(
		not tower._door_fate_active,
		"「砰」之后立刻弹了购买界面 —— 掉落物没有露过面（后置过渡缺失）"
	)
	# 「砰」的触觉不能只有音效：音效在静音/戴耳机分神时完全失效，
	# 而箱子本体又小、在屏幕角落 —— 镜头这一下是兜底的物理反馈。
	# 时长按 `BURST_SECONDS`（0.14s）给，所以只在这一小段里断言得到，
	# 检查点刚好在 0.12s，再晚就自然衰减为零了（那时断言会假红）。
	if tower.player != null and is_instance_valid(tower.player):
		_check(
			tower.player.camera_feedback._shake_amplitude > 0.0,
			"「砰」没有触发镜头冲击（玩家可能根本没感觉到箱子爆开）"
		)

	# 后置留白结束：弹窗出现。
	await _wait(CHEST_OVERLAY_WAIT_SEC)
	var cards_gained := _fate_card_count() - cards_before
	print(
		"  开箱结果：掉落 +%d 件，免费命运卡 +%d 张，购买弹窗=%s，status=%s"
		% [
			_count_ground_loot() - loot_before, cards_gained,
			str(tower._door_fate_active), tower.status_label.text,
		]
	)
	_check(tower._door_fate_active, "开箱没有弹出命运卡购买界面")
	_check(
		tower._fate_overlay != null and is_instance_valid(tower._fate_overlay),
		"命运卡购买界面没有挂到 HUD 上"
	)
	_check(
		tower._door_fate_choices.size() == 3,
		"购买界面不是三选一（actual=%d）" % tower._door_fate_choices.size()
	)
	_check(
		cards_gained == 0,
		"开箱仍自动发卡 +%d 张（新口径：命运卡一律走购买，不再白送）" % cards_gained
	)

	# 动画收尾：阶段必须落到 OPENED（否则「余韵」永远播不完，探针也测不到终态）。
	await _wait(TreasureChest3D.SETTLE_SECONDS + 0.15)
	_check(
		chest.is_open_animation_done(),
		"开箱动画没有收尾（phase=%s）" % chest.get_chest_snapshot().get("open_phase_name", "?")
	)
	# 钥匙退役后，「太阳钥印（获得房间钥匙）」这类卡在本关是**付钱买空气**：
	# 必须整张不进报价池。单次抽 3 张有 3/21 概率撞不到它，所以扫 40 个报价序号 ——
	# 若过滤器没生效，它几乎必然在某一轮里出现（探针跑两次结论不同的坑见文件头）。
	var banned_offers := 0
	var original_offer_id: int = int(tower._fate_door_offer_id)
	for offer_index in range(40):
		tower._fate_door_offer_id = original_offer_id + offer_index
		for offered in tower._gate_expedition_fate_offer():
			if tower._card_grants_room_key(offered):
				banned_offers += 1
	tower._fate_door_offer_id = original_offer_id
	_check(
		banned_offers == 0,
		"本关仍报价「获得房间钥匙」空卡 %d 次（40 轮报价）" % banned_offers
	)

	# —— ④ 重复开箱不得再给东西、也不得再弹一次界面 ——
	var loot_after_first := _count_ground_loot()
	var cards_after_first := _fate_card_count()
	tower._on_chest_open_requested(room, chest)
	await get_tree().process_frame
	_check(
		_count_ground_loot() == loot_after_first,
		"重复开箱又掉了一次物资（%d → %d）" % [loot_after_first, _count_ground_loot()]
	)
	_check(
		_fate_card_count() == cards_after_first,
		"重复开箱又发了一张命运卡（%d → %d）" % [cards_after_first, _fate_card_count()]
	)
	_check(chest.get_interaction_candidate(tower.player).is_empty(), "已开的箱子仍然可交互")
	print("  重复开箱：无新增掉落、无新增命运卡 ✓")

	# 收尾：退掉购买弹窗，确认它不会把输入锁留在场上。
	tower._close_door_fate_overlay()
	await get_tree().process_frame
	_check(not tower._door_fate_active, "退出购买界面后 `_door_fate_active` 仍为 true（玩家会一直被锁输入）")

	# —— ⑦ 走**真实交互链路**再开一只（第二间宝箱房）——
	#
	# 上面所有断言都是直接 `tower._on_chest_open_requested(room, chest)`，
	# 而正式玩法是 `chest.perform_interaction()` → `open_requested` → 房间转发 → Dungeon3D。
	# 这条链上多了一个「信号回调里 `await`」的形态：Godot 不 await 信号返回值，
	# 协程能不能活到 `create_timer` 回调取决于引擎是否持有它的引用。
	# 这不是理论问题 —— 写成 `await` 后如果状态被回收，表现就是「箱子抖了、然后什么都不发生」。
	if chest_rooms.size() > 1:
		var second_room := chest_rooms[1]
		await _enter_room(tower, second_room)
		var second_list := second_room.get_treasure_chests()
		if second_list.is_empty():
			_check(false, "%s 没有箱子，无法验证真实交互链路" % second_room.room_id)
		else:
			var second := second_list[0]
			second.mimic = false
			second._player_in_range = true
			var accepted := second.perform_interaction(tower.player, {})
			_check(accepted, "真实交互链路：`perform_interaction()` 拒绝了开箱")
			# 必须等满「砰 + 后置留白 + 弹窗淡入」才断言。只等 0.42s 会得到
			# 「掉落 +0、弹窗没出」的假红 —— 那不是协程被回收，是探针等得太短（本轮踩过一次）。
			await _wait(second.get_open_burst_delay() + CHEST_OVERLAY_WAIT_SEC)
			# 数**本房**的掉落，不用全局组计数：进第二间房时第一间房的 detail 已被卸载，
			# 全局组里的数量会掉下去，净变化恒为 0，那样这条断言永远测不出东西。
			var landed := _count_room_loot(second_room)
			_check(
				landed == second.drop_count,
				"真实交互链路（信号 → 协程）没有把 %d 件物资落地（本房 actual=%d）"
				% [second.drop_count, landed]
			)
			_check(
				tower._door_fate_active,
				"真实交互链路下没有弹出购买界面（`await` 的状态可能被回收了）"
			)
			tower._close_door_fate_overlay()
			await get_tree().process_frame
			print(
				"  真实交互链路（perform_interaction → 信号 → 协程）：本房掉落 %d 件、弹窗已出 ✓"
				% landed
			)

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print(
			"EGT_CHEST_PROBE_OK 宝箱房：有箱 / 免钥匙直开 / 前置抖动+砰+后置余韵 / 掉落晚于砰 / "
			+ "弹命运卡购买 / 不自动发卡 / 不可重复开 / 真实交互链路可用"
		)
		get_tree().quit(0)
		return
	print("EGT_CHEST_PROBE_FAIL count=%d" % failures.size())
	for message in failures:
		print("  - %s" % message)
	get_tree().quit(1)


func _enter_room(tower: TowerDescent3D, room: DungeonRoom3D) -> void:
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(room.room_id)
	for _frame in 4:
		await get_tree().process_frame


## 把玩家钥匙清到 0。三个来源都要清：`_room_key_count`（开局赠送）、
## `_temporary_room_keys`（临时钥匙）、背包里的 `item_room_key`。
## 2026-11-05 起本关钥匙经济已退役，探针不再需要「造出无钥匙状态」，
## 但清空工具保留给将来的钥匙关卡复用（直接调 `_strip_room_keys`）。
func _strip_room_keys(tower: TowerDescent3D) -> void:
	tower._room_key_count = 0
	tower._temporary_room_keys = 0
	if tower._inventory != null:
		var held := tower._inventory.get_item_count("item_room_key")
		if held > 0:
			tower._inventory.consume_item("item_room_key", held)


func _room_key_total(tower: TowerDescent3D) -> int:
	return tower._get_total_room_keys()


func _count_ground_loot() -> int:
	return get_tree().get_nodes_in_group("ground_loot_3d").size()


## 只数某一间房里的地面掉落。跨房断言必须用它 —— 进房会卸载上一间房的 detail，
## 全局组计数会跟着掉下去，净变化永远算不准。
func _count_room_loot(room: DungeonRoom3D) -> int:
	var total := 0
	for node in room.find_children("*", "", true, false):
		if node is GroundLootPickup3D and not node.is_queued_for_deletion():
			total += 1
	return total


func _fate_card_count() -> int:
	var bridge := get_node_or_null(FATE_BRIDGE_PATH)
	if bridge == null:
		return 0
	var cards: Variant = bridge.call("get_cards")
	return (cards as Array).size() if cards is Array else 0
