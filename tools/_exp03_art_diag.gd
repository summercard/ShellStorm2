extends Node
## 长征03 美术层诊断：**给定一个真实种子**，逐房打印「为什么这间房没拿到公馆美术」。
##
## 用法：改 `SEED` 或 `--seed=<值>` 传入真实种子（游戏内 HUD 左下角「关卡种子」）。
##
## 输出每行一条判据链：
##   room_id | template | signature前12 | 门位指纹 | 期望文件是否存在 | 该模板现存哪些文件
##
## 只读。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
var SEED := 3893044740

## 与 `tools/_exp03_manor_shell_builder.gd::_style_for()` 同源。**只读参考**，
## 用于判断「若按原型键匹配，这间房能不能命中」。改 builder 的 ARCHETYPES 时
## 这里不跟随也不影响生产 —— 它只出现在诊断输出里。
const HUB_IDS := ["hub_01", "hub_02"]
const ARCHETYPES := {
	"COMBAT": {
		"small": {"floor": "full", "windows": "blind", "note": "逼仄空厅"},
		"mid": {"floor": "full", "windows": "pair", "note": "中庭回廊"},
		"large": {"floor": "full", "windows": "double_pair", "note": "大回廊"},
		"max_short_side": {"small": 25.0, "mid": 30.0},
	},
	"BOSS": {"floor": "wood_ring", "windows": "blind", "note": "王座间"},
	"TRAP": {"floor": "full", "windows": "blind", "note": "陷阱厅"},
	"UPGRADE": {"floor": "full", "windows": "pair", "note": "更衣前厅"},
	"MERCHANT": {"floor": "full", "windows": "pair", "note": "铺面"},
	"EVENT": {"floor": "full", "windows": "single_side", "note": "陈列室"},
	"SCAVENGE": {"floor": "stone_ring", "windows": "pair", "note": "操作间"},
	"EXTRACTION": {"floor": "full", "windows": "blind", "note": "撤离舱"},
	"SAFE_ROOM": {"floor": "full", "windows": "blind", "note": "安全屋"},
	"STAIR_LOBBY": {"floor": "full", "windows": "blind", "note": "楼梯厅"},
}


