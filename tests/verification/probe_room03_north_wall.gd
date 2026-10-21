extends Node

## 一次性探针：room_03 的**北墙**（局部 -Z）上，哪一段是真的空的。
##
## 背景（业主 2026-10-21）：「03号房间的那个门，帮我放到另一侧去，我把南面的墙封起来了。」
## 门从南墙（局部 +Z）搬到北墙（局部 -Z）后，从房心直视过去射线在 12m 处撞上
## `work_cluster_a3` —— 北墙一带摆着军械库的家具。所以要沿墙扫一遍，挑一段
## **从房心看得见、且宽度够 2.2m 门洞** 的 x 区间。
##
## 做法：沿北墙内表面从 x=-14 走到 +14（步长 0.5），以房心人眼位朝该点打射线，
## 记录首个命中物与距离；再列出「离北墙 3m 内」的所有可视件及其 x 覆盖范围。
##
## 用法：
##   SS2_SEED=1122239949 godot --headless --path . res://tests/verification/probe_room03_north_wall.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const TARGET_ROOM := "room_03"
const WAIT_LIMIT_S := 45.0
## 扫描范围（房间局部 x）。墙内空宽 38.27m，留 1m 边距。
const SCAN_HALF_SPAN := 14.0
const SCAN_STEP := 0.5
## 从房心眼位看过去，命中距离距墙小于这个值就算「通畅」。
const CLEAR_TOLERANCE_M := 1.5
## 列家具时只看离北墙这么近的。
const NEAR_WALL_M := 3.0
const EYE_Y := 1.6
const WALL_INNER_HALF_Z := 19.135002

var _tower: TowerDescent3D = null
var _room: Node3D = null


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
	print("=== room_03 北墙空档扫描  seed=%s ===" % (seed_env if not seed_env.is_empty() else "<随机器>"))
	_room = _find_room_node(tower, TARGET_ROOM) as Node3D
	if _room == null:
		print("**找不到 room_03**")
		print("NORTH_WALL_SCAN_END")
		get_tree().quit(0)
		return

	var center := _room.global_position
	var wall_z := center.z - WALL_INNER_HALF_Z
	print("[房间] 中心=(%.2f, %.2f, %.2f)  北墙内表面 z=%.3f" % [center.x, center.y, center.z, wall_z])

	_list_near_wall(center, wall_z)
	_scan(center, wall_z)

	print("")
	print("NORTH_WALL_SCAN_END")
	get_tree().quit(0)


func _list_near_wall(center: Vector3, wall_z: float) -> void:
	print("")
	print("── 离北墙 %.1fm 内的可视件（挡不挡视线看它们的深度）──" % NEAR_WALL_M)
	var rows: Array = []
	for node in _room.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		var mesh := vi as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var box: AABB = vi.global_transform * mesh.mesh.get_aabb()
		# 只看北侧：包围盒的近墙面 z 与墙的距离
		var far_edge := box.position.z + box.size.z  # 朝房间内的一侧（z 更大）
		var depth := far_edge - wall_z
		if depth < -0.2 or depth > NEAR_WALL_M:
			continue
		rows.append({
			"name": str(vi.name),
			"x0": box.position.x,
			"x1": box.position.x + box.size.x,
			"depth": depth,
			"top": box.position.y + box.size.y,
		})
	rows.sort_custom(func(a, b): return float(a["depth"]) < float(b["depth"]))
	for row in rows:
		var r := row as Dictionary
		print("  %-28s x=[%+6.2f, %+6.2f]  离墙 %5.2fm  顶高 %5.2fm" % [
			_tidy(str(r["name"])),
			float(r["x0"]) - center.x, float(r["x1"]) - center.x,
			float(r["depth"]), float(r["top"]),
		])
	if rows.is_empty():
		print("  <3m 内没有可视件>")


func _scan(center: Vector3, wall_z: float) -> void:
	print("")
	print("── 沿北墙扫描：房心眼位朝墙上每 0.5m 打一条射线 ──")
	print("   x     首个命中                          命中距离   距墙剩余   判定")
	var clear_runs: Array = []
	var run_start := 0.0
	var run_open := false
	var x := -SCAN_HALF_SPAN
	while x <= SCAN_HALF_SPAN + 0.001:
		var target := Vector3(center.x + x, 1.25, wall_z)
		var eye := Vector3(center.x, EYE_Y, center.z)
		var to_target := target - eye
		var wall_dist := Vector2(to_target.x, to_target.z).length()
		var hit := _ray(eye, target)
		var hit_dist := float(hit.get("dist", wall_dist))
		var remain := wall_dist - hit_dist
		var ok := remain <= CLEAR_TOLERANCE_M
		var who := str(hit.get("name", "<无>"))
		print("  %+6.2f  %-32s %7.2f   %7.2f   %s" % [
			x, _tidy(who), hit_dist, remain, "通畅" if ok else "被挡",
		])
		if ok and not run_open:
			run_open = true
			run_start = x
		elif not ok and run_open:
			run_open = false
			clear_runs.append([run_start, x - SCAN_STEP])
		x += SCAN_STEP
	if run_open:
		clear_runs.append([run_start, SCAN_HALF_SPAN])

	print("")
	print("── 可用的连续空档（宽度 ≥ 2.2m 才能放门）──")
	var usable := 0
	for pair in clear_runs:
		var span: Array = pair
		var width := float(span[1]) - float(span[0]) + SCAN_STEP
		var verdict := "✔ 可放" if width >= 2.2 else "✘ 太窄"
		if width >= 2.2:
			usable += 1
		print("  x ∈ [%+.1f, %+.1f]  宽 %.1fm  %s  建议 lane=%+.1f" % [
			float(span[0]), float(span[1]), width, verdict,
			(float(span[0]) + float(span[1])) * 0.5,
		])
	if usable == 0:
		print("  <没有 ≥2.2m 的空档：北墙被家具占满，需要同时挪家具或换墙>")
	else:
		print("  结论：北墙有 %d 段可用" % usable)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_viewport().world_3d
	if world == null:
		return {}
	var space := world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.get("collider") as Node
	return {
		"name": str(collider.get_path()) if collider != null else "<无>",
		"dist": from.distance_to(hit.get("position", from)),
	}


func _tidy(path: String) -> String:
	var parts := path.split("/")
	if parts.size() <= 1:
		return path
	return "%s/%s" % [parts[parts.size() - 2], parts[parts.size() - 1]]


func _find_room_node(root: Node, room_id: String) -> Node:
	for node in root.find_children("*", "Node3D", true, false):
		if str(node.name) == room_id:
			return node
	return null
