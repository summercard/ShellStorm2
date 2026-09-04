extends Node

const WALL_CONTENT_ID := "ENV-BASE99-WALL-CONTENTS-V021"
const REQUIRED_CHILDREN := [
	"二楼后墙服务管线",
	"二楼工具洞洞板",
	"BASE_STATUS状态终端",
	"东墙工业管线",
	"南墙资料板组",
]
const FORBIDDEN_TOKENS := ["门", "墙体", "墙板", "挡板"]


func _ready() -> void:
	var failures: Array[String] = []
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间没有生成", failures)
	if facility != null:
		var wall_content := facility.get_node_or_null("基地99层_美术布置层/场景装饰_可自由增删/BlenderV021非门墙面内容_仅视觉")
		_expect(wall_content != null, "V021非门墙面内容没有接入正式基地布局", failures)
		if wall_content != null:
			_expect(str(wall_content.get_meta("asset_id", "")) == WALL_CONTENT_ID, "墙面内容资产ID不正确", failures)
			_expect(str(wall_content.get_meta("asset_version", "")) == "v021", "墙面内容没有使用账本v021版本", failures)
			_expect(str(wall_content.get_meta("collision_policy", "")) == "visual_only_no_collision", "墙面内容不应拥有独立碰撞", failures)
			_expect(int(wall_content.get_meta("runtime_mesh_count", 0)) == 18, "墙面内容导出的运行时网格数不正确", failures)
			for child_name in REQUIRED_CHILDREN:
				_expect(wall_content.get_node_or_null(child_name) != null, "缺少墙面内容包: %s" % child_name, failures)
			_expect_mesh_near(wall_content, "BASE_STATUS状态终端", Vector3(8.38, 1.62, -3.58), 0.08, failures)
			_expect_mesh_near(wall_content, "南墙资料板组", Vector3(2.4, 4.65, 14.51), 0.08, failures)
			_expect_mesh_near(wall_content, "东墙WORK_TOGETHER海报", Vector3(14.14, 4.72, 8.45), 0.08, failures)
			for descendant_value in wall_content.find_children("*", "CollisionObject3D", true, false):
				_expect(false, "墙面内容产生了不应存在的碰撞节点: %s" % (descendant_value as Node).get_path(), failures)
			for child in wall_content.get_children():
				for token in FORBIDDEN_TOKENS:
					_expect(not child.name.contains(token), "门或结构墙体资产不应导入墙面内容根: %s" % child.name, failures)
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_WALL_CONTENT_V021_OK: 18 optimized non-door visual-only wall-content packages")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_mesh_near(root: Node, package_name: String, expected: Vector3, tolerance: float, failures: Array[String]) -> void:
	var package := root.get_node_or_null(package_name)
	_expect(package != null, "坐标检查缺少资产包: %s" % package_name, failures)
	if package == null:
		return
	var meshes := package.find_children("*", "MeshInstance3D", true, false)
	_expect(not meshes.is_empty(), "坐标检查找不到网格: %s" % package_name, failures)
	if meshes.is_empty():
		return
	var world_bounds := AABB()
	for mesh_value in meshes:
		var mesh_instance := mesh_value as MeshInstance3D
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		world_bounds = mesh_bounds if world_bounds.size == Vector3.ZERO else world_bounds.merge(mesh_bounds)
	var actual: Vector3 = root.to_local(world_bounds.get_center())
	_expect(actual.distance_to(expected) <= tolerance, "Blender摆放坐标漂移: %s actual=%s expected=%s" % [package_name, actual, expected], failures)
