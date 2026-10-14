extends Node
## 轻量版图探针：直接调 FloorPlanGenerator，不装配 3D 场景（秒级）。
## 打出每局的：整层旋转 / 是否回退 / 校验错误 / 逐房房心·尺寸·房向；
## 并用「房心 + 房向 + 半尺寸」把每扇门换算到世界坐标，逐个相邻对算重合度。

const GEN := preload("res://src/map/FloorPlanGenerator.gd")

const SEEDS: Array[int] = [3198984856, 286648852]
const ROLL: Array[int] = [180, 0]


func _ready() -> void:
	for seed_value in SEEDS:
		for rotation in ROLL:
			_dump(seed_value, rotation)
	print("EXP01_PLAN_DONE")
	get_tree().quit(0)


func _dump(seed_value: int, rotation: int) -> void:
	var plan: Dictionary = GEN.generate_from_level_plan("expedition_01", 0, seed_value, rotation)
	print("")
	print("=== SEED %d  整层旋转=%d ===" % [seed_value, rotation])
	var errs: Array = plan.get("validation_errors", []) as Array
	print("  layout_id=%s valid=%s fallback=%s entry=%s exit=%s %s" % [str(plan.get("layout_id","")),
		str(plan.get("valid", false)), str(plan.get("used_fallback", false)),
		str(plan.get("entry_side", "")), str(plan.get("exit_side", "")),
		("🔴" + str(errs)) if not errs.is_empty() else "",
	])
	var doors: Dictionary = {}
	for value in plan.get("rooms", []) as Array:
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		var pos := room.get("position", Vector2.ZERO) as Vector2
		var dims := room.get("dimensions", Vector2.ZERO) as Vector2
		var rot := float(room.get("rotation_deg", 0.0))
		var ports: Array[String] = []
		for port_value in room.get("connection_ports", []) as Array:
			var port := port_value as Dictionary
			var target := str(port.get("target", port.get("target_room_id", "")))
			var side := str(port.get("side", "?"))
			var lane := float(port.get("lane_m", 0.0))
			ports.append("%s%.1f%s" % [
				side.substr(0, 1).to_upper(), lane,
				("→" + target) if target != "" else "(空)",
			])
			if target != "":
				doors["%s|%s" % [key, target]] = _door_world(pos, dims, rot, side, lane)
		var off := float(room.get("floor_offset_m", 0.0))
		print("  %-11s (%8.2f,%8.2f) %-11s rot=%6.1f y=%6.1f [%5.1f x %5.1f] %s" % [
			key, pos.x, pos.y, str(room.get("anchor_policy", "grid")),
			rot, off, dims.x, dims.y, " ".join(ports),
		])
	print("  --- 相邻门洞世界坐标差（>0.5m = 错位） ---")
	var bad := 0
	var checked := 0
	for pair_value in doors.keys():
		var pair := str(pair_value)
		var parts := pair.split("|")
		var a_key := parts[0]
		var b_key := parts[1]
		if a_key > b_key:
			continue
		var back: Variant = doors.get("%s|%s" % [b_key, a_key], null)
		if back == null:
			continue
		checked += 1
		var p1: Vector2 = doors[pair]
		var p2: Vector2 = back
		var gap := p1.distance_to(p2)
		if gap >= 0.5:
			bad += 1
			print("    🔴 %-10s <-> %-10s gap=%7.3f  (%s) vs (%s)" % [
				a_key, b_key, gap, _xy(p1), _xy(p2),
			])
	print("  >>> 共检 %d 对，错位 %d 对" % [checked, bad])


func _xy(p: Vector2) -> String:
	return "%.1f,%.1f" % [p.x, p.y]


## 门在世界坐标：`connection_ports` 的 side/lane 已按最终帧给出（房心 + 沿墙偏移），
## **不再叠加 rotation_deg**（rotation_deg 是给模板美术用的，不是给端口用的）。
func _door_world(pos: Vector2, dims: Vector2, rot: float, side: String, lane: float) -> Vector2:
	var half := dims * 0.5
	match side:
		"north":
			return Vector2(pos.x + lane, pos.y - half.y)
		"south":
			return Vector2(pos.x + lane, pos.y + half.y)
		"east":
			return Vector2(pos.x + half.x, pos.y + lane)
		"west":
			return Vector2(pos.x - half.x, pos.y + lane)
	return pos
