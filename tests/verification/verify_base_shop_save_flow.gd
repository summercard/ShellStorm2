extends Node

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const TEST_PATH := "user://base_shop_save_probe.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	_verify_catalog(failures)
	_verify_save_envelope_and_backup(failures)
	_verify_avatar_save_with_numeric_weapon_slots(failures)
	_verify_transactions_and_restart(failures)
	_verify_save_failure_rollback(failures)
	_verify_stale_writer_guard(failures)
	_verify_runtime_inventory_transactions(failures)
	await _verify_interface_and_model(failures)
	_cleanup()
	_finish(failures)


func _verify_catalog(failures: Array[String]) -> void:
	var goods := ItemRegistry.get_instance().get_base_shop_goods()
	var expected_ids := ["weapon_baseball_bat", "weapon_pistol", "weapon_shotgun", "weapon_rifle", "equipment_backpack_2", "item_health_potion", "item_battery_s"]
	if goods.size() != 7:
		failures.append("基地货架不是7类商品（含初级棒球棍与小型电池）")
	for index in expected_ids.size():
		if index >= goods.size() or str(goods[index].get("id", "")) != expected_ids[index]:
			failures.append("基地货架顺序或ID与数据库不一致")
			break
	for item in goods:
		if int(item.get("base_buy_price", 0)) <= 0 or int(item.get("base_sell_price", 0)) <= 0:
			failures.append("上架商品缺少独立买价/卖价：%s" % str(item.get("id", "")))


func _verify_save_envelope_and_backup(failures: Array[String]) -> void:
	_cleanup()
	var payload := BaseData.new()._to_dict()
	var revision_one := ProfileSaveService.build_envelope(payload, 1, "probe_one")
	if not AtomicJsonStore.save_dictionary(TEST_PATH, revision_one):
		failures.append("无法写入第一版封套")
		return
	payload["extraction_points"] = 99
	var revision_two := ProfileSaveService.build_envelope(payload, 2, "probe_two")
	if not AtomicJsonStore.save_dictionary(TEST_PATH, revision_two):
		failures.append("无法写入第二版封套")
		return
	revision_two["payload_checksum"] = "tampered"
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(revision_two))
		file.close()
	var recovered: Variant = AtomicJsonStore.load_dictionary(TEST_PATH, Callable(ProfileSaveService, "is_valid_envelope"))
	if not recovered is Dictionary or int((recovered as Dictionary).get("revision", 0)) != 1:
		failures.append("checksum损坏后没有回退到有效备份")


