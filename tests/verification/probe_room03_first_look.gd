extends Node

## 一次性探针：玩家**走进 room_03 的那一刻**，视野里到底有没有那扇暗门。
##
## 业主 2026-10-21 问：「那我进 room03 后会自动看到那个门吗」
##
## 这个问题不能靠「门在不在房间里」回答 —— 门在，但玩家相机 `fov = 43°`（`Player3D.tscn`），
## 竖向半视角只有 21.5°，水平半视角约 35°。一扇摆在侧墙上的门，进门时完全可能在视野之外。
##
## 探针按**真实游戏流程**（`test_mode = false`）加载远征 01，然后：
##   · 打印 room_03 的世界位置、尺寸、四个方向的主路门；
##   · 对每个主路门：站在门内侧 1.8m、人眼高 1.6m，朝房间中心看（= 玩家进门后的自然视线），
##     算出暗门中心相对视线的水平角与垂直角，与 fov 半角比较，判定「在不在视野里」；
##   · 另外算「站在房间中心，要转多少度才正对暗门」；
##   · 从站位打一条射线，确认视线没有被别的几何挡住。
##
## 用法：
##   SS2_SEED=1122239949 godot --headless --path . res://tests/verification/probe_room03_first_look.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const TARGET_ROOM := "room_03"
const WAIT_LIMIT_S := 45.0
const OUT_DIR := "res://outputs/room03_first_look"

## 玩家相机的实际参数（`Player3D.tscn` → `Camera3D.fov = 43.0`，16:9）。
const PLAYER_FOV_V := 43.0
const SCREEN_ASPECT := 16.0 / 9.0
## 人眼高（相对门底/地面）。玩家身高按 1.8m 量级取眼位。
const EYE_Y := 1.60
## 站到门口内侧多深（m）—— 模拟「刚跨进门」的位置。
const STAND_IN_M := 1.8
## 暗门中心相对门底的原点高度（门高 2.51m，取中段）。
const DOOR_MID_Y := 1.25

var _tower: TowerDescent3D = null
var _room: Node3D = null
var _secret_door: Node3D = null
var _cam: Camera3D = null


func _ready() -> void:
	var seed_env := OS.get_environment("SS2_SEED")
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	if not seed_env.is_empty():
		tower.run_seed_override = int(seed_env)
	_tower = tower
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			await get_tree().process_frame
			await get_tree().process_frame
			break

	print("")
	print("=== 进 room_03 第一眼：暗门在不在视野里  seed=%s 等待=%.1fs ===" % [
		seed_env if not seed_env.is_empty() else "<随机器>", waited,
	])

	_room = _find_room_node(tower, TARGET_ROOM) as Node3D
	if _room == null:
		print("**找不到 %s 节点，后面无法核对**" % TARGET_ROOM)
		print("ROOM03_FIRST_LOOK_END")
		get_tree().quit(0)
		return

	_secret_door = _find_child_named(_room, "SecretDoor_S1") as Node3D
	if _secret_door == null:
		# 门可能被搬到了房间子树外（`_adopt_authored_door` 会 reparent），退到全场景找。
		_secret_door = _find_secret_door_by_site(tower, "S1")

	var dims := Vector2.ZERO
	if _room.has_method("get_dimensions"):
		dims = _room.call("get_dimensions") as Vector2
	print("[房间] %s  world=(%.2f, %.2f, %.2f)  尺寸=%.1f x %.1f  rotation.y=%.1f°" % [
		TARGET_ROOM,
		_room.global_position.x, _room.global_position.y, _room.global_position.z,
		dims.x, dims.y, rad_to_deg(_room.global_rotation.y),
	])

	if _secret_door == null:
		print("**找不到暗门 S1**")
		print("ROOM03_FIRST_LOOK_END")
		get_tree().quit(0)
		return

	var door_box := _visual_world_box(_secret_door)
	var door_center := Vector3(
		door_box.get_center().x,
		_secret_door.global_position.y + DOOR_MID_Y,
		door_box.get_center().z
	)
	print("[暗门] S1  world=(%.2f, %.2f, %.2f)  可视包围盒 尺寸=(%.2f, %.2f, %.2f)  中心=(%.2f, %.2f, %.2f)" % [
		_secret_door.global_position.x, _secret_door.global_position.y, _secret_door.global_position.z,
		door_box.size.x, door_box.size.y, door_box.size.z,
		door_center.x, door_center.y, door_center.z,
	])
	print("[暗门] 距房心 %.2fm  所在方位=%s" % [
		_horizontal_distance(door_center, _room.global_position),
		_side_of_room(door_center),
	])

	var half_h := rad_to_deg(atan(tan(deg_to_rad(PLAYER_FOV_V * 0.5)) * SCREEN_ASPECT))
	print("[视野] 玩家相机 fov=%.0f° ⇒ 半垂直=%.1f°  半水平=%.1f°（%.2f:1）" % [
		PLAYER_FOV_V, PLAYER_FOV_V * 0.5, half_h, SCREEN_ASPECT,
	])

	print("")
	_look_from_doors(door_center, half_h)

	print("")
	_look_from_room_center(door_center)

	print("")
	print("ROOM03_FIRST_LOOK_END")
	await _shoot_all(door_center)
	get_tree().quit(0)


