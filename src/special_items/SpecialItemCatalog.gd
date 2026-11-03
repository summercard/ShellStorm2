class_name SpecialItemCatalog
extends RefCounted
## Only numeric/content source for SPECIAL-ITEMS; UI and vendors consume this projection.
const PATH := "res://data/special_items/catalog.json"
const GRENADE := "special_grenade"
const MOLOTOV := "special_molotov"
const GASOLINE := "special_gasoline"
static var _definitions: Dictionary = {}

static func definitions() -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for value: Dictionary in _definitions.values():
		result.append(value.duplicate(true))
	return result

static func get_item(item_id: String) -> Dictionary:
	_load()
	return (_definitions.get(item_id, {}) as Dictionary).duplicate(true)

static func contains(item_id: String) -> bool:
	_load()
	return _definitions.has(item_id)

static func _load() -> void:
	if not _definitions.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or str(parsed.get("schema", "")) != "special_item_catalog_v1":
		push_error("SPECIAL_ITEM_CATALOG_INVALID")
		return
	for value: Dictionary in parsed.get("items", []):
		var definition := value.duplicate(true)
		definition["base_shop_enabled"] = true
		definition["base_stock_rule"] = "unlimited"
		definition["base_shop_entry_id"] = "base_stock_%s" % definition.id
		definition["tags"] = ["special_item", "consumable"]
		_definitions[str(definition.id)] = definition
