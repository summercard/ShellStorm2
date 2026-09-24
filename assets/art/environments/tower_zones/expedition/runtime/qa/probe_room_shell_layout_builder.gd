extends SceneTree
## 组合器自检：用 RoomShellLayoutBuilder3D 重放**区块00 已验收摆位源**的四间房，
## 再与摆位源自身的 corners / corners_dropped / wall_lanes / instances 逐值对照。
##
## 这是「算法替不等于源」的反假绿基线：区块00 的布局源已在运行时验收通过
## （verify_block00_floor98_assembly，checks=230），所以只要组合器能从
## 「房间尺寸 + 门位 + 邻接」重算出一模一样的 90 件实例，就证明全局 lane 归属、
## L 臂预留、共面去重、共角去重、棋盘地砖这五条规则都对。
##
## 运行：godot --headless --path . --script <本文件>
## 通过输出：ROOM_SHELL_LAYOUT_BUILDER_OK pass=<n> fail=0

const BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")
## 区块00 的**生产路径**（布局源 → 运行时实例字典）。用它当运行时形状的参照系。
const BLOCK00_PRODUCTION := preload("res://src/world3d/Block00MasterOfficeLayout3D.gd")
const LAYOUT_PATH := (
	"res://source/art/blender/master_office_layout/source/"
	+ "block_00_master_office_layout_v002.layout.json"
)
const EPSILON := 0.0001
## 运行时通用壳体注册表：把批次号与通用件名统一到同一个 `component_id`。
## 两侧写不同的 ID 但指向同一件 prefab 是**有意契约**（双 ID 别名），不是差异。
const REGISTRY_PATH := (
	"res://assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
)

var _pass := 0
var _fail := 0
var _messages: Array[String] = []
var _canonical_ids: Dictionary = {}


