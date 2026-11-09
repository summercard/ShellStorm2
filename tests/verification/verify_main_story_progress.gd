extends Node

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const DATA_SCRIPT := preload("res://src/base/BaseData.gd")
const STORY_SCRIPT := preload("res://src/narrative/MainStoryProgress.gd")
const TEST_SAVE_PATH := "user://verify_main_story_progress.json"

var failures: Array[String] = []
var original_data: BaseData
var original_save_path := ""
var original_force_save_failure := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	original_data = BaseManager.data
	original_save_path = BaseManager.save_path
	original_force_save_failure = BaseManager.force_save_failure_for_test
	BaseManager.save_path = TEST_SAVE_PATH
	_remove_test_save()
	BaseManager.force_save_failure_for_test = false
	BaseManager.data = DATA_SCRIPT.new()
	_verify_rules_and_serialization()
	_verify_accept_claim_deposit_reload()
	_verify_save_failure_and_stale_revision()
	_verify_settlement_and_checkpoint_isolation()
	_restore_process_state()
	_finish()

func _verify_rules_and_serialization() -> void:
	_expect(STORY_SCRIPT.KEY_RARE_EARTH == "mq_key_rare_earth", "稀土钥匙常量错误")
	_expect(STORY_SCRIPT.BRIEFING_ID == "nar_main_031_green_briefing", "3.1 ID 错误")
	_expect(STORY_SCRIPT.BOSS_ID == "nar_main_032_monitor_audience", "3.2 ID 错误")
	_expect(STORY_SCRIPT.DEPOSIT_ID == "nar_main_033_key_install", "3.3 ID 错误")
	_expect(STORY_SCRIPT.key_for_level("01") == STORY_SCRIPT.KEY_RARE_EARTH, "01 映射错误")
	_expect(STORY_SCRIPT.key_for_level("03") == STORY_SCRIPT.KEY_MANOR, "03 映射错误")
	_expect(STORY_SCRIPT.key_for_level("02") == STORY_SCRIPT.KEY_HOTEL, "02 映射错误")
	_expect(STORY_SCRIPT.key_for_level("04") == STORY_SCRIPT.KEY_SECTOR_04, "04 映射错误")
	_expect(STORY_SCRIPT.key_state({}, STORY_SCRIPT.KEY_RARE_EARTH) == "not_acquired", "缺失钥匙状态错误")
	_expect(STORY_SCRIPT.installed_count({}) == 0, "空主线安装计数错误")

	var fresh := DATA_SCRIPT.new()
	var serialized := fresh._to_dict()
	_expect(str(serialized.get("save_version", "")) == "2.0", "SAVE_VERSION 被修改")
	_expect((serialized.get("main_story", {}) as Dictionary).get("schema_version", 0) == 1, "默认主线 schema 错误")
	var restored := DATA_SCRIPT.from_dict(serialized)
	_expect(restored.main_story == STORY_SCRIPT.default_state(), "默认主线序列化不对称")
	var malformed := DATA_SCRIPT.from_dict({"main_story": {"schema_version": "bad", "keys": ["bad"]}})
	_expect(malformed.main_story == STORY_SCRIPT.default_state(), "坏主线字典未安全降级")
	var malformed_record := DATA_SCRIPT.from_dict({
		"main_story": {"accepted": true, "keys": {STORY_SCRIPT.KEY_RARE_EARTH: "bad", "unknown": {"state": "deposited"}}}
	})
	_expect(bool(malformed_record.main_story.get("accepted", false)), "坏字典丢失合法 accepted")
	_expect(STORY_SCRIPT.installed_count(malformed_record.main_story) == 0, "坏钥匙记录被错误计入安装")

