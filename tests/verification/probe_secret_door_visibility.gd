extends Node

## 一次性探针：回答「暗门木板在游戏里到底看不看得见」。
##
## 业主实测两次「打到第四个房间找不到支线入口」—— 而 S1 就在主路第 3 间
## `room_03` 的南墙上。所以问题不是「没刷」，是「看不见」。本探针量三件事：
##
##   1. 木板 `Boards` 的**真实网格 AABB**（资产缺 mesh 时这里会是 0 尺寸）；
##   2. 木板相对**房间墙面内表面**朝房间里凸出多少（负数 = 埋在墙里）；
##   3. 从房间内侧往门中心打一条射线，**第一个命中的是谁**（墙先被命中 = 被挡）。
##
## 用法：bash scripts/run_verification_suite.sh scene probe_secret_door_visibility
## 输出：SECRET_DOOR_VISIBILITY_PROBE_OK（脚本只出数，不判红绿）。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const SEED := 77001199
## 射线起点：从墙面往房间内退这么多米、人眼高度。
const RAY_INSET_M := 4.0
const RAY_EYE_Y_M := 1.4

var _rooms: Dictionary = {}


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		print("SECRET_DOOR_VISIBILITY_PROBE_MISS 远征场景加载失败")
		get_tree().quit(0)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		print("SECRET_DOOR_VISIBILITY_PROBE_MISS 远征场景实例化失败")
		get_tree().quit(0)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_collect_rooms(tower)
	var branch := tower.get_node_or_null("SecretBranches")
	if branch == null:
		print("SECRET_DOOR_VISIBILITY_PROBE_MISS 没有 SecretBranches 节点")
		get_tree().quit(0)
		return

	var found := 0
	var snapshot := branch.call("debug_snapshot") as Dictionary
	var room_index: Variant = branch.get("_room_nodes")
	var index_size := 0
	if room_index is Dictionary:
		index_size = (room_index as Dictionary).size()
	print("")
	print("=== 房间索引：%d 个（room_03=%s, room_06=%s）===" % [
		index_size,
		"有" if room_index is Dictionary and (room_index as Dictionary).has("room_03") else "无",
		"有" if room_index is Dictionary and (room_index as Dictionary).has("room_06") else "无",
	])
	var sites: Array = snapshot.get("sites", []) as Array
	if not sites.is_empty():
		print("")
		print("=== 位点装配参数（是否被墙埋 / 门前被什么挡）===")
		for value in sites:
			var site := value as Dictionary
			print("  %-3s room=%-9s 外推=%.2fm  门前遮挡=%s" % [
				str(site.get("site_id", "")), str(site.get("room_id", "")),
				float(site.get("wall_push_m", 0.0)),
				str(site.get("blocker", "")) if site.has("blocker") else "无",
			])
	for site_id in ["S1", "S2", "S3", "S4"]:
		var door := branch.get_node_or_null("SecretDoor_%s" % site_id) as Node3D
		if door == null:
			print("")
			print("=== %s 未刷出（本次种子没有这个位点）===" % site_id)
			continue
		found += 1
		_report(site_id, door)

	print("")
	print("SECRET_DOOR_VISIBILITY_PROBE_OK seed=%d 检查板体=%d" % [SEED, found])
	get_tree().quit(0)


