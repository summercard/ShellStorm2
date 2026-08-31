class_name TowerFloorStage3D
extends Node3D
## 常规层为250m塔楼物理层；100层主区16×16格，西侧为楼梯净空扩展2格。
## 重复地砖和外墙使用 Blender 导入 Mesh + MultiMesh；承重碰撞独立于渲染。

const GRID_UNIT := 5.0
const GRID_COUNT := 50
const MAP_SIZE := GRID_UNIT * GRID_COUNT
const MAP_HALF := MAP_SIZE * 0.5
# 原16×16主天台以99层基地中心(0, 5)居中；只向西追加2格（10m），
# 东/南/北边界保持不变，为100→99西侧楼梯外廓留下完整栏杆净空。
const ROOFTOP_GRID_DIMENSIONS := Vector2i(18, 16)
const ROOFTOP_MAP_DIMENSIONS := Vector2(90.0, 80.0)
const ROOFTOP_GRID_COUNT := ROOFTOP_GRID_DIMENSIONS.x
const ROOFTOP_MAP_SIZE := ROOFTOP_MAP_DIMENSIONS.x
const ROOFTOP_WORLD_RECT := Rect2(-50.0, -35.0, 90.0, 80.0)
const FACILITY_OUTER_GRID_COUNT := 32
const FACILITY_OUTER_MAP_SIZE := GRID_UNIT * FACILITY_OUTER_GRID_COUNT
const FACILITY_OUTER_WORLD_RECT := Rect2(
	-FACILITY_OUTER_MAP_SIZE * 0.5,
	-FACILITY_OUTER_MAP_SIZE * 0.5,
	FACILITY_OUTER_MAP_SIZE,
	FACILITY_OUTER_MAP_SIZE
)
const ROOFTOP_PARAPET_HEIGHT := 0.75
const PROTECTED_FLOOR_PATCH_SIDE_M := 50.0
const PROTECTED_FLOOR_PATCH_TILES_PER_SIDE := int(PROTECTED_FLOOR_PATCH_SIDE_M / GRID_UNIT)
const FLOOR_THICKNESS := 0.30
const WALL_THICKNESS := 0.30
const FLOOR_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m_v001.tscn"
)
const WALL_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m_v001.tscn"
)
const PARAPET_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m_v001.tscn"
)
const PARAPET_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_door_5m_v001.tscn"
)
const ROOFTOP_ART_SCENE: PackedScene = preload(
	"res://assets/art/environments/rooftop_shelter_3d/runtime/env_rooftop_shelter_90x80m_facilities_root_top3d_v021.tscn"
)
const FLOOR_TILE_MATERIAL_LIGHT: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_override_top3d_v001.tres"
)
const FLOOR_TILE_MATERIAL_DARK: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_dark_top3d_v001.tres"
)
# v0.1 v2 拼接交替材质（A/B 微差异版）
const FLOOR_TILE_MATERIAL_A: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_a_v001.tres"
)
const FLOOR_TILE_MATERIAL_B: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_b_v001.tres"
)
const WALL_DOOR_GAP_HALF_WIDTH := 5.0
const BASE_99_100_ATRIUM_WORLD_RECT := Rect2(-15.0, -10.0, 30.0, 30.0)
const BASE_99_100_ATRIUM_TILE_COUNT := 36

var floor_index := 0
var floor_kind := "combat"
var stair_hole_sides: Array[String] = []
var _floor_visual_light: MultiMeshInstance3D
var _floor_visual_dark: MultiMeshInstance3D
var _protected_floor_visual_light: MultiMeshInstance3D
var _protected_floor_visual_dark: MultiMeshInstance3D
var _outer_visual: MultiMeshInstance3D
var _support_root: StaticBody3D
var _rooftop_art_instance: Node3D
var _shell_visible := true
var _floor_visible := true
var _outer_visible := true
var _tile_count := 0
var _support_rect_count := 0
var _protected_floor_patch_enabled := false
var _protected_floor_patch_grid_center := Vector2i(-1, -1)
var _protected_floor_patch_tile_count := 0


