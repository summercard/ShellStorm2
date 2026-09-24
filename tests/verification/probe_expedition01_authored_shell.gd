extends Node
## 探针：远征01「整房 5m 通用壳体组件清单」（第 4 环）区块级取证。
##
## 断言口径 = **区块级**，不是逐房级：同一道共享墙上的同一个 lane 全局只出一件
## （先声明者拥有），被邻房持有的那一件在本房子树里根本不存在 —— 这正是
## `DungeonRoom3D._build_authored_layout_shell()` 里 `delegated_sides` 的契约。
##   ① 除入口安全房外，每房都产出 authored_layout_shell + 实例清单；
##   ② `build_block()` 无 errors（房界在 5m 格线、门位正中 lane、门不在 L 臂下）；
##   ③ 区块内 role=door 的 lane 总数 == 边数（= 有 parent_key 的房间数），
##      即「每扇门恰有一件门墙承接，既不漏也不重」；
##   ④ 任何房间里都不存在「坐在自己门位上的实墙」（运行时那条 push_error 的静态镜像）；
##   ⑤ slot_role 分布不含 door_leaf_preview；
##   ⑥ 累计实例数（性能信号：地砖逐件实例化，不是 MultiMesh）；
##   ⑦ **非矩形外轮廓真被消费**：轮廓透传到区块输入、`template_variant` 回写一致、
##      凹口格不出砖（砖数 == 多边形面积/25 — 凹口被当成实心房就会多出砖）；
##   ⑧ **角件账目守恒**：每房「保留的 L 件 + 让位的 L 件 == 多边形凸角数」。
##      凹角若被当成凸角放 L 件，这条立刻不平（曾是真实 bug：db_01 房多放 2 件）。
##
## ⑧ 的凸角数由多边形现算（不读 builder 内部记录），与 `_corner_records()` 的判据同源但独立。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")
const VALIDATOR := preload("res://src/map/LevelPlanValidator.gd")
const BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")

const LEVEL := "expedition_01"
const SAMPLES := 12

var failures: Array[String] = []
var contour_room_total := 0
var contour_variants: Dictionary = {}
var corner_checked_rooms := 0


func _ready() -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	if level_plan.is_empty():
		print("PROBE_FAIL: level_plan 加载失败")
		get_tree().quit(1)
		return
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	print("policy.authored_layout_shell=%s" % str(policy.get("authored_layout_shell", false)))

	var role_totals: Dictionary = {}
	var reported := false
	for index in range(SAMPLES):
		var run_seed := 700000 + index * 7919
		var generated := GENERATOR._generate_constrained_floor(
			LEVEL, 0, run_seed, normalized, policy, templates
		)
		if generated.is_empty():
			_fail("seed %d: 生成为空" % run_seed)
			continue
		var errors := VALIDATOR.validate_normalized(LEVEL, 0, generated, policy, templates)
		if not errors.is_empty():
			_fail("seed %d: 校验失败 %s" % [run_seed, str(errors)])
			continue
		var rooms := generated.get("rooms", []) as Array
		_check_block(rooms, run_seed, templates)
		var total := 0
		for value in rooms:
			var room := value as Dictionary
			var key := str(room["key"])
			if str(room.get("role", "")) == "stair_entry":
				if bool(room.get("authored_layout_shell", false)):
					_fail("seed %d: 入口安全房被接管（应留给 v007）" % run_seed)
				continue
			if not bool(room.get("authored_layout_shell", false)):
				_fail("seed %d: %s 未产出授权壳体" % [run_seed, key])
				continue
			var instances := room.get("authored_layout_instances", []) as Array
			total += instances.size()
			for inst_value in instances:
				var role := str((inst_value as Dictionary).get("slot_role", ""))
				role_totals[role] = int(role_totals.get(role, 0)) + 1
				if role == "door_leaf_preview" or role.is_empty():
					_fail("seed %d: %s 出现不该带下来的 role=%s" % [run_seed, key, role])
		if not reported:
			reported = true
			_dump_sample(generated, run_seed)
		print("seed %d: rooms=%d authored_instances=%d" % [run_seed, rooms.size(), total])

	print("\n=== slot_role 累计（%d 个种子）===" % SAMPLES)
	var role_keys := role_totals.keys()
	role_keys.sort()
	for key in role_keys:
		print("  %8d x %s" % [int(role_totals[key]), str(key)])
	print("\n=== 非矩形外轮廓消费（⑦⑧）===")
	var variant_keys := contour_variants.keys()
	variant_keys.sort()
	for key in variant_keys:
		print("  %4d x 轮廓变体 %s" % [int(contour_variants[key]), str(key)])
	print("  轮廓房累计 = %d，角件账目复核房数 = %d" % [contour_room_total, corner_checked_rooms])
	# 房型池里 corridor_45x40 / db_70x50 都带凹凸变体，12 个种子一个都没用上 = 透传链路断了。
	if contour_room_total < 1:
		_fail("12 个种子一次都没用到非矩形外轮廓 —— 轮廓透传链路可能已断")
	if corner_checked_rooms < 1:
		_fail("角件账目一次都没复核到")
	if failures.is_empty():
		print("\nPROBE_OK")
		get_tree().quit(0)
	else:
		print("\nPROBE_FAIL count=%d" % failures.size())
		for line in failures.slice(0, 25):
			print("  !! %s" % line)
		get_tree().quit(1)


## 区块级复核：直接重放 build_block（与生产同一份实现），校验门槽覆盖与 lane 唯一性。
func _check_block(rooms: Array, run_seed: int, templates: Dictionary) -> void:
	var block := GENERATOR.authored_shell_block(rooms, templates)
	if block.size() != rooms.size() - 1:
		_fail("seed %d: 区块房间数 %d 与预期 %d 不符" % [run_seed, block.size(), rooms.size() - 1])
		return
	var result := BUILDER.build_block(block)
	for error_value in result.get("errors", []):
		_fail("seed %d: build_block 报错 %s" % [run_seed, str(error_value)])
	var door_lanes := 0
	for lane_value in result.get("wall_lanes", []):
		var lane := lane_value as Dictionary
		if str(lane.get("role", "")) in ["door", "exit"]:
			door_lanes += 1
	var edges := 0
	for value in rooms:
		var room := value as Dictionary
		if not str(room.get("parent_key", "")).is_empty():
			edges += 1
	if door_lanes != edges:
		_fail("seed %d: 门墙 lane 数 %d != 边数 %d" % [run_seed, door_lanes, edges])
	# ④ 没有任何房间在自己的门位上放实墙。
	for value in rooms:
		var room := value as Dictionary
		var key := str(room["key"])
		var size := room["size"] as Vector2
		var instances := room.get("authored_layout_instances", []) as Array
		for port_value in room.get("ports", []):
			var port := port_value as Dictionary
			var side := str(port.get("side", ""))
			var lane := float(port.get("lane_m", 0.0))
			for inst_value in instances:
				var inst := inst_value as Dictionary
				var role := str(inst.get("slot_role", ""))
				if role != "solid_wall":
					continue
				var pos := inst.get("position", Vector3.ZERO) as Vector3
				if _on_position(role, side, pos, size, lane):
					_fail("seed %d: %s 的 %s 门位上有实墙（门开在实墙上）" % [run_seed, key, side])
	# ⑦⑧ 轮廓消费与角件账目：几何真源取 `build_block()` 归一化后的多边形，
	# 不与生成器侧的声明值比对（生成器会按门位筛变体、把声明值换掉）。
	var normalized_rooms := result.get("rooms", []) as Array
	for value in block:
		var built := value as Dictionary
		var key := str(built.get("room_id", ""))
		var normalized_room: Dictionary = {}
		for room_value in normalized_rooms:
			var candidate := room_value as Dictionary
			if str(candidate.get("room_id", "")) == key:
				normalized_room = candidate
				break
		if normalized_room.is_empty():
			_fail("seed %d: 区块房间 %s 没进 build_block 归一化结果" % [run_seed, key])
			continue
		var polygon := normalized_room.get("footprint_m", PackedVector2Array()) as PackedVector2Array
		# ⑧ 角件账目守恒（凸角数现算，不看 builder 内部记录）。
		_check_corner_accounting(result, key, polygon, run_seed)
		if not built.has("footprint_vertices_m"):
			continue
		# ⑦ 轮廓透传 + 变体回写一致。
		var source_room: Dictionary = {}
		for room_value in rooms:
			var candidate := room_value as Dictionary
			if str(candidate.get("key", "")) == key:
				source_room = candidate
				break
		if source_room.is_empty():
			_fail("seed %d: 区块房间 %s 在生成器房表里查不到" % [run_seed, key])
			continue
		var variant := str(built.get("footprint_variant", ""))
		if str(source_room.get("template_variant", "")) != variant:
			_fail("seed %d: %s 的 template_variant=%s 与实际外轮廓变体 %s 不一致（回写断了）" % [
				run_seed, key, str(source_room.get("template_variant", "")), variant,
			])
		contour_room_total += 1
		contour_variants[variant] = int(contour_variants.get(variant, 0)) + 1
		# ⑦ 凹口格不出砖：地砖数必须等于多边形面积 / 25（凹口当实心房 ⇒ 砖变多，立刻不平）。
		var tiles := 0
		for inst_value in (source_room.get("authored_layout_instances", []) as Array):
			if str((inst_value as Dictionary).get("slot_role", "")) == "floor_tile":
				tiles += 1
		var expected := int(round(absf(BUILDER.polygon_signed_area(polygon)) / 25.0))
		if tiles != expected:
			_fail("seed %d: %s 的凹口没有正确排除地砖：砖数 %d != 多边形面积/25 = %d" % [
				run_seed, key, tiles, expected,
			])


