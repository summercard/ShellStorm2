extends Node3D
## 端到端实测：远征02 房间顶盖能否把镜头竖直压下来。
##
## 复刻 `TowerDescent3D._find_stair_slab_camera_clearance_height()` 的射线算法，
## 在**真实房间场景**里跑，验证三件事：
##   ① 向上射线能命中 4.0m 顶盖
##   ② 命中的 collider 带 `camera_ceiling_occluder`（写在 CollisionBody 上，射线读得到）
##   ③ 算出的「允许相机高度」落在 4.0m 顶盖底面之下 —— 即相机真的会被压进室内
##
## 运行：godot --headless --path <项目> res://scripts/verify_expedition02_ceiling_camera.tscn

const ROOM_SCENE := (
	"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/"
	+ "expedition_02/f00_room_02_static_layout.tscn"
)
# 与 TowerDescent3D 常量逐值一致（改一边必须改另一边，这里刻意写死成对照表）。
const CAMERA_HEIGHT_M := 10.262659
const PROBE_START_HEIGHT_M := 1.31
const SLAB_CLEARANCE_M := 0.28
const SLAB_MIN_HEIGHT_M := 1.25
const WALL_MASK := 1

var _fails: Array[String] = []


func _fail(message: String) -> void:
	_fails.append(message)
	push_error("[CEIL-PROBE] %s" % message)


func _ready() -> void:
	await _run()
	if _fails.is_empty():
		print("EXPEDITION02_CEILING_CAMERA_VERIFY_OK")
	else:
		print("EXPEDITION02_CEILING_CAMERA_VERIFY_FAIL count=%d" % _fails.size())
		for message in _fails:
			print("   - %s" % message)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run() -> void:
	var packed: PackedScene = load(ROOM_SCENE)
	if packed == null:
		_fail("房间场景加载失败：%s" % ROOM_SCENE)
		return
	var room := packed.instantiate()
	add_child(room)
	# 等两帧：实例化 + 物理体注册。远征房间是静态装配，无脚本副作用。
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 找房间里的第一块顶盖（按节点名）
	var ceiling: Node3D = null
	for node in room.find_children("*", "Node3D", true, false):
		if str(node.name).begins_with("CEILING_"):
			ceiling = node as Node3D
			break
	if ceiling == null:
		_fail("房间里找不到任何 CEILING_* 顶盖实例")
		room.queue_free()
		return
	print("顶盖实例：%s  world_pos=%s" % [ceiling.name, str(ceiling.global_position)])
	if absf(ceiling.global_position.y - 4.0) > 0.001:
		_fail("顶盖底面 y=%.4f，应为 4.0" % ceiling.global_position.y)

	var body := ceiling.get_node_or_null("CollisionBody") as CollisionObject3D
	if body == null:
		_fail("顶盖实例没有 CollisionBody")
		room.queue_free()
		return
	if not bool(body.get_meta("camera_ceiling_occluder", false)):
		_fail("CollisionBody 上没有 camera_ceiling_occluder 标记 —— 相机会停在顶盖之上")
	if body.collision_layer != 1:
		_fail("CollisionBody.collision_layer=%d，应为 1" % body.collision_layer)

	# ---- 复刻算法：玩家站在走面上，向上打射线 ----
	# 走面 = floor_base 顶面 0.26 + 地砖 0.04 = 0.30（房间局部），玩家原点在脚底。
	const WALK_PLANE_Y := 0.30
	var probe_x := ceiling.global_position.x
	var probe_z := ceiling.global_position.z
	var probe_start := Vector3(probe_x, WALK_PLANE_Y + PROBE_START_HEIGHT_M, probe_z)
	var probe_end := Vector3(probe_x, WALK_PLANE_Y + CAMERA_HEIGHT_M, probe_z)

	# Node3D 才有 get_world_3d()；且项目把「从 Variant 推断类型」当错误，须显式标注。
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(probe_start, probe_end, WALL_MASK)
	query.collide_with_areas = false
	query.hit_back_faces = true
	query.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		_fail("向上射线打空了 —— 顶盖碰撞盒没挡住射线（也就不可能压镜头）")
		room.queue_free()
		return

	var collider := hit.get("collider") as Node
	var hit_position: Vector3 = hit.get("position", probe_start)
	print("射线命中：y=%.4f  collider=%s" % [
		hit_position.y, str(collider.name) if collider != null else "<null>"])

	var reads_meta := false
	if collider != null:
		reads_meta = (
			bool(collider.get_meta("camera_stair_slab", false))
			or bool(collider.get_meta("camera_ceiling_occluder", false))
		)
	if not reads_meta:
		_fail("射线命中的 collider 读不到摄像机标记 —— TowerDescent3D 不会夹镜")

	# ---- 算允许高度与相机最终高度 ----
	var allowed := clampf(
		hit_position.y - WALK_PLANE_Y - SLAB_CLEARANCE_M,
		SLAB_MIN_HEIGHT_M,
		CAMERA_HEIGHT_M
	)
	var drop := maxf(0.0, CAMERA_HEIGHT_M - allowed)
	print("允许高度=%.4f m  下压量=%.4f m" % [allowed, drop])

	# 相机最终 height = allowed（推导见 TowerDescent3D._apply_indoor_camera_pose）
	var ceiling_bottom := ceiling.global_position.y
	if allowed >= ceiling_bottom:
		_fail(
			"算出的允许高度 %.4f 不低于顶盖底面 %.4f —— 相机仍在顶盖之上，会被挡住"
			% [allowed, ceiling_bottom]
		)
	else:
		print("相机可压至 %.4f m，顶盖底面 %.4f m ⇒ 相机在室内（余量 %.4f m）"
			% [allowed, ceiling_bottom, ceiling_bottom - allowed])

	# ---- 对照：未封顶的房间必须不触发（挑高前厅不应被压）----
	var hall := load(
		"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/"
		+ "expedition_02/f00_room_01_static_layout.tscn"
	) as PackedScene
	if hall != null:
		var hall_node := hall.instantiate()
		add_child(hall_node)
		await get_tree().physics_frame
		var hall_ceilings := 0
		for node in hall_node.find_children("*", "Node3D", true, false):
			if str(node.name).begins_with("CEILING_"):
				hall_ceilings += 1
		if hall_ceilings != 0:
			_fail("挑高前厅有 %d 块顶盖 —— 通高空间不该封顶" % hall_ceilings)
		else:
			print("对照 OK：挑高前厅 0 块顶盖（11.9m 通高不被压）")
		hall_node.queue_free()

	# ---- 对照：阳台安全屋也不封顶（业主 2026-10-12 要求）----
	var balcony := load(
		"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/"
		+ "expedition_02/f00_start_static_layout.tscn"
	) as PackedScene
	if balcony != null:
		var balcony_node := balcony.instantiate()
		add_child(balcony_node)
		await get_tree().physics_frame
		var balcony_ceilings := 0
		for node in balcony_node.find_children("*", "Node3D", true, false):
			if str(node.name).begins_with("CEILING_"):
				balcony_ceilings += 1
		if balcony_ceilings != 0:
			_fail("阳台安全屋有 %d 块顶盖 —— 业主明确要求阳台不封顶" % balcony_ceilings)
		else:
			print("对照 OK：阳台安全屋 0 块顶盖")
		balcony_node.queue_free()

	# ---- ③ 墙件：镜头后墙标记 + 水平射线能读到 ----
	await _check_walls(room)
	room.queue_free()


