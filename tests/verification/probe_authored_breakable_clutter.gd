extends Node
## 探针：场景工坊里**手摆**的易碎陈设能不能当正式组件用。
##
## 业主 2026-10-30 问「易碎物品是不是也能放进场景编辑器里作为组件去刷」。
## 只把 prefab 注册进组件目录是**不够**的 —— 那只能"摆得出来"，摆出来的东西会：
##   ① 砸碎后不进房间账 ⇒ 走远再回来 / 存档重进，罐子自己复原；
##   ② 没有稳定 id ⇒ 存档里那笔账无处可挂；
##   ③ 不参与随机撒点避让 ⇒ 同一位置叠出第二件。
##
## 本探针把这三条都变成会失败的断言，并且走**真实接入点** `_build_shell()` 静态分支，
## 不是手工调 `_adopt_authored_breakable_clutter()` 自证。
##
## godot --headless --path . --scene res://tests/verification/probe_authored_breakable_clutter.tscn

const FIXTURE := "res://tests/fixtures/authored_clutter_room.tscn"
const ROOM_ID := "clutter_fixture"

var _failed := 0
var _room: DungeonRoom3D


func _ready() -> void:
	await get_tree().process_frame
	if not ResourceLoader.exists(FIXTURE, "PackedScene"):
		_finish("找不到测试布局 %s" % FIXTURE)
		return
	var plan := {
		"enabled": true,
		"per_room_min": 4,
		"per_room_max": 6,
		"exclude_room_types": [],
		"min_room_size_m": 8.0,
		"wall_margin_m": 0.9,
		"door_clearance_m": 2.4,
		"min_spacing_m": 1.1,
	}
	_room = DungeonRoom3D.new()
	_room.configure({
		"room_id": ROOM_ID,
		"room_type": "COMBAT",
		"size_class": "large",
		"custom_dimensions": Vector2(40.0, 30.0),
		"static_layout_scene_path": FIXTURE,
		"procedural_shell": true,
		"interactive_clutter": plan,
	})
	add_child(_room)
	await get_tree().process_frame
	_room.ensure_shell_built()
	await _settle()

	# —— A. 建壳时就认领了，不用等 detail ——
	var authored := _room.get_authored_clutter()
	_check(authored.size() == 2, "A1 静态布局里 2 件易碎件必须全部认领（实得 %d）" % authored.size())
	if authored.is_empty():
		_finish("没有认领到任何手摆易碎件")
		return
	var ids: Array[String] = []
	for clutter in authored:
		var id := str(clutter.get_meta("clutter_id", ""))
		ids.append(id)
		_check(id.begins_with("authored_"), "A2 手摆件必须有 authored_ 前缀的稳定 id（实得 %s）" % id)
		_check(
			clutter.broken.is_connected(Callable(_room, "_on_interactive_clutter_broken")),
			"A3 %s 的 broken 信号必须接到房间记账（没接 ⇒ 砸了不记账）" % clutter.name
		)
	_check(ids[0] != ids[1], "A4 两件手摆件 id 不能相同（%s）" % str(ids))

	# —— B. 打碎进账 ——
	var target: BreakableClutter3D = authored[0]
	var target_id := str(target.get_meta("clutter_id", ""))
	target.shatter(Vector3(0.0, 0.0, -1.0))
	await _settle()
	var ledger := _room.get_persistent_detail_state("breakable_clutter")
	_check(
		ledger.has(target_id) and bool((ledger[target_id] as Dictionary).get("broken", false)),
		"B1 砸碎后房间账必须记下 %s（ledger=%s）" % [target_id, str(ledger)]
	)

	# —— C. detail 卸载重建后仍是已碎（壳常驻，不重建） ——
	_room.ensure_detail_built()
	await _settle()
	_room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	await _settle()
	_room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await _settle()
	var after_rebuild := _room.get_authored_clutter()
	var still_broken := false
	for clutter in after_rebuild:
		if str(clutter.get_meta("clutter_id", "")) == target_id:
			still_broken = clutter.is_broken()
	_check(still_broken, "C1 detail 卸载重建后手摆件必须仍是已碎（否则走远回来会复原）")

	# —— D. 随机撒点的候选落点必须避让手摆件 ——
	#
	# ⚠ 只数"实际撒出的 6 件有没有压在手摆件上"是**抽样**：撒点从几百个候选里随机取，
	# 落在 1.1m 内的概率很低，断言几乎恒绿（第一版就是这样，把避让代码删掉照样 PASS）。
	# 所以这里直接断言**候选落点集合**：任何一个候选点都不许贴着手摆件。
	var spacing := 1.1
	var authored_points: Array[Vector3] = []
	for clutter in _room.get_authored_clutter():
		var local := _room.to_local(clutter.global_position)
		authored_points.append(Vector3(local.x, 0.0, local.z))
	var candidates := _room.get_interactive_clutter_candidates()
	var blocked_candidates := 0
	for point in candidates:
		for authored_point in authored_points:
			if Vector2(point.x - authored_point.x, point.z - authored_point.z).length() < spacing:
				blocked_candidates += 1
				break
	_check(candidates.size() > 0, "D0 候选落点不能为空（否则 D1 是空断言）")
	_check(
		blocked_candidates == 0,
		"D1 候选落点不得贴着手摆件（越界 %d / 共 %d 个候选）" % [blocked_candidates, candidates.size()]
	)
	var random_clutter: Array[BreakableClutter3D] = []
	for value in get_tree().get_nodes_in_group("breakable_clutter_3d"):
		var clutter := value as BreakableClutter3D
		if clutter == null or not _room.is_ancestor_of(clutter):
			continue
		if bool(clutter.get_meta("clutter_authored", false)):
			continue
		random_clutter.append(clutter)
	var overlap := 0
	for clutter in random_clutter:
		var local := _room.to_local(clutter.global_position)
		for authored_point in authored_points:
			if Vector2(local.x - authored_point.x, local.z - authored_point.z).length() < spacing:
				overlap += 1
				print("AUTHORED_CLUTTER_OVERLAP %s 与手摆件 %.2fm" % [
					clutter.name,
					Vector2(local.x - authored_point.x, local.z - authored_point.z).length(),
				])
	_check(overlap == 0, "D2 实际撒出的易碎件也不得与手摆件重叠（重叠 %d 处）" % overlap)
	var random_points: Array[String] = []
	for clutter in random_clutter:
		var local := _room.to_local(clutter.global_position)
		random_points.append("(%.2f,%.2f)" % [local.x, local.z])
	print("AUTHORED_CLUTTER_DIAG authored=%d random=%d ids=%s random_at=%s" % [
		authored.size(), random_clutter.size(), str(ids), str(random_points)
	])
	# —— E. 存档往返：账写进字典 → 新房间回灌 → 建壳建 detail 后仍已碎 ——
	var saved := {
		"room_id": ROOM_ID,
		"detail_state": {"breakable_clutter": ledger.duplicate(true)},
	}
	var restored := DungeonRoom3D.new()
	restored.configure({
		"room_id": ROOM_ID,
		"room_type": "COMBAT",
		"size_class": "large",
		"custom_dimensions": Vector2(40.0, 30.0),
		"static_layout_scene_path": FIXTURE,
		"procedural_shell": true,
		"interactive_clutter": plan,
	})
	restored.apply_runtime_detail_state(
		(saved["detail_state"] as Dictionary).duplicate(true)
	)
	add_child(restored)
	await get_tree().process_frame
	restored.ensure_shell_built()
	restored.ensure_detail_built()
	await _settle()
	var restored_broken := 0
	for clutter in restored.get_authored_clutter():
		if clutter.is_broken():
			restored_broken += 1
	_check(restored_broken == 1, "E1 回灌存档后必须恰好 1 件是已碎（实得 %d）" % restored_broken)

	_verify_catalog()
	_finish("")


