extends Node
## 探针：实测测试关卡99「玩法配套逻辑到底装了什么」——刷怪、搜刮容器、门策略、
## 过门命运卡、局内命运触发、撤离信标、HUD。
##
## 只读运行时状态，不改关卡数据文件。跑法：
##   godot --headless --path . res://tests/verification/probe_test_level_99_gameplay.tscn
##
## 为什么需要它：`verify_test_level_99_flow` 覆盖的是「入口 / 数据驱动 / 场景结构」，
## 它**没有**断言「玩家进去之后有没有东西可打、门怎么开、能不能搜刮、能不能撤离」。
## 本探针先把实际值打出来供人判断；确认结论后再把该断言的固化成门禁。
##
## 三个反直觉的运行时事实（都实测踩过）：
##   1. 敌人挂在 `$ActiveEnemies` 下，**不在房间子树里** —— `room.find_children()` 恒为 0，
##      必须查 `_enemy_nodes_by_room` / `$ActiveEnemies`。
##   2. 战斗房是**多波次**的，首波只有一部分；`_alive_by_room` 是首波数，不等于该房总数。
##   3. `_try_open_room_door()` 对**已开启的边**直接返回 true（"通道已经开启"），
##      所以探针**不能**先全开边再测门策略，否则测出假阳性。

const SCENE_PATH := "res://scenes/ExpeditionLevel99_3D.tscn"
const ALL_ROOM_IDS: Array[String] = ["start", "room_01", "room_02", "extraction"]
## 主路（设计源 floor_00.json 的 main_path）。
const MAIN_PATH: Array[String] = ["room_01", "room_02"]
## 门策略的三个开关，与 verify_expedition_level01_flow 同一套口径。
const DOOR_POLICY_KEYS: Array[String] = ["requires_clear", "requires_key", "triggers_fate"]


func _ready() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		print("PROBE_FAIL: %s 加载失败" % SCENE_PATH)
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77199999
	add_child(tower)
	await _settle()

	# 注意：**不要**在这里 force_open_edge_for_test 全开边（见文件头第 3 条）。
	# 进房走 `_on_room_entered()`，不需要边表是开的。

	print("=== 1. 房间内容与类型 ===")
	_dump_room_types(tower)

	print("\n=== 2. 刷怪（战斗房）===")
	# 必须 await：本段含 await，是协程；漏 await 会只跑到第一个 await 就返回。
	await _probe_combat_spawn(tower)

	print("\n=== 3. 搜刮容器 ===")
	# 必须 await：本函数含 await（ensure_detail_built 后要等一帧），漏 await 会只跑到
	# 第一个 await 就返回，整段静默不执行 —— 本仓已多次踩到（见技能 §5 坑 14）。
	await _probe_searchable(tower)

	print("\n=== 4. 门策略（清房 / 钥匙 / 命运卡）===")
	_probe_door_policies(tower)

	print("\n=== 5. 清房联动与过门命运卡 ===")
	await _probe_clear_and_fate(tower)

	print("\n=== 6. 撤离信标 ===")
	_probe_extraction(tower)

	print("\n=== 7. 局内命运效果 / HUD ===")
	_probe_fate_and_hud(tower)

	print("\nPROBE_DONE")
	get_tree().quit(0)


func _dump_room_types(tower: TowerDescent3D) -> void:
	for room_id in ALL_ROOM_IDS:
		var room := (tower.get("_room_by_id") as Dictionary).get(room_id) as DungeonRoom3D
		if room == null:
			print("  %-10s <缺失>" % room_id)
			continue
		print(
			"  %-10s type=%-12s dims=%s main_path=%s"
			% [
				room_id, room.room_type, str(room.get_dimensions()),
				str(room_id in MAIN_PATH)
			]
		)