## 墙件检查：与 `_find_lower_camera_wall_distance()` 同口径 —— 水平射线、高度 1.09m。
## 缺标记时相机在玩家贴墙时会退到墙外，而顶盖把镜头压到 2.62m 之后这一点尤其明显。
func _check_walls(room: Node) -> void:
	var wall: Node3D = null
	for node in room.find_children("*", "Node3D", true, false):
		var nm := str(node.name)
		if nm.begins_with("WALL_") and not nm.contains("FLOOR"):
			wall = node as Node3D
			break
	if wall == null:
		_fail("房间里找不到任何 WALL_* 墙实例")
		return
	var body := wall.get_node_or_null("CollisionBody") as CollisionObject3D
	if body == null:
		_fail("墙实例 %s 没有 CollisionBody" % wall.name)
		return
	if not bool(body.get_meta("camera_lower_wall", false)):
		_fail("墙 %s 的 CollisionBody 缺 camera_lower_wall —— 玩家贴墙时相机退到墙外" % wall.name)
		return
	print("墙件标记 OK：%s 带 camera_lower_wall" % wall.name)

	# 水平射线：从墙内侧朝墙打，应命中且读得到标记
	var probe_y := 0.30 + 1.09  # 走面 + CAMERA_LOWER_WALL_PROBE_HEIGHT_M
	var center := wall.global_position
	var from := Vector3(center.x, probe_y, center.z + 1.2)
	var to := Vector3(center.x, probe_y, center.z - 1.2)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, WALL_MASK)
	query.collide_with_areas = false
	query.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		print("墙水平射线未命中（该墙为竖直走向，本探针只做标记检查）")
		return
	var collider := hit.get("collider") as Node
	if collider != null and bool(collider.get_meta("camera_lower_wall", false)):
		print("墙水平射线 OK：命中 %s 且读得到 camera_lower_wall" % collider.name)
	else:
		_fail("墙水平射线命中的 collider 读不到 camera_lower_wall")