func configure(index: int, kind: String, holes: Array[String]) -> void:
	floor_index = index
	floor_kind = kind
	stair_hole_sides.assign(holes)


func _ready() -> void:
	name = "TowerFloorStage_%02d_%s" % [floor_index, floor_kind.capitalize()]
	add_to_group("tower_floor_stage_3d")
	_build_floor()
	_build_outer_shell()
	_build_support()
	_install_rooftop_art()


func set_shell_visible(show_shell: bool) -> void:
	set_render_state(show_shell, show_shell)


func set_render_state(_show_floor: bool, _show_outer: bool) -> void:
	# 结构壳体永久驻留：任何流送调用都不得隐藏楼板或塔楼外圈墙。
	var show_floor := true
	var show_outer := true
	_floor_visible = true
	_outer_visible = true
	_shell_visible = true
	if _floor_visual_light != null:
		_floor_visual_light.visible = show_floor
	if _floor_visual_dark != null:
		_floor_visual_dark.visible = show_floor
	if _outer_visual != null:
		_outer_visual.visible = show_outer
	if _rooftop_art_instance != null:
		_rooftop_art_instance.visible = true
	_apply_protected_floor_patch_visibility()


## 兼容旧存档/测试入口。完整楼板已永久显示，局部补丁必须保持关闭，
## 避免同位置重复渲染引发闪烁、阴影偏差或额外 draw call。
func set_protected_floor_patch(_center_world_position: Vector3, _enabled: bool) -> void:
	_protected_floor_patch_enabled = false
	_apply_protected_floor_patch_visibility()


func is_shell_visible() -> bool:
	return _shell_visible


func get_snapshot() -> Dictionary:
	return {
		"floor_index": floor_index,
		"floor_kind": floor_kind,
		"map_size": _floor_map_size(),
		"grid_count": _floor_grid_count(),
		"map_dimensions": _floor_map_dimensions(),
		"grid_dimensions": _floor_grid_dimensions(),
		"floor_world_rect": _floor_world_rect(),
		"grid_unit": GRID_UNIT,
		"tile_count": _tile_count,
		"tile_count_light": _floor_visual_light.multimesh.instance_count if _floor_visual_light != null and _floor_visual_light.multimesh != null else 0,
		"tile_count_dark": _floor_visual_dark.multimesh.instance_count if _floor_visual_dark != null and _floor_visual_dark.multimesh != null else 0,
		"outer_map_size": _outer_map_size(),
		"outer_grid_count": _outer_grid_count(),
		"outer_map_dimensions": _outer_map_dimensions(),
		"outer_grid_dimensions": _outer_grid_dimensions(),
		"outer_world_rect": _outer_world_rect(),
		"outer_module_count": 2 * (_outer_grid_dimensions().x + _outer_grid_dimensions().y),
		"outer_wall_height": _outer_wall_height(),
		"support_rect_count": _support_rect_count,
		"stair_hole_sides": stair_hole_sides.duplicate(),
		"shell_visible": _shell_visible,
		"floor_visible": _floor_visible,
		"outer_visible": _outer_visible,
		"protected_floor_patch_enabled": _protected_floor_patch_enabled,
		"protected_floor_patch_visible": (
			_protected_floor_patch_enabled and not _floor_visible
		),
		"protected_floor_patch_grid_center": _protected_floor_patch_grid_center,
		"protected_floor_patch_tile_count": _protected_floor_patch_tile_count,
		"protected_floor_patch_side_m": PROTECTED_FLOOR_PATCH_SIDE_M,
		"protected_floor_patch_tiles_per_side": PROTECTED_FLOOR_PATCH_TILES_PER_SIDE,
		"protected_floor_patch_casts_shadow": (
			_protected_floor_visual_light != null
			and _protected_floor_visual_dark != null
			and _protected_floor_visual_light.cast_shadow
				== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			and _protected_floor_visual_dark.cast_shadow
				== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		),
		"support_collision_persistent": (
			_support_root != null
			and _support_root.process_mode == Node.PROCESS_MODE_ALWAYS
			and _enabled_collision_shape_count(_support_root) > 0
		),
		"support_process_mode_always": (
			_support_root != null
			and _support_root.process_mode == Node.PROCESS_MODE_ALWAYS
		),
		"uses_imported_floor_mesh": _floor_visual_light != null and _floor_visual_light.multimesh != null,
		"uses_imported_outer_mesh": _outer_visual != null and _outer_visual.multimesh != null,
		"uses_formal_rooftop_art": _rooftop_art_instance != null,
		"formal_rooftop_art_version": (
			str(_rooftop_art_instance.get_meta("version", ""))
			if _rooftop_art_instance != null else ""
		),
		"formal_rooftop_art_blocker_count": (
			int(_rooftop_art_instance.get_meta("independent_blocker_count", 0))
			if _rooftop_art_instance != null else 0
		),
		"checkerboard_pattern": true,
		"base_99_100_atrium_enabled": floor_index == 0,
		"base_99_100_atrium_tile_count": BASE_99_100_ATRIUM_TILE_COUNT if floor_index == 0 else 0,
		"base_99_100_atrium_world_rect": BASE_99_100_ATRIUM_WORLD_RECT if floor_index == 0 else Rect2(),
	}


