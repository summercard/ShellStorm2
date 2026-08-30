class_name WeaponInstance
extends RefCounted

## 持久枪械实例。运行时 WeaponAssemblyTree 只是该实例的可执行投影；
## 背包、地面、保险、交易与存档统一传递 to_item_dictionary() 的纯数据结果。

const SCHEMA_VERSION := 2
const DEFAULT_FATE_SLOT_CAPACITY := 8

static var _id_sequence: int = 0

var weapon_instance_id: String = ""
var weapon_content_id: String = ""
var assembly_id: String = ""
var rarity: String = "common"
var fate_slot_capacity: int = DEFAULT_FATE_SLOT_CAPACITY
var fate_upgrades: Array[Dictionary] = []
var assembly_snapshot: Dictionary = {}
var current_ammo: int = -1
var created_transaction_id: String = ""
var _base_item: Dictionary = {}


static func from_item(item: Dictionary, runtime_tree: WeaponAssemblyTree = null) -> WeaponInstance:
	if item.is_empty():
		return null
	var instance := WeaponInstance.new()
	instance._base_item = item.duplicate(true)
	var nested := item.get("weapon_instance", {}) as Dictionary
	instance.weapon_instance_id = str(item.get(
		"weapon_instance_id", nested.get("weapon_instance_id", "")
	))
	if instance.weapon_instance_id.is_empty():
		instance.weapon_instance_id = generate_instance_id()
	instance.weapon_content_id = str(item.get(
		"weapon_content_id", nested.get("weapon_content_id", item.get("id", ""))
	))
	instance.assembly_id = str(item.get(
		"assembly_id", nested.get("assembly_id", item.get("id", ""))
	))
	# ItemRegistry/BlueprintRegistry 是稳定内容 ID 与装配 ID 的唯一映射来源。
	# 兼容只保存 weapon_content_id 的旧物品，避免再次用 `weapon_*` 猜成蓝图 ID。
	var canonical_item := ItemRegistry.get_instance().get_item(instance.weapon_content_id)
	var canonical_assembly_id := str(canonical_item.get("assembly_id", ""))
	if (
		instance.assembly_id.is_empty()
		or instance.assembly_id == instance.weapon_content_id
		or not canonical_assembly_id.is_empty() and instance.assembly_id != canonical_assembly_id
	):
		instance.assembly_id = canonical_assembly_id
	instance.rarity = str(item.get("rarity", nested.get("rarity", "common")))
	instance.fate_slot_capacity = maxi(0, int(item.get(
		"fate_slot_capacity", nested.get("fate_slot_capacity", DEFAULT_FATE_SLOT_CAPACITY)
	)))
	var stored_upgrades: Variant = item.get("fate_upgrades", nested.get("fate_upgrades", []))
	if stored_upgrades is Array:
		for upgrade in stored_upgrades:
			if upgrade is Dictionary:
				instance.fate_upgrades.append((upgrade as Dictionary).duplicate(true))
	var stored_snapshot: Variant = item.get(
		"assembly_snapshot", nested.get("assembly_snapshot", {})
	)
	if stored_snapshot is Dictionary:
		instance.assembly_snapshot = _normalize_assembly_snapshot(stored_snapshot as Dictionary)
	instance.current_ammo = int(item.get("current_ammo", nested.get("current_ammo", -1)))
	instance.created_transaction_id = str(item.get(
		"created_transaction_id", nested.get("created_transaction_id", "")
	))
	if instance.created_transaction_id.is_empty():
		instance.created_transaction_id = "create:%s" % instance.weapon_instance_id
	if runtime_tree != null and runtime_tree.get_root() != null:
		instance.capture_runtime_tree(runtime_tree)
	elif instance.assembly_snapshot.is_empty():
		var root := BlueprintRegistry.create_assembly_node(instance.assembly_id)
		if root != null:
			# 远程成品枪拥有自己的标准子弹模块；近战根不伪装成零弹量枪械。
			if "melee" not in root.tags:
				var bullet_id := str(item.get("bullet_module_id", "mod_bullet_standard"))
				var bullet := BlueprintRegistry.create_assembly_node(bullet_id)
				if bullet != null and not root.mount(AssemblyNode.SlotType.BULLET, bullet):
					bullet.free()
			instance.assembly_snapshot = _serialize_node(root)
			_free_assembly_subtree(root)
	return instance