func _initialize() -> void:
	_load_canonical_ids()
	_expect(
		_canonical_ids.size() > 0,
		"运行时通用壳体注册表可读，别名可归一（已登记 %d 个 ID）" % _canonical_ids.size()
	)
	var text := _read_text(LAYOUT_PATH)
	if text.is_empty():
		_fail += 1
		print("ROOM_SHELL_LAYOUT_BUILDER_FAIL 摆位源读不到 %s" % LAYOUT_PATH)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_fail += 1
		print("ROOM_SHELL_LAYOUT_BUILDER_FAIL 摆位源不是 JSON 对象")
		quit(1)
		return
	var source := parsed as Dictionary
	_expect(
		str(source.get("schema", "")) == "shellstorm2.battle.room_instance_layout",
		"摆位源 schema 为 shellstorm2.battle.room_instance_layout"
	)

	var rooms := _input_rooms(source)
	_expect(rooms.size() == 4, "区块00 四间房都能转成组合器输入（实得 %d）" % rooms.size())
	var built := BUILDER.build_block(rooms)
	for message in built.get("errors", []) as Array:
		_fail += 1
		_messages.append("builder_error: %s" % str(message))
	_expect((built.get("errors", []) as Array).is_empty(), "组合器无报错（实得 %d 条）" % (
		built.get("errors", []) as Array).size())

	# —— 角件 ——
	_expect(
		(built["corners"] as Array).size() == (source["corners"] as Array).size(),
		"角件数一致（源 %d / 实得 %d）" % [
			(source["corners"] as Array).size(), (built["corners"] as Array).size()
		]
	)
	_compare_rows(
		_keyed_rows(source["corners"] as Array, "corner"),
		_keyed_rows(built["corners"] as Array, "corner"),
		["room_id", "corner_id", "rotation_z_deg", "point_m"],
		"corner"
	)
	# —— 被邻房顶掉的角件 ——
	_expect(
		(built["corners_dropped"] as Array).size()
			== (source["corners_dropped"] as Array).size(),
		"corners_dropped 数一致（源 %d / 实得 %d）" % [
			(source["corners_dropped"] as Array).size(),
			(built["corners_dropped"] as Array).size()
		]
	)
	_compare_rows(
		_keyed_rows(source["corners_dropped"] as Array, "dropped"),
		_keyed_rows(built["corners_dropped"] as Array, "dropped"),
		["room_id", "corner_id", "provided_by", "point_m"],
		"corners_dropped"
	)
	# —— 墙平面 lane ——
	_expect(
		(built["wall_lanes"] as Array).size() == (source["wall_lanes"] as Array).size(),
		"wall_lanes 数一致（源 %d / 实得 %d）" % [
			(source["wall_lanes"] as Array).size(), (built["wall_lanes"] as Array).size()
		]
	)
	_compare_rows(
		_keyed_rows(source["wall_lanes"] as Array, "wall_lane"),
		_keyed_rows(built["wall_lanes"] as Array, "wall_lane"),
		["axis", "line_m", "lane_key", "center_m", "role", "owner_room",
			"rotation_z_deg", "claims"],
		"wall_lane"
	)
	# —— 实例（逐 instance_id 对齐）——
	var source_instances := _index_by_id(source["instances"] as Array)
	var built_instances := _index_by_id(built["instances"] as Array)
	_expect(
		source_instances.size() == (source["instances"] as Array).size(),
		"源实例 instance_id 唯一（%d 件）" % source_instances.size()
	)
	_expect(
		built_instances.size() == (built["instances"] as Array).size(),
		"组合器实例 instance_id 唯一（%d 件）" % built_instances.size()
	)
	_compare_instance_sets(source_instances, built_instances)
	# —— slot_role 计数（源 validation 里也声明了一份）——
	var source_counts := (
		((source.get("validation", {}) as Dictionary).get("slot_role_counts", {})) as Dictionary
	)
	_compare_role_counts(source_counts, built["slot_role_counts"] as Dictionary, "validation")
	# —— 运行时形状往返：与区块00 生产路径 room_shell_instances() 逐件对照 ——
	# 这一层才是真正喂给 DungeonRoom3D.authored_layout_instances 的东西；
	# 只比区块00 自己也产出的件（门扇预览件在生产路径里被跳过）。
	for value in rooms:
		var room := value as Dictionary
		var room_id := str(room["room_id"])
		var bounds_x := room["bounds_x_m"] as Array
		var bounds_y := room["bounds_y_m"] as Array
		var center_bx := (float(bounds_x[0]) + float(bounds_x[1])) * 0.5
		var center_by := (float(bounds_y[0]) + float(bounds_y[1])) * 0.5
		var mine := _runtime_index(
			BUILDER.to_runtime_instances(built["instances"] as Array, room_id, center_bx, center_by)
		)
		var theirs := _runtime_index(
			BLOCK00_PRODUCTION.room_shell_instances(
				source, room_id, Vector2(center_bx, center_by)
			)
		)
		_expect(
			theirs.size() > 0,
			"区块00 生产路径对 %s 产出运行时实例（%d 件）" % [room_id, theirs.size()]
		)
		for key_value in theirs.keys():
			var key := str(key_value)
			if not mine.has(key):
				_expect(false, "运行时形状 %s 不缺件（缺 %s）" % [room_id, key])
				continue
			var left := theirs[key] as Dictionary
			var right := mine[key] as Dictionary
			for field_value in ["slot_role", "corner_id", "rotation_y_deg"]:
				var field := str(field_value)
				_expect(
					str(left.get(field, "")) == str(right.get(field, "")),
					"运行时 %s.%s：源 %s / 实得 %s" % [
						key, field, str(left.get(field)), str(right.get(field))
					]
				)
			_expect(
				_canonical_id(str(left.get("component_id", "")))
					== _canonical_id(str(right.get("component_id", ""))),
				"运行时 %s.component_id：源 %s / 实得 %s" % [
					key, str(left.get("component_id")), str(right.get("component_id"))
				]
			)
			_expect(
				_vector3_close(
					left.get("position", Vector3.ZERO) as Vector3,
					right.get("position", Vector3.ZERO) as Vector3
				),
				"运行时 %s.position：源 %s / 实得 %s" % [
					key, str(left.get("position")), str(right.get("position"))
				]
			)
	_finalize()


