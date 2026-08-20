class_name BaseWorld3D
extends Node3D
## 游戏入口的正式 3D 基地地图。设施、入口和返回契约经共享服务层持有，
## 只替换空间、角色、相机与表现层；战斗副本继续作为独立场景按需加载。

const FacilityCatalog = preload("res://src/base/BaseFacilityCatalog.gd")

@onready var player: Player3D = $Player3D
@onready var environment_kit: BaseWorld3DEnvironment = $EnvironmentKit
@onready var runs_label: Label = $HUD/InfoPanel/VBox/RunsLabel
@onready var extraction_label: Label = $HUD/InfoPanel/VBox/ExtractionLabel
@onready var kills_label: Label = $HUD/InfoPanel/VBox/KillsLabel
@onready var points_label: Label = $HUD/InfoPanel/VBox/PointsLabel
@onready var loot_label: Label = $HUD/InfoPanel/VBox/LootLabel
@onready var state_label: Label = $HUD/StatePanel/StateLabel
@onready var status_label: Label = $HUD/StatusPanel/StatusLabel

var _active_menu: CanvasLayer = null


func _ready() -> void:
	Global.clear_pause_reasons()
	player.set_combat_enabled(false)
	player.presentation_state_changed.connect(_on_player_state_changed)
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if facility is BaseFacility3D and is_ancestor_of(facility):
			facility.activated.connect(_on_facility_activated)
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if entrance is DungeonEntrance3D and is_ancestor_of(entrance):
			entrance.activated.connect(_on_dungeon_entrance_activated)
	_refresh_base_status()
	_refresh_facilities()
	_restore_world_position()
	_on_player_state_changed(player.get_presentation_state(), {})


func _on_facility_activated(facility: BaseFacility3D) -> void:
	if _active_menu != null and is_instance_valid(_active_menu):
		return
	var snapshot := BaseManager.get_facility_snapshot(facility.facility_id)
	if not bool(snapshot.get("available", false)):
		status_label.text = "%s：%s" % [
			facility.display_name,
			str(snapshot.get("availability_reason", "设施不可用")),
		]
		return
	status_label.text = "%s｜%s\n%s" % [
		str(snapshot.get("display_name", facility.display_name)),
		str(snapshot.get("summary", "")),
		str(snapshot.get("description", facility.description)),
	]
	match str(snapshot.get("action_kind", FacilityCatalog.ACTION_INFO)):
		FacilityCatalog.ACTION_MENU:
			_open_menu(str(snapshot.get("action_path", "")))
		FacilityCatalog.ACTION_SCENE:
			_load_scene(str(snapshot.get("action_path", "")), facility.target_floor)
		FacilityCatalog.ACTION_INFO:
			status_label.text += "\n四条远征路线均从基地外道路进入；训练场不计入行动结算。"


func _open_menu(scene_path: String) -> void:
	if scene_path.is_empty():
		status_label.text = "该设施尚未接入功能。"
		return
	var menu_scene := load(scene_path) as PackedScene
	if menu_scene == null:
		status_label.text = "设施功能加载失败。"
		return
	var menu := menu_scene.instantiate() as CanvasLayer
	if menu == null:
		push_warning("[BaseWorld3D] Facility menu is not a CanvasLayer: %s" % scene_path)
		return
	if menu is BaseMenu:
		menu.overlay_mode = true
	if menu.has_method("set_player"):
		menu.call("set_player", player)
	# 设施菜单必须覆盖基地 HUD，避免状态面板与菜单内容重叠。
	menu.layer = 50
	_active_menu = menu
	player.set_input_locked(true)
	add_child(menu)
	menu.tree_exited.connect(_on_active_menu_closed)


func _load_scene(scene_path: String, floor: int = 0) -> void:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		status_label.text = "目标地图尚未配置。"
		return
	if floor > 0:
		LevelSelect.selected_floor = floor
		LevelSelect.selection_made = true
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("[BaseWorld3D] Scene transition failed: %s" % error_string(change_error))


func _on_dungeon_entrance_activated(entrance: DungeonEntrance3D) -> void:
	if entrance.target_scene_path.is_empty() or not ResourceLoader.exists(entrance.target_scene_path, "PackedScene"):
		status_label.text = "这个入口仍被封锁。"
		return
	LevelSelect.prepare_dungeon_entry(entrance.target_floor, entrance.entrance_id)
	status_label.text = "进入 %s……" % entrance.display_name
	var change_error := get_tree().change_scene_to_file(entrance.target_scene_path)
	if change_error != OK:
		push_error("[BaseWorld3D] Dungeon transition failed: %s" % error_string(change_error))


func _restore_world_position() -> void:
	var entrance_id := str(LevelSelect.return_entrance_id)
	if entrance_id.is_empty():
		return
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if entrance is DungeonEntrance3D and is_ancestor_of(entrance) and entrance.entrance_id == entrance_id:
			player.global_position = entrance.global_position + Vector3(0, 0, 2.8)
			status_label.text = "你回到了 %s 门外。" % entrance.display_name
			break
	LevelSelect.return_entrance_id = ""


func _on_active_menu_closed() -> void:
	_active_menu = null
	if player != null and is_instance_valid(player):
		player.set_input_locked(false)
	if not is_inside_tree():
		return
	_refresh_base_status()
	_refresh_facilities()


func try_close_modal_for_pause() -> bool:
	if _active_menu == null or not is_instance_valid(_active_menu):
		return false
	_active_menu.queue_free()
	return true


func _on_player_state_changed(state_id: String, _context: Dictionary) -> void:
	var labels := {
		"idle": "待命",
		"moving": "机动",
		"dashing": "突进",
		"hurt": "受创",
		"locked": "交互锁定",
		"dead": "生命终止",
	}
	state_label.text = "3D 姿态 · %s" % str(labels.get(state_id, state_id))


func _refresh_base_status() -> void:
	if BaseManager == null or BaseManager.data == null:
		return
	var data := BaseManager.data
	runs_label.text = "总局数: %d" % data.total_runs
	extraction_label.text = "成功撤离: %d" % data.successful_extractions
	kills_label.text = "总击杀: %d" % data.total_kills
	points_label.text = "魂: ◈ %d" % BaseManager.get_extraction_points()
	var loot_count := BaseManager.get_extraction_loot_count()
	loot_label.text = "待处理战利品: %d" % loot_count
	loot_label.modulate = Color(1.0, 0.78, 0.35) if loot_count > 0 else Color(0.65, 0.72, 0.78)
	status_label.text = "3D 基地与荒野已接入；沿破败公路寻找四个副本入口。"


func _refresh_facilities() -> void:
	if BaseManager == null or not is_inside_tree():
		return
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if facility is BaseFacility3D and is_ancestor_of(facility):
			facility.apply_snapshot(BaseManager.get_facility_snapshot(facility.facility_id))


func get_facility_count() -> int:
	var count := 0
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if facility is BaseFacility3D and is_ancestor_of(facility):
			count += 1
	return count


func get_dungeon_entrance_count() -> int:
	var count := 0
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if entrance is DungeonEntrance3D and is_ancestor_of(entrance):
			count += 1
	return count


func get_environment_snapshot() -> Dictionary:
	return environment_kit.get_environment_snapshot() if environment_kit != null else {}


func get_active_menu() -> CanvasLayer:
	return _active_menu


func get_facility_snapshots() -> Array[Dictionary]:
	return BaseManager.get_facility_snapshots() if BaseManager != null else []
