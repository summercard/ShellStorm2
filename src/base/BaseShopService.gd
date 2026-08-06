class_name BaseShopService
extends RefCounted
## 自动贩卖机的纯数据规则。BaseManager负责单次保存与失败回滚。

const CURRENCY_ID := "extraction_points"
const MAX_TRANSACTION_LOG := 128
static var _item_sequence := 0


static func get_goods() -> Array[Dictionary]:
	return ItemRegistry.get_instance().get_base_shop_goods()


static func get_sell_price(item: Dictionary) -> int:
	var content_id := str(item.get("id", item.get("weapon_content_id", "")))
	var definition := ItemRegistry.get_instance().get_item(content_id)
	if definition.is_empty():
		return 0
	return maxi(0, int(definition.get("base_sell_price", 0)))


static func make_item_instance(definition: Dictionary, transaction_id: String) -> Dictionary:
	var item := definition.duplicate(true)
	item["count"] = 1
	item["item_instance_id"] = generate_item_instance_id()
	item["acquired_from"] = "base_vending"
	item["purchase_transaction_id"] = transaction_id
	if str(item.get("type", "")) == "weapon":
		item = WeaponInstance.ensure_weapon_item(item)
	return item


static func ensure_item_instance(item: Dictionary) -> Dictionary:
	var normalized := WeaponInstance.ensure_weapon_item(item)
	if str(normalized.get("item_instance_id", "")).is_empty():
		normalized["item_instance_id"] = generate_item_instance_id()
	return normalized


static func find_vault_item_index(items: Array, item_instance_id: String) -> int:
	if item_instance_id.is_empty():
		return -1
	for index in items.size():
		var raw: Variant = items[index]
		if not raw is Dictionary:
			continue
		var item := raw as Dictionary
		if str(item.get("item_instance_id", "")) == item_instance_id:
			return index
		if str(item.get("weapon_instance_id", "")) == item_instance_id:
			return index
	return -1


static func has_completed(transaction_ids: Array[String], transaction_id: String) -> bool:
	return not transaction_id.is_empty() and transaction_id in transaction_ids


static func append_completed(transaction_ids: Array[String], transaction_id: String) -> void:
	if transaction_id.is_empty() or transaction_id in transaction_ids:
		return
	transaction_ids.append(transaction_id)
	while transaction_ids.size() > MAX_TRANSACTION_LOG:
		transaction_ids.pop_front()


static func generate_transaction_id(operation: String) -> String:
	return "shop:%s:%s" % [operation, generate_item_instance_id()]


static func generate_item_instance_id() -> String:
	_item_sequence += 1
	var unix_us := int(Time.get_unix_time_from_system() * 1000000.0)
	return "itm_%016x_%08x_%04x" % [unix_us, Time.get_ticks_usec() & 0xFFFFFFFF, _item_sequence & 0xFFFF]
