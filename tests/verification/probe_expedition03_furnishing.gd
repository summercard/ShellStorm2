extends Node3D
## 探针：远征03 房间「随机家具 / 可搜索容器」的布置是否与房间尺寸相称。
##
## 业主 2026-10-30 提问「自动刷出的搜索用的设施，这个是写死的嘛？」—— 答：是。
## 定位出三处不合理（都不是"值设小了"，是**判据用错了量**）：
##   ① 档位一刀切 `tower_cell`：40×30 的大厅与 5×10 的走廊拿到同一档，家具数量相同；
##   ② 没有尺寸下限：5×5 的十字路口也塞 3 件，通道被堵成迷宫；
##   ③ 没有"专属陈设"排除：商店房的随机家具会挡在服务台前（服务台在家具之后建、不避让）。
##
## 本探针把这三条都变成会失败的断言，并打印每间房的实际布置供对照。
##
## godot --headless --path . res://tests/verification/probe_expedition03_furnishing.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"
## 与 `DungeonRoom3D.MIN_FURNISHED_SHORT_SIDE_M` 同源；探针显式复算，不读实现常量
## （实现被改错时要能红）。
const MIN_SHORT_SIDE := 8.0
## 有专属陈设、不该摆随机家具的房型。
const EXCLUDED_TYPES: Array[String] = ["FACILITY", "STAIR_LOBBY", "BOSS", "MERCHANT", "EXTRACTION"]

var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		print("FURNISH_PROBE FAIL: 场景加载失败")
		get_tree().quit(1)
		return
	var scene := packed.instantiate()
	add_child(scene)
	for i in range(900):
		await get_tree().process_frame
		if (scene.get("_rooms") as Array).size() >= 10:
			break
	await get_tree().process_frame

	var rooms: Dictionary = scene.get("_room_by_id") as Dictionary
	var rows: Array = []
	for room_id_value in rooms.keys():
		var room := rooms[room_id_value] as Node
		if room == null:
			continue
		room.call("ensure_detail_built")
		await get_tree().process_frame
		var dims: Vector2 = room.call("get_dimensions")
		var props := 0
		var searchable := 0
		for value in get_tree().get_nodes_in_group("room_prop_3d"):
			if not room.is_ancestor_of(value):
				continue
			props += 1
			if value.is_in_group("searchable_prop_3d"):
				searchable += 1
		rows.append({
			"room_id": str(room.get("room_id")),
			"type": str(room.get("room_type")),
			"size": str(room.get("size_class")),
			"dims": dims,
			"props": props,
			"searchable": searchable,
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float((a["dims"] as Vector2).x * (a["dims"] as Vector2).y) > float(
			(b["dims"] as Vector2).x * (b["dims"] as Vector2).y))

	for row in rows:
		var dims := row["dims"] as Vector2
		print("FURNISH room=%-26s type=%-12s size=%-8s dims=%dx%d props=%d searchable=%d" % [
			str(row["room_id"]), str(row["type"]), str(row["size"]),
			int(dims.x), int(dims.y), int(row["props"]), int(row["searchable"])])

	# ① 小房不得布置
	var small_with_props := 0
	# ② 专属陈设房型不得布置
	var excluded_with_props := 0
	# ③ 大房间的家具不得少于小房间（档位必须真的随尺寸走）
	var large_min := 999
	var medium_max := -1
	for row in rows:
		var dims := row["dims"] as Vector2
		var short_side := minf(dims.x, dims.y)
		var props := int(row["props"])
		var room_type := str(row["type"])
		if short_side < MIN_SHORT_SIDE and props > 0:
			small_with_props += 1
			print("FURNISH FAIL_SMALL %s short=%.1f props=%d" % [
				str(row["room_id"]), short_side, props])
		if room_type in EXCLUDED_TYPES and props > 0:
			excluded_with_props += 1
			print("FURNISH FAIL_EXCLUDED %s type=%s props=%d" % [
				str(row["room_id"]), room_type, props])
		if short_side >= 28.0 and room_type not in EXCLUDED_TYPES:
			large_min = mini(large_min, props)
		elif short_side >= 18.0 and room_type not in EXCLUDED_TYPES:
			medium_max = maxi(medium_max, props)

	print("FURNISH small_with_props=%d excluded_with_props=%d large_min=%d medium_max=%d" % [
		small_with_props, excluded_with_props,
		large_min if large_min != 999 else -1, medium_max])
	_check(small_with_props == 0, "短边 < %.0fm 的房间不得布置家具" % MIN_SHORT_SIDE)
	_check(excluded_with_props == 0, "专属陈设房型不得布置随机家具")
	if large_min != 999 and medium_max >= 0:
		_check(large_min >= medium_max,
			"大房间家具数不得少于中房间（large_min=%d medium_max=%d）" % [
				large_min, medium_max])

	print("FURNISH_PROBE %s" % ("OK" if _failed == 0 else "FAIL count=%d" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed += 1
	print("FURNISH %s %s" % ["PASS" if ok else "FAIL", label])
