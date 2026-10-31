extends Node
## 远征03 房间数量拆解：按来源分类统计运行时实际实例化的房间。
##
## 只读，不改任何资产。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEEDS := [77003244, 100990, 42, 123456]
const CONNECTOR_PREFIXES := ["cr"]

var _rows: Array[String] = []


func _ready() -> void:
	var all_ids := {}
	for seed_value in SEEDS:
		var tower := await _spawn(seed_value)
		var by_kind := {}
		var by_source := {}
		var ids: Array[String] = []
		for value in tower.get("_rooms") as Array:
			var room := value as DungeonRoom3D
			if room == null:
				continue
			ids.append(room.room_id)
			var kind := str(room.room_type)
			by_kind[kind] = int(by_kind.get(kind, 0)) + 1
			var source := _source_of(room)
			by_source[source] = int(by_source.get(source, 0)) + 1
			all_ids[room.room_id] = true
		ids.sort()
		print("COUNT_SEED %d rooms=%d" % [seed_value, ids.size()])
		print("  BY_TYPE   %s" % _fmt(by_kind))
		print("  BY_SOURCE %s" % _fmt(by_source))
		print("  IDS       %s" % ", ".join(ids))
		var blank: Array[String] = []
		for value in tower.get("_rooms") as Array:
			var room := value as DungeonRoom3D
			if room != null and str(room.room_type).is_empty():
				blank.append(room.room_id)
		blank.sort()
		print("  BLANK_TYPE %s" % ", ".join(blank))
		# ── 「真正房间」口径：排除一切走廊类 ────────────────────────────────
		# 两类都排除：① `cr*` 前缀（运行时自动生成的走廊连接器）；
		# ② `conn_01` / `conn_02`（flow 里声明为 CONNECTOR 节点，模板池是
		#    connector_10x30 / connector_30x10，一样是走廊，不是可停留房间）。
		var real: Array[String] = []
		var corridor: Array[String] = []
		for value in tower.get("_rooms") as Array:
			var room := value as DungeonRoom3D
			if room == null:
				continue
			if _is_corridor(room):
				corridor.append(room.room_id)
			else:
				real.append(room.room_id)
		real.sort()
		corridor.sort()
		print("  REAL rooms=%d  %s" % [real.size(), ", ".join(real)])
		print("  CORRIDOR %d  %s" % [corridor.size(), ", ".join(corridor)])
		_rows.append("seed=%d rooms=%d" % [seed_value, ids.size()])
		tower.queue_free()
		await get_tree().process_frame
	print("COUNT_DISTINCT_IDS %d（四种子的房间 id 并集）" % all_ids.size())
	var id_list: Array[String] = []
	for key in all_ids.keys():
		id_list.append(str(key))
	id_list.sort()
	print("COUNT_ALL_IDS %s" % ", ".join(id_list))
	get_tree().quit(0)


func _source_of(room: DungeonRoom3D) -> String:
	var id := room.room_id
	for prefix in CONNECTOR_PREFIXES:
		if id.begins_with(prefix):
			return "走廊连接器"
	if id.contains("_inj"):
		return "运行时注入房"
	return "flow 骨架房"


## 是不是走廊类（不是可停留房间）。
##
## 两类：
##   · `cr*` —— 运行时为连通两间房自动生成的走廊连接器；
##   · `conn_*` —— flow 里声明为 `CONNECTOR` 的节点，其 `template_pool` 是
##     `connector_10x30` / `connector_30x10`，同样是走廊。
## 两者都不该计入「房间数」—— 它们没有内容、不摆美术、玩家不停留。
func _is_corridor(room: DungeonRoom3D) -> bool:
	var id := room.room_id
	for prefix in CONNECTOR_PREFIXES:
		if id.begins_with(prefix):
			return true
	return id.begins_with("conn_")


func _fmt(counter: Dictionary) -> String:
	var keys: Array[String] = []
	for key in counter.keys():
		keys.append(str(key))
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%d" % [key, int(counter[key])])
	return ", ".join(parts)


func _spawn(seed_value: int) -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", seed_value)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower
