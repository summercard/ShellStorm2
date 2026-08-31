extends Node

const ROOT_SCENE := "res://assets/art/environments/rooftop_shelter_3d/runtime/env_rooftop_shelter_90x80m_facilities_root_top3d_v017.tscn"
const GLB_PATH := "res://assets/art/environments/rooftop_shelter_3d/runtime/env_rooftop_shelter_90x80m_facilities_v017.glb"
const REPORT_PATH := "res://assets/art/environments/rooftop_shelter_3d/reports/validation_v017.json"
const COLLISION_REPORT_PATH := "res://assets/art/environments/rooftop_shelter_3d/reports/collision_manifest_v017.json"
const SHARED_PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


func _ready() -> void:
	var failures: Array[String] = []
	_expect(ResourceLoader.exists(ROOT_SCENE, "PackedScene"), "v017天台设施包装场景缺失", failures)
	_expect(FileAccess.file_exists(GLB_PATH), "v017天台设施GLB缺失", failures)
	_expect(FileAccess.file_exists(REPORT_PATH), "v017天台验收报告缺失", failures)
	_expect(FileAccess.file_exists(COLLISION_REPORT_PATH), "v017组合阻挡清单缺失", failures)
	var packed := load(ROOT_SCENE) as PackedScene
	var rooftop := packed.instantiate() as Node3D if packed != null else null
	_expect(rooftop != null, "v017天台设施包装场景无法实例化", failures)
	if rooftop != null:
		add_child(rooftop)
		await get_tree().physics_frame
		_expect(rooftop.scale.is_equal_approx(Vector3.ONE), "v017天台根缩放不是1", failures)
		_expect(str(rooftop.get_meta("asset_id", "")) == "ENV-ROOFTOP-SHELTER-90X80", "天台稳定资产ID错误", failures)
		_expect(str(rooftop.get_meta("version", "")) == "v017", "天台设施包装版本不是v017", failures)
		_expect(str(rooftop.get_meta("runtime_scope", "")) == "facilities_only", "正式包装未限定为仅设施", failures)
		_expect(bool(rooftop.get_meta("native_floor_and_parapet_preserved", false)), "包装契约没有声明保留Godot原生地板与围栏", failures)
		_expect(rooftop.get_node_or_null("BaseEnvironment") == null, "设施包装错误带入Blender基础环境", failures)
		_expect((rooftop.get_meta("grid_dimensions", Vector2i.ZERO) as Vector2i) == Vector2i(18, 16), "天台网格不是18x16", failures)
		_expect(int(rooftop.get_meta("tile_count", 0)) == 234, "天台有效砖块数不是234", failures)
		_expect((rooftop.get_meta("roof_world_rect", Rect2()) as Rect2).is_equal_approx(Rect2(-50, -35, 90, 80)), "天台世界范围与游戏不一致", failures)
		_expect((rooftop.get_meta("base_atrium_world_rect", Rect2()) as Rect2).is_equal_approx(Rect2(-15, -10, 30, 30)), "基地中庭净空范围错误", failures)
		_expect((rooftop.get_meta("west_stair_world_rect", Rect2()) as Rect2).is_equal_approx(Rect2(-45, 0, 15, 30)), "西楼梯净空范围错误", failures)
		_expect((rooftop.get_meta("living_cluster_rect", Rect2()) as Rect2).is_equal_approx(Rect2(15.25, -31, 24, 67)), "东侧生活聚落规划范围错误", failures)
		_expect((rooftop.get_meta("door_walkway_rect", Rect2()) as Rect2).is_equal_approx(Rect2(15.25, -6, 24, 20)), "黄色门前动线范围错误", failures)
		_expect((rooftop.get_meta("shelter_zone_rect", Rect2()) as Rect2).is_equal_approx(Rect2(7.5, 27.5, 21, 17.5)), "贴北边缘的棚屋区范围错误", failures)
		_expect((rooftop.get_meta("farm_zone_rect", Rect2()) as Rect2).is_equal_approx(Rect2(-24, 22, 12.5, 20)), "西侧种植区范围错误", failures)
		_expect((rooftop.get_meta("radio_zone_rect", Rect2()) as Rect2).is_equal_approx(Rect2(30.5, 34, 9.5, 10.5)), "东北角通信高台范围错误", failures)
		_expect(int(rooftop.get_meta("editable_component_count", 0)) == 68, "包装场景可手动编辑组件数量不是68", failures)
		_expect(int(rooftop.get_meta("independent_blocker_count", 0)) == 39, "包装场景阻挡组件数量不是39", failures)
		_expect(int(rooftop.get_meta("collision_shape_count", 0)) == 82, "包装场景细分碰撞形状数量不是82", failures)
		var layout_root := rooftop.get_node_or_null("布局_可手动编辑") as Node3D
		_expect(layout_root != null and is_equal_approx(layout_root.position.y, -0.34), "设施没有按原生地面Y=0校正高度", failures)
		_verify_editable_components_and_collisions(rooftop, failures)
		_verify_key_blocker_rays(rooftop, failures)
		_verify_shared_palette(rooftop, failures)

	var report := _read_json(REPORT_PATH)
	_expect(bool(report.get("passed", false)), "v017天台布局报告未通过", failures)
	var layout := report.get("layout", {}) as Dictionary
	_expect(int(layout.get("tile_count", 0)) == 234, "布局报告砖块数错误", failures)
	_expect(int(layout.get("reserved_overlap_count", -1)) == 0, "布局报告存在保留区穿插", failures)
	_expect(int(layout.get("marked_zone_violation_count", -1)) == 0, "棚屋、种植或通信设施离开标注规划区", failures)
	_expect(int(layout.get("door_walkway_blocker_count", -1)) == 0, "黄色门前动线存在独立阻挡", failures)
	var collision_report := _read_json(COLLISION_REPORT_PATH)
	_expect(int(collision_report.get("count", 0)) == 39, "组合阻挡清单组件数量不是39", failures)
	_expect(int(collision_report.get("shape_count", 0)) == 82, "组合阻挡清单形状数量不是82", failures)

	if rooftop != null:
		rooftop.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ROOFTOP_SHELTER_ASSET_CONTRACT_OK: v017 imports facilities only, preserves the native rooftop shell, and exposes 68 editable components with 39 compound blockers / 82 shapes")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _verify_shared_palette(rooftop: Node3D, failures: Array[String]) -> void:
	var checked_surfaces := 0
	for candidate in rooftop.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			if material == null:
				continue
			checked_surfaces += 1
			if material.albedo_texture == null or material.albedo_texture.resource_path != SHARED_PALETTE_PATH:
				failures.append("Godot导入材质没有统一绑定公共色盘：%s" % mesh_instance.name)
				return
	_expect(checked_surfaces > 500, "Godot导入后的设施材质表面数量异常", failures)


