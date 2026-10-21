extends Node

## 一次性探针（业主 2026-10-21）：
##   「装配的房间有问题。会掉落。支线的。然后08号房间的装配也有问题。」
##
## 只回答「装配」到底哪里坏了，不猜。对**每一间**已经建好的房（主路 12 间 + 支线共享壳房）
## 逐项量：
##   ① 壳：本房用的是哪份静态布局、根节点朝向、对齐量（`_static_layout_alignment_delta_deg`）；
##   ② 地：房内 1m 网格逐点向下打射线，数「打不到任何东西」的格 —— 那就是脚下一空会掉下去的洞；
##   ③ 墙：四面墙每 1m 从外向内打射线，数「打不到东西」的缺口；
##   ④ 面：地砖件数 / 静态碰撞体数 / 网格件数，与 `layout_instance_total` 对账。
##
## 用法：
##   SS2_SEED=414339956 godot --headless --path . res://tests/verification/probe_room_assembly_health.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
## 地面采样网格步长（m）。1m 足够看出「整块地板缺失」，又不会把探针拖到几分钟。
const FLOOR_STEP_M := 1.0
## 向下打射线的起点高度 / 终点深度（相对房间地面）。
const FLOOR_RAY_TOP_M := 2.2
const FLOOR_RAY_BOTTOM_M := -6.0
## 墙面采样：从墙外 0.8m 处朝墙内打，长度 1.6m；只在门洞高度区间内打。
const WALL_OUT_M := 0.8
const WALL_IN_M := 0.8
const WALL_STEP_M := 1.0
const WALL_RAY_Y_M := 1.4

var _tower: TowerDescent3D = null


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
			for _i in range(4):
				await get_tree().process_frame
			break

	print("")
	print("=== 房间装配体检  seed=%s  等待=%.1fs ===" % [
		seed_env if not seed_env.is_empty() else "<随机器>", waited,
	])

	var rooms: Array = _collect_rooms(tower)
	print("共找到 %d 个房间节点（主路 + 支线共享壳）" % rooms.size())
	var bad: Array = []
	for room in rooms:
		var report := _inspect(room as DungeonRoom3D)
		if int(report.get("floor_holes", 0)) > 0 or int(report.get("wall_gaps", 0)) > 0:
			bad.append(report)

	print("")
	print("── 汇总：地板有洞 / 墙有缺口 的房间 ──")
	if bad.is_empty():
		print("  无")
	for report in bad:
		print("  %s  地板洞 %d/%d  墙缺口 %d/%d" % [
			str(report.get("room_id", "?")),
			int(report.get("floor_holes", 0)), int(report.get("floor_total", 0)),
			int(report.get("wall_gaps", 0)), int(report.get("wall_total", 0)),
		])
	_scan_corridors(tower)
	print("")
	print("ROOM_ASSEMBLY_HEALTH_END")
	get_tree().quit(0)


## 走廊与门洞接缝也要量：房间地板完好、门外那 5 m 走廊没铺到 / 铺歪了，一样会掉下去。
func _scan_corridors(tower: TowerDescent3D) -> void:
	var corridors := tower.get_node_or_null("GeneratedCorridors")
	if corridors == null:
		print("")
		print("── 走廊：本关没有 GeneratedCorridors 节点 ──")
		return
	var space := get_viewport().world_3d.direct_space_state
	print("")
	print("── 走廊地板（1m 网格向下射线）──")
	var total := 0
	var holes_total := 0
	for body_value in corridors.get_children():
		var body := body_value as StaticBody3D
		if body == null or not str(body.name).begins_with("Corridor_"):
			continue
		if not body.visible:
			continue
		var box := AABB()
		var started := false
		for node in body.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var part: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			if not started:
				box = part
				started = true
			else:
				box = box.merge(part)
		if not started or box.size.x <= 0.1 or box.size.z <= 0.1:
			continue
		var cols := maxi(1, int(box.size.x))
		var rows := maxi(1, int(box.size.z))
		var holes := 0
		for row in range(rows):
			for col in range(cols):
				var wx := box.position.x + (float(col) + 0.5) * (box.size.x / float(cols))
				var wz := box.position.z + (float(row) + 0.5) * (box.size.z / float(rows))
				var from := Vector3(wx, box.end.y + 1.0, wz)
				var to := Vector3(wx, box.position.y - 4.0, wz)
				var query := PhysicsRayQueryParameters3D.create(from, to)
				query.collide_with_areas = false
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty():
					holes += 1
		total += cols * rows
		holes_total += holes
		if holes > 0:
			print("  %s  空 %d/%d  足迹 x=[%.1f, %.1f] z=[%.1f, %.1f]" % [
				str(body.name), holes, cols * rows,
				box.position.x, box.end.x, box.position.z, box.end.z,
			])
	print("  合计：走廊 %d 格采样，空 %d 格" % [total, holes_total])


