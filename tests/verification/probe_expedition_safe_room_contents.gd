extends Node
## 临时探针：实测远征关卡01 入口安全屋（room_id = "start"）的运行时装配内容。
## 目的是回答「除了墙之外，安全屋里头目前拼装了哪些组件资产」。
## 只读，不修改任何运行内容；不改任何断言。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WALL_PREFIX := "SafeRoomWall_"
const TILE_PREFIX := "SafeRoomFloorTile_"
const PACKAGE_PREFIX := "SafeRoomPackage_"

var _tower: TowerDescent3D = null


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	_tower = scene.instantiate() as TowerDescent3D
	_tower.test_mode = true
	_tower.run_seed_override = 77001199
	add_child(_tower)
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame

	var rooms: Dictionary = _tower.get("_room_by_id")
	var room := rooms.get("start") as DungeonRoom3D
	if room == null:
		print("PROBE_SAFE_ROOM_CONTENTS_FAIL: 找不到 start 房")
		get_tree().quit(1)
		return

	room.ensure_shell_built()
	room.ensure_detail_built()
	await get_tree().process_frame

	print("=== 安全屋房间身份 ===")
	print("  room_id=%s  room_type=%s  role=%s" % [
		room.room_id, room.room_type, str(room.get_meta("room_role", "-"))
	])
	print("  position=%s  dimensions=%s" % [
		_v3(room.global_position), _v2(room.get_dimensions())
	])
	print("  doors=%s" % str(room.doors))
	print("  door_targets=%s" % str(room.door_targets))
	print("  snapshot: art_version=%s steps=%s wall=%s doorwall=%s tile=%s package=%s" % [
		str(room.get_meta("safe_room_art_version", "<none>")),
		str(room.get_meta("safe_room_orientation_steps", "<none>")),
		str(room.get_meta("safe_room_wall_module_count", "<none>")),
		str(room.get_meta("safe_room_door_wall_module_count", "<none>")),
		str(room.get_meta("safe_room_floor_tile_count", "<none>")),
		str(room.get_meta("safe_room_package_count", "<none>")),
	])

	var art_root := room.get_node_or_null("SafeRoomArtRoot") as Node3D
	if art_root == null:
		print("PROBE_SAFE_ROOM_CONTENTS_FAIL: 无 SafeRoomArtRoot（未走 v007 壳体）")
		get_tree().quit(1)
		return

	# 四角 L 型墙角哨兵（防假绿）：远征入口安全房必须真的装配出 4 件 L。
	# 计的是节点上带 asset_id=ENV-TOWER-CORNER-L-5M 的实际件数，不是读建造时的自报 meta。
	var corner_l_enabled := bool(room.get_meta("safe_room_corner_l", false))
	var corner_nodes: Array = []
	for value in room.find_children("*", "Node3D", true, false):
		if str((value as Node).get_meta("asset_id", "")) == "ENV-TOWER-CORNER-L-5M":
			corner_nodes.append(value)
	var expected_corner_count := DungeonRoom3D.SAFE_ROOM_CORNER_IDS.size()
	if not corner_l_enabled or corner_nodes.size() != expected_corner_count:
		print("PROBE_SAFE_ROOM_CONTENTS_FAIL: 四角 L 件未装配 (enabled=%s count=%d/%d)" % [
			corner_l_enabled, corner_nodes.size(), expected_corner_count
		])
		get_tree().quit(1)
		return
	print("")
	print("=== A1 四角 L 型墙角（%d 件）asset_id=ENV-TOWER-CORNER-L-5M ===" % corner_nodes.size())
	for node in corner_nodes:
		var corner := node as Node3D
		print("  %-24s local=%s  corner=%s  dir=%s  rot_y=%.1f°" % [
			str(corner.name), _v3(corner.position),
			str(corner.get_meta("tower_wall_corner", "-")),
			str(corner.get_meta("tower_wall_direction", "-")),
			rad_to_deg(corner.rotation.y),
		])
		var bodies: Array = []
		for value in corner.find_children("*", "StaticBody3D", true, false):
			var body := value as StaticBody3D
			bodies.append("%s(camera_lower_wall=%s)" % [
				str(body.name), str(body.get_meta("camera_lower_wall", "-"))
			])
		print("      碰撞臂：%s" % str(bodies))

	print("")
	print("=== SafeRoomArtRoot 装配总览（art_root.rotation.y=%.1f°）===" % rad_to_deg(art_root.rotation.y))
	var wall_solids: Array = []
	var wall_doors: Array = []
	var tiles: Array = []
	var packages: Array = []
	var proxies: Array = []
	var others: Array = []
	for child in art_root.get_children():
		var node := child as Node3D
		var raw_name: String = String(child.name)
		if node == null:
			others.append(raw_name)
			continue
		# Godot 对同名兄弟节点自动改名成 "@Name@2"，统计前先削掉这层后缀。
		var clean_name: String = raw_name.trim_prefix("@")
		if clean_name.contains("@"):
			clean_name = clean_name.split("@")[0]
		# 重名墙件会被引擎改名成 "@Node3D@NNN"（Godot 用类名做基名），
		# 因此墙件判定不能只看名字前缀，改用墙件专有的 tower_wall_direction 元数据。
		if clean_name.begins_with("CameraOnlyDoorWall_"):
			proxies.append(node)
		elif child.has_meta("tower_wall_direction"):
			if clean_name.ends_with("_Door"):
				wall_doors.append(node)
			else:
				wall_solids.append(node)
		elif clean_name.begins_with(TILE_PREFIX):
			tiles.append(node)
		elif clean_name.begins_with(PACKAGE_PREFIX):
			packages.append(node)
		else:
			others.append("%s(class=%s,wall_meta=%s)" % [
				raw_name, child.get_class(),
				str(child.has_meta("tower_wall_direction")),
			])
	print("  实墙=%d  门墙=%d  地砖=%d  房间包=%d  镜头代理=%d  其他=%d" % [
		wall_solids.size(), wall_doors.size(), tiles.size(),
		packages.size(), proxies.size(), others.size(),
	])
	if not others.is_empty():
		print("  其他明细：%s" % str(others))

	print("")
	print("=== A2 地砖（%d 件）===" % tiles.size())
	for node in tiles:
		print("  %-24s local=%s  walk_plane_snap_y=%s" % [
			str(node.name), _v3(node.position),
			str(node.get_meta("walk_plane_snap_y", "-")),
		])

	print("")
	print("=== A3 房间包（%d 件）—— 安全屋内的固定设施美术 ===" % packages.size())
	var total := Vector3.ZERO
	for node in packages:
		var box := _world_aabb(node)
		print("  %-34s local=%s" % [
			str(node.name).replace(PACKAGE_PREFIX, ""), _v3(node.position),
		])
		print("      世界包围盒 min=%s size=%s  asset_id=%s" % [
			_v3(box.position), _v3(box.size), str(node.get_meta("asset_id", "-")),
		])

	print("")
	print("=== A5 门扇 ===")
	for direction in room.doors:
		var door := room.get_node_or_null("Door_%s" % str(direction).capitalize()) as RoomDoor3D
		if door == null:
			print("  %-6s 缺失" % str(direction))
			continue
		print("  %-6s pos=%s rot_y=%.1f  target=%s" % [
			str(direction), _v3(door.position), rad_to_deg(door.rotation.y),
			str(door.target_room_id),
		])
		var leaf := door.get_node_or_null("DoorPanel/ImportedDoorVisual")
		print("         门扇包=%s" % ("有" if leaf != null else "无"))

	print("")
	print("=== C 细节层（代码生成，挂 RuntimeDetail）===")
	var detail := room.get_node_or_null("RuntimeDetail")
	if detail == null:
		print("  无 RuntimeDetail")
	else:
		for child in detail.get_children():
			var node := child as Node3D
			print("  %-28s (%s)%s" % [
				str(child.name), child.get_class(),
				(" pos=%s" % _v3(node.position)) if node != null else "",
			])
	print("  RoomTrigger 存在=%s" % str(room.get_node_or_null("RoomTrigger") != null))

	print("")
	print("PROBE_SAFE_ROOM_CONTENTS_OK")
	get_tree().quit(0)


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_result := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := _relative_transform(root, mesh_instance) * mesh_instance.get_aabb()
		if not has_result:
			result = box
			has_result = true
		else:
			result = result.merge(box)
	return result


func _relative_transform(root: Node, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _v3(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]


func _v2(value: Vector2) -> String:
	return "(%.2f, %.2f)" % [value.x, value.y]
