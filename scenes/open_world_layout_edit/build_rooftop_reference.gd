extends SceneTree

## 一次性生成静态视觉快照，不加载主游戏，不回写正式资产。
const OUTPUT := "res://scenes/open_world_layout_edit/rooftop_visual_reference.tscn"
const ROUTE := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"
const UPPER_SHELL := "res://assets/art/environments/base_facility_3d/runtime/env_base100_upper_shell_30x30_h12/env_base100_upper_shell_30x30_h12_root_top3d.tscn"

# 无头渲染器不能可靠回读 MultiMesh 变换，在生成入口直接捕获原始变换。
class CapturedRooftop extends TowerFloorStage3D:
	var floor_batches: Dictionary = {}

	func _create_floor_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], material: StandardMaterial3D) -> MultiMeshInstance3D:
		floor_batches[node_name] = transforms.duplicate()
		return super._create_floor_multimesh(node_name, mesh, transforms, material)

var instance_count := 0

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	if FileAccess.file_exists(OUTPUT) and "--rebuild-reference" not in OS.get_cmdline_user_args():
		push_error("已有天台参照，拒绝覆盖。")
		quit(1)
		return
	var route := load(ROUTE).instantiate() as Node3D
	var opening: float = float(route.get_meta("north_bridge_opening_x", INF))
	route.free()
	var stage := CapturedRooftop.new()
	stage.configure(0, "rooftop", ["west"])
	stage.north_bridge_opening_x = opening
	root.add_child(stage)
	if stage.get("_rooftop_art_blocker_count") != 0:
		push_error("真实天台装饰生成失败。")
		stage.free()
		quit(1)
		return
	var reference := Node3D.new()
	reference.name = "RooftopVisualReference"
	reference.set_meta("source_generator", "res://src/world3d/TowerFloorStage3D.gd")
	reference.set_meta("world_rect_m", Rect2(-50, -35, 100, 80))
	reference.set_meta("north_bridge_opening_x", opening)
	reference.set_meta("snapshot_only", true)
	for batch_name in stage.floor_batches:
		for placement in stage.floor_batches[batch_name]:
			_append_prefab(reference, stage.ROOFTOP_FLOOR_SCENE, str(batch_name), placement)
	var slots := stage.get_outer_straight_slot_transforms()
	var kinds := stage.get_outer_slot_kinds()
	var scenes: Dictionary = {"intact": stage.PARAPET_SCENE}
	for index in range(stage.PARAPET_DAMAGE_KEYS.size()):
		scenes[stage.PARAPET_DAMAGE_KEYS[index]] = stage.PARAPET_DAMAGE_SCENES[index]
	for index in range(slots.size()):
		_append_prefab(reference, scenes[kinds[index]], "Parapet_" + str(kinds[index]), slots[index])
	for corner in stage.get("_rooftop_outer_corner_visuals"):
		_append_prefab(reference, stage.ROOFTOP_CORNER_PREFAB, "Corner", corner.transform)
	var decor := stage.get_node("FormalRooftopFacilities")
	for item in decor.get_children():
		_append_prefab(reference, load(item.scene_file_path), str(item.name), item.transform)
	# 围护在正式基地根 (0,-12,5) 下；不挂基地整屋，也不执行围护碰撞脚本。
	var upper := load(UPPER_SHELL).instantiate() as Node3D
	var upper_placement := Transform3D(Basis.IDENTITY, Vector3(0, -12, 5))
	for group in upper.get_children():
		for component in group.get_children():
			_append_prefab(reference, load(component.scene_file_path), "UpperShell", upper_placement * group.transform * component.transform)
	upper.free()
	reference.set_meta("prefab_instance_count", instance_count)
	reference.set_meta("floor_tile_count", stage.get("_tile_count"))
	reference.set_meta("decor_instance_count", stage.get("_rooftop_art_instance_count"))
	reference.set_meta("parapet_slot_count", slots.size())
	var packed := PackedScene.new()
	var error := packed.pack(reference)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	print("ROOFTOP_REFERENCE error=%s prefabs=%d floor_tiles=%s decor=%s parapets=%d" % [error, instance_count, stage.get("_tile_count"), stage.get("_rooftop_art_instance_count"), slots.size()])
	reference.free()
	stage.free()
	quit(0 if error == OK else 1)

func _append_prefab(target: Node3D, scene: PackedScene, label: String, placement: Transform3D) -> Node3D:
	var instance := scene.instantiate() as Node3D
	instance.name = "%s_%04d" % [label, instance_count]
	instance.transform = placement
	target.add_child(instance)
	instance.owner = target
	instance_count += 1
	return instance
