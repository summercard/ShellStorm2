extends Node
## 门洞阻挡定位：找出到底是哪件家具、哪个包围盒挡住了门轴线。
##
## 业主侧的现象：`probe_expedition03_playable` 报
## `exit -> fireplace_room_inj2 BLOCKED hit=CollisionBody`。
## 本工具把两个房间的**家具世界 AABB** 与**门位轴线**全部打印出来，
## 直接看谁越界 —— 不靠猜。
##
## 只读。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED := 77003244
const TARGETS := ["exit", "fireplace_room_inj2", "n03", "cr05_n03_reward_01"]


func _ready() -> void:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _f in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _f in 3:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not (room.room_id in TARGETS):
			continue
		_dump(room)
	await _ray_scan(tower)
	get_tree().quit(0)


## 对**每个**房间的每条边做与 `probe_expedition03_playable` 相同的射线判定，
## 命中时报告"打到的是哪件家具"——这是唯一能定位踩线家具的办法。
func _ray_scan(tower: Node) -> void:
	var space := (tower as Node3D).get_world_3d().direct_space_state
	# **必须先把门扇本身的碰撞层置 0**，与 `probe_expedition03_playable` 的做法一致。
	# 否则射线打到的是 `Door_North_P1` 这类门扇，而不是真正挡路的家具 ——
	# 第一版漏了这步，所有 25 条门全报 BLOCKED，完全没有信息量。
	var door_bodies: Array[Node] = []
	for value in tower.get("_rooms") as Array:
		var r := value as DungeonRoom3D
		if r == null:
			continue
		for child in r.find_children("*", "Node", true, false):
			if child is RoomDoor3D:
				for body in (child as RoomDoor3D).find_children("*", "CollisionObject3D", true, false):
					var co := body as CollisionObject3D
					if co != null and co.collision_layer != 0:
						door_bodies.append(co)
	for co in door_bodies:
		(co as CollisionObject3D).collision_layer = 0
	var mask := 0xFFFFFFFF
	var player: Variant = tower.get("player")
	if player != null:
		mask = int((player as Node3D).collision_mask)
	print("=== 射线扫描（mask=%d）===" % mask)
	var rooms: Dictionary = {}
	for value in tower.get("_rooms") as Array:
		var r := value as DungeonRoom3D
		if r != null:
			rooms[r.room_id] = r
	for room_key in rooms.keys():
		var room := rooms[room_key] as DungeonRoom3D
		var room_pos := room.global_position
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var target := str(port.get("target_room_id", ""))
			if target.is_empty() or not rooms.has(target):
				continue
			var local: Array = port.get("position_m", [0.0, 0.0])
			var outward: Array = port.get("outward", [0.0, 0.0])
			var gate := room_pos + Vector3(float(local[0]), 0.9, float(local[1]))
			var normal := Vector3(float(outward[0]), 0.0, float(outward[1]))
			var query := PhysicsRayQueryParameters3D.create(
				gate - normal * 1.2, gate + normal * 1.2)
			query.collision_mask = mask
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var collider := hit.get("collider") as Node
			var owner_name := _furniture_owner(collider)
			print("  BLOCKED %-22s -> %-22s  collider=%-16s owner=%s  hit_local=(%.2f,%.2f,%.2f)"
				% [str(room_key), target,
					str(collider.name) if collider != null else "?",
					owner_name,
					(hit["position"] as Vector3).x - room_pos.x,
					(hit["position"] as Vector3).y,
					(hit["position"] as Vector3).z - room_pos.z])


## 沿祖先链找 `Furn_` 前缀，确认这个碰撞体是不是家具的。
func _furniture_owner(node: Node) -> String:
	var current := node
	var depth := 0
	while current != null and depth < 8:
		if str(current.name).begins_with("Furn_"):
			return str(current.name)
		current = current.get_parent()
		depth += 1
	return "(非家具)"


func _dump(room: DungeonRoom3D) -> void:
	var dim: Vector2 = room.call("get_dimensions")
	var origin := room.global_position
	print("=== %s  %dx%d  origin=(%.1f,%.1f) ===" % [
		room.room_id, int(dim.x), int(dim.y), origin.x, origin.z])
	for port_value in room.get("connection_ports") as Array:
		var p := port_value as Dictionary
		print("  PORT %-6s lane=%6.2f  target=%s"
			% [str(p.get("side", "")), float(p.get("lane_m", 0.0)),
				str(p.get("target_room_id", ""))])
	# 家具挂在 `AuthoredLayoutArtRoot/ArtComponents/` 下，**不是房间的直接子节点**，
	# 必须递归找（`find_children(..., true, ...)`）。
	for value in room.find_children("Furn_*", "Node3D", true, false):
		var node := value as Node3D
		# 合成世界 AABB：这件的网格 × 它的缩放
		var box := AABB()
		var first := true
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			continue
		# 换算成房间局部坐标（房间不旋转）
		var rel_pos := box.position - origin
		print("  %-26s local xz=[%6.2f..%6.2f]x[%6.2f..%6.2f]  y=[%.2f..%.2f]"
			% [str(node.name), rel_pos.x, rel_pos.x + box.size.x,
				rel_pos.z, rel_pos.z + box.size.z,
				box.position.y, box.position.y + box.size.y])