func _verify_avatar_save_with_numeric_weapon_slots(failures: Array[String]) -> void:
	_cleanup()
	var expected_loadout := {
		"body": "suit_cobalt",
		"head": "plated_amber",
		"hand": "gauntlet_teal",
		"feet": "boot_teal",
		"hat": "hard_hat",
		"glasses": "wide_visor",
	}
	var numeric_slot_snapshot := {
		"node_type": 0,
		"node_name": "GunBody_Pistol",
		"tags": ["weapon"],
		"base_stats": {},
		"slots": {
			3: {
				"node_type": 3,
				"node_name": "Bullet_Sticky",
				"tags": ["bullet"],
				"base_stats": {},
				"slots": {},
			},
		},
	}
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	manager.data.avatar_customization = expected_loadout.duplicate(true)
	manager.data.active_run_snapshot = {
		"valid": true,
		"checkpoint_id": "avatar_numeric_slot_probe",
		"layout_id": "avatar_numeric_slot_probe",
		"equipped_weapon_items": [{"assembly_snapshot": numeric_slot_snapshot}],
	}
	if not manager.save_base("avatar_numeric_slot_probe"):
		failures.append("带整数武器槽位时换装总档没有通过写后回读校验")
		manager.free()
		return
	var stored: Variant = AtomicJsonStore.load_dictionary(TEST_PATH)
	if not stored is Dictionary:
		failures.append("带整数武器槽位的换装总档无法读取")
	else:
		var envelope := stored as Dictionary
		if str(envelope.get("payload_checksum_algorithm", "")) != ProfileSaveService.CHECKSUM_ALGORITHM:
			failures.append("换装总档没有升级到当前校验算法")
		var payload := envelope.get("payload", {}) as Dictionary
		var weapon_items := (payload.get("active_run_snapshot", {}) as Dictionary).get("equipped_weapon_items", []) as Array
		var slots := (((weapon_items[0] as Dictionary).get("assembly_snapshot", {}) as Dictionary).get("slots", {}) as Dictionary)
		if not slots.has("3") or slots.has(3):
			failures.append("武器装配枚举槽位没有在落盘前统一为JSON字符串键")
	var restored := MANAGER_SCRIPT.new()
	restored.save_path = TEST_PATH
	restored.load_base()
	if restored.data.avatar_customization != expected_loadout:
		failures.append("换装与带整数槽位的武器快照共同保存后，模拟重启丢失外观")
	manager.free()
	restored.free()

	# 精确模拟canonical_json_v2旧缺陷档：内存中整数槽位被旧算法按null摘要，
	# JSON写盘后变成字符串键。新版本必须定向识别并自动重存为v3。
	_cleanup()
	var legacy_data := BaseData.new()
	legacy_data.avatar_customization = expected_loadout.duplicate(true)
	legacy_data.active_run_snapshot = {
		"valid": true,
		"checkpoint_id": "avatar_v2_migration_probe",
		"layout_id": "avatar_v2_migration_probe",
		"equipped_weapon_items": [{"assembly_snapshot": numeric_slot_snapshot}],
	}
	var legacy_payload := legacy_data._to_dict()
	var legacy_envelope := {
		"manifest_version": ProfileSaveService.MANIFEST_VERSION,
		"profile_schema": BaseData.SAVE_VERSION,
		"revision": 7,
		"saved_at_unix": 1,
		"reason": "active_run_checkpoint:legacy_numeric_slot",
		"payload_checksum_algorithm": ProfileSaveService.LEGACY_CHECKSUM_ALGORITHM,
		"payload_checksum": _legacy_v2_checksum(legacy_payload),
		"payload": legacy_payload,
	}
	if not AtomicJsonStore.save_dictionary(TEST_PATH, legacy_envelope):
		failures.append("无法建立旧整数槽位迁移测试档")
		return
	var migrated := MANAGER_SCRIPT.new()
	migrated.save_path = TEST_PATH
	migrated.load_base()
	if migrated.data.avatar_customization != expected_loadout:
		failures.append("canonical_json_v2整数槽位旧档迁移后丢失换装")
	var migrated_file: Variant = AtomicJsonStore.load_dictionary(TEST_PATH)
	if (
		not migrated_file is Dictionary
		or str((migrated_file as Dictionary).get("payload_checksum_algorithm", ""))
		!= ProfileSaveService.CHECKSUM_ALGORITHM
	):
		failures.append("canonical_json_v2整数槽位旧档没有自动升级为v3")
	migrated.free()

	# 旧v2还可能因写前高精度Variant与JSON落盘形态不同而无法精确复算。
	# 只有封套/载荷元数据完全互证时允许一次性升级。
	_cleanup()
	legacy_data.save_revision = 9
	legacy_data.last_save_reason = "active_run_checkpoint:v2_json_representation"
	legacy_data.last_saved_at_unix = 20750101
	legacy_payload = legacy_data._to_dict()
	legacy_envelope = {
		"manifest_version": ProfileSaveService.MANIFEST_VERSION,
		"profile_schema": BaseData.SAVE_VERSION,
		"revision": legacy_data.save_revision,
		"saved_at_unix": legacy_data.last_saved_at_unix,
		"reason": legacy_data.last_save_reason,
		"payload_checksum_algorithm": ProfileSaveService.LEGACY_CHECKSUM_ALGORITHM,
		"payload_checksum": "a".repeat(64),
		"payload": legacy_payload,
	}
	var structurally_recoverable := ProfileSaveService.unpack(legacy_envelope)
	if not bool(structurally_recoverable.get("success", false)) or not bool(structurally_recoverable.get("legacy", false)):
		failures.append("元数据互证的v2 JSON表示差异档不能进入一次性迁移")
	var inconsistent := legacy_envelope.duplicate(true)
	(inconsistent.get("payload", {}) as Dictionary)["last_save_reason"] = "mismatched_reason"
	if bool(ProfileSaveService.unpack(inconsistent).get("success", false)):
		failures.append("封套/载荷元数据不一致的v2损坏档被错误接受")


