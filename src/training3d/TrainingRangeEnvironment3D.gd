class_name TrainingRangeEnvironment3D
extends Node3D
## 靶场空间资产：10×10 块 5m 地砖铺满 50×50m 场地，四周用 5m 标准墙段封死；
## 另含三条射击道、装备墙、工作台与废土灯光。
##
## 地面与封边直接实例化「战局区块通用组件库 v004」的正式美术件（自带碰撞）；
## 标线、装备墙、工作台与掩体仍走程序化 BoxMesh。
##
## 地砖原点契约 = 底面中心（Y=0 是砖底，不是砖面）。c01 结构厚 0.056、c02 厚 0.081，
## 两者顶面不同高；本脚本按各自厚度把实例整体下移，使**所有砖面顶都落在行走面 Y=0**，
## 否则棋盘格铺法会每隔一格出现 25mm 台阶。这层换算必须与 prefab 的
## snap_to_walk_plane_offset_m 保持一致，改砖就必须同步改下面的两个常量。

const LIGHT_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_wasteland_light_root_top3d.tscn")
const FLOOR_TILE_C01_SCENE: PackedScene = preload("res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn")
const FLOOR_TILE_C02_SCENE: PackedScene = preload("res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d.tscn")
const WALL_SEGMENT_SCENE: PackedScene = preload("res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn")

## 5m 网格铺 10×10 块 = 50×50m 场地，坐标范围 X/Z ∈ [-25, 25]。
const GRID_UNIT_M := 5.0
const GRID_TILES := 10
const HALF_EXTENT := 25.0
## 砖面顶对齐行走面所需的实例 Y 偏移（= prefab 的 snap_to_walk_plane_offset_m）。
const TILE_SNAP_Y_C01 := -0.056
const TILE_SNAP_Y_C02 := -0.081
## 三条射击道中心线（沿用改造前位置，保持既有靶位与镜头预览口径不变）。
const LANE_X := [-8.0, 0.0, 8.0]
## 灯光网格 3 列 × 4 行 = 12 盏，覆盖整块 50×50 场地。
const LIGHT_COL_X := [-15.0, 0.0, 15.0]
const LIGHT_ROW_Z := [-20.0, -8.0, 4.0, 16.0]

var _metal: StandardMaterial3D
var _accent: StandardMaterial3D
var _tile_counts := {"c01": 0, "c02": 0}
var _wall_segment_count := 0


func _ready() -> void:
	add_to_group("training_environment_3d")
	_metal = _material(Color(0.16, 0.18, 0.18), 0.66, 0.52)
	_accent = _material(Color(0.88, 0.48, 0.13), 0.50, 0.38, true)
	_build_floor_tiles()
	_build_boundary_walls()
	_build_shooting_lanes()
	_build_equipment_wall()
	_build_lighting()
	_build_furniture()


