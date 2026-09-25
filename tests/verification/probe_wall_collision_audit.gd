extends Node
## 只读探针：审计远征01 授权布局里「每一件墙自己带不带碰撞」。
##
## 为什么需要它：「battle 通用墙能否直接换成 tower A 套实墙」这个问题的关键不是外观，
## 而是**挡人靠谁**。两套 prefab 的碰撞归属完全不同：
##   · battle 通用墙 / 门墙  →  metadata/collision_owner = "self"（包内自带 StaticBody3D）
##   · tower A 套实墙 / 门墙 →  metadata/visual_only = true（包内 0 碰撞，靠脚本生成代理）
## 而授权布局路径（_build_authored_layout_shell）**不生成任何结构碰撞代理**
## （TowerWallCollision_* / _add_tower_wall_collision 都只属塔楼路径）。
## 所以只要量出「现在这批墙各自带几个实体碰撞体」，就能判定直接换的后果。
##
## 运行：export APPDATA=I:/ss2_iso/wall_audit
##       $GODOT --headless --path . --scene res://tests/verification/probe_wall_collision_audit.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const PHYSICAL_WALL_LAYER := 1

var _by_asset: Dictionary = {}
var _rooms_seen := 0
var _wall_total := 0
var _camera_only_proxies := 0
var _room_physical_total := 0
var _room_wall_attributed := 0
var _other_physical: Dictionary = {}


func _ready() -> void:
	await _phase_audit()
	print("\nDONE rooms=%d walls=%d camera_only_proxies=%d" % [
		_rooms_seen, _wall_total, _camera_only_proxies,
	])
	get_tree().quit(0)


func _phase_audit() -> void:
	print("========== 远征01 授权布局：墙件自带碰撞审计 ==========")
	var scene := load(LEVEL_SCENE) as PackedScene
	if scene == null:
		print("  !! 关卡场景加载失败")
		return
	var instance := scene.instantiate()
	add_child(instance)
	for _i in range(10):
		await get_tree().process_frame
	var hud := instance.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false
	var rooms := get_tree().get_nodes_in_group("dungeon_room_3d")
	# 只有授权布局壳体的房才有 5m 通用墙；逐个强制建壳。
	for value in rooms:
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_shell:
			room.set_stream_state(2)
	await get_tree().process_frame
	await get_tree().process_frame

	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or not room.authored_layout_shell:
			continue
		_rooms_seen += 1
		_audit_room(room)

	print("")
	print("  —— 按 prefab asset_id 汇总 ——")
	print("  %-42s %5s %8s %9s %10s  %s" % [
		"asset_id", "件数", "实体碰撞", "cameraonly", "collision_owner", "forward_axis",
	])
	var keys := _by_asset.keys()
	keys.sort()
	var total_physical := 0
	for key in keys:
		var row := _by_asset[key] as Dictionary
		var count := int(row.get("count", 0))
		var physical := int(row.get("physical", 0))
		var camera_only := int(row.get("camera_only", 0))
		total_physical += physical
		print("  %-42s %5d %8d %9d %10s  %s" % [
			str(key), count, physical, camera_only,
			str(row.get("owner", "?")), str(row.get("forward", "?")),
		])
	print("")
	print("  实体碰撞体合计 = %d（这是远征01 现在**唯一的墙体挡人来源**）" % total_physical)
	print("")
	print("  —— 交叉核对：全房实体碰撞体总数 vs 墙件归属 ——")
	print("  全房 layer=1 StaticBody3D 合计 = %d" % _room_physical_total)
	print("  其中归属墙件 prefab 的        = %d" % _room_wall_attributed)
	print("  差额（房间层/门/其它）         = %d" % (_room_physical_total - _room_wall_attributed))
	print("")
	print("  —— 非墙件来源的实体碰撞体是谁（按 名称 < 父节点）——")
	var other_keys := _other_physical.keys()
	other_keys.sort()
	for key in other_keys:
		print("    ×%-4d %s" % [int(_other_physical[key]), str(key)])


func _audit_room(room: DungeonRoom3D) -> void:
	var wall_roots: Array[Node] = []
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		# 墙体 prefab 根节点都带 metadata/forward_axis（实墙/门墙/塔楼实墙/塔楼门墙四件都带）。
		if node.has_meta("forward_axis") and node.has_meta("asset_id"):
			wall_roots.append(node)
	for wall in wall_roots:
		_wall_total += 1
		var asset_id := str(wall.get_meta("asset_id"))
		var owner := str(wall.get_meta("collision_owner", "?"))
		var forward := str(wall.get_meta("forward_axis", "?"))
		var physical := 0
		var camera_only := 0
		var sub_stack: Array[Node] = [wall]
		while not sub_stack.is_empty():
			var node: Node = sub_stack.pop_back()
			for child in node.get_children():
				sub_stack.append(child)
			var body := node as StaticBody3D
			if body == null:
				continue
			if body.collision_layer == PHYSICAL_WALL_LAYER:
				physical += 1
			else:
				camera_only += 1
		_room_wall_attributed += physical
		var row := _by_asset.get(asset_id, {}) as Dictionary
		row["count"] = int(row.get("count", 0)) + 1
		row["physical"] = int(row.get("physical", 0)) + physical
		row["camera_only"] = int(row.get("camera_only", 0)) + camera_only
		row["owner"] = owner
		row["forward"] = forward
		_by_asset[asset_id] = row
		if physical == 0:
			print("  ⚠ 无实体碰撞：%s @ %s/%s（part=%s）" % [
				asset_id, room.authored_layout_room_id, str(wall.name),
				str(wall.get_meta("authored_multi_level_part", "-")),
			])
	# 顺带点数 camera-only 门墙代理（它是**镜头专用**，不挡人）。
	var proxy_stack: Array[Node] = [room]
	while not proxy_stack.is_empty():
		var node: Node = proxy_stack.pop_back()
		for child in node.get_children():
			proxy_stack.append(child)
		if node.has_meta("camera_only_door_wall"):
			_camera_only_proxies += 1
	# 全房实体碰撞体总数（不分来源）：用来证明墙件归属那条确实是全部。
	var physical_stack: Array[Node] = [room]
	while not physical_stack.is_empty():
		var node: Node = physical_stack.pop_back()
		for child in node.get_children():
			physical_stack.append(child)
		var body := node as StaticBody3D
		if body == null or body.collision_layer != PHYSICAL_WALL_LAYER:
			continue
		_room_physical_total += 1
		if not _has_wall_ancestor(body):
			var label := "%s < %s" % [str(body.name), str(body.get_parent().name)]
			_other_physical[label] = int(_other_physical.get(label, 0)) + 1


## 往上找有没有「墙件 prefab 根」（带 forward_axis meta）。
func _has_wall_ancestor(node: Node) -> bool:
	var cursor := node
	while cursor != null:
		if cursor.has_meta("forward_axis"):
			return true
		cursor = cursor.get_parent()
	return false