func _runtime_index(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in rows:
		var row := value as Dictionary
		result[str(row.get("name", ""))] = row
	return result


func _vector3_close(left: Vector3, right: Vector3) -> bool:
	return (
		absf(left.x - right.x) <= EPSILON
		and absf(left.y - right.y) <= EPSILON
		and absf(left.z - right.z) <= EPSILON
	)


func _compare_role_counts(source_counts: Dictionary, built_counts: Dictionary, label: String) -> void:
	var roles: Array = ["corner_l", "solid_wall", "door_wall", "door_leaf_preview", "floor_tile"]
	for role_value in roles:
		var role := str(role_value)
		_expect(
			int(built_counts.get(role, 0)) == int(source_counts.get(role, -1)),
			"slot_role %s 计数：源 %d / 实得 %d" % [
				role, int(source_counts.get(role, -1)), int(built_counts.get(role, 0))
			]
		)


## 对照两组「按 instance_id 索引」的实例字典：先比键集合，再逐字段比共有键。
func _compare_instance_sets(source: Dictionary, built: Dictionary) -> void:
	var missing: Array[String] = []
	var extra: Array[String] = []
	for key_value in source.keys():
		if not built.has(key_value):
			missing.append(str(key_value))
	for key_value in built.keys():
		if not source.has(key_value):
			extra.append(str(key_value))
	_expect(missing.is_empty(), "组合器没有漏掉源实例（漏 %d）%s" % [
		missing.size(), _preview(missing)
	])
	_expect(extra.is_empty(), "组合器没有多出源没有的实例（多 %d）%s" % [
		extra.size(), _preview(extra)
	])
	var fields: Array = [
		"component_id", "slot_role", "position_m", "rotation_z_deg", "package",
		"room_id", "scale", "enabled",
	]
	for key_value in source.keys():
		var key := str(key_value)
		if not built.has(key):
			continue
		var left := source[key] as Dictionary
		var right := built[key] as Dictionary
		for field_value in fields:
			var field := str(field_value)
			if not left.has(field) and not right.has(field):
				continue
			if field == "component_id":
				# 双 ID 契约：批次号与通用件名归一后再比。
				_expect(
					_canonical_id(str(left.get(field))) == _canonical_id(str(right.get(field))),
					"%s.%s：源 %s / 实得 %s（归一后应同件）" % [
						key, field, str(left.get(field)), str(right.get(field))
					]
				)
				continue
			_expect(
				_value_equal(left.get(field), right.get(field)),
				"%s.%s：源 %s / 实得 %s" % [
					key, field, str(left.get(field)), str(right.get(field))
				]
			)
		# 只在源里出现的可选字段也照比（corner_id / grid / side / lane_key / claims / shared_with）
		for field_value in ["corner_id", "grid", "side", "lane_key", "claims", "shared_with"]:
			var field := str(field_value)
			if not left.has(field):
				continue
			_expect(
				_value_equal(left.get(field), right.get(field)),
				"%s.%s：源 %s / 实得 %s" % [
					key, field, str(left.get(field)), str(right.get(field))
				]
			)


func _compare_rows(source: Dictionary, built: Dictionary, fields: Array, label: String) -> void:
	_expect(
		source.size() == built.size(),
		"%s 行数一致（源 %d / 实得 %d）" % [label, source.size(), built.size()]
	)
	var missing: Array[String] = []
	for key_value in source.keys():
		if not built.has(key_value):
			missing.append(str(key_value))
	_expect(missing.is_empty(), "%s 无缺失行（缺 %d）%s" % [
		label, missing.size(), _preview(missing)
	])
	for key_value in source.keys():
		var key := str(key_value)
		if not built.has(key):
			continue
		var left := source[key] as Dictionary
		var right := built[key] as Dictionary
		for field_value in fields:
			var field := str(field_value)
			_expect(
				_value_equal(left.get(field), right.get(field)),
				"%s[%s].%s：源 %s / 实得 %s" % [
					label, key, field, str(left.get(field)), str(right.get(field))
				]
			)


## 键：角件 = room_id|corner_id；墙 lane = axis|line|lane_key；dropped = room_id|corner_id。
func _keyed_rows(rows: Array, kind: String) -> Dictionary:
	var result: Dictionary = {}
	for value in rows:
		var row := value as Dictionary
		var key := ""
		match kind:
			"corner", "dropped":
				key = "%s|%s" % [str(row.get("room_id", "")), str(row.get("corner_id", ""))]
			_:
				key = "%s|%s|%d" % [
					str(row.get("axis", "")),
					_number(str(row.get("line_m", 0.0))),
					int(row.get("lane_key", 0)),
				]
		result[key] = row
	return result


func _index_by_id(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in rows:
		var row := value as Dictionary
		result[str(row.get("instance_id", ""))] = row
	return result


## 组合器输入：从摆位源的 rooms 段取，只带几何与门位（带进 rooms 段之外的字段反而会掩盖差异）。
func _input_rooms(source: Dictionary) -> Array:
	var result: Array = []
	for value in source.get("rooms", []):
		var room := value as Dictionary
		result.append({
			"room_id": str(room.get("room_id", "")),
			"bounds_x_m": room.get("bounds_x_m", []),
			"bounds_y_m": room.get("bounds_y_m", []),
			"doors": room.get("doors", {}),
			"exits": room.get("exits", {}),
			"use_corner_l": bool(room.get("use_corner_l", true)),
		})
	return result


func _value_equal(left: Variant, right: Variant) -> bool:
	if left == null and right == null:
		return true
	if left is Array and right is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return false
		for index in range(left_array.size()):
			if not _value_equal(left_array[index], right_array[index]):
				return false
		return true
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left) - float(right)) <= EPSILON
	return str(left) == str(right)


