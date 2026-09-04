extends Node

const FACILITY_ROOT := preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v001.tscn")
const EXPECTED_PACKAGE_COUNT := 45
const EXPECTED_SOLID_PACKAGE_COUNT := 34


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
	for package in root.get_children():
		if not package.has_node("ImportedModel"):
			_fail("missing ImportedModel on %s" % package.name)
			return
		var policy := str(package.get_meta("collision_policy", ""))
		if policy == "per_source_object_box_collision":
			solid_count += 1
			if not package.has_node("StaticCollision"):
				_fail("solid package missing collision: %s" % package.name)
				return
		elif policy != "visual_only_no_collision":
			_fail("unexpected collision policy on %s: %s" % [package.name, policy])
			return
	if solid_count != EXPECTED_SOLID_PACKAGE_COUNT:
		_fail("expected %d solid packages, got %d" % [EXPECTED_SOLID_PACKAGE_COUNT, solid_count])
		return
	print("BASE99_REMAINING_FACILITIES_V021_OK: %d optimized packages, %d simplified solid blockers" % [EXPECTED_PACKAGE_COUNT, solid_count])
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("BASE99_REMAINING_FACILITIES_V021_FAIL: " + message)
	get_tree().quit(1)
