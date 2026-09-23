class_name RunMerchantService
extends RefCounted
## 局内商人会话与购买事务；不依赖 UI / 场景节点。
## 钱包、背包仍各自拥有状态；本服务协调转移并要求宿主同步确认行动快照。

var _session_id := ""
var _merchant_id := ""
var _offers: Array[Dictionary] = []
var _stocks: Dictionary = {}


func open_session(session_id: String, merchant_id: String, goods: Array[Dictionary]) -> Dictionary:
	if session_id.is_empty() or merchant_id.is_empty():
		return _failure("session_closed")
	_session_id = session_id
	_merchant_id = merchant_id
	_offers.clear()
	if _stocks.has(merchant_id):
		for value in _stocks[merchant_id]:
			_offers.append((value as Dictionary).duplicate(true))
	else:
		for index in range(mini(6, goods.size())):
			var item := WeaponInstance.ensure_weapon_item(goods[index])
			if str(item.get("id", "")).is_empty() or int(item.get("price", -1)) < 0:
				continue
			_offers.append({
				"offer_id": "%s:%d" % [merchant_id, index],
				"item": item.duplicate(true),
			})
		_stocks[merchant_id] = _offers.duplicate(true)
	return {"success": true, "code": "opened", "session_id": _session_id,
		"merchant_id": merchant_id, "offers": get_offers_snapshot()}


func close_session() -> void:
	_session_id = ""
	_merchant_id = ""
	_offers.clear()


func get_session_id() -> String:
	return _session_id


func has_stock(merchant_id: String) -> bool:
	return _stocks.has(merchant_id)


func get_offers_snapshot() -> Array[Dictionary]:
	return _offers.duplicate(true)


func export_stock_snapshot() -> Dictionary:
	return {"schema": "run_merchant_stock_v1", "stocks": _stocks.duplicate(true)}


## 全量校验后才替换内存货架；坏档不得部分恢复或静默重抽。
func restore_stock_snapshot(snapshot: Dictionary) -> bool:
	if str(snapshot.get("schema", "")) != "run_merchant_stock_v1":
		return false
	var raw_stocks: Variant = snapshot.get("stocks")
	if not raw_stocks is Dictionary:
		return false
	var rebuilt: Dictionary = {}
	var seen_offer_ids: Dictionary = {}
	var seen_weapon_ids: Dictionary = {}
	for merchant_key in (raw_stocks as Dictionary).keys():
		if not merchant_key is String or str(merchant_key).is_empty():
			return false
		var merchant_id := str(merchant_key)
		var raw_offers: Variant = raw_stocks[merchant_key]
		if not raw_offers is Array or (raw_offers as Array).size() > 6:
			return false
		var restored: Array[Dictionary] = []
		for value in raw_offers:
			if not value is Dictionary:
				return false
			var offer := value as Dictionary
			var offer_id := str(offer.get("offer_id", ""))
			var item_value: Variant = offer.get("item")
			if (
				not offer_id.begins_with("%s:" % merchant_id)
				or seen_offer_ids.has(offer_id)
				or not item_value is Dictionary
			):
				return false
			var item := item_value as Dictionary
			if str(item.get("id", "")).is_empty() or int(item.get("price", -1)) < 0:
				return false
			if str(item.get("type", "")) == "weapon":
				var instance_id := str(item.get("weapon_instance_id", ""))
				if instance_id.is_empty() or seen_weapon_ids.has(instance_id):
					return false
				seen_weapon_ids[instance_id] = true
			seen_offer_ids[offer_id] = true
			restored.append(offer.duplicate(true))
		rebuilt[merchant_id] = restored
	_stocks = rebuilt
	close_session()
	return true


func purchase(
	session_id: String, offer_id: String, expected_weapon_instance_id: String,
	inventory: InventoryModule, wallet: Object, commit_checkpoint: Callable,
	owned_weapon_instance: Callable = Callable()
) -> Dictionary:
	if _session_id.is_empty() or session_id != _session_id:
		return _failure("session_closed")
	var offer_index := -1
	for index in _offers.size():
		if str(_offers[index].get("offer_id", "")) == offer_id:
			offer_index = index
			break
	if offer_index < 0:
		return _failure("offer_missing")
	var offer := _offers[offer_index]
	var item := (offer.get("item", {}) as Dictionary).duplicate(true)
	var instance_id := str(item.get("weapon_instance_id", ""))
	if instance_id != expected_weapon_instance_id:
		return _failure("stale_offer")
	if str(item.get("type", "")) == "weapon" and instance_id.is_empty():
		return _failure("stale_offer")
	if inventory == null or wallet == null or not wallet.has_method("spend_currency") or not wallet.has_method("add_currency"):
		return _failure("inventory_rejected")
	var price := int(item.get("price", -1))
	if price < 0:
		return _failure("stale_offer")
	if str(item.get("type", "")) == "weapon" and inventory.has_weapon_instance(instance_id):
		return _failure("inventory_rejected")
	if str(item.get("type", "")) == "weapon" and owned_weapon_instance.is_valid():
		if bool(owned_weapon_instance.call(instance_id)):
			return _failure("inventory_rejected")
	if not inventory.can_add_item_exact(item, 1):
		return _failure("inventory_full")
	if int(wallet.get("currency")) < price:
		return _failure("insufficient_currency")
	if not commit_checkpoint.is_valid():
		return _failure("save_failed")
	var inventory_before := inventory.get_slots_snapshot()
	if not bool(wallet.call("spend_currency", price)):
		return _failure("insufficient_currency")
	if inventory.add_item(item, 1) != 1:
		inventory.restore_slots_snapshot(inventory_before)
		wallet.call("add_currency", price)
		return _failure("inventory_rejected")
	_offers.remove_at(offer_index)
	_stocks[_merchant_id] = _offers.duplicate(true)
	if not bool(commit_checkpoint.call()):
		_offers.insert(offer_index, offer)
		_stocks[_merchant_id] = _offers.duplicate(true)
		inventory.restore_slots_snapshot(inventory_before)
		wallet.call("add_currency", price)
		return _failure("save_failed")
	return {"success": true, "code": "committed", "session_id": session_id,
		"offer_id": offer_id, "item": item, "weapon_instance_id": instance_id,
		"offers": get_offers_snapshot()}


func _failure(code: String) -> Dictionary:
	return {"success": false, "code": code}
