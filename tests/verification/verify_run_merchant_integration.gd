extends Node

const LEVEL := preload("res://scenes/levels3d/IronFrontier3D.tscn")
const TEST_SAVE_PATH := "user://run_merchant_integration_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	_cleanup_test_save()
	var dungeon := LEVEL.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 12024
	add_child(dungeon)
	await get_tree().process_frame
	GameManager.currency = 100000
	GameManager.currency_changed.emit(GameManager.currency)
	var original_save_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	BaseManager.save_path = TEST_SAVE_PATH
	BaseManager.data = BaseData.new()
	BaseManager.register_runtime_checkpoint_provider(dungeon)
	dungeon.set("_runtime_persistence_active", true)
	var merchant_id := str(dungeon.get("_current_room_id"))
	if not BaseManager.set_active_run_checkpoint(dungeon.build_runtime_save_snapshot(), "merchant_before"):
		failures.append("商人交易前的行动检查点无法写盘")
	var revision_before_open := BaseManager.data.save_revision
	BaseManager.force_save_failure_for_test = true
	dungeon.call("_open_merchant")
	var merchant := dungeon.get("_merchant_service") as RunMerchantService
	if dungeon.get("_merchant_ui") != null or merchant == null or merchant.has_stock(merchant_id):
		failures.append("首开写盘失败后错误展示或保留未提交货架")
	if BaseManager.data.save_revision != revision_before_open:
		failures.append("首开写盘失败仍修改存档修订号")
	BaseManager.force_save_failure_for_test = false
	dungeon.call("_open_merchant")
	merchant = dungeon.get("_merchant_service") as RunMerchantService
	var ui := dungeon.get("_merchant_ui") as MerchantUI
	if merchant == null or ui == null or merchant.get_offers_snapshot().is_empty():
		failures.append("正式场景没有持久化并展示商人货架")
	else:
		var first_offer := merchant.get_offers_snapshot()[0] as Dictionary
		var offered := first_offer.get("item", {}) as Dictionary
		var starting_currency := GameManager.currency
		var inventory := dungeon.get("_inventory") as InventoryModule
		var starting_slots := inventory.get_slots_snapshot()
		var starting_used_slots := inventory.get_used_slots()
		var starting_snapshot := BaseManager.get_active_run_checkpoint()
		var starting_revision := BaseManager.data.save_revision
		var starting_offers := merchant.get_offers_snapshot().size()
		var initial_stock := starting_snapshot.get("merchant_stock", {}) as Dictionary
		if JSON.stringify((initial_stock.get("stocks", {}) as Dictionary).get(merchant_id, [])) != JSON.stringify(merchant.get_offers_snapshot()):
			failures.append("首开落档没有保存同一批报价与武器实例")
		BaseManager.force_save_failure_for_test = true
		ui.call("_on_slot_clicked", 0)
		if GameManager.currency != starting_currency:
			failures.append("写盘失败后扣魂没有回滚")
		if inventory.get_slots_snapshot() != starting_slots:
			failures.append("写盘失败后背包精确格位没有回滚")
		if merchant.get_offers_snapshot().size() != starting_offers:
			failures.append("写盘失败后货架报价没有恢复")
		if bool(dungeon.get("_trade_extraction_unlocked")):
			failures.append("写盘失败后错误解锁交易撤离")
		if BaseManager.data.save_revision != starting_revision or BaseManager.get_active_run_checkpoint() != starting_snapshot:
			failures.append("写盘失败后行动检查点或存档修订号发生变化")
		BaseManager.force_save_failure_for_test = false
		ui.call("_on_slot_clicked", 0)
		if GameManager.currency != starting_currency - int(offered.get("price", 0)):
			failures.append("点击 UI 后没有按报价扣魂")
		if inventory.get_used_slots() != starting_used_slots + 1:
			failures.append("点击 UI 后没有把完整物品转入行动背包")
		var remaining := merchant.get_offers_snapshot()
		if remaining.size() != starting_offers - 1:
			failures.append("成交后货架报价未移除")
		if not bool(dungeon.get("_trade_extraction_unlocked")):
			failures.append("成交后交易撤离条件未解锁")
		BaseManager.load_base()
		var persisted := BaseManager.get_active_run_checkpoint()
		if int(persisted.get("run_currency", -1)) != GameManager.currency:
			failures.append("重读存档后的魂余额不是成交值")
		var normalized_slots: Variant = JSON.parse_string(JSON.stringify(inventory.get_slots_snapshot()))
		if persisted.get("inventory_slots", []) != normalized_slots:
			failures.append("重读存档后的背包格位不是成交值")
		if not bool(persisted.get("trade_extraction_unlocked", false)):
			failures.append("重读存档后没有交易撤离条件")
		var persisted_stock := persisted.get("merchant_stock", {}) as Dictionary
		if _canonical_json((persisted_stock.get("stocks", {}) as Dictionary).get(merchant_id, [])) != _canonical_json(remaining):
			failures.append("成交重读存档后货架没有移除已售报价")
		if str(offered.get("type", "")) == "weapon":
			var instance_id := str(offered.get("weapon_instance_id", ""))
			if instance_id.is_empty() or not inventory.has_weapon_instance(instance_id):
				failures.append("货架枪械的实例 ID 没有原样转移")
		ui.hide_merchant()
		if not merchant.get_session_id().is_empty():
			failures.append("关闭 UI 后商人会话仍可购买")
		dungeon.call("_open_merchant")
		var reopened := dungeon.get("_merchant_service") as RunMerchantService
		if reopened == null or reopened.get_offers_snapshot() != remaining:
			failures.append("关窗重开后货架被刷新")
		var reopened_ui := dungeon.get("_merchant_ui") as MerchantUI
		if reopened_ui != null:
			reopened_ui.hide_merchant()
		dungeon.set("_trade_extraction_unlocked", false)
		dungeon.set("_trade_extraction_room_id", "")
		dungeon.call("_restore_runtime_save_snapshot", persisted)
		if not bool(dungeon.get("_trade_extraction_unlocked")):
			failures.append("重载快照没有恢复交易撤离条件")
		dungeon.call("_open_merchant")
		var restored_merchant := dungeon.get("_merchant_service") as RunMerchantService
		if restored_merchant == null or _canonical_json(restored_merchant.get_offers_snapshot()) != _canonical_json(remaining):
			failures.append("重载后报价、价格或武器实例改变")
		if restored_merchant != null:
			for value in restored_merchant.get_offers_snapshot():
				if str(value.get("offer_id", "")) == str(first_offer.get("offer_id", "")):
					failures.append("重载后重新上架已售报价")
		var final_ui := dungeon.get("_merchant_ui") as MerchantUI
		if final_ui != null:
			final_ui.hide_merchant()
		var invalid_snapshot := persisted.duplicate(true)
		invalid_snapshot["merchant_stock"] = {"schema": "invalid", "stocks": {}}
		dungeon.call("_restore_runtime_save_snapshot", invalid_snapshot)
		dungeon.call("_open_merchant")
		if dungeon.get("_merchant_ui") != null:
			failures.append("无效商人货架快照没有拒绝交易")
		var legacy_snapshot := persisted.duplicate(true)
		legacy_snapshot.erase("merchant_stock")
		dungeon.call("_restore_runtime_save_snapshot", legacy_snapshot)
		dungeon.call("_open_merchant")
		var legacy_merchant := dungeon.get("_merchant_service") as RunMerchantService
		if dungeon.get("_merchant_ui") == null or legacy_merchant == null or not legacy_merchant.has_stock(merchant_id):
			failures.append("旧档缺货架字段无法首次生成并落档")
		var legacy_ui := dungeon.get("_merchant_ui") as MerchantUI
		if legacy_ui != null:
			legacy_ui.hide_merchant()
	BaseManager.force_save_failure_for_test = false
	BaseManager.unregister_runtime_checkpoint_provider(dungeon, false)
	dungeon.set("_runtime_persistence_active", false)
	BaseManager.save_path = original_save_path
	BaseManager.data = original_data
	dungeon.queue_free()
	await get_tree().process_frame
	_cleanup_test_save()
	if failures.is_empty():
		print("RUN_MERCHANT_INTEGRATION_OK: stock save failure, trade rollback, reopen, reload, invalid and legacy snapshots")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _cleanup_test_save() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
