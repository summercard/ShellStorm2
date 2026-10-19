extends Node
## 实拍：在 99F 基地里走到原「怪物档案室」那个位点，按 E 打开武器改造台。
##
## 只验"能不能真的打开、打开后长什么样"。规则与表现分别由
## `verify_workbench_menu_entry` / `verify_synthesis_gate` 覆盖。
## 只在窗口模式产出 PNG —— `--headless` 下 `frame_post_draw` 不触发。

const TOWER := preload("res://scenes/TowerDescent3D.tscn")
const OUT_DIR := "res://outputs/verification"


func _ready() -> void:
	var world := TOWER.instantiate() as TowerDescent3D
	world.test_mode = true
	add_child(world)
	for _frame in 16:
		await get_tree().process_frame

	var forge: BaseFacility3D = null
	for node in get_tree().get_nodes_in_group("base_facility"):
		var facility := node as BaseFacility3D
		if facility != null and facility.facility_id == "weapon_forge":
			forge = facility
	if forge == null:
		print("CAPTURE_WORKBENCH_ENTRY_FAIL 没找到 weapon_forge")
		get_tree().quit(1)
		return

	# ① 站在它前面看这台机器（确认名字/颜色/位置没被改动误伤）
	var forward := (forge.global_basis * Vector3.FORWARD).normalized()
	world.player.global_position = forge.global_position + forward * 3.2 + Vector3.UP * 0.2
	world.player.velocity = Vector3.ZERO
	# 面向设施：玩家朝向与 forward 相反
	world.player.look_at(forge.global_position + Vector3.UP * 1.4, Vector3.UP)
	for _frame in 8:
		await get_tree().process_frame
	await _capture("workbench_facility_in_base")

	# ② 真按一次 E
	world.call("_on_facility_activated", forge)
	for _frame in 10:
		await get_tree().process_frame
	await _capture("workbench_panel_opened")

	# ③ 切到合成目录页（确认第二页签在基地里也正常）
	var menu = world.get("_active_facility_menu")
	if menu != null and menu.has_method("get_panel"):
		var panel = menu.call("get_panel")
		if panel != null:
			panel.call("_switch_page", "catalog")
			for _frame in 6:
				await get_tree().process_frame
			await _capture("workbench_panel_catalog")
	get_tree().quit(0)


func _capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(path)
	if err == OK:
		print("CAPTURE_WORKBENCH_ENTRY_OK %s %dx%d" % [path, image.get_width(), image.get_height()])
	else:
		print("CAPTURE_WORKBENCH_ENTRY_FAIL %s err=%d" % [path, err])
