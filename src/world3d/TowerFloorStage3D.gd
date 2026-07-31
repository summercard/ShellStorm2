class_name TowerFloorStage3D
extends Node3D
## 250m 塔楼物理层。重复地砖和外墙使用 Blender 导入 Mesh + MultiMesh；
## 承重碰撞独立于渲染，楼梯开口按 5m 网格从楼板中剔除。

const GRID_UNIT := 5.0
const GRID_COUNT := 50
const MAP_SIZE := GRID_UNIT * GRID_COUNT
const MAP_HALF := MAP_SIZE * 0.5
const FLOOR_THICKNESS := 0.30
const WALL_THICKNESS := 0.30
const FLOOR_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m.tscn"
)
const WALL_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"
)
const PARAPET_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m.tscn"
)
const PARAPET_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_door_5m.tscn"
)
const FLOOR_TILE_MATERIAL_LIGHT: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_override_top3d_v001.tres"
)
const FLOOR_TILE_MATERIAL_DARK: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_dark_top3d_v001.tres"
)
const WALL_DOOR_GAP_HALF_WIDTH := 5.0

var floor_index := 0
var floor_kind := "combat"
var stair_hole_sides: Array[String] = []
var _floor_visual_light: MultiMeshInstance3D
var _floor_visual_dark: MultiMeshInstance3D
var _outer_visual: MultiMeshInstance3D
var _support_root: StaticBody3D
var _shell_visible := true
var _floor_visible := true
var _outer_visible := true
var _tile_count := 0
var _support_rect_count := 0


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


func set_shell_visible(show_shell: bool) -> void:
	set_render_state(show_shell, show_shell)


func set_render_state(show_floor: bool, show_outer: bool) -> void:
	_floor_visible = show_floor
	_outer_visible = show_outer
	_shell_visible = show_floor or show_outer
	if _floor_visual_light != null:
		_floor_visual_light.visible = show_floor
	if _floor_visual_dark != null:
		_floor_visual_dark.visible = show_floor
	if _outer_visual != null:
		_outer_visual.visible = show_outer


func is_shell_visible() -> bool:
	return _shell_visible


func get_snapshot() -> Dictionary:
	return {
		"floor_index": floor_index,
		"floor_kind": floor_kind,
		"map_size": MAP_SIZE,
		"grid_unit": GRID_UNIT,
		"tile_count": _tile_count,
		"tile_count_light": _floor_visual_light.multimesh.instance_count if _floor_visual_light != null and _floor_visual_light.multimesh != null else 0,
		"tile_count_dark": _floor_visual_dark.multimesh.instance_count if _floor_visual_dark != null and _floor_visual_dark.multimesh != null else 0,
		"outer_module_count": GRID_COUNT * 4,
		"support_rect_count": _support_rect_count,
		"stair_hole_sides": stair_hole_sides.duplicate(),
		"shell_visible": _shell_visible,
		"floor_visible": _floor_visible,
		"outer_visible": _outer_visible,
		"support_collision_persistent": _support_root != null,
		"uses_imported_floor_mesh": _floor_visual_light != null and _floor_visual_light.multimesh != null,
		"uses_imported_outer_mesh": _outer_visual != null and _outer_visual.multimesh != null,
		"checkerboard_pattern": true,
	}