## 进战斗房后看敌人：首波数、波次计划、敌节点数（挂 $ActiveEnemies）、血量/伤害、是否跑物理。
func _probe_combat_spawn(tower: TowerDescent3D) -> void:
	var combat_ids: Array[String] = []
	for room_id in MAIN_PATH:
		var room := (tower.get("_room_by_id") as Dictionary).get(room_id) as DungeonRoom3D
		if room != null and room.room_type == "COMBAT":
			combat_ids.append(room_id)
	if combat_ids.is_empty():
		print("  没有 COMBAT 房，无怪可刷")
		return
	var by_room_nodes := tower._enemy_nodes_by_room
	var wave_queues := tower._room_wave_queues
	for room_id in combat_ids:
		var room := (tower.get("_room_by_id") as Dictionary).get(room_id) as DungeonRoom3D
		room.cleared = false
		tower._current_room_id = ""
		# 必须把玩家**真放进房间**：房间流送状态是按玩家实际位置算的。
		# 玩家不在房里 → 房间进 hibernate → `_hibernate_room_entities()`
		# 当场 queue_free 掉该房敌人，于是「首波数」还在 `_alive_by_room`
		# 里，敌节点却已为 0。这是流送契约，不是刷怪失败。
		tower.force_enter_room_for_test(room_id)
		tower.player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
		# 走真实入口路径触发刷怪（与 verify_expedition_level01_flow 同一做法）。
		tower._on_room_entered(room)
		await get_tree().process_frame
		await get_tree().physics_frame
		var nodes: Array = by_room_nodes.get(room_id, [])
		var queued: Array = wave_queues.get(room_id, [])
		print(
			"  进 %s → 首波 _alive_by_room=%d 敌节点=%d 波次 %d/%d 待发波次=%d 已流送=%s"
			% [
				room_id, int((tower._alive_by_room as Dictionary).get(room_id, 0)), nodes.size(),
				int(tower._room_wave_numbers.get(room_id, 0)),
				int(tower._room_wave_totals.get(room_id, 0)),
				queued.size(), str(room.is_streamed())
			]
		)
		for node in nodes:
			var enemy := node as Enemy3D
			if enemy == null:
				continue
			print(
				"      · %s room_id=%s hp=%d/%d dmg=%d speed=%.2f physics=%s"
				% [
					enemy.name, enemy.room_id, enemy.current_hp, enemy.max_hp,
					enemy.contact_damage, enemy.move_speed,
					str(enemy.is_physics_processing())
				]
			)
		await _settle()
		var after: Array = by_room_nodes.get(room_id, [])
		print(
			"      （0.35s 后复查：敌节点=%d，房已流送=%s，已清=%s）"
			% [after.size(), str(room.is_streamed()), str(room.cleared)]
		)
	# 注意：这里已是「全部房都走完」之后的状态。除最后一个房以外的房
	# 会因玩家不在而 hibernate，敌人被释放，所以此时通常只剩当前房那一波。
	var active_root := tower.get_node_or_null("ActiveEnemies")
	print(
		"  收尾快照：ActiveEnemies 子节点=%d（当前房 %s）"
		% [
			active_root.get_child_count() if active_root != null else -1,
			tower._current_room_id
		]
	)


## 搜刮容器：查每房的可搜刮家具数，以及 `searched` 信号是否已接到运行时。
func _probe_searchable(tower: TowerDescent3D) -> void:
	var searchable_total := 0
	var wired := 0
	var by_room: Dictionary = {}
	for room_id in ALL_ROOM_IDS:
		var room := (tower.get("_room_by_id") as Dictionary).get(room_id) as DungeonRoom3D
		if room == null:
			continue
		room.ensure_detail_built()
		await get_tree().process_frame
		for node in room.find_children("*", "RoomFurniture3D", true, false):
			var prop := node as RoomFurniture3D
			if prop == null or not prop.searchable:
				continue
			searchable_total += 1
			by_room[room_id] = int(by_room.get(room_id, 0)) + 1
			if prop.searched.get_connections().size() > 0:
				wired += 1
	print("  可搜刮家具合计=%d（接入回调 %d）按房=%s" % [searchable_total, wired, str(by_room)])
	if searchable_total == 0:
		print("  → 无可搜刮家具")


func _probe_door_policies(tower: TowerDescent3D) -> void:
	var edges: Array = [["start", "room_01"]]
	for index in range(MAIN_PATH.size() - 1):
		edges.append([MAIN_PATH[index], MAIN_PATH[index + 1]])
	edges.append([MAIN_PATH[MAIN_PATH.size() - 1], "extraction"])
	for edge_pair in edges:
		var policy: Dictionary = tower._door_policy_for_edge(edge_pair[0], edge_pair[1])
		var flags: Array[String] = []
		for key in DOOR_POLICY_KEYS:
			flags.append("%s=%s" % [key, str(policy.get(key, false))])
		print("  %-24s %s" % ["%s→%s" % [edge_pair[0], edge_pair[1]], " ".join(flags)])