func _install_rooftop_art() -> void:
	if floor_index != 0 or floor_kind != "rooftop":
		return
	var instance := ROOFTOP_ART_SCENE.instantiate() as Node3D
	if instance == null:
		push_error("ENV-ROOFTOP-SHELTER-90X80 v021 设施场景无法实例化")
		return
	instance.name = "FormalRooftopFacilitiesV019"
	add_child(instance)
	_rooftop_art_instance = instance
	# v017只提供设施、家具及其组合碰撞。100层原生地板、围栏、门洞视觉
	# 与FloorSupport承重碰撞继续由TowerFloorStage3D完整持有。


func _floor_grid_count() -> int:
	return _floor_grid_dimensions().x


func _floor_grid_dimensions() -> Vector2i:
	return ROOFTOP_GRID_DIMENSIONS if floor_index == 0 else Vector2i(GRID_COUNT, GRID_COUNT)


func _floor_map_size() -> float:
	return _floor_map_dimensions().x


func _floor_map_dimensions() -> Vector2:
	return ROOFTOP_MAP_DIMENSIONS if floor_index == 0 else Vector2(MAP_SIZE, MAP_SIZE)


func _floor_world_rect() -> Rect2:
	return ROOFTOP_WORLD_RECT if floor_index == 0 else Rect2(-MAP_HALF, -MAP_HALF, MAP_SIZE, MAP_SIZE)


func _outer_grid_count() -> int:
	# 此次只收缩100层。99层外墙保持此前的160m轮廓，基地和设施不移动。
	return _outer_grid_dimensions().x


func _outer_grid_dimensions() -> Vector2i:
	return (
		ROOFTOP_GRID_DIMENSIONS
		if floor_index == 0
		else Vector2i(FACILITY_OUTER_GRID_COUNT, FACILITY_OUTER_GRID_COUNT)
		if floor_index == 1
		else Vector2i(GRID_COUNT, GRID_COUNT)
	)


func _outer_map_size() -> float:
	return _outer_map_dimensions().x


func _outer_map_dimensions() -> Vector2:
	return (
		ROOFTOP_MAP_DIMENSIONS
		if floor_index == 0
		else Vector2(FACILITY_OUTER_MAP_SIZE, FACILITY_OUTER_MAP_SIZE)
		if floor_index == 1
		else Vector2(MAP_SIZE, MAP_SIZE)
	)


func _outer_world_rect() -> Rect2:
	return ROOFTOP_WORLD_RECT if floor_index == 0 else FACILITY_OUTER_WORLD_RECT if floor_index == 1 else Rect2(-MAP_HALF, -MAP_HALF, MAP_SIZE, MAP_SIZE)


func _outer_wall_height() -> float:
	return ROOFTOP_PARAPET_HEIGHT if floor_index == 0 else 9.0


