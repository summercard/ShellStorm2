class_name Block00MasterOfficeLayout3D
extends RefCounted
## 区块00-主人的办公室：把 Blender 摆位源（schema `shellstorm2.battle.room_instance_layout`）
## 翻译成塔楼 98F 的运行时房间表 + 每个房间的授权壳体实例清单。
##
## 本类只做「源 → 运行时数据」的翻译与自检，**不碰场景树**：
##   · build_plan_override()  —— 用区块00 四房拓扑替换 98F plan 的 rooms；
##   · room_shell_instances() —— 逐房给出授权壳体实例（房间局部坐标）；
##   · visual_footprints()    —— 逐房足迹，交塔楼楼层台座挖掉整层通用地砖。
## 真正的节点装配在 DungeonRoom3D._build_authored_layout_shell()。
##
## —— 坐标契约（2026-09-20 实测钉死，勿凭 JSON 里的 coordinate_contract 反推）——
## Blender Z-up：X=东、Y=北。塔楼平面约定 planar +y = 世界 +z = 南
## （见 TowerDescent3D._plan_world_position 与 RoomDoorLane.port_pair 的注释）。
## 于是「Blender 平面 → Godot 平面」是绕 X 轴 −90° 的**真旋转**（det=+1，非镜像）：
##     world.x = bx
##     world.z = −by + planar_z_shift
##     rotation.y = deg_to_rad(rotation_z_deg)     # 同号，不是 180−rot
## 判据三条，互相独立、指向同一组解：
##   1. **L 角件手性**：摆位源 corner_rotation_deg = {SW:0, SE:90, NE:180, NW:−90}，
##      且组件原点=角点、两臂沿 +X/+Y。塔楼 prp_corner_l_5m 在 rot0 是
##      「长臂 +X / 短臂 −Z」。两者并列 ⇒ Blender +Y ↔ Godot −Z。
##      若取 world.z = +by 则翻手性，SW 角会被摆成 NW 角（外扩臂朝房外）。
##   2. **装饰面朝向**：wall_standard_5m 的 forward_axis = −Z（装饰面朝 −Z）；
##      摆位源 face_in_rotation_deg 里「南墙 rot 0」表示装饰面朝 +Y（房内在 +Y 侧）。
##      rot0 在 Godot 侧 ⇒ 装饰面朝 −Z ⇒ 该墙落在 world.z 较大的一侧 = 南 ✓
##      与 Godot「+z = 南」一致（若取 +by 则南北会整体翻面）。
##   3. **锚点**：摆位源 entry = Blender(35, 2.5)，note 明写「原 99→98 楼梯间末端门位」；
##      运行时实测 98F 楼梯下端落点 = world(35, −24, 2.5)
##      （probe_block00_floor98_baseline 输出的 Door_East）。
##      ⇒ planar_z_shift 由「门厅东墙中心的世界 z 必须等于入口房中心 z」反解，
##      不硬编码 —— 见 _resolve_planar_z_shift()。
## 同一锚点还给出第二个自洽结果：门厅 Blender x[20,35] y[−5,10] → world
## x[20,35] z[−5,10]，与 98F 既有 STAIR_LOBBY 的 15×15 足迹逐值相同。
##
## 摆位源的 coordinate_contract 只给了「轴映射」（Blender(x,y) → Godot(x,−z)，rotation 同号），
## 那是**块内相对关系**，是对的；它缺的是「这一块整体落在塔楼哪个位置」。
## 直接按 position_m 摆会把门厅放到 z∈[−10,5]，东出口落到 z=−2.5，
## 与 98F 楼梯下端 z=2.5 差 5m。差的那一项就是本类的 planar_z_shift，
## 由「门厅东墙中心必须与 98F 入口房中心同 z」反解，不硬编码。

