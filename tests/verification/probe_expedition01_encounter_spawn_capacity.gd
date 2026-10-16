extends Node
## 探针：远征01 每个房间的**遭遇事件落点容量**（`DungeonRoom3D.spawn_point_for_index` 能排出多少点）。
##
## 为什么必须单独量：遭遇事件（踩点触发式遭遇 / 撤离防守）按 `index` 逐只取落点，
## 与触发盒走的是**不同的取点路径**（盒走盒内撒点，事件走房间级落点池）。
## 高水位在 `spawn_point_for_index`：落点耗尽时它返回 `Vector3.INF`，而
## `Dungeon3D._spawn_enemy_batch` 把「非有限落点」判为整批失败，
## 并顺手写 `_room_spawn_blocked[room_id] = true` —— **该房此后不再刷怪**。
##
## 因此「一波几只」不是随便写的数：**单波人数必须 ≤ 本房落点容量**，
## 否则表现不是"少刷几只"，而是「这一波直接不出、房间从此卡住」。
##
## ⚠ 与本文件旁的 `probe_expedition01_box_capacity.gd` 是两件事，别混：
##   那个量「盒内能排多少」（触发盒用），这个量「全房能排多少」（遭遇事件用）。
##
## 只看**首帧**容量：`enemy_spawn_points` 是每房缓存的，且 `index == 0` 时会清空重建，
## 所以每个波次看到的都是同一批点 —— 同一波内 index 不重复即可。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
## 逐点试到耗尽为止的硬上限，防止探针本身死循环。
## `DungeonRoom3D.SPAWN_MAX_POINTS` 是 64，超过它只会重复取最后一点，故 64 足够。
const PROBE_MAX_COUNT := 64
const ROOM_KEYS: Array[String] = [
	"room_03", "room_04", "room_06", "room_09", "room_10",
]

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("SEED=%d" % SEED_VALUE)
	print("key|dim|max_points|candidates|available|first=INF?")
	for key in ROOM_KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("%s|MISSING" % key)
			continue
		_probe_room(room)
	print("ENCOUNTER_SPAWN_CAPACITY_PROBE_DONE")
	get_tree().quit(0)


## 逐点加取，直到 `spawn_point_for_index` 不再产出新点（即已耗尽）。
## 耗尽那一次会返回 `Vector3.INF` 并由 `DungeonRoom3D` 打一条 `push_error` ——
## 那是**预期**的诊断输出，不是探针失败：它正是"这一房排不下第 N+1 只"的证据。
func _probe_room(room: DungeonRoom3D) -> void:
	room.spawn_point_for_index(0)
	var candidates := room._spawn_candidates.size()
	var available := room._spawn_available.size()
	var max_points := 0
	var first_infinite := room.spawn_point_for_index(0) == Vector3.INF
	for index in range(1, PROBE_MAX_COUNT):
		var point := room.spawn_point_for_index(index)
		if point == Vector3.INF:
			break
		max_points = index + 1
	# 世界足迹：落点池的世界坐标极值。它给出房间**在世界里的真实占地**，
	# 与 `get_dimensions()`（房间自身坐标系）可能不是一回事 —— 房间若被旋转过，
	# 两者会差 90°。触发带是按**世界轴**判定的（见 `_room_encounter_trigger_center`），
	# 所以必须按这一组数来定带子的方向与长度。
	var min_x := INF; var max_x := -INF; var min_z := INF; var max_z := -INF
	for local_point in room._spawn_candidates:
		var world_point := room.to_global(local_point)
		min_x = minf(min_x, world_point.x); max_x = maxf(max_x, world_point.x)
		min_z = minf(min_z, world_point.z); max_z = maxf(max_z, world_point.z)
	# 门在世界里的位置 + 房间朝向：判断"哪几面墙有门"以及主通行轴。
	var doors := []
	doors.append("raw=%s" % str(room.door_targets))
	for direction in room.door_targets.keys():
		var door := room.get_door_node(str(direction))
		if door == null:
			doors.append("%s(->%s)@NO_NODE" % [str(direction), str(room.door_targets[direction])])
			continue
		var offset := door.global_position - room.global_position
		doors.append("%s(->%s)@(%.1f,%.1f)" % [
			str(direction), str(room.door_targets[direction]), offset.x, offset.z
		])
	# 落点池的**局部**极值。与 `get_dimensions()` 对照，就能判断
	# 「房间局部轴」与「布局示例坐标系」是不是同一套（不是的话差 90°）。
	var lmin_x := INF; var lmax_x := -INF; var lmin_z := INF; var lmax_z := -INF
	for local_point in room._spawn_candidates:
		lmin_x = minf(lmin_x, local_point.x); lmax_x = maxf(lmax_x, local_point.x)
		lmin_z = minf(lmin_z, local_point.z); lmax_z = maxf(lmax_z, local_point.z)
	print("  %s LOCAL x=[%.1f,%.1f] z=[%.1f,%.1f] | transform_basis=%s" % [
		room.room_id, lmin_x, lmax_x, lmin_z, lmax_z,
		str(room.global_transform.basis.get_euler() * 180.0 / PI),
	])
	print("%s|dim=%s|rot_y=%.1f|world_x=[%.1f,%.1f]|world_z=[%.1f,%.1f]|points=%d|cand=%d|avail=%d|first_INF=%s|doors=%s" % [
		room.room_id, str(room.get_dimensions()), room.rotation_degrees.y,
		min_x, max_x, min_z, max_z, max_points, candidates, available,
		str(first_infinite), "; ".join(doors),
	])
