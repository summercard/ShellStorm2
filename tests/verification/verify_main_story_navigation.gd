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
	if not OS.get_environment("HOLOGRAM_CENTERED_QA_DIR").is_empty():
		await _capture_visual_states()
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
	for lock: Node3D in city.lock_nodes:
		_expect(lock.position.is_equal_approx(Vector3(0, 0, 0.25)), "锁头未居中到关卡牌面")
		_expect(lock.scale.is_equal_approx(Vector3.ONE * 1.30), "锁头未按1.30倍放大")
	for id in ["expedition_02", "expedition_04"]:
		var scale_value := float(city.SITE_ANCHORS[id]["marker_scale"])
		_expect(is_equal_approx(scale_value, 0.95), "后排图标未由0.78增至0.95")
		_expect(scale_value <= float(city.SITE_ANCHORS["expedition_01"]["marker_scale"]) and scale_value <= float(city.SITE_ANCHORS["expedition_03"]["marker_scale"]), "后排图标比前排更大")
	var mode := {"locked": true}
	city.entry_state_provider = func(_id: String) -> String: return "locked" if bool(mode.locked) else "open"
	city.refresh_entry_states()
	_expect(city.labels[0].position.y < -1.1 and city.entry_hints[0].position.y < city.labels[0].position.y, "锁定文字未让开中心大锁")
	_expect(city.entry_badges[0].position.y > 1.1, "锁定序号未让开中心大锁")
	mode.locked = false
	city.refresh_entry_states()
	_expect(city.labels[0].position.is_equal_approx(Vector3(0, 0.22, 0.11)), "解锁后名称未回牌内")
	_expect(city.entry_hints[0].position.is_equal_approx(Vector3(0, -0.48, 0.11)), "解锁后提示未回牌内")
	_expect(city.entry_badges[0].position.is_equal_approx(Vector3(0, 0.75, 0.11)), "解锁后序号未回牌内")
	city.queue_free()

func _capture_visual_states() -> void:
	if DisplayServer.get_name() == "headless":
		_expect(false, "居中锁头截图必须使用真实渲染器")
		return
	var output := OS.get_environment("HOLOGRAM_CENTERED_QA_DIR")
	BaseManager.data = DATA_SCRIPT.new()
	BaseManager.save_path = "user://centered_locks_fixture.json"
	var host := Node3D.new()
	add_child(host)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.001, 0.003, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.25, 0.4)
	env.ambient_light_energy = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	host.add_child(environment)
	var platform := load("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/hologram_terminal_platform/hologram_terminal_platform_root_top3d.tscn").instantiate() as BaseFacility3D
	host.add_child(platform)
	var camera := Camera3D.new()
	host.add_child(camera)
	var anchor: Vector3 = platform.call("get_hologram_anchor")
	camera.position = anchor + Vector3(0, 8, 6)
	camera.look_at(anchor)
	camera.make_current()
	var menu := load("res://scenes/RogueMapSelectMenu.tscn").instantiate() as RogueMapSelectMenu
	menu.set_facility(platform)
	host.add_child(menu)
	await get_tree().create_timer(5.0).timeout
	_expect(menu._state == "active", "真实选关界面未完成展开")
	# 菜单接管后必须用它的正式近景相机测量，原玩法相机已不再渲染。
	camera = menu._camera
	menu._focus = -1
	await get_tree().create_timer(0.7).timeout
	var captures: Array[Dictionary] = []
	for installed in [0, 1]:
		if installed == 1:
			BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {"mq_key_rare_earth": {"state": "deposited"}}}
			menu._city.refresh_entry_states()
			menu._city.set_installed_count(installed)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var path := output.path_join("map_%dof4_centered_locks.png" % installed)
		_expect(get_viewport().get_texture().get_image().save_png(path) == OK, "选关实拍保存失败")
		var geometry: Array[Dictionary] = []
		var front_width := INF
		var rear_width := 0.0
		for i in menu.LEVEL_IDS.size():
			var id: String = menu.LEVEL_IDS[i]
			var marker: Node3D = menu._city.markers[i]
			var lock: Node3D = menu._city.lock_nodes[i]
			var center := camera.unproject_position(marker.to_global(Vector3(0, 0, 0.25)))
			var lock_center := camera.unproject_position(lock.global_position)
			var left := camera.unproject_position(marker.to_global(Vector3(-1.6, 0, 0)))
			var right := camera.unproject_position(marker.to_global(Vector3(1.6, 0, 0)))
			var width := left.distance_to(right)
			var body_left := camera.unproject_position(lock.to_global(Vector3(-0.62, -0.23, 0)))
			var body_right := camera.unproject_position(lock.to_global(Vector3(0.62, -0.23, 0)))
			if id in ["expedition_01", "expedition_03"]:
				front_width = minf(front_width, width)
			else:
				rear_width = maxf(rear_width, width)
			_expect(center.distance_to(lock_center) < 1.0, "大锁与牌面屏幕中心偏离")
			_expect(get_viewport().get_visible_rect().grow(-20).has_point(center), "图标中心超出视口")
			_expect(menu._pick(center) == i, "图标放大后鼠标命中错误")
			geometry.append({"id": id, "width_px": width, "body_width_px": body_left.distance_to(body_right), "marker_center": str(center), "lock_center": str(lock_center), "lock_visible": lock.is_visible_in_tree(), "name_position": str(menu._city.labels[i].position)})
		_expect(rear_width <= front_width, "透视后后排牌面大于前排")
		var snapshot: Dictionary = menu._city.get_entry_visual_snapshot()
		_expect((snapshot.locked_ids as Array).size() == 3 - installed, "安装前后锁头数量错误")
		_expect(menu.entry_state("expedition_03") == (menu.ENTRY_OPEN if installed == 1 else menu.ENTRY_LOCKED), "公馆安装前后权限改变错误")
		captures.append({"installed": installed, "image": path, "geometry": geometry, "snapshot": snapshot})
	var file := FileAccess.open(output.path_join("visual_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures": captures, "failures": failures, "display_server": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "user_data_dir": OS.get_user_data_dir(), "fixture": true, "scope": "真实设施与正式菜单，不是完整基地层贯通"}, "  "))
	file.close()
	menu.request_close()
	await get_tree().create_timer(3.8).timeout
	host.queue_free()
	await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
