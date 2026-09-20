extends Node
## 一次性探针：核对入口安全房 v007 房间包的**玩法阻挡**是否真的存在于运行时。
##
## 背景：2026-09-20 之前，15 个房间包的 metadata 声明
##   collision_owner = "godot_0p30m_structural_proxy" / collision_policy = "none_in_package"
## 但全仓不存在该代理的任何实现 → 设施全部可穿模。当日改为「内嵌 BoxShape3D」（范例 B）。
##
## 本探针只读，不改游戏状态，覆盖四件事：
##   1. 清单一致性：EXPECTED_BLOCKING ∪ EXPECTED_NON_BLOCKING 必须**恰好等于**当前房间包清单
##      （新增包会强制在此处做一次「挡 / 不挡」的表态，避免悄悄漏做）
##   2. 元数据真实性：metadata/collision_shape_count 必须等于实测启用形状数
##   3. 几何契约：阻挡件的 BoxShape3D.size 必须等于 bounds_size_m，盒中心 = +height/2
##   4. **物理证明**：把玩家身位大小的探针放在阻挡件包围盒中心做 intersect_shape，
##      必须命中该包自己拥有的 StaticBody3D（layer 1）；不阻挡件必须打不中自己。

const ROOM_RUNTIME_ROOT := "res://assets/art/environments/tower_zones/battle/runtime/"
const PLAYER_PROBE_BAND_MAX_Y := 1.0
## 家具必须占住「走行面以上 1m」这段身位，否则等于没挡（例如碰撞盒浮在 4m 高）。
const EXPECTED_BLOCKING: Array[String] = [
	"north_server_00",
	"north_server_01",
	"north_server_02",
	"north_server_03",
	"north_server_04",
	"north_server_05",
	"north_broken_core",
	"east_repair_bay",
	"east_robot_arm",
	"office_planter",
	"maintenance_chair",
]
const EXPECTED_NON_BLOCKING: Array[String] = [
	"floor_base",
	"overhead_services",
	"debris_papers",
	"north_nexus_sign",
]

var failures: Array[String] = []


func _ready() -> void:
	print("=== 探针：安全房 v007 —— 房间包玩法阻挡 ===")
	_probe_manifest_consistency()
	print("")
	await _probe_runtime()
	print("")
	if failures.is_empty():
		print("SAFE_ROOM_FACILITY_COLLISION_OK")
	else:
		print("SAFE_ROOM_FACILITY_COLLISION_FAIL: %d" % failures.size())
		for failure in failures:
			print("  - ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)


## 1. 清单一致性：两个期望集合必须恰好覆盖运行时房间包清单。
func _probe_manifest_consistency() -> void:
	var declared := EXPECTED_BLOCKING.duplicate()
	declared.append_array(EXPECTED_NON_BLOCKING)
	var runtime_ids: Array[String] = []
	for value in DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS:
		runtime_ids.append(str(value))
	declared.sort()
	runtime_ids.sort()
	print(
		"清单：运行时 %d 件 / 探针表态 %d 件（阻挡 %d + 不阻挡 %d）"
		% [runtime_ids.size(), declared.size(), EXPECTED_BLOCKING.size(), EXPECTED_NON_BLOCKING.size()]
	)
	if runtime_ids.is_empty():
		failures.append("哨兵：运行时房间包清单为空，后续断言无样本，结论不可信")
	if declared != runtime_ids:
		failures.append(
			"探针表态与运行时房间包清单不一致（新增/删除包必须在此处补一次挡与不挡的表态）\n      运行时=%s\n      探针  =%s"
			% [runtime_ids, declared]
		)


## 2~4. 实际建一间 15×15 双门安全房，逐包实测。
func _probe_runtime() -> void:
	var room := DungeonRoom3D.new()
	room.configure({
		"room_id": "probe_facility_collision",
		"room_type": "STAIR_LOBBY",
		"size_class": "tower_cell",
		"doors": ["north", "east"],
		"door_targets": {"north": "probe_a", "east": "probe_b"},
		"seed": 4242,
		"custom_dimensions": Vector2(15.0, 15.0),
		"tower_module_shell": true,
	})
	add_child(room)
	room.ensure_shell_built()
	room.ensure_detail_built()
	# 物理需要空间步进后才可查询。
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var art_root := room.get_node_or_null("SafeRoomArtRoot")
	if art_root == null:
		failures.append("安全房未生成 SafeRoomArtRoot")
		room.queue_free()
		return
	var space: PhysicsDirectSpaceState3D = room.get_world_3d().direct_space_state
	var packages := 0
	var blocking_hits := 0
	var blocking_total := 0
	for value in art_root.get_children():
		var package := value as Node3D
		if package == null or not package.name.begins_with("SafeRoomPackage_"):
			continue
		packages += 1
		var slug := str(package.get_meta("slug", ""))
		var bounds := package.get_meta("bounds_size_m", Vector3.ZERO) as Vector3
		var declared_shapes := int(package.get_meta("collision_shape_count", -1))
		var live_shapes := 0
		var live_bodies := 0
		var size_mismatch := -1
		for body_value in package.find_children("*", "StaticBody3D", true, false):
			var body := body_value as StaticBody3D
			if body.collision_layer == 0:
				continue
			live_bodies += 1
			for shape_value in body.find_children("*", "CollisionShape3D", true, false):
				var shape := shape_value as CollisionShape3D
				if shape.disabled or shape.shape == null:
					continue
				live_shapes += 1
				var box := shape.shape as BoxShape3D
				if box != null and not box.size.is_equal_approx(bounds):
					size_mismatch = live_shapes
		var expects_blocking := slug in EXPECTED_BLOCKING
		if expects_blocking:
			blocking_total += 1
		var probe_point := package.global_transform.origin + Vector3(0.0, bounds.y * 0.5, 0.0)
		var hit_own := _probe_hits_own_package(space, probe_point, package)
		if expects_blocking and hit_own:
			blocking_hits += 1
		print(
			"  %-20s 声明=%d 启用体=%d 启用形=%d  盒=%s  世界中心y=%.3f  物理探针=%s  期望=%s"
			% [
				slug,
				declared_shapes,
				live_bodies,
				live_shapes,
				_vector3_text(bounds),
				probe_point.y,
				"命中本包" if hit_own else "未命中",
				"阻挡" if expects_blocking else "不挡",
			]
		)
		if declared_shapes != live_shapes:
			failures.append(
				"%s 元数据 collision_shape_count=%d 与实测启用形状数 %d 不一致"
				% [slug, declared_shapes, live_shapes]
			)
		if size_mismatch != -1:
			failures.append("%s 第 %d 个 BoxShape3D 尺寸 != bounds_size_m(%s)" % [
				slug, size_mismatch, _vector3_text(bounds)
			])
		if expects_blocking:
			if live_shapes == 0:
				failures.append("%s 应为阻挡件，实测没有任何启用碰撞形状" % slug)
			if not hit_own:
				failures.append("%s 应为阻挡件，但玩家身位探针打不中它" % slug)
			var bottom := probe_point.y - bounds.y * 0.5
			var top := probe_point.y + bounds.y * 0.5
			if bottom > PLAYER_PROBE_BAND_MAX_Y or top < 0.0:
				failures.append(
					"%s 碰撞盒 [%.3f..%.3f] 未覆盖走行面以上 %.1fm 身位，等于没挡"
					% [slug, bottom, top, PLAYER_PROBE_BAND_MAX_Y]
				)
		else:
			if live_shapes != 0:
				failures.append("%s 按设计不应阻挡，实测却有 %d 个启用形状" % [slug, live_shapes])
			if hit_own:
				failures.append("%s 按设计不应阻挡，但玩家身位探针命中它" % slug)

	# 哨兵：样本数必须与清单一致，且阻挡样本不能为 0（0 样本断言恒真）。
	var expected_packages := DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS.size()
	print("")
	print(
		"汇总：实际检查 %d 件（期望 %d）· 阻挡件 %d/%d 探针命中"
		% [packages, expected_packages, blocking_hits, blocking_total]
	)
	if packages != expected_packages:
		failures.append("哨兵：实测房间包 %d 件 != 清单 %d 件" % [packages, expected_packages])
	if blocking_total == 0:
		failures.append("哨兵：阻挡件样本为 0，阻挡断言恒真、结论不可信")
	room.queue_free()


## 玩家身位大小的方形探针，只看 layer 1（实心世界层）。
func _probe_hits_own_package(
	space: PhysicsDirectSpaceState3D, point: Vector3, package: Node3D
) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.transform = Transform3D(Basis(), point)
	for result in space.intersect_shape(query, 8):
		var collider := result.get("collider") as Node
		if collider == null:
			continue
		var walk: Node = collider
		while walk != null:
			if walk == package:
				return true
			walk = walk.get_parent()
	return false


func _vector3_text(value: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [value.x, value.y, value.z]
