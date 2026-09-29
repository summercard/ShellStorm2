extends Node
## 探针：远征01 每房「真砖格集合」与「中央顶灯 / 墙面开关落位」的一致性实测。
## 不移动玩家（避免触发归属切换与战斗），只把外壳与 detail 建好后读数据。
##
## 判据（复刻运行时口径）：
##   · `_authored_tile_cells` = 本局真实存在的地砖格心；
##   · `_inside_authored_footprint(p)` = p 是否落在某个真砖格上（房内）；
##   · 中央顶灯落位 = local (0, 0)；开关落位 = `_light_switch.position`。
## 两者若不在任何真砖格上 ⇒ 灯吊在房外/凹口、开关悬空不可达。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_probe'
##   "<godot-console>" --headless --path "<project>" --scene res://_scratch/probe_expedition_light_placement.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var rooms := _collect_rooms(tower)
	print("EXPEDITION_LIGHT_PLACEMENT rooms=%d seed=%d" % [rooms.size(), RUN_SEED])
	print("%-12s %-6s %-8s %-9s %-9s %-24s %s" % [
		"room", "tiles", "中心在房内", "灯在房内", "开关在房内", "开关落点(local) 距最近砖心", "房型",
	])
	for room in rooms:
		await _probe_room(room)
	print("EXPEDITION_LIGHT_PLACEMENT_DONE")
	get_tree().quit(0)


func _probe_room(room: DungeonRoom3D) -> void:
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle()
	var cells: Array = room.get("_authored_tile_cells") as Array
	var center_ok := bool(room.call("_inside_authored_footprint", Vector3.ZERO))
	var light_local := Vector3.ZERO
	var light_ok := center_ok
	var switch := room.get("_light_switch") as RoomLightSwitch3D
	var switch_local := Vector3.ZERO
	var switch_ok := "无开关"
	var switch_note := "-"
	if switch != null:
		switch_local = switch.position
		switch_ok = str(bool(room.call("_inside_authored_footprint", switch_local)))
		var best := INF
		var best_cell := Vector3.ZERO
		for value in cells:
			var cell := value as Vector3
			var d := Vector2(switch_local.x - cell.x, switch_local.z - cell.z).length()
			if d < best:
				best = d
				best_cell = cell
		switch_note = "%.2fm" % best if best < INF else "无砖"
		if best < INF:
			switch_note += " → (%.1f,%.1f)" % [best_cell.x, best_cell.z]
	print("%-12s %-6d %-8s %-9s %-9s %-24s %s" % [
		room.room_id, cells.size(), str(center_ok), str(light_ok), switch_ok,
		"(%+.2f,%+.2f) %s" % [switch_local.x, switch_local.z, switch_note],
		room.get_meta("static_layout_scene_path", ""),
	])


func _collect_rooms(tower: TowerDescent3D) -> Array[DungeonRoom3D]:
	var rooms: Array[DungeonRoom3D] = []
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms.append(room)
	return rooms


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