static func from_runtime_tree(tree: WeaponAssemblyTree, base_item: Dictionary = {}) -> WeaponInstance:
	var item := base_item.duplicate(true)
	if item.is_empty() and tree != null and tree.get_root() != null:
		var content_id := content_id_for_root(tree.get_root())
		item = ItemRegistry.get_instance().get_item(content_id)
	return from_item(item, tree)


static func ensure_weapon_item(item: Dictionary, runtime_tree: WeaponAssemblyTree = null) -> Dictionary:
	if str(item.get("type", "")) != "weapon":
		return item.duplicate(true)
	var instance := from_item(item, runtime_tree)
	return instance.to_item_dictionary() if instance != null else item.duplicate(true)


static func generate_instance_id() -> String:
	_id_sequence += 1
	var unix_us := int(Time.get_unix_time_from_system() * 1000000.0)
	var ticks := Time.get_ticks_usec()
	return "wpn_%016x_%08x_%04x" % [unix_us, ticks & 0xFFFFFFFF, _id_sequence & 0xFFFF]


func capture_runtime_tree(tree: WeaponAssemblyTree) -> void:
	if tree == null or tree.get_root() == null:
		return
	assembly_snapshot = _serialize_node(tree.get_root())
	current_ammo = tree.current_ammo
	if weapon_content_id.is_empty():
		weapon_content_id = content_id_for_root(tree.get_root())
	if assembly_id.is_empty():
		assembly_id = assembly_id_for_root(tree.get_root())


func build_runtime_tree() -> WeaponAssemblyTree:
	var root: AssemblyNode = null
	if not assembly_snapshot.is_empty():
		root = _deserialize_node(assembly_snapshot)
	if root == null:
		root = BlueprintRegistry.create_assembly_node(assembly_id)
	if root == null:
		return null
	_hydrate_and_migrate_root(root)
	var tree := WeaponAssemblyTree.new(root)
	if current_ammo >= 0:
		tree.current_ammo = clampi(current_ammo, 0, tree.magazine_size)
	return tree


func load_into_runtime_tree(tree: WeaponAssemblyTree) -> bool:
	if tree == null:
		return false
	var root: AssemblyNode = null
	if not assembly_snapshot.is_empty():
		root = _deserialize_node(assembly_snapshot)
	if root == null:
		root = BlueprintRegistry.create_assembly_node(assembly_id)
	if root != null:
		_hydrate_and_migrate_root(root)
	if root == null or not tree.set_root(root):
		if root != null:
			_free_assembly_subtree(root)
		return false
	if current_ammo >= 0:
		tree.current_ammo = clampi(current_ammo, 0, tree.magazine_size)
		tree.ammo_changed.emit(tree.current_ammo, tree.magazine_size)
	return true


static func _free_assembly_subtree(node: AssemblyNode) -> void:
	if node == null:
		return
	for slot_type in node.slots.keys():
		var child := node.slots.get(slot_type) as AssemblyNode
		if child != null:
			node.slots[slot_type] = null
			child.parent_node = null
			_free_assembly_subtree(child)
	node.free()


func has_free_fate_slot() -> bool:
	return fate_upgrades.size() < fate_slot_capacity


func next_fate_slot_index() -> int:
	return fate_upgrades.size() + 1


func append_fate_upgrade(card: FateCard, transaction_id: String = "") -> Dictionary:
	if card == null:
		return {"success": false, "reason": "命运卡无效"}
	if not has_free_fate_slot():
		return {"success": false, "reason": "枪械命运槽已满"}
	var stable_id := card.get_stable_card_id()
	if stable_id.is_empty():
		return {"success": false, "reason": "命运卡缺少稳定ID"}
	var record: Dictionary = {
		"slot_index": next_fate_slot_index(),
		"stable_card_id": stable_id,
		"tarot_name": card.card_name,
		"orientation": "REVERSED" if card.is_reversed() else "UPRIGHT",
		"orientation_roll": card.orientation_roll,
		"effect_version": 2,
		"effect_params_snapshot": card.effect.duplicate(true),
		"applied_transaction_id": transaction_id if not transaction_id.is_empty()
			else "fate:%s:%02d" % [weapon_instance_id, next_fate_slot_index()],
	}
	fate_upgrades.append(record)
	return {"success": true, "record": record.duplicate(true)}