## —— F. 场景工坊必须真的能刷出来 ——
##
## 「注册进目录」不是"写进 JSON 就算"，要过 `layout_model.catalog()` 的**真实加载路径**：
## 它会校验 component_id 非空、不重复、prefab 能 load 成 PackedScene。
## 任何一条不满足，卡片会静默消失（只在刷新提示里留一行 errors），业主看到的就是"没有"。
func _verify_catalog() -> void:
	var model := load("res://tools/scene_builder/layout_model.gd")
	var result: Dictionary = model.catalog()
	var rows: Array = result.get("rows", []) as Array
	var clutter_rows: Array = []
	for row_value in rows:
		var row := row_value as Dictionary
		if str(row.get("slot_role", "")) == "breakable_clutter":
			clutter_rows.append(row)
	_check(
		clutter_rows.size() == 5,
		"F1 组件套件里必须有 5 件易碎陈设（实得 %d）" % clutter_rows.size()
	)
	var tags := load("res://tools/scene_builder/catalog_tags.gd")
	var labels := {}
	for row_value in clutter_rows:
		var row := row_value as Dictionary
		var slug := str(row.get("slug", ""))
		var label := str(tags.caption(row))
		labels[label] = true
		_check(not label.is_empty(), "F6 %s 卡片必须有可见标题" % slug)
		_check(
			str(tags.kit(row)) == "共享 / 易碎陈设",
			"F2 %s 必须归到「共享 / 易碎陈设」组（实得 %s）" % [slug, str(tags.kit(row))]
		)
		_check(
			str(tags.type_tag(row)) == "易碎陈设",
			"F3 %s 的类型标签必须是易碎陈设（实得 %s）" % [slug, str(tags.type_tag(row))]
		)
		_check(
			ResourceLoader.exists(str(row.get("prefab_path", "")), "PackedScene"),
			"F4 %s 的 prefab 必须能加载：%s" % [slug, str(row.get("prefab_path", ""))]
		)
	var errors := result.get("errors", []) as Array
	_check(errors.is_empty(), "F5 组件目录读取不得有错误（%s）" % str(errors))
	# 5 张卡片必须在列表里能区分开：`caption()` 取 display_name，取不到就落到 category
	# ⇒ 5 件全叫「易碎陈设」，等于没法挑。这条专门盯那个退化。
	_check(labels.size() == 5, "F7 5 件易碎件的卡片标题必须互不相同（实得 %s）" % str(labels.keys()))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed += 1
	print("AUTHORED_CLUTTER %s %s" % ["PASS" if ok else "FAIL", label])


func _settle() -> void:
	for step in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame


func _finish(extra: String) -> void:
	if not extra.is_empty():
		print("AUTHORED_CLUTTER FAIL %s" % extra)
		_failed += 1
	print("AUTHORED_CLUTTER_PROBE %s" % ("OK" if _failed == 0 else "FAIL count=%d" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)
