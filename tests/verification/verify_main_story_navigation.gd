extends Node
## 主线四地图导航与红色电子锁的无头契约验证。
## 不启动正式用户场景；只验证配置、权限门禁、未知区域与城市锁头快照。

const MENU_SCRIPT := preload("res://scenes/RogueMapSelectMenu.gd")
const CITY_SCRIPT := preload("res://src/ui/HologramCity3D.gd")
const DATA_SCRIPT := preload("res://src/base/BaseData.gd")

var failures: Array[String] = []
var original_data: BaseData

func _ready() -> void:
	original_data = BaseManager.data
	BaseManager.data = DATA_SCRIPT.new()
	BaseManager._debug_unlock_overrides_loaded = true
	BaseManager._debug_unlock_overrides.clear()
	_verify_config_and_navigation()
	_verify_new_save_permissions_and_locks()
	_verify_deposited_key_unlocks()
	_verify_unknown_area_never_starts()
	await _verify_lock_visual_contract()
	BaseManager.data = original_data
	for failure in failures:
		printerr("FAIL: " + failure)
	print("MAIN_STORY_NAVIGATION_OK" if failures.is_empty() else "MAIN_STORY_NAVIGATION_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_config_and_navigation() -> void:
	var ids := GameDesignConfig.expedition_nav_order()
	_expect(ids == ["expedition_01", "expedition_03", "expedition_02", "expedition_04", "99"], "配置主线排位错误")
	var menu := MENU_SCRIPT.new() as RogueMapSelectMenu
	menu._refresh_level_ids()
	_expect(menu.LEVEL_IDS == ["expedition_01", "expedition_03", "expedition_02", "expedition_04"], "正式导航包含99或四入口顺序错误")
	_expect(GameDesignConfig.expedition_level("99").get("nav_visibility", "") == "hidden", "99未标记hidden")
	_expect(GameDesignConfig.expedition_level("expedition_01").get("nav_visibility", "") == "always", "01可见性错误")
	_expect(GameDesignConfig.expedition_level("expedition_03").get("run_id", "") == "expedition_03", "公馆run_id被修改")
	_expect(GameDesignConfig.expedition_level("expedition_03").get("scene_3d", "") == "res://scenes/ExpeditionLevel03_3D.tscn", "公馆场景路径被修改")
	menu.free()

func _verify_new_save_permissions_and_locks() -> void:
	var menu := MENU_SCRIPT.new() as RogueMapSelectMenu
	menu._refresh_level_ids()
	_expect(menu.entry_state("expedition_01") == menu.ENTRY_OPEN, "新档01未开放")
	_expect(menu.entry_state("expedition_03") == menu.ENTRY_LOCKED, "新档公馆未锁定")
	_expect(menu.entry_state("expedition_02") == menu.ENTRY_LOCKED, "新档旅馆未锁定")
	_expect(menu.entry_state("expedition_04") == menu.ENTRY_LOCKED, "新档未知区域未先显示锁定")
	menu._state = "active"
	menu._enter_level("expedition_03")
	menu._enter_level("expedition_02")
	menu._enter_level("expedition_04")
	_expect(not menu._departing, "锁定入口可通过直接出发绕过")
	_expect(GameDesignConfig.pending_expedition_level_id.is_empty(), "锁定入口写入待进入关卡")
	menu.free()

func _verify_deposited_key_unlocks() -> void:
	BaseManager.data.main_story = {
		"schema_version": 1,
		"accepted": true,
		"keys": {
			"mq_key_rare_earth": {"state": "deposited"},
			"mq_key_manor": {"state": "deposited"},
		}
	}
	var menu := MENU_SCRIPT.new() as RogueMapSelectMenu
	_expect(menu.entry_state("expedition_03") == menu.ENTRY_OPEN, "稀土钥匙deposit后公馆未开放")
	_expect(menu.entry_state("expedition_02") == menu.ENTRY_OPEN, "公馆钥匙deposit后旅馆未开放")
	_expect(menu.entry_state("expedition_04") == menu.ENTRY_LOCKED, "未知区域缺旅馆钥匙时未锁定")
	_expect(menu._main_story_deposited_count() == 2, "中心塔安装计数未来自deposited")
	menu.free()

func _verify_unknown_area_never_starts() -> void:
	BaseManager.data.main_story["keys"]["mq_key_hotel"] = {"state": "deposited"}
	var menu := MENU_SCRIPT.new() as RogueMapSelectMenu
	_expect(menu.entry_state("expedition_04") == menu.ENTRY_COMING_SOON, "未知区域有权限但无场景未判coming_soon")
	menu._state = "active"
	menu._enter_level("expedition_04")
	_expect(not menu._departing, "未知区域场景为空仍允许出发")
	_expect(GameDesignConfig.pending_expedition_level_id.is_empty(), "未知区域回退或写入了其他待进入关卡")
	menu.free()

func _verify_lock_visual_contract() -> void:
	_expect(CITY_SCRIPT.LOCK_RED.r > CITY_SCRIPT.LOCK_RED.g * 10.0, "锁头不是红色材质")
	_expect(CITY_SCRIPT.LOCK_SCAN_SPEED > 0.0, "锁头扫描效果未配置")
	var city := CITY_SCRIPT.new()
	_expect(city.has_method("get_entry_visual_snapshot"), "城市缺少锁头快照接口")
	_expect(city.has_method("refresh_entry_states"), "城市缺少状态刷新接口")
	city.level_ids = ["expedition_01", "expedition_03", "expedition_02", "expedition_04"]
	add_child(city)
	await get_tree().process_frame
	_expect(city.lock_nodes.size() == 4, "四正式入口未生成四个几何锁头")
	_expect(city.get_entry_visual_snapshot().get("lock_geometry", 0) == 4, "锁头快照未暴露几何数量")
	city.queue_free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
