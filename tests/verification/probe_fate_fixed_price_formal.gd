extends Node

## 聚焦补验（2026-11-20）：正式远征拾取入口的**固定售价**契约。
##
## 与 `verify_fate_level01_pool` 的区别（上一轮的验收缺口）：
## - 上一轮只改 `_fate_door_offer_id` / `_fate_offer_price_index` 两个序号，**没有真的换 run_seed**，
##   也没有走正式建单（`_show_door_fate_choices`），因此不能作为「跨种子同价」的证据。
## - 本探针每个用例都新建一个**新 run_seed** 的远征实例，从**不同真实来源房**生成
##   `item_fate_card_drop` 凭据并走 `perform_interaction()` → `_show_door_fate_choices()` 正式建单，
##   不预填 `_fate_door_quote`，靠生产路径自己报价。
##
## 覆盖：
## A. 三个不同 run_seed × 三个不同来源房，同一稳定卡 / 同稀有度报价必须同值且等于表价；
## B. 至少一笔完整成交：显示报价 == 实扣 == 发卡后槽位变化；
## C. 余额不足：不降价、不扣款、不发卡、弹层不关。
##
## 不做：不跑赏金击杀长段（上一轮在该段卡死），不改任何生产代码。

# 运行时 load，不用 preload：解析期拉整条远征场景依赖链会让脚本迟迟不 ready。
const EXPEDITION_PATH := "res://scenes/ExpeditionLevel01_3D.tscn"
const FATE_PICKUP_PATH := "res://src/world3d/FateCardDropPickup3D.gd"

## 三个互不相同的种子 + 三个不同的真实来源房。
const SEEDS: Array[int] = [515151, 770032, 421001]
const SOURCE_ROOMS: Array[String] = ["room_01", "room_02", "room_03"]

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	print("PROBE_READY t=%d" % Time.get_ticks_msec())
	call_deferred("run")


func run() -> void:
	print("PROBE_RUN_ENTER t=%d" % Time.get_ticks_msec())
	var deadline := Time.get_ticks_msec() + 240000
	var samples: Dictionary = {}
	for seed_index in range(SEEDS.size()):
		var seed_value: int = SEEDS[seed_index]
		var room_id: String = SOURCE_ROOMS[seed_index]
		if Time.get_ticks_msec() > deadline:
			failures.append("超时：未能在 240s 内跑完种子 %d" % seed_value)
			break
		var outcome: Dictionary = await _sample_seed(seed_value, room_id)
		for row_value in outcome.get("rows", []) as Array:
			var row: Dictionary = row_value as Dictionary
			var key := str(row.get("rarity", -1))
			samples[key] = samples.get(key, [])
			(samples[key] as Array).append(row)
			print("PRICE_SAMPLE seed=%d room=%s card=%s rarity=%d quoted=%d shown=%s" % [
				seed_value, room_id, str(row.get("card", "")), int(row.get("rarity", -1)),
				int(row.get("quoted", -1)), str(row.get("shown", "")),
			])
		if not bool(outcome.get("ok", false)):
			failures.append("种子 %d / %s 未能建立正式报价：%s" % [seed_value, room_id, str(outcome.get("reason", ""))])

	# A. 同稀有度跨种子/跨来源房必须同价。
	for rarity_value in samples.keys():
		var rows: Array = samples[rarity_value] as Array
		if rows.is_empty():
			continue
		var first := int((rows[0] as Dictionary).get("quoted", -1))
		for row_value in rows:
			var row: Dictionary = row_value as Dictionary
			var quoted := int(row.get("quoted", -1))
			_expect(quoted == first, "稀有度%s 跨种子/来源房价格漂移：%d != %d（seed=%d room=%s）" % [
				str(rarity_value), quoted, first, int(row.get("seed", 0)), str(row.get("room", "")),
			])
		_expect(first == int(Dungeon3D.FATE_PRICE_BY_RARITY[clampi(int(rarity_value), 0, 4)]),
			"稀有度%s 报价不等于固定表价：%d" % [str(rarity_value), first])
		print("PRICE_STABLE rarity=%s samples=%d value=%d" % [str(rarity_value), rows.size(), first])

	# B/C 在第一个种子里完成，避免重复起场景。
	await _check_purchase_and_shortage(SEEDS[0], SOURCE_ROOMS[0])

	for failure in failures:
		push_error(failure)
	print("FATE_FIXED_PRICE_FORMAL_%s checks=%d failures=%d" % [
		"OK" if failures.is_empty() else "FAILED", checks, failures.size(),
	])
	get_tree().quit(0 if failures.is_empty() else 1)


