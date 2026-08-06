class_name BaseWorld
extends Node2D

@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D
@onready var runs_label: Label = $HUD/InfoPanel/VBox/RunsLabel
@onready var extraction_label: Label = $HUD/InfoPanel/VBox/ExtractionLabel
@onready var kills_label: Label = $HUD/InfoPanel/VBox/KillsLabel
@onready var points_label: Label = $HUD/InfoPanel/VBox/PointsLabel
@onready var loot_label: Label = $HUD/InfoPanel/VBox/LootLabel
@onready var status_label: Label = $HUD/StatusPanel/StatusLabel

var _active_menu: CanvasLayer = null


func _ready() -> void:
	Global.clear_pause_reasons()
	player.set_combat_enabled(false)
	var base_avatar := player.get_node_or_null("Components/Body/AvatarRenderer") as Node2D
	if base_avatar != null:
		base_avatar.scale = Vector2.ONE * 1.28
	camera.reparent(player)
	camera.position = Vector2.ZERO
	camera.make_current()
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if facility is Node and is_ancestor_of(facility) and facility.has_signal("activated"):
			facility.activated.connect(_on_facility_activated)
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if entrance is Node and is_ancestor_of(entrance) and entrance.has_signal("activated"):
			entrance.activated.connect(_on_dungeon_entrance_activated)
	_refresh_base_status()
	_restore_world_position()


func _on_facility_activated(facility: Node) -> void:
	if _active_menu != null and is_instance_valid(_active_menu):
		return
	status_label.text = "%s：%s" % [facility.get("display_name"), facility.get("description")]
	match int(facility.get("activation_type")):
		0:
			_open_menu(str(facility.get("menu_scene_path")))
		1:
			_load_scene(str(facility.get("target_scene_path")), int(facility.get("target_floor")))
		2:
			pass


func _open_menu(scene_path: String) -> void:
	if scene_path.is_empty():
		status_label.text = "该设施尚未接入功能。"
		return
	var menu_scene := load(scene_path) as PackedScene
	if menu_scene == null:
		push_warning("[BaseWorld] Cannot load facility menu: %s" % scene_path)
		status_label.text = "设施功能加载失败。"
		return
	var menu := menu_scene.instantiate() as CanvasLayer
	if menu == null:
		push_warning("[BaseWorld] Facility menu is not a CanvasLayer: %s" % scene_path)
		return
	if menu is BaseMenu:
		menu.overlay_mode = true
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
		push_error("[BaseWorld] Scene transition failed: %s" % error_string(change_error))


func _on_dungeon_entrance_activated(entrance: Node) -> void:
	var scene_path := str(entrance.get("target_scene_path"))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		status_label.text = "这个入口仍被封锁。"
		return
	var entrance_id := str(entrance.get("entrance_id"))
	var floor := int(entrance.get("target_floor"))
	LevelSelect.prepare_dungeon_entry(floor, entrance_id)
	status_label.text = "进入 %s……" % str(entrance.get("display_name"))
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("[BaseWorld] Dungeon transition failed: %s" % error_string(change_error))


func _restore_world_position() -> void:
	var entrance_id := str(LevelSelect.return_entrance_id)
	if entrance_id.is_empty():
		return
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if (
			entrance is Node2D
			and is_ancestor_of(entrance)
			and str(entrance.get("entrance_id")) == entrance_id
		):
			player.global_position = entrance.global_position + Vector2(0, 180)
			camera.reset_smoothing()
			status_label.text = "你回到了 %s 门外。" % str(entrance.get("display_name"))
			break
	LevelSelect.return_entrance_id = ""


func _on_active_menu_closed() -> void:
	_active_menu = null
	if player != null and is_instance_valid(player):
		player.set_input_locked(false)
	_refresh_base_status()


func _refresh_base_status() -> void:
	if BaseManager == null or BaseManager.data == null:
		return
	var data := BaseManager.data
	runs_label.text = "总局数: %d" % data.total_runs
	extraction_label.text = "成功撤离: %d" % data.successful_extractions
	kills_label.text = "总击杀: %d" % data.total_kills
	points_label.text = "基地币: ◈ %d" % BaseManager.get_extraction_points()
	var loot_count := BaseManager.get_extraction_loot_count()
	loot_label.text = "待处理战利品: %d" % loot_count
	loot_label.modulate = Color(1.0, 0.78, 0.35, 1.0) if loot_count > 0 else Color(0.65, 0.72, 0.78, 1.0)
	status_label.text = "基地与荒野处于同一张固定地图；向东沿道路寻找副本入口。"


func get_facility_count() -> int:
	var count := 0
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if facility is Node and is_ancestor_of(facility):
			count += 1
	return count


func get_dungeon_entrance_count() -> int:
	var count := 0
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if entrance is Node and is_ancestor_of(entrance):
			count += 1
	return count


func get_active_menu() -> CanvasLayer:
	return _active_menu
