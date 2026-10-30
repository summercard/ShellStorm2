extends Node
## 远征03 商店房实测探针（2026-10-30）。
##
## 验的是业主那句「商人房间是否建立了」。这个问题的答案**不能靠读配置**：
## 每张 flow 骨架里都有 1 个 `SHOP` 节点，但生成期它被映射成什么 `room_type`、
## 运行时服务点有没有真的建出来、交互后 UI 能不能开、买了东西金币扣不扣得掉，
## 这四步任何一步断掉，症状都是"房间在、能进去、里面什么都没有"，且**没有任何报错**。
##
## 五条判据：
##   ① 每张 flow 至少有 1 间 `room_type == MERCHANT` 的房；
##   ② 进房后 `get_service_station("merchant")` 非空（服务点真的建出来了）；
##   ③ 商店房是和平区：无刷怪盒、无宝箱；
##   ④ 交互后商人 UI 出现且货架非空；
##   ⑤ 买得动：给足金币后购买成功、金币扣掉、货架少一件。
##
## 用法：godot --headless --path . --scene res://tools/_egt_merchant_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
## 换几个种子跑：EGT 骨架每局抽一张，不同骨架的 SHOP 房尺寸/位置不同。
const SEEDS := [77003244, 1, 42]

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _ready() -> void:
	print("=== EGT_MERCHANT_PROBE ===")
	for seed_value in SEEDS:
		await _probe_seed(seed_value)
	_finish()


func _probe_seed(seed_value: int) -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		_check(false, "场景不是 TowerDescent3D")
		return
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	# —— ① MERCHANT 房存在 ——
	var merchant_rooms: Array[DungeonRoom3D] = []
	for room in tower._rooms:
		var candidate := room as DungeonRoom3D
		if candidate != null and candidate.room_type == "MERCHANT":
			merchant_rooms.append(candidate)
	print("\n[seed %d] MERCHANT 房：%d 间 → %s"
		% [seed_value, merchant_rooms.size(), str(merchant_rooms.map(func(r): return r.room_id))])
	_check(merchant_rooms.is_empty() == false,
		"种子 %d：全层没有 room_type == MERCHANT 的房（SHOP kind 没被映射成 MERCHANT）" % seed_value)
	if merchant_rooms.is_empty():
		tower.queue_free()
		await get_tree().process_frame
		return

	var shop := merchant_rooms[0]
	# —— ③ 和平区判据 ——
	_check((shop.spawn_placements as Array).is_empty(),
		"种子 %d：%s 是商店房却摆了刷怪盒" % [seed_value, shop.room_id])
	_check((shop.chest_placements as Array).is_empty(),
		"种子 %d：%s 是商店房却摆了宝箱" % [seed_value, shop.room_id])

	# —— ② 服务点真的建出来 ——
	await _enter_room(tower, shop)
	var station := shop.get_service_station("merchant")
	print("  %s 服务点存在=%s" % [shop.room_id, str(station != null)])
	_check(station != null,
		"种子 %d：%s 进房后没有 merchant 服务点（_build_detail 的 room_type 判据没命中）"
		% [seed_value, shop.room_id])
	if station == null:
		tower.queue_free()
		await get_tree().process_frame
		return

	# —— ④ 交互 → UI + 货架 ——
	tower._on_service_activated(shop, station)
	await get_tree().process_frame
	await get_tree().process_frame
	var ui_ready := tower._merchant_ui != null and is_instance_valid(tower._merchant_ui)
	_check(ui_ready, "种子 %d：交互后商人 UI 没建出来（status=%s）"
		% [seed_value, tower.status_label.text])
	if not ui_ready:
		tower.queue_free()
		await get_tree().process_frame
		return
	var offers: Array = tower._merchant_service.get_offers_snapshot()
	# ⚠ 价格在 `offer.item.price`，**不在 offer 顶层**。`RunMerchantService.open_session()`
	# 只把 `{offer_id, item}` 放上去，物品本身（含 price）在 `item` 里。
	# 第一版探针读 `offer.price`，六件全是 0，看起来像"商人白送"——那是探针读错了层级。
	var rows: Array[String] = []
	for value in offers:
		var offer_row := value as Dictionary
		var row_item := offer_row.get("item", {}) as Dictionary
		rows.append("%s/%d枚" % [str(row_item.get("id", "?")), int(row_item.get("price", 0))])
	print("  货架 %d 件：%s" % [offers.size(), ", ".join(rows)])
	_check(not offers.is_empty(), "种子 %d：商人货架是空的" % seed_value)
	if offers.is_empty():
		tower.queue_free()
		await get_tree().process_frame
		return

	# —— ⑤ 买得动 ——
	# 挑最便宜的一件：贵的那几件本来就要攒层数，拿它判「买得起」会误报失败。
	var cheapest := 0
	for index in range(offers.size()):
		if _offer_price(offers[index]) < _offer_price(offers[cheapest]):
			cheapest = index
	var offer := offers[cheapest] as Dictionary
	var item := offer.get("item", {}) as Dictionary
	var price := int(item.get("price", 0))
	var offer_id := str(offer.get("offer_id", ""))
	_check(price > 0, "种子 %d：最便宜的商品价格是 %d（<=0 意味着白送）" % [seed_value, price])
	# 给足金币（一层实际约 61 枚，但探针要单独验"购买链路"，不验经济，所以直接给够）。
	GameManager.currency = price + 50
	var currency_before := GameManager.currency
	var offers_before := offers.size()
	tower._on_merchant_purchase_command(
		str(tower._merchant_service.get_session_id()), offer_id,
		str(item.get("weapon_instance_id", ""))
	)
	await get_tree().process_frame
	print("  购买 %s（%d 枚）：%d → %d 枚，货架 %d → %d，status=%s"
		% [str(item.get("name", item.get("id", "?"))), price, currency_before, GameManager.currency,
		   offers_before, tower._merchant_service.get_offers_snapshot().size(), tower.status_label.text])
	_check(GameManager.currency == currency_before - price,
		"种子 %d：购买没有按价扣金币（%d → %d，应扣 %d）"
		% [seed_value, currency_before, GameManager.currency, price])
	_check(tower._merchant_service.get_offers_snapshot().size() == offers_before - 1,
		"种子 %d：买完之后货架没少一件（%d → %d）"
		% [seed_value, offers_before, tower._merchant_service.get_offers_snapshot().size()])

	# —— ⑥ 关店 ——
	tower._on_merchant_closed()
	await get_tree().process_frame
	_check(tower._merchant_ui == null, "种子 %d：关店后 UI 引用没清空" % seed_value)
	print("  关店：UI 引用已清空 ✓")

	tower.queue_free()
	await get_tree().process_frame


func _enter_room(tower: TowerDescent3D, room: DungeonRoom3D) -> void:
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(room.room_id)
	for _frame in 4:
		await get_tree().process_frame


## 货架条目 → 价格。价格在 `item.price`，不在 offer 顶层（见上面的注释）。
func _offer_price(value: Variant) -> int:
	var offer := value as Dictionary
	if offer == null:
		return 0
	return int((offer.get("item", {}) as Dictionary).get("price", 0))


func _finish() -> void:
	# 空字符串判据是 `_check` 的 no-op 占位，这里过滤掉防空报。
	var real: Array[String] = []
	for line in _failures:
		if not line.is_empty():
			real.append(line)
	if real.is_empty():
		print("\nEGT_MERCHANT_PROBE_OK 商店房：MERCHANT 可识别 / 服务点建出 / UI 可开 / 买得动 / 关得掉")
		get_tree().quit(0)
		return
	print("\nEGT_MERCHANT_PROBE_FAIL count=%d" % real.size())
	for line in real:
		print("  - %s" % line)
	get_tree().quit(1)