func to_item_dictionary() -> Dictionary:
	var item := _base_item.duplicate(true)
	var stored_assembly_snapshot := _normalize_assembly_snapshot(assembly_snapshot)
	item["type"] = "weapon"
	item["stack_max"] = 1
	item["weapon_instance_id"] = weapon_instance_id
	item["weapon_content_id"] = weapon_content_id
	item["assembly_id"] = assembly_id
	item["rarity"] = rarity
	item["fate_slot_capacity"] = fate_slot_capacity
	item["fate_upgrades"] = fate_upgrades.duplicate(true)
	item["assembly_snapshot"] = stored_assembly_snapshot.duplicate(true)
	item["current_ammo"] = current_ammo
	item["created_transaction_id"] = created_transaction_id
	item["weapon_instance"] = {
		"schema_version": SCHEMA_VERSION,
		"weapon_instance_id": weapon_instance_id,
		"weapon_content_id": weapon_content_id,
		"assembly_id": assembly_id,
		"rarity": rarity,
		"fate_slot_capacity": fate_slot_capacity,
		"fate_upgrades": fate_upgrades.duplicate(true),
		"assembly_snapshot": stored_assembly_snapshot.duplicate(true),
		"current_ammo": current_ammo,
		"created_transaction_id": created_transaction_id,
	}
	return item


func get_presentation_snapshot(tree: WeaponAssemblyTree = null, owner_location: String = "") -> Dictionary:
	var stats := {}
	var attachment_layout: Array[Dictionary] = []
	if tree != null and tree.get_root() != null:
		stats = tree.get_computed_stats()
		attachment_layout = _build_attachment_layout(tree.get_root())
	else:
		var temp_tree := build_runtime_tree()
		if temp_tree != null:
			stats = temp_tree.get_computed_stats()
			attachment_layout = _build_attachment_layout(temp_tree.get_root())
			temp_tree.free()
	return {
		"weapon_instance_id": weapon_instance_id,
		"instance_suffix": weapon_instance_id.right(6).to_upper(),
		"weapon_content_id": weapon_content_id,
		"assembly_id": assembly_id,
		"display_name": str(_base_item.get("name", weapon_content_id)),
		"rarity": rarity,
		"owner_location": owner_location,
		"fate_slot_capacity": fate_slot_capacity,
		"fate_slot_used": fate_upgrades.size(),
		"fate_upgrades": fate_upgrades.duplicate(true),
		"attachment_slots": _attachment_layout_to_dictionary(attachment_layout),
		"attachment_layout": attachment_layout,
		"computed_stats": stats.duplicate(true),
		"current_ammo": current_ammo,
	}


static func content_id_for_root(root: AssemblyNode) -> String:
	return BlueprintRegistry.get_item_id_for_assembly_node(root)


static func assembly_id_for_root(root: AssemblyNode) -> String:
	var content_id := content_id_for_root(root)
	if content_id.is_empty():
		return ""
	return str(ItemRegistry.get_instance().get_item(content_id).get("assembly_id", ""))


static func _serialize_node(node: AssemblyNode) -> Dictionary:
	if node == null:
		return {}
	var slot_data: Dictionary = {}
	for slot_type in node.slots.keys():
		var child := node.slots.get(slot_type) as AssemblyNode
		if child != null:
			slot_data[str(int(slot_type))] = _serialize_node(child)
	return {
		"node_type": int(node.node_type),
		"node_name": node.node_name,
		"tags": node.tags.duplicate(),
		"base_stats": node.base_stats.duplicate(true),
		"slots": slot_data,
	}


