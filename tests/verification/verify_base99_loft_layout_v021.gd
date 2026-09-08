extends Node
## Verifies the approved three-package layout-only revision without GLB reimport.

const ROOT_SCENE: PackedScene = preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v002.tscn")

const EXPECTED := {
	"31_参考床架床品与床下收纳_资产包": {
		"position": Vector3(-9.5, 0.0, -11.85), "rotation_y": -PI * 0.5,
	},
	"32_参考床头柜与生活物件_资产包": {
		"position": Vector3(7.62, 0.0, -10.435), "rotation_y": PI * 0.5,
	},
	"37_红棕茶几与生活物件_资产包": {
		"position": Vector3(-2.6, 0.0, 2.83), "rotation_y": 0.0,
	},
}


func _ready() -> void:
	var failures: Array[String] = []
	var root := ROOT_SCENE.instantiate() as Node3D
	add_child(root)
	for package_name in EXPECTED:
		var package := root.get_node_or_null(NodePath(package_name)) as Node3D
		if package == null:
			failures.append("缺少布局资产包: %s" % package_name)
			continue
		var expected: Dictionary = EXPECTED[package_name]
		if not package.position.is_equal_approx(expected.position as Vector3):
			failures.append("位置错误: %s = %s" % [package_name, package.position])
		if not is_equal_approx(package.rotation.y, float(expected.rotation_y)):
			failures.append("朝向错误: %s = %s" % [package_name, package.rotation.y])
		if str(package.get_meta("layout_revision", "")) != "v021_loft_layout_adjustment_001":
			failures.append("缺少布局台账版本: %s" % package_name)
		if package.find_children("*", "CollisionObject3D", true, false).is_empty():
			failures.append("布局后丢失既有碰撞: %s" % package_name)
	if failures.is_empty():
		print("BASE99_LOFT_LAYOUT_V021_OK: bed, nightstand and coffee table transformed without GLB reexport")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
