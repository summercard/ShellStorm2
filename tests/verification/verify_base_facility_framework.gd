extends Node

const FacilityCatalog = preload("res://src/base/BaseFacilityCatalog.gd")
const FacilityService = preload("res://src/base/BaseFacilityService.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	_verify_catalog(failures)
	_verify_query_and_atomic_command(failures)
	await _verify_world_and_terminal(failures)
	_finish(failures)


func _verify_catalog(failures: Array[String]) -> void:
	var definitions := FacilityCatalog.all_definitions()
	if definitions.size() != 11:
		failures.append("正式基地设施目录不是 11 项")
	var ids: Dictionary = {}
	var all_text := ""
	for definition in definitions:
		var facility_id := str(definition.get("facility_id", ""))
		if facility_id.is_empty() or ids.has(facility_id):
			failures.append("设施 ID 为空或重复：%s" % facility_id)
		ids[facility_id] = true
		all_text += str(definition.get("display_name", ""))
		var action_kind := str(definition.get("action_kind", ""))
		if action_kind not in [FacilityCatalog.ACTION_INFO, FacilityCatalog.ACTION_MENU, FacilityCatalog.ACTION_SCENE]:
			failures.append("设施动作类型无效：%s" % facility_id)
		var action_path := str(definition.get("action_path", ""))
		if action_kind != FacilityCatalog.ACTION_INFO and not ResourceLoader.exists(action_path, "PackedScene"):
			failures.append("设施动作场景不存在：%s" % facility_id)
	for retired_name in ["资源转换", "废品回收", "黑市"]:
		if retired_name in all_text:
			failures.append("正式设施目录仍包含旧建筑：%s" % retired_name)


func _verify_query_and_atomic_command(failures: Array[String]) -> void:
	var data := BaseData.new()
	data.extraction_points = 500
	data.workshop_level = 2
	data.blueprint_gunbody_tier = 1
	data.blueprint_bullet_tier = 2
	data.blueprint_attachment_tier = 3
	var snapshots := FacilityService.get_all_snapshots(data)
	if snapshots.size() != 11:
		failures.append("统一设施查询没有返回 11 个快照")
	for snapshot in snapshots:
		if str(snapshot.get("summary", "")).is_empty():
			failures.append("设施缺少玩家可读摘要：%s" % str(snapshot.get("facility_id", "")))
		if not bool(snapshot.get("available", false)):
			failures.append("基础设施在新档中不可用：%s" % str(snapshot.get("facility_id", "")))

	var result := FacilityService.apply_upgrade("weapon_workshop", data, 150)
	if not bool(result.get("success", false)) or data.workshop_level != 3 or data.extraction_points != 350:
		failures.append("设施升级没有同时修改资源与等级")
	FacilityService.rollback_upgrade(result, data)
	if data.workshop_level != 2 or data.extraction_points != 500:
		failures.append("设施升级回滚没有同时恢复资源与等级")
	var rejected := FacilityService.apply_upgrade("fate_collection", data, 100)
	if bool(rejected.get("success", false)) or data.extraction_points != 500:
		failures.append("不可升级设施错误地扣除了资源")


func _verify_world_and_terminal(failures: Array[String]) -> void:
	var base_scene := load("res://scenes/BaseWorld3D.tscn") as PackedScene
	var base_world := base_scene.instantiate() as BaseWorld3D
	add_child(base_world)
	await get_tree().process_frame
	var world_ids: Dictionary = {}
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if not facility is BaseFacility3D or not base_world.is_ancestor_of(facility):
			continue
		if facility.facility_id.is_empty() or world_ids.has(facility.facility_id):
			failures.append("3D 基地设施 ID 为空或重复：%s" % facility.facility_id)
		world_ids[facility.facility_id] = true
		var snapshot: Dictionary = facility.get_snapshot()
		if str(snapshot.get("summary", "")).is_empty() or "\n" not in facility.name_label.text:
			failures.append("3D 设施牌没有显示实时摘要：%s" % facility.facility_id)
	if (
		world_ids.size() != 11
		or not world_ids.has("base_vending")
		or not world_ids.has("base_recovery")
		or not world_ids.has("avatar_wardrobe")
	):
		failures.append("3D 基地没有绑定全部 11 个稳定设施 ID")

	var menu_scene := load("res://scenes/BaseMenu.tscn") as PackedScene
	var menu := menu_scene.instantiate() as BaseMenu
	menu.overlay_mode = true
	add_child(menu)
	await get_tree().process_frame
	var grid := menu.get_node_or_null("VBox/HSplit/RightPanel/BuildingsGrid") as GridContainer
	if grid == null or grid.get_child_count() != 11:
		failures.append("基地管理终端没有显示完整 11 设施目录")
	else:
		var terminal_text := ""
		for child in grid.get_children():
			if child is Button:
				terminal_text += child.text
		for retired_name in ["资源转换", "废品回收", "黑市"]:
			if retired_name in terminal_text:
				failures.append("基地管理终端仍显示旧建筑：%s" % retired_name)
	menu.call("_show_building_panel", "weapon_workshop")
	await get_tree().process_frame
	var building_panel := menu.find_child("BuildingUpgradePanel", true, false) as PanelContainer
	if building_panel == null:
		failures.append("基地管理终端无法打开设施详情与升级面板")
	else:
		var panel_text := _collect_label_text(building_panel)
		if "枪械工坊" not in panel_text or "当前状态" not in panel_text:
			failures.append("设施详情面板没有读取共享设施快照")
	menu.queue_free()
	base_world.queue_free()
	await get_tree().process_frame


func _collect_label_text(root: Node) -> String:
	var result := ""
	if root is Label:
		result += (root as Label).text
	for child in root.get_children():
		result += _collect_label_text(child)
	return result


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE_FACILITY_FRAMEWORK_OK: eleven stable facilities, shared snapshots, visible status, terminal directory, and atomic upgrade planning pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
