extends Node
## 天台女儿墙「随机破损排布」运行时探针。
##
## 用户要求「导入成新的预制体后重新随机排列外墙」。资产层的可拼接性由
## probe_rooftop_parapet_damage_prefabs 证明；本探针看的是**排布结果**：
## 把天台 stage 真装一遍，按四条边逐槽位打印用的是哪一档（`.`=完好 / `A`=崩顶 /
## `B`=贯穿 / `C`=塌脚），并断言：
##   1. 破损不是全挤在一条边上（四条边里至少 3 条有破损）；
##   2. 同一条边上破损不是一整段连续（最长连续破损段 < 该边破损数）；
##   3. 三档破损都真的出现过；
##   4. 槽位总数 = intact + 破损 = 61（64 段 - 西侧门洞补位 3 件）。
##
## 纯诊断，不算门禁；输出 PROBE_DMG_LAYOUT_* 行供肉眼核对与留档。
## 跑法：Godot --headless --path <项目> res://tests/verification/probe_rooftop_parapet_damage_layout.tscn

const SLOT_COUNT_EXPECTED := 61
const SIDE_TOLERANCE_M := 0.01
const VARIANT_KEYS: Array[String] = ["dmg_a", "dmg_b", "dmg_c"]

var _failures: Array[String] = []


func _ready() -> void:
	var rooftop := TowerFloorStage3D.new()
	rooftop.configure(0, "rooftop", ["west"])
	add_child(rooftop)
	await get_tree().process_frame
	await get_tree().physics_frame

	var slot_transforms: Array = rooftop.call("get_outer_straight_slot_transforms")
	print(
		"PROBE_DMG_LAYOUT seed=%d slots=%d"
		% [int(rooftop.get("_outer_damage_seed")), slot_transforms.size()]
	)
	if slot_transforms.is_empty():
		print("PROBE_DMG_LAYOUT_FAIL 槽位为 0（哨兵：后面全是 0 样本假绿）")
		await _release(rooftop)
		get_tree().quit(1)
		return
	_expect(
		slot_transforms.size() == SLOT_COUNT_EXPECTED,
		"直段槽位数 %d != %d" % [slot_transforms.size(), SLOT_COUNT_EXPECTED]
	)

	var kinds := _resolve_slot_kinds(rooftop, slot_transforms)
	var placements := _classify_sides(slot_transforms, kinds)

	var sides_with_damage := 0
	var damaged_total := 0
	for side in ["north", "south", "west", "east"]:
		var entries: Array = placements[side]
		var map := ""
		var longest_run := 0
		var run := 0
		var damaged_on_side := 0
		for entry in entries:
			var key := str(entry["key"])
			if key == "intact":
				map += "."
				run = 0
			else:
				map += key.substr(key.length() - 1).to_upper()
				run += 1
				damaged_on_side += 1
				longest_run = maxi(longest_run, run)
		damaged_total += damaged_on_side
		print(
			"PROBE_DMG_LAYOUT side=%-5s slots=%2d damaged=%2d longest_run=%d map=%s"
			% [side, entries.size(), damaged_on_side, longest_run, map]
		)
		_expect(not entries.is_empty(), "%s 边没有任何直段槽位" % side)
		if damaged_on_side > 0:
			sides_with_damage += 1
			_expect(longest_run < damaged_on_side, "%s 边破损全挤成一段连续" % side)

	var histogram := _histogram(kinds)
	print(
		"PROBE_DMG_LAYOUT summary damaged=%d sides_with_damage=%d/4 histogram=%s"
		% [damaged_total, sides_with_damage, str(histogram)]
	)
	# 哨兵：破损为 0 时下面的「至少 3 条边有破损」「三档都出现」都无意义，
	# 必须先确认真排上了破损，否则比对会退化成假绿。
	_expect(damaged_total > 0, "一件破损都没排上（破损未接线或 0 样本）")
	_expect(
		damaged_total == _count_damaged(kinds),
		"逐边统计的破损数(%d) != 全局破损数(%d)" % [damaged_total, _count_damaged(kinds)]
	)
	_expect(sides_with_damage >= 3, "破损只落在 %d 条边上（应至少 3 条，否则不像随机散布）" % sides_with_damage)
	for variant in VARIANT_KEYS:
		_expect(int(histogram.get(variant, 0)) > 0, "破损档 %s 一件都没排上" % variant)

	if _failures.is_empty():
		print("PROBE_DMG_LAYOUT_DONE scattered=true variants_all_used=true slots_match=true")
	else:
		for failure in _failures:
			print("PROBE_DMG_LAYOUT_FAIL %s" % failure)
		print("PROBE_DMG_LAYOUT_DONE failures=%d" % _failures.size())
	await _release(rooftop)
	get_tree().quit(0 if _failures.is_empty() else 1)


