extends Node
## 验证「美术复用键」是否真的收敛：一局里 N 间房应该落成少数几个键。
##
## 回答两个问题：
##   ① 同一模板 + 同尺寸 + 同房型的房间，跨门位是否共用一个键？（业主的核心诉求）
##   ② 有烘焙美术时，运行时是否走「几何重建 + 美术层叠加」，而不是整房接管？
##
## 用法：godot --headless --path . --scene res://tools/_exp03_reuse_key_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const SEEDS: Array[int] = [77003244, 42]

var _failures: Array[String] = []


func _ready() -> void:
	for seed_value in SEEDS:
		await _probe(seed_value)
	print("REUSE_PROBE_%s failures=%d"
		% ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("REUSE_FAIL ", message)


func _probe(seed_value: int) -> void:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", seed_value)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame

	var by_key := {}
	var rows: Array[Dictionary] = []
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
		var descriptor := CONTRACT.describe(room)
		var key := str(descriptor["signature"])
		var template := str(descriptor["template_id"])
		var size: Array = descriptor["size_m"]
		var lanes: Array[String] = []
		for port in room.get("connection_ports") as Array:
			var p := port as Dictionary
			lanes.append("%s@%.1f" % [str(p.get("side", "")), float(p.get("lane_m", 0.0))])
		lanes.sort()
		rows.append({
			"room_id": room.room_id, "template": template,
			"size": "%.0fx%.0f" % [float(size[0]), float(size[1])],
			"key": key.substr(0, 12), "lanes": ",".join(lanes),
			"type": room.room_type,
		})
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append(str(room.room_id))

	print("REUSE_SEED %d rooms=%d unique_keys=%d"
		% [seed_value, rows.size(), by_key.size()])
	# record 层诊断：template_id 在哪一环丢的
	if seed_value == SEEDS[0]:
		for rec in tower.get("_records") as Array:
			var r := rec as Dictionary
			if str(r.get("id", "")) in ["start", "n02", "n04", "conn_01"]:
				print("  REC %-10s template_id=[%s] floor_plan_key=[%s]"
					% [str(r.get("id", "")), str(r.get("template_id", "<缺键>")),
						str(r.get("floor_plan_key", "<缺键>"))])
	# 详情只打一局，避免刷屏
	if seed_value == SEEDS[0]:
		for row in rows:
			print("  ROOM %-14s %-16s %-9s %-14s %-22s %s"
				% [row["room_id"], row["template"], row["size"], row["key"],
					row["lanes"], row["type"]])
	print("  GROUPS:")
	for key in by_key.keys():
		var members: Array = by_key[key]
		print("    %s x%-2d %s" % [str(key).substr(0, 12), members.size(), str(members)])

	# ① 复用键必须收敛：房间数 > 键数，否则说明"每个房间还是独立的键"
	_check(by_key.size() < rows.size(), "复用键没有收敛（%d 键 / %d 房）"
		% [by_key.size(), rows.size()])
	# ② 每个键下 ≥1 个模板名，且同键内的模板必须一致
	for key in by_key.keys():
		var templates := {}
		for row in rows:
			if str(row["key"]) == str(key).substr(0, 12):
				templates[str(row["template"])] = true
		_check(templates.size() == 1, "同一个键 %s 里混了多个模板 %s"
			% [str(key).substr(0, 12), str(templates.keys())])
	# ③ 有烘焙美术时：必须走美术层叠加，不得整房接管
	var with_art := 0
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		if bool(room.get_meta("art_layer_loaded", false)):
			with_art += 1
			_check(not bool(room.get_meta("static_layout_scene_loaded", false)),
				"%s 同时打了 art_layer_loaded 与 static_layout_scene_loaded（语义冲突）"
				% room.room_id)
			_check(room.get_node_or_null("Wall_north") != null,
				"%s 走美术层后没建程序化墙" % room.room_id)
	print("REUSE_ART_LAYER seed=%d rooms_with_art=%d"
		% [seed_value, with_art])
	tower.queue_free()
	await get_tree().process_frame
