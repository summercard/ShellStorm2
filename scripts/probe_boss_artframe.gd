extends Node
## 量 Boss 房的**美术帧**：把绑定壳里的静态美术节点位置打出来，与端口帧对比。
##
## 判据来自两处独立事实：
##   ① 楼梯/高位平台在美术里的位置（共享房烘焙坐标：楼梯 x∈[-2.5,2.5]、z∈[-10,40]）；
##   ② 本局端口的 side/lane（南门在 +z、东门在 +x）。
## 两者一致 ⇒ 美术帧 == 端口帧（玩家能进门）；差 180° ⇒ 门开在实墙上。

const LEVELS := [
	{"id": "expedition_01", "scene": "res://scenes/ExpeditionLevel01_3D.tscn"},
	{"id": "99", "scene": "res://scenes/ExpeditionLevel99_3D.tscn"},
]
const RUN_SEED := 77001199
const WANT_KEYWORDS: Array[String] = ["stair", "exit_portal", "exit_leaf", "deck_barrier", "bridge_deck"]


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	for value in LEVELS:
		var level := value as Dictionary
		await _dump(str(level.get("id", "")), str(level.get("scene", "")))
	print("BOSS_ARTFRAME_DONE")
	get_tree().quit(0)


func _dump(level_id: String, scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		print("ART %s <加载失败>" % level_id)
		return
	var tower := packed.instantiate() as Dungeon3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var room := tower._room_by_id.get("boss") as DungeonRoom3D
	print("=== ART %s ===" % level_id)
	if room == null:
		print("  ART %s boss=<缺>" % level_id)
		tower.queue_free()
		await get_tree().process_frame
		return
	print("  ART %s 房间 pos=%s yaw=%.1f° dims=(%.1f,%.1f)" % [
		level_id, _v(room.global_position), rad_to_deg(room.global_rotation.y),
		room.get_dimensions().x, room.get_dimensions().y,
	])
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art == null:
		art = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	print("  ART %s art_root=%s 局部rot_y=%.1f° 全局rot_y=%.1f° scale=%s" % [
		level_id, "有" if art != null else "无",
		rad_to_deg(art.rotation.y) if art != null else 0.0,
		rad_to_deg(art.global_rotation.y) if art != null else 0.0,
		str(art.scale) if art != null else "-",
	])
	if art == null:
		tower.queue_free()
		await get_tree().process_frame
		return
	# 逐 child 打印：名字 + 相对房间的局部位置（把 art 自身变换算进去）
	var matches: Array[Node3D] = []
	_collect(art, matches)
	print("  ART %s 子节点总数(含组件根)=%d" % [level_id, matches.size()])
	var shown := 0
	for node in matches:
		var low := str(node.name).to_lower()
		var hit := false
		for keyword in WANT_KEYWORDS:
			if low.contains(keyword):
				hit = true
				break
		if not hit:
			continue
		var room_local := room.to_local(node.global_position)
		print("     %-46s 房间局部=(%8.2f,%7.2f,%8.2f)" % [str(node.name), room_local.x, room_local.y, room_local.z])
		shown += 1
		if shown >= 24:
			break
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _collect(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D:
			out.append(child as Node3D)
		_collect(child, out)


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