## 退出前把整层舞台拆掉：套件 runner 会把「资源或 ObjectDB 泄漏」判成退出码 4，
## 不能靠「quit 时会顺手清树」侥幸过关。
func _release(stage: Node) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	stage.queue_free()
	await get_tree().process_frame


## 各槽位的档位表直接取自 TowerFloorStage3D.get_outer_slot_kinds()（与槽位表同源同序）。
##
## ⚠️ 刻意**不**从 MultiMesh 回读实例变换来判断「哪个槽位用了哪一档」：MultiMesh 的
## 实例变换存在 RenderingServer 侧，dummy 渲染器（--headless）下一律回读成单位阵，
## 于是 61 个槽位会全部落到 (0,0,0)、匹配不上任何批次，探针会误报「槽位与批次脱钩」。
## 本探针改为读 stage 自己的档位表，因此可以在 --headless 下跑。
func _resolve_slot_kinds(rooftop: TowerFloorStage3D, slot_transforms: Array) -> Array:
	var kinds: Array = rooftop.call("get_outer_slot_kinds")
	_expect(
		kinds.size() == slot_transforms.size(),
		"档位表长度(%d) != 槽位表长度(%d)" % [kinds.size(), slot_transforms.size()]
	)
	return kinds


## 按四条边界线把槽位归到 north / south / west / east，并沿边排序。
## 边界口径直接取 TowerFloorStage3D 的常量，避免探针自己抄一份走偏。
func _classify_sides(slot_transforms: Array, kinds: Array) -> Dictionary:
	var rect: Rect2 = TowerFloorStage3D.ROOFTOP_WORLD_RECT
	var inset: float = TowerFloorStage3D.ROOFTOP_PARAPET_THICKNESS * 0.5
	var north_z := rect.position.y + inset
	var south_z := rect.end.y - inset
	var west_x := rect.position.x + inset
	var east_x := rect.end.x - inset
	var placements := {"north": [], "south": [], "west": [], "east": []}
	for index in range(slot_transforms.size()):
		var origin: Vector3 = (slot_transforms[index] as Transform3D).origin
		var side := ""
		var along := 0.0
		if absf(origin.z - north_z) < SIDE_TOLERANCE_M:
			side = "north"
			along = origin.x
		elif absf(origin.z - south_z) < SIDE_TOLERANCE_M:
			side = "south"
			along = origin.x
		elif absf(origin.x - west_x) < SIDE_TOLERANCE_M:
			side = "west"
			along = origin.z
		elif absf(origin.x - east_x) < SIDE_TOLERANCE_M:
			side = "east"
			along = origin.z
		else:
			_expect(false, "槽位 %d 的坐标 %s 不在任何一条边界线上" % [index, str(origin)])
			continue
		(placements[side] as Array).append({"key": str(kinds[index]), "along": along})
	for side in placements.keys():
		var entries: Array = placements[side]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["along"]) < float(b["along"])
		)
	return placements


func _count_damaged(kinds: Array) -> int:
	var count := 0
	for kind in kinds:
		if str(kind) != "intact":
			count += 1
	return count


func _histogram(kinds: Array) -> Dictionary:
	var histogram := {"intact": 0}
	for variant in VARIANT_KEYS:
		histogram[variant] = 0
	for kind in kinds:
		var key := str(kind)
		histogram[key] = int(histogram.get(key, 0)) + 1
	return histogram


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