## 逐个主路门：站门内侧朝房心看，门在不在视野内。
func _look_from_doors(door_center: Vector3, half_h: float) -> void:
	print("── 从各个主路门「刚跨进门」朝房心看 ──")
	var doors_value: Variant = _room.get("_door_nodes")
	if not (doors_value is Dictionary):
		print("  <拿不到 _door_nodes>")
		return
	var door_map := doors_value as Dictionary
	if door_map.is_empty():
		print("  <房间没有主路门节点>")
		return

	var room_center := _room.global_position
	var sorted_keys: Array = door_map.keys()
	sorted_keys.sort()

	for key in sorted_keys:
		var door := door_map[key] as Node3D
		if door == null or not is_instance_valid(door):
			continue
		var door_pos := door.global_position
		var flat := Vector3(room_center.x - door_pos.x, 0.0, room_center.z - door_pos.z)
		if flat.length_squared() < 0.01:
			continue
		var inward := flat.normalized()
		var eye := door_pos + inward * STAND_IN_M
		eye.y = door_pos.y + EYE_Y
		# 进门后的自然视线：朝房心（水平）。
		var dir := Vector3(room_center.x - eye.x, 0.0, room_center.z - eye.z).normalized()

		var report := _angle_report(eye, dir, door_center)
		var side_name := str(key)
		var verdict := "✔ 在视野内" if bool(report["in_view"]) else "✘ 在视野外"
		print("  [%s] 站位=(%.1f, %.1f, %.1f)  暗门 水平偏角=%+.1f° 垂直偏角=%+.1f°  距离=%.2fm  → %s" % [
			side_name, eye.x, eye.y, eye.z,
			float(report["yaw"]), float(report["pitch"]), float(report["dist"]), verdict,
		])
		var yaw := float(report["yaw"])
		if absf(yaw) > half_h:
			print("         需要转头 %.1f° 才进画面（半水平视角只有 %.1f°）" % [absf(yaw) - half_h, half_h])
		# 两条视线分别看：沿主路朝房心（进门自然视线）、转头正对门（主动观察）。
		var center_point := Vector3(room_center.x, eye.y, room_center.z)
		print("         朝房心首个命中：%s" % _ray_hit_name(eye, center_point))
		print("         转头看门首个命中：%s" % _ray_hit_name(eye, door_center))


## 站在房间正中环视，门在什么方位。
func _look_from_room_center(door_center: Vector3) -> void:
	print("── 站在房间中心环视 ──")
	var eye := _room.global_position + Vector3(0.0, EYE_Y, 0.0)
	var to_door := Vector3(door_center.x - eye.x, 0.0, door_center.z - eye.z)
	var dist := to_door.length()
	if dist < 0.01:
		print("  <门就在脚下>")
		return
	print("  门在 %.2fm 外，方位 %s（相对于房间局部 +X 轴 %+.1f°）" % [
		dist, _side_of_room(door_center), _bearing_deg(to_door),
	])
	print("  站房心朝门看，首个命中：%s" % _ray_hit_name(eye, door_center))
	# 玩家若正对房间「长边」进门，通常需要转头多少度。
	print("  进门后若沿主路继续前进（朝对侧门），门一般在侧方 %.0f° 左右，需要主动转头才看到" % _side_turn_estimate())


func _side_turn_estimate() -> float:
	# 房间是矩形，主路两个门通常在对边 ⇒ 视线沿主轴，侧墙上的门接近 90°。
	return 90.0


## 把世界点投到「站位 eye + 视线 dir」的相机局部坐标里，算水平/垂直偏角。
func _angle_report(eye: Vector3, dir: Vector3, target: Vector3) -> Dictionary:
	var to_target := target - eye
	var dist := to_target.length()
	var cam_basis := Basis.looking_at(dir, Vector3.UP).inverse()
	var local := cam_basis * to_target
	var forward_depth := -local.z
	if forward_depth <= 0.001:
		return {"in_view": false, "yaw": 180.0, "pitch": 0.0, "dist": dist}
	var yaw := rad_to_deg(atan2(local.x, forward_depth))
	var pitch := rad_to_deg(atan2(local.y, forward_depth))
	var half_v := PLAYER_FOV_V * 0.5
	var half_h := rad_to_deg(atan(tan(deg_to_rad(half_v)) * SCREEN_ASPECT))
	return {
		"in_view": absf(yaw) <= half_h and absf(pitch) <= half_v,
		"yaw": yaw,
		"pitch": pitch,
		"dist": dist,
	}


## 从眼到目标打射线，返回首个命中物的路径（空 = 通畅；含「就是门」标注）。
func _ray_hit_name(from: Vector3, to: Vector3) -> String:
	var world := get_viewport().world_3d
	if world == null:
		return "<无 world>"
	var space := world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return "无（通畅）"
	var collider := hit.get("collider") as Node
	if collider == null:
		return "<无 collider>"
	var path := str(collider.get_path())
	var tag := "  ← 就是门" if _is_door_part(collider) else ""
	return "%s  距眼 %.2fm%s" % [path, from.distance_to(hit.get("position", from)), tag]


func _is_door_part(node: Node) -> bool:
	var probe: Node = node
	var depth := 0
	while probe != null and depth < 6:
		if probe == _secret_door:
			return true
		if str(probe.name).begins_with("SecretDoor"):
			return true
		probe = probe.get_parent()
		depth += 1
	return false


func _visual_world_box(root: Node) -> AABB:
	var box := AABB()
	var started := false
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		var mesh := vi as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var part: AABB = (vi.global_transform * mesh.mesh.get_aabb())
		if not started:
			box = part
			started = true
		else:
			box = box.merge(part)
	return box


func _side_of_room(point: Vector3) -> String:
	# 用房间局部坐标判断在哪个墙侧。
	var local := _room.global_transform.affine_inverse() * point
	var dims := _room.call("get_dimensions") as Vector2
	var dx := local.x
	var dz := local.z
	if absf(dx) / maxf(dims.x * 0.5, 0.01) > absf(dz) / maxf(dims.y * 0.5, 0.01):
		return "房间局部 +X 侧" if dx > 0.0 else "房间局部 -X 侧"
	return "房间局部 +Z 侧" if dz > 0.0 else "房间局部 -Z 侧"


func _bearing_deg(flat_dir: Vector3) -> float:
	return rad_to_deg(atan2(flat_dir.z, flat_dir.x))


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _find_room_node(root: Node, room_id: String) -> Node:
	for node in root.find_children("*", "Node3D", true, false):
		if str(node.name) == room_id:
			return node
	return null


func _find_child_named(root: Node, target: String) -> Node:
	for node in root.find_children("*", "", true, false):
		if str(node.name) == target:
			return node
	return null


func _find_secret_door_by_site(root: Node, site_id: String) -> Node3D:
	for node in root.find_children("*", "", true, false):
		if not node.has_method("can_teleport"):
			continue
		if str(node.get("site_id")) == site_id:
			return node as Node3D
	return null


# ── 拍照（只在带窗口时执行；headless 是 dummy 渲染驱动，`get_image()` 拿不到画面）──

func _shoot_all(door_center: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		print("（headless：跳过拍照，数值已给出）")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_hide_ui(_tower)
	_release_cameras(_tower)
	print("")
	print("── 拍照（fov=%.0f°，与玩家相机一致，不打补光）──" % PLAYER_FOV_V)

	var room_center := _room.global_position
	var doors_value: Variant = _room.get("_door_nodes")
	if doors_value is Dictionary:
		var door_map := doors_value as Dictionary
		for key in ["east", "west"]:
			if not door_map.has(key):
				continue
			var door := door_map[key] as Node3D
			if door == null or not is_instance_valid(door):
				continue
			var door_pos := door.global_position
			var inward := Vector3(room_center.x - door_pos.x, 0.0, room_center.z - door_pos.z).normalized()
			var eye := door_pos + inward * STAND_IN_M
			eye.y = door_pos.y + EYE_Y
			await _shoot(eye, Vector3(room_center.x, eye.y, room_center.z), "01_%s_door_in" % str(key))

	var mid_eye := room_center + Vector3(0.0, EYE_Y, 0.0)
	await _shoot(mid_eye, door_center, "02_room_center_turn")

	var flat := Vector3(door_center.x - mid_eye.x, 0.0, door_center.z - mid_eye.z)
	if flat.length_squared() > 0.01:
		var near_eye := door_center - flat.normalized() * 5.0
		near_eye.y = room_center.y + EYE_Y
		await _shoot(near_eye, door_center, "03_near_door")


func _shoot(eye: Vector3, target: Vector3, label: String) -> void:
	var cam := _ensure_cam()
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("  [拍照失败] %s" % label)
		return
	var path := "%s/%s.png" % [OUT_DIR, label]
	img.save_png(path)
	print("  [拍照] %s" % path)


func _ensure_cam() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.fov = PLAYER_FOV_V
		_cam.near = 0.05
		_cam.far = 600.0
		add_child(_cam)
	return _cam


func _hide_ui(root: Node) -> void:
	for node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in root.find_children("*", "Control", true, false):
		(node as Control).visible = false


func _release_cameras(root: Node) -> void:
	for node in root.find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
