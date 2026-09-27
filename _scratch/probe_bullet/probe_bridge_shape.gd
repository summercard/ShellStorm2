extends Node3D
## 诊断（只读）：把 room_01 的三维形状量清楚 ——
##  ① 逐 5m 格心竖向打射线，报「命中面相对房间基准的高度 + 碰撞体名」；
##  ② 从房心在枪口高度水平打 16 个方向，报首个阻挡物的距离/高度/名字。
## 只打印，不改产品代码。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOM_ID := "room_01"
const CHEST_Y := 0.458

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(20)
	var room := tower._room_by_id.get(ROOM_ID) as DungeonRoom3D
	if room == null:
		print("BSP_ABORT no_room")
		get_tree().quit(0)
		return
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	await _settle(4)
	var dim := room.get_dimensions()
	var cols := maxi(1, int(round(dim.x / 5.0)))
	var rows := maxi(1, int(round(dim.y / 5.0)))
	print("BSP_ROOM %s dim=(%.0f,%.0f) room_gp=(%.1f,%.2f,%.1f)" % [
		room.room_id, dim.x, dim.y, room.global_position.x, room.global_position.y, room.global_position.z,
	])
	for r in rows:
		var line := ""
		for c in cols:
			var lx := -dim.x * 0.5 + 2.5 + float(c) * 5.0
			var lz := -dim.y * 0.5 + 2.5 + float(r) * 5.0
			line += _vcell(room, Vector3(lx, 3.0, lz))
		print("BSP_VROW %s r=%02d %s" % [room.room_id, r, line])
	# 水平 16 方向
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		print("BSP_H %s deg=%3d %s" % [room.room_id, i * 22, _hray(room, dir)])
	# 关键 XZ 处的「竖向剖面」：从上往下依次列出各层命中面高度与名称
	for sample in [
		Vector2(0.0, 4.8), Vector2(0.0, 5.0), Vector2(0.0, 5.2), Vector2(11.7, 5.0),
		Vector2(0.0, 7.5), Vector2(0.0, 12.5), Vector2(0.0, -5.0), Vector2(15.2, 4.8),
	]:
		print("BSP_STACK local=(%.1f,%.1f)%s" % [sample.x, sample.y, _vstack(room, sample.x, sample.y)])
	# 墙顶高扫描：从房心向 +Z / -Z / +X 方向，逐档抬高射线看哪一档不再被挡
	for hy in [0.46, 0.70, 1.00, 1.40, 1.80, 2.20, 2.60, 3.00]:
		print("BSP_TOPZ %s y=%.2f +Z:%s -Z:%s +X:%s" % [
			room.room_id, hy,
			_hray_at(room, Vector3(0.0, hy, 0.0), Vector3(0.0, 0.0, 1.0), 20.0),
			_hray_at(room, Vector3(0.0, hy, 0.0), Vector3(0.0, 0.0, -1.0), 20.0),
			_hray_at(room, Vector3(0.0, hy, 0.0), Vector3(1.0, 0.0, 0.0), 20.0),
		])
	print("BSP_DONE")
	get_tree().quit(0)


## 竖向：返回命中面相对房间基准的高度（整数，限制在 [-15,5]）+ 首字表示碰撞体类型
func _vcell(room: DungeonRoom3D, local: Vector3) -> String:
	var from := room.to_global(local)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -60.0, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "  .  "
	var rel := float(hit.get("position").y) - room.global_position.y
	# 命中名称首字母：W=墙 F=地砖 P=坑件
	var node := hit.get("collider") as Node
	var tag := "?"
	if node != null:
		var n := String(node.name)
		if n.begins_with("Wall") or n.contains("Wall"):
			tag = "W"
		elif n.contains("Floor") or n.contains("floor"):
			tag = "F"
		elif n.contains("Pit") or n.contains("pit"):
			tag = "P"
		else:
			tag = n.substr(0, 1)
	return "%4d%s" % [int(round(rel)), tag]


func _hray(room: DungeonRoom3D, dir: Vector3) -> String:
	var from := room.to_global(Vector3(0.0, CHEST_Y, 0.0))
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "CLEAR(40m)"
	var node := hit.get("collider") as Node3D
	var hit_pos := hit.get("position") as Vector3
	var local_hit := room.to_local(hit_pos)
	var name_text := str(node.name) if node != null else "?"
	var origin_y := node.global_position.y - room.global_position.y if node != null else 0.0
	return "%6.2fm rel_y=%+.2f local=(%.1f,%.1f) node_y0=%+.1f %s" % [
		from.distance_to(hit_pos), hit_pos.y - room.global_position.y,
		local_hit.x, local_hit.z, origin_y, name_text,
	]


## 指定局部起点与方向、指定长度的一条水平射线：返回首个阻挡物（距离/名称/命中局部坐标）。
func _hray_at(room: DungeonRoom3D, local_from: Vector3, dir: Vector3, length: float) -> String:
	var from := room.to_global(local_from)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * length)
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "clear"
	var hit_pos := hit.get("position") as Vector3
	var node := hit.get("collider") as Node
	var lh := room.to_local(hit_pos)
	return "%.2fm@(%.1f,%.1f):%s" % [
		from.distance_to(hit_pos), lh.x, lh.z, str(node.name) if node != null else "?",
	]


## 从 +6m 往下逐层剥：列出该 XZ 上每个命中面的相对高度与名称。
func _vstack(room: DungeonRoom3D, lx: float, lz: float) -> String:
	var out := ""
	var y := 6.0
	for _step in 6:
		var from := room.to_global(Vector3(lx, y, lz))
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -30.0, 0.0))
		query.collision_mask = 1
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var hit_pos := hit.get("position") as Vector3
		var rel := hit_pos.y - room.global_position.y
		var node := hit.get("collider") as Node
		out += " %+.2f:%s" % [rel, str(node.name) if node != null else "?"]
		y = rel - 0.05
		if y < -20.0:
			break
	return out


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
