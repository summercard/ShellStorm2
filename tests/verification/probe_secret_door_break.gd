extends Node

## 一次性探针（业主 2026-10-21）：
##   「打门后，有木板破碎的动画，但是木板没有消失，也不能点击进入支线。」
##
## 只回答一件事：**玩家打的那扇门，是不是运行时配置好的那扇。**
##
## 背景：2026-10-19 把暗门做成 `secret_door_root_top3d.tscn` 放进房间 TSCN 后，
## 场景里可能同时存在两份：
##   ① 房间 TSCN 自带的那扇（美术齐全、木板可见，但**没人给它 configure**）；
##   ② `SecretBranch3D` 生成的/接管的那扇（site_id / 电量 / 落点 / 信号都齐）。
## 若玩家打的是 ①：`_boards` 为 null ⇒ 缩放动画与 `visible=false` 全落空（木板不消失）；
## `_has_teleport` 为 false ⇒ `can_teleport()` 恒假（按 E 没反应）。
## 而 `_spawn_board_debris()` 不依赖这两者，所以**碎块照样飞** —— 三个现象一次对上。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_secret_door_break.tscn
##   SS2_SEED=1122239949 ...   # 指定种子

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 45.0

var _tower: TowerDescent3D = null
var _branch: Node3D = null


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
		var branch := tower.get_node_or_null("SecretBranches")
		var rooms := tower.get("_rooms") as Array
		if branch != null and rooms != null and rooms.size() >= 4:
			_branch = branch as Node3D
			break
	# 房间壳体是 `_ensure_structural_shells_resident()` 建的；探针再显式催一次，
	# 确保「房间 TSCN 里那扇门」在本次观测里真的出现过（否则测的是空场景）。
	await get_tree().process_frame
	_force_build_rooms()
	for _i in range(4):
		await get_tree().process_frame

	print("")
	print("=== 破板核对  seed=%s 等待=%.1fs ===" % [
		seed_env if not seed_env.is_empty() else "<随机器>", waited,
	])
	if _branch == null:
		print("**SecretBranches 不存在**")
		print("SECRET_DOOR_BREAK_PROBE_END")
		get_tree().quit(0)
		return

	_dump_registered()
	_dump_all_doors()
	await _break_and_report()
	print("")
	print("SECRET_DOOR_BREAK_PROBE_END")
	get_tree().quit(0)


## 把主图每一间房的壳体都催建出来 —— 房间 TSCN 里那扇门只有在壳体建成后才存在。
func _force_build_rooms() -> void:
	var rooms := _tower.get("_rooms") as Array
	if rooms == null:
		return
	var total := 0
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room.call("ensure_shell_built")
		total += 1
	print("[催建] 主图房间壳体 %d 间" % total)


## `SecretBranch3D._doors` 里登记的门（运行时认账的那批）。
func _dump_registered() -> void:
	var doors: Dictionary = _branch.get("_doors") as Dictionary
	print("[登记] _doors 共 %d 扇" % doors.size())
	for site_id in doors:
		var door := doors[site_id] as Node3D
		if door == null or not is_instance_valid(door):
			print("  %-6s **节点无效**" % str(site_id))
			continue
		print("  %-6s path=%s  pos=(%.2f,%.2f,%.2f)  %s" % [
			str(site_id), str(_tower.get_path_to(door)),
			door.global_position.x, door.global_position.y, door.global_position.z,
			_snap(door),
		])


## 全场景扫出来的所有 SecretDoor3D —— 包括**没被登记**的那些。
func _dump_all_doors() -> void:
	var all := _tower.find_children("*", "StaticBody3D", true, false)
	var registered: Dictionary = _branch.get("_doors") as Dictionary
	var registered_nodes: Array = []
	for site_id in registered:
		registered_nodes.append(registered[site_id])
	print("[全场景] SecretDoor3D 节点：")
	var count := 0
	for node in all:
		if not (node is SecretDoor3D):
			continue
		count += 1
		var tag := "已登记" if registered_nodes.has(node) else "**未登记**"
		print("  %-6s %s  path=%s  pos=(%.2f,%.2f,%.2f)  %s" % [
			tag, str(node.name), str(_tower.get_path_to(node)),
			(node as Node3D).global_position.x, (node as Node3D).global_position.y,
			(node as Node3D).global_position.z, _snap(node),
		])
		var kids: Array = []
		for child in node.get_children():
			kids.append("%s(%s)" % [str(child.name), child.get_class()])
		print("         子节点: %s" % ", ".join(kids))
	print("[全场景] 合计 %d 扇（登记 %d 扇，已清副本 %d 扇）" % [
		count, registered.size(), int(_branch.get("_pruned_room_copies")),
	])


## 按玩家视角打那扇「看得见的门」：从房间侧 1.5m 打一条射线，
## 首个命中是谁，就打谁 —— 这才是玩家扣扳机时真正打到的那一扇。
func _break_and_report() -> void:
	var door := _find_visible_door()
	if door == null:
		print("[破板] **找不到入口门**")
		return
	var player := _find_player()
	var site_id := str(door.get("site_id"))
	print("[破板] 目标门 %s site=%s" % [str(door.name), site_id if not site_id.is_empty() else "<空>"])

	# 玩家眼里那一侧 = 门局部 -Z
	var room_side := -door.global_transform.basis.z
	room_side.y = 0.0
	if room_side.length_squared() < 0.0001:
		room_side = Vector3.FORWARD
	room_side = room_side.normalized()
	var from := door.global_position + Vector3(0.0, 1.2, 0.0) + room_side * 1.5
	var to := door.global_position + Vector3(0.0, 1.2, 0.0)
	var hit := _ray(from, to)
	print("[破板] 房间侧射线 %.2fm → 首个命中: %s" % [1.5, str(hit)])

	door.call("set_locked", false)
	var guard := 0
	while not bool(door.call("is_broken")) and guard < 20:
		door.call("take_damage", 999)
		await get_tree().process_frame
		guard += 1
	# 等缩放 tween 走完（0.06 + 0.10 + 余量）
	for _i in range(20):
		await get_tree().process_frame
	print("[破板] 破后 %s" % _snap(door))
	print("[破板] 破后 子节点: %s" % _children_summary(door))
	if player != null:
		player.set("global_position", door.global_position + room_side * 1.2)
		await get_tree().process_frame
		await get_tree().process_frame
		print("[破板] 站位后候选=%s" % str(door.call("get_interaction_candidate", player)))


func _snap(door: Node) -> String:
	var snap: Dictionary = door.call("debug_snapshot")
	return "state=%s 木板在=%s 木板可见=%s 落点=%s 可传送=%s 提示=%s 层=%s" % [
		str(snap.get("state")), str(snap.get("has_boards")), str(snap.get("boards_visible")),
		str(snap.get("teleport_target")), str(snap.get("can_teleport")),
		("「%s」" % str(snap.get("teleport_verb"))) if str(snap.get("teleport_verb")) != "" else "<空>",
		str(snap.get("collision_layer")),
	]


func _children_summary(door: Node) -> String:
	var rows: Array = []
	for child in door.get_children():
		var vis := ""
		if child is Node3D:
			vis = " visible=%s scale=%s" % [str((child as Node3D).visible), str((child as Node3D).scale)]
		rows.append("%s%s" % [str(child.name), vis])
	return "; ".join(rows)


## 玩家会打的那扇：优先未登记但可见的木板的门？不猜 —— 用「离玩家最近且木板可见」。
func _find_visible_door() -> Node3D:
	var player := _find_player()
	var best: Node3D = null
	var best_d := INF
	for node in _tower.find_children("*", "StaticBody3D", true, false):
		var door := node as Node3D
		if door == null or not str(door.name).begins_with("SecretDoor_"):
			continue
		var snap: Dictionary = door.call("debug_snapshot")
		if not bool(snap.get("boards_visible", false)):
			continue
		var d := 0.0
		if player != null:
			d = player.global_position.distance_to(door.global_position)
		if d < best_d:
			best_d = d
			best = door
	return best


func _find_player() -> Node3D:
	var direct := _tower.get_node_or_null("Player") as Node3D
	if direct != null:
		return direct
	for node in get_tree().get_nodes_in_group("player_3d"):
		return node as Node3D
	return null


func _ray(from: Vector3, to: Vector3) -> String:
	var world: World3D = _tower.get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return "<没有命中>"
	var collider := hit.get("collider") as Node
	return "%s（%s）" % [
		str(collider.name) if collider != null else "?",
		str(_tower.get_path_to(collider)) if collider != null else "?",
	]