## 角件账目守恒：凸角数 == 保留的 L 件 + 让位的 L 件（让位 = 共点去重或门让位）。
## 凹角若被当凸角放件，`kept` 会多出来；漏放则少 ⇒ 两个方向都会开火。
func _check_corner_accounting(
	result: Dictionary, key: String, polygon: PackedVector2Array, run_seed: int
) -> void:
	var convex := _convex_vertex_count(polygon)
	var kept := 0
	for corner_value in result.get("corners", []):
		if str((corner_value as Dictionary).get("room_id", "")) == key:
			kept += 1
	var dropped := 0
	for corner_value in result.get("corners_dropped", []):
		if str((corner_value as Dictionary).get("room_id", "")) == key:
			dropped += 1
	corner_checked_rooms += 1
	if kept + dropped != convex:
		_fail("seed %d: %s 角件账目不平：保留 %d + 让位 %d != 凸角数 %d（凹角被当成凸角了？）" % [
			run_seed, key, kept, dropped, convex,
		])


## 多边形凸角数（直角多边形，按面积符号统一绕向后 `cross > 0` 即凸角）。
func _convex_vertex_count(polygon: PackedVector2Array) -> int:
	var count := polygon.size()
	if count < 3:
		return 0
	var orientation := 1.0 if BUILDER.polygon_signed_area(polygon) > 0.0 else -1.0
	var convex := 0
	for index in range(count):
		var previous := polygon[(index - 1 + count) % count]
		var current := polygon[index]
		var following := polygon[(index + 1) % count]
		var incoming := current - previous
		var outgoing := following - current
		if (incoming.x * outgoing.y - incoming.y * outgoing.x) * orientation > 0.0:
			convex += 1
	return convex


## 某实例是否正坐在 (side, lane) 这个门位上。
func _on_position(role: String, side: String, pos: Vector3, size: Vector2, lane: float) -> bool:
	match side:
		"south":
			return is_equal_approx(pos.z, size.y * 0.5) and absf(pos.x - lane) <= 0.01
		"north":
			return is_equal_approx(pos.z, -size.y * 0.5) and absf(pos.x - lane) <= 0.01
		"east":
			return is_equal_approx(pos.x, size.x * 0.5) and absf(pos.z - lane) <= 0.01
		"west":
			return is_equal_approx(pos.x, -size.x * 0.5) and absf(pos.z - lane) <= 0.01
	return false


func _dump_sample(generated: Dictionary, run_seed: int) -> void:
	print("\n=== 样例（seed %d）===" % run_seed)
	for value in generated.get("rooms", []):
		var room := value as Dictionary
		var counts: Dictionary = {}
		for inst_value in room.get("authored_layout_instances", []):
			var role := str((inst_value as Dictionary).get("slot_role", ""))
			counts[role] = int(counts.get(role, 0)) + 1
		print("  %-12s %-12s %-10s doors=%d %s" % [
			str(room["key"]),
			str(room.get("template_id", "")),
			str(room.get("size", Vector2.ZERO)),
			(room.get("ports", []) as Array).size(),
			str(counts),
		])
	print("")


func _fail(message: String) -> void:
	failures.append(message)