## 用指定种子起远征，进指定真实房间，生成正式凭据并交互建单；不改任何报价字段。
func _sample_seed(seed_value: int, room_id: String) -> Dictionary:
	var dungeon := await _spawn(seed_value)
	if dungeon == null:
		return {"ok": false, "reason": "场景未起来"}
	print("PROBE_STEP enter_begin room=%s t=%d" % [room_id, Time.get_ticks_msec()])
	var entered := await _enter_room(dungeon, room_id)
	print("PROBE_STEP enter_done room=%s ok=%s t=%d" % [room_id, str(entered), Time.get_ticks_msec()])
	if not entered:
		dungeon.queue_free()
		return {"ok": false, "reason": "无法进入真实来源房 %s" % room_id}
	print("PROBE_STEP offer_begin room=%s t=%d" % [room_id, Time.get_ticks_msec()])
	var opened := await _open_formal_offer(dungeon, room_id, "probe:%d:%s" % [seed_value, room_id])
	print("PROBE_STEP offer_done room=%s ok=%s t=%d" % [room_id, str(opened), Time.get_ticks_msec()])
	if not opened:
		dungeon.queue_free()
		return {"ok": false, "reason": "正式凭据交互未建立报价"}
	var rows: Array = []
	for card_value in dungeon.get("_door_fate_choices") as Array:
		var card := card_value as FateCard
		if card == null:
			continue
		var quoted := int(dungeon.call("_fate_price", card))
		var shown := _price_row_text(dungeon, int(dungeon.get("_door_fate_choices").find(card)))
		rows.append({
			"card": card.get_stable_card_id(),
			"rarity": int(card.card_rarity),
			"quoted": quoted,
			"shown": shown,
			"seed": seed_value,
			"room": room_id,
		})
	dungeon.call("_close_door_fate_overlay")
	dungeon.queue_free()
	await get_tree().process_frame
	return {"ok": not rows.is_empty(), "rows": rows}


func _spawn(seed_value: int) -> Node:
	print("PROBE_STEP spawn_begin seed=%d t=%d" % [seed_value, Time.get_ticks_msec()])
	var packed := load(EXPEDITION_PATH) as PackedScene
	print("PROBE_STEP scene_loaded seed=%d t=%d ok=%s" % [seed_value, Time.get_ticks_msec(), str(packed != null)])
	var dungeon := packed.instantiate() as Dungeon3D
	print("PROBE_STEP instantiated seed=%d t=%d" % [seed_value, Time.get_ticks_msec()])
	dungeon.test_mode = true
	dungeon.run_seed_override = seed_value
	add_child(dungeon)
	print("PROBE_STEP added seed=%d t=%d" % [seed_value, Time.get_ticks_msec()])
	for _frame in 10:
		await get_tree().process_frame
	print("PROBE_STEP spawn_done seed=%d t=%d player=%s" % [seed_value, Time.get_ticks_msec(), str(dungeon.player != null)])
	if dungeon.player == null:
		return null
	dungeon.player.set_physics_process(false)
	dungeon.player.set_process(false)
	return dungeon


func _enter_room(dungeon: Dungeon3D, room_id: String) -> bool:
	var rooms := dungeon.get("_room_by_id") as Dictionary
	var room := rooms.get(room_id) as DungeonRoom3D
	if room == null:
		return false
	dungeon.player.global_position = room.global_position + Vector3.UP * 0.1
	dungeon.force_enter_room_for_test(room_id)
	for _frame in 3:
		await get_tree().process_frame
	return str(dungeon.get("_current_room_id")) == room_id


