extends Node
## 诊断探针：把远征01 末三房（room_10 / boss / extraction）在**平面帧**与**世界帧**的
## 真值全部打出来 —— 换房前先确认「哪边是北」这件事到底怎么算出来的。
##
## 为什么要它：远征01 是 `mode = constrained` + `expedition_global_rotation_deg = 180`
## （见 `FloorPlanGenerator.generate_from_level_plan`）：
##   ① 几何按种子**现算**，蓝图里的 center_m 只是兜底样例；
##   ② 算完还整体**绕入口房反射 180°**，并给每房 `rotation_deg += 180`。
## ⇒ 「平面帧朝北」和「世界里朝北」**差 180°**。靠读代码推容易差一个号，
##    所以这里把两个帧都实测出来，作为改数据的依据。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_diag'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_boss_swap_diagnose.tscn

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199
const WATCH: Array[String] = ["room_09", "room_10", "boss", "extraction"]

var _root: Window


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	_dump_plan_frame()
	var tower: TowerDescent3D = EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	_root.add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("PLAN used_fallback=", tower.get("_floor_plan_snapshots") != null and _fallback(tower))
	for room_id in WATCH:
		var room: DungeonRoom3D = tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("WORLD %-12s <缺>" % room_id)
			continue
		var dims := room.get_dimensions()
		print("WORLD %-12s pos=%s yaw=%.2f° dims=(%.1f, %.1f) type=%s" % [
			room_id, _v(room.global_position), rad_to_deg(room.global_rotation.y),
			dims.x, dims.y, room.room_type,
		])
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var side := str(port.get("side", ""))
			var lane := float(port.get("lane_m", 0.0))
			var world := room.to_global(_port_local(room, port))
			var normal := (room.global_basis * _outward(port)).normalized()
			print("      port %-3s side=%-5s lane=%7.2f height=%5.2f → world=%s outward=%s (%s)" % [
				str(port.get("port_id", "")), side, lane, float(port.get("height_m", 0.0)),
				_v(world), _v(normal), _compass(normal),
			])
	print("BOSS_SWAP_DIAG_DONE")
	get_tree().quit(0)


func _fallback(tower: TowerDescent3D) -> bool:
	var snapshots: Dictionary = tower.get("_floor_plan_snapshots")
	var entry := snapshots.get(0, {}) as Dictionary
	return bool(entry.get("used_fallback", false))


## 平面帧：直接问生成器要一份真几何（与运行时同一条链路）。
func _dump_plan_frame() -> void:
	var plan := LevelPlanLoader.load_level_plan("expedition_01")
	var policy := (plan.get("generation_policy", {}) as Dictionary).duplicate(true)
	policy["expedition_global_rotation_deg"] = 180
	var templates := LevelPlanLoader.load_room_templates("expedition_01")
	var blueprint := LevelPlanLoader.normalize_floor("expedition_01", 0)
	var generated := FloorPlanGenerator._generate_constrained_floor(
		"expedition_01", 0, RUN_SEED, blueprint, policy, templates
	)
	if generated.is_empty():
		print("PLAN 生成失败（used_fallback 会为真）")
		return
	print("PLAN generated rooms=", (generated.get("rooms", []) as Array).size())
	for room_id in WATCH:
		for value in generated.get("rooms", []) as Array:
			var room := value as Dictionary
			if str(room.get("key", "")) != room_id:
				continue
			var center := room.get("center", Vector2.ZERO) as Vector2
			var size := room.get("size", Vector2.ZERO) as Vector2
			print("PLAN  %-12s center=(%8.2f,%8.2f) size=(%5.1f,%5.1f) rot=%.0f template=%s" % [
				room_id, center.x, center.y, size.x, size.y,
				float(room.get("rotation_deg", 0.0)), str(room.get("template_id", "")),
			])
			for port_value in room.get("connection_ports", []) as Array:
				var port := port_value as Dictionary
				print("      port %-3s target=%-11s pos=%s outward=%s h=%s" % [
					str(port.get("port_id", "")), str(port.get("target", "<空>")),
					_v2(port.get("position_m", [])), _v2(port.get("outward", [])),
					str(port.get("height_m", "-")),
				])


## 端口在房间局部空间的位置：side + lane 是运行时口径，height_m 是相对走面高度。
func _port_local(room: DungeonRoom3D, port: Dictionary) -> Vector3:
	var dims := room.get_dimensions()
	var lane := float(port.get("lane_m", 0.0))
	var height := float(port.get("height_m", 0.0))
	match str(port.get("side", "")):
		"north":
			return Vector3(lane, height, -dims.y * 0.5)
		"south":
			return Vector3(lane, height, dims.y * 0.5)
		"west":
			return Vector3(-dims.x * 0.5, height, lane)
		_:
			return Vector3(dims.x * 0.5, height, lane)


func _outward(port: Dictionary) -> Vector3:
	match str(port.get("side", "")):
		"north":
			return Vector3(0.0, 0.0, -1.0)
		"south":
			return Vector3(0.0, 0.0, 1.0)
		"west":
			return Vector3(-1.0, 0.0, 0.0)
		_:
			return Vector3(1.0, 0.0, 0.0)


func _compass(direction: Vector3) -> String:
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 0.5:
		return "垂直"
	if absf(flat.x) > absf(flat.y):
		return "东(+X)" if flat.x > 0.0 else "西(-X)"
	return "南(+Z)" if flat.y > 0.0 else "北(-Z)"


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _v2(v: Variant) -> String:
	var arr := v as Array
	if arr.size() < 2:
		return str(v)
	return "(%.2f, %.2f)" % [float(arr[0]), float(arr[1])]
