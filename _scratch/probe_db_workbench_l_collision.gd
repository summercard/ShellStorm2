extends Node3D

## 临时探针（_scratch，未跟踪）：实测 db 房 L 形维修台 workbench_a 的分段碰撞。
##
## 验收四件事：
##   ① prefab 仍可加载，碰撞形状数与 metadata/collision_shape_count 一致（L 形需 2 段）。
##   ② L 的凹口（x[-7.05,5.20] * z[-1.875,3.625]）里没有任何阻挡 —— 竖直/水平射线必须打空。
##   ③ 两臂内部仍在挡人 —— 射线必须命中。
##   ④ 内侧面位置精确：从凹口朝臂里打，命中点应落在几何内侧面（z=-1.875 / x=5.20）。
## 对照组：按旧整块 AABB(14.1, 3.565, 7.25) 做同样的点，量化修掉了多少空阻挡。
##
## 🔴 射线起点必须在盒外：Godot 默认 hit_from_inside=false，从盒内起步的射线打不到该盒，
##    第一版探针把起点放在 y=3.0（盒顶 3.565 之内）⇒ 全部假绿/假红，已改为从 y=5.0 起步。

const PREFAB := (
	"res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/"
	+ "db_room/workbench_a/workbench_a_root_top3d.tscn"
)
const OLD_SIZE := Vector3(14.1, 3.565, 7.25)

var _failures: Array[String] = []


func _ready() -> void:
	var scene := load(PREFAB) as PackedScene
	if scene == null:
		print("DB_WORKBENCH_L_COLLISION_FAIL prefab 加载失败")
		get_tree().quit(1)
		return
	var inst := scene.instantiate() as Node3D
	inst.name = "WorkbenchA"
	add_child(inst)

	var declared := int(inst.get_meta("collision_shape_count", -1))
	var policy := str(inst.get_meta("collision_policy", ""))
	var live: Array[CollisionShape3D] = []
	for body_value in inst.find_children("*", "StaticBody3D", true, false):
		var body := body_value as StaticBody3D
		if body.collision_layer == 0:
			continue
		for shape_value in body.find_children("*", "CollisionShape3D", true, false):
			var shape := shape_value as CollisionShape3D
			if shape.disabled or shape.shape == null:
				continue
			live.append(shape)
			var box := shape.shape as BoxShape3D
			var box_size := box.size if box != null else Vector3.ZERO
			print("SHAPE %s size=%s local_pos=%s" % [shape.name, box_size, shape.position])
			if box == null:
				_failures.append("%s 不是 BoxShape3D" % shape.name)
				continue
			var bottom := shape.global_position.y - box_size.y * 0.5
			var top := shape.global_position.y + box_size.y * 0.5
			if bottom > 1.8 or top < 0.0:
				_failures.append("%s 竖直区间 [%.2f..%.2f] 与玩家身位无交" % [shape.name, bottom, top])
	print("DECLARED collision_shape_count=%d  LIVE=%d  policy=%s" % [declared, live.size(), policy])
	if declared != live.size():
		_failures.append("metadata collision_shape_count=%d 与实测 %d 不一致" % [declared, live.size()])
	if live.size() < 2:
		_failures.append("L 形分段碰撞至少需要 2 段，实测 %d" % live.size())

	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state

	# —— ② 凹口竖直射线（起点 y=5.0，在盒顶 3.565 之上）——
	var notch_x := [-6.5, -4.0, -1.5, 1.0, 3.5, 4.8]
	var notch_z := [-1.6, -0.5, 0.5, 2.0, 3.0, 3.5]
	var notch_empty := 0
	var old_hits_in_notch := 0
	for x in notch_x:
		for z in notch_z:
			if _ray(space, Vector3(x, 5.0, z), Vector3(x, -1.0, z)).is_empty():
				notch_empty += 1
			else:
				_failures.append("凹口 (%.1f, %.1f) 仍有阻挡（空阻挡未修）" % [x, z])
			if abs(x) <= OLD_SIZE.x * 0.5 and abs(z) <= OLD_SIZE.z * 0.5:
				old_hits_in_notch += 1

	# —— ③ 两臂内部竖直射线 ——
	var arm_points: Array[Vector3] = []
	for x in [-6.5, -3.0, 0.0, 3.0, 6.5]:
		arm_points.append(Vector3(x, 0.0, -2.7))
	for x in [-6.5, -3.0, 0.0, 3.0, 6.5]:
		arm_points.append(Vector3(x, 0.0, -2.0))
	for z in [-1.5, -0.5, 0.5, 2.0, 3.4]:
		arm_points.append(Vector3(6.0, 0.0, z))
	arm_points.append(Vector3(5.5, 0.0, -0.5))
	arm_points.append(Vector3(7.0, 0.0, -3.4))
	var arm_hit := 0
	for point in arm_points:
		if not _ray(space, Vector3(point.x, 5.0, point.z), Vector3(point.x, -1.0, point.z)).is_empty():
			arm_hit += 1
		else:
			_failures.append("臂内 (%.1f, %.1f) 没有阻挡（实体可穿模）" % [point.x, point.z])

	print("NOTCH empty=%d/%d   ARM hit=%d/%d   旧整块 AABB 在相同凹口点上的命中数=%d（本次修掉的空阻挡点）"
		% [notch_empty, notch_x.size() * notch_z.size(), arm_hit, arm_points.size(), old_hits_in_notch])

	# —— ④ 内侧面位置：从凹口朝臂里打，看命中点落在哪 ——
	var z_hit := _ray(space, Vector3(3.0, 1.0, 3.5), Vector3(3.0, 1.0, -3.0))
	var x_hit := _ray(space, Vector3(-6.0, 1.0, 0.0), Vector3(7.0, 1.0, 0.0))
	var z_stop := float(z_hit.get("position", Vector3.ZERO).z) if not z_hit.is_empty() else INF
	var x_stop := float(x_hit.get("position", Vector3.ZERO).x) if not x_hit.is_empty() else INF
	print("INNER_FACE 后臂内侧面 z 实测=%.3f（期望 -1.875）   侧臂内侧面 x 实测=%.3f（期望 5.200）"
		% [z_stop, x_stop])
	if z_hit.is_empty() or absf(z_stop - (-1.875)) > 0.01:
		_failures.append("后臂内侧面位置不符：z=%s（期望 -1.875）" % str(z_stop))
	if x_hit.is_empty() or absf(x_stop - 5.2) > 0.01:
		_failures.append("侧臂内侧面位置不符：x=%s（期望 5.200）" % str(x_stop))

	# 未走到内侧面即命中 ⇒ 凹口里有东西
	var early := _ray(space, Vector3(3.0, 1.0, 3.5), Vector3(3.0, 1.0, -1.0))
	if not early.is_empty():
		_failures.append("凹口里 z=-1.0 之前就有阻挡，命中点 %s" % str(early.get("position")))

	if _failures.is_empty():
		print("DB_WORKBENCH_L_COLLISION_OK notch=%d arms=%d shapes=%d"
			% [notch_x.size() * notch_z.size(), arm_points.size(), live.size()])
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL " + item)
		print("DB_WORKBENCH_L_COLLISION_FAIL failures=%d" % _failures.size())
		get_tree().quit(1)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	return space.intersect_ray(query)