func _enabled_collision_shape_count(root: Node) -> int:
	var count := 0
	if root is CollisionShape3D and not (root as CollisionShape3D).disabled:
		count += 1
	for child in root.get_children():
		count += _enabled_collision_shape_count(child)
	return count


func _build_floor() -> void:
	var mesh := _mesh_from_scene(FLOOR_SCENE)
	if mesh == null:
		push_error("Tower floor module GLB has no MeshInstance3D")
		return
	# 国际象棋棋盘式地砖：按 (x_index + z_index) % 2 分流到浅/深两套 MultiMesh。
	var light_transforms: Array[Transform3D] = []
	var dark_transforms: Array[Transform3D] = []
	var holes := _floor_visual_hole_rects()
	var grid_dimensions := _floor_grid_dimensions()
	var floor_rect := _floor_world_rect()
	for z_index in range(grid_dimensions.y):
		for x_index in range(grid_dimensions.x):
			var point := Vector2i(x_index, z_index)
			var skipped := false
			for hole in holes:
				if (hole as Rect2i).has_point(point):
					skipped = true
					break
			if skipped:
				continue
			var x := floor_rect.position.x + GRID_UNIT * (float(x_index) + 0.5)
			var z := floor_rect.position.y + GRID_UNIT * (float(z_index) + 0.5)
			# BoxMesh地砖以中心为原点；下移半个厚度，使可视顶面与承重面Y=0重合。
			var transform := Transform3D(
				Basis.IDENTITY,
				Vector3(x, -FLOOR_THICKNESS * 0.5, z)
			)
			if (x_index + z_index) % 2 == 0:
				light_transforms.append(transform)
			else:
				dark_transforms.append(transform)
	_floor_visual_light = _create_floor_multimesh(
		"ImportedFloorTileGrid5M_A", mesh, light_transforms, FLOOR_TILE_MATERIAL_A
	)
	add_child(_floor_visual_light)
	_floor_visual_dark = _create_floor_multimesh(
		"ImportedFloorTileGrid5M_B", mesh, dark_transforms, FLOOR_TILE_MATERIAL_B
	)
	add_child(_floor_visual_dark)
	var empty_transforms: Array[Transform3D] = []
	_protected_floor_visual_light = _create_floor_multimesh(
		"ProtectedFloorPatch5M_A", mesh, empty_transforms, FLOOR_TILE_MATERIAL_A
	)
	_protected_floor_visual_light.visible = false
	add_child(_protected_floor_visual_light)
	_protected_floor_visual_dark = _create_floor_multimesh(
		"ProtectedFloorPatch5M_B", mesh, empty_transforms, FLOOR_TILE_MATERIAL_B
	)
	_protected_floor_visual_dark.visible = false
	add_child(_protected_floor_visual_dark)
	_tile_count = light_transforms.size() + dark_transforms.size()


func _rebuild_protected_floor_patch(grid_center: Vector2i) -> void:
	_protected_floor_patch_grid_center = grid_center
	var light_transforms: Array[Transform3D] = []
	var dark_transforms: Array[Transform3D] = []
	var holes := _floor_visual_hole_rects()
	var patch_start_offset := -int(PROTECTED_FLOOR_PATCH_TILES_PER_SIDE / 2)
	var patch_end_offset := patch_start_offset + PROTECTED_FLOOR_PATCH_TILES_PER_SIDE
	var grid_dimensions := _floor_grid_dimensions()
	var floor_rect := _floor_world_rect()
	for z_index in range(grid_center.y + patch_start_offset, grid_center.y + patch_end_offset):
		if z_index < 0 or z_index >= grid_dimensions.y:
			continue
		for x_index in range(grid_center.x + patch_start_offset, grid_center.x + patch_end_offset):
			if x_index < 0 or x_index >= grid_dimensions.x:
				continue
			var point := Vector2i(x_index, z_index)
			var skipped := false
			for hole in holes:
				if (hole as Rect2i).has_point(point):
					skipped = true
					break
			if skipped:
				continue
			var transform := Transform3D(
				Basis.IDENTITY,
				Vector3(
					floor_rect.position.x + GRID_UNIT * (float(x_index) + 0.5),
					-FLOOR_THICKNESS * 0.5,
					floor_rect.position.y + GRID_UNIT * (float(z_index) + 0.5)
				)
			)
			if (x_index + z_index) % 2 == 0:
				light_transforms.append(transform)
			else:
				dark_transforms.append(transform)
	_update_floor_multimesh_transforms(_protected_floor_visual_light, light_transforms)
	_update_floor_multimesh_transforms(_protected_floor_visual_dark, dark_transforms)
	_protected_floor_patch_tile_count = light_transforms.size() + dark_transforms.size()


func _update_floor_multimesh_transforms(
	visual: MultiMeshInstance3D, transforms: Array[Transform3D]
) -> void:
	if visual == null or visual.multimesh == null:
		return
	visual.multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		visual.multimesh.set_instance_transform(index, transforms[index])


func _apply_protected_floor_patch_visibility() -> void:
	var patch_visible := _protected_floor_patch_enabled and not _floor_visible
	if _protected_floor_visual_light != null:
		_protected_floor_visual_light.visible = patch_visible
	if _protected_floor_visual_dark != null:
		_protected_floor_visual_dark.visible = patch_visible


func _create_floor_multimesh(
	node_name: String, mesh: Mesh, transforms: Array[Transform3D], material: StandardMaterial3D
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = node_name
	visual.multimesh = multimesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.material_override = material
	return visual


func _build_outer_shell() -> void:
	var module_scene := PARAPET_SCENE if floor_kind == "rooftop" else WALL_SCENE
	var mesh := _mesh_from_scene(module_scene)
	if mesh == null:
		push_error("Tower outer-wall module GLB has no MeshInstance3D")
		return
	# 楼梯口门洞：跳过门洞位置的实墙模块，碰撞盒也留缺口。
	# 楼顶额外在缺口处摆放带门墙预制体（5m 宽组件含 2m 宽门洞），可通行。
	var transforms: Array[Transform3D] = []
	var outer_grid_dimensions := _outer_grid_dimensions()
	var outer_rect := _outer_world_rect()
	var outer_max := outer_rect.end
	var wall_height := _outer_wall_height()
	# 普通墙视觉网格高8.9m且以中心为原点；按底面反算其中心高度。
	# 屋顶矮墙继续使用0.75m运行时缩放后的中心高度。
	var visual_wall_center_y := (
		wall_height * 0.5
		if floor_index == 0
		else -mesh.get_aabb().position.y
	)
	var north_boundary := outer_rect.position.y + WALL_THICKNESS * 0.5
	var south_boundary := outer_max.y - WALL_THICKNESS * 0.5
	var west_boundary := outer_rect.position.x + WALL_THICKNESS * 0.5
	var east_boundary := outer_max.x - WALL_THICKNESS * 0.5
	var door_transforms: Dictionary = {"north": [], "south": [], "west": [], "east": []}
	for index in range(outer_grid_dimensions.x):
		var offset_x := outer_rect.position.x + GRID_UNIT * (float(index) + 0.5)
		if not _is_in_wall_door_gap("north", index):
			transforms.append(_outer_visual_transform(Basis.IDENTITY, Vector3(offset_x, visual_wall_center_y, north_boundary)))
		else:
			door_transforms["north"].append(Transform3D(Basis.IDENTITY, Vector3(offset_x, 0.0, north_boundary)))
		if not _is_in_wall_door_gap("south", index):
			transforms.append(_outer_visual_transform(Basis(Vector3.UP, PI), Vector3(offset_x, visual_wall_center_y, south_boundary)))
		else:
			door_transforms["south"].append(Transform3D(Basis(Vector3.UP, PI), Vector3(offset_x, 0.0, south_boundary)))
	for index in range(outer_grid_dimensions.y):
		var offset_z := outer_rect.position.y + GRID_UNIT * (float(index) + 0.5)
		if not _is_in_wall_door_gap("west", index):
			transforms.append(_outer_visual_transform(Basis(Vector3.UP, PI * 0.5), Vector3(west_boundary, visual_wall_center_y, offset_z)))
		else:
			door_transforms["west"].append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(west_boundary, 0.0, offset_z)))
		if not _is_in_wall_door_gap("east", index):
			transforms.append(_outer_visual_transform(Basis(Vector3.UP, -PI * 0.5), Vector3(east_boundary, visual_wall_center_y, offset_z)))
		else:
			door_transforms["east"].append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(east_boundary, 0.0, offset_z)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	_outer_visual = MultiMeshInstance3D.new()
	_outer_visual.name = "ImportedOuter%sGrid5M" % (
		"Parapet" if floor_kind == "rooftop" else "Wall"
	)
	_outer_visual.multimesh = multimesh
	_outer_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_outer_visual)

	# 楼顶：在每个缺口位置摆带门墙预制体（替代被跳过的实墙模块）。
	if floor_kind == "rooftop":
		for side in door_transforms.keys():
			for door_transform in (door_transforms[side] as Array):
				var door_instance := PARAPET_DOOR_PREFAB.instantiate() as Node3D
				if door_instance == null:
					continue
				door_instance.name = "ParapetDoorWall_%s" % side.capitalize()
				door_instance.transform = door_transform
				door_instance.scale = Vector3(1.0, 0.5, 1.0)
				add_child(door_instance)

	# 每一边使用独立碰撞体，避免一个共享 body 让摄像机无法判断命中方向。
	for side in ["north", "south", "west", "east"]:
		var body := StaticBody3D.new()
		body.name = "OuterBoundaryCollision_%s" % side.capitalize()
		# 远层 stage 会停用脚本处理，但永久结构碰撞必须继续服务移动、子弹和
		# 受光射线。显式 ALWAYS 可避免从禁用父节点继承物理停用状态。
		body.process_mode = Node.PROCESS_MODE_ALWAYS
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("camera_lower_wall", side == "south")
		add_child(body)
		_add_wall_collision(body, side, wall_height)


func _outer_visual_transform(basis: Basis, position: Vector3) -> Transform3D:
	var visual_basis := basis
	if floor_index == 0:
		visual_basis = visual_basis.scaled(Vector3(1.0, 0.5, 1.0))
	return Transform3D(visual_basis, position)


func _is_in_wall_door_gap(side: String, index: int) -> bool:
	for hole_side in stair_hole_sides:
		if hole_side != side:
			continue
		var module_pos := _wall_module_position(side, index)
		var hole_center := _stair_hole_center(hole_side)
		var along_axis := module_pos.x if side in ["north", "south"] else module_pos.z
		var hole_along := hole_center.x if side in ["north", "south"] else hole_center.z
		return absf(along_axis - hole_along) <= WALL_DOOR_GAP_HALF_WIDTH
	return false


func _wall_module_position(side: String, index: int) -> Vector3:
	var outer_rect := _outer_world_rect()
	var outer_max := outer_rect.end
	var offset_x := outer_rect.position.x + GRID_UNIT * (float(index) + 0.5)
	var offset_z := outer_rect.position.y + GRID_UNIT * (float(index) + 0.5)
	var north_boundary := outer_rect.position.y + WALL_THICKNESS * 0.5
	var south_boundary := outer_max.y - WALL_THICKNESS * 0.5
	var west_boundary := outer_rect.position.x + WALL_THICKNESS * 0.5
	var east_boundary := outer_max.x - WALL_THICKNESS * 0.5
	match side:
		"north":
			return Vector3(offset_x, 0.0, north_boundary)
		"south":
			return Vector3(offset_x, 0.0, south_boundary)
		"west":
			return Vector3(west_boundary, 0.0, offset_z)
		"east":
			return Vector3(east_boundary, 0.0, offset_z)
	return Vector3.ZERO


func _stair_hole_center(side: String) -> Vector3:
	# 外墙缺口、楼板视觉和承重碰撞必须引用同一个洞口矩形。
	var hole_rect := _stair_hole_world_rect(side)
	return Vector3(
		hole_rect.position.x + hole_rect.size.x * 0.5,
		0.0,
		hole_rect.position.y + hole_rect.size.y * 0.5
	)


func _add_wall_collision(body: StaticBody3D, side: String, height: float) -> void:
	var outer_rect := _outer_world_rect()
	var outer_max := outer_rect.end
	var north_boundary := outer_rect.position.y + WALL_THICKNESS * 0.5
	var south_boundary := outer_max.y - WALL_THICKNESS * 0.5
	var west_boundary := outer_rect.position.x + WALL_THICKNESS * 0.5
	var east_boundary := outer_max.x - WALL_THICKNESS * 0.5
	if not (side in stair_hole_sides):
		match side:
			"north":
				_add_box_collision(body, Vector3(outer_rect.get_center().x, height * 0.5, north_boundary), Vector3(outer_rect.size.x, height, WALL_THICKNESS))
			"south":
				_add_box_collision(body, Vector3(outer_rect.get_center().x, height * 0.5, south_boundary), Vector3(outer_rect.size.x, height, WALL_THICKNESS))
			"west":
				_add_box_collision(body, Vector3(west_boundary, height * 0.5, outer_rect.get_center().y), Vector3(WALL_THICKNESS, height, outer_rect.size.y))
			"east":
				_add_box_collision(body, Vector3(east_boundary, height * 0.5, outer_rect.get_center().y), Vector3(WALL_THICKNESS, height, outer_rect.size.y))
		return
	var center := _stair_hole_center(side)
	var gap_start := 0.0
	var gap_end := 0.0
	var axis_pos := 0.0
	match side:
		"north":
			gap_start = clampf(center.x - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			gap_end = clampf(center.x + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			axis_pos = north_boundary
		"south":
			gap_start = clampf(center.x - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			gap_end = clampf(center.x + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			axis_pos = south_boundary
		"west":
			gap_start = clampf(center.z - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			gap_end = clampf(center.z + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			axis_pos = west_boundary
		"east":
			gap_start = clampf(center.z - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			gap_end = clampf(center.z + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			axis_pos = east_boundary
	match side:
		"north", "south":
			var left_size := gap_start - outer_rect.position.x
			var right_size := outer_max.x - gap_end
			if left_size > 0.01:
				_add_box_collision(
					body,
					Vector3(outer_rect.position.x + left_size * 0.5, height * 0.5, axis_pos),
					Vector3(left_size, height, WALL_THICKNESS)
				)
			if right_size > 0.01:
				_add_box_collision(
					body,
					Vector3(gap_end + right_size * 0.5, height * 0.5, axis_pos),
					Vector3(right_size, height, WALL_THICKNESS)
				)
		"west", "east":
			var left_size := gap_start - outer_rect.position.y
			var right_size := outer_max.y - gap_end
			if left_size > 0.01:
				_add_box_collision(
					body,
					Vector3(axis_pos, height * 0.5, outer_rect.position.y + left_size * 0.5),
					Vector3(WALL_THICKNESS, height, left_size)
				)
			if right_size > 0.01:
				_add_box_collision(
					body,
					Vector3(axis_pos, height * 0.5, gap_end + right_size * 0.5),
					Vector3(WALL_THICKNESS, height, right_size)
				)


func _add_box_collision(body: StaticBody3D, position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.position = position
	collision.shape = shape
	body.add_child(collision)


func _build_support() -> void:
	_support_root = StaticBody3D.new()
	_support_root.name = "FloorSupport"
	# 楼板是跨层太阳遮挡体，不能随当前楼层的处理窗口退出物理空间。
	_support_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_support_root.collision_layer = 1
	_support_root.collision_mask = 0
	add_child(_support_root)
	var grid_dimensions := _floor_grid_dimensions()
	var floor_rect := _floor_world_rect()
	var rectangles: Array[Rect2i] = [Rect2i(Vector2i.ZERO, grid_dimensions)]
	for hole in _hole_rects():
		rectangles = _subtract_hole(rectangles, hole)
	for rect in rectangles:
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var shape := BoxShape3D.new()
		shape.size = Vector3(
			float(rect.size.x) * GRID_UNIT,
			FLOOR_THICKNESS,
			float(rect.size.y) * GRID_UNIT
		)
		var collision := CollisionShape3D.new()
		collision.name = "SupportRect_%02d" % _support_rect_count
		collision.position = Vector3(
			floor_rect.position.x + (float(rect.position.x) + float(rect.size.x) * 0.5) * GRID_UNIT,
			-FLOOR_THICKNESS * 0.5,
			floor_rect.position.y + (float(rect.position.y) + float(rect.size.y) * 0.5) * GRID_UNIT
		)
		collision.shape = shape
		_support_root.add_child(collision)
		_support_rect_count += 1


func _hole_rects() -> Array[Rect2i]:
	var holes: Array[Rect2i] = []
	# 100层与99层基地打通：只从100层(stage 0)移除基地上方6×6地砖，
	# 99层自身的36块地面仍由基地房间保留。
	if floor_index == 0:
		holes.append(_world_rect_to_grid(BASE_99_100_ATRIUM_WORLD_RECT))
	for side in stair_hole_sides:
		holes.append(_world_rect_to_grid(_stair_hole_world_rect(side)))
	return holes


func _floor_visual_hole_rects() -> Array[Rect2i]:
	var holes := _hole_rects()
	# 99F的承重面仍由完整FloorSupport负责；这里只从通用可视地砖中挖出
	# 基地地板区域，避免与两套正式基地地砖在Y=0处重叠闪烁。
	if floor_index == 1:
		holes.append(_world_rect_to_grid(BASE_99_100_ATRIUM_WORLD_RECT))
	return holes


func _stair_hole_world_rect(side: String) -> Rect2:
	# 两条楼梯跑道的外廓按 5m 单元取整，边界全部落在整格线上。
	match side:
		"west":
			return Rect2(-45.0, 0.0, 15.0, 30.0)
		"east":
			return Rect2(35.0, -25.0, 15.0, 30.0)
		"north":
			return Rect2(-25.0, -45.0, 30.0, 15.0)
		"south":
			return Rect2(0.0, 35.0, 30.0, 15.0)
	return Rect2()


func _world_rect_to_grid(world_rect: Rect2) -> Rect2i:
	var floor_rect := _floor_world_rect()
	return Rect2i(
		int(round((world_rect.position.x - floor_rect.position.x) / GRID_UNIT)),
		int(round((world_rect.position.y - floor_rect.position.y) / GRID_UNIT)),
		int(round(world_rect.size.x / GRID_UNIT)),
		int(round(world_rect.size.y / GRID_UNIT))
	)


func _subtract_hole(rectangles: Array[Rect2i], hole: Rect2i) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for rect in rectangles:
		var overlap := rect.intersection(hole)
		if overlap.size.x <= 0 or overlap.size.y <= 0:
			result.append(rect)
			continue
		var rect_end := rect.end
		var overlap_end := overlap.end
		if overlap.position.x > rect.position.x:
			result.append(Rect2i(
				rect.position.x,
				rect.position.y,
				overlap.position.x - rect.position.x,
				rect.size.y
			))
		if overlap_end.x < rect_end.x:
			result.append(Rect2i(
				overlap_end.x,
				rect.position.y,
				rect_end.x - overlap_end.x,
				rect.size.y
			))
		if overlap.position.y > rect.position.y:
			result.append(Rect2i(
				overlap.position.x,
				rect.position.y,
				overlap.size.x,
				overlap.position.y - rect.position.y
			))
		if overlap_end.y < rect_end.y:
			result.append(Rect2i(
				overlap.position.x,
				overlap_end.y,
				overlap.size.x,
				rect_end.y - overlap_end.y
			))
	return result


func _mesh_from_scene(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var instance := scene.instantiate()
	var mesh := _find_first_mesh(instance)
	instance.free()
	return mesh


func _find_first_mesh(root: Node) -> Mesh:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return (root as MeshInstance3D).mesh
	for child in root.get_children():
		var mesh := _find_first_mesh(child)
		if mesh != null:
			return mesh
	return null
