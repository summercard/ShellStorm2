extends Node
## 诊断：boss 房 doors / RoomDoor3D 落位 / 端口 / 房间尺寸 全面取证。

const EXP := "res://scenes/ExpeditionLevel01_3D.tscn"
const RUN_SEED := 77001199


func _ready() -> void:
	var tower: Node = (load(EXP) as PackedScene).instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", RUN_SEED)
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition")
	var room: Node = block.get_node_or_null("boss") if block != null else null
	if room == null:
		print("BOSS_ROOM_MISSING")
		get_tree().quit()
		return
	room.call("ensure_shell_built")
	print("room.name = ", room.name)
	print("room.transform = ", (room as Node3D).transform)
	print("room.global    = ", (room as Node3D).global_transform)
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	print("art.transform  = ", art.transform)
	print("art.global     = ", art.global_transform)
	print("doors dict     = ", str(room.get("doors")))
	var dn: Dictionary = room.get("_door_nodes") as Dictionary
	print("_door_nodes keys = ", str(dn.keys()))
	for k in dn:
		var d := dn[k] as Node3D
		if d == null:
			print("  door[%s] = null" % str(k))
			continue
		print("  door[%s] name=%s type=%s pos=%s global=%s" % [
			str(k), d.name, d.get_class(), str(d.position), str(d.global_position),
		])
	print("--- room meta ---")
	for key in [
		"room_id", "grid_size", "authored_layout_instance_total",
		"authored_layout_promoted_walls", "authored_layout_floor_tile_count",
		"authored_layout_door_wall_count", "authored_layout_solid_wall_count",
		"connection_port_count", "authored_layout_unresolved_instances",
	]:
		if room.has_meta(key):
			print("  %s = %s" % [key, str(room.get_meta(key))])
	for prop in ["room_size", "size", "footprint", "bounds"]:
		var v = room.get(prop)
		if v != null:
			print("  %s = %s" % [prop, str(v)])
	var ports := art.get_node_or_null("ConnectionPorts")
	if ports != null:
		for c in ports.get_children():
			print("port %s local=%s global=%s meta.side=%s lane=%s target=%s" % [
				c.name, str((c as Node3D).position), str((c as Node3D).global_position),
				str(c.get_meta("side", "")), str(c.get_meta("lane_m", "")), str(c.get_meta("target_room_id", "")),
			])
	# 找出存档架与所有 x>0 的门相关对象
	print("--- art children with |x|>10 ---")
	for child in art.get_children():
		if not (child is Node3D):
			continue
		var n := child as Node3D
		var p := n.position
		if absf(p.x) > 10.0 and absf(p.z + 2.5) <= 3.0:
			print("  %-30s pos=%s comp=%s" % [n.name, str(p), str(n.get_meta("authored_component_id", ""))])
	get_tree().quit()