## 走正式凭据：真实房间挂 `item_fate_card_drop`，用 perform_interaction 触发建单。
func _open_formal_offer(dungeon: Dungeon3D, room_id: String, pickup_id: String) -> bool:
	var rooms := dungeon.get("_room_by_id") as Dictionary
	var room := rooms.get(room_id) as DungeonRoom3D
	if room == null:
		return false
	var pickup := (load(FATE_PICKUP_PATH) as GDScript).new() as FateCardDropPickup3D
	pickup.interaction_handler = Callable(dungeon, "_on_fate_pickup_interacted")
	pickup.configure({
		"type": "fate_pickup",
		"id": "item_fate_card_drop",
		"name": "命运卡",
		"fate_pickup_id": pickup_id,
		"fate_source": "verification",
		"source_room_id": room.room_id,
		"source_chest_id": "probe_chest",
	}, Color(0.72, 0.34, 1.0))
	room.add_child(pickup)
	pickup.global_position = dungeon.player.global_position
	for _frame in 2:
		await get_tree().process_frame
	var candidate := pickup.get_interaction_candidate(dungeon.player)
	if candidate.is_empty():
		return false
	if not pickup.perform_interaction(dungeon.player, candidate):
		return false
	for _frame in 3:
		await get_tree().process_frame
	return bool(dungeon.get("_door_fate_active"))


## 显示文本：从真实按钮的价签读，和玩家看到的一致。
func _price_row_text(dungeon: Dungeon3D, index: int) -> String:
	var button := dungeon.call("_fate_choice_button", index) as Button
	if button == null or not button.has_meta("tarot_price_label"):
		return "<no-label>"
	var label := button.get_meta("tarot_price_label") as Label
	return label.text if label != null else "<null>"


## B：一笔完整成交 —— 显示 == 实扣 == 发卡；C：余额不足 —— 不降价/不扣款/不发卡。
func _check_purchase_and_shortage(seed_value: int, room_id: String) -> void:
	var dungeon := await _spawn(seed_value)
	if dungeon == null:
		failures.append("成交验收：场景未起来")
		return
	if not await _enter_room(dungeon, room_id):
		failures.append("成交验收：无法进入 %s" % room_id)
		dungeon.queue_free()
		return
	var instance: Variant = dungeon.player.get_equipped_weapon_instance()
	if instance == null:
		failures.append("成交验收：玩家没有武器实例")
		dungeon.queue_free()
		return
	(instance.fate_upgrades as Array).clear()
	if not await _open_formal_offer(dungeon, room_id, "probe:trade:%d" % seed_value):
		failures.append("成交验收：正式凭据未建立报价")
		dungeon.queue_free()
		return
	var choices: Array = (dungeon.get("_door_fate_choices") as Array).duplicate()
	_expect(choices.size() == 3, "正式入口不是三张候选（%d）" % choices.size())

	# 先找一张 WEAPON 卡做完整成交（要经过不可逆确认），没有就退而取第一张非武器卡。
	var weapon_index := -1
	for index in range(choices.size()):
		var card := choices[index] as FateCard
		if card.scope == FateCard.Scope.WEAPON:
			weapon_index = index
			break
	var target_index := weapon_index if weapon_index >= 0 else 0
	var target := choices[target_index] as FateCard
	var quoted := int(dungeon.call("_fate_price", target))
	var shown_text := _price_row_text(dungeon, target_index)
	_expect(shown_text.contains(str(quoted)), "显示价不含固定价：'%s' vs %d" % [shown_text, quoted])
	_expect(quoted == int(Dungeon3D.FATE_PRICE_BY_RARITY[clampi(int(target.card_rarity), 0, 4)]),
		"成交卡报价不等于固定表价：%d" % quoted)

	var upgrades_before: int = int((instance.fate_upgrades as Array).size())
	GameManager.currency = quoted + 500
	var wallet_before := GameManager.currency
	var consumed := await _purchase(dungeon, target_index)
	var wallet_after := GameManager.currency
	if bool(consumed.get("success", false)):
		_expect(wallet_before - wallet_after == quoted, "实扣不等于显示价：扣了 %d，显示 %d" % [wallet_before - wallet_after, quoted])
		var upgrades_after: int = int((instance.fate_upgrades as Array).size())
		if target.scope == FateCard.Scope.WEAPON:
			_expect(upgrades_after == upgrades_before + 1, "武器卡未真正刻入命运槽（%d→%d）" % [upgrades_before, upgrades_after])
		else:
			_expect(upgrades_after == upgrades_before, "非武器卡不应占用枪槽（%d→%d）" % [upgrades_before, upgrades_after])
		_expect(str(consumed.get("code", "")) == "committed" or bool(consumed.get("success", false)), "成交返回码异常：%s" % str(consumed.get("code", "")))
		print("TRADE_OK card=%s rarity=%d quoted=%d deducted=%d slot_before=%d slot_after=%d" % [
			target.get_stable_card_id(), int(target.card_rarity), quoted, wallet_before - wallet_after, upgrades_before, upgrades_after,
		])
	else:
		# 应用失败也必须原额退款，不能把「没发卡」当成成交。
		_expect(wallet_after == wallet_before, "成交失败未原额退款：%d→%d" % [wallet_before, wallet_after])
		print("TRADE_NOT_COMMITTED card=%s reason=%s refunded=%s" % [
			target.get_stable_card_id(), str(consumed.get("message", consumed.get("code", ""))), str(wallet_after == wallet_before),
		])
	dungeon.call("_close_door_fate_overlay")
	await get_tree().process_frame

	# C. 余额不足：重开一单，钱包置 0，必须不降价、不扣款、不发卡。
	if not await _open_formal_offer(dungeon, room_id, "probe:short:%d" % seed_value):
		failures.append("余额验收：正式凭据未建立报价")
		dungeon.queue_free()
		return
	var short_choices: Array = dungeon.get("_door_fate_choices") as Array
	var short_index := 0
	var short_card := short_choices[short_index] as FateCard
	var short_quoted := int(dungeon.call("_fate_price", short_card))
	GameManager.currency = 0
	dungeon.call("_refresh_door_fate_prices")
	var short_shown := _price_row_text(dungeon, short_index)
	_expect(int(dungeon.call("_fate_price", short_card)) == short_quoted, "空钱包把报价改了：%d→%d" % [short_quoted, int(dungeon.call("_fate_price", short_card))])
	_expect(short_quoted == int(Dungeon3D.FATE_PRICE_BY_RARITY[clampi(int(short_card.card_rarity), 0, 4)]), "空钱包后报价不等于固定表价")
	_expect(str(dungeon.call("_fate_card_block_reason", short_index)) == "insufficient", "空钱包未判为余额不足")
	var short_slots_before: int = int((instance.fate_upgrades as Array).size())
	await _purchase(dungeon, short_index)
	_expect(GameManager.currency == 0, "余额不足仍扣款：余额 %d" % GameManager.currency)
	_expect(int((instance.fate_upgrades as Array).size()) == short_slots_before, "余额不足仍发卡")
	_expect(bool(dungeon.get("_door_fate_active")), "余额不足关闭了购卡层")
	print("SHORTAGE_OK card=%s rarity=%d quoted=%d shown='%s' wallet=%d slots=%d active=%s" % [
		short_card.get_stable_card_id(), int(short_card.card_rarity), short_quoted, short_shown,
		GameManager.currency, int((instance.fate_upgrades as Array).size()), str(dungeon.get("_door_fate_active")),
	])
	dungeon.call("_close_door_fate_overlay")
	await get_tree().process_frame
	dungeon.queue_free()
	await get_tree().process_frame


## 走正式购买入口；武器卡会自动应答不可逆确认的「是」。
func _purchase(dungeon: Dungeon3D, index: int) -> Dictionary:
	# `_on_door_fate_selected` 是协程：Godot 4 里 call() 会跑到第一个 await 就返回，
	# 所以这里按状态轮询，而不是 await 返回值。
	dungeon.call("_on_door_fate_selected", index)
	var deadline := Time.get_ticks_msec() + 8000
	var answered := false
	while is_instance_valid(dungeon) and Time.get_ticks_msec() < deadline:
		var confirm := dungeon.get("_fate_confirm") as Control
		if confirm != null and not answered:
			for node in confirm.find_children("*", "Button", true, false):
				if (node as Button).text == "是":
					(node as Button).pressed.emit()
					answered = true
					break
		if not bool(dungeon.get("_fate_purchase_busy")):
			break
		await get_tree().process_frame
	var purchased: Array = dungeon.get("_door_fate_purchased") as Array
	var success := index < purchased.size() and bool(purchased[index])
	return {
		"success": success,
		"code": "committed" if success else "not_committed",
		"message": str(dungeon.get("status_label").text) if dungeon.get("status_label") != null else "",
	}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)
