extends Node
## 宝箱房探针（2026-10-29）。
##
## 验的是**业主那两条需求**：
##   ① 宝箱房要真的有宝箱（不是只在数据里写了一句）；
##   ② 开箱后除了掉落，还会出现一张命运卡。
## 外加三条「不写就会静默错」的边界：
##   ③ 没钥匙时打不开，且**箱子不能被标成已开**（否则玩家带钥匙回来就没得开了）；
##   ④ 同一只箱子只能开一次（`commit_opened()` 幂等 + 上层不重复结算）；
##   ⑤ 掉落数量 = `drop_count`，不是 1 也不是翻倍。
##
## 用法：godot --headless --path . --scene res://tools/_egt_chest_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED_VALUE := 77003244
const FATE_BRIDGE_PATH := "/root/FateCardGameBridge"

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _ready() -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("EGT_CHEST_PROBE_FAIL 场景不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	# —— ① 每间宝箱房都要有箱子 ——
	#
	# ⚠ **不能按 `room_type == "REWARD"` 找**：flow 的 kind 不写进运行时 `room_type`
	# （`_flow_room_type()` 只区分 SAFE_ROOM / EXTRACTION_ROOM / BOSS_ROOM / COMMON_ROOM），
	# REWARD 房在运行时就是一间 `COMMON_ROOM`。第一版探针按 REWARD 找，结果「0 张宝箱房」，
	# 而实际上 `reward_01` / `reward_02` 都在。
	#
	# 正确判据：**有 `chest_placements` 的房就是宝箱房** —— 生成器只给 REWARD 房写这个字段，
	# 所以这条等价于"宝箱房"，而且不依赖任何房型命名。
	var chest_rooms: Array[DungeonRoom3D] = []
	for room in tower._rooms:
		var candidate := room as DungeonRoom3D
		if candidate != null and not (candidate.chest_placements as Array).is_empty():
			chest_rooms.append(candidate)
	print("宝箱房数量：%d → %s" % [chest_rooms.size(), str(chest_rooms.map(func(r): return r.room_id))])
	_check(not chest_rooms.is_empty(), "远征03 一张宝箱房都没有（生成期没给 REWARD 房写 chest_placements）")

	var total_chests := 0
	for room in chest_rooms:
		var declared := (room.chest_placements as Array).size()
		# ⚠ **必须先让房间建内容再数箱子**：flow 房间的细节（家具 / 摆件 / 宝箱）
		# 是「进房时按需构建」的，开局所有房的 `_build_content()` 都还没跑。
		# 第一版探针在进入房间之前就数实例，恒得 0 —— 那是探针的错，不是箱子没建。
		await _enter_room(tower, room)
		var built := room.get_treasure_chests().size()
		total_chests += built
		print("  %s chest_placements=%d 实例化=%d" % [room.room_id, declared, built])
		_check(built == declared, "%s 声明 %d 只箱子但只建出 %d 只" % [room.room_id, declared, built])
		# 宝箱房必须是「无怪房」—— 原作 REWARD 是 enemyless，摆怪会让开箱变成战斗中断。
		_check(
			(room.spawn_placements as Array).is_empty(),
			"%s 是宝箱房但还摆了刷怪盒（宝箱房应当无怪）" % room.room_id
		)
	_check(total_chests > 0, "全层一只宝箱都没建出来")

	if chest_rooms.is_empty() or total_chests == 0:
		_finish()
		return

	var room := chest_rooms[0]
	# 前面已经进过每间宝箱房，这里重新进第一间以确保它当前是"在场"状态。
	await _enter_room(tower, room)
	var chest := room.get_treasure_chests()[0]
	if chest == null:
		_check(false, "%s 取不到 TreasureChest3D 实例" % room.room_id)
		_finish()
		return
	print(
		"目标箱：%s quality=%s requires_key=%s drop_count=%d fate=%d"
		% [
			chest.chest_id, chest.quality, str(chest.requires_key),
			chest.drop_count, chest.fate_card_per_open,
		]
	)

	# —— ③ 没钥匙：必须拒绝，且箱子保持未开 ——
	_strip_room_keys(tower)
	await _enter_room(tower, room)
	chest._player_in_range = true
	var loot_before := _count_ground_loot()
	var cards_before := _fate_card_count()

	tower._on_chest_open_requested(room, chest)
	await get_tree().process_frame
	if chest.requires_key:
		_check(not chest.is_opened(), "没有钥匙却把箱子标成已开（玩家带钥匙回来就没得开了）")
		_check(
			_count_ground_loot() == loot_before,
			"没有钥匙却掉出了物资（%d → %d）" % [loot_before, _count_ground_loot()]
		)
		print("  无钥匙分支：箱子保持未开，无掉落 ✓")
	else:
		print("  本关配置 requires_key=false，跳过无钥匙分支")

	# —— ②④⑤ 有钥匙：开箱 → 掉落 + 命运卡 ——
	tower._room_key_count = 1
	loot_before = _count_ground_loot()
	cards_before = _fate_card_count()
	tower._on_chest_open_requested(room, chest)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(chest.is_opened(), "给了钥匙仍然没开箱")
	_check(tower._room_key_count == 0 or _room_key_total(tower) == 0, "开箱没有扣钥匙")
	var loot_gained := _count_ground_loot() - loot_before
	var cards_gained := _fate_card_count() - cards_before
	print("  开箱结果：掉落 +%d 件，命运卡 +%d 张，status=%s" % [loot_gained, cards_gained, tower.status_label.text])
	_check(loot_gained >= 1, "开箱没有掉出任何物资")
	_check(
		loot_gained == chest.drop_count,
		"开箱掉出 %d 件，配置是 %d 件" % [loot_gained, chest.drop_count]
	)
	_check(
		cards_gained >= 1,
		"开箱没有出现命运卡（业主需求：开箱除了掉落还要出一张命运卡）"
	)

	# —— ④ 重复开箱不得再给东西 ——
	var loot_after_first := _count_ground_loot()
	var cards_after_first := _fate_card_count()
	tower._on_chest_open_requested(room, chest)
	await get_tree().process_frame
	_check(
		_count_ground_loot() == loot_after_first,
		"重复开箱又掉了一次物资（%d → %d）" % [loot_after_first, _count_ground_loot()]
	)
	_check(
		_fate_card_count() == cards_after_first,
		"重复开箱又给了一张命运卡（%d → %d）" % [cards_after_first, _fate_card_count()]
	)
	_check(chest.get_interaction_candidate(tower.player).is_empty(), "已开的箱子仍然可交互")
	print("  重复开箱：无新增掉落、无新增命运卡 ✓")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("EGT_CHEST_PROBE_OK 宝箱房：有箱 / 无钥匙可拒 / 开箱给掉落 + 命运卡 / 不可重复开")
		get_tree().quit(0)
		return
	print("EGT_CHEST_PROBE_FAIL count=%d" % failures.size())
	for message in failures:
		print("  - %s" % message)
	get_tree().quit(1)


func _enter_room(tower: TowerDescent3D, room: DungeonRoom3D) -> void:
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(room.room_id)
	for _frame in 4:
		await get_tree().process_frame


## 把玩家钥匙清到 0。三个来源都要清：`_room_key_count`（开局赠送）、
## `_temporary_room_keys`（临时钥匙）、背包里的 `item_room_key`。
## 只清一个会让探针「以为没钥匙」但实际能开 —— 那样无钥匙分支永远测不到。
func _strip_room_keys(tower: TowerDescent3D) -> void:
	tower._room_key_count = 0
	tower._temporary_room_keys = 0
	if tower._inventory != null:
		var held := tower._inventory.get_item_count("item_room_key")
		if held > 0:
			tower._inventory.consume_item("item_room_key", held)


func _room_key_total(tower: TowerDescent3D) -> int:
	return tower._get_total_room_keys()


func _count_ground_loot() -> int:
	return get_tree().get_nodes_in_group("ground_loot_3d").size()


func _fate_card_count() -> int:
	var bridge := get_node_or_null(FATE_BRIDGE_PATH)
	if bridge == null:
		return 0
	var cards: Variant = bridge.call("get_cards")
	return (cards as Array).size() if cards is Array else 0
