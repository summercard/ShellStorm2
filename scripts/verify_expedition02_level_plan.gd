extends Node
## 远征关卡02 设计源验证（纯只读）。
##
## 跑法（**以场景方式跑**，这样 autoload 可用；`--script` 模式不加载 autoload，
## 会因为 `EliteRosterService` 找不到标识符而整链编译失败）：
##
##   godot --headless --path "<项目根>" res://scripts/verify_expedition02_level_plan.tscn
##
## 逐层验证：L1 可加载 → L2 可归一化 → `generate_from_level_plan` 的几何与校验错误。

const LEVEL_ID := "expedition_02"
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")

var failures: Array[String] = []


func _ready() -> void:
	print("=== expedition_02 设计源验证 ===")
	print("data_root: %s" % LOADER.data_root_for(LEVEL_ID))
	print("has_level_plan: %s" % LOADER.has_level_plan(LEVEL_ID))
	print("data_driven_enabled: %s" % GENERATOR.data_driven_enabled(LEVEL_ID))

	var plan := LOADER.load_level_plan(LEVEL_ID)
	if plan.is_empty():
		_fail("L1 level_plan.json 加载为空")
		_finish()
		return
	print("L1 runtime_enabled: %s" % str(
		(plan.get("generation_policy", {}) as Dictionary).get("runtime_enabled", null)))
	print("L1 room_templates: %s" % str(plan.get("room_templates", [])))

	var normalized := LOADER.normalize_floor(LEVEL_ID, 0)
	if normalized.is_empty():
		_fail("L2 floor_00.json 归一化为空")
		_finish()
		return
	print("L2 mode: %s | rooms: %d" % [
		str(normalized.get("mode", "")), (normalized.get("rooms", []) as Array).size()])
	for schema_error in normalized.get("errors", []):
		_fail("L2 schema: %s" % str(schema_error))

	var templates := LOADER.load_room_templates(LEVEL_ID)
	if templates.is_empty():
		_fail("room_templates 加载为空")

	var generated := GENERATOR.generate_from_level_plan(LEVEL_ID, 0, 20261012, 0)
	if generated.is_empty():
		_fail("generate_from_level_plan 返回空")
		_finish()
		return
	print("--- plan ---")
	print("valid=%s mode=%s layout_id=%s rooms=%d" % [
		str(generated.get("valid", false)), str(generated.get("mode", "")),
		str(generated.get("layout_id", "")), (generated.get("rooms", []) as Array).size()])
	print("main_path=%s" % str(generated.get("main_path_keys", [])))
	print("content=%s branch=%s branch_rooms=%s terminal=%s" % [
		str(generated.get("content_room_count", -1)), str(generated.get("branch_count", -1)),
		str(generated.get("branch_room_count", -1)), str(generated.get("terminal_mode", ""))])
	var errors := generated.get("validation_errors", []) as Array
	print("validation_errors(%d):" % errors.size())
	for error_value in errors:
		print("   %s" % str(error_value))
		_fail("validator: %s" % str(error_value))

	var total_area := 0.0
	for value in generated.get("rooms", []) as Array:
		var room := value as Dictionary
		var dim := room.get("dimensions", Vector2.ZERO) as Vector2
		var pos := room.get("position", Vector2.ZERO) as Vector2
		total_area += dim.x * dim.y
		print("  %-9s %-12s %-7s parent=%-9s pos=(%7.1f,%7.1f) size=(%4.0f,%4.0f) ports=%d" % [
			str(room.get("key", "")), str(room.get("role", "")),
			str(room.get("type", "")),
			str(room.get("parent_key", "")) if str(room.get("parent_key", "")) != "" else "-",
			pos.x, pos.y, dim.x, dim.y,
			(room.get("connection_ports", []) as Array).size()])
	print("总面积: %.0f m²" % total_area)

	# ---- 每个连接端口必须带**可用的 side** ----
	# 这一段同样是**事后补的**。`LevelPlanLoader` 曾静默丢掉端口的 `side`
	# （白盒端口只写 position_m + outward），于是运行时
	# `_declare_and_register_edge()` 取到空 side、两门坐标退化成房间中心 ⇒
	# 相邻房之间凭空长出通用走廊：**实测 23/25 条边中招，
	# 多出 286 段墙 / 143 块地板 / 46 个挡人碰撞体**，实机表现是
	# 「开了阳台→room_01 的门，刷出一堆墙、排列很糟糕、很多空空洞」。
	# 门数与门的可交互性都没报错，所以这条只能靠"端口 side 非空且与几何一致"来堵。
	var side_issues: Array[String] = []
	var port_total := 0
	for value in generated.get("rooms", []) as Array:
		var room := value as Dictionary
		var dim := room.get("dimensions", Vector2.ZERO) as Vector2
		var room_key := str(room.get("key", ""))
		for port_value in room.get("connection_ports", []) as Array:
			var port := port_value as Dictionary
			port_total += 1
			var side := str(port.get("side", ""))
			var port_id := str(port.get("port_id", ""))
			if side.is_empty():
				side_issues.append("%s/%s side 为空" % [room_key, port_id])
				continue
			# side 必须与「端口压在房间哪条边界上」一致（同一套判据见
			# `LevelPlanLoader._side_from_room_boundary` 与
			# `FloorPlanGenerator._connection_port_is_on_room_boundary`）。
			var raw := port.get("position_m", []) as Array
			if raw.size() < 2 or dim.x <= 0.0 or dim.y <= 0.0:
				side_issues.append("%s/%s 缺少可判定的 position_m/尺寸" % [room_key, port_id])
				continue
			var position := Vector2(float(raw[0]), float(raw[1]))
			var expected := LOADER._side_from_room_boundary(position, dim)
			if expected != side:
				side_issues.append(
					"%s/%s side=%s 与几何应得 %s 不符（local=%s size=%s）"
					% [room_key, port_id, side, expected, str(position), str(dim)]
				)
	if port_total == 0:
		_fail("设计源一个连接端口都没有 —— 26 房共墙拓扑不可能没有端口")
	elif not side_issues.is_empty():
		for issue in side_issues:
			_fail("连接端口 side 不可用: %s" % issue)
	else:
		print("连接端口 side 全部可用且与几何一致 ✓（%d 个）" % port_total)

	# ---- 运行时静态布局路径 ----
	# 这一段是**事后补的**。之前只验了 L2 合法（valid=true、26 房），**没验运行时 record
	# 拿到什么路径** —— 于是「路径目录写死成 expedition_01」这种错一路溜到实机，
	# 表现是「进去后用的是远征01 的素材拼接」。
	#
	# 直接调 `TowerDescent3D.expedition_static_layout_path()` 真身，**不复刻拼接规则** ——
	# 复刻出来的探针测不到真身，正是那条 bug 溜过去的原因。
	var tower_script: GDScript = load("res://src/world3d/TowerDescent3D.gd")
	if tower_script == null:
		_fail("TowerDescent3D.gd 加载失败")
		_finish()
		return
	if not tower_script.has_method("expedition_static_layout_path"):
		_fail("TowerDescent3D 缺 expedition_static_layout_path() —— 路径拼接规则没抽出来")
		_finish()
		return
	var plan_level_id := str(plan.get("level_id", LEVEL_ID))
	var runtime_rooms := generated.get("rooms", []) as Array
	print("运行时布局路径核对（level_id=%s）:" % plan_level_id)
	var missing_layouts: Array[String] = []
	var foreign_level_layouts: Array[String] = []
	for value in runtime_rooms:
		var room := value as Dictionary
		var runtime_id := str(room.get("id", ""))
		var layout_path := str(tower_script.call(
			"expedition_static_layout_path", plan_level_id, runtime_id
		))
		if not ResourceLoader.exists(layout_path):
			missing_layouts.append("%s -> %s" % [runtime_id, layout_path])
		if layout_path.contains("/expedition_01/"):
			foreign_level_layouts.append(runtime_id)
	if missing_layouts.is_empty():
		print("  全部 %d 间都有布局 ✓" % runtime_rooms.size())
	else:
		for item in missing_layouts:
			print("  缺: %s" % item)
		_fail("有 %d 间房缺静态布局 —— 会静默回退到程序化生成（不是本关美术）" % missing_layouts.size())
	if not foreign_level_layouts.is_empty():
		_fail("布局路径指向 expedition_01: %s" % str(foreign_level_layouts))

	# ---- 入口房的运行时 ID 必须是 `start` ----
	# `TowerDescent3D` 三处按 `room_id == "start"` 取房（出生点、安全房尺寸、HUD 标签）。
	# 写成别的值不会报错，只会**出生点静默失效** —— 玩家不在阳台。
	var has_start := false
	for value in runtime_rooms:
		if str((value as Dictionary).get("id", "")) == "start":
			has_start = true
			break
	if not has_start:
		_fail(
			"没有 room.id == \"start\" —— 出生点 `_room_by_id.get(\"start\")` 会取到 null，"
			+ "玩家不会落在入口安全屋"
		)
	else:
		print("入口房 id = start ✓")

	_finish()


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("EXPEDITION02_LEVEL_PLAN_VERIFY_OK")
		get_tree().quit(0)
		return
	print("EXPEDITION02_LEVEL_PLAN_VERIFY_FAILED count=%d" % failures.size())
	for failure in failures:
		print("FAIL %s" % failure)
	get_tree().quit(1)