const LAYOUT_MANIFEST_PATH := (
	"res://source/art/blender/master_office_layout/source/"
	+ "block_00_master_office_layout_v002.layout.json"
)
const LAYOUT_SCHEMA := "shellstorm2.battle.room_instance_layout"
const LAYOUT_ASSET_ID := "ENV-BATTLE-BLOCK00-ART-LAYOUT-3D"
const LAYOUT_VERSION := "v002"
const BLOCK_ID := "master_office"
## 摆位源的 `floor_anchor` = 98F（floor_index 2，世界 Y = −12×2 = −24）。
const FLOOR_INDEX := 2
const FLOOR_NUMBER := 98
const GRID_UNIT_M := 5.0
## entry 指向的是「99→98 楼梯间末端门位」，运行时楼梯下端就落在入口房东墙上。
## 这里只声明「入口房的哪一面墙是楼梯落点」，具体坐标由 base_plan 的入口房推出。
const ENTRY_STAIR_SIDE := "east"

## 摆位源房间 → 塔楼盘面的绑定。
## key / id 沿用原 98F 规划里的同名键：存档 room_progress、到达门事务、门槽算法
## 都按老 id/键找房间，换掉整层拓扑但保留 id 可以把存档影响压到最小。
## parent_key 决定水平门边（区块00 的房间是相邻共墙，门到门距离 0 ⇒ 塔楼
## 水平走廊连接器自带 length<=0.05 短路，不生成几何，只留状态节点）。
const ROOM_BINDINGS: Array = [
	{
		"key": "entry", "id": "floor_01_entry", "type": "STAIR_LOBBY",
		"role": "stair_entry", "parent_key": "", "authored_room_id": "lobby",
	},
	{
		"key": "hub", "id": "floor_01_hub", "type": "COMBAT",
		"role": "hub", "parent_key": "entry", "authored_room_id": "corridor",
	},
	{
		"key": "main_02", "id": "floor_01_main_02", "type": "COMBAT",
		"role": "main", "parent_key": "hub", "authored_room_id": "meeting_room",
	},
	{
		"key": "exit", "id": "floor_01_exit", "type": "COMBAT",
		"role": "stair_exit", "parent_key": "main_02", "authored_room_id": "master_office",
	},
]

## 摆位源自身的 slot_role → 期望实例数（反假绿基线）。
## 与 .godot.json 的 instance_counts 逐值一致，任一侧漂移即报错。
const EXPECTED_SLOT_ROLE_COUNTS := {
	"corner_l": 11,
	"solid_wall": 23,
	"door_wall": 4,
	"door_leaf_preview": 3,
	"floor_tile": 49,
}
## 摆位源里 `door_leaf_preview` 是编辑器预览件，运行时由 RoomDoor3D 生成唯一门扇，
## 必须跳过；其余角色全部实例化。
const SKIPPED_SLOT_ROLES: Array[String] = ["door_leaf_preview"]
## 壳体实例里「自持地砖」的角色：内嵌静态碰撞必须关掉，承重归 TowerFloorStage3D。
const FLOOR_TILE_SLOT_ROLE := "floor_tile"

## —— 和平区（2026-09-20 主人要求）——
## 区块00 是叙事固定关卡，不是战斗楼层：区域内
##   ① 门**只做普通开关**（无清房 / 无钥匙 / 无命运卡）；
##   ② **不刷怪**（四房全部，含入口门厅）；
##   ③ 门扇直接沿用 **99F 基地的滑升门**（`BASE99_DOOR_LIFT_PREFAB`），不另造门美术。
## 声明点只此一处：`build_plan_override()` 把 `authored_layout_peaceful` 落到房间 spec，
## 逐层透传 record → DungeonRoom3D，由 Dungeon3D 的三个消费点读它。
## ⚠️ 门策略（requires_clear/key/fate）由 `Dungeon3D._door_policies_for_record` 统一覆盖，
## 不在 `_door_policy_for_edge` 里按 room_id 逐边列举 —— 那样每加一扇门都要改一趟。
const PEACEFUL_ZONE := true


## 读摆位源。失败一律返回空字典 + 报错，由调用方回退内置房表（绝不静默换布局）。
static func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_MANIFEST_PATH):
		push_error("Block00Layout: 摆位源缺失 %s" % LAYOUT_MANIFEST_PATH)
		return {}
	var text := FileAccess.get_file_as_string(LAYOUT_MANIFEST_PATH)
	if text.is_empty():
		push_error("Block00Layout: 摆位源为空 %s" % LAYOUT_MANIFEST_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Block00Layout: 摆位源不是 JSON 对象 %s" % LAYOUT_MANIFEST_PATH)
		return {}
	var manifest := parsed as Dictionary
	if str(manifest.get("schema", "")) != LAYOUT_SCHEMA:
		push_error(
			"Block00Layout: schema 不匹配（期望 %s，实得 %s）"
			% [LAYOUT_SCHEMA, str(manifest.get("schema", ""))]
		)
		return {}
	return manifest


## 摆位源自检。返回错误列表（空 = 通过）。全部期望值都从摆位源自己的
## 声明推出，或与 .godot.json 的 instance_counts 对齐，不写死摆位结果。
static func validate_manifest(manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if manifest.is_empty():
		errors.append("manifest_empty")
		return errors
	var instances := manifest.get("instances", []) as Array
	if instances.is_empty():
		errors.append("instances_empty")
		return errors
	var role_counts: Dictionary = {}
	for value in instances:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		if str(instance.get("component_id", "")).is_empty():
			errors.append("instance_without_component_id:%s" % str(instance.get("instance_id", "")))
		if not bool(instance.get("enabled", true)):
			errors.append("instance_disabled:%s" % str(instance.get("instance_id", "")))
	for role_value in EXPECTED_SLOT_ROLE_COUNTS.keys():
		var role := str(role_value)
		var expected := int(EXPECTED_SLOT_ROLE_COUNTS[role])
		var actual := int(role_counts.get(role, 0))
		if actual != expected:
			errors.append("slot_role_count:%s expected=%d actual=%d" % [role, expected, actual])
	var declared := manifest.get("validation", {}) as Dictionary
	var declared_roles := declared.get("slot_role_counts", {}) as Dictionary
	for role_value in EXPECTED_SLOT_ROLE_COUNTS.keys():
		var role := str(role_value)
		if int(declared_roles.get(role, -1)) != int(EXPECTED_SLOT_ROLE_COUNTS[role]):
			errors.append("manifest_validation_slot_role_count:%s" % role)
	if bool(declared.get("room_owned_geometry", true)):
		errors.append("manifest_claims_room_owned_geometry")
	# 每个绑定房间必须在摆位源里存在，且四边落在 5m 格线上。
	var room_lookup := _room_lookup(manifest)
	for value in ROOM_BINDINGS:
		var binding := value as Dictionary
		var room_id := str(binding["authored_room_id"])
		var room := room_lookup.get(room_id, {}) as Dictionary
		if room.is_empty():
			errors.append("binding_room_missing:%s" % room_id)
			continue
		var bounds := _room_bounds(room)
		for axis in ["x", "y"]:
			for endpoint in [0, 1]:
				var coordinate := float((bounds[axis] as Array)[endpoint])
				if not is_zero_approx(fmod(absf(coordinate), GRID_UNIT_M)):
					errors.append("room_bound_off_grid:%s:%s=%s" % [room_id, axis, str(coordinate)])
		if str(room.get("room_id", "")) != room_id:
			errors.append("room_id_field_mismatch:%s" % room_id)
	return errors


## 用区块00 四房拓扑替换 98F plan 的 rooms。
##
## 保留 base_plan 的其余字段（尤其 layout_id）不动 —— 存档按
## `floor_layout_ids[floor_index]` 比对，layout_id 变了整档恢复会直接失败
## （TowerDescent3D 恢复路径的 `Runtime floor layout mismatch`）。
## 房间 id 也沿用同名键，房间级进度（room_progress）不会因为换拓扑而丢。
##
## 返回空字典 = 本层不该走区块00（源不可用 / 自检失败），调用方回退内置房表。
static func build_plan_override(base_plan: Dictionary) -> Dictionary:
	var base_entry := _plan_spec(base_plan, "entry")
	if base_entry.is_empty():
		push_error("Block00Layout: base_plan 缺少 entry，无法推导锚点")
		return {}
	var manifest := load_manifest()
	var errors := validate_manifest(manifest)
	if not errors.is_empty():
		for message in errors:
			push_error("Block00Layout 自检失败: %s" % message)
		return {}
	var anchor_position := base_entry.get("position", Vector2.ZERO) as Vector2
	var anchor_size := base_entry.get("dimensions", Vector2.ZERO) as Vector2
	var result := base_plan.duplicate(true)
	var rooms: Array = []
	var shifts: Array[float] = []
	for value in ROOM_BINDINGS:
		var binding := value as Dictionary
		var room_id := str(binding["authored_room_id"])
		var room := _room_lookup(manifest).get(room_id, {}) as Dictionary
		if room.is_empty():
			push_error("Block00Layout: 摆位源缺少房间 %s" % room_id)
			return {}
		var planar_corners := _room_planar_corners(room, 0.0)
		var planar_position := (
			planar_corners[0] + planar_corners[1]
		) * 0.5
		var dimensions := (planar_corners[1] - planar_corners[0]).abs()
		var shift := 0.0
		if room_id == str(ROOM_BINDINGS[0]["authored_room_id"]):
			# 入口房（门厅）的楼梯侧墙中心就是 99→98 楼梯下端落点：
			# 由 base_plan 的入口房推出目标点，再反解平面 z 平移量。
			var resolved: Variant = _resolve_planar_z_shift(room, anchor_position, anchor_size)
			if resolved == null:
				push_error("Block00Layout: 无法把门厅楼梯侧墙对齐到入口房锚点")
				return {}
			shift = float(resolved)
			planar_corners = _room_planar_corners(room, shift)
			planar_position = (planar_corners[0] + planar_corners[1]) * 0.5
			dimensions = (planar_corners[1] - planar_corners[0]).abs()
		else:
			shift = float(shifts[0])
			planar_corners = _room_planar_corners(room, shift)
			planar_position = (planar_corners[0] + planar_corners[1]) * 0.5
			dimensions = (planar_corners[1] - planar_corners[0]).abs()
		shifts.append(shift)
		rooms.append({
			"key": str(binding["key"]),
			"id": str(binding["id"]),
			"type": str(binding["type"]),
			"role": str(binding["role"]),
			"parent_key": str(binding["parent_key"]),
			"position": planar_position,
			"dimensions": dimensions,
			"authored_layout_shell": true,
			"authored_layout_asset_id": LAYOUT_ASSET_ID,
			"authored_layout_version": LAYOUT_VERSION,
			"authored_layout_room_id": room_id,
			"authored_layout_peaceful": PEACEFUL_ZONE,
			"authored_layout_instances": room_shell_instances(manifest, room_id, planar_position),
		})
	# 入口房锚点必须逐值命中 base_plan 的入口房：位置与尺寸都不能动，
	# 否则 99→98 竖梯的下端门位、seed gate 与到达门事务会一起错位。
	var first := rooms[0] as Dictionary
	if not (first["position"] as Vector2).is_equal_approx(anchor_position):
		push_error(
			"Block00Layout: 门厅落位 %s 与 98F 入口房锚点 %s 不一致"
			% [str(first["position"]), str(anchor_position)]
		)
		return {}
	if not (first["dimensions"] as Vector2).is_equal_approx(anchor_size):
		push_error(
			"Block00Layout: 门厅尺寸 %s 与 98F 入口房 %s 不一致"
			% [str(first["dimensions"]), str(anchor_size)]
		)
		return {}
	result["rooms"] = rooms
	# 主路 = 走廊 → 会议室（区块00 只有这两间内容房；入口与出口是功能房）。
	result["main_path_keys"] = ["hub", "main_02"]
	result["main_path_content_count"] = 2
	result["branch_count"] = 0
	result["branch_room_count"] = 0
	result["content_room_count"] = rooms.size()
	# 下行走**办公室西墙**（摆位源 x=−40 那道）：生成器对 98F 本来就算出 west
	# （exit_side = 入口侧 east 的对侧），这里显式钉一遍 —— 它是「下行楼梯开在哪一侧」
	# 的唯一来源（TowerDescent3D._append_next_arrival_shell 读它建竖直边），
	# 一旦回退到生成器的旧 exit 房（x=−22.5 的 15×15 出口厅）就会把楼梯修到别处。
	result["exit_side"] = "west"
	result["authored_layout"] = true
	result["authored_layout_asset_id"] = LAYOUT_ASSET_ID
	result["authored_layout_version"] = LAYOUT_VERSION
	# 整层和平区：探针按这条断言「本层不刷怪、门策略全放行」，不必逐房去问。
	result["authored_layout_peaceful"] = PEACEFUL_ZONE
	result["authored_layout_planar_z_shift_m"] = float(shifts[0])
	return result


## 逐房授权壳体实例（**房间局部坐标**）。摆位源里每个实例都归属唯一 room_id，
## 所以「四房各建各的」不会重复也不会漏；房间之间共用的那道墙只归它声明的房间。
## 局部换算：world = (bx, −by + shift)，房间中心 world 已含同一个 shift ⇒
##     local = (bx − cx, 0, −(by − cy))
## 房间本身不旋转（区块00 是轴对齐布局），所以 rotation_y 直接沿用 rotation_z_deg。
static func room_shell_instances(
	manifest: Dictionary, authored_room_id: String, planar_center: Vector2
) -> Array:
	var result: Array = []
	if manifest.is_empty():
		return result
	var room := _room_lookup(manifest).get(authored_room_id, {}) as Dictionary
	if room.is_empty():
		push_error("Block00Layout: 摆位源缺少房间 %s，无法导出壳体实例" % authored_room_id)
		return result
	var bounds := _room_bounds(room)
	var center_bx := (float((bounds["x"] as Array)[0]) + float((bounds["x"] as Array)[1])) * 0.5
	var center_by := (float((bounds["y"] as Array)[0]) + float((bounds["y"] as Array)[1])) * 0.5
	if not is_equal_approx(planar_center.x, center_bx):
		push_error(
			"Block00Layout: 房间 %s 平面中心 x=%s 与摆位源 %s 不一致"
			% [authored_room_id, str(planar_center.x), str(center_bx)]
		)
	var instances := manifest.get("instances", []) as Array
	for value in instances:
		var instance := value as Dictionary
		if str(instance.get("room_id", "")) != authored_room_id:
			continue
		var role := str(instance.get("slot_role", ""))
		if role in SKIPPED_SLOT_ROLES:
			continue
		var position_m := instance.get("position_m", []) as Array
		if position_m.size() < 2:
			push_error(
				"Block00Layout: 实例 %s 缺 position_m" % str(instance.get("instance_id", ""))
			)
			continue
		# Blender(bx, by) → 房间局部 Godot(x = bx−cbx, 0, z = −(by−cby))。
		# 平面 z 平移量与房间中心的平移量相同，作差时自动抵消，故这里无需再带 shift，
		# 也就不用把 planar_center.y 掺进来（它含 shift，掺进来会整体偏 5m）。
		result.append({
			"name": str(instance.get("instance_id", "")),
			"component_id": str(instance.get("component_id", "")),
			"slot_role": role,
			"corner_id": str(instance.get("corner_id", "")),
			"position": Vector3(
				float(position_m[0]) - center_bx,
				0.0,
				-(float(position_m[1]) - center_by)
			),
			"rotation_y_deg": float(instance.get("rotation_z_deg", 0.0)),
		})
	return result


## 该层授权布局占用的世界足迹（挖通用地砖用）。只认 98F；其余楼层返回空。
static func visual_footprints(plan: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not bool(plan.get("authored_layout", false)):
		return result
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		if not bool(spec.get("authored_layout_shell", false)):
			continue
		var position := spec.get("position", Vector2.ZERO) as Vector2
		var dimensions := spec.get("dimensions", Vector2.ZERO) as Vector2
		result.append(Rect2(position - dimensions * 0.5, dimensions))
	return result


## 该层是否由区块00 授权布局接管。
static func owns_floor(plan: Dictionary) -> bool:
	return bool(plan.get("authored_layout", false))


## 平面 z 平移量：把「门厅楼梯侧墙中心」对齐到 base_plan 入口房推出的楼梯落点。
## 目标 z = 入口房中心 z（15m 墙只有 offset 0 一个合法门槽，所以落点必在墙中心；
## x 由入口房东墙给出）。来源是摆位源自己的 bounds，不是硬编码常量。
static func _resolve_planar_z_shift(
	room: Dictionary, anchor_position: Vector2, anchor_size: Vector2
) -> Variant:
	var bounds := _room_bounds(room)
	var door_y := (float((bounds["y"] as Array)[0]) + float((bounds["y"] as Array)[1])) * 0.5
	var target := _anchor_stair_landing(anchor_position, anchor_size)
	# world.z = −by + shift ⇒ shift = target.z + by
	return target.y + door_y


## 入口房的楼梯落点（planar）：沿 ENTRY_STAIR_SIDE 偏出半个尺寸。
static func _anchor_stair_landing(anchor_position: Vector2, anchor_size: Vector2) -> Vector2:
	match ENTRY_STAIR_SIDE:
		"east":
			return anchor_position + Vector2(anchor_size.x * 0.5, 0.0)
		"west":
			return anchor_position - Vector2(anchor_size.x * 0.5, 0.0)
		"south":
			return anchor_position + Vector2(0.0, anchor_size.y * 0.5)
		_:
			return anchor_position - Vector2(0.0, anchor_size.y * 0.5)


## 摆位源房间的两个对角平面点（min / max），按给定 z 平移量换算到塔楼平面。
static func _room_planar_corners(room: Dictionary, planar_z_shift: float) -> Array[Vector2]:
	var bounds := _room_bounds(room)
	var x0 := float((bounds["x"] as Array)[0])
	var x1 := float((bounds["x"] as Array)[1])
	var y0 := float((bounds["y"] as Array)[0])
	var y1 := float((bounds["y"] as Array)[1])
	# Blender y → planar z = −by + shift ⇒ y 越大 z 越小（Y=北 ⇒ 北 = −z）
	var z0 := -y0 + planar_z_shift
	var z1 := -y1 + planar_z_shift
	return [
		Vector2(minf(x0, x1), minf(z0, z1)),
		Vector2(maxf(x0, x1), maxf(z0, z1)),
	]


static func _room_bounds(room: Dictionary) -> Dictionary:
	return {
		"x": room.get("bounds_x_m", [0.0, 0.0]) as Array,
		"y": room.get("bounds_y_m", [0.0, 0.0]) as Array,
	}


static func _room_lookup(manifest: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	for value in manifest.get("rooms", []):
		var room := value as Dictionary
		lookup[str(room.get("room_id", ""))] = room
	return lookup


static func _plan_spec(plan: Dictionary, key: String) -> Dictionary:
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		if str(spec.get("key", "")) == key:
			return spec
	return {}