func _build_floor() -> void:
	var mesh := _mesh_from_scene(FLOOR_SCENE)
	if mesh == null:
		push_error("Tower floor module GLB has no MeshInstance3D")
		return
	# 国际象棋棋盘式地砖：按 (x_index + z_index) % 2 分流到浅/深两套 MultiMesh。
	var light_transforms: Array[Transform3D] = []
	var dark_transforms: Array[Transform3D] = []
	var holes := _hole_rects()
	for z_index in range(GRID_COUNT):
		for x_index in range(GRID_COUNT):
			var point := Vector2i(x_index, z_index)
			var skipped := false
			for hole in holes:
				if (hole as Rect2i).has_point(point):
					skipped = true
					break
			if skipped:
				continue
			var x := -MAP_HALF + GRID_UNIT * (float(x_index) + 0.5)
			var z := -MAP_HALF + GRID_UNIT * (float(z_index) + 0.5)
			var transform := Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z))
			if (x_index + z_index) % 2 == 0:
				light_transforms.append(transform)
			else:
				dark_transforms.append(transform)
	_floor_visual_light = _create_floor_multimesh(
		"ImportedFloorTileGrid5M_Light", mesh, light_transforms, FLOOR_TILE_MATERIAL_LIGHT
	)
	add_child(_floor_visual_light)
	_floor_visual_dark = _create_floor_multimesh(
		"ImportedFloorTileGrid5M_Dark", mesh, dark_transforms, FLOOR_TILE_MATERIAL_DARK
	)
	add_child(_floor_visual_dark)
	_tile_count = light_transforms.size() + dark_transforms.size()


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
	var boundary := MAP_HALF - WALL_THICKNESS * 0.5
	var door_transforms: Dictionary = {"north": [], "south": [], "west": [], "east": []}
	for index in range(GRID_COUNT):
		var offset := -MAP_HALF + GRID_UNIT * (float(index) + 0.5)
		if not _is_in_wall_door_gap("north", index):
			transforms.append(Transform3D(Basis.IDENTITY, Vector3(offset, 0.0, -boundary)))
		else:
			door_transforms["north"].append(Transform3D(Basis.IDENTITY, Vector3(offset, 0.0, -boundary)))
		if not _is_in_wall_door_gap("south", index):
			transforms.append(Transform3D(Basis(Vector3.UP, PI), Vector3(-offset, 0.0, boundary)))
		else:
			door_transforms["south"].append(Transform3D(Basis(Vector3.UP, PI), Vector3(-offset, 0.0, boundary)))
		if not _is_in_wall_door_gap("west", index):
			transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-boundary, 0.0, -offset)))
		else:
			door_transforms["west"].append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-boundary, 0.0, -offset)))
		if not _is_in_wall_door_gap("east", index):
			transforms.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(boundary, 0.0, offset)))
		else:
			door_transforms["east"].append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(boundary, 0.0, offset)))
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
				add_child(door_instance)

	var body := StaticBody3D.new()
	body.name = "OuterBoundaryCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var height := 1.5 if floor_kind == "rooftop" else 9.0
	_add_wall_collision(body, "north", height, boundary)
	_add_wall_collision(body, "south", height, boundary)
	_add_wall_collision(body, "west", height, boundary)
	_add_wall_collision(body, "east", height, boundary)


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
	var offset := -MAP_HALF + GRID_UNIT * (float(index) + 0.5)
	var boundary := MAP_HALF - WALL_THICKNESS * 0.5
	match side:
		"north":
			return Vector3(offset, 0.0, -boundary)
		"south":
			return Vector3(-offset, 0.0, boundary)
		"west":
			return Vector3(-boundary, 0.0, -offset)
		"east":
			return Vector3(boundary, 0.0, offset)
	return Vector3.ZERO


func _stair_hole_center(side: String) -> Vector3:
	var hole_rect := Rect2()
	match side:
		"west":
			hole_rect = Rect2(-45.0, 0.0, 15.0, 30.0)
		"east":
			hole_rect = Rect2(35.0, -25.0, 15.0, 30.0)
		"north":
			hole_rect = Rect2(-25.0, -45.0, 30.0, 15.0)
		"south":
			hole_rect = Rect2(0.0, 35.0, 30.0, 15.0)
	return Vector3(
		hole_rect.position.x + hole_rect.size.x * 0.5,
		0.0,
		hole_rect.position.y + hole_rect.size.y * 0.5
	)


func _add_wall_collision(body: StaticBody3D, side: String, height: float, boundary: float) -> void:
	if not (side in stair_hole_sides):
		match side:
			"north":
				_add_box_collision(body, Vector3(0.0, height * 0.5, -boundary), Vector3(MAP_SIZE, height, WALL_THICKNESS))
			"south":
				_add_box_collision(body, Vector3(0.0, height * 0.5, boundary), Vector3(MAP_SIZE, height, WALL_THICKNESS))
			"west":
				_add_box_collision(body, Vector3(-boundary, height * 0.5, 0.0), Vector3(WALL_THICKNESS, height, MAP_SIZE))
			"east":
				_add_box_collision(body, Vector3(boundary, height * 0.5, 0.0), Vector3(WALL_THICKNESS, height, MAP_SIZE))
		return
	var center := _stair_hole_center(side)
	var gap_start := 0.0
	var gap_end := 0.0
	var axis_pos := 0.0
	match side:
		"north":
			gap_start = center.x - WALL_DOOR_GAP_HALF_WIDTH
			gap_end = center.x + WALL_DOOR_GAP_HALF_WIDTH
			axis_pos = -boundary
		"south":
			gap_start = center.x - WALL_DOOR_GAP_HALF_WIDTH
			gap_end = center.x + WALL_DOOR_GAP_HALF_WIDTH
			axis_pos = boundary
		"west":
			gap_start = center.z - WALL_DOOR_GAP_HALF_WIDTH
			gap_end = center.z + WALL_DOOR_GAP_HALF_WIDTH
			axis_pos = -boundary
		"east":
			gap_start = center.z - WALL_DOOR_GAP_HALF_WIDTH
			gap_end = center.z + WALL_DOOR_GAP_HALF_WIDTH
			axis_pos = boundary
	match side:
		"north", "south":
			var left_size := gap_start + MAP_HALF
			var right_size := MAP_HALF - gap_end
			if left_size > 0.01:
				_add_box_collision(
					body,
					Vector3(-MAP_HALF + left_size * 0.5, height * 0.5, axis_pos),
					Vector3(left_size, height, WALL_THICKNESS)
				)
			if right_size > 0.01:
				_add_box_collision(
					body,
					Vector3(gap_end + right_size * 0.5, height * 0.5, axis_pos),
					Vector3(right_size, height, WALL_THICKNESS)
				)
		"west", "east":
			var left_size := gap_start + MAP_HALF
			var right_size := MAP_HALF - gap_end
			if left_size > 0.01:
				_add_box_collision(
					body,
					Vector3(axis_pos, height * 0.5, -MAP_HALF + left_size * 0.5),
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
	_support_root.collision_layer = 1
	_support_root.collision_mask = 0
	add_child(_support_root)
	var rectangles: Array[Rect2i] = [Rect2i(0, 0, GRID_COUNT, GRID_COUNT)]
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
			-MAP_HALF + (float(rect.position.x) + float(rect.size.x) * 0.5) * GRID_UNIT,
			-FLOOR_THICKNESS * 0.5,
			-MAP_HALF + (float(rect.position.y) + float(rect.size.y) * 0.5) * GRID_UNIT
		)
		collision.shape = shape
		_support_root.add_child(collision)
		_support_rect_count += 1


func _hole_rects() -> Array[Rect2i]:
	var holes: Array[Rect2i] = []
	for side in stair_hole_sides:
		match side:
			"west":
				# 楼梯两条6m跑道总外廓约15×27m；洞口按5m模块取
				# 15×30m。核心偏移半格后洞口边界仍与250m整层格线对齐。
				holes.append(_world_rect_to_grid(Rect2(-45.0, 0.0, 15.0, 30.0)))
			"east":
				holes.append(_world_rect_to_grid(Rect2(35.0, -25.0, 15.0, 30.0)))
			"north":
				holes.append(_world_rect_to_grid(Rect2(-25.0, -45.0, 30.0, 15.0)))
			"south":
				holes.append(_world_rect_to_grid(Rect2(0.0, 35.0, 30.0, 15.0)))
	return holes


func _world_rect_to_grid(world_rect: Rect2) -> Rect2i:
	return Rect2i(
		int(round((world_rect.position.x + MAP_HALF) / GRID_UNIT)),
		int(round((world_rect.position.y + MAP_HALF) / GRID_UNIT)),
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