func _report(site_id: String, door: Node3D) -> void:
	var pos := door.global_position
	print("")
	print("=== %s world=(%.2f, %.2f, %.2f) yaw=%.1f° ===" % [
		site_id, pos.x, pos.y, pos.z, rad_to_deg(door.global_rotation.y),
	])

	# —— 1. 木板层网格 AABB ——
	var boards := door.get_node_or_null("Boards") as Node3D
	if boards == null:
		print("  木板节点：不存在 ✘（资产没实例化出来，玩家看到的是空气或兜底板）")
		if door.get_node_or_null("Panel") != null:
			print("  但存在程序化兜底板 Panel")
	else:
		var aabb := _global_aabb(boards)
		var meshes := _count_meshes(boards)
		print("  木板节点：存在，网格数=%d，AABB size=(%.3f, %.3f, %.3f)" % [
			meshes, aabb.size.x, aabb.size.y, aabb.size.z,
		])
		if aabb.size.length() < 0.01:
			print("    ✘ AABB 为 0 —— mesh 没加载（资产空壳），玩家什么也看不到")

	# —— 2. 找它贴着的房间，算墙面内表面 ——
	var room_row := _room_at(pos)
	if room_row.is_empty():
		print("  所在房间：找不到（位点不在任何房间的包围盒面上）")
		return
	var room := room_row.get("node") as Node3D
	var dims: Vector2 = room.call("get_dimensions")
	var center := room.global_position
	print("  所在房间：%s  center=(%.2f, %.2f)  尺寸=%.1fx%.1f" % [
		str(room_row.get("room_id", "")), center.x, center.z, dims.x, dims.y,
	])

	# ⚠ 不能拿 `pos - center` 当法线：位点带 lane 偏移，那样算出来的"法线"
	# 会被沿墙分量污染（S1 的 lane=2.5 让法线歪了约 7°），墙面与起点全错。
	# 法线只能由**贴的是哪条边**决定：看哪个轴的偏差更接近半尺寸。
	var half := dims * 0.5
	var dx := pos.x - center.x
	var dz := pos.z - center.z
	var normal: Vector3
	if absf(absf(dz) - half.y) <= absf(absf(dx) - half.x):
		normal = Vector3(0.0, 0.0, signf(dz))
	else:
		normal = Vector3(signf(dx), 0.0, 0.0)
	# 墙面内表面 = 位点所在的房间边界（墙件原点就坐在 ±dimensions/2 上，
	# 墙厚向房间外侧展开，见 DungeonRoom3D:227）。
	var wall_inner := pos
	print("  墙面位置投影：%.3f（normal=%s）" % [wall_inner.dot(normal), str(normal)])

	if boards != null:
		var aabb2 := _global_aabb(boards)
		# 沿法线的投影区间（用 AABB 的 8 个角点投影，转置房间也能算对）。
		var lo := INF
		var hi := -INF
		for index in range(8):
			var corner := aabb2.get_endpoint(index)
			var proj := corner.dot(normal)
			lo = minf(lo, proj)
			hi = maxf(hi, proj)
		var wall_proj := wall_inner.dot(normal)
		print("  木板沿法线区间：%.3f ~ %.3f（墙面 %.3f）" % [lo, hi, wall_proj])
		print("  朝房间里凸出：%.3f m（> 0 才露在墙面外）" % (wall_proj - lo))
		if wall_proj - lo <= 0.01:
			print("    ✘ 木板整体在墙体内部或墙外 —— 玩家在房间里看不到它")

	# —— 3. 视线射线：从房间内往门中心 ——
	var origin := wall_inner - normal * RAY_INSET_M
	origin.y = RAY_EYE_Y_M
	var target := pos + Vector3(0.0, 1.3, 0.0)
	var hit := _ray(origin, target)
	if hit.is_empty():
		print("  视线射线：未命中任何碰撞（可能没有碰撞体）")
	else:
		var collider := hit.get("collider") as Node
		var name_text := ""
		var node: Node = collider
		for _i in range(6):
			if node == null:
				break
			name_text = "%s/%s" % [str(node.name), name_text]
			if node == door or node.is_ancestor_of(door):
				break
			node = node.get_parent()
		print("  视线射线：首个命中 %s 距离=%.2fm 命中点=(%.2f, %.2f, %.2f)" % [
			name_text, float(hit.get("dist", 0.0)),
			(hit.get("position", Vector3.ZERO) as Vector3).x,
			(hit.get("position", Vector3.ZERO) as Vector3).y,
			(hit.get("position", Vector3.ZERO) as Vector3).z,
		])
		var is_door := collider == door or (collider != null and door.is_ancestor_of(collider))
		if not is_door:
			print("    ✘ 视线先撞到别的东西 —— 木板被墙体/装饰挡住")
			# 把挡路件的**可视** AABB 也打出来：碰撞代理盒可能比美术面更厚，
			# 只有可视面才知道玩家眼睛看到的是墙还是木板。
			var piece := collider
			if piece != null and piece.get_parent() is Node3D:
				piece = piece.get_parent()
			var piece_box := _global_aabb(piece as Node3D)
			if piece_box.size.length() > 0.0:
				var piece_lo := INF
				var piece_hi := -INF
				for index in range(8):
					var proj := piece_box.get_endpoint(index).dot(normal)
					piece_lo = minf(piece_lo, proj)
					piece_hi = maxf(piece_hi, proj)
				print("    挡路件可视区间：%.3f ~ %.3f（木板外沿 %.3f）" % [
					piece_lo, piece_hi, pos.dot(normal),
				])
				if piece_hi - pos.dot(normal) > 0.02 or piece_lo - pos.dot(normal) > 0.02:
					print("    ✘ 挡路件比木板更靠房间内 —— 木板埋进墙体，玩家看到的是墙")

	# —— 4. 门腔是否被实心墙填住 ——
	# 设计 §4.1/§4.2 要求木板后面是 1.70m 深门腔，光从板缝里透出来。
	# 但房间墙体生成不认 `secret_site`（只有 `connection_ports` 才开门洞），
	# 所以这面墙很可能是**实心**的：门腔被墙填死，板缝后面是墙面，一条光都透不出。
	var back_from := pos + Vector3(0.0, 1.3, 0.0)
	var back_hit := _ray(back_from, back_from + normal * 1.8)
	if back_hit.is_empty():
		print("  墙后 1.8m：空腔")
	else:
		print("  墙后 1.8m：命中 %s 距离=%.2fm（实心墙 —— 本方案不依赖门腔透光）" % [
			_path_text(back_hit.get("collider") as Node), float(back_hit.get("dist", 0.0)),
		])


## 从碰撞体往上取 6 层父节点名，便于人眼认出"这是哪面墙"。
func _path_text(node: Node) -> String:
	var text := ""
	var cursor := node
	for _i in range(6):
		if cursor == null:
			break
		text = "%s/%s" % [str(cursor.name), text]
		cursor = cursor.get_parent()
	return text


func _global_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box := mesh_node.global_transform * mesh_node.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _count_meshes(root: Node3D) -> int:
	var total := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null:
			total += 1
	return total


func _room_at(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for room_id in _rooms:
		var room := _rooms[room_id] as Node3D
		if room == null or not is_instance_valid(room):
			continue
		var dims: Vector2 = room.call("get_dimensions")
		var center := room.global_position
		var half := dims * 0.5
		var local_x := absf(pos.x - center.x)
		var local_z := absf(pos.z - center.z)
		# 门装配时会被推到墙面之外（离开边界 0~0.6m），所以不能再用「必须贴边」
		# 判断归属 —— 只要求点落在包围盒内，取「离边最近」的那间。
		if local_x > half.x + 0.05 or local_z > half.y + 0.05:
			continue
		var dist := (half.x - local_x) + (half.y - local_z)
		if dist < best_dist:
			best_dist = dist
			best = {"room_id": str(room_id), "node": room}
	return best


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space.intersect_ray(query)
	if result.is_empty():
		return {}
	var out := result.duplicate()
	out["dist"] = from.distance_to(result.get("position", from))
	return out


func _collect_rooms(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child.get("room_id") != null:
			var room_id := str(child.get("room_id"))
			if not room_id.is_empty() and not room_id.begins_with("secret_"):
				_rooms[room_id] = child
		_collect_rooms(child)
