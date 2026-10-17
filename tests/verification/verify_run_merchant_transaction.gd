extends Node

const SERVICE := preload("res://src/game/RunMerchantService.gd")

class Wallet:
	extends RefCounted
	var currency := 100
	func spend_currency(amount: int) -> bool:
		if amount < 0 or currency < amount:
			return false
		currency -= amount
		return true
	func add_currency(amount: int) -> void:
		currency += amount

var _failures: Array[String] = []
var _save_ok := true
var _save_calls := 0
var _probe_inventory: InventoryModule
var _probe_service: RunMerchantService
var _probe_wallet: Wallet
var _probe_save_ok := true
var _probe_calls := 0
var _probe_slots: Array[Dictionary] = []
var _probe_offers: Array[Dictionary] = []
var _probe_currency := 0


func _ready() -> void:
	var service := SERVICE.new()
	var wallet := Wallet.new()
	# 8列×2行才容纳4×2武器；8格只有一行，同样不能容纳两格高的大件。
	var inventory := InventoryModule.new(16)
	var weapon := ItemRegistry.get_instance().get_item("weapon_sprinkler")
	weapon["price"] = 40
	var opened := service.open_session("session-1", "room-a", [weapon])
	_check(bool(opened.get("success", false)), "会话必须打开")
	var offer := service.get_offers_snapshot()[0] as Dictionary
	var offer_id := str(offer.get("offer_id", ""))
	var item := offer.get("item", {}) as Dictionary
	var instance_id := str(item.get("weapon_instance_id", ""))
	_check(not instance_id.is_empty(), "货架武器必须有唯一实例")
	var first_price := int(item.get("price", -1))
	service.close_session()
	var reopened_before_buy := service.open_session("session-2", "room-a", [weapon])
	var same_offer := service.get_offers_snapshot()[0] as Dictionary
	_check(bool(reopened_before_buy.get("success", false)) and same_offer == offer, "关窗重开必须保留同一报价、价格和武器实例")
	var command := Callable(self, "_commit")
	_check(_code(service.purchase("session-1", offer_id, instance_id, inventory, wallet, command)) == "session_closed", "旧会话拒绝")
	_check(_code(service.purchase("session-2", "missing", instance_id, inventory, wallet, command)) == "offer_missing", "缺失报价拒绝")
	_check(_code(service.purchase("session-2", offer_id, "wrong", inventory, wallet, command)) == "stale_offer", "武器实例变更拒绝")
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command, Callable(self, "_always_owned"))) == "inventory_rejected", "其他所有权位置已有该实例时拒绝")
	wallet.currency = 20
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "insufficient_currency", "余额不足拒绝")
	wallet.currency = 100
	for index in range(inventory.get_capacity()):
		inventory.add_item({"id": "test_filler_%d" % index, "type": "material"}, 1)
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "inventory_full", "格位满拒绝")
	inventory.clear_all()
	_save_ok = false
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "save_failed", "写盘失败拒绝")
	_check(wallet.currency == 100 and inventory.get_used_slots() == 0 and service.get_offers_snapshot().size() == 1, "写盘失败必须回滚金币、格位与货架")
	_save_ok = true
	var result := service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)
	_check(_code(result) == "committed", "重试必须成交")
	_check(wallet.currency == 100 - first_price and inventory.has_weapon_instance(instance_id) and service.get_offers_snapshot().is_empty(), "成交完整转移同一武器实例")
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "offer_missing", "重复点击不得重复扣款")
	service.close_session()
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "session_closed", "关窗后旧命令无效")
	var reopened := service.open_session("session-3", "room-a", [weapon])
	_check(bool(reopened.get("success", false)), "关窗后必须能够开启新会话")
	_check(service.get_offers_snapshot().is_empty(), "售罄后重开不得重新抽货")
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "session_closed", "重开后旧会话命令仍必须失效")
	var reloaded := SERVICE.new()
	_check(reloaded.restore_stock_snapshot(service.export_stock_snapshot()), "售罄货架快照必须可恢复")
	reloaded.open_session("session-4", "room-a", [weapon])
	_check(reloaded.get_offers_snapshot().is_empty(), "售罄货架跨重载不得重新抽货")
	_check(_save_calls == 2, "只有写盘故障与成功应调用提交回调")
	var stack_inventory := InventoryModule.new(1)
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	potion["price"] = 10
	stack_inventory.add_item(potion, 1)
	var stack_service := SERVICE.new()
	stack_service.open_session("session-stack", "room-stack", [potion])
	var stack_offer := stack_service.get_offers_snapshot()[0] as Dictionary
	var stack_result := stack_service.purchase(
		"session-stack", str(stack_offer.get("offer_id", "")), "",
		stack_inventory, wallet, command
	)
	_check(_code(stack_result) == "committed" and stack_inventory.get_used_slots() == 1 and stack_inventory.get_item_count("item_health_potion") == 2, "满格但已有可用堆叠空间时购买应成功")
	var unbought := SERVICE.new()
	unbought.open_session("session-unbought", "room-b", [weapon])
	var unbought_offer := unbought.get_offers_snapshot()[0] as Dictionary
	var restored := SERVICE.new()
	_check(restored.restore_stock_snapshot(unbought.export_stock_snapshot()), "未成交货架快照必须可恢复")
	restored.open_session("session-restored", "room-b", [weapon])
	_check(restored.get_offers_snapshot()[0] == unbought_offer, "未成交报价与实例跨重载必须完全相同")
	_check(not SERVICE.new().restore_stock_snapshot({"schema": "wrong", "stocks": {}}), "错误库存 schema 必须拒绝")
	_verify_fragmented_purchase_transactions()
	_verify_base_fragmented_purchase_transactions()
	if _failures.is_empty():
		print("RUN_MERCHANT_TRANSACTION_OK: persistent stock, session, instance, balance, capacity, rollback, retry, duplicate and fragmented layout transactions")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _make_fragmented_board(capacity: int, anchors: Array[int]) -> InventoryModule:
	var inventory := InventoryModule.new(capacity)
	for index in anchors.size():
		var filler := {
			"id": "fragment_filler_%d" % index, "type": "material",
			"name": "fragment_%d" % index, "grid_size": [1, 1], "grid_area": 1,
			"stack_max": 1, "grid_rotation": index % 4,
			"fixture_metadata": {"original_anchor": anchors[index], "index": index},
		}
		_check(inventory.put_item_in_empty_slot(anchors[index], filler, 1), "碎片夹具必须放入指定锚点%d" % anchors[index])
	_check(inventory.get_capacity() == capacity and inventory.get_used_area() == anchors.size(), "碎片夹具容量和实际占用面积必须准确")
	return inventory


func _verify_fragmented_purchase_transactions() -> void:
	var rifle := ItemRegistry.get_instance().get_item("weapon_rifle")
	_check(ItemRegistry.grid_size_of(rifle) == Vector2i(4, 2), "碎片购买必须使用真实4x2步枪定义")
	rifle["price"] = 40
	for capacity in [16, 24]:
		var anchors: Array[int] = [3, 7, 11, 15]
		if capacity == 24:
			anchors.append_array([19, 23])
		var inventory := _make_fragmented_board(capacity, anchors)
		var before := inventory.get_slots_snapshot()
		var service := SERVICE.new()
		service.open_session("fragment-session", "fragment-room-%d" % capacity, [rifle])
		var offers_before := service.get_offers_snapshot()
		var stock_before := service.export_stock_snapshot()
		var offer := offers_before[0]
		var item := offer.get("item", {}) as Dictionary
		var instance_id := str(item.get("weapon_instance_id", ""))
		var offer_id := str(offer.get("offer_id", ""))
		_check(not instance_id.is_empty(), "碎片货架武器实例不得为空")
		_check(inventory.get_free_grid_cells() >= 8 and inventory.find_valid_placement(item).is_empty(), "碎片反例必须面积足够但无4x2或旋转放置位置")
		_check(not inventory.can_add_item_exact(item), "原碎片布局的普通预检必须拒绝大件")
		var sorted_control := InventoryModule.new(capacity)
		sorted_control.restore_slots_snapshot(before)
		sorted_control.sort_items()
		_check(sorted_control.get_slots_snapshot() != before and sorted_control.can_add_item_exact(item), "同一批物品整理后必须真实可放入步枪")
		_check(sorted_control.add_item(item, 1) == 1, "整理对照必须真实放入同一武器实例")
		var plan := inventory.plan_purchase_add(item, 1)
		_check(not plan.is_empty() and bool(plan.get("sorted", false)), "碎片购买规划必须走副本整理分支")
		_check(inventory.get_slots_snapshot() == before, "成功规划也不得修改真实碎片布局")
		_check(plan.get("slots", []) == sorted_control.get_slots_snapshot(), "购买规划必须精确等于整理后真实入包对照")
		var wallet := Wallet.new()
		wallet.currency = 39
		_probe_inventory = inventory
		_probe_service = service
		_probe_wallet = wallet
		_probe_calls = 0
		_probe_save_ok = true
		var command := Callable(self, "_commit_fragment_probe")
		var insufficient := service.purchase("fragment-session", offer_id, instance_id, inventory, wallet, command)
		_check(_code(insufficient) == "insufficient_currency", "可整理碎片棋盘的余额不足必须精确拒绝")
		_check(inventory.get_slots_snapshot() == before and wallet.currency == 39, "余额不足不得整理棋盘或改余额")
		_check(service.get_offers_snapshot() == offers_before and service.export_stock_snapshot() == stock_before and _probe_calls == 0, "余额不足不得改货架库存或尝试写盘")
		wallet.currency = 100
		_probe_save_ok = false
		var failed := service.purchase("fragment-session", offer_id, instance_id, inventory, wallet, command)
		_check(_code(failed) == "save_failed" and _probe_calls == 1, "碎片购买必须到达注入写盘失败而非容量拒绝")
		_check(_probe_slots == plan.get("slots", []) and _probe_slots != before, "故障回调必须观察到已整理且已转入武器的精确布局")
		_check(_probe_currency == 60 and _probe_offers.is_empty(), "写盘失败注入时必须已扣准确金额并移除报价")
		_check(inventory.get_slots_snapshot() == before and inventory.get_capacity() == capacity, "写盘失败必须精确恢复空格、锚点、旋转、完整物品元数据和容量")
		_check(wallet.currency == 100 and service.get_offers_snapshot() == offers_before and service.export_stock_snapshot() == stock_before, "写盘失败必须精确回滚余额、报价和持久化库存")
		_check(not inventory.has_weapon_instance(instance_id), "失败回滚不得残留购买武器实例")
		_probe_save_ok = true
		var committed := service.purchase("fragment-session", offer_id, instance_id, inventory, wallet, command)
		_check(_code(committed) == "committed" and _probe_calls == 2, "同一碎片报价失败后重试必须成交")
		_check(wallet.currency == 60 and inventory.get_slots_snapshot() == plan.get("slots", []), "成交必须按40准确扣款并采用完整规划布局")
		_check(str(committed.get("weapon_instance_id", "")) == instance_id and committed.get("item", {}) == item, "成交返回值必须保留原报价的同一武器实例和全部元数据")
		var weapon_slot := inventory.find_weapon_instance_slot(instance_id)
		var stored := inventory.get_slot(weapon_slot)
		var expected_item := item.duplicate(true)
		expected_item["grid_rotation"] = int(stored.get("grid_rotation", 0))
		_check(weapon_slot >= 0 and int(stored.get("count", 0)) == 1 and stored.get("item", {}) == expected_item, "棋盘必须只收到同一武器实例一件且保留完整内容")
		_check(inventory.get_used_area() == anchors.size() + 8 and service.get_offers_snapshot().is_empty(), "成交后的真实占用面积和售罄状态必须正确")
		var committed_slots := inventory.get_slots_snapshot()
		_check(_code(service.purchase("fragment-session", offer_id, instance_id, inventory, wallet, command)) == "offer_missing", "碎片成交后重复点击必须拒绝")
		_check(wallet.currency == 60 and inventory.get_slots_snapshot() == committed_slots and _probe_calls == 2, "重复点击不得二次扣款、改布局或写盘")
		print("FRAGMENT_PURCHASE_CHECKED capacity=%d save_calls=%d" % [capacity, _probe_calls])
	var full := _make_fragmented_board(16, [1, 3, 5, 7, 9, 11, 13, 14, 15])
	var full_before := full.get_slots_snapshot()
	var full_service := SERVICE.new()
	full_service.open_session("full-session", "fragment-full", [rifle])
	var full_offers := full_service.get_offers_snapshot()
	var full_stock := full_service.export_stock_snapshot()
	var full_item := full_offers[0].get("item", {}) as Dictionary
	var full_wallet := Wallet.new()
	_probe_calls = 0
	_check(full.get_free_grid_cells() == 7 and full.plan_purchase_add(full_item, 1).is_empty(), "容量不足反例必须是7空格不能放8格武器")
	_check(full.get_slots_snapshot() == full_before, "失败购买规划不得整理真实棋盘")
	var full_result := full_service.purchase("full-session", str(full_offers[0].get("offer_id", "")), str(full_item.get("weapon_instance_id", "")), full, full_wallet, Callable(self, "_commit_fragment_probe"))
	_check(_code(full_result) == "inventory_full", "容量不足必须精确返回inventory_full")
	_check(full.get_slots_snapshot() == full_before and full_wallet.currency == 100, "容量不足不得改任何格位或余额")
	_check(full_service.get_offers_snapshot() == full_offers and full_service.export_stock_snapshot() == full_stock and _probe_calls == 0, "容量不足不得改货架库存或写盘")
	_probe_inventory = null
	_probe_service = null
	_probe_wallet = null


func _commit_fragment_probe() -> bool:
	_probe_calls += 1
	_probe_slots = _probe_inventory.get_slots_snapshot()
	_probe_offers = _probe_service.get_offers_snapshot()
	_probe_currency = _probe_wallet.currency
	return _probe_save_ok


func _verify_base_fragmented_purchase_transactions() -> void:
	var manager := preload("res://src/base/BaseManager.gd").new()
	manager.save_path = "user://base_fragment_purchase_probe.json"
	manager.data = BaseData.new()
	var rifle := ItemRegistry.get_instance().get_item("weapon_rifle")
	var price := int(rifle.get("base_buy_price", 0))
	_check(price > 0 and ItemRegistry.grid_size_of(rifle) == Vector2i(4, 2), "基地碎片购买必须使用真实上架步枪及正数购买价")
	var inventory := _make_fragmented_board(16, [3, 7, 11, 15])
	var before := inventory.get_slots_snapshot()
	_check(inventory.find_valid_placement(rifle).is_empty(), "基地碎片反例必须没有直接放置位置")
	manager.data.extraction_points = price - 1
	var data_before := manager.data._to_dict().duplicate(true)
	var insufficient := manager.purchase_base_shop_item_to_inventory("weapon_rifle", inventory, "base_fragment_insufficient")
	_check(not bool(insufficient.get("success", false)) and str(insufficient.get("reason", "")) == "金币不足", "基地余额不足必须精确拒绝")
	_check(inventory.get_slots_snapshot() == before and manager.data._to_dict() == data_before, "基地余额不足不得改布局、余额或交易记录")
	manager.data.extraction_points = price + 100
	data_before = manager.data._to_dict().duplicate(true)
	manager.force_save_failure_for_test = true
	var failed := manager.purchase_base_shop_item_to_inventory("weapon_rifle", inventory, "base_fragment_retry")
	_check(not bool(failed.get("success", false)) and str(failed.get("reason", "")) == "存档失败，购买已回滚", "基地碎片购买必须进入写盘故障分支")
	_check(inventory.get_slots_snapshot() == before and inventory.get_capacity() == 16 and manager.data._to_dict() == data_before, "基地写盘失败必须精确回滚布局及完整BaseData")
	manager.force_save_failure_for_test = false
	var committed := manager.purchase_base_shop_item_to_inventory("weapon_rifle", inventory, "base_fragment_retry")
	var purchased := committed.get("item", {}) as Dictionary
	var instance_id := str(purchased.get("weapon_instance_id", ""))
	_check(bool(committed.get("success", false)) and not instance_id.is_empty(), "基地相同事务失败后必须能购买同一实例")
	var control := InventoryModule.new(16)
	control.restore_slots_snapshot(before)
	control.sort_items()
	_check(control.add_item(purchased, 1) == 1 and inventory.get_slots_snapshot() == control.get_slots_snapshot(), "基地购买必须精确采用整理后同一武器入包布局")
	_check(int(committed.get("price", -1)) == price and manager.data.extraction_points == 100 and inventory.has_weapon_instance(instance_id), "基地购买金额与转入武器实例必须准确")
	var committed_slots := inventory.get_slots_snapshot()
	var committed_data := manager.data._to_dict().duplicate(true)
	var duplicate := manager.purchase_base_shop_item_to_inventory("weapon_rifle", inventory, "base_fragment_retry")
	_check(bool(duplicate.get("duplicate", false)) and inventory.get_slots_snapshot() == committed_slots and manager.data._to_dict() == committed_data, "基地重复事务不得二次扣款、改布局或存档状态")
	var full := _make_fragmented_board(16, [1, 3, 5, 7, 9, 11, 13, 14, 15])
	var full_before := full.get_slots_snapshot()
	manager.data.extraction_points = price + 100
	data_before = manager.data._to_dict().duplicate(true)
	var full_result := manager.purchase_base_shop_item_to_inventory("weapon_rifle", full, "base_fragment_full")
	_check(not bool(full_result.get("success", false)) and str(full_result.get("reason", "")) == "当前I键背包空间不足", "基地容量不足必须精确拒绝")
	_check(full.get_slots_snapshot() == full_before and manager.data._to_dict() == data_before, "基地容量不足不得改布局、余额或交易记录")
	manager.free()
	print("BASE_FRAGMENT_PURCHASE_CHECKED: insufficient, save rollback, retry, duplicate and capacity")


func _commit() -> bool:
	_save_calls += 1
	return _save_ok


func _always_owned(_instance_id: String) -> bool:
	return true


func _code(result: Dictionary) -> String:
	return str(result.get("code", ""))


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
