extends Node
## 只读探查：列出指定层安全房（STAIR_LOBBY）里跨度 >=2m 的可视件，并还原真实显示色。
## 用途：定位"运行时看到但认不出"的神秘几何 —— 例如 98F 安全房里那条蓝色横带，
## 就是 SafeRoomPackage_overhead_services（跨设施顶部管线与灯带）的自发光部分。
##
## 关键：GLB 走 PaletteUV 取色，材质 albedo 恒为白，颜色判据必须用顶点 UV 反查色盘像素，
## 否则会漏判成"无色"（这正是第一次排查走弯路的原因）。
##
## 跑法：godot --headless --path <proj> res://tests/verification/probe_safe_room_visual_inventory.tscn
## 想换层改 TARGET_FLOOR；想换种子改 run_seed_override。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const PALETTE := preload("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
const TARGET_FLOOR := 98
const FLOOR_Y := -24.0

var _palette: Image


func _ready() -> void:
	_palette = PALETTE.get_image()
	if _palette.is_compressed():
		_palette.decompress()
	var scene := load(TOWER_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(TARGET_FLOOR)
	await get_tree().process_frame
	var room_by_id := tower.get("_room_by_id") as Dictionary
	for id_value in room_by_id.keys():
		var room := room_by_id.get(id_value) as DungeonRoom3D
		if room != null:
			room.set_stream_state(1)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	for id_value in room_by_id.keys():
		var room := room_by_id.get(id_value) as DungeonRoom3D
		if room == null or room.room_type != "STAIR_LOBBY":
			continue
		if absf(room.global_position.y - FLOOR_Y) > 1.0:
			continue
		print("=== 98F STAIR_LOBBY %s @ %s ===" % [room.room_id, str(room.global_position)])
		var items: Array = []
		for value in room.find_children("*", "MeshInstance3D", true, false):
			var mi := value as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
			var span := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			if span < 2.0:
				continue
			items.append({
				"path": String(room.get_path_to(mi)),
				"size": aabb.size,
				"local": room.to_local(aabb.get_center()),
				"top": aabb.position.y + aabb.size.y - room.global_position.y,
				"color": _sample_color(mi),
			})
		items.sort_custom(func(a, b): return a["size"].length() > b["size"].length())
		for item in items:
			var color: Color = item["color"]
			print("   %-66s size=%s local=%s top=%.2f color=%s" % [
				item["path"].right(68),
				_vec(item["size"]),
				_vec(item["local"]),
				float(item["top"]),
				"(%.2f, %.2f, %.2f)" % [color.r, color.g, color.b],
			])
		print("   -> span>=2m count=%d" % items.size())
		print("")

	print("PROBE_BLUE_SLAB_V3_DONE")
	get_tree().quit(0)


## 用顶点 UV 反查色盘，取出现次数最多（主色）的像素颜色。
func _sample_color(mi: MeshInstance3D) -> Color:
	var mesh := mi.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return Color(0, 0, 0, 0)
	var arrays := mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_TEX_UV:
		return Color(0, 0, 0, 0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return Color(0, 0, 0, 0)
	var histogram := {}
	var width := float(_palette.get_width())
	var height := float(_palette.get_height())
	for index in range(0, uvs.size(), maxi(1, uvs.size() / 256)):
		var uv := uvs[index]
		var x := clampi(int(uv.x * width), 0, _palette.get_width() - 1)
		var y := clampi(int(uv.y * height), 0, _palette.get_height() - 1)
		var key := "%d_%d" % [x / 32, y / 32]
		histogram[key] = int(histogram.get(key, 0)) + 1
	var best_key := ""
	var best_count := -1
	for key in histogram.keys():
		if int(histogram[key]) > best_count:
			best_count = int(histogram[key])
			best_key = str(key)
	if best_key.is_empty():
		return Color(0, 0, 0, 0)
	var parts := best_key.split("_")
	var x := clampi(int(parts[0]) * 32 + 16, 0, _palette.get_width() - 1)
	var y := clampi(int(parts[1]) * 32 + 16, 0, _palette.get_height() - 1)
	return _palette.get_pixel(x, y)


func _vec(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
