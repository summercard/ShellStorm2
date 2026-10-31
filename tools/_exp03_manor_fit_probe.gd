extends Node
## 实测：远征03 的 18 间真房间里，哪些能用 5m 方形公馆件铺满。
##
## 判据：① 尺寸是否 5 的整数倍；② 轮廓是否矩形（非矩形用方形件铺不满，
## `_art_layer_coverage()` 会把轮廓外的格子也算作需覆盖，于是永远判不满 → 静默回退）。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const SEEDS := [77003244, 100990]
const GRID := 5.0


func _ready() -> void:
	var seen := {}
	for seed_value in SEEDS:
		var tower := await _spawn(seed_value)
		for value in tower.get("_rooms") as Array:
			var room := value as DungeonRoom3D
			if room == null or not room.procedural_shell:
				continue
			if _is_corridor(room):
				continue
			var dim: Vector2 = room.call("get_dimensions")
			var key := "%.0fx%.0f" % [dim.x, dim.y]
			if seen.has(key):
				continue
			var descriptor := CONTRACT.describe(room)
			var rect := _is_rect(room, dim)
			var floor_text := _floor_text(room)
			var cells := int(round(dim.x / GRID)) * int(round(dim.y / GRID))
			var fit5 := fmod(dim.x, GRID) < 0.01 and fmod(dim.y, GRID) < 0.01
			seen[key] = true
			print("FIT %-10s room=%-14s type=%-12s cells=%-4d 5整除=%-5s 地板=%-11s 矩形=%-5s"
				% [key, room.room_id, str(room.room_type), cells,
					"yes" if fit5 else "NO", floor_text, "yes" if rect else "NO"])
		tower.queue_free()
		await get_tree().process_frame
	print("FIT_TOTAL 不同尺寸 %d 种" % seen.size())
	get_tree().quit(0)


## 轮廓是不是轴对齐矩形：所有网格的水平投影 AABB 拼起来后，
## 投影面积 ≈ 房间面积（非矩形会明显小于外接矩形）。
## 量程序化地板 `Floor` 在房间局部空间里的水平尺寸。
##
## `_spawn_prefab` 返回的是 **Node3D**（prefab 根），mesh 在其子树里 ——
## 直接 `as MeshInstance3D` 会转换失败、量到「缺」。必须取子树合并。
func _floor_bounds(room: DungeonRoom3D, dim: Vector2) -> AABB:
	var node := room.get_node_or_null("Floor") as Node3D
	if node == null:
		return AABB()
	var inverse := room.global_transform.affine_inverse()
	var box := AABB()
	var has := false
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var aabb: AABB = inverse * mi.global_transform * mi.get_aabb()
		box = box.merge(aabb) if has else aabb
		has = true
	return box if has else AABB()


func _floor_text(room: DungeonRoom3D) -> String:
	var box := _floor_bounds(room, Vector2.ZERO)
	if box.size == Vector3.ZERO:
		return "缺"
	return "%.1fx%.1f" % [box.size.x, box.size.z]


## 轮廓是不是矩形：程序化地板是否**铺满**整个房间尺寸。
##
## 运行时程序化壳体里地板恒为一整块 `Vector3(dim.x, 0.36, dim.y)`（见 `_build_shell()`），
## 非矩形只存在于白盒壳 `rt_*_l_turn` 那类离线参考物上，运行时并不加载。
## 所以「地板尺寸 == 房间尺寸」即等价于矩形。
func _is_rect(room: DungeonRoom3D, dim: Vector2) -> bool:
	var box := _floor_bounds(room, dim)
	if box.size == Vector3.ZERO:
		return false
	return absf(box.size.x - dim.x) < 0.8 and absf(box.size.z - dim.y) < 0.8


func _is_corridor(room: DungeonRoom3D) -> bool:
	return room.room_id.begins_with("cr") or room.room_id.begins_with("conn_")


func _spawn(seed_value: int) -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", seed_value)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			# 必须先建壳体：不调这一步 `Floor` / `Wall_*` 都不存在，
			# 量地板会量到空（第一版探针因此把所有房间都误判成非矩形）。
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower
