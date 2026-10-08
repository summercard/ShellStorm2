extends RefCounted
## 三款背包的可失败资产契约；同时由装备流程及真实渲染验收调用。

const SIZES := {
	2: Vector3(0.56, 0.60, 0.28),
	4: Vector3(0.66, 0.74, 0.33),
	8: Vector3(0.76, 0.88, 0.38),
}
const NAMES := {2: "SMALL", 4: "MEDIUM", 8: "LARGE"}
const PALETTE := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const ROLES := ["01_精工金属_紫色骨架", "02_细腻哑光_青绿大面", "03_清漆反光_紫粉点缀", "04_柔和自发光_UI灯光"]

static func verify(model: Node3D, slots: int, failures: Array[String]) -> void:
	var tag := "%d格背包" % slots
	if model == null:
		failures.append(tag + "模型缺失")
		return
	var asset := model.get_node_or_null("ItemRoot") as Node3D
	if asset == null:
		failures.append(tag + "缺少稳定ItemRoot")
		return
	_expect(asset.get_meta("asset_id", "") == "ITM-EQUIPMENT-BACKPACK-%s-3D" % NAMES[slots], tag + "身份错误", failures)
	_expect(asset.get_meta("logical_id", "") == "equipment_backpack_%d" % slots, tag + "内容映射错误", failures)
	_expect(asset.scene_file_path == "res://assets/art/items_weapons/props/backpack_%s/runtime/prp_backpack_%s_root_top3d.tscn" % [NAMES[slots].to_lower(), NAMES[slots].to_lower()], tag + "非稳定场景引用", failures)
	_expect(asset.scale.is_equal_approx(Vector3.ONE), tag + "源资产根缩放非1", failures)
	if not model.has_meta("equipment_item_id"):
		_expect(model.scale.is_equal_approx(Vector3.ONE), tag + "世界/UI根缩放非1", failures)
	_expect(asset.get_meta("front_axis", "") == "+Z", tag + "前袋轴向错误", failures)
	_expect(model.get_meta("model_kind", "") == "backpack" and int(model.get_meta("backpack_extra_slots", 0)) == slots, tag + "原根元数据丢失", failures)
	_expect(model.find_children("*", "CollisionObject3D", true, false).is_empty() and model.find_children("*", "CollisionShape3D", true, false).is_empty(), tag + "意外玩法碰撞", failures)
	_expect(model.find_children("*", "Skeleton3D", true, false).is_empty(), tag + "静态资产不应有骨架", failures)
	_expect(model.find_children("*Shoulder*", "", true, false).is_empty() and model.find_children("*肩带*", "", true, false).is_empty(), tag + "禁止背部肩带", failures)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var count := 0
	var points: Array[Vector3] = []
	var front_pocket := false
	var clasps := 0
	var bedroll := false
	for node in meshes:
		var instance := node as MeshInstance3D
		_expect(instance.mesh is ArrayMesh, tag + "仍使用程序占位几何", failures)
		var transform := _relative_transform(instance, model)
		if str(instance.name).contains("前袋"):
			front_pocket = true
			_expect((transform * instance.mesh.get_aabb().get_center()).z > 0.0, tag + "前袋朝内", failures)
		if str(instance.name).contains("前盖扣带"):
			clasps += 1
		if str(instance.name).contains("顶部卷铺盖"):
			bedroll = true
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			count += (indices.size() if not indices.is_empty() else verts.size()) / 3
			for point in verts:
				points.append(transform * point)
			var material := instance.get_active_material(surface) as BaseMaterial3D
			_expect(material != null, tag + "缺少材质", failures)
			if material != null:
				_expect(material.resource_name in ROLES, tag + "材质名不合规", failures)
				_expect(material.albedo_texture != null and material.albedo_texture.resource_path == PALETTE, tag + "未绑定公共色盘", failures)
				_expect(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, tag + "未使用Closest", failures)
			for triangle in range(0, indices.size(), 3):
				var a := uv[indices[triangle]]
				var b := uv[indices[triangle + 1]]
				var c := uv[indices[triangle + 2]]
				_expect(absf((b-a).cross(c-a)) > 0.00000001, tag + "导出UV三角无面积", failures)
				_expect(Vector2i((a*10).floor()) == Vector2i((b*10).floor()) and Vector2i((a*10).floor()) == Vector2i((c*10).floor()), tag + "导出UV跨格", failures)
	_expect(count > 0 and count <= 500 and count == int(asset.get_meta("triangle_count", 0)), tag + "三角预算或清单不一致：%d" % count, failures)
	_expect(front_pocket and clasps == (0 if slots == 2 else 1 if slots == 4 else 2) and bedroll == (slots == 8), tag + "款式结构不符", failures)
	if not points.is_empty():
		var low := points[0]
		var high := points[0]
		for point in points:
			low = low.min(point)
			high = high.max(point)
		_expect((high-low-SIZES[slots]).length() < 0.0001, tag + "整包尺寸不符：%s" % str(high-low), failures)
		_expect((high+low).length() < 0.0001, tag + "不是包围盒中心原点", failures)

