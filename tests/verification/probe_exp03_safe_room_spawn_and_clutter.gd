extends Node
## 远征03 入口安全屋的两条玩家可见性质（2026-11-03 业主返修）：
##
##   一、玩家进入后必须出现在安全屋**正中间**（不再贴门洞）。
##   二、安全屋正中间原先那排**五件易碎小物件**必须拿掉。
##
## 两条都只能靠"真的走进那间房、数实际节点、读玩家真实坐标"来判 ——
## 数据段里写了 false 但运行时没接上，表现和没改一模一样（本工程踩过同形状的坑：
## 2026-11-02 的开发记录声称已加 `fixed_lobby_clutter_enabled` 开关并关闭了中央五件，
## 而全仓代码与关卡数据里**从来没有这个开关** —— 五件一直都在）。
##
## 反向对照：随机撒点用的 `interactive_clutter` 段在远征03 是开的，
## 所以"中央五件为 0"必须是**固定分支被关掉**的结果，不是"这关不放易碎件"。
## 本探针另数一次随机撒点总数，确认它没有被误伤。
##
## 手动跑：
##   godot --headless --path <project> res://tests/verification/probe_exp03_safe_room_spawn_and_clutter.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"
const LEVEL_ID := "expedition_03"
const RUN_SEED := 1118653462
const SPAWN_HORIZONTAL_TOLERANCE_M := 0.05
## 与 `DungeonRoom3D.INTERACTIVE_CLUTTER_PLACEMENTS` 的键集合同口径（这里只数数量，
## 不从那边导入 —— 探针要能在常量被改动时仍然独立报出实际件数）。
const FIXED_LOBBY_CLUTTER_EXPECTED := 5

var failures: Array[String] = []
var report := {}
var tower: TowerDescent3D


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("EXP03_SAFE_ROOM: " + message)


func _ready() -> void:
	if not GameDesignConfig.select_expedition_level(LEVEL_ID):
		check(false, "select_expedition_level(%s) 被拒绝" % LEVEL_ID)
		_finish()
		return
	tower = (load(LEVEL_SCENE) as PackedScene).instantiate() as TowerDescent3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", RUN_SEED)
	add_child(tower)
	for step in range(120):
		await get_tree().process_frame
		if not (tower.get("_room_by_id") as Dictionary).is_empty():
			break
	await _settle()

	var rooms: Dictionary = tower.get("_room_by_id") as Dictionary
	check(not rooms.is_empty(), "远征03 没有建出房间")
	if rooms.is_empty():
		_finish()
		return

	var entry_room := rooms.get("start") as DungeonRoom3D
	check(entry_room != null, "缺少入口安全房 start")
	if entry_room == null:
		_finish()
		return
	entry_room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	entry_room.ensure_shell_built()
	entry_room.ensure_detail_built()
	await _settle()

	await _check_spawn_at_center(entry_room)
	await _check_central_clutter_removed(entry_room, rooms)
	await _check_survives_stream_rebuild(entry_room)
	await _check_switch_is_the_cause(rooms)
	_finish()


## C 段（**反向对照，这是本探针的牙齿**）：
## 证明"中央五件为 0"真的是**开关**造成的，而不是"这间房根本走不到固定分支"。
##
## 做法：另建一间**同一房型、同一尺寸**的安全房，把开关拨回 true，数出五件；
## 再拨回 false，数出 0 件。两次都走同一条 `_build_interactive_clutter()`。
##
## 为什么必须这么做：`_build_interactive_clutter()` 的第一条分支是随机撒点，
## 若哪天有人把远征03 的 `interactive_clutter` 段调成覆盖安全房，中央也会变成 0 件 ——
## 那时 A/B 两段依然全绿，而业主的诉求（只拿掉固定的五件、随机那批别动）其实被破坏了。
func _check_switch_is_the_cause(rooms: Dictionary) -> void:
	var enabled_count := await _fixed_clutter_count_with_switch(true)
	var disabled_count := await _fixed_clutter_count_with_switch(false)
	check(
		enabled_count == FIXED_LOBBY_CLUTTER_EXPECTED,
		"开关拨回 true 时没摆出 %d 件（实得 %d）—— 固定分支已失效，B 段的 0 件是假绿"
		% [FIXED_LOBBY_CLUTTER_EXPECTED, enabled_count]
	)
	check(
		disabled_count == 0,
		"开关为 false 时仍摆了 %d 件" % disabled_count
	)
	print("EXP03_SAFE_ROOM_SWITCH enabled=%d disabled=%d" % [enabled_count, disabled_count])
	report["switch_control"] = {"enabled": enabled_count, "disabled": disabled_count}


