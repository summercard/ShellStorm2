extends Node
## 验证两个"基地里已下线但保留功能"的设施：
##   1. 怪物档案馆：BaseWorld3D.tscn 不再实例化该节点。
##   2. 基地 99F 电梯：TowerDescent3D 在基地模式下不再生成
##      access_room_id == "facility" 的电梯。
## 但 BaseFacilityCatalog / MonsterArchiveMenu / TowerDescent3D 电梯所有
## 函数必须仍然存在于源代码中，以便以后要带回去时一键恢复。

const TOWER_SCRIPT_PATH := "res://src/world3d/TowerDescent3D.gd"
const BASE_SCENE_PATH := "res://scenes/BaseWorld3D.tscn"
const MONSTER_ARCHIVE_MENU_PATH := "res://scenes/MonsterArchiveMenu.tscn"

func _ready() -> void:
	var failures: Array[String] = []
	_check_monster_archive_removed_from_base(failures)
	_check_base_99f_elevator_not_installed(failures)
	_check_optional_facilities_can_be_restored(failures)
	if failures.is_empty():
		print(
			"BASE_OPTIONAL_FACILITIES_OK: "
			+ "monster_archive node removed from base / "
			+ "base 99F elevator skipped / "
			+ "catalog + menu + elevator functions all intact"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check_monster_archive_removed_from_base(failures: Array[String]) -> void:
	var base_text := _read_text(BASE_SCENE_PATH)
	if base_text == "":
		failures.append("%s 读取失败" % BASE_SCENE_PATH)
		return
	if _contains_monster_archive_node(base_text):
		failures.append("%s 中仍含有 monster_archive 节点块" % BASE_SCENE_PATH)
	if not _contains_comment_marker(base_text, "怪物档案室"):
		failures.append(
			"%s 缺少怪物档案室下线说明注释（应保留以便以后带回）" % BASE_SCENE_PATH
		)


func _check_base_99f_elevator_not_installed(failures: Array[String]) -> void:
	var tower_text := _read_text(TOWER_SCRIPT_PATH)
	if tower_text == "":
		failures.append("%s 读取失败" % TOWER_SCRIPT_PATH)
		return
	if not _contains_marker(tower_text, "99F 基地电梯默认隐藏"):
		failures.append(
			"%s 缺少 99F 基地电梯下线说明标记" % TOWER_SCRIPT_PATH
		)
	# 开关必须存在并默认为 false。
	var enabled_marker := "var base_elevator_enabled := false"
	if not _contains_marker(tower_text, enabled_marker):
		failures.append(
			"%s 缺少 base_elevator_enabled := false 开关" % TOWER_SCRIPT_PATH
		)


func _check_optional_facilities_can_be_restored(failures: Array[String]) -> void:
	# 1) BaseFacilityCatalog 仍然能查到 monster_archive（运行时行为）。
	if not BaseFacilityCatalog.has_facility("monster_archive"):
		failures.append("BaseFacilityCatalog.has_facility('monster_archive') 失败：catalog 记录缺失")
		return
	var definition: Dictionary = BaseFacilityCatalog.get_definition("monster_archive")
	var menu_path := str(definition.get("action_path", ""))
	if menu_path != MONSTER_ARCHIVE_MENU_PATH:
		failures.append(
			"monster_archive.action_path 错误：%s" % menu_path
		)
	if not ResourceLoader.exists(menu_path):
		failures.append("monster_archive 入口场景资源不存在：%s" % menu_path)
		return
	var menu_scene := load(menu_path) as PackedScene
	if menu_scene == null:
		failures.append("MonsterArchiveMenu.tscn PackedScene 加载失败")
		return
	var menu_node := menu_scene.instantiate()
	if menu_node == null:
		failures.append("MonsterArchiveMenu.tscn 实例化失败")
	else:
		menu_node.queue_free()

	# 2) TowerDescent3D 电梯相关函数在源代码中仍然存在。
	var tower_text := _read_text(TOWER_SCRIPT_PATH)
	if tower_text == "":
		failures.append("%s 读取失败" % TOWER_SCRIPT_PATH)
		return
	var required_functions := [
		"func _install_elevator_facility(",
		"func _create_standalone_elevator(",
		"func _elevator_wall_pose(",
		"func _on_facility_activated(",
		"func _open_elevator_panel(",
		"func _close_elevator_panel(",
		"func _travel_elevator_to(",
		"func _sorted_unlocked_elevator_floors(",
	]
	for func_signature in required_functions:
		if not tower_text.contains(func_signature):
			failures.append(
				"%s 缺失函数定义：%s" % [TOWER_SCRIPT_PATH, func_signature]
			)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _contains_monster_archive_node(scene_text: String) -> bool:
	return scene_text.contains('facility_id = "monster_archive"')


func _contains_marker(text: String, marker: String) -> bool:
	return text.find(marker) >= 0


func _contains_comment_marker(scene_text: String, marker: String) -> bool:
	return scene_text.contains(marker)