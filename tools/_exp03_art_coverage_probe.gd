extends Node
## 远征03 美术层覆盖体检：**按游戏实际装载口径**逐房核对「这间房有没有公馆美术」。
##
## 为什么需要它：`_exp03_manor_shell_verify` 只跑一个固定种子（77003244 → flow_01），
## 只能证明那一次装配出来的 17 间房有美术。但 `level_plan.generation_policy` 是
## `mode = flow / flow_pick = seeded_uniform`，运行时会从 6 条 flow 里按种子挑一条，
## 实际房间集合会变（`n08` 只在 flow_02/04/06 出现，注入房有 `inj1`/`inj2` 两套）。
## 所以「有没有房间被漏掉」必须跨种子、跨 flow 看。
##
## 判据（与 `DungeonRoom3D._expedition_static_layout_path()` 同一条解析链）：
##   `RuntimeRoomArtSource.matching_path()` 命中 → 才是本关的美术；
##   否则回退到 `rt_*_static_layout.tscn`（程序化壳体）= 这间房没有公馆包装。
##
## 走廊（`cr*` / `conn_*`）按设计不摆美术，不计入缺口，单独统计。
##
## 只读。退出码：非零 = 有可停留房间没拿到美术层。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")

## 覆盖 6 条 flow 的种子。flow 由种子均匀挑，多个种子才能把 6 条都走到。
const SEEDS := [
	77003244, 100990, 42, 123456, 7, 99, 2026, 31415, 55555, 808080,
	9173, 6060, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13,
]

var _seen_keys: Dictionary = {}
var _missing: Array[String] = []
var _corridor_missing: Array[String] = []
var _room_sets: Dictionary = {}
var _failures: Array[String] = []


func _ready() -> void:
	var seed_room_counts: Array[String] = []
	for seed_value in SEEDS:
		var tower := await _spawn(seed_value)
		var ids: Array[String] = []
		var rooms_n := 0
		var corridors_n := 0
		var art_n := 0
		for value in tower.get("_rooms") as Array:
			var room := value as DungeonRoom3D
			if room == null or not room.procedural_shell:
				continue
			var is_corridor := _is_corridor(room)
			var descriptor: Dictionary = CONTRACT.describe(room)
			var base := str(room.get("static_layout_scene_path"))
			var art_path := CONTRACT.art_path(base, descriptor)
			var has_art := not art_path.is_empty() and ResourceLoader.exists(art_path, "PackedScene")
			var loaded := bool(room.get_meta("art_layer_loaded", false))
			var sig := str(descriptor.get("signature", "")).substr(0, 12)
			var portal := str(descriptor.get("portal_fingerprint", ""))
			var template := str(descriptor.get("template_id", ""))
			var key := "%s|%s|%s" % [template, sig, portal]
			if is_corridor:
				corridors_n += 1
				if not has_art:
					_corridor_missing.append(key)
			else:
				rooms_n += 1
				ids.append(room.room_id)
				if has_art:
					art_n += 1
				if not has_art:
					_missing.append("%s (模板 %s 键 %s 门位 %s)" % [room.room_id, template, sig, portal])
				if not loaded and has_art:
					_failures.append("%s: 美术文件在但运行时没接管（art_layer_loaded=false）" % room.room_id)
			_seen_keys[key] = {
				"art": has_art,
				"loaded": loaded,
				"template": template,
			}
		ids.sort()
		var signature_set := ",".join(ids)
		_room_sets[signature_set] = int(_room_sets.get(signature_set, 0)) + 1
		seed_room_counts.append("COV_SEED %d 可停留=%d 走廊=%d 有美术=%d"
			% [seed_value, rooms_n, corridors_n, art_n])
		print(seed_room_counts[-1])
		print("  ROOMS %s" % signature_set)
		tower.queue_free()
		await get_tree().process_frame

	print("=== 装配变体（按房间集合去重）%d 种 ===" % _room_sets.size())
	for key in _room_sets.keys():
		print("  出现 %d 次: %s" % [int(_room_sets[key]), key])

	print("=== 美术复用键 %d 个 ===" % _seen_keys.size())
	var keys: Array[String] = []
	for key in _seen_keys.keys():
		keys.append(str(key))
	keys.sort()
	for key in keys:
		var info: Dictionary = _seen_keys[key]
		print("  KEY %-46s art=%-5s loaded=%-5s" % [key, info["art"], info["loaded"]])

	print("COV_MISSING_ROOMS %d" % _missing.size())
	for item in _missing:
		print("  MISSING %s" % item)
	print("COV_CORRIDOR_WITHOUT_ART %d（走廊按设计不摆美术，仅统计）" % _corridor_missing.size())
	print("COV_%s 缺口=%d 未接管=%d"
		% ["OK" if _missing.is_empty() and _failures.is_empty() else "FAILED",
			_missing.size(), _failures.size()])
	for reason in _failures:
		printerr("COV_FAIL ", reason)
	get_tree().quit(0 if _missing.is_empty() and _failures.is_empty() else 1)


func _is_corridor(room: DungeonRoom3D) -> bool:
	var id := room.room_id
	if id.begins_with("cr"):
		return true
	return id.begins_with("conn_")


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
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower
