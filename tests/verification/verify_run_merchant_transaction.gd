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


func _ready() -> void:
	var service := SERVICE.new()
	var wallet := Wallet.new()
	var inventory := InventoryModule.new(1)
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
	inventory.add_item({"id": "test_filler", "type": "material"}, 1)
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "inventory_full", "格位满拒绝")
	inventory.clear_all()
	_save_ok = false
	_check(_code(service.purchase("session-2", offer_id, instance_id, inventory, wallet, command)) == "save_failed", "写盘失败拒绝")
	_check(wallet.currency == 100 and inventory.get_used_slots() == 0 and service.get_offers_snapshot().size() == 1, "写盘失败必须回滚魂、格位与货架")
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
	if _failures.is_empty():
		print("RUN_MERCHANT_TRANSACTION_OK: persistent stock, session, instance, balance, capacity, rollback, retry and duplicate")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


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
