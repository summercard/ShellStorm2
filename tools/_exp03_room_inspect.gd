extends Node
## 单房透视：把一间房「为什么进/不进美术层」的全部判据一次打出来。
##
## 用法：`-- --room=start --seed=3893044740`
##
## 打印：procedural_shell / tower_module_shell / room_type / 尺寸 / template_id
##      / static_layout_path / RuntimeRoomArtSource.supports() / 复用键 / 期望路径
##
## 只读。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
var SEED := 3893044740
var TARGET := "start"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			SEED = int(arg.substr(7))
		elif arg.begins_with("--room="):
			TARGET = arg.substr(7)
	print("ROOM_SEED %d TARGET %s" % [SEED, TARGET])
	var tower := await _spawn()
	print("ROOM 全部房间（不过滤）：")
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		var dim: Vector2 = room.call("get_dimensions")
		var path := str(room.get("static_layout_scene_path"))
		print("  %-24s proc=%-5s tower=%-5s type=%-14s %dx%d tpl=%s"
			% [room.room_id, room.procedural_shell, bool(room.get("tower_module_shell")),
				str(room.room_type), int(dim.x), int(dim.y), str(room.get("template_id"))])
		print("        static_layout=%s" % (path if not path.is_empty() else "(空)"))
		print("        supports=%s" % CONTRACT.supports(room))
		if CONTRACT.supports(room):
			var d: Dictionary = CONTRACT.describe(room)
			print("        sig=%s portal=%s tpl=%s"
				% [str(d.get("signature", "")).substr(0, 12),
					str(d.get("portal_fingerprint", "")), str(d.get("template_id", ""))])
			var want := CONTRACT.art_path(path, d)
			print("        art_path=%s exists=%s"
				% [want.get_file(), ResourceLoader.exists(want, "PackedScene")])
			var ports: Array[String] = []
			for pv in room.get("connection_ports") as Array:
				var p := pv as Dictionary
				ports.append("%s@%.2f w=%.2f" % [
					str(p.get("side", "")), float(p.get("lane_m", 0.0)),
					float(p.get("door_width_m", 0.0))])
			print("        ports=%s" % ", ".join(ports))
		if room.room_id == TARGET:
			print("  ↑↑↑ 目标房间 ↑↑↑")
			_dump_art(room)
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _dump_art(room: DungeonRoom3D) -> void:
	print("  目标房美术层状态：")
	print("    art_layer_keep_structure = %s" % str(room.get("art_layer_keep_structure")))
	print("    static_layout_scene_path(成员) = %s" % str(room.get("static_layout_scene_path")))
	for key in [
		"art_layer_loaded", "art_layer_geometry_stripped", "art_layer_structure_kept",
		"art_layer_floor_complete", "art_layer_covered_sides",
		"procedural_floor_skipped", "static_layout_scene_path",
	]:
		print("    %-32s = %s" % [key, str(room.get_meta(key, "(无)"))])
	var root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if root == null:
		root = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	if root == null:
		print("    ✗ 场景树里没有 AuthoredLayoutArtRoot / SafeRoomArtRoot —— 美术层没挂上")
		return
	print("    美术根 = %s  子节点 %d" % [root.name, root.get_child_count()])
	var by_family := {}
	var total := 0
	var visible := 0
	for node in root.find_children("*", "Node3D", true, false):
		var prefab := str(node.scene_file_path)
		if prefab.is_empty():
			continue
		total += 1
		if node.is_visible_in_tree():
			visible += 1
		var key := "白盒件" if prefab.contains("prp_room_") else (
			"公馆件" if prefab.contains("env_manor_") else "其他")
		by_family[key] = int(by_family.get(key, 0)) + 1
		if key == "其他":
			by_family["其他:" + prefab.get_file().get_basename()] = int(
				by_family.get("其他:" + prefab.get_file().get_basename(), 0)) + 1
	print("    结构件/美术件合计 %d（可见 %d）" % [total, visible])
	for key in by_family.keys():
		print("      %-40s %d" % [key, int(by_family[key])])


func _spawn() -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower
