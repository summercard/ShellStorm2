extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_IDS := [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05", "room_06",
	"room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]
const RUN_SEED := 77001199
const POSITION_TOLERANCE_M := 0.001
const ALIGN_TOLERANCE_M := 0.6
const PORT_TOLERANCE_M := 0.25
const CATALOG_PATH := "res://assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
var failures: Array[String] = []
var checks := 0
var _catalog_roles: Dictionary = {}
var _catalog_roles_loaded := false

func _ready() -> void:
	for room_id in ROOM_IDS:
		var path := _scene_path(room_id)
		_check(ResourceLoader.exists(path), "%s 静态场景必须存在" % room_id)
		if ResourceLoader.exists(path):
			var packed := load(path) as PackedScene
			_check(packed != null, "%s 必须可加载为 PackedScene" % room_id)
			if packed != null:
				var instance := packed.instantiate() as Node3D
				_check(instance != null, "%s 必须可实例化为 Node3D" % room_id)
				if instance != null:
					add_child(instance)
					_check(str(_metadata_value(instance, "schema", "")) == "shellstorm2.expedition.room_static_layout.v001", "%s schema 错误" % room_id)
					var prefabs := _prefab_children(instance)
					_check(not prefabs.is_empty(), "%s 正式 TSCN 必须有实体 prefab" % room_id)
					print("STATIC_SOURCE %s metadata_total=%d prefab=%d direct=%d" % [
						room_id, int(_metadata_value(instance, "layout_instance_total", -1)),
						prefabs.size(), instance.get_child_count(),
					])
					_check(instance.find_children("*", "RoomDoor3D", true, false).is_empty(), "%s TSCN 不得固化 RoomDoor3D" % room_id)
					_check(instance.get_node_or_null("RoomTrigger") == null, "%s TSCN 不得固化 RoomTrigger" % room_id)
					_check(instance.find_children("*", "NavigationRegion3D", true, false).is_empty(), "%s TSCN 不得固化 NavigationRegion3D" % room_id)
					_check(instance.find_children("RuntimeDetail", "Node3D", true, false).is_empty(), "%s TSCN 不得固化 RuntimeDetail" % room_id)
					if room_id == "room_03":
						_check(
							instance.get_node_or_null("filing_run_west") == null,
							"room_03 入口净空不得固化默认西侧文件柜"
						)
					if room_id == "start":
						_check(
							_count_nodes_with_meta(instance, "tower_wall_corner") == 4,
							"start TSCN 必须包含四个 L 型转角墙 prefab"
						)
						_check(
							_count_nodes_with_meta(instance, "editor_preview_only") == 2,
							"start TSCN 必须包含两扇编辑器门扇预览"
						)
					instance.queue_free()
					await get_tree().process_frame
					await get_tree().physics_frame
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	_check(tower != null, "远征场景必须可实例化")
	if tower != null:
		tower.test_mode = true
		tower.run_seed_override = RUN_SEED
		var legacy := "--legacy" in OS.get_cmdline_user_args()
		if legacy:
			tower.set("_runtime_restore_snapshot", {"world_state": {}})
		_check(tower._expedition_rotation_for_checkpoint({"world_state": {}} if legacy else {}) == (0 if legacy else 180), "旧快照/新战局朝向分支必须为 0/180")
		print("STATIC_MODE legacy=%s rotation=%d" % [str(legacy), 0 if legacy else 180])
		add_child(tower)
		for _index in range(8):
			await get_tree().process_frame
			await get_tree().physics_frame
		var snapshots := tower.get("_floor_plan_snapshots") as Dictionary
		var actual_plan := snapshots.get(0, {}) as Dictionary
		_check(int(actual_plan.get("expedition_global_rotation_deg", -1)) == (0 if legacy else 180), "实际运行规划必须落在所选 0/180 对照分支")
		var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
		_check(block != null, "运行时必须生成远征区块")
		if block != null:
			for room_id in ROOM_IDS:
				var room := block.get_node_or_null(room_id) as DungeonRoom3D
				_check(room != null, "运行时缺少 %s" % room_id)
				if room == null:
					continue
				room.ensure_shell_built()
				_check(bool(_metadata_value(room, "static_layout_scene_loaded", false)), "%s 必须从 TSCN 加载静态布局" % room_id)
				_check(room.get_node_or_null("RoomTrigger") != null, "%s 必须保留运行时 RoomTrigger" % room_id)
				_check((room.get("_door_nodes") as Dictionary).size() == room.doors.size(), "%s 必须保留全部运行时门" % room_id)
				var art_root := room.get_node_or_null(
					"SafeRoomArtRoot" if room_id == "start" else "AuthoredLayoutArtRoot"
				) as Node3D
				_check(art_root != null, "%s 必须保留静态艺术根" % room_id)
				if art_root != null:
					_check_saved_instance_replay(room, art_root, room_id)
					_check_static_camera_wall_contract(art_root, room_id)
					_check_camera_wall_rotation_invariance(room, art_root, room_id)
				if room_id == "start" and art_root != null:
					_check(
						_count_nodes_with_meta(art_root, "tower_wall_corner") == 4,
						"start 运行时必须保留四个 L 型转角墙"
					)
					_check(
						_count_visible_nodes_with_meta(art_root, "editor_preview_only") == 0,
						"start 运行时必须隐藏两扇编辑器门扇预览"
					)
					_check(
						(room.get("_door_nodes") as Dictionary).size() == 2,
						"start 运行时必须创建两扇动态门"
					)
				if art_root != null and room.authored_layout_shell:
					_check_plan_scene_alignment(room, art_root, room_id)
					_check(
						(room.get("_authored_tile_cells") as Array).size()
						== int(_metadata_value(art_root, "authored_layout_floor_tile_count", -1)),
						"%s 刷怪 footprint 必须与静态地砖统计一致" % room_id
					)
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().physics_frame
		_check(not is_instance_valid(tower), "远征验收场景必须在退出前完成释放")
	if failures.is_empty():
		print("EXPEDITION_ROOM_STATIC_SCENES_OK checks=%d rooms=%d" % [checks, ROOM_IDS.size()])
		call_deferred("_finish", 0)
		return
	for failure in failures:
		print("FAIL %s" % failure)
	call_deferred("_finish", 1)

func _finish(exit_code: int) -> void:
	var exit_timer := Timer.new()
	exit_timer.one_shot = true
	exit_timer.wait_time = 0.1
	exit_timer.timeout.connect(get_tree().quit.bind(exit_code))
	get_tree().root.add_child(exit_timer)
	exit_timer.start()
	queue_free()

func _scene_path(room_id: String) -> String:
	return (
		"res://assets/art/environments/tower_zones/expedition/runtime/"
		+ "room_instances/expedition_01/f00_%s_static_layout.tscn" % room_id
	)

## 正式 PackedScene 离树实例是作者事实源；只允许有实际端口证据的结构转换。
func _check_saved_instance_replay(room: DungeonRoom3D, art_root: Node3D, room_id: String) -> void:
	var packed := load(_scene_path(room_id)) as PackedScene
	_check(packed != null, "%s 正式 PackedScene 必须可加载" % room_id)
	if packed == null:
		return
	var saved := packed.instantiate() as Node3D
	_check(saved != null, "%s 正式布局必须可实例化" % room_id)
	if saved == null:
		return
	_check(art_root.has_meta("layout_instance_total") == saved.has_meta("layout_instance_total") and _metadata_value(art_root, "layout_instance_total") == _metadata_value(saved, "layout_instance_total"), "%s 必须保留正式 TSCN 的历史 layout_instance_total；该值不充当实体计数" % room_id)
	# 整体对齐只允许四向刚体旋转，不能通过缩放/平移掩盖逐件坐标差异。
	_check(art_root.position.is_equal_approx(saved.position) and art_root.scale.is_equal_approx(saved.scale), "%s 美术根必须保留作者位置与缩放" % room_id)
	var delta_basis := art_root.basis * saved.basis.inverse()
	var four_way := false
	for steps in range(4):
		if delta_basis.is_equal_approx(Basis(Vector3.UP, float(steps) * PI * 0.5)):
			four_way = true
	_check(four_way, "%s 美术根对齐必须为四向刚体旋转：%s" % [room_id, str(delta_basis)])
	var source := _prefab_children(saved)
	var live := _prefab_children(art_root)
	var consumed: Dictionary = {}
	var removed := 0
	var added := 0
	for instance_name in source:
		var original := source[instance_name] as Node3D
		var current := live.get(instance_name) as Node3D
		if current == null:
			var fill_name := "%s_SolidFill" % instance_name
			var fill := live.get(fill_name) as Node3D
			if fill != null and _valid_solid_fill(room, art_root, original, fill, source):
				consumed[fill_name] = true
				removed += 1
				added += 1
				print("STATIC_CONVERSION %s seal %s -> %s path=%s" % [room_id, instance_name, fill_name, fill.scene_file_path])
				continue
			var room_position := art_root.transform * original.position
			var side := _port_side_at(room, room_position)
			if _is_wall_piece(original) and not side.is_empty() and not room.owns_door_endpoint(side):
				removed += 1
				print("STATIC_CONVERSION %s remove_shared %s side=%s position=%s" % [room_id, instance_name, side, str(room_position)])
				continue
			_check(false, "%s 缺少正式实例 %s path=%s position=%s" % [room_id, instance_name, original.scene_file_path, str(original.position)])
			continue
		consumed[instance_name] = true
		if _is_door_wall(current):
			_check(_door_at_owned_port(room, art_root, current), "%s %s 门墙必须对齐真实 owner 端口及 room 轴：transform=%s ports=%s" % [room_id, instance_name, str(art_root.transform * current.transform), str(room.connection_ports)])
		_check(current.scene_file_path == original.scene_file_path, "%s %s prefab 来源改变：%s -> %s" % [room_id, instance_name, original.scene_file_path, current.scene_file_path])
		for key in ["asset_id", "authored_component_id", "authored_source_component_id", "authored_slot_role", "material_variant"]:
			_check(current.has_meta(key) == original.has_meta(key) and _metadata_value(current, key) == _metadata_value(original, key), "%s %s 保存身份/颜色 metadata %s 改变" % [room_id, instance_name, key])
		if not current.transform.is_equal_approx(original.transform):
			var rehomed := _is_door_wall(original) and original.scene_file_path.contains("wall_door") and _door_at_owned_port(room, art_root, current)
			_check(rehomed, "%s %s 作者局部变换改变：saved=%s live=%s" % [room_id, instance_name, str(original.transform), str(current.transform)])
			if rehomed:
				_check(current.scale.is_equal_approx(original.scale), "%s %s 门槽重定位不得改变作者缩放" % [room_id, instance_name])
				print("STATIC_CONVERSION %s rehome %s room_transform=%s" % [room_id, instance_name, str(art_root.transform * current.transform)])
		if _is_floor_tile(original):
			_check(current.transform.is_equal_approx(original.transform), "%s 地砖 %s identity/position 必须保持正式 TSCN" % [room_id, instance_name])
			_check(_tile_colors(current) == _tile_colors(original), "%s 地砖 %s 材质颜色/贴图必须保持正式 TSCN" % [room_id, instance_name])
	for instance_name in live:
		if consumed.has(instance_name):
			continue
		# 未知新增不能仅凭名字含 door 放过：当前生产路径没有独立新增 prefab 合同。
		var current := live[instance_name] as Node3D
		print("STATIC_EXTRA %s %s path=%s room_transform=%s" % [room_id, instance_name, current.scene_file_path, str(art_root.transform * current.transform)])
		_check(false, "%s 出现未经解释的额外正式实例 %s" % [room_id, instance_name])
	_check(live.size() == source.size() - removed + added, "%s 正式实例集合数量必须符合逐件门槽转换：saved=%d removed=%d added=%d live=%d" % [room_id, source.size(), removed, added, live.size()])
	if room.authored_layout_shell:
		_check_live_role_metadata(room, art_root, room_id)
	print("STATIC_REPLAY %s saved=%d live=%d removed=%d added=%d metadata_total=%d" % [room_id, source.size(), live.size(), removed, added, int(_metadata_value(art_root, "layout_instance_total", -1))])
	saved.free()


func _prefab_children(root: Node) -> Dictionary:
	var result: Dictionary = {}
	for child in root.get_children():
		if child is Node3D and not child.scene_file_path.is_empty():
			result[str(child.name)] = child
	return result


func _is_door_wall(piece: Node3D) -> bool:
	return piece.scene_file_path.contains("wall_door") or piece.scene_file_path.contains("door_wall")


func _tile_id(piece: Node3D) -> String:
	return str(_metadata_value(piece, "authored_component_id", _metadata_value(piece, "asset_id", "")))


## 角色来自 prefab metadata 或注册来源；旧通用地砖没有 authored_component_id。
## 明确的非 floor_tile 角色不能因模型名含 tile 被算作主层地砖。
func _is_floor_tile(piece: Node3D) -> bool:
	var authored_role := str(_metadata_value(piece, "authored_slot_role", ""))
	if not authored_role.is_empty():
		return authored_role == "floor_tile"
	if not piece.scene_file_path.is_empty() and not _catalog_role(piece.scene_file_path).is_empty():
		return _catalog_role(piece.scene_file_path) == "floor_tile"
	return _catalog_role(_tile_id(piece)) == "floor_tile"


func _catalog_role(identity: String) -> String:
	if not _catalog_roles_loaded:
		_catalog_roles_loaded = true
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		_check(catalog is Dictionary, "壳体组件角色注册表必须可读")
		if catalog is Dictionary:
			for value in (catalog as Dictionary).get("components", []):
				var component := value as Dictionary
				var role := str(component.get("slot_role", ""))
				for key in ["component_id", "prefab_asset_id", "prefab_path"]:
					var identity_key := str(component.get(key, ""))
					if not identity_key.is_empty():
						_catalog_roles[identity_key] = role
				for alias in component.get("aliases", []):
					_catalog_roles[str(alias)] = role
	return str(_catalog_roles.get(identity, ""))


## 不以 C01/C02 数量差或邻色合法性推断作者意图；逐表面比较实际保存颜色。
func _tile_colors(piece: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var meshes := piece.find_children("*", "MeshInstance3D", true, false)
	if piece is MeshInstance3D:
		meshes.append(piece)
	for value in meshes:
		var mesh := value as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			var key := "%s:%d" % [str(piece.get_path_to(mesh)), surface]
			result[key] = null if material == null else [material.albedo_color, material.albedo_texture.resource_path if material.albedo_texture != null else ""]
	return result


func _port_position(port: Dictionary) -> Vector3:
	var raw := port.get("position_m", []) as Array
	return Vector3(float(raw[0]), 0.0, float(raw[1])) if raw.size() >= 2 else Vector3(INF, INF, INF)


func _port_side_at(room: DungeonRoom3D, point: Vector3) -> String:
	for value in room.connection_ports:
		var port := value as Dictionary
		var position := _port_position(port)
		if Vector2(point.x, point.z).distance_to(Vector2(position.x, position.z)) <= PORT_TOLERANCE_M:
			var side := str(port.get("side", ""))
			if side in room.doors:
				return side
	return ""


func _door_at_owned_port(room: DungeonRoom3D, root: Node3D, piece: Node3D) -> bool:
	var transform := root.transform * piece.transform
	var side := _port_side_at(room, transform.origin)
	if side.is_empty() or not room.owns_door_endpoint(side):
		return false
	# 通用门墙局部 X 为沿墙轴；保留原角度 is_equal_approx 容差，180° 同轴有效。
	var axis := transform.basis.x.normalized()
	var angle_deg := rad_to_deg(atan2(absf(axis.z), absf(axis.x)))
	var expected_deg := 0.0 if side in ["north", "south"] else 90.0
	var basis := transform.basis.orthonormalized()
	return (
		is_equal_approx(angle_deg, expected_deg) and is_zero_approx(axis.y)
		and basis.y.is_equal_approx(Vector3.UP)
		and is_equal_approx(basis.determinant(), 1.0)
		and absf(transform.origin.y) <= POSITION_TOLERANCE_M
	)


func _boundary_side(room: DungeonRoom3D, point: Vector3) -> String:
	var half := room.get_dimensions() * 0.5
	var distances := {"north": absf(point.z + half.y), "south": absf(point.z - half.y), "west": absf(point.x + half.x), "east": absf(point.x - half.x)}
	var side := ""
	var closest := PORT_TOLERANCE_M
	for candidate in distances:
		if float(distances[candidate]) <= closest:
			side = str(candidate)
			closest = float(distances[candidate])
	return side


func _valid_solid_fill(room: DungeonRoom3D, root: Node3D, original: Node3D, fill: Node3D, source: Dictionary) -> bool:
	if not _is_door_wall(original) or not fill.position.is_equal_approx(original.position):
		return false
	var side := _boundary_side(room, root.transform * original.position)
	if side.is_empty() or side in room.doors or _is_door_wall(fill):
		return false
	for value in source.values():
		var donor := value as Node3D
		if not donor.scene_file_path.get_file().begins_with("wall") or _is_door_wall(donor):
			continue
		if _boundary_side(room, root.transform * donor.position) != side:
			continue
		if fill.scene_file_path == donor.scene_file_path and fill.basis.is_equal_approx(donor.basis):
			return true
	return false


func _check_live_role_metadata(room: DungeonRoom3D, root: Node3D, room_id: String) -> void:
	var floors := 0
	var room_type := 0
	var room_type_names: Array[String] = []
	for value in _prefab_children(root).values():
		var piece := value as Node3D
		if _is_floor_tile(piece):
			floors += 1
		if str(_metadata_value(piece, "authored_slot_role", "")) == "room_type_component":
			room_type += 1
			room_type_names.append(str(piece.name))
	if int(_metadata_value(room, "authored_layout_room_type_component_count", -1)) != room_type:
		print("STATIC_ROLE_MISMATCH %s metadata=%d entities=%d names=%s" % [room_id, int(_metadata_value(room, "authored_layout_room_type_component_count", -1)), room_type, str(room_type_names)])
	_check(int(_metadata_value(room, "authored_layout_floor_tile_count", -1)) == floors, "%s 地砖 metadata 必须等于实际实体数 %d" % [room_id, floors])
	_check(int(_metadata_value(room, "authored_layout_room_type_component_count", -1)) == room_type, "%s 房型件 metadata 必须等于实际实体数 %d" % [room_id, room_type])
	_check((room.get("_authored_tile_cells") as Array).size() == floors, "%s 主层 footprint 必须等于实际地砖数 %d" % [room_id, floors])


## 对齐仍是硬门禁：地砖逐格落在规划坐标；不要求作者陈设回到 JSON 默认布局。
func _check_plan_scene_alignment(room: DungeonRoom3D, root: Node3D, room_id: String) -> void:
	var floor_points: Array[Vector3] = []
	for value in _prefab_children(root).values():
		var piece := value as Node3D
		if _is_floor_tile(piece):
			floor_points.append(root.transform * piece.position)
	var used: Dictionary = {}
	var planned_floors := 0
	for value in room.authored_layout_instances:
		var item := value as Dictionary
		if str(item.get("slot_role", "")) != "floor_tile":
			continue
		planned_floors += 1
		var point := item.get("position", Vector3.ZERO) as Vector3
		var match_index := -1
		for index in range(floor_points.size()):
			if not used.has(index) and Vector2(point.x, point.z).distance_to(Vector2(floor_points[index].x, floor_points[index].z)) <= ALIGN_TOLERANCE_M:
				match_index = index
				break
		_check(match_index >= 0, "%s 规划地砖 %s 未与正式实体对齐：room_position=%s" % [room_id, str(item.get("name", "")), str(point)])
		if match_index >= 0:
			used[match_index] = true
	_check(planned_floors == floor_points.size(), "%s 规划/正式实体主层地砖必须一一对应：plan=%d live=%d" % [room_id, planned_floors, floor_points.size()])
	if room_id == "room_07":
		_check_room07_plan_difference(room, root)


## room07 没有独立 JSON 布局源：打印真实结构差项，不能用历史 36 或计数跳过掩盖。
func _check_room07_plan_difference(room: DungeonRoom3D, root: Node3D) -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	_check(catalog is Dictionary, "room_07 结构注册表必须可读")
	if not (catalog is Dictionary):
		return
	var paths: Dictionary = {}
	for value in (catalog as Dictionary).get("components", []):
		var component := value as Dictionary
		paths[str(component.get("component_id", ""))] = str(component.get("prefab_path", ""))
		for alias in component.get("aliases", []):
			paths[str(alias)] = str(component.get("prefab_path", ""))
	var live := _prefab_children(root)
	var used: Dictionary = {}
	var differences: Array[String] = []
	var roles: Dictionary = {}
	for value in room.authored_layout_instances:
		var item := value as Dictionary
		var role := str(item.get("slot_role", ""))
		roles[role] = int(roles.get(role, 0)) + 1
		var point := item.get("position", Vector3.ZERO) as Vector3
		var path := str(paths.get(str(item.get("component_id", "")), ""))
		var matched := false
		for instance_name in live:
			if used.has(instance_name):
				continue
			var piece := live[instance_name] as Node3D
			var position := root.transform * piece.position
			if Vector2(point.x, point.z).distance_to(Vector2(position.x, position.z)) > ALIGN_TOLERANCE_M:
				continue
			var same := not path.is_empty() and piece.scene_file_path == path
			var promoted := role in ["solid_wall", "door_wall"] and _is_door_wall(piece) and _door_at_owned_port(room, root, piece)
			if same or promoted:
				used[instance_name] = true
				matched = true
				break
		if not matched:
			var side := _port_side_at(room, point)
			if role in ["solid_wall", "door_wall"] and not side.is_empty() and not room.owns_door_endpoint(side):
				print("ROOM07_PLAN_CONVERSION remove_shared name=%s role=%s position=%s side=%s" % [str(item.get("name", "")), role, str(point), side])
			else:
				differences.append("missing name=%s role=%s path=%s room_position=%s" % [str(item.get("name", "")), role, path, str(point)])
	for instance_name in live:
		if not used.has(instance_name):
			var piece := live[instance_name] as Node3D
			differences.append("extra name=%s path=%s room_position=%s" % [instance_name, piece.scene_file_path, str(root.transform * piece.position)])
	print("ROOM07_PLAN_DIFF plan=%d roles=%s prefab=%d direct=%d metadata=%d differences=%d" % [room.authored_layout_instances.size(), str(roles), live.size(), root.get_child_count(), int(_metadata_value(root, "layout_instance_total", -1)), differences.size()])
	for difference in differences:
		print("ROOM07_PLAN_ITEM %s" % difference)
	_check(differences.is_empty(), "room_07 规划与正式结构存在未解释差项：%s" % str(differences))


func _check_static_camera_wall_contract(art_root: Node, room_id: String) -> void:
	for child in art_root.get_children():
		var corner_id := str(_metadata_value(child, "tower_wall_corner", ""))
		if not corner_id.is_empty():
			var corner_node := child as Node3D
			var basis := corner_node.global_transform.basis
			var long_along_world_x := absf(basis.x.x) >= absf(basis.x.z)
			var short_along_world_x := absf(basis.z.x) >= absf(basis.z.z)
			for value in child.find_children("*", "StaticBody3D", true, false):
				var body := value as StaticBody3D
				var expected := false
				if body.name == "WallCollisionLong":
					expected = long_along_world_x
				elif body.name == "WallCollisionShort":
					expected = short_along_world_x
				else:
					continue
				_check(
					bool(_metadata_value(body, "camera_lower_wall", false)) == expected,
					"%s %s 转角的 %s 世界朝向判定与摄像机墙标记不一致" % [
						room_id, corner_id, body.name
					]
				)
			continue
		if not (child is Node3D):
			continue
		var piece := child as Node3D
		if not _is_wall_piece(piece):
			continue
		var static_bodies: Array[Node] = []
		if piece is StaticBody3D:
			static_bodies.append(piece)
		static_bodies.append_array(piece.find_children("*", "StaticBody3D", true, false))
		if static_bodies.is_empty():
			# 标签 / 预览这类无碰撞装饰件不参与；带 side meta 的墙必须保留碰撞体。
			var direction := str(_metadata_value(piece, "tower_wall_direction", ""))
			_check(
				direction not in ["north", "south", "east", "west"],
				"%s %s 墙必须保留摄像机碰撞" % [room_id, piece.name]
			)
			continue
		# 期望值按**几何**给（墙长轴是否沿世界 X），不按 `tower_wall_direction`：
		# 该 meta 是烘焙当时的方向，房间整体旋转后即过期；且 L 型房型的**内墙**在源
		# 清单里根本没有可用的 side（room_01 内侧横墙标的是 west，几何上却与南外墙
		# 同向）—— 按 meta 判会让内墙漏标，镜头从那里穿出去。转角分支本就走几何口径。
		_check_wall_piece_camera_flags(piece, static_bodies, room_id, "")


## 逐件比对 `camera_lower_wall` 与几何口径。`context` 非空时写进失败信息
## （用于「摆到 90° 时」这类需要标明朝向的场合）。
func _check_wall_piece_camera_flags(
	piece: Node3D, static_bodies: Array[Node], room_id: String, context: String
) -> void:
	var expected := _wall_runs_along_world_x(piece)
	var prefix := "" if context.is_empty() else "%s " % context
	for value in static_bodies:
		var body := value as StaticBody3D
		_check(
			bool(_metadata_value(body, "camera_lower_wall", false)) == expected,
			"%s%s %s 墙的 %s 摄像机墙标记错误（长轴沿世界 X = %s）" % [
				prefix, room_id, piece.name, body.name, str(expected)
			]
		)


## 镜头后墙契约必须**随朝向重放**：随机拼接下每局房间朝向不同（room_01 在各局取过
## 0 / 90 / 180 / 270），而 `tower_wall_direction` 是**烘焙当时**的方向、整体旋转后即过期；
## L 型房型的**内墙**更是连 side 都没有（源清单只标外圈）。
##
## 只在当前朝向查一遍抓不住这条：实测 room_01 在 90°/180°/270° 三个朝向下共 **28 个
## 地砖格点镜头会穿墙**（玩家在走廊北段时，镜头后墙正是那道没被标记的内侧横墙），
## 而它那一局恰好落在 0°、单朝向断言全绿。所以这里把房间依次摆到另外三个朝向、
## 重放契约，再逐件比对标记与几何 —— 判据掉了这条就会当场变红。
func _check_camera_wall_rotation_invariance(
	room: DungeonRoom3D, art_root: Node3D, room_id: String
) -> void:
	var original_rotation := art_root.rotation.y
	for rotation in [90.0, 180.0, 270.0]:
		art_root.rotation.y = deg_to_rad(rotation)
		room._restore_static_layout_camera_wall_contract(art_root)
		for child in art_root.get_children():
			if not (child is Node3D):
				continue
			var piece := child as Node3D
			if not _is_wall_piece(piece) or piece.has_meta("tower_wall_corner"):
				continue
			var bodies: Array[Node] = []
			if piece is StaticBody3D:
				bodies.append(piece)
			bodies.append_array(piece.find_children("*", "StaticBody3D", true, false))
			if bodies.is_empty():
				continue
			_check_wall_piece_camera_flags(
				piece, bodies, room_id, "摆到 %d° 时" % int(rotation)
			)
	art_root.rotation.y = original_rotation
	room._restore_static_layout_camera_wall_contract(art_root)


## 墙件判定：只认组件来源（与 DungeonRoom3D._is_static_layout_wall_piece 同口径）。
func _is_wall_piece(piece: Node3D) -> bool:
	if piece.scene_file_path.is_empty():
		return piece.has_meta("tower_wall_direction")
	if piece.scene_file_path.contains("wall_door") or piece.scene_file_path.contains("door_wall"):
		return true
	return piece.scene_file_path.get_file().begins_with("wall")


## 墙长轴是否沿世界 X：取碰撞盒世界包围盒较长的一边（独立实现，不复用生产代码）。
func _wall_runs_along_world_x(piece: Node3D) -> bool:
	var bounds := AABB()
	var has_bounds := false
	for value in piece.find_children("*", "CollisionShape3D", true, false):
		var collision := value as CollisionShape3D
		var box := collision.shape as BoxShape3D
		if box == null:
			continue
		var shape_basis := collision.global_transform.basis
		var half := box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var point: Vector3 = (
						collision.global_transform.origin
						+ shape_basis * (Vector3(sx, sy, sz) * half)
					)
					if not has_bounds:
						bounds = AABB(point, Vector3.ZERO)
						has_bounds = true
					else:
						bounds = bounds.expand(point)
	if not has_bounds:
		return false
	return bounds.size.x >= bounds.size.z


func _count_nodes_with_meta(root: Node, key: StringName) -> int:
	var count := 1 if root.has_meta(key) else 0
	for child in root.get_children():
		count += _count_nodes_with_meta(child, key)
	return count


func _count_visible_nodes_with_meta(root: Node, key: StringName) -> int:
	var count := 0
	if root.has_meta(key) and root is Node3D and (root as Node3D).visible:
		count += 1
	for child in root.get_children():
		count += _count_visible_nodes_with_meta(child, key)
	return count


func _metadata_value(node: Object, key: StringName, default_value: Variant = null) -> Variant:
	if not node.has_meta(key):
		return default_value
	var value: Variant = node.get_meta(key)
	return value


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