func _style_of(room: DungeonRoom3D, dim: Vector2) -> String:
	var id := room.room_id
	for hub in HUB_IDS:
		if id == hub:
			return "大堂/clerestory/stone_ring"
	var type_id := str(room.room_type)
	var entry: Variant = ARCHETYPES.get(type_id)
	if entry is Dictionary and (entry as Dictionary).has("small"):
		var short_side := minf(dim.x, dim.y)
		var tiers: Dictionary = entry["max_short_side"]
		if short_side <= float(tiers["small"]):
			entry = entry["small"]
		elif short_side <= float(tiers["mid"]):
			entry = entry["mid"]
		else:
			entry = entry["large"]
	if not (entry is Dictionary):
		return "(无原型)"
	var e := entry as Dictionary
	return "%s/%s/%s" % [str(e.get("note", "?")), str(e.get("windows", "?")), str(e.get("floor", "?"))]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			SEED = int(arg.substr(7))
	print("DIAG_SEED %d" % SEED)
	var tower := await _spawn()
	var art_n := 0
	var miss_n := 0
	var proto_hit := 0
	var proto_miss: Array[String] = []
	# 现有烘焙文件的「原型索引」：(template, sig12, style) → 文件名
	var proto_index := _build_proto_index()
	print("DIAG 现有烘焙文件原型索引 %d 种组合" % proto_index.size())
	print("DIAG %-24s %-20s %-13s %-8s %-6s %s" % ["room_id", "template", "signature", "门位", "按门位", "原型 / 按原型"])
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		var id := room.room_id
		var corridor := id.begins_with("cr") or id.begins_with("conn_")
		var d: Dictionary = CONTRACT.describe(room)
		var base := str(room.get("static_layout_scene_path"))
		var want := CONTRACT.art_path(base, d)
		var exists := not want.is_empty() and ResourceLoader.exists(want, "PackedScene")
		var loaded := bool(room.get_meta("art_layer_loaded", false))
		var sig := str(d.get("signature", "")).substr(0, 12)
		var pf := str(d.get("portal_fingerprint", "(无门位)"))
		var tpl := str(d.get("template_id", "?"))
		var mark := "有" if exists else ("走廊" if corridor else "缺")
		var dim: Vector2 = room.call("get_dimensions")
		var style := _style_of(room, dim)
		if style == "(无原型)":
			print("        [次因] room_type=\"%s\" 不在 ARCHETYPES —— 拿不到原型，改键也命不中"
				% str(room.room_type))
		var pkey := "%s|%s|%s" % [tpl, sig, style]
		var pmatch := str(proto_index.get(pkey, ""))
		print("DIAG %-24s %-20s %-13s %-8s %-6s %s%s"
			% [id, tpl, sig, pf, mark, style,
				("" if pmatch.is_empty() else "  → 可命中 " + pmatch)])
		if corridor:
			continue
		if exists:
			art_n += 1
		else:
			miss_n += 1
		if not pmatch.is_empty():
			proto_hit += 1
		else:
			proto_miss.append("%s(%s)" % [id, style])
			print("        期望文件: %s" % want.get_file())
			var have := _list_siblings(want.get_base_dir(), tpl + "_" + sig)
			print("        现有同签名文件 %d 份: %s"
				% [have.size(), ", ".join(have) if not have.is_empty() else "(无)"])
		# 门位是否落在 5m 格心？决定能否运行时按格替换门墙。
		var lanes: Array[String] = []
		for pv in room.get("connection_ports") as Array:
			var port := pv as Dictionary
			var side := str(port.get("side", ""))
			var lane := float(port.get("lane_m", 0.0))
			var cells := _cells(dim, side)
			var on_center := false
			for c in cells:
				if absf(float(c) - lane) < 0.01:
					on_center = true
					break
			lanes.append("%s@%.2f%s" % [side, lane, "" if on_center else "(非格心)"])
	print("DIAG_PROTO 按原型键可命中 %d 间，缺 %d 间 %s"
		% [proto_hit, proto_miss.size(), ", ".join(proto_miss)])
	print("DIAG_SUMMARY 按门位命中=%d/17  按原型命中=%d/17" % [art_n, proto_hit])
	# 模板整体覆盖度
	print("--- 各模板烘焙文件数（签名命中与否）---")
	var by_tpl: Dictionary = {}
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		var d2: Dictionary = CONTRACT.describe(room)
		var tpl2 := str(d2.get("template_id", "?"))
		var base2 := str(room.get("static_layout_scene_path"))
		var stem2 := tpl2 + "_" + str(d2.get("signature", "")).substr(0, 12)
		var has2 := not CONTRACT.art_path(base2, d2).is_empty() and ResourceLoader.exists(
			CONTRACT.art_path(base2, d2), "PackedScene")
		var row: Array = by_tpl.get(tpl2, [0, 0, 0]) as Array
		row[0] = int(row[0]) + 1
		row[1] = int(row[1]) + int(1 if has2 else 0)
		row[2] = maxi(int(row[2]), _list_siblings(
			CONTRACT.art_path(base2, d2).get_base_dir(), stem2).size())
		by_tpl[tpl2] = row
	for k in by_tpl.keys():
		var r: Array = by_tpl[k]
		print("  %-22s 本局 %d 间  命中 %d  同签名既有文件 %d"
			% [k, int(r[0]), int(r[1]), int(r[2])])
	print("DIAG_DONE 有美术=%d 缺=%d" % [art_n, miss_n])
	print("DIAG_%s" % ("ART_OK" if miss_n == 0 else "ART_MISSING"))
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if miss_n == 0 else 1)


## 扫 `runtime_rooms/` 下所有烘焙文件，建 `template|sig12|原型` → 文件名 的索引。
##
## 原型取文件里的 `metadata/archetype` / `window_mode` / `floor_mode` —— 这三件
## 由 `_style_for()` 按 `(room_type, 短边)` 纯函数算出，**不含随机**，所以是稳定的复用维度。
func _build_proto_index() -> Dictionary:
	var out := {}
	var dir := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms"
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if name.ends_with(".tscn"):
			var path := dir.path_join(name)
			var packed := load(path) as PackedScene
			if packed != null:
				var state := packed.get_state()
				var meta := {}
				for index in range(state.get_node_property_count(0)):
					var pname := str(state.get_node_property_name(0, index))
					if pname.begins_with("metadata/"):
						meta[pname.substr(9)] = str(state.get_node_property_value(0, index))
				var tpl := str(meta.get("template_id", ""))
				var sig := str(meta.get("runtime_room_signature", "")).substr(0, 12)
				var style := "%s/%s/%s" % [
					str(meta.get("archetype", "")),
					str(meta.get("window_mode", "")),
					str(meta.get("floor_mode", "")),
				]
				if not tpl.is_empty() and not sig.is_empty():
					var key := "%s|%s|%s" % [tpl, sig, style]
					if not out.has(key):
						out[key] = name
		name = da.get_next()
	da.list_dir_end()
	return out


func _list_siblings(dir: String, stem_prefix: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		if name.begins_with(stem_prefix) and name.ends_with(".tscn"):
			out.append(name)
		name = da.get_next()
	da.list_dir_end()
	return out


func _cells(dim: Vector2, side: String) -> Array[float]:
	var length := dim.x if side in ["north", "south"] else dim.y
	var count := int(round(length / 5.0))
	var out: Array[float] = []
	for index in range(count):
		out.append(-length * 0.5 + (float(index) + 0.5) * 5.0)
	return out


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