## 造一间与真实入口安全房同规格的 STAIR_LOBBY（15×15、缺省双门），
## 指定开关值，返回它实际摆出的易碎件数；同时核对每一件的落点都落在 B 段那个
## 「正中央」圆内 —— 阈值 2.2 m 不能是拍的，必须由这一批的实际落点反证。
func _fixed_clutter_count_with_switch(enabled: bool) -> int:
	var room := DungeonRoom3D.new()
	room.configure({
		"room_id": "qa_fixed_lobby_switch_%s" % str(enabled),
		"room_type": "STAIR_LOBBY",
		"size_class": "tower_cell",
		"doors": ["south"],
		"door_targets": {"south": "next"},
		"custom_dimensions": Vector2(15.0, 15.0),
		"tower_module_shell": true,
		"fixed_lobby_clutter_enabled": enabled,
	})
	add_child(room)
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle()
	var items := _room_clutter(room)
	var farthest := 0.0
	for item in items:
		farthest = maxf(farthest, Vector2(item.position.x, item.position.z).length())
	if enabled:
		# 这条把 B 段的 2.2 m 阈值钉在真实落点上：固定五件的最远一件也在圆内，
		# 所以「B 段圆内为 0」等价于「固定五件被关掉」。
		check(
			farthest <= 2.2,
			"固定五件的最远落点 %.2f m 超出 B 段判定半径 —— 阈值需重新对齐" % farthest
		)
		report["fixed_lobby_farthest_m"] = snappedf(farthest, 0.001)
	var count := items.size()
	room.queue_free()
	await get_tree().process_frame
	return count


## A 段：玩家落地必须在安全屋**正中**。
##
## 判据取两路，互相不会互相掩盖：
##   ① 偏移函数本身（装配时用的那个，`_expedition_entry_spawn_offset`）；
##   ② 玩家节点的**真实世界坐标**减去房心 —— 这是玩家真正看到的东西。
##
## 最后一条是**旧口径的反向对照**：把默认分支（朝前门偏 4 m）在**同一间房**上算一遍，
## 它必须显著偏离房心。没有这条，本段在"函数被改成永远返回零向量"时也会绿。
func _check_spawn_at_center(entry_room: DungeonRoom3D) -> void:
	var offset: Vector3 = tower.call("_expedition_entry_spawn_offset", entry_room) as Vector3
	var offset_horizontal := Vector2(offset.x, offset.z).length()
	check(
		offset_horizontal <= SPAWN_HORIZONTAL_TOLERANCE_M,
		"出生点偏移函数没落在房心：水平 %.3f m（上限 %.2f）%s" % [
			offset_horizontal, SPAWN_HORIZONTAL_TOLERANCE_M, str(offset)
		]
	)
	_check_legacy_offset_would_miss(entry_room)
	var player := tower.player
	check(player != null, "关卡里没有玩家")
	var actual := Vector3.INF
	if player != null:
		actual = player.global_position
		var delta := actual - entry_room.global_position
		var horizontal := Vector2(delta.x, delta.z).length()
		check(
			horizontal <= SPAWN_HORIZONTAL_TOLERANCE_M,
			"玩家没落在安全屋正中：距房心 %.3f m（上限 %.2f）%s" % [
				horizontal, SPAWN_HORIZONTAL_TOLERANCE_M, str(delta)
			]
		)
		check(
			entry_room.contains_world_position(actual),
			"玩家不在安全屋范围内：%s" % str(actual)
		)
		# 落地判据：脚下真得有地面，否则"正中"是悬空的。
		var from := actual + Vector3.UP * 1.0
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
		query.exclude = [player.get_rid()] if player is CollisionObject3D else []
		var hit := tower.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "玩家脚下没有地面（正中落点是悬空的）")
		print("EXP03_SAFE_ROOM_SPAWN offset=%s room=%s player=%s ground=%s" % [
			str(offset), str(entry_room.global_position), str(actual), str(not hit.is_empty())
		])
	report["spawn"] = {
		"offset": str(offset), "offset_horizontal_m": snappedf(offset_horizontal, 0.0001),
		"room_center": str(entry_room.global_position), "player": str(actual),
	}


## 反向对照：本关入口房的门确实存在"朝前门那一侧"，而旧口径（偏 4 m）会落在那儿。
##
## 做法：直接按旧口径的映射算一遍，断言它**超出**容差。
## 若哪天有人把门向判断写坏（`front` 取空 ⇒ 旧的兜底返回零向量），
## 这条会红 —— 因为那时"旧口径"也会落在房心附近，对照失去意义。
func _check_legacy_offset_would_miss(entry_room: DungeonRoom3D) -> void:
	var front := ""
	for side_value in entry_room.door_targets.keys():
		if not str(entry_room.door_targets[side_value]).is_empty():
			front = str(side_value)
			break
	check(
		not front.is_empty(),
		"入口房没有任何带目标的门 —— 旧口径的「朝前门」无从谈起，对照失去意义"
	)
	var legacy := {
		"north": Vector3(0.0, 0.05, -4.0),
		"south": Vector3(0.0, 0.05, 4.0),
		"east": Vector3(4.0, 0.05, 0.0),
		"west": Vector3(-4.0, 0.05, 0.0),
	}.get(front, Vector3(0.0, 0.05, 0.0)) as Vector3
	var legacy_horizontal := Vector2(legacy.x, legacy.z).length()
	check(
		legacy_horizontal > SPAWN_HORIZONTAL_TOLERANCE_M,
		"旧口径的落点（%s）竟然也在容差内 —— 本段的对照无法区分新旧口径" % str(legacy)
	)
	print("EXP03_SAFE_ROOM_LEGACY front=%s legacy=%s horizontal=%.2f" % [
		front, str(legacy), legacy_horizontal
	])
	report["legacy_control"] = {
		"front": front, "offset": str(legacy),
		"horizontal_m": snappedf(legacy_horizontal, 0.001),
	}


## B 段：中央五件必须为 0，且**随机撒点那批不受牵连**。
##
## 区分两批的办法：固定五件由 `_build_interactive_clutter()` 的 STAIR_LOBBY 分支建，
## 落点全部在房心附近（|x| ≤ 1.8, |z| ≤ 1.9）；随机撒点受 `wall_margin_m = 0.9` 约束、
## 且要离门 2.4 m，不会挤在正中央那几个格。
##
## 所以判据是：**以房心为心、半径 2.2 m 的圆内，易碎件必须为 0**。
## 这比"整间房为 0"更准确 —— 业主说的是"中间五个"，不是"安全屋不许有任何杂物"。
func _check_central_clutter_removed(entry_room: DungeonRoom3D, rooms: Dictionary) -> void:
	var all := _room_clutter(entry_room)
	var central := 0
	var central_ids: Array[String] = []
	for item in all:
		var planar := Vector2(item.position.x, item.position.z).length()
		if planar <= 2.2:
			central += 1
			central_ids.append("%s@%.2f" % [str(item.get_meta("clutter_id", "?")), planar])
	check(
		central == 0,
		"安全屋正中间仍有 %d 件易碎物件（应 0）：%s" % [central, str(central_ids)]
	)
	# 反向对照：整关随机撒点那批必须还在，否则本探针分不清"关掉固定件"与"关掉整段能力"。
	var total_clutter := 0
	var placed_rooms := 0
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		if room == null or room == entry_room:
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
	await _settle()
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		if room == null or room == entry_room:
			continue
		var count := _room_clutter(room).size()
		if count > 0:
			placed_rooms += 1
		total_clutter += count
	check(total_clutter >= 30, "随机撒点那批被误伤：全关只剩 %d 件" % total_clutter)
	check(placed_rooms >= 8, "随机撒点覆盖房间被误伤：只剩 %d 间" % placed_rooms)
	print("EXP03_SAFE_ROOM_CLUTTER central=%d room_total=%d random_total=%d rooms=%d" % [
		central, all.size(), total_clutter, placed_rooms
	])
	report["clutter"] = {
		"central": central, "entry_room_total": all.size(),
		"random_total": total_clutter, "random_rooms": placed_rooms,
		"fixed_expected": FIXED_LOBBY_CLUTTER_EXPECTED,
	}


## 流送卸载重建：两条性质都必须仍然成立（不是"只在开局那一帧为真"）。
func _check_survives_stream_rebuild(entry_room: DungeonRoom3D) -> void:
	entry_room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	await get_tree().process_frame
	entry_room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	entry_room.ensure_detail_built()
	await _settle()
	var central := 0
	for item in _room_clutter(entry_room):
		if Vector2(item.position.x, item.position.z).length() <= 2.2:
			central += 1
	check(central == 0, "流送重建后中央又冒出 %d 件易碎物件" % central)


func _room_clutter(room: DungeonRoom3D) -> Array[BreakableClutter3D]:
	var result: Array[BreakableClutter3D] = []
	for value in get_tree().get_nodes_in_group("breakable_clutter_3d"):
		var clutter := value as BreakableClutter3D
		if clutter != null and room.is_ancestor_of(clutter):
			result.append(clutter)
	return result


func _settle() -> void:
	for step in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame


func _finish() -> void:
	var out := OS.get_environment("EXP03_SAFE_ROOM_QA_DIR")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out + "/probe.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	if failures.is_empty():
		print("EXP03_SAFE_ROOM_SPAWN_AND_CLUTTER_OK")
	else:
		print("EXP03_SAFE_ROOM_SPAWN_AND_CLUTTER_FAIL count=%d" % failures.size())
		for failure in failures.slice(0, 20):
			print("  - ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)
