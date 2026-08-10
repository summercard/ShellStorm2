extends Node

const TOWER := preload("res://scenes/TowerDescent3D.tscn")
const VENDING_OUTPUT := "res://outputs/verification/formal_vending_in_base.png"
const FACILITY_ROW_OUTPUT := "res://outputs/verification/formal_mission_workshop_in_base.png"
const DECOR_OUTPUT := "res://outputs/verification/formal_facility_wall_decor.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var world := TOWER.instantiate() as TowerDescent3D
	add_child(world)
	for _frame in 12:
		await get_tree().process_frame
	var vending := _find_facility(world, "base_vending")
	var mission := _find_facility(world, "mission_operations")
	var workshop := _find_facility(world, "weapon_workshop")
	var locker_decor := world.find_child("赛博储物站_墙边装饰", true, false) as Node3D
	var retro_decor := world.find_child("复古电视站_墙边装饰", true, false) as Node3D
	var workshop_stool := world.find_child("维修圆凳_独立装饰", true, false) as Node3D
	var mission_chair := world.find_child("战术指挥椅_独立装饰", true, false) as Node3D
	var art_layout := world.find_child("基地99层_美术布置层", true, false) as Node3D
	_check(vending != null and mission != null and workshop != null, "三个正式基地设施未全部实例化", failures)
	_check(locker_decor != null and retro_decor != null, "两个墙边装饰设施未全部实例化", failures)
	_check(workshop_stool != null and mission_chair != null, "两把独立座椅未全部实例化", failures)
	if workshop_stool != null:
		_check(not workshop_stool.is_in_group("base_facility"), "维修圆凳不应绑定设施交互", failures)
	if mission_chair != null:
		_check(not mission_chair.is_in_group("base_facility"), "战术指挥椅不应绑定设施交互", failures)
	_check(art_layout != null, "基地美术布置层未通过代码桥接实例化", failures)
	if art_layout != null:
		var editor_guide := art_layout.get_node_or_null("编辑器参考_运行时自动隐藏") as Node3D
		var light_root := art_layout.get_node_or_null("基地美术灯光_可编辑") as Node3D
		var elevator_anchor := art_layout.get_node_or_null("玩法锚点_只移动不删除/99层电梯锚点") as Marker3D
		_check(editor_guide != null and not editor_guide.visible, "编辑器参考网格在运行时没有隐藏", failures)
		_check(light_root != null and light_root.get_child_count() >= 3, "基地可编辑灯组缺失", failures)
		_check(elevator_anchor != null, "99层电梯可编辑锚点缺失", failures)
		_check(_count_facilities(art_layout) == 8, "美术布置层没有保留8个交互设施桥接节点", failures)
		if light_root != null:
			for light_node in light_root.get_children():
				if light_node is Light3D:
					_check((light_node as Light3D).shadow_enabled, "%s 没有启用可编辑阴影" % light_node.name, failures)
	for facility in [vending, mission, workshop]:
		if facility != null:
			_check(_faces_room(facility), "%s 正面没有朝向基地房间内部" % facility.facility_id, failures)
	if vending != null:
		_place_player_for_view(world, vending.global_position + _forward(vending) * 2.2)
		await _settle()
		_save(VENDING_OUTPUT, "贩卖机基地实景验收图保存失败", failures)
	if mission != null and workshop != null:
		var middle := (mission.global_position + workshop.global_position) * 0.5
		_place_player_for_view(world, middle + _forward(mission) * 3.1)
		await _settle()
		_save(FACILITY_ROW_OUTPUT, "情报台/工作台基地实景验收图保存失败", failures)
	if locker_decor != null and retro_decor != null:
		_check(_faces_room_node(locker_decor), "储物站装饰正面没有朝向基地房间内部", failures)
		_check(_faces_room_node(retro_decor), "电视站装饰正面没有朝向基地房间内部", failures)
		_check(not locker_decor.is_in_group("base_facility"), "储物站装饰不应注册为交互设施", failures)
		_check(not retro_decor.is_in_group("base_facility"), "电视站装饰不应注册为交互设施", failures)
		var decor_middle := (locker_decor.global_position + retro_decor.global_position) * 0.5
		_place_player_for_view(world, decor_middle + _forward_node(locker_decor) * 4.0)
		world.player.look_at(decor_middle, Vector3.UP)
		await _settle()
		_save(DECOR_OUTPUT, "墙边装饰设施验收图保存失败", failures)
	if failures.is_empty():
		print("FORMAL_ASSET_PLACEMENT_VISUAL_OK: 三交互设施、两墙边装饰与两把独立座椅验收图已生成")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _find_facility(world: TowerDescent3D, facility_id: String) -> BaseFacility3D:
	for node in get_tree().get_nodes_in_group("base_facility"):
		var facility := node as BaseFacility3D
		if facility != null and facility.is_ancestor_of(world) == false and facility.facility_id == facility_id:
			return facility
		if facility != null and facility.facility_id == facility_id:
			return facility
	return null


func _forward(facility: BaseFacility3D) -> Vector3:
	return _forward_node(facility)


func _forward_node(node: Node3D) -> Vector3:
	return (node.global_basis * Vector3.FORWARD).normalized()


func _faces_room(facility: BaseFacility3D) -> bool:
	return _faces_room_node(facility)


func _faces_room_node(node: Node3D) -> bool:
	var room_center := node.get_parent_node_3d().global_position
	var to_room := (room_center - node.global_position).normalized()
	return _forward_node(node).dot(to_room) > 0.72


func _place_player_for_view(world: TowerDescent3D, position: Vector3) -> void:
	world.player.global_position = position
	world.player.velocity = Vector3.ZERO


func _settle() -> void:
	for _frame in 10:
		await get_tree().process_frame


func _save(path: String, message: String, failures: Array[String]) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append(message)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _count_facilities(root: Node) -> int:
	var count := 1 if root is BaseFacility3D else 0
	for child in root.get_children():
		count += _count_facilities(child)
	return count
