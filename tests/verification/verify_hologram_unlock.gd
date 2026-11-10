extends Node
const MANAGER = preload("res://src/base/BaseManager.gd")
const FIXTURE = preload("res://tests/verification/helpers/hologram_city_fixture.gd")
const STORY = preload("res://src/narrative/MainStoryProgress.gd")
const NAV_IDS := ["expedition_01", "expedition_03", "expedition_02", "expedition_04"]
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _ready() -> void:
	_cleanup()
	var original_data: BaseData = BaseManager.data
	var original_pending: String = GameDesignConfig.pending_expedition_level_id
	GameDesignConfig.pending_expedition_level_id = ""
	# Runner 在 Autoload 前隔离用户目录；这里另外清除内存调试覆盖。
	BaseManager._debug_unlock_overrides_loaded = true
	BaseManager._debug_unlock_overrides.clear()
	var manager = MANAGER.new()
	manager.save_path = "user://unlock_probe.json"
	manager.data = BaseData.new()
	manager._debug_unlock_overrides_loaded = true
	manager._debug_unlock_overrides.clear()
	_check_permissions(manager, false, false, false, "新档")
	var ambiguous := BaseData.from_dict({"successful_extractions": 10})
	check(not ambiguous.expedition_02_unlocked and ambiguous.expedition_unlocked_levels.is_empty(), "历史撤离次数推导了地图权限")
	check(STORY.installed_count(ambiguous.main_story) == 0, "历史撤离次数补发了钥匙")
	for entry in [{"id":"death", "success":false, "level":"expedition_01"}, {"id":"test99", "success":true, "level":"99"}, {"id":"tower", "success":true, "level":""}]:
		var result: Dictionary = manager.commit_run_settlement({"transaction_id":entry.id, "success":entry.success, "expedition_level_id":entry.level})
		check(result.success, "无关结算失败：%s" % entry.id)
		_check_permissions(manager, false, false, false, "无关结算 " + entry.id)
	var request := {"transaction_id":"clear01", "success":true, "expedition_level_id":"expedition_01"}
	var before: Dictionary = manager.data._to_dict().duplicate(true)
	manager.force_save_failure_for_test = true
	check(not manager.commit_run_settlement(request).success, "保存失败仍接受01结算")
	check(manager.data._to_dict() == before, "失败结算未整体回滚")
	_check_permissions(manager, false, false, false, "结算保存失败")
	manager.force_save_failure_for_test = false
	check(manager.commit_run_settlement(request).success, "01结算重试失败")
	_check_permissions(manager, false, false, false, "01成功撤离不解锁其他目标")
	check(not manager.data.expedition_02_unlocked and manager.data.expedition_unlocked_levels.is_empty(), "01成功撤离写入旧解锁标志")
	var revision: int = manager.data.save_revision
	var duplicate: Dictionary = manager.commit_run_settlement(request)
	check(duplicate.success and duplicate.duplicate and manager.data.save_revision == revision, "重复结算改变存档")
	manager.load_base()
	_check_permissions(manager, false, false, false, "结算重载")
	duplicate = manager.commit_run_settlement(request)
	check(duplicate.success and duplicate.duplicate and manager.data.save_revision == revision, "重载后重复结算改变存档")
	BaseManager.data = manager.data
	var locked := FIXTURE.create(self)
	check(locked.menu.LEVEL_IDS == NAV_IDS, "新档四入口顺序错误：%s" % [locked.menu.LEVEL_IDS])
	check(GameDesignConfig.expedition_level("99").get("nav_visibility", "") == "hidden" and not locked.menu.LEVEL_IDS.has("99"), "测试99未隐藏")
	check(locked.menu.entry_state("expedition_01") == locked.menu.ENTRY_OPEN, "新档01未开放")
	locked.menu._progress = 1.0
	locked.menu._process(0.0)
	for level_id in ["expedition_03", "expedition_02", "expedition_04"]:
		check(locked.menu.entry_state(level_id) == locked.menu.ENTRY_LOCKED, "新档入口未锁定：" + level_id)
		var index: int = locked.menu.LEVEL_IDS.find(level_id)
		check(locked.menu._city.entry_hints[index].text.begins_with("尚未解锁"), "锁定入口牌面错误：" + level_id)
		locked.menu._enter_level(level_id)
		check(not locked.menu._departing and GameDesignConfig.pending_expedition_level_id.is_empty(), "锁定入口绕过门禁：" + level_id)
		check(locked.menu._city.status.text.contains("尚未解锁"), "锁定入口缺拒绝反馈：" + level_id)
	locked.host.queue_free()
	await get_tree().process_frame

	var key_id: String = STORY.KEY_RARE_EARTH
	var source := {"level_id":"expedition_01", "boss_content_id":"boss_monitor002", "room_id":"f00_boss", "chest_id":"drop_f00_boss", "chest_tier":"advanced", "run_id":"expedition_01"}
	before = manager.data._to_dict().duplicate(true)
	manager.force_save_failure_for_test = true
	check(not manager.claim_main_story_key(key_id, source).success, "领取保存失败仍成功")
	check(manager.data._to_dict() == before, "领取保存失败泄漏永久状态")
	_check_permissions(manager, false, false, false, "领取保存失败")
	manager.force_save_failure_for_test = false
	check(manager.claim_main_story_key(key_id, source).success, "稀土钥匙领取重试失败")
	check(STORY.key_state(manager.get_main_story_snapshot(), key_id) == "acquired", "领取未写acquired")
	_check_permissions(manager, false, false, false, "acquired不解锁公馆")
	revision = manager.data.save_revision
	duplicate = manager.claim_main_story_key(key_id, source)
	check(duplicate.success and duplicate.duplicate and manager.data.save_revision == revision, "重复领取改变存档")
	manager.load_base()
	check(STORY.key_state(manager.get_main_story_snapshot(), key_id) == "acquired", "重载丢失acquired")
	_check_permissions(manager, false, false, false, "领取重载仍锁定")
	BaseManager.data = manager.data
	var acquired := FIXTURE.create(self)
	check(acquired.menu.entry_state("expedition_03") == acquired.menu.ENTRY_LOCKED, "acquired牌面错误开放公馆")
	acquired.menu._enter_level("expedition_03")
	check(not acquired.menu._departing and GameDesignConfig.pending_expedition_level_id.is_empty(), "acquired允许出发公馆")
	before = manager.data._to_dict().duplicate(true)
	var disk_before := FileAccess.get_file_as_string(manager.save_path)
	manager.force_save_failure_for_test = true
	check(not manager.deposit_main_story_key(key_id).success, "安装保存失败仍成功")
	check(manager.data._to_dict() == before, "安装保存失败未整体回滚")
	check(FileAccess.get_file_as_string(manager.save_path) == disk_before, "安装失败修改磁盘")
	check(acquired.menu.entry_state("expedition_03") == acquired.menu.ENTRY_LOCKED, "安装失败泄漏公馆开放")
	_check_permissions(manager, false, false, false, "安装保存失败")
	manager.force_save_failure_for_test = false
	manager.load_base()
	check(STORY.key_state(manager.get_main_story_snapshot(), key_id) == "acquired", "失败安装重载未保持acquired")
	_check_permissions(manager, false, false, false, "失败安装重载")
	BaseManager.data = manager.data
	check(manager.deposit_main_story_key(key_id).success, "安装稀土钥匙重试失败")
	check(STORY.key_state(manager.get_main_story_snapshot(), key_id) == "deposited", "安装未写deposited")
	_check_permissions(manager, true, false, false, "稀土安装只开公馆")
	check(acquired.menu.entry_state("expedition_03") == acquired.menu.ENTRY_OPEN, "deposit后公馆未open")
	check(acquired.menu._entry_hint_text("expedition_03").begins_with("点击进入"), "deposit后公馆牌面不可进")
	revision = manager.data.save_revision
	duplicate = manager.deposit_main_story_key(key_id)
	check(duplicate.success and duplicate.duplicate and manager.data.save_revision == revision, "重复安装改变存档")
	manager.load_base()
	check(STORY.key_state(manager.get_main_story_snapshot(), key_id) == "deposited", "重载丢失deposited")
	_check_permissions(manager, true, false, false, "安装重载")
	duplicate = manager.deposit_main_story_key(key_id)
	check(duplicate.success and duplicate.duplicate and manager.data.save_revision == revision, "重载后重复安装改变存档")
	acquired.host.queue_free()
	await get_tree().process_frame

	# 兼容明确旧档权限；单独从旧档起跑，不覆盖前段的高revision存档。
	_cleanup()
	manager.data = BaseData.from_dict({"expedition_02_unlocked": true})
	_check_permissions(manager, false, true, false, "旧明确02权限")
	check(STORY.installed_count(manager.get_main_story_snapshot()) == 0, "旧地图权限补发钥匙")
	check(manager.save_base("legacy_explicit_unlock"), "旧权限保存失败")
	manager.load_base()
	_check_permissions(manager, false, true, false, "旧权限重载")
	BaseManager.data = manager.data
	var unlocked := FIXTURE.create(self)
	check(unlocked.menu.LEVEL_IDS == NAV_IDS, "旧档四入口顺序错误：%s" % [unlocked.menu.LEVEL_IDS])
	check(unlocked.menu.entry_state("expedition_02") == unlocked.menu.ENTRY_OPEN, "旧明确02权限未兼容")
	unlocked.menu._progress = 1.0
	unlocked.menu._process(0.0)
	# 未登记目标的失败断言保留；另用真实04覆盖有权限但未制作的分支。
	var missing_id := "expedition_99_missing"
	check(unlocked.menu.entry_state(missing_id) == unlocked.menu.ENTRY_COMING_SOON, "未登记id未判尚未开放")
	check(unlocked.menu._entry_hint_text(missing_id) == "尚未开放", "未登记id牌面错误")
	unlocked.menu._enter_level(missing_id)
	check(not unlocked.menu._departing and GameDesignConfig.pending_expedition_level_id.is_empty(), "未登记入口改变路由")
	check(unlocked.menu._city.status.text.contains("尚未开放"), "未登记入口缺反馈")
	manager.data.main_story["keys"][STORY.KEY_HOTEL] = {"state":"deposited"}
	check(unlocked.menu.entry_state("expedition_04") == unlocked.menu.ENTRY_COMING_SOON, "04有权限但无场景未判尚未开放")
	check(unlocked.menu._entry_hint_text("expedition_04") == "尚未开放", "04无场景牌面错误")
	var pending_before: String = GameDesignConfig.pending_expedition_level_id
	unlocked.menu._enter_level("expedition_04")
	check(not unlocked.menu._departing and unlocked.menu._pending_level_id.is_empty() and GameDesignConfig.pending_expedition_level_id == pending_before, "未制作04出发或改路由")
	check(unlocked.menu._city.status.text.contains("尚未开放"), "04无场景缺反馈")
	unlocked.host.queue_free()
	await get_tree().process_frame
	BaseManager.data = original_data
	GameDesignConfig.pending_expedition_level_id = original_pending
	manager.free()
	_cleanup()
	for failure in failures: printerr("FAIL: " + failure)
	print("HOLOGRAM_UNLOCK_OK" if failures.is_empty() else "HOLOGRAM_UNLOCK_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_permissions(manager: Node, manor: bool, hotel: bool, unknown: bool, stage: String) -> void:
	check(manager.is_expedition_level_unlocked("expedition_01"), stage + "：01未开放")
	check(manager.is_expedition_level_unlocked("expedition_03") == manor, stage + "：03权限错误")
	check(manager.is_expedition_level_unlocked("expedition_02") == hotel, stage + "：02权限错误")
	check(manager.is_expedition_level_unlocked("expedition_04") == unknown, stage + "：04权限错误")

func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = "user://unlock_probe.json" + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
