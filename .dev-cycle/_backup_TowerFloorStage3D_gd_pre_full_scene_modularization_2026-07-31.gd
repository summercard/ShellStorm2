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
	"res://assets/art/environments/tower_descent_3d/components/env_tower_floor_tile_5m_top3d_v001.glb"
)
const WALL_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v001.glb"
)
const PARAPET_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_parapet_5m_top3d_v001.glb"
)
const FLOOR_TILE_MATERIAL: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_override_top3d_v001.tres"
)

var floor_index := 0
var floor_kind := "combat"
var stair_hole_sides: Array[String] = []
var _floor_visual: MultiMeshInstance3D
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
	if _floor_visual != null:
		_floor_visual.visible = show_floor
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
		"outer_module_count": GRID_COUNT * 4,
		"support_rect_count": _support_rect_count,
		"stair_hole_sides": stair_hole_sides.duplicate(),
		"shell_visible": _shell_visible,
		"floor_visible": _floor_visible,
		"outer_visible": _outer_visible,
		"support_collision_persistent": _support_root != null,
		"uses_imported_floor_mesh": _floor_visual != null and _floor_visual.multimesh != null,
		"uses_imported_outer_mesh": _outer_visual != null and _outer_visual.multimesh != null,
	}


func _build_floor() -> void:
	var mesh := _mesh_from_scene(FLOOR_SCENE)
	if mesh == null:
		push_error("Tower floor module GLB has no MeshInstance3D")
		return
	var transforms: Array[Transform3D] = []
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
			transforms.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	_floor_visual = MultiMeshInstance3D.new()
	_floor_visual.name = "ImportedFloorTileGrid5M"
	_floor_visual.multimesh = multimesh
	_floor_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_floor_visual.material_override = FLOOR_TILE_MATERIAL
	add_child(_floor_visual)
	_tile_count = transforms.size()


func _build_outer_shell() -> void:
	var module_scene := PARAPET_SCENE if floor_kind == "rooftop" else WALL_SCENE
	var mesh := _mesh_from_scene(module_scene)
	if mesh == null:
		push_error("Tower outer-wall module GLB has no MeshInstance3D")
		return
	var transforms: Array[Transform3D] = []
	var boundary := MAP_HALF - WALL_THICKNESS * 0.5
	for index in range(GRID_COUNT):
		var offset := -MAP_HALF + GRID_UNIT * (float(index) + 0.5)
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(offset, 0.0, -boundary)))
		transforms.append(Transform3D(Basis(Vector3.UP, PI), Vector3(-offset, 0.0, boundary)))
		transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-boundary, 0.0, -offset)))
		transforms.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(boundary, 0.0, offset)))
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

	var body := StaticBody3D.new()
	body.name = "OuterBoundaryCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var height := 1.5 if floor_kind == "rooftop" else 9.0
	for spec in [
		[Vector3(0.0, height * 0.5, -boundary), Vector3(MAP_SIZE, height, WALL_THICKNESS)],
		[Vector3(0.0, height * 0.5, boundary), Vector3(MAP_SIZE, height, WALL_THICKNESS)],
		[Vector3(-boundary, height * 0.5, 0.0), Vector3(WALL_THICKNESS, height, MAP_SIZE)],
		[Vector3(boundary, height * 0.5, 0.0), Vector3(WALL_THICKNESS, height, MAP_SIZE)],
	]:
		var shape := BoxShape3D.new()
		shape.size = spec[1] as Vector3
		var collision := CollisionShape3D.new()
		collision.position = spec[0] as Vector3
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