## 收集场上所有 `DungeonRoom3D`：主路在 `_records` 里、支线房挂在 `SecretBranch_*` 下。
func _collect_rooms(tower: TowerDescent3D) -> Array:
	var result: Array = []
	for node in tower.find_children("*", "", true, false):
		if node is DungeonRoom3D and not (node as DungeonRoom3D).is_queued_for_deletion():
			result.append(node)
	return result


func _inspect(room: DungeonRoom3D) -> Dictionary:
	var room_id := room.room_id if not room.room_id.is_empty() else str(room.name)
	var dims := room.get_dimensions()
	var floor_y := room.global_position.y
	var report := {"room_id": room_id}

	print("")
	print("── %s ──" % room_id)
	print("  世界= (%.2f, %.2f, %.2f)  尺寸= %.1f x %.1f  rotation.y= %.1f°  子图=%s" % [
		room.global_position.x, room.global_position.y, room.global_position.z,
		dims.x, dims.y, rad_to_deg(room.global_rotation.y),
		"是" if not room.is_main_path else "否",
	])

	# ① 壳
	var layout_path := str(room.get_meta("static_layout_scene_path", ""))
	var root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if root == null:
		root = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	print("  壳: %s" % ("灰盒（没有静态布局）" if layout_path.is_empty() else layout_path.get_file()))
	if root != null:
		print("  壳根: %s  local=(%.2f, %.2f, %.2f)  rotation.y=%.1f°  scale=(%.3f, %.3f, %.3f)" % [
			root.name, root.position.x, root.position.y, root.position.z,
			rad_to_deg(root.rotation.y), root.scale.x, root.scale.y, root.scale.z,
		])
	print("  清单条数=%d  地砖 meta=%d  静态碰撞体=%d  网格件=%d" % [
		(room.authored_layout_instances as Array).size(),
		int(room.get_meta("authored_layout_floor_tile_count", -1)),
		room.find_children("*", "StaticBody3D", true, false).size(),
		room.find_children("*", "MeshInstance3D", true, false).size(),
	])
	# 美术内容在**房间局部系**里的包围盒：壳被平移/转错时，这里会直接露馅。
	var box := _local_visual_box(room)
	if box.size != Vector3.ZERO:
		print("  美术局部包围盒: min=(%.1f, %.1f, %.1f)  max=(%.1f, %.1f, %.1f)  尺寸=(%.1f, %.1f, %.1f)" % [
			box.position.x, box.position.y, box.position.z,
			box.end.x, box.end.y, box.end.z,
			box.size.x, box.size.y, box.size.z,
		])
	# 对齐量：本房实际用的旋转步（0 = 停在烘焙朝向）。
	var delta: Variant = room.call("_static_layout_alignment_delta_deg", root) if root != null else 0.0
	print("  对齐量=%.0f°  房间 rotY=%.0f°" % [
		float(delta) if delta != null else 0.0, rad_to_deg(room.global_rotation.y),
	])

	# ② 地
	var floor := _scan_floor(room, dims, floor_y)
	report["floor_holes"] = floor["holes"]
	report["floor_total"] = floor["total"]
	print("  地板: %d/%d 格打不到东西（%.1f%%）%s" % [
		int(floor["holes"]), int(floor["total"]),
		100.0 * float(floor["holes"]) / maxf(1.0, float(floor["total"])),
		"" if int(floor["holes"]) == 0 else "  ← 会掉下去",
	])
	if int(floor["holes"]) > 0:
		_print_map(floor)
		print("  首个空洞局部坐标: %s" % str(_first_hole_local(room, floor)))

	# ③ 墙
	var walls := _scan_walls(room, dims, floor_y)
	report["wall_gaps"] = walls["gaps"]
	report["wall_total"] = walls["total"]
	print("  墙: 缺口 %d/%d 探针%s" % [
		int(walls["gaps"]), int(walls["total"]),
		"" if int(walls["gaps"]) == 0 else "  ← %s" % str(walls["gap_sides"]),
	])
	if int(walls["gaps"]) > 0:
		_print_map(walls)

	# ④ 垂直对齐：壳根与房间根是否同高（壳被抬高/压下去 ⇒ 地板与门框错位）
	if root != null and not is_zero_approx(root.position.y):
		print("  ⚠ 壳根 Y 偏移 %.3f m（房间地面 y=%.2f）" % [root.position.y, floor_y])
	return report