func _number(value: String) -> String:
	var parsed := float(value)
	if absf(parsed - roundf(parsed)) <= EPSILON:
		return str(int(roundf(parsed)))
	return str(parsed)


func _preview(values: Array[String]) -> String:
	if values.is_empty():
		return ""
	var head: Array[String] = []
	for index in range(mini(6, values.size())):
		head.append(values[index])
	return " [" + ", ".join(head) + "]"


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 组件 ID → 通用件名（registry 的 `component_id`）；未登记的原样返回，让差异照样报出来。
func _canonical_id(component_id: String) -> String:
	if _canonical_ids.has(component_id):
		return str(_canonical_ids[component_id])
	return component_id


func _load_canonical_ids() -> void:
	var text := _read_text(REGISTRY_PATH)
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var catalog := parsed as Dictionary
	for value in catalog.get("components", []):
		if not (value is Dictionary):
			continue
		var entry := value as Dictionary
		var component_id := str(entry.get("component_id", ""))
		if component_id.is_empty():
			continue
		_canonical_ids[component_id] = component_id
		var alias_list: Array = entry.get("aliases", [])
		for alias_value in alias_list:
			_canonical_ids[str(alias_value)] = component_id


func _expect(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		return
	_fail += 1
	_messages.append(label)


func _finalize() -> void:
	if _fail == 0:
		print("ROOM_SHELL_LAYOUT_BUILDER_OK pass=%d fail=0" % _pass)
		quit(0)
		return
	print("ROOM_SHELL_LAYOUT_BUILDER_FAIL pass=%d fail=%d" % [_pass, _fail])
	for message in _messages:
		print("  - %s" % message)
	quit(1)