func _verify_editable_components_and_collisions(rooftop: Node3D, failures: Array[String]) -> void:
	var layout_root := rooftop.get_node_or_null("布局_可手动编辑") as Node3D
	_expect(layout_root != null, "包装场景缺少可手动编辑布局根节点", failures)
	if layout_root == null:
		return
	var ids := {}
	var static_body_count := 0
	var collision_shape_count := 0
	var editable_component_count := 0
	for candidate in layout_root.find_children("*", "Node3D", true, false):
		var node := candidate as Node3D
		if bool(node.get_meta("manual_layout_editable", false)):
			editable_component_count += 1
	for candidate in layout_root.find_children("*", "StaticBody3D", true, false):
		var body := candidate as StaticBody3D
		static_body_count += 1
		var component_id := str(body.get_meta("component_id", ""))
		_expect(not component_id.is_empty(), "组合阻挡缺少component_id", failures)
		_expect(not ids.has(component_id), "组合阻挡component_id重复：%s" % component_id, failures)
		ids[component_id] = true
		_expect(body.get_parent() != null and bool(body.get_parent().get_meta("manual_layout_editable", false)), "阻挡未挂在可移动组件下：%s" % component_id, failures)
		for child in body.get_children():
			if child is CollisionShape3D:
				collision_shape_count += 1
	_expect(editable_component_count == 68, "TSCN可手动编辑节点数量不是68", failures)
	_expect(static_body_count == 39, "包装场景StaticBody3D数量不是39", failures)
	_expect(collision_shape_count == 82, "包装场景CollisionShape3D数量不是82", failures)
	_expect(ids.has("lounge_sofa") and ids.has("spool_table") and ids.has("table_radio"), "沙发、圆桌、桌面收音机未拥有各自阻挡", failures)
	_expect(ids.has("shelter_platform") and ids.has("shelter_stair_ramp"), "0.5米棚屋平台或连续木梯坡面缺少阻挡", failures)
	_expect(ids.has("radio_platform") and ids.has("radio_stairs") and ids.has("radio_railings"), "东北角高台、楼梯或栏杆缺少细分阻挡", failures)


func _verify_key_blocker_rays(rooftop: Node3D, failures: Array[String]) -> void:
	var space: PhysicsDirectSpaceState3D = rooftop.get_world_3d().direct_space_state
	for sample in [
		{"id": "lounge_sofa", "point": Vector3(21.0, 8.0, -37.8)},
		# 避开摆在桌面上的收音机，从圆桌外沿验证圆柱碰撞。
		{"id": "spool_table", "point": Vector3(21.9, 8.0, -34.5)},
		{"id": "table_radio", "point": Vector3(20.55, 8.0, -34.45)},
		{"id": "shelter_platform", "point": Vector3(10.0, 8.0, -37.0)},
		{"id": "shelter_stair_ramp", "point": Vector3(18.0, 8.0, -28.82)},
		{"id": "radio_platform", "point": Vector3(34.0, 8.0, -40.0)},
		{"id": "radio_stairs", "point": Vector3(35.0, 8.0, -34.8)},
	]:
		var start := sample["point"] as Vector3
		var query := PhysicsRayQueryParameters3D.create(start, Vector3(start.x, -1.0, start.z))
		var hit: Dictionary = space.intersect_ray(query)
		_expect(not hit.is_empty(), "独立阻挡射线未命中：%s" % sample["id"], failures)
		if hit.is_empty():
			continue
		var collider := hit.get("collider") as CollisionObject3D
		_expect(collider != null and str(collider.get_meta("component_id", "")) == sample["id"], "独立阻挡射线命中了错误组件：%s" % sample["id"], failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