func _legacy_v2_checksum(value: Variant) -> String:
	return _legacy_v2_canonical_json(value).sha256_text()


func _legacy_v2_canonical_json(value: Variant) -> String:
	var value_type := typeof(value)
	if value_type == TYPE_INT or value_type == TYPE_FLOAT:
		return String.num(float(value), 12)
	if value is Dictionary:
		var keys: Array[String] = []
		for raw_key in (value as Dictionary).keys():
			keys.append(str(raw_key))
		keys.sort()
		var entries: Array[String] = []
		for key in keys:
			entries.append("%s:%s" % [JSON.stringify(key), _legacy_v2_canonical_json((value as Dictionary).get(key))])
		return "{%s}" % ",".join(entries)
	if value is Array:
		var entries: Array[String] = []
		for child in value as Array:
			entries.append(_legacy_v2_canonical_json(child))
		return "[%s]" % ",".join(entries)
	return JSON.stringify(value)


func _verify_transactions_and_restart(failures: Array[String]) -> void:
	_cleanup()
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	manager.data.extraction_points = 500
	manager.data.vault_level = 8
	var buy := manager.purchase_base_shop_item("weapon_pistol", "txn_buy_pistol") as Dictionary
	if not bool(buy.get("success", false)) or manager.data.extraction_points != 430 or manager.data.pending_loadout_items.size() != 1:
		failures.append("购买没有原子扣款并放入随身背包")
		return
	var bought := manager.data.pending_loadout_items[0] as Dictionary
	if str(bought.get("item_instance_id", "")).is_empty() or str(bought.get("weapon_instance_id", "")).is_empty():
		failures.append("购买枪械没有生成双重稳定实例ID")
	var duplicate := manager.purchase_base_shop_item("weapon_pistol", "txn_buy_pistol") as Dictionary
	if not bool(duplicate.get("duplicate", false)) or manager.data.extraction_points != 430 or manager.data.pending_loadout_items.size() != 1:
		failures.append("重复购买事务产生了二次扣款或发物")
	var second_buy := manager.purchase_base_shop_item("weapon_pistol", "txn_buy_pistol_2") as Dictionary
	if not bool(second_buy.get("success", false)) or manager.data.extraction_points != 360 or manager.data.pending_loadout_items.size() != 2:
		failures.append("无限库存商品不能连续购买")
	var item_instance_id := str(bought.get("item_instance_id", ""))
	var sell := manager.sell_base_shop_item(item_instance_id, "txn_sell_pistol", "loadout") as Dictionary
	if not bool(sell.get("success", false)) or manager.data.extraction_points != 395 or manager.data.pending_loadout_items.size() != 1:
		failures.append("出售没有按数据库卖价原子结算")
	var duplicate_sell := manager.sell_base_shop_item(item_instance_id, "txn_sell_pistol") as Dictionary
	if not bool(duplicate_sell.get("duplicate", false)) or manager.data.extraction_points != 395:
		failures.append("重复出售事务产生了二次收款")
	for index in 6:
		var potion_buy := manager.purchase_base_shop_item("item_health_potion", "txn_buy_potion_%d" % index) as Dictionary
		if not bool(potion_buy.get("success", false)):
			failures.append("第%d瓶药水连续购买失败" % (index + 1))
			break
	if manager.data.pending_loadout_items.size() != 3:
		failures.append("六瓶药水没有按5+1形成两个可见堆叠格")
	else:
		var potion_a := manager.data.pending_loadout_items[1] as Dictionary
		var potion_b := manager.data.pending_loadout_items[2] as Dictionary
		if int(potion_a.get("count", 0)) != 5 or int(potion_b.get("count", 0)) != 1:
			failures.append("药水堆叠数量不是5+1")
	var to_vault := manager.transfer_base_storage_item("loadout", 0, "vault") as Dictionary
	var to_loadout := manager.transfer_base_storage_item("vault", 0, "loadout") as Dictionary
	if not bool(to_vault.get("success", false)) or not bool(to_loadout.get("success", false)) or not manager.data.vault_items.is_empty():
		failures.append("保险柜与随身背包不能双向原子转移")
	var restored := MANAGER_SCRIPT.new()
	restored.save_path = TEST_PATH
	restored.load_base()
	if restored.data.extraction_points != 155 or restored.data.pending_loadout_items.size() != 3 or restored.data.save_revision < 2:
		failures.append("重启加载没有恢复交易结果与revision")
	manager.free()
	restored.free()


