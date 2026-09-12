extends Node

const FACILITY_ROOT := preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v004.tscn")
const EXPECTED_PACKAGE_COUNT := 45
const EXPECTED_SOLID_PACKAGE_COUNT := 35


func _ready() -> void:
	var root := FACILITY_ROOT.instantiate()
	add_child(root)
	if root.get_meta("asset_id", "") != "ENV-BASE99-REMAINING-FACILITIES-V021":
		_fail("asset id metadata mismatch")
		return
	if root.get_meta("asset_version", "") != "v021":
		_fail("asset version metadata mismatch")
		return
	if root.get_child_count() != EXPECTED_PACKAGE_COUNT:
		_fail("expected %d packages, got %d" % [EXPECTED_PACKAGE_COUNT, root.get_child_count()])
		return
	var solid_count := 0
	var scene_vfx_count := 0
	for package in root.get_children():
		if package.name == "场景特效_光束尘埃粒子":
			scene_vfx_count += 1
			continue
		if package.find_child("ImportedModel", true, false) == null:
			_fail("missing ImportedModel on %s" % package.name)
			return
		var policy := _find_collision_policy(package)
		var has_solid_collision := package.find_child("StaticCollision", true, false) != null \
			or not package.find_children("*", "StaticBody3D", true, false).is_empty()
		if has_solid_collision:
			solid_count += 1
			if policy.is_empty() or policy == "visual_only_no_collision":
				_fail("solid package has invalid collision policy: %s" % package.name)
				return
		elif policy != "visual_only_no_collision":
			_fail("non-solid package has unexpected collision policy on %s: %s" % [package.name, policy])
			return
	if solid_count != EXPECTED_SOLID_PACKAGE_COUNT:
		_fail("expected %d solid packages, got %d" % [EXPECTED_SOLID_PACKAGE_COUNT, solid_count])
		return
	if scene_vfx_count != int(root.get_meta("scene_vfx_count", 0)):
		_fail("scene VFX count does not match current assembly metadata")
		return
	print("BASE99_REMAINING_FACILITIES_V021_OK: current v004 ledger has %d packages and %d simplified solid blockers; 46-package baseline is an old asset" % [EXPECTED_PACKAGE_COUNT, solid_count])
	get_tree().quit(0)


func _find_collision_policy(node: Node) -> String:
	var policy := str(node.get_meta("collision_policy", ""))
	if not policy.is_empty():
		return policy
	for child in node.get_children():
		var nested_policy := _find_collision_policy(child)
		if not nested_policy.is_empty():
			return nested_policy
	return ""


func _fail(message: String) -> void:
	push_error("BASE99_REMAINING_FACILITIES_V021_FAIL: " + message)
	get_tree().quit(1)
