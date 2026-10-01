extends Node
## 规划按源布局契约验收；运行时按正式 TSCN 实体逐件验收，不以历史 metadata 代替实体。
## 地砖保留作者保存的 identity / position / color，不据两色总数宣称源布局棋盘合法。
## 默认与 --legacy 共用判据，分别覆盖新战局 180° 与无朝向字段旧快照 0°。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const STATIC_VERIFIER := preload("res://tests/verification/verify_expedition_room_static_scenes.gd")
const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")

const MANIFEST_PATH := (
	"res://assets/art/environments/tower_zones/expedition/runtime/"
	+ "room_type_components/runtime_manifest.json"
)
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const LEVEL_ID := "expedition_01"
const RUN_SEED := 77001199
const EXPECTED_COMPONENTS := 160
const COMMON_FLOOR_IDS := [
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
]
const BRIDGE_BAD_WALL_ID := "ENV-EXPEDITION-L01-BRIDGE-WALL_X670"
const GENERIC_SOLID_WALL_ID := "ENV-SHARED-GENERIC-WALL-STANDARD-5M"
const TARGETS := {
	"room_01": {
		"template_id": "corridor_45x40",
		"expected_instances": 123,
		"expected_floor_tiles": 42,
		"expected_common_floor_tiles": 42,
		"expected_room_type_components": 47,
		"expected_solid_walls": 34,
		"expected_door_walls": 0,
		"expected_version": "v012",
		"expected_asset_id": "ENV-EXPEDITION-L01-CORRIDOR-ROOM-TYPE-LAYOUT",
	},
	"room_08": {
		"template_id": "corridor_45x40",
		"expected_instances": 123,
		"expected_floor_tiles": 42,
		"expected_common_floor_tiles": 42,
		"expected_room_type_components": 47,
		"expected_solid_walls": 34,
		"expected_door_walls": 0,
		"expected_version": "v012",
		"expected_asset_id": "ENV-EXPEDITION-L01-CORRIDOR-ROOM-TYPE-LAYOUT",
	},
	"room_04": {
		"template_id": "corridor_45x40",
		"template_variant": "u_turn",
		"expected_instances": 123,
		"expected_floor_tiles": 60,
		"expected_common_floor_tiles": 60,
		"expected_room_type_components": 17,
		"expected_solid_walls": 46,
		"expected_door_walls": 0,
		"expected_version": "v001",
		"expected_asset_id": "ENV-EXPEDITION-L01-CORRIDOR-U-TURN-ROOM04-LAYOUT",
	},
	"room_03": {
		"template_id": "office_60x70",
		"expected_instances": 105,
		"expected_floor_tiles": 48,
		"expected_common_floor_tiles": 48,
		"expected_room_type_components": 28,
		"expected_solid_walls": 28,
		"expected_door_walls": 1,
		"expected_version": "v001",
		"expected_asset_id": "ENV-EXPEDITION-L01-OFFICE-ROOM03-PORT-CLEARANCE-LAYOUT",
	},
	"room_05": {
		"template_id": "bridge_60x50",
		"expected_instances": 242,
		"expected_floor_tiles": 48,
		"expected_common_floor_tiles": 48,
		"expected_room_type_components": 158,
		"expected_solid_walls": 36,
		"expected_door_walls": 0,
		"expected_version": "v010",
		"expected_asset_id": "ENV-EXPEDITION-L01-BRIDGE-ROOM-TYPE-LAYOUT",
	},
	"room_09": {
		"template_id": "office_60x70",
		"expected_instances": 106,
		"expected_floor_tiles": 48,
		"expected_common_floor_tiles": 48,
		"expected_room_type_components": 29,
		"expected_solid_walls": 28,
		"expected_door_walls": 1,
		"expected_version": "v009",
		"expected_asset_id": "ENV-EXPEDITION-L01-OFFICE-ROOM-TYPE-LAYOUT",
	},
	"boss": {
		"template_id": "boss_50x40",
		"expected_instances": 210,
		"expected_floor_tiles": 80,
		"expected_common_floor_tiles": 80,
		"expected_room_type_components": 58,
		"expected_solid_walls": 72,
		"expected_door_walls": 0,
		"expected_version": "v011",
		"expected_asset_id": "ENV-EXPEDITION-L01-BOSS-ROOM-TYPE-LAYOUT",
	},
	"room_02": {
		"template_id": "db_70x50",
		"expected_instances": 108,
		"expected_source_instances": 86,
		"expected_corner_walls": 6,
		"expected_floor_tiles": 42,
		"expected_common_floor_tiles": 42,
		"expected_room_type_components": 44,
		"expected_solid_walls": 16,
		"expected_door_walls": 0,
		"expected_version": "v014",
		"expected_asset_id": "ENV-EXPEDITION-L01-DB-ROOM-TYPE-LAYOUT",
	},
	"room_06": {
		"template_id": "db_70x50",
		"expected_instances": 108,
		"expected_source_instances": 86,
		"expected_corner_walls": 6,
		"expected_floor_tiles": 42,
		"expected_common_floor_tiles": 42,
		"expected_room_type_components": 44,
		"expected_solid_walls": 16,
		"expected_door_walls": 0,
		"expected_version": "v014",
		"expected_asset_id": "ENV-EXPEDITION-L01-DB-ROOM-TYPE-LAYOUT",
	},
	"room_10": {
		"template_id": "db_70x50",
		"expected_instances": 108,
		"expected_source_instances": 86,
		"expected_corner_walls": 6,
		"expected_floor_tiles": 42,
		"expected_common_floor_tiles": 42,
		"expected_room_type_components": 44,
		"expected_solid_walls": 16,
		"expected_door_walls": 0,
		"expected_version": "v014",
		"expected_asset_id": "ENV-EXPEDITION-L01-DB-ROOM-TYPE-LAYOUT",
	},
}

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	print("---- 远征01 房型组件重放验收 ----")
	await _check_runtime_prefabs()
	var legacy := "--legacy" in OS.get_cmdline_user_args()
	var rotation := 0 if legacy else 180
	print("REPLAY_MODE legacy=%s rotation=%d" % [str(legacy), rotation])
	var plan := GENERATOR.generate_from_level_plan(LEVEL_ID, 0, RUN_SEED, rotation)
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
		call_deferred("_finish", 0)
		return
	print("ROOM_TYPE_COMPONENT_REPLAY_FAIL checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		print("FAIL  %s" % failure)
	call_deferred("_finish", 1)


func _finish(exit_code: int) -> void:
	var exit_timer := Timer.new()
	exit_timer.one_shot = true
	exit_timer.wait_time = 0.1
	exit_timer.timeout.connect(get_tree().quit.bind(exit_code))
	get_tree().root.add_child(exit_timer)
	exit_timer.start()
	queue_free()


func _check_runtime_prefabs() -> void:
	var manifest := _read_json(MANIFEST_PATH)
	_check(not manifest.is_empty(), "运行时 manifest 必须可读")
	if manifest.is_empty():
		return
	var records := manifest.get("records", []) as Array
	_check(records.size() == EXPECTED_COMPONENTS, "PackedScene 清单应为 %d，实得 %d" % [EXPECTED_COMPONENTS, records.size()])
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
		add_child(instance)
		instantiated += 1
		_check(str(_metadata_value(instance, "asset_id", "")) == component_id, "%s 根 metadata/asset_id 必须一致" % component_id)
		_check(str(_metadata_value(instance, "asset_version", "")) == str(record.get("version", "")), "%s 根版本必须与 manifest 一致" % component_id)
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
		instance.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame
	_check(loaded == EXPECTED_COMPONENTS, "PackedScene 应 %d/%d 可加载，实得 %d" % [EXPECTED_COMPONENTS, EXPECTED_COMPONENTS, loaded])
	_check(instantiated == EXPECTED_COMPONENTS, "PackedScene 应 %d/%d 可实例化，实得 %d" % [EXPECTED_COMPONENTS, EXPECTED_COMPONENTS, instantiated])
	_check(palette_materials > 0, "导入后材质必须实际绑定公共色盘")
	print("prefabs loaded=%d instantiated=%d palette_materials=%d" % [loaded, instantiated, palette_materials])


func _check_plan_record(room_id: String, record: Dictionary, expected: Dictionary) -> void:
	var instances := record.get("authored_layout_instances", []) as Array
	_check_source_plan_contract(room_id, instances, expected)
	_check(bool(record.get("authored_layout_shell", false)), "%s 必须启用 authored_layout_shell" % room_id)
	_check(str(record.get("authored_layout_version", "")) == str(expected["expected_version"]), "%s 房型版本应为 %s" % [room_id, expected["expected_version"]])
	_check(str(record.get("authored_layout_asset_id", "")) == str(expected["expected_asset_id"]), "%s 房型 asset_id 不符" % room_id)
	if expected.has("template_variant"):
		# 运行房表的精简 record 不透传 template_variant；具体房间 asset_id 只有在生成器
		# 同时匹配 room_key/template_id/template_variant 时才会选中，因此它就是变体门禁。
		_check(str(record.get("authored_layout_asset_id", "")) == str(expected["expected_asset_id"]), "%s 必须选中 %s 差异布局" % [room_id, expected["template_variant"]])
	_check(instances.size() == int(expected["expected_instances"]), "%s 规划实例数应为 %d，实得 %d" % [room_id, int(expected["expected_instances"]), instances.size()])
	var roles := _role_counts(instances)
	_check(int(roles.get("floor_tile", 0)) == int(expected["expected_floor_tiles"]), "%s 主层地砖规划数错误：%s" % [room_id, str(roles)])
	_check(int(roles.get("room_type_component", 0)) == int(expected["expected_room_type_components"]), "%s 普通房型组件规划数错误：%s" % [room_id, str(roles)])
	_check(int(roles.get("solid_wall", 0)) == int(expected["expected_solid_walls"]), "%s 实墙规划数错误：%s" % [room_id, str(roles)])
	if expected.has("expected_corner_walls"):
		_check(int(roles.get("corner_l", 0)) == int(expected["expected_corner_walls"]), "%s L 转角规划数错误：%s" % [room_id, str(roles)])
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


## 独立读取源规划（含 remove 覆写），不从正式 TSCN 倒推规划数量。
func _check_source_plan_contract(room_id: String, instances: Array, expected: Dictionary) -> void:
	var path := "res://assets/art/environments/tower_zones/expedition/source/common_components/%s/component_instances.json" % str(expected["expected_version"])
	if room_id in ["room_03", "room_04"]:
		path = "res://assets/art/environments/tower_zones/expedition/source/room_instances/f00_%s/v001/room_layout.json" % room_id
	var source := _read_json(path)
	_check(not source.is_empty(), "%s 源规划契约必须可读：%s" % [room_id, path])
	if source.is_empty():
		return
	var declared := source.get("instances", []) as Array
	var removed: Dictionary = {}
	var validation := source.get("validation", {}) as Dictionary
	if declared.is_empty() and source.has("base_layout"):
		var base_path := str(source["base_layout"])
		if not base_path.begins_with("res://"):
			base_path = "res://" + base_path
		var base := _read_json(base_path)
		_check(not base.is_empty(), "%s base_layout 必须可读" % room_id)
		for value in source.get("instance_overrides", []):
			var override := value as Dictionary
			_check(str(override.get("op", "")) == "remove", "%s 未支持的源覆写必须失败：%s" % [room_id, str(override)])
			removed[str(override.get("instance_id", ""))] = true
		declared = []
		for value in base.get("instances", []):
			var item := value as Dictionary
			if not removed.has(str(item.get("instance_id", ""))):
				declared.append(item)
	if room_id == "room_03":
		_check(removed.size() == 1 and removed.has("filing_run_west"), "room_03 源覆写必须仅 remove filing_run_west")
	var declared_total := int(validation.get("resolved_instance_count", validation.get("instance_count", -1)))
	_check(declared_total == declared.size(), "%s 源 validation 与真实规划条目不符：declared=%d resolved=%d" % [room_id, declared_total, declared.size()])
	var by_name: Dictionary = {}
	for value in instances:
		var item := value as Dictionary
		var instance_name := str(item.get("name", ""))
		_check(not by_name.has(instance_name), "%s 规划实例 identity 重复：%s" % [room_id, instance_name])
		by_name[instance_name] = item
	for value in declared:
		var item := value as Dictionary
		var instance_name := str(item.get("instance_id", ""))
		var planned := by_name.get(instance_name, {}) as Dictionary
		_check(not planned.is_empty() and str(planned.get("component_id", "")) == str(item.get("component_id", "")), "%s 源实例必须原样承接 identity：%s" % [room_id, instance_name])
	for instance_name in removed:
		_check(not by_name.has(instance_name), "%s 已 remove 的源实例不得出现在规划：%s" % [room_id, instance_name])
	if str(expected["template_id"]) == "db_70x50":
		# v014 validation=86（floor42 + 房型44）；db_01 源轮廓周长140m=28槽，
		# 六个凸角各占两槽，剩16实墙。86+6+16=108，不从 live/TSCN 倒推。
		var verifier := STATIC_VERIFIER.new()
		var source_roles: Dictionary = {}
		for value in declared:
			var item := value as Dictionary
			var role: String = verifier._catalog_role(str(item.get("component_id", "")))
			source_roles[role] = int(source_roles.get(role, 0)) + 1
		checks += verifier.checks
		failures.append_array(verifier.failures)
		verifier.free()
		_check(declared.size() == int(expected["expected_source_instances"]), "%s 数据库源实例数必须为 %d，实得 %d" % [room_id, int(expected["expected_source_instances"]), declared.size()])
		_check(int(source_roles.get("floor_tile", 0)) == int(expected["expected_floor_tiles"]) and int(source_roles.get("room_type_component", 0)) == int(expected["expected_room_type_components"]), "%s 数据库源角色契约不符：%s" % [room_id, str(source_roles)])
		var structural_total := int(expected["expected_corner_walls"]) + int(expected["expected_solid_walls"]) + int(expected["expected_door_walls"])
		_check(declared.size() + structural_total == int(expected["expected_instances"]) and instances.size() == declared.size() + structural_total, "%s 数据库源及外围结构合同不符：source=%d structure=%d expected=%d plan=%d" % [room_id, declared.size(), structural_total, int(expected["expected_instances"]), instances.size()])
	else:
		_check(declared.size() == int(expected["expected_instances"]) and instances.size() == declared.size(), "%s 源规划数量合同不符：source=%d expected=%d plan=%d" % [room_id, declared.size(), int(expected["expected_instances"]), instances.size()])
	print("PLAN_SOURCE %s path=%s resolved=%d removed=%s runtime_plan=%d" % [room_id, path, declared.size(), str(removed.keys()), instances.size()])


func _check_live_expedition_rooms() -> void:
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	_check(tower != null, "远征01 场景必须可实例化")
	if tower == null:
		return
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	var legacy := "--legacy" in OS.get_cmdline_user_args()
	if legacy:
		tower.set("_runtime_restore_snapshot", {"world_state": {}})
	_check(tower._expedition_rotation_for_checkpoint({"world_state": {}} if legacy else {}) == (0 if legacy else 180), "旧快照/新战局朝向分支必须为 0/180")
	add_child(tower)
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	var snapshots := tower.get("_floor_plan_snapshots") as Dictionary
	var actual_plan := snapshots.get(0, {}) as Dictionary
	_check(int(actual_plan.get("expedition_global_rotation_deg", -1)) == (0 if legacy else 180), "实际运行规划必须落在所选 0/180 对照分支")
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	_check(block != null, "远征01 必须生成 Blocks/Expedition")
	if block != null:
		for room_id in TARGETS:
			var room := block.get_node_or_null(room_id) as DungeonRoom3D
			_check(room != null, "真实远征场景必须生成 %s" % room_id)
			if room != null:
				_check_runtime_room(room_id, room, TARGETS[room_id] as Dictionary)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(not is_instance_valid(tower), "远征验收场景必须在退出前完成释放")


func _check_runtime_room(room_id: String, room: DungeonRoom3D, expected: Dictionary) -> void:
	room.ensure_shell_built()
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	_check(art_root != null, "%s 必须生成 AuthoredLayoutArtRoot" % room_id)
	if art_root != null:
		var verifier := STATIC_VERIFIER.new()
		verifier._check_saved_instance_replay(room, art_root, room_id)
		verifier._check_plan_scene_alignment(room, art_root, room_id)
		checks += verifier.checks
		failures.append_array(verifier.failures)
		verifier.free()
	var unresolved := _metadata_value(room, "authored_layout_unresolved_instances", []) as Array
	_check(unresolved.is_empty(), "%s unresolved 必须为 0，实得 %s" % [room_id, str(unresolved)])
	_check(int(_metadata_value(room, "authored_layout_floor_tile_count", -1)) == int(expected["expected_floor_tiles"]), "%s 运行时主层地砖数错误" % room_id)
	# 房型规划计数不约束作者手改 TSCN；实体及统计一致性由正式场景逐件验收。
	_check(int(_metadata_value(room, "authored_layout_multi_level_count", -1)) == 0, "%s 旧程序化多层件运行时必须为 0" % room_id)
	var tile_cells := room.get("_authored_tile_cells") as Array
	_check(tile_cells.size() == int(expected["expected_floor_tiles"]), "%s 主层刷怪地砖格应为 %d，实得 %d" % [room_id, int(expected["expected_floor_tiles"]), tile_cells.size()])
	for cell_value in tile_cells:
		var cell := cell_value as Vector3
		_check(is_zero_approx(cell.y), "%s 主层地砖格 y 必须归零" % room_id)
	if room_id in ["room_03", "room_09"]:
		_check(int(_metadata_value(room, "authored_layout_door_wall_count", -1)) >= 1, "%s 必须至少实例化 1 件办公室门墙" % room_id)
	_check_runtime_floor_tiles(
		room_id, art_root, int(expected.get("expected_common_floor_tiles", expected["expected_floor_tiles"]))
	)
	_check_runtime_wall_contract(room_id, room, art_root)
	_check_door_aperture(room_id, room, art_root)
	_check_runtime_doors(room_id, room)
	print("runtime %-7s unresolved=%d floor_tiles=%d room_type=%d doors=%d" % [
		room_id,
		unresolved.size(),
		int(_metadata_value(room, "authored_layout_floor_tile_count", -1)),
		int(_metadata_value(room, "authored_layout_room_type_component_count", -1)),
		(room.get("_door_nodes") as Dictionary).size(),
	])


func _check_runtime_floor_tiles(room_id: String, art_root: Node3D, expected_count: int) -> void:
	if art_root == null:
		return
	var counts := {COMMON_FLOOR_IDS[0]: 0, COMMON_FLOOR_IDS[1]: 0}
	var total := 0
	var verifier := STATIC_VERIFIER.new()
	for child in art_root.get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		if not verifier._is_floor_tile(node):
			continue
		var component_id: String = verifier._tile_id(node)
		total += 1
		counts[component_id] = int(counts.get(component_id, 0)) + 1
		_check(
			is_equal_approx(node.position.y, float(_metadata_value(node, "walk_plane_snap_y", INF))),
			"%s 通用地砖位置必须使用自身 walk-plane 偏移" % room_id
		)
	checks += verifier.checks
	failures.append_array(verifier.failures)
	verifier.free()
	_check(total == expected_count, "%s 运行时必须用 %d 块通用地砖，实得 %d" % [room_id, expected_count, total])
	# 颜色合法性不由全局两色数量差推断；上游已逐件比较正式 TSCN 保存状态。
	print("TILE_IDENTITY %s counts=%s（仅记录作者配色，不宣称棋盘合法）" % [room_id, str(counts)])


func _check_runtime_wall_contract(room_id: String, room: DungeonRoom3D, art_root: Node3D) -> void:
	if art_root == null:
		return
	var bad_bridge_solids := 0
	for child in art_root.get_children():
		if not (child is Node3D):
			continue
		var wall := child as Node3D
		var source_id := str(_metadata_value(wall, "authored_source_component_id", ""))
		var resolved_id := str(_metadata_value(wall, "authored_component_id", ""))
		if wall.scene_file_path.contains("wall_door") or wall.scene_file_path.contains("door_wall"):
			_check_door_wall_port_axis(room_id, room, wall)
		if room_id == "room_05" and source_id == BRIDGE_BAD_WALL_ID:
			if not bool(_metadata_value(wall, "authored_door_wall_promoted", false)):
				_check(resolved_id == GENERIC_SOLID_WALL_ID, "%s 的非门槽 WALL_X670 必须替换成通用实墙" % wall.name)
				if resolved_id != GENERIC_SOLID_WALL_ID:
					bad_bridge_solids += 1
	_check(bad_bridge_solids == 0, "room_05 不得保留带门洞视觉的普通 WALL_X670")
	# 数据库源库不含 solid_wall；规划追加通用壳体的 corner6/solid16。
	# 门位仍按正式 TSCN、owner 端口、净空与 RoomDoor3D 验收，不伪造 promoted 记录。
	if room_id in ["room_01", "room_02", "room_04", "room_06", "room_08", "room_10"]:
		return
	# 每个有门的房间都至少应有一件实墙按真实门槽提升为门墙。
	var promoted := _metadata_value(room, "authored_layout_promoted_walls", []) as Array
	_check(not promoted.is_empty(), "%s 至少应有一件实墙按真实门槽提升为门墙" % room_id)


## 门墙在房间帧中与真实端口位置和沿墙轴对齐；历史方向 metadata 不参与判定。
func _check_door_wall_port_axis(room_id: String, room: DungeonRoom3D, wall: Node3D) -> void:
	var to_room := room.global_transform.affine_inverse() * wall.global_transform
	var matched := false
	for value in room.connection_ports:
		var port := value as Dictionary
		var raw := port.get("position_m", []) as Array
		var side := str(port.get("side", ""))
		if raw.size() < 2 or side not in room.doors:
			continue
		var position := Vector3(float(raw[0]), 0.0, float(raw[1]))
		if Vector2(to_room.origin.x, to_room.origin.z).distance_to(Vector2(position.x, position.z)) > 0.25:
			continue
		matched = true
		var axis := to_room.basis.x.normalized()
		var angle_deg := rad_to_deg(atan2(absf(axis.z), absf(axis.x)))
		var expected_deg := 0.0 if side in ["north", "south"] else 90.0
		var basis := to_room.basis.orthonormalized()
		_check(is_equal_approx(angle_deg, expected_deg) and is_zero_approx(axis.y) and basis.y.is_equal_approx(Vector3.UP) and is_equal_approx(basis.determinant(), 1.0), "%s 门墙 %s room 轴与真实 %s 端口不符：angle_deg=%f transform=%s port=%s" % [room_id, wall.name, side, angle_deg, str(to_room), str(position)])
		_check(room.owns_door_endpoint(side), "%s 门墙 %s 不得占用非 owner 的 %s 端口" % [room_id, wall.name, side])
	_check(matched, "%s 门墙 %s 未对齐任何真实端口：room_transform=%s ports=%s" % [room_id, wall.name, str(to_room), str(room.connection_ports)])


## 门位必须**真的留出通透门洞**：升降门板上行时，净空区里不能有本层任何几何。
##
## 判据用**房间局部空间**的净空盒，与「门位由谁承接」无关：
##   沿墙轴 ±1.05m（门宽 2.2 的一半）、竖直 y ∈ [0.15, 2.35]（净高 2.5 去掉上下余量）、
##   法向 ±0.4m —— **只覆盖墙带**（墙厚 0.3 加余量），不含站在门前的家具。
## 这一条必须写死：Boss 房东门口有两台机柜，其角会探进 ±1.05×±0.6 的盒子，但它们是
## 门内陈设、不是墙；而且门靠**整体升降**开合而不是平开 ⇒ 不构成阻挡。
##
## 反例（2026-09-27 实测）：办公室 v009 的 `door_wall` 件门洞区正投影覆盖率 100%，
## 门扇整个被埋在实心墙里，开与不开画面完全一致 —— 只数门扇存在是查不出来的。
## 另一个反例：Boss 房源预切的门洞（南 x=+2.5 / 西 z=+2.5）与本关门位（西/东 z=−2.5）
## 不一致，净空里没有任何门扇 ⇒ 入库时已按 02 规范封成整樘实墙。
func _check_door_aperture(room_id: String, room: DungeonRoom3D, art_root: Node3D) -> void:
	if art_root == null:
		return
	for direction_value in room.doors:
		var direction := str(direction_value)
		var door := room.get_door_node(direction)
		if door == null:
			continue
		# 共享门可能由邻房 owner 创建；门、网格、碰撞统一经世界坐标转到当前 room。
		var lane := room.global_transform.affine_inverse() * door.global_position
		var blocked := 0
		for child in art_root.get_children():
			if not (child is Node3D):
				continue
			blocked += _count_vertices_in_door_clear_box(child as Node3D, room, direction, lane)
		# 检查整个远征区块，含邻房拥有的共墙；动态门扇碰撞由门的开合合同承接。
		var collision_root := room.get_parent() as Node3D
		var collided := _count_shapes_in_door_clear_box(collision_root, room, direction, lane)
		_check(
			blocked == 0,
			"%s 的 %s 门位门洞被 %d 个顶点封住（门洞未通透）"
			% [room_id, direction, blocked]
		)
		# 顶点检查对**简单盒体网格**是盲的：8 个角点全落在 5m 模块四角，窄窗（沿墙 ±1.05m）
		# 内一个顶点都没有，可整块代孕碰撞盒却横跨门洞。2026-09-28 Boss 房门模块墙皮
		# `WALL_SKIN_ARMORED_BROKEN_5M`（碰撞 0.36×11.8×4.925）实测正是如此：门洞视觉通透、
		# 玩家走进去却被隐形盒挡住（「空阻挡」）。故必须与顶点检查互为补集，同时查碰撞盒。
		_check(
			collided == 0,
			"%s 的 %s 门位门洞被 %d 个碰撞盒封住（空阻挡）"
			% [room_id, direction, collided]
		)


## 净空盒内的顶点数：统一转到当前 room，不用旋转后的美术根帧。
func _count_vertices_in_door_clear_box(
	module: Node3D, room: Node3D, direction: String, lane: Vector3
) -> int:
	var blocked := 0
	for node in _mesh_instances_of(module):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var to_room_from_mesh := room.global_transform.affine_inverse() * mesh_instance.global_transform
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for vertex in vertices:
				var local := to_room_from_mesh * vertex
				if local.y < 0.15 or local.y > 2.35:
					continue
				if direction in ["north", "south"]:
					if absf(local.x - lane.x) <= 1.05 and absf(local.z - lane.z) <= 0.4:
						blocked += 1
				elif absf(local.z - lane.z) <= 1.05 and absf(local.x - lane.x) <= 0.4:
					blocked += 1
	return blocked


## 门洞净空盒（当前 room 局部）：沿墙轴 ±1.05m、法向 ±0.4m。
## 与顶点检查同一口径：只覆盖墙带，不含站在门前的家具（家具角常探到法向 ±0.6m）。
func _door_clear_box(direction: String, lane: Vector3, top: float) -> AABB:
	var height := top - 0.15
	if direction in ["north", "south"]:
		return AABB(Vector3(lane.x - 1.05, 0.15, lane.z - 0.4), Vector3(2.10, height, 0.80))
	return AABB(Vector3(lane.x - 0.4, 0.15, lane.z - 1.05), Vector3(0.80, height, 2.10))


## 净空盒内与之相交的碰撞盒数（用形状 AABB 的保守包络求交；门墙分段件天然留出余量）。
func _count_shapes_in_door_clear_box(
	module: Node3D, room: Node3D, direction: String, lane: Vector3
) -> int:
	# 碰撞口径按「玩家能否通过」定：玩家胶囊高 1.5m ⇒ 取到 1.90m 留余量。
	# 不用网格检查的 2.35m：门墙门楣的名义净高 2.5m 是相对墙底，墙件下沉 0.358m
	# 落地后实际约 2.14m（玩家仍可通过），用 2.35 会把合法门楣判成阻挡。
	var clear := _door_clear_box(direction, lane, 1.90)
	var count := 0
	for node in _collision_shapes_of(module):
		var shape_node := node as CollisionShape3D
		if shape_node == null or shape_node.shape == null or shape_node.disabled:
			continue
		# 形状所属物理 owner，不是编辑器 Node.owner；Area/相机层不阻挡玩家。
		var body := shape_node.get_parent() as StaticBody3D
		if body == null or (body.collision_layer & 1) == 0:
			continue
		var cursor: Node = body
		var runtime_door := false
		while cursor != null and cursor != module:
			if cursor is RoomDoor3D:
				runtime_door = true
				break
			cursor = cursor.get_parent()
		if runtime_door:
			continue
		var to_room := room.global_transform.affine_inverse() * shape_node.global_transform
		var bounds: AABB = to_room * _shape_aabb(shape_node.shape)
		if bounds.intersects(clear):
			count += 1
			print("DOOR_BLOCKER room=%s side=%s shape=%s owner=%s layer=%d bounds=%s clear=%s" % [room.name, direction, str(shape_node.get_path()), str(body.get_path()), body.collision_layer, str(bounds), str(clear)])
	return count


## Shape3D 在 Godot 4 **没有** get_aabb()（调用会报 "Nonexistent function"）；
## 必须按形状类型取尺寸。基础体走显式分支（组件库绝大多数是 BoxShape3D），
## 其余退回调试网格包围盒。
func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var box := (shape as BoxShape3D).size
		return AABB(-box * 0.5, box)
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r * 2.0, r * 2.0, r * 2.0))
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		return AABB(
			Vector3(-cap.radius, -cap.height * 0.5, -cap.radius),
			Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0),
		)
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return AABB(
			Vector3(-cyl.radius, -cyl.height * 0.5, -cyl.radius),
			Vector3(cyl.radius * 2.0, cyl.height, cyl.radius * 2.0),
		)
	var debug_mesh := shape.get_debug_mesh()
	return debug_mesh.get_aabb() if debug_mesh != null else AABB()


## 模块自身或后代的全部 CollisionShape3D（含根本身）。
func _collision_shapes_of(module: Node3D) -> Array[Node]:
	var shapes: Array[Node] = []
	if module is CollisionShape3D:
		shapes.append(module)
	shapes.append_array(module.find_children("*", "CollisionShape3D", true, false))
	return shapes


## 模块自身或后代的全部 MeshInstance3D（含根本身）。
func _mesh_instances_of(module: Node3D) -> Array[Node]:
	var meshes: Array[Node] = []
	if module is MeshInstance3D:
		meshes.append(module)
	meshes.append_array(module.find_children("*", "MeshInstance3D", true, false))
	return meshes


## 门扇：RoomDoor3D 必须存在、带 ImportedDoorVisual、且至少一扇可见。
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


func _metadata_value(node: Object, key: StringName, default_value: Variant = null) -> Variant:
	if not node.has_meta(key):
		return default_value
	var value: Variant = node.get_meta(key)
	return value


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