## 在真实动作驱动器中采样，统一换到背包挂点空间，避免翻滚时世界AABB误报。
static func measure_worn(player: Player3D, slots: int, failures: Array[String], enforce := true) -> Dictionary:
	var avatar := player.avatar
	var motion: CharacterMotionLibrary3D = avatar.get("_authored_motion")
	var clips: Dictionary = motion.get("_cache").get("clips", {})
	var model := player.get("_backpack_model") as Node3D
	var socket := avatar.get_backpack_socket()
	var minimum := INF
	var maximum_head_z := -INF
	var body_bounds := visible_bounds(avatar.body.get_node("Model"), avatar.body)
	var max_follow_error := 0.0
	var max_back_gap := -INF
	var worst := {}
	var samples := 0
	var intersections := 0
	var envelopes: Array = []
	var clip_names := clips.keys()
	clip_names.sort()
	for clip_name: String in clip_names:
		avatar.set("_state", clip_name)
		motion.pose_lock_enabled = true
		for step in 41:
			motion.pose_lock_phase = step / 40.0
			# 完成过渡后采样同一正式驱动器，不在测试中复制动画变换。
			motion.apply(avatar, 1.0)
			avatar.body.force_update_transform()
			var follow := player.get("_backpack_follow") as RemoteTransform3D
			if follow != null:
				follow.force_update_transform()
				max_follow_error = maxf(max_follow_error, model.global_position.distance_to(follow.global_position))
			var head_bounds := visible_bounds(avatar.bunny_head_model, avatar.body)
			var pack_bounds := visible_bounds(model, avatar.body)
			max_back_gap = maxf(max_back_gap, pack_bounds.position.z - body_bounds.end.z)
			envelopes.append([motion.active_clip, motion.pose_lock_phase, head_bounds.position.y, head_bounds.end.z])
			var gap := maxf(pack_bounds.position.z - head_bounds.end.z, head_bounds.position.y - pack_bounds.end.y)
			maximum_head_z = maxf(maximum_head_z, head_bounds.end.z)
			if head_bounds.intersects(pack_bounds):
				intersections += 1
			if gap < minimum:
				minimum = gap
				worst = {"clip": motion.active_clip, "phase": motion.pose_lock_phase, "head_bounds": str(head_bounds), "pack_bounds": str(pack_bounds)}
			samples += 1
	if enforce:
		_expect(samples >= 41 * 14, "%d格动作采样不足" % slots, failures)
		_expect(minimum >= 0.015, "%d格背包侵入头部动作包络：%.6fm %s" % [slots, minimum, str(worst)], failures)
		_expect(max_follow_error < 0.0001, "%d格背包未跟随躯干" % slots, failures)
		_expect(is_equal_approx(model.scale.x, 0.68), "%d格背负缩放契约错误" % slots, failures)
		_expect(max_back_gap < 0.04, "%d格背包离背过远：%.6f" % [slots, max_back_gap], failures)
	avatar.set("_state", "idle")
	motion.pose_lock_phase = 0.0
	motion.apply(avatar, 1.0)
	motion.pose_lock_enabled = false
	return {"body_bounds": str(body_bounds), "max_back_gap": max_back_gap, "max_follow_error": max_follow_error, "envelopes": envelopes, "slots": slots, "samples": samples, "clips": clip_names, "minimum_socket_gap_m": minimum, "maximum_head_socket_z": maximum_head_z, "aabb_intersections": intersections, "worst": worst, "offset": str(model.position), "socket": str(socket.position), "avatar_scale": str(avatar.scale)}

static func visible_bounds(root: Node3D, space: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var transform := space.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := transform * vertex
				bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
				found = true
	return bounds

static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var value := node.transform
	var parent := node.get_parent() as Node3D
	while parent != null and parent != root:
		value = parent.transform * value
		parent = parent.get_parent() as Node3D
	return value

static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