func _verify_accept_claim_deposit_reload() -> void:
	var accepted := BaseManager.accept_main_story()
	_expect(bool(accepted.get("success", false)) and not bool(accepted.get("duplicate", false)), "接受主线失败")
	var accepted_duplicate := BaseManager.accept_main_story()
	_expect(bool(accepted_duplicate.get("success", false)) and bool(accepted_duplicate.get("duplicate", false)), "接受主线不幂等")

	var source := _legal_source()
	var checkpoint := {"valid": true, "checkpoint_id": "verify_checkpoint", "runtime_map_id": "expedition_01"}
	var claimed := BaseManager.claim_main_story_key(STORY_SCRIPT.KEY_RARE_EARTH, source, checkpoint)
	_expect(bool(claimed.get("success", false)) and not bool(claimed.get("duplicate", false)), "合法来源领取失败")
	var snapshot := BaseManager.get_main_story_snapshot()
	_expect(STORY_SCRIPT.key_state(snapshot, STORY_SCRIPT.KEY_RARE_EARTH) == "acquired", "领取后永久状态错误")
	_expect(snapshot.get("keys", {}).get(STORY_SCRIPT.KEY_RARE_EARTH, {}).get("acquired_source", {}) == source, "领取来源未记账")
	_expect(BaseManager.get_active_run_checkpoint() == checkpoint, "领取未与合法 checkpoint 一起保存")
	_expect(not BaseManager.get_pending_loadout_items().any(func(item): return str(item.get("id", "")) == STORY_SCRIPT.KEY_RARE_EARTH), "主线钥匙进入普通带入栏")

	var claimed_duplicate := BaseManager.claim_main_story_key(STORY_SCRIPT.KEY_RARE_EARTH, source, checkpoint)
	_expect(bool(claimed_duplicate.get("success", false)) and bool(claimed_duplicate.get("duplicate", false)), "领取不幂等")
	var before_deposit := BaseManager.get_main_story_snapshot()
	_expect(STORY_SCRIPT.installed_count(before_deposit) == 0, "领取后错误计入安装")
	_expect(not BaseManager.is_expedition_level_unlocked("expedition_03") if GameDesignConfig.expedition_unlock_policy("expedition_03") == "main_story" else true, "领取后错误解锁公馆")

	var deposited := BaseManager.deposit_main_story_key(STORY_SCRIPT.KEY_RARE_EARTH)
	_expect(bool(deposited.get("success", false)) and not bool(deposited.get("duplicate", false)), "安装主线钥匙失败")
	_expect(STORY_SCRIPT.key_state(BaseManager.get_main_story_snapshot(), STORY_SCRIPT.KEY_RARE_EARTH) == "deposited", "安装状态错误")
	var deposited_duplicate := BaseManager.deposit_main_story_key(STORY_SCRIPT.KEY_RARE_EARTH)
	_expect(bool(deposited_duplicate.get("success", false)) and bool(deposited_duplicate.get("duplicate", false)), "安装不幂等")

	BaseManager.load_base()
	var reloaded := BaseManager.get_main_story_snapshot()
	_expect(STORY_SCRIPT.key_state(reloaded, STORY_SCRIPT.KEY_RARE_EARTH) == "deposited", "重载丢失永久钥匙")
	_expect(STORY_SCRIPT.installed_count(reloaded) == 1, "重载安装计数错误")

func _verify_save_failure_and_stale_revision() -> void:
	BaseManager.data.main_story["accepted"] = false
	var before := BaseManager.get_main_story_snapshot()
	BaseManager.force_save_failure_for_test = true
	var failed_accept := BaseManager.accept_main_story()
	_expect(not bool(failed_accept.get("success", false)), "保存失败错误成功")
	_expect(BaseManager.get_main_story_snapshot() == before, "接受失败未整体回滚")
	var failed_deposit := BaseManager.deposit_main_story_key(STORY_SCRIPT.KEY_MANOR)
	_expect(not bool(failed_deposit.get("success", false)), "未领取钥匙安装错误成功")
	BaseManager.force_save_failure_for_test = false

	var stale := MANAGER_SCRIPT.new()
	stale.save_path = TEST_SAVE_PATH
	stale.data = DATA_SCRIPT.new()
	var stale_saved := stale.save_base("stale_should_not_overwrite")
	_expect(not stale_saved, "stale revision 错误覆盖权威档")
	_expect(STORY_SCRIPT.key_state(BaseManager.get_main_story_snapshot(), STORY_SCRIPT.KEY_RARE_EARTH) == "deposited", "stale save 改写了权威主线")
	stale.free()
	BaseManager.load_base()

func _verify_settlement_and_checkpoint_isolation() -> void:
	var story_before := BaseManager.get_main_story_snapshot()
	var checkpoint_before := BaseManager.get_active_run_checkpoint()
	BaseManager.force_save_failure_for_test = true
	var settlement := BaseManager.commit_run_settlement({
		"transaction_id": "verify_main_story_failed_settlement",
		"success": true,
		"kills": 3,
		"expedition_level_id": "expedition_01",
		"return_checkpoint": {},
	})
	_expect(not bool(settlement.get("success", false)), "失败结算错误成功")
	_expect(BaseManager.get_main_story_snapshot() == story_before, "失败结算改变永久主线")
	_expect(BaseManager.get_active_run_checkpoint() == checkpoint_before, "失败结算改变活动检查点")
	var clear_failed := BaseManager.clear_active_run_checkpoint("verify_failed_clear")
	_expect(not clear_failed, "主动清除保存失败错误成功")
	_expect(BaseManager.get_main_story_snapshot() == story_before, "失败清除改变永久主线")
	_expect(BaseManager.get_active_run_checkpoint() == checkpoint_before, "失败清除未回滚活动检查点")
	BaseManager.force_save_failure_for_test = false

func _legal_source() -> Dictionary:
	return {
		"level_id": "expedition_01",
		"boss_content_id": "boss_monitor002",
		"room_id": "f00_boss",
		"chest_id": "drop_f00_boss",
		"chest_tier": "advanced",
		"run_id": "expedition_01",
	}

func _remove_test_save() -> void:
	for suffix_value in ["", ".bak", ".tmp"]:
		var suffix := str(suffix_value)
		var path: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _restore_process_state() -> void:
	_remove_test_save()
	BaseManager.force_save_failure_for_test = original_force_save_failure
	BaseManager.save_path = original_save_path
	BaseManager.data = original_data

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("MAIN_STORY_PROGRESS_TESTS_DEFERRED_OK: rules, persistence, idempotency, rollback, reload, and settlement isolation are covered")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