func _verify_save_failure_rollback(failures: Array[String]) -> void:
	_cleanup()
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.force_save_failure_for_test = true
	manager.data = BaseData.new()
	manager.data.extraction_points = 500
	manager.data.vault_level = 8
	var result := manager.purchase_base_shop_item("item_health_potion", "txn_must_rollback") as Dictionary
	if bool(result.get("success", false)) or manager.data.extraction_points != 500 or not manager.data.pending_loadout_items.is_empty():
		failures.append("写盘失败时购买没有完整回滚")
	if "txn_must_rollback" in manager.data.completed_transaction_ids:
		failures.append("失败交易被错误记入幂等日志")
	manager.free()


func _verify_stale_writer_guard(failures: Array[String]) -> void:
	_cleanup()
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	manager.data.extraction_points = 10
	if not manager.save_base("stale_guard_seed"):
		failures.append("无法建立旧写入者保护测试档")
		manager.free()
		return
	var newer_data := BaseData.new()
	newer_data.extraction_points = 99
	var newer := ProfileSaveService.build_envelope(newer_data._to_dict(), 5, "newer_writer")
	if not AtomicJsonStore.save_dictionary(TEST_PATH, newer):
		failures.append("无法建立高revision外部测试档")
		manager.free()
		return
	manager.data.extraction_points = 11
	if manager.save_base("stale_writer_attempt"):
		failures.append("旧revision写入者错误覆盖了新存档")
	if manager.data.extraction_points != 99 or manager.data.save_revision != 5:
		failures.append("拒绝旧revision写入后没有重新加载磁盘权威档")
	manager.free()


func _verify_runtime_inventory_transactions(failures: Array[String]) -> void:
	_cleanup()
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	manager.data.extraction_points = 500
	manager.data.vault_level = 8
	var inventory := InventoryModule.new(12)
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_pistol"), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	if inventory.get_used_slots() != 2:
		failures.append("I键测试背包没有准备两件物品")
		manager.free()
		return
	var deposit := manager.transfer_runtime_inventory_item("inventory", 0, inventory) as Dictionary
	if not bool(deposit.get("success", false)) or inventory.get_used_slots() != 1 or manager.data.vault_items.size() != 1:
		failures.append("I键背包物品不能存入保险柜")
	var withdraw := manager.transfer_runtime_inventory_item("vault", 0, inventory) as Dictionary
	if not bool(withdraw.get("success", false)) or inventory.get_used_slots() != 2 or not manager.data.vault_items.is_empty():
		failures.append("保险柜物品不能即时取回I键背包")
	var before_buy := inventory.get_item_count("item_health_potion")
	var buy := manager.purchase_base_shop_item_to_inventory("item_health_potion", inventory, "txn_runtime_buy") as Dictionary
	if not bool(buy.get("success", false)) or inventory.get_item_count("item_health_potion") != before_buy + 1:
		failures.append("贩卖机购买没有即时进入I键背包")
	var potion_slot := _find_inventory_slot(inventory, "item_health_potion")
	var sell := manager.sell_runtime_inventory_item(inventory, potion_slot, "txn_runtime_sell") as Dictionary
	if not bool(sell.get("success", false)) or inventory.get_item_count("item_health_potion") != before_buy:
		failures.append("贩卖机不能从I键背包出售物品")
	manager.force_save_failure_for_test = true
	var old_points := manager.data.extraction_points
	var old_used := inventory.get_used_slots()
	var failed_buy := manager.purchase_base_shop_item_to_inventory("weapon_rifle", inventory, "txn_runtime_rollback") as Dictionary
	if bool(failed_buy.get("success", false)) or manager.data.extraction_points != old_points or inventory.get_used_slots() != old_used:
		failures.append("I键背包购买写盘失败时没有同时回滚")
	manager.free()


