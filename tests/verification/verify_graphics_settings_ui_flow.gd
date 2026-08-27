extends Node
## 高档画质、太阳间接漫反射、ESC画面设置、抗锯齿档位与0键性能面板验收。

const PAUSE_SCENE: PackedScene = preload("res://assets/art/ui/pause_3d/ui_pause_overlay_screen_v001.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var original := GraphicsSettingsManager.get_settings_snapshot()
	_verify_environment_switches(failures)
	_verify_indirect_diffuse_quality_modes(failures)
	_verify_antialiasing_modes(failures)
	_verify_shadow_quality_modes(failures)
	await _verify_pause_and_performance_ui(failures)
	for key in original.keys():
		GraphicsSettingsManager.set_value(str(key), original[key], false)
	_finish(failures)


func _verify_environment_switches(failures: Array[String]) -> void:
	var environment := Environment.new()
	for key in ["bloom", "ssao", "ssil", "ssr", "volumetric_fog", "distance_fog", "color_grading"]:
		GraphicsSettingsManager.set_value(key, false, false)
	GraphicsSettingsManager.apply_to_environment(environment)
	var property_map := {
		"bloom": "glow_enabled",
		"ssao": "ssao_enabled",
		"ssil": "ssil_enabled",
		"ssr": "ssr_enabled",
		"volumetric_fog": "volumetric_fog_enabled",
		"distance_fog": "fog_enabled",
		"color_grading": "adjustment_enabled",
	}
	for key in property_map.keys():
		if bool(environment.get(property_map[key])):
			failures.append("%s关闭后Environment仍保持启用" % key)
		GraphicsSettingsManager.set_value(str(key), true, false)
		GraphicsSettingsManager.apply_to_environment(environment)
		if not bool(environment.get(property_map[key])):
			failures.append("%s开启后Environment没有生效" % key)


func _verify_indirect_diffuse_quality_modes(failures: Array[String]) -> void:
	var environment := Environment.new()
	var expected := {
		"low": {"cascades": 2, "max_distance": 90.0},
		"medium": {"cascades": 3, "max_distance": 140.0},
		"high": {"cascades": 4, "max_distance": 204.8},
	}
	var cell_sizes: Dictionary = {}
	for mode in GraphicsSettingsManager.INDIRECT_DIFFUSE_QUALITY_MODES:
		GraphicsSettingsManager.set_value("indirect_diffuse_quality", mode, false)
		GraphicsSettingsManager.apply_to_environment(environment)
		if GraphicsSettingsManager.get_indirect_diffuse_quality() != mode:
			failures.append("太阳间接漫反射档位没有保存：%s" % mode)
		if not bool(environment.get("sdfgi_enabled")):
			failures.append("太阳间接漫反射在%s档被关闭" % mode)
		if not bool(environment.get("sdfgi_read_sky_light")):
			failures.append("太阳间接漫反射在%s档没有读取天空光" % mode)
		if int(environment.get("sdfgi_cascades")) != int(expected[mode]["cascades"]):
			failures.append("太阳间接漫反射%s档级联数量不正确" % mode)
		cell_sizes[mode] = float(environment.get("sdfgi_min_cell_size"))
		if not is_equal_approx(
			float(environment.get("sdfgi_max_distance")),
			float(expected[mode]["max_distance"])
		):
			failures.append("太阳间接漫反射%s档覆盖距离不正确" % mode)
	if not (
		float(cell_sizes["low"]) > float(cell_sizes["medium"])
		and float(cell_sizes["medium"]) > float(cell_sizes["high"])
	):
		failures.append("太阳间接漫反射体素精度没有按低→中→高逐级提升")
	if GraphicsSettingsManager.set_value("sdfgi", false, false):
		failures.append("旧版SDFGI关闭入口仍然可用")
	if not GraphicsSettingsManager.is_enabled("sdfgi"):
		failures.append("SDFGI兼容查询没有保持开启")


func _verify_antialiasing_modes(failures: Array[String]) -> void:
	var viewport := get_tree().root
	for mode in GraphicsSettingsManager.AA_MODES:
		GraphicsSettingsManager.set_value("anti_aliasing", mode, false)
		match mode:
			"off":
				if viewport.msaa_3d != Viewport.MSAA_DISABLED or viewport.use_taa:
					failures.append("关闭抗锯齿后Viewport仍启用AA")
			"fxaa":
				if viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_FXAA:
					failures.append("FXAA档没有写入Viewport")
			"msaa_2x":
				if viewport.msaa_3d != Viewport.MSAA_2X:
					failures.append("MSAA 2x档没有写入Viewport")
			"msaa_4x":
				if viewport.msaa_3d != Viewport.MSAA_4X:
					failures.append("MSAA 4x档没有写入Viewport")
			"msaa_8x":
				if viewport.msaa_3d != Viewport.MSAA_8X:
					failures.append("MSAA 8x档没有写入Viewport")
			"taa":
				if not viewport.use_taa:
					failures.append("TAA档没有写入Viewport")


func _verify_shadow_quality_modes(failures: Array[String]) -> void:
	var expected_sizes := {"low": 1024, "medium": 2048, "high": 4096}
	for mode in GraphicsSettingsManager.SHADOW_QUALITY_MODES:
		GraphicsSettingsManager.set_value("shadow_quality", mode, false)
		if GraphicsSettingsManager.get_shadow_quality() != mode:
			failures.append("动态阴影档位没有保存：%s" % mode)
		if GraphicsSettingsManager.get_shadow_atlas_size() != int(expected_sizes[mode]):
			failures.append("动态阴影图集尺寸不正确：%s" % mode)
		if not GraphicsSettingsManager.is_enabled("shadows"):
			failures.append("动态阴影在%s档被关闭，破坏玩法约束" % mode)
	if GraphicsSettingsManager.set_value("shadows", false, false):
		failures.append("旧版动态阴影关闭入口仍然可用")


func _verify_pause_and_performance_ui(failures: Array[String]) -> void:
	var pause := PAUSE_SCENE.instantiate() as PauseMenu3D
	add_child(pause)
	await get_tree().process_frame
	var graphics_page := pause.get_node("Center/Panel/Margin/GraphicsPage") as Control
	var main_page := pause.get_node("Center/Panel/Margin/MainPage") as Control
	var aa_option := pause.get_node("Center/Panel/Margin/GraphicsPage/AASection/AAOption") as OptionButton
	var shadow_option := pause.get_node("Center/Panel/Margin/GraphicsPage/Scroll/Grid/Shadows/ShadowOption") as OptionButton
	var indirect_option := pause.get_node("Center/Panel/Margin/GraphicsPage/Scroll/Grid/IndirectDiffuse/QualityOption") as OptionButton
	var grid := pause.get_node("Center/Panel/Margin/GraphicsPage/Scroll/Grid") as GridContainer
	if aa_option.item_count != 6:
		failures.append("抗锯齿界面没有提供6档调节")
	if grid.get_child_count() != 9:
		failures.append("画面设置没有提供完整的9项效果控制")
	for child in grid.get_children():
		if child.name not in ["Shadows", "IndirectDiffuse"] and not child is CheckButton:
			failures.append("画面效果项不是可开关按钮：%s" % child.name)
	if shadow_option.item_count != 3:
		failures.append("动态阴影没有提供向下两级的三级调节")
	if indirect_option.item_count != 3:
		failures.append("太阳间接漫反射没有提供高中低三级调节")
	pause.set_paused(true)
	pause.call("_show_graphics_page")
	if not graphics_page.visible or main_page.visible:
		failures.append("ESC暂停菜单不能进入画面设置页")
	if not pause.try_consume_pause_input() or graphics_page.visible:
		failures.append("画面设置页按ESC不能返回暂停主页")
	var overlay := pause.get_node("PerformanceOverlay") as PerformanceOverlay
	var event := InputEventKey.new()
	event.keycode = KEY_0
	event.pressed = true
	overlay.call("_unhandled_input", event)
	if not overlay.visible:
		failures.append("0键不能打开性能面板")
	else:
		if not Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).intersects(overlay.get_global_rect()):
			failures.append("0键性能面板已开启但位于屏幕可视区域之外")
		var metrics := overlay.get_node("Metrics") as Label
		if "FPS" not in metrics.text or "Draw Call" not in metrics.text or "渲染器" not in metrics.text:
			failures.append("性能面板缺少FPS、Draw Call或渲染器指标")
	overlay.call("_unhandled_input", event)
	if overlay.visible:
		failures.append("再次按0不能关闭性能面板")
	pause.set_paused(false)
	pause.queue_free()
	await get_tree().process_frame


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("GRAPHICS_SETTINGS_UI_OK: sunlight indirect diffuse stays enabled at 3 quality levels, 7 switches, locked 3-tier gameplay shadows, 6 AA modes, ESC graphics page and 0 performance overlay pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
