extends Node
## 临时探针：实测远征关卡01 的**整层地砖**到底来自哪个 PackedScene。
## 判据不读代码分支，只比运行时 MultiMesh 里那把 mesh 与三个候选场景解析出的 mesh
## 是不是同一个资源（同一性），并打印各自的 AABB 做反向对照。
## 只读，不修改任何运行内容。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const CANDIDATES := [
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m.tscn",
	"res://assets/art/environments/tower_descent_3d/runtime/floor_tile_5m/env_tower_floor_tile_5m_root_top3d.tscn",
	"res://assets/art/props/dungeon_3d/prp_rooftop_floor_5m.tscn",
	"res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn",
	"res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d.tscn",
]

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

	var stages: Dictionary = _tower.get("_floor_stages")
	print("=== floor_stages keys=%s ===" % str(stages.keys()))
	var found := false
	for key in stages.keys():
		var stage: Node = stages[key]
		print("--- floor_index=%s name=%s kind=%s force_standard_map=%s block_id=%s" % [
			str(stage.get("floor_index")),
			str(stage.name),
			str(stage.get("floor_kind")),
			str(stage.get("force_standard_map")),
			str(stage.get_meta("block_id", "-")),
		])
		for prop in ["_floor_visual_light", "_floor_visual_dark"]:
			var mm := stage.get(prop) as MultiMeshInstance3D
			if mm == null or mm.multimesh == null:
				print("   %-22s <null>" % prop)
				continue
			var mesh: Mesh = mm.multimesh.mesh
			print("   %-22s instances=%d  mesh=%s  res_name=%s  aabb_size=%s" % [
				prop, mm.multimesh.instance_count,
				mesh.resource_path if mesh != null else "<null>",
				mesh.resource_name if mesh != null else "<null>",
				_v3((mesh.get_aabb().size) if mesh != null else Vector3.ZERO),
			])
			if mesh == null:
				continue
			for candidate in CANDIDATES:
				var packed := load(candidate) as PackedScene
				if packed == null:
					continue
				var source := packed.instantiate()
				var candidate_mesh := GEOMETRY.resolve_visual_mesh(source)
				var same := candidate_mesh != null and candidate_mesh == mesh
				print("        %s  same_object=%s  cand_aabb=%s" % [
					candidate.get_file(), str(same),
					_v3(candidate_mesh.get_aabb().size if candidate_mesh != null else Vector3.ZERO),
				])
				if same:
					found = true
				source.free()
	print("")
	print("=== 入口安全房自持地砖（SafeRoomFloorTile_*）===")
	var rooms: Dictionary = _tower.get("_room_by_id")
	var room := rooms.get("start") as DungeonRoom3D
	if room == null:
		print("  找不到 start 房")
	else:
		room.ensure_shell_built()
		await get_tree().process_frame
		var count := 0
		for value in room.find_children("SafeRoomFloorTile_*", "Node3D", true, false):
			var tile := value as Node3D
			print("  %-26s asset_id=%s  snap_y=%s" % [
				str(tile.name),
				str(tile.get_meta("asset_id", "-")),
				str(tile.get_meta("walk_plane_snap_y", "-")),
			])
			count += 1
		print("  合计 %d 件；room_type=%s" % [count, room.room_type])
	print("")
	if found:
		print("PROBE_EXPEDITION_FLOOR_SOURCE_OK")
	else:
		print("PROBE_EXPEDITION_FLOOR_SOURCE_FAIL: 整层地砖不在候选清单内")
	get_tree().quit(0 if found else 1)


func _v3(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]