## 房内 1m 网格向下打射线。返回 {total, holes, cols, rows, cells(Array[String])}。
func _scan_floor(room: DungeonRoom3D, dims: Vector2, floor_y: float) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var cols := maxi(1, int(floor(dims.x / FLOOR_STEP_M)))
	var rows := maxi(1, int(floor(dims.y / FLOOR_STEP_M)))
	var cells: Array = []
	var holes := 0
	var hole_points: Array = []
	for row in range(rows):
		var line := ""
		for col in range(cols):
			# 取格心，四周各让 0.5m，避免角落贴墙判成洞。
			var lx := -half_x + (float(col) + 0.5) * (dims.x / float(cols))
			var lz := -half_z + (float(row) + 0.5) * (dims.y / float(rows))
			var world := room.global_transform * Vector3(lx, 0.0, lz)
			var from := Vector3(world.x, floor_y + FLOOR_RAY_TOP_M, world.z)
			var to := Vector3(world.x, floor_y + FLOOR_RAY_BOTTOM_M, world.z)
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			var hit: Dictionary = space.intersect_ray(query)
			var ok := not hit.is_empty()
			if ok:
				var hit_y := float((hit.get("position", Vector3.ZERO) as Vector3).y)
				# 打到的东西若在房间地面以下 0.6m 以外，等同于「脚下没有地板」。
				ok = hit_y > floor_y - 0.6
			if ok:
				line += "."
			else:
				line += "#"
				holes += 1
				hole_points.append(Vector3(lx, 0.0, lz))
		cells.append(line)
	return {
		"total": cols * rows, "holes": holes, "cols": cols, "rows": rows,
		"cells": cells, "hole_points": hole_points,
	}


## 四面墙各打一排射线，数打不到东西的缺口。
## 图例：`.` 有东西  `#` 打空  `D` 打到的就是门扇（门洞，不算缺口）
func _scan_walls(room: DungeonRoom3D, dims: Vector2, floor_y: float) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var sides := {
		"north": {"fixed": -half_z, "span": dims.x, "axis": "x"},
		"east": {"fixed": half_x, "span": dims.y, "axis": "z"},
		"south": {"fixed": half_z, "span": dims.y * 0.0 + dims.x, "axis": "x"},
		"west": {"fixed": -half_x, "span": dims.y, "axis": "z"},
	}
	var cells: Array = []
	var gaps := 0
	var total := 0
	var gap_sides: Array = []
	for side in ["north", "east", "south", "west"]:
		var info := sides[side] as Dictionary
		var count := maxi(1, int(floor(float(info["span"]) / WALL_STEP_M)))
		var line := ""
		var side_gaps := 0
		for index in range(count):
			var t := -float(info["span"]) * 0.5 + (float(index) + 0.5) * (
				float(info["span"]) / float(count)
			)
			var local := Vector3.ZERO
			var outward := Vector3.ZERO
			match side:
				"north":
					local = Vector3(t, 0.0, float(info["fixed"]))
					outward = Vector3(0.0, 0.0, -1.0)
				"south":
					local = Vector3(t, 0.0, float(info["fixed"]))
					outward = Vector3(0.0, 0.0, 1.0)
				"east":
					local = Vector3(float(info["fixed"]), 0.0, t)
					outward = Vector3(1.0, 0.0, 0.0)
				"west":
					local = Vector3(float(info["fixed"]), 0.0, t)
					outward = Vector3(-1.0, 0.0, 0.0)
			var wall_world := room.global_transform * local
			var out_world := (room.global_transform.basis * outward).normalized()
			var from := wall_world - out_world * WALL_OUT_M
			var to := wall_world + out_world * WALL_IN_M
			from.y = floor_y + WALL_RAY_Y_M
			to.y = from.y
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			var hit: Dictionary = space.intersect_ray(query)
			total += 1
			if hit.is_empty():
				line += "#"
				gaps += 1
				side_gaps += 1
			elif _is_door_like(hit.get("collider")):
				line += "D"
			else:
				line += "."
		if side_gaps > 0:
			gap_sides.append("%s:%d" % [side, side_gaps])
		cells.append("%-6s %s" % [side, line])
	return {"total": total, "gaps": gaps, "cells": cells, "gap_sides": gap_sides}


## 全部可见网格并成**房间局部系**的一个 AABB（含壳体、道具、地砖）。
func _local_visual_box(room: DungeonRoom3D) -> AABB:
	var box := AABB()
	var started := false
	var to_local := room.global_transform.affine_inverse()
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var part := to_local * (mesh.global_transform * mesh.mesh.get_aabb())
		if not started:
			box = part
			started = true
		else:
			box = box.merge(part)
	return box


func _is_door_like(node: Variant) -> bool:
	var probe := node as Node
	var depth := 0
	while probe != null and depth < 6:
		var name := str(probe.name).to_lower()
		if "door" in name:
			return true
		probe = probe.get_parent()
		depth += 1
	return false


func _first_hole_local(room: DungeonRoom3D, floor: Dictionary) -> String:
	var points := floor.get("hole_points", []) as Array
	if points.is_empty():
		return "<无>"
	var point := points[0] as Vector3
	return "(%.1f, 0, %.1f)" % [point.x, point.z]


func _print_map(data: Dictionary) -> void:
	for line in data.get("cells", []) as Array:
		print("      %s" % str(line))