func _verify_interface_and_model(failures: Array[String]) -> void:
	var runtime_inventory := InventoryModule.new(12)
	runtime_inventory.add_item(ItemRegistry.get_instance().get_item("weapon_pistol"), 1)
	runtime_inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	var menu_scene := load("res://scenes/BaseVendingMenu.tscn") as PackedScene
	var menu := menu_scene.instantiate() as BaseVendingMenu
	menu.set_inventory_module(runtime_inventory)
	add_child(menu)
	await get_tree().process_frame
	if menu._buy_list == null or menu._buy_list.get_child_count() != 7:
		failures.append("自动贩卖机界面没有展示7个固定货架条目（含初级棒球棍与小型电池）")
	if menu.find_children("*", "ItemModelIcon3D", true, false).size() < 7:
		failures.append("购买货架没有复用背包3D物品图标")
	if "魂" not in menu._points_label.text or "当前背包" not in menu._capacity_label.text:
		failures.append("贩卖机顶部没有明确显示购买货币与购买目标")
	if "2 / 12" not in menu._capacity_label.text or not _tree_has_label_text(menu._sell_list, "当前背包（与I键一致）"):
		failures.append("贩卖机没有显示I键背包中的两件物品")
	menu.queue_free()
	var vault_scene := load("res://scenes/VaultMenu.tscn") as PackedScene
	var vault_menu := vault_scene.instantiate() as VaultMenu
	vault_menu.set_inventory_module(runtime_inventory)
	add_child(vault_menu)
	await get_tree().process_frame
	if vault_menu.find_children("*", "BaseStorageSlot", true, false).size() < 14:
		failures.append("保险柜没有生成长期仓储与12格随身背包的可见格子")
	var visible_runtime_items := 0
	for slot in vault_menu.find_children("*", "BaseStorageSlot", true, false):
		if slot is BaseStorageSlot and slot.owner_id == "inventory" and not slot.item.is_empty():
			visible_runtime_items += 1
	if visible_runtime_items != 2:
		failures.append("保险柜右栏没有读取I键背包中的两件物品")
	vault_menu.queue_free()
	var model_scene := load("res://assets/art/props/base_world_3d/prp_base_vending_machine_root_top3d_v001.tscn") as PackedScene
	var model := model_scene.instantiate() as BaseFacility3D
	add_child(model)
	await get_tree().process_frame
	if model.facility_id != "base_vending" or model.get_node_or_null("Visual/ProductWindow") == null:
		failures.append("长方体自动贩卖机模型或设施契约缺失")
	model.queue_free()
	await get_tree().process_frame


func _find_inventory_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _tree_has_label_text(root: Node, text_fragment: String) -> bool:
	if root is Label and text_fragment in (root as Label).text:
		return true
	for child in root.get_children():
		if _tree_has_label_text(child, text_fragment):
			return true
	return false


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE_SHOP_SAVE_OK: database-backed catalog, checksum fallback, idempotent atomic buy/sell, restart restore, 3D icons and vending model pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
