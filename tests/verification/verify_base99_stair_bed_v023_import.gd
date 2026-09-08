extends SceneTree

const BED_PREFAB := preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/loft_bed_and_bedding/loft_bed_and_bedding_root_top3d_v004.tscn")
const STAIR_PREFAB := preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_stair_l_z5/env_base99_stair_l_z5_root_top3d_v006.tscn")
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const LAYOUT_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn"

func _init() -> void:
	var failures: Array[String] = []
	var bed := BED_PREFAB.instantiate() as Node3D
	var stair := STAIR_PREFAB.instantiate() as Node3D
	_validate_bed(bed, failures)
	_validate_stair(stair, failures)
	_validate_runtime_layout(failures)
	bed.free()
	stair.queue_free()
	if failures.is_empty():
		print("BASE99_STAIR_BED_V023_IMPORT_OK bed=v004 stair=v006 layout=v002")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_bed(bed: Node3D, failures: Array[String]) -> void:
	if str(bed.get_meta("asset_id", "")) != "ENV-BASE99-V023::loft_bed_and_bedding":
		failures.append("v023 bed prefab is not installed")
	if bed.find_children("*", "CollisionObject3D", true, false).is_empty():
		failures.append("v023 bed collision is missing")
	var bounds := bed.get_node_or_null("StaticCollision/OptimizedOutputBounds") as CollisionShape3D
	if bounds == null or not bounds.shape is BoxShape3D:
		failures.append("v023 bed bounds collision is missing")
	elif not is_equal_approx(bounds.position.x, 1.75) or not is_equal_approx(bounds.position.y, 6.420979) or not is_equal_approx(bounds.position.z, -11.55):
		failures.append("v023 bed bounds collision moved away from the baked bed")
	_validate_visual_materials(bed, failures)


func _validate_stair(stair: Node3D, failures: Array[String]) -> void:
	if str(stair.get_meta("asset_version", "")) != "v006":
		failures.append("v023 stair visual prefab is not installed")
	if str(stair.get_meta("collision_policy", "")) != "source_convex_ramps_and_rails":
		failures.append("v023 stair source collision policy is missing")
	var blockers := stair.find_children("Blocker_*", "CollisionShape3D", true, false)
	if blockers.size() != 8:
		failures.append("v023 stair must preserve all 8 source blockers")
	_validate_visual_materials(stair, failures)


func _validate_visual_materials(package: Node3D, failures: Array[String]) -> void:
	var palette := load(PALETTE_PATH) as Texture2D
	var material_count := 0
	for light in package.find_children("*", "Light3D", true, false):
		failures.append("imported asset must not contain DCC light: %s" % light.name)
	for mesh_node_value in package.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mesh_node_value as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as StandardMaterial3D
			if material == null:
				continue
			material_count += 1
			if material.albedo_texture == null or material.albedo_texture != palette:
				failures.append("shared palette missing: %s" % mesh_node.name)
	if material_count == 0:
		failures.append("no imported materials found: %s" % package.name)


func _validate_runtime_layout(failures: Array[String]) -> void:
	var layout_text := FileAccess.get_file_as_string(LAYOUT_PATH)
	if "env_base99_stair_l_z5_root_top3d_v006.tscn" not in layout_text:
		failures.append("live art layout does not reference stair v006")
	if "env_base99_remaining_facilities_root_top3d_v004.tscn" not in layout_text:
		failures.append("live art layout does not reference bed assembly v004")