## 清房联动：未清房应开不了门；清房 + 钥匙后开门应进入命运卡三选一。
func _probe_clear_and_fate(tower: TowerDescent3D) -> void:
	if MAIN_PATH.size() < 2:
		print("  主路不足 2 房，跳过")
		return
	var from_id := MAIN_PATH[0]
	var to_id := MAIN_PATH[1]
	var from_room := (tower.get("_room_by_id") as Dictionary).get(from_id) as DungeonRoom3D
	if from_room == null:
		print("  缺少房间 %s，跳过" % from_id)
		return
	var edge := "%s|%s" % [from_id, to_id]
	print("  边 %s 当前开启=%s（期望 false）" % [edge, str(tower._open_edges.get(edge, false))])
	# 1) 未清房
	from_room.cleared = false
	tower._current_room_id = from_id
	var opened_before := tower._try_open_room_door(to_id)
	print("  未清房时开门 → %s（期望 false）" % str(opened_before))
	# 2) 清房 + 给够钥匙
	from_room.cleared = true
	var keys_before := tower._get_total_room_keys()
	tower._room_key_count = maxi(int(tower._room_key_count), 3)
	tower._current_room_id = from_id
	var opened_after := tower._try_open_room_door(to_id)
	print(
		"  清房+钥匙后开门 → %s（钥匙 %d→%d）"
		% [str(opened_after), keys_before, tower._get_total_room_keys()]
	)
	# 命运卡是 call_deferred 弹的，等几帧再看。
	for i in 4:
		await get_tree().process_frame
	print("  命运卡激活=%s 选项数=%d" % [str(tower._door_fate_active), tower._door_fate_choices.size()])
	if tower._door_fate_active:
		var overlay := tower.get_node_or_null("HUD/DoorFateOverlay3D")
		print("  命运卡界面节点=%s" % ("已构建" if overlay != null else "未构建"))
		# _door_fate_choices 是 Array[FateCard]（RefCounted 数据对象，不是 Dictionary），
		# 读字段要用 FateCard 的属性，不能用 Dictionary.get(key, default)。
		for card in tower._door_fate_choices:
			print(
				"      · %s [%s] stable_id=%s 稀有度=%d"
				% [card.card_name, card.orientation_name(), card.stable_card_id, card.card_rarity]
			)
		tower._cancel_door_fate_selection()
		await get_tree().process_frame


func _probe_extraction(tower: TowerDescent3D) -> void:
	print("  has_expedition_extraction=%s" % str(tower.has_expedition_extraction()))
	var beacon := tower._extraction as ExtractionBeacon3D
	if beacon == null:
		print("  撤离信标为空")
		return
	var extraction_room := (tower.get("_room_by_id") as Dictionary).get("extraction") as DungeonRoom3D
	var room_type := "?"
	if extraction_room != null:
		room_type = extraction_room.room_type
	print(
		"  beacon_type=%s locked=%s 挂在=%s（期望 extraction/EXTRACTION）"
		% [beacon.beacon_type, str(beacon.locked), _room_id_of_node(beacon) + "/" + room_type]
	)


## 局内命运触发（MapFateTriggers3D）与 HUD 三件套是否存在/活跃。
func _probe_fate_and_hud(tower: TowerDescent3D) -> void:
	# MapFateTriggers 由 Dungeon3D 自建并挂为子节点，名字固定 "MapFateTriggers3D"；
	# 它没有「当前命运 id」这种字段，状态在 _counters / _triggered_this_run 两个字典里。
	var fate := tower._map_fate_triggers
	print("  MapFateTriggers3D 节点=%s" % ("存在" if fate != null else "缺失"))
	if fate != null:
		print("      触发条数=%d 计数器=%s" % [fate._triggers.size(), str(fate._counters)])
		print("      本局已触发=%s" % str(fate._triggered_this_run))
	for hud_path in [
		"HUD/DungeonMinimap3D", "HUD/TopBar", "HUD/StatusPanel",
		"HUD/ReferenceCombatHUD", "HUD/ExtractionPanel",
	]:
		print("  %-30s %s" % [hud_path, "存在" if tower.get_node_or_null(hud_path) != null else "缺失"])


## 找某个节点所在房间的 room_id（用于核对信标归属）。
func _room_id_of_node(node: Node) -> String:
	var cursor := node
	while cursor != null:
		if cursor is DungeonRoom3D:
			return (cursor as DungeonRoom3D).room_id
		cursor = cursor.get_parent()
	return "<不在任何房内>"


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