static func _normalize_assembly_snapshot(snapshot: Dictionary) -> Dictionary:
	# 空快照表示“尚未生成运行时装配”，必须保持为空。旧实现会把 `{}`
	# 扩成 `{"slots": {}}`，使 from_item() 误以为已有有效快照并跳过
	# BlueprintRegistry 构建，最终反序列化出 GunBody_Unknown。
	if snapshot.is_empty():
		return {}
	var normalized := snapshot.duplicate(true)
	var stored_slots: Variant = snapshot.get("slots", {})
	if not stored_slots is Dictionary:
		return normalized
	var normalized_slots: Dictionary = {}
	for raw_slot_key in (stored_slots as Dictionary).keys():
		var child: Variant = (stored_slots as Dictionary).get(raw_slot_key)
		normalized_slots[str(raw_slot_key)] = (
			_normalize_assembly_snapshot(child as Dictionary)
			if child is Dictionary
			else child
		)
	normalized["slots"] = normalized_slots
	return normalized


static func _deserialize_node(data: Dictionary) -> AssemblyNode:
	if data.is_empty():
		return null
	var node_type := int(data.get("node_type", AssemblyNode.NodeType.GUN_BODY))
	var node := AssemblyNode.new(node_type, str(data.get("node_name", "")))
	for tag in data.get("tags", []):
		node.tags.append(str(tag))
	var stats: Variant = data.get("base_stats", {})
	if stats is Dictionary:
		node.set_base_stats((stats as Dictionary).duplicate(true))
	var slots: Variant = data.get("slots", {})
	if slots is Dictionary:
		for raw_slot in (slots as Dictionary).keys():
			var child_data: Variant = (slots as Dictionary).get(raw_slot, {})
			if not child_data is Dictionary:
				continue
			var child := _deserialize_node(child_data as Dictionary)
			if child != null and not node.mount(int(str(raw_slot)), child):
				child.free()
	return node


static func _hydrate_and_migrate_root(root: AssemblyNode) -> void:
	if root == null:
		return
	BlueprintRegistry.apply_runtime_contract(root)
	# v1 把枪托/瞄具/战术/特性配件都塞在 MOUNT。v2 按声明槽位搬迁，
	# 只动普通 Attachment，绝不碰命运系统的递归枪身挂载。
	var legacy := root.slots.get(AssemblyNode.SlotType.MOUNT) as AssemblyNode
	if legacy == null or legacy.node_type != AssemblyNode.NodeType.ATTACHMENT:
		return
	var declared_slot := legacy.get_attachment_slot_type()
	if declared_slot < 0 or root.slots.get(declared_slot) != null:
		return
	root.unmount(AssemblyNode.SlotType.MOUNT)
	if not root.mount(declared_slot, legacy):
		root.mount(AssemblyNode.SlotType.MOUNT, legacy)


static func _build_attachment_layout(root: AssemblyNode) -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	if root == null:
		return layout
	for slot_type in AssemblyNode.PUBLIC_ATTACHMENT_SLOTS:
		var child := root.slots.get(slot_type) as AssemblyNode
		layout.append({
			"slot_type": slot_type,
			"slot_key": AssemblyNode.get_attachment_slot_key(slot_type),
			"display_name": AssemblyNode.get_attachment_slot_display_name(slot_type),
			"supported": root.supports_attachment_slot(slot_type),
			"installed_item_id": BlueprintRegistry.get_item_id_for_assembly_node(child),
			"installed_node_name": child.node_name if child != null else "",
		})
	return layout


static func _attachment_layout_to_dictionary(layout: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for entry in layout:
		result[str(entry.get("slot_key", ""))] = str(entry.get("installed_item_id", ""))
	return result


static func _extract_attachment_slots(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var slots: Variant = snapshot.get("slots", {})
	if not slots is Dictionary:
		return result
	for raw_slot in (slots as Dictionary).keys():
		var child: Variant = (slots as Dictionary).get(raw_slot, {})
		if child is Dictionary:
			result[AssemblyNode.SlotType.keys()[int(str(raw_slot))]] = str(
				(child as Dictionary).get("node_name", "")
			)
	return result
