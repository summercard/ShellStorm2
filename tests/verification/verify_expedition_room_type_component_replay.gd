extends Node
## 验收：办公室 v006 与通道桥 v007 逐组件导入、默认布局重放及运行时拼装。
##
## 覆盖四层契约：
## ① runtime_manifest 中 60 个稳定 PackedScene 均可独立加载/实例化，且资产元数据与公共色盘绑定完整；
## ② FloorPlanGenerator 对 room_03/room_09 重放 106 件、room_05 重放 242 件；
## ③ DungeonRoom3D 实际生成同数实例且 unresolved=0，桥房旧 multi_level_component=0；
## ④ 办公室门墙/RoomDoor3D 门扇与主层地砖存在，桥房 tile_lower 不进入主层刷怪格。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")

const MANIFEST_PATH := (
	"res://assets/art/environments/tower_zones/expedition/runtime/"
	+ "room_type_components/runtime_manifest.json"
)
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const LEVEL_ID := "expedition_01"
const RUN_SEED := 77001199
const EXPECTED_COMPONENTS := 60
const COMMON_FLOOR_IDS := [
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
]
const BRIDGE_BAD_WALL_ID := "ENV-EXPEDITION-L01-BRIDGE-WALL_X670"
const GENERIC_SOLID_WALL_ID := "ENV-SHARED-GENERIC-WALL-STANDARD-5M"
const TARGETS := {
	"room_03": {
		"template_id": "office_60x70",
		"expected_instances": 106,
		"expected_floor_tiles": 48,
		"expected_room_type_components": 29,
		"expected_solid_walls": 28,
		"expected_door_walls": 1,
		"expected_version": "v006",
		"expected_asset_id": "ENV-EXPEDITION-L01-OFFICE-ROOM-TYPE-LAYOUT",
	},
	"room_05": {
		"template_id": "bridge_60x50",
		"expected_instances": 242,
		"expected_floor_tiles": 48,
		"expected_room_type_components": 158,
		"expected_solid_walls": 36,
		"expected_door_walls": 0,
		"expected_version": "v007",
		"expected_asset_id": "ENV-EXPEDITION-L01-BRIDGE-ROOM-TYPE-LAYOUT",
	},
	"room_09": {
		"template_id": "office_60x70",
		"expected_instances": 106,
		"expected_floor_tiles": 48,
		"expected_room_type_components": 29,
		"expected_solid_walls": 28,
		"expected_door_walls": 1,
		"expected_version": "v006",
		"expected_asset_id": "ENV-EXPEDITION-L01-OFFICE-ROOM-TYPE-LAYOUT",
	},
}

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	print("---- 远征01 房型组件重放验收 ----")
	_check_runtime_prefabs()
	var plan := GENERATOR.generate_from_level_plan(LEVEL_ID, 0, RUN_SEED)
	_check(bool(plan.get("valid", false)), "关卡规划应有效：%s" % str(plan.get("validation_errors", [])))
	if bool(plan.get("valid", false)):
		var rooms := plan.get("rooms", []) as Array
		for room_id in TARGETS:
			var record := _room_record(rooms, room_id)
			_check(not record.is_empty(), "规划中必须存在 %s" % room_id)
			if not record.is_empty():
				_check_plan_record(room_id, record, TARGETS[room_id] as Dictionary)
	await _check_live_expedition_rooms()
	if failures.is_empty():
		print("ROOM_TYPE_COMPONENT_REPLAY_OK checks=%d" % checks)
		get_tree().quit(0)
		return
	print("ROOM_TYPE_COMPONENT_REPLAY_FAIL checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		print("FAIL  %s" % failure)
	get_tree().quit(1)


func _check_runtime_prefabs() -> void:
	var manifest := _read_json(MANIFEST_PATH)
	_check(not manifest.is_empty(), "运行时 manifest 必须可读")
	if manifest.is_empty():
		return
	var records := manifest.get("records", []) as Array
	_check(records.size() == EXPECTED_COMPONENTS, "PackedScene 清单应为 60，实得 %d" % records.size())
	var ids: Dictionary = {}
	var loaded := 0
	var instantiated := 0
	var palette_materials := 0
	for value in records:
		var record := value as Dictionary
		var component_id := str(record.get("component_id", ""))
		var prefab_path := str(record.get("prefab_path", ""))
		_check(not component_id.is_empty(), "运行时组件不得缺 component_id")
		_check(not ids.has(component_id), "运行时组件 ID 不得重复：%s" % component_id)
		ids[component_id] = true
		_check(ResourceLoader.exists(prefab_path), "%s 的 PackedScene 路径必须存在" % component_id)
		if not ResourceLoader.exists(prefab_path):
			continue
		var packed := load(prefab_path) as PackedScene
		_check(packed != null, "%s 必须可加载为 PackedScene" % component_id)
		if packed == null:
			continue
		loaded += 1
		var instance := packed.instantiate() as Node3D
		_check(instance != null, "%s 必须可实例化为 Node3D" % component_id)
		if instance == null:
			continue
		instantiated += 1
		_check(str(instance.get_meta("asset_id", "")) == component_id, "%s 根 metadata/asset_id 必须一致" % component_id)
		_check(str(instance.get_meta("asset_version", "")) == str(record.get("version", "")), "%s 根版本必须与 manifest 一致" % component_id)
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		_check(not meshes.is_empty(), "%s 的 ImportedModel 后代必须含 MeshInstance3D" % component_id)
		for mesh_value in meshes:
			var mesh_instance := mesh_value as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
				_check(material != null, "%s 的表面 %d 必须有 BaseMaterial3D" % [component_id, surface])
				if material == null:
					continue
				var texture := material.albedo_texture
				_check(texture != null, "%s 的表面 %d 必须绑定公共色盘" % [component_id, surface])
				if texture != null:
					_check(texture.resource_path == PALETTE_PATH, "%s 的表面 %d 色盘路径错误：%s" % [component_id, surface, texture.resource_path])
					if texture.resource_path == PALETTE_PATH:
						palette_materials += 1
		instance.free()
	_check(loaded == EXPECTED_COMPONENTS, "PackedScene 应 60/60 可加载，实得 %d" % loaded)
	_check(instantiated == EXPECTED_COMPONENTS, "PackedScene 应 60/60 可实例化，实得 %d" % instantiated)
	_check(palette_materials > 0, "导入后材质必须实际绑定公共色盘")
	print("prefabs loaded=%d instantiated=%d palette_materials=%d" % [loaded, instantiated, palette_materials])


func _check_plan_record(room_id: String, record: Dictionary, expected: Dictionary) -> void:
	var instances := record.get("authored_layout_instances", []) as Array
	_check(bool(record.get("authored_layout_shell", false)), "%s 必须启用 authored_layout_shell" % room_id)
	_check(str(record.get("authored_layout_version", "")) == str(expected["expected_version"]), "%s 房型版本应为 %s" % [room_id, expected["expected_version"]])
	_check(str(record.get("authored_layout_asset_id", "")) == str(expected["expected_asset_id"]), "%s 房型 asset_id 不符" % room_id)
	_check(instances.size() == int(expected["expected_instances"]), "%s 规划实例数应为 %d，实得 %d" % [room_id, int(expected["expected_instances"]), instances.size()])
	var roles := _role_counts(instances)
	_check(int(roles.get("floor_tile", 0)) == int(expected["expected_floor_tiles"]), "%s 主层地砖规划数错误：%s" % [room_id, str(roles)])
	_check(int(roles.get("room_type_component", 0)) == int(expected["expected_room_type_components"]), "%s 普通房型组件规划数错误：%s" % [room_id, str(roles)])
	_check(int(roles.get("solid_wall", 0)) == int(expected["expected_solid_walls"]), "%s 实墙规划数错误：%s" % [room_id, str(roles)])
	_check(int(roles.get("door_wall", 0)) == int(expected["expected_door_walls"]), "%s 门墙规划数错误：%s" % [room_id, str(roles)])
	_check(int(roles.get("multi_level_component", 0)) == 0, "%s 不得叠加旧程序化 multi_level_component" % room_id)
	if room_id == "room_05":
		var lower_tiles := 0
		for value in instances:
			var instance := value as Dictionary
			if str(instance.get("component_id", "")) == "ENV-EXPEDITION-L01-BRIDGE-TILE_LOWER":
				lower_tiles += 1
				_check(str(instance.get("slot_role", "")) == "room_type_component", "tile_lower 必须是普通视觉件而非 floor_tile")
				_check((instance.get("position", Vector3.ZERO) as Vector3).y < -10.0, "tile_lower 必须保留下沉标高")
		_check(lower_tiles == 36, "room_05 应含 36 块坑底 tile_lower，实得 %d" % lower_tiles)
	print("plan %-7s instances=%d roles=%s" % [room_id, instances.size(), str(roles)])


func _check_live_expedition_rooms() -> void:
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	_check(tower != null, "远征01 场景必须可实例化")
	if tower == null:
		return
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	_check(block != null, "远征01 必须生成 Blocks/Expedition")
	if block != null:
		for room_id in TARGETS:
			var room := block.get_node_or_null(room_id) as DungeonRoom3D
			_check(room != null, "真实远征场景必须生成 %s" % room_id)
			if room != null:
				_check_runtime_room(room_id, room, TARGETS[room_id] as Dictionary)
	remove_child(tower)
	tower.free()


func _check_runtime_room(room_id: String, room: DungeonRoom3D, expected: Dictionary) -> void:
	room.ensure_shell_built()
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	_check(art_root != null, "%s 必须生成 AuthoredLayoutArtRoot" % room_id)
	if art_root != null:
		_check(int(art_root.get_meta("layout_instance_total", -1)) == int(expected["expected_instances"]), "%s 美术根记录的布局实例数错误" % room_id)
	var unresolved := room.get_meta("authored_layout_unresolved_instances", []) as Array
	_check(unresolved.is_empty(), "%s unresolved 必须为 0，实得 %s" % [room_id, str(unresolved)])
	_check(int(room.get_meta("authored_layout_floor_tile_count", -1)) == int(expected["expected_floor_tiles"]), "%s 运行时主层地砖数错误" % room_id)
	_check(int(room.get_meta("authored_layout_room_type_component_count", -1)) == int(expected["expected_room_type_components"]), "%s 运行时普通房型组件数错误" % room_id)
	_check(int(room.get_meta("authored_layout_multi_level_count", -1)) == 0, "%s 旧程序化多层件运行时必须为 0" % room_id)
	var tile_cells := room.get("_authored_tile_cells") as Array
	_check(tile_cells.size() == int(expected["expected_floor_tiles"]), "%s 主层刷怪地砖格应为 %d，实得 %d" % [room_id, int(expected["expected_floor_tiles"]), tile_cells.size()])
	for cell_value in tile_cells:
		var cell := cell_value as Vector3
		_check(is_zero_approx(cell.y), "%s 主层地砖格 y 必须归零" % room_id)
	if room_id in ["room_03", "room_09"]:
		_check(int(room.get_meta("authored_layout_door_wall_count", -1)) >= 1, "%s 必须至少实例化 1 件办公室门墙" % room_id)
	_check_runtime_floor_tiles(room_id, art_root, int(expected["expected_floor_tiles"]))
	_check_runtime_wall_contract(room_id, room, art_root)
	_check_door_aperture(room_id, room, art_root)
	_check_runtime_doors(room_id, room)
	print("runtime %-7s unresolved=%d floor_tiles=%d room_type=%d doors=%d" % [
		room_id,
		unresolved.size(),
		int(room.get_meta("authored_layout_floor_tile_count", -1)),
		int(room.get_meta("authored_layout_room_type_component_count", -1)),
		(room.get("_door_nodes") as Dictionary).size(),
	])


func _check_runtime_floor_tiles(room_id: String, art_root: Node3D, expected_count: int) -> void:
	if art_root == null:
		return
	var counts := {COMMON_FLOOR_IDS[0]: 0, COMMON_FLOOR_IDS[1]: 0}
	var total := 0
	for child in art_root.get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		var component_id := str(node.get_meta("authored_component_id", ""))
		if component_id not in COMMON_FLOOR_IDS:
			continue
		total += 1
		counts[component_id] = int(counts[component_id]) + 1
		_check(
			is_equal_approx(node.position.y, float(node.get_meta("walk_plane_snap_y", INF))),
			"%s 通用地砖位置必须使用自身 walk-plane 偏移" % room_id
		)
	_check(total == expected_count, "%s 运行时必须用 %d 块通用地砖，实得 %d" % [room_id, expected_count, total])
	_check(abs(int(counts[COMMON_FLOOR_IDS[0]]) - int(counts[COMMON_FLOOR_IDS[1]])) <= 1, "%s 通用地砖必须按 C01/C02 棋盘交替：%s" % [room_id, str(counts)])


func _check_runtime_wall_contract(room_id: String, room: DungeonRoom3D, art_root: Node3D) -> void:
	if art_root == null:
		return
	var bad_bridge_solids := 0
	for child in art_root.get_children():
		if not (child is Node3D):
			continue
		var wall := child as Node3D
		var source_id := str(wall.get_meta("authored_source_component_id", ""))
		var resolved_id := str(wall.get_meta("authored_component_id", ""))
		var direction := str(wall.get_meta("tower_wall_direction", ""))
		if direction.is_empty():
			continue
		var expected_yaw := 0.0 if direction in ["north", "south"] else 90.0
		if bool(wall.get_meta("authored_door_wall_promoted", false)):
			_check(
				is_equal_approx(absf(rad_to_deg(wall.rotation.y)), expected_yaw),
				"%s 的 %s 门墙旋转必须与 %s 墙面一致，实得 %.1f°"
				% [room_id, wall.name, direction, rad_to_deg(wall.rotation.y)]
			)
		if room_id == "room_05" and source_id == BRIDGE_BAD_WALL_ID:
			if not bool(wall.get_meta("authored_door_wall_promoted", false)):
				_check(resolved_id == GENERIC_SOLID_WALL_ID, "%s 的非门槽 WALL_X670 必须替换成通用实墙" % wall.name)
				if resolved_id != GENERIC_SOLID_WALL_ID:
					bad_bridge_solids += 1
	_check(bad_bridge_solids == 0, "room_05 不得保留带门洞视觉的普通 WALL_X670")
	var promoted := room.get_meta("authored_layout_promoted_walls", []) as Array
	_check(not promoted.is_empty(), "%s 至少应有一件实墙按真实门槽提升为门墙" % room_id)


## 门位门墙必须**真的留出通透门洞**：升降门板上行时，门洞区里不能有墙件几何。
## 2.2×2.5m 净空由 TowerGeometry3D 定义；这里在门墙模块的局部坐标里判，
## 与模块朝向无关（局部 X 恒为墙宽轴）。
## 反例（2026-09-27 实测）：办公室 v006 的 `door_wall` 件门洞区正投影覆盖率 100%，
## 门扇整个被埋在实心墙里，开与不开画面完全一致 —— 只数门扇存在是查不出来的。
func _check_door_aperture(room_id: String, room: DungeonRoom3D, art_root: Node3D) -> void:
	if art_root == null:
		return
	for direction_value in room.doors:
		var direction := str(direction_value)
		var door := room.get_door_node(direction)
		if door == null:
			continue
		var wall := _door_lane_wall(art_root, direction, _along_of(door.position, direction))
		_check(wall != null, "%s 的 %s 门位必须有一件门墙承接" % [room_id, direction])
		if wall == null:
			continue
		var blocked := _count_geometry_in_door_clear_region(wall)
		_check(
			blocked == 0,
			"%s 的 %s 门位门洞被 %d 个顶点封住（门墙未切通透门洞）"
			% [room_id, direction, blocked]
		)


func _along_of(local_position: Vector3, direction: String) -> float:
	return (
		local_position.x
		if direction in ["north", "south"]
		else local_position.z
	)


## 门槽车道上那件门墙：按 tower_wall_direction + 沿墙坐标匹配（容差沿用门槽判据）。
func _door_lane_wall(art_root: Node3D, direction: String, along: float) -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	for child in art_root.get_children():
		var module := child as Node3D
		if module == null:
			continue
		if str(module.get_meta("tower_wall_direction", "")) != direction:
			continue
		var gap := absf(_along_of(module.position, direction) - along)
		if gap <= 0.3 and gap < best_gap:
			best_gap = gap
			best = module
	return best


## 门洞净空区（局部 |x| ≤ 1.1、y ∈ [0, 2.5]）内的墙件顶点数。
func _count_geometry_in_door_clear_region(module: Node3D) -> int:
	var to_module := module.global_transform.affine_inverse()
	var blocked := 0
	for node in module.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var to_module_from_mesh := to_module * mesh_instance.global_transform
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for vertex in vertices:
				var local := to_module_from_mesh * vertex
				if (
					absf(local.x) <= 1.05
					and local.y >= 0.15
					and local.y <= 2.35
				):
					blocked += 1
	return blocked


func _check_runtime_doors(room_id: String, room: DungeonRoom3D) -> void:
	var door_nodes := room.get("_door_nodes") as Dictionary
	_check(door_nodes.size() == room.doors.size(), "%s RoomDoor3D 数应与 doors 一致" % room_id)
	var visible_mesh_doors := 0
	for direction_value in door_nodes:
		var door := door_nodes[direction_value] as RoomDoor3D
		_check(door != null, "%s 的 %s 门节点必须是 RoomDoor3D" % [room_id, str(direction_value)])
		if door == null:
			continue
		var imported := door.get_node_or_null("DoorPanel/ImportedDoorVisual")
		_check(imported != null, "%s 的 %s 门必须有 ImportedDoorVisual" % [room_id, str(direction_value)])
		if imported == null:
			continue
		var meshes := imported.find_children("*", "MeshInstance3D", true, false)
		if imported is MeshInstance3D:
			meshes.append(imported)
		_check(not meshes.is_empty(), "%s 的 %s 门扇自身或后代必须有 MeshInstance3D（根类型=%s）" % [room_id, str(direction_value), imported.get_class()])
		var panel := door.get_node_or_null("DoorPanel") as Node3D
		if panel != null and panel.visible and not meshes.is_empty():
			visible_mesh_doors += 1
	_check(visible_mesh_doors >= 1, "%s 至少应有一扇可见且含 MeshInstance3D 的门扇" % room_id)


func _role_counts(instances: Array) -> Dictionary:
	var counts: Dictionary = {}
	for value in instances:
		var role := str((value as Dictionary).get("slot_role", ""))
		counts[role] = int(counts.get(role, 0)) + 1
	return counts


func _room_record(rooms: Array, room_id: String) -> Dictionary:
	for value in rooms:
		var room := value as Dictionary
		if str(room.get("id", "")) == room_id or str(room.get("key", "")) == room_id:
			return room
	return {}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