func get_snapshot() -> Dictionary:
	return {
		"has_shooting_lanes": get_node_or_null("ShootingLanes") != null,
		"has_equipment_wall": get_node_or_null("EquipmentWall") != null,
		"has_workbench": get_node_or_null("Workbench") != null,
		"light_count": get_tree().get_nodes_in_group("training_light_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"floor_tile_count": int(_tile_counts["c01"]) + int(_tile_counts["c02"]),
		"boundary_wall_segment_count": _wall_segment_count,
		"arena_size_m": GRID_UNIT_M * float(GRID_TILES),
		"is_3d": true,
	}


## 10×10 块地砖棋盘格交替铺满；c01 是角块与中心块、c02 是边中块。
func _build_floor_tiles() -> void:
	var floor_root := Node3D.new()
	floor_root.name = "FloorTiles"
	add_child(floor_root)
	for row in range(GRID_TILES):
		for column in range(GRID_TILES):
			var use_c01 := (row + column) % 2 == 0
			var tile_scene: PackedScene = FLOOR_TILE_C01_SCENE if use_c01 else FLOOR_TILE_C02_SCENE
			var tile := tile_scene.instantiate() as Node3D
			tile.name = "FloorTile_r%02d_c%02d" % [row, column]
			tile.position = Vector3(
				-HALF_EXTENT + GRID_UNIT_M * (float(column) + 0.5),
				TILE_SNAP_Y_C01 if use_c01 else TILE_SNAP_Y_C02,
				-HALF_EXTENT + GRID_UNIT_M * (float(row) + 0.5)
			)
			floor_root.add_child(tile)
			var key := "c01" if use_c01 else "c02"
			_tile_counts[key] = int(_tile_counts[key]) + 1


## 四条边各 10 段 5m 墙，正好 50m 闭合。墙 prefab 装饰面在局部 -Z，
## 逐边旋转使装饰面一律朝向场地内侧（玩家永远看不到结构背板）。
func _build_boundary_walls() -> void:
	var wall_root := Node3D.new()
	wall_root.name = "BoundaryWalls"
	add_child(wall_root)
	for index in range(GRID_TILES):
		var along := -HALF_EXTENT + GRID_UNIT_M * (float(index) + 0.5)
		# 北墙（-Z 侧）：内侧朝 +Z，需绕竖轴 180°。
		_place_wall_segment(wall_root, Vector3(along, 0.0, -HALF_EXTENT), PI)
		# 南墙（+Z 侧）：装饰面本就在局部 -Z，正对内侧，无需旋转。
		_place_wall_segment(wall_root, Vector3(along, 0.0, HALF_EXTENT), 0.0)
		# 西墙（-X 侧）：内侧朝 +X。
		_place_wall_segment(wall_root, Vector3(-HALF_EXTENT, 0.0, along), -PI * 0.5)
		# 东墙（+X 侧）：内侧朝 -X。
		_place_wall_segment(wall_root, Vector3(HALF_EXTENT, 0.0, along), PI * 0.5)


func _place_wall_segment(parent: Node3D, position: Vector3, yaw: float) -> void:
	var segment := WALL_SEGMENT_SCENE.instantiate() as Node3D
	segment.name = "WallSegment_%02d" % _wall_segment_count
	segment.position = position
	segment.rotation.y = yaw
	parent.add_child(segment)
	_wall_segment_count += 1


func _build_shooting_lanes() -> void:
	var lanes := Node3D.new()
	lanes.name = "ShootingLanes"
	add_child(lanes)
	for x in LANE_X:
		_add_box("LaneStripe", Vector3(x, 0.025, -15.0), Vector3(0.08, 0.025, 18.0), _accent, lanes)
		_add_box("FiringLine", Vector3(x, 0.035, -5.9), Vector3(5.7, 0.035, 0.16), _accent, lanes)


func _build_equipment_wall() -> void:
	var wall := Node3D.new()
	wall.name = "EquipmentWall"
	add_child(wall)
	_add_static_box("RackBacking", Vector3(-10.8, 1.65, 3.8), Vector3(10.8, 3.3, 0.42), _metal, wall)
	for x in range(-15, -5, 2):
		_add_box("RackRail", Vector3(float(x), 1.65, 3.55), Vector3(0.06, 2.7, 0.08), _accent, wall)


func _build_lighting() -> void:
	var index := 0
	for row in range(LIGHT_ROW_Z.size()):
		for column in range(LIGHT_COL_X.size()):
			var light := LIGHT_SCENE.instantiate() as WastelandLight3D
			light.position = Vector3(LIGHT_COL_X[column], 0.0, LIGHT_ROW_Z[row])
			light.rotation.y = PI * 0.5 if column < 2 else -PI * 0.5
			# 奇数行冷光、偶数行暖光；挑两盏开启闪烁与阴影，避免全场统一呆板。
			light.configure(
				Color(1.0, 0.58, 0.24) if row % 2 == 0 else Color(0.34, 0.72, 0.90),
				2.5, 8.5, 700 + index, index == 2, index % 5 == 1
			)
			add_child(light)
			light.add_to_group("training_light_3d")
			index += 1


func _build_furniture() -> void:
	var workbench := Node3D.new()
	workbench.name = "Workbench"
	add_child(workbench)
	_add_static_box("BenchTop", Vector3(10.5, 0.92, 2.8), Vector3(6.2, 0.22, 1.7), _metal, workbench)
	for x in [8.0, 13.0]:
		_add_static_box("BenchLeg", Vector3(x, 0.42, 2.8), Vector3(0.22, 0.84, 1.35), _metal, workbench)
	_add_box("BenchGlow", Vector3(10.5, 1.05, 2.2), Vector3(4.8, 0.06, 0.08), _accent, workbench)
	for x in [-12.0, 12.0]:
		_add_static_box("Cover", Vector3(x, 0.65, -10.5), Vector3(2.4, 1.3, 1.2), _metal)


func _add_static_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D = self) -> void:
	var body := StaticBody3D.new()
	body.name = "%sBody" % node_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D = self) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	parent.add_child(instance)


func _material(color: Color, metallic: float, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.55
	return material
