extends Node
## 验收入口：基地 NPC 的一次性剧情节拍（`BASE-NPC`，首遇收租人 → 回基地被提醒）。
##
## 覆盖：
##   S01–S03 内容契约（台词、指路设施、节拍登记）与"未遭遇不触发"；
##   S04 首次确认遭遇（预约不算）之后才成立；
##   S05–S08 回到 99F：站在迎宾锚点、停巡、玩家进 4m 自动说出指定台词、朝向玩家、跨局落盘；
##   S09 气泡放完后恢复巡逻；
##   S10–S11 再回一次基地不再重复（一次性，跨场景重建仍然压住）；
##   S12 台词指向的二楼档案室真实存在、且档案里能查到收租人。
##
## ⚠️ 口径：真实塔楼场景 `TowerDescent3D.tscn`（不是旧兼容场景 `BaseWorld3D.tscn`）。
## 需要隔离的 `APPDATA` 由套件在 Autoload 之前设置；本脚本只走公开服务接口读写。

const NPC_ID := "npc_base99_green"
const ELITE_ID := "elite_arms_taker"
const BEAT_ID := "elite_arms_taker_first_seen"
## 用户口径的台词，逐字比对（改台词必须同时改这里，防止"内容悄悄变了没人发现"）。
## 内容目录里按两句存（每句一个气泡），这里比对拼接后的全文。
const EXPECTED_TEXT := "你遇到收租人啦？有没有被夺走东西呀？你可以去二楼的档案室里看看它的信息哦。"
## 第一句单独比对：真正先被看见的那一行。
const FIRST_LINE := "你遇到收租人啦？有没有被夺走东西呀？"
const STANDBY_ANCHOR := "99层基地NPC迎宾锚点"
const ARCHIVE_FACILITY_ID := "monster_archive"
## 99F 基地地面高度。
const BASE99_FLOOR_Y := -12.0
## 二楼的高度下限：档案终端在世界 y=-4.44（约在地面上方 7.5m）。
const SECOND_FLOOR_MIN_CLEARANCE := 3.0
const ENCOUNTER_ID := "verify_story_beat_run:92:elite_arms_taker"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	await _run(failures)
	_finish(failures)


func _run(failures: Array[String]) -> void:
	# —— 清零：档案与节拍历史都回到"没见过、没说过" ——
	NpcStoryBeatService.reset_for_test()
	EliteRosterService.reset_roster_for_test()
	BaseManager.force_save_failure_for_test = false

	# —— S01 内容契约 ——
	var beat := NpcCatalog.get_story_beat(NPC_ID, BEAT_ID)
	if beat.is_empty():
		failures.append("S01 NpcCatalog 没有登记节拍『%s』" % BEAT_ID)
	var beat_text := NpcCatalog.get_story_beat_full_text(NPC_ID, BEAT_ID)
	if beat_text != EXPECTED_TEXT:
		failures.append("S01 节拍全文与用户口径不一致：『%s』" % beat_text)
	var beat_lines := NpcCatalog.get_story_beat_lines(NPC_ID, BEAT_ID)
	if beat_lines.is_empty() or beat_lines[0] != FIRST_LINE:
		failures.append("S01 第一句不是用户口径：『%s』" % str(beat_lines[0] if not beat_lines.is_empty() else ""))
	# 单句必须能排成两行以内：气泡挂高 3.40m 是按两行定的口径，超过就会顶出画面上缘
	# （2026-11-04 真实渲染实测：40 字整句排 4 行、顶部被裁）。
	for index in beat_lines.size():
		if beat_lines[index].length() > 24:
			failures.append(
				"S01 第 %d 句有 %d 字，超过两行上限（24 字）—— 会排成 3 行以上把气泡顶出屏幕"
					% [index, beat_lines[index].length()]
			)
	if NpcCatalog.get_story_beat_requirement(NPC_ID, BEAT_ID) != ELITE_ID:
		failures.append("S01 节拍没有绑定『%s』的遭遇事实" % ELITE_ID)
	if NpcCatalog.get_story_beat_archive_facility(NPC_ID, BEAT_ID) != ARCHIVE_FACILITY_ID:
		failures.append("S02 节拍没有登记指路设施『%s』" % ARCHIVE_FACILITY_ID)
	if NpcCatalog.has_npc(NPC_ID) == false:
		failures.append("S01 内容目录缺少 NPC『%s』" % NPC_ID)

	# —— S03 未遭遇：不该有待播节拍 ——
	if NpcStoryBeatService.has_pending_beat(NPC_ID):
		failures.append("S03 还没遭遇收租人就已经有待播节拍")

	var tower := await _load_tower(failures)
	if tower == null:
		return
	var npc := tower.find_npc(NPC_ID)
	if npc == null:
		failures.append("S03 99F 基地里找不到 NPC『%s』" % NPC_ID)
		_finish_now(tower, failures)
		return
	if bool(npc.get_snapshot().get("story_standby", false)):
		failures.append("S03 没有节拍时 NPC 不应处于迎宾站定")

	# —— S04 预约不算"遇到"：只有首次生成确认之后才算 ——
	if not EliteRosterService.reserve(ELITE_ID, ENCOUNTER_ID, 92):
		failures.append("S04 无法预约『%s』" % ELITE_ID)
	if NpcStoryBeatService.has_pending_beat(NPC_ID):
		failures.append("S04 仅预约（还没见面）就让节拍成立了")
	if not EliteRosterService.confirm_reservation(ELITE_ID, ENCOUNTER_ID):
		failures.append("S04 首次生成确认失败")
	var record := EliteRosterService.get_record(ELITE_ID)
	if int(record.get("encounter_count", 0)) != 1:
		failures.append("S04 确认后 encounter_count 应为 1，实际 %d" % int(record.get("encounter_count", 0)))
	if not NpcStoryBeatService.has_pending_beat(NPC_ID):
		failures.append("S04 首次确认遭遇后节拍仍未成立")

	# 回到 99F = 重新进入塔楼场景（真实路径）。旧塔楼先释放。
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# —— S05 回基地：站在迎宾锚点上，停巡，待播 ——
	tower = await _load_tower(failures)
	if tower == null:
		return
	npc = tower.find_npc(NPC_ID)
	if npc == null:
		failures.append("S05 重进基地后找不到 NPC")
		_finish_now(tower, failures)
		return
	var standby_anchor := tower.find_child(STANDBY_ANCHOR, true, false) as Node3D
	if standby_anchor == null:
		failures.append("S05 布置层缺少迎宾锚点『%s』（会退回巡逻起点，位置就不在归航点旁）" % STANDBY_ANCHOR)
	var snapshot := npc.get_snapshot()
	if not bool(snapshot.get("story_standby", false)):
		failures.append("S05 首遇之后回基地，NPC 没有站在边上等玩家")
	if bool(snapshot.get("moving", true)):
		failures.append("S05 迎宾站定期间 NPC 仍在走动")
	if str(snapshot.get("story_beat_id", "")) != BEAT_ID:
		failures.append("S05 待播节拍不是『%s』：『%s』" % [BEAT_ID, str(snapshot.get("story_beat_id", ""))])
	if standby_anchor != null:
		var standby_point: Vector3 = snapshot.get("standby_world", Vector3.ZERO)
		if standby_point.distance_to(standby_anchor.global_position) > 0.05:
			failures.append("S05 迎宾站位与作者锚点不一致：%s vs %s" % [str(standby_point), str(standby_anchor.global_position)])
		if npc.global_position.distance_to(standby_anchor.global_position) > 0.15:
			failures.append("S05 NPC 没有站到锚点上：%s" % str(npc.global_position))
	var standby_position: Vector3 = npc.global_position
	await get_tree().create_timer(1.0).timeout
	if standby_position.distance_to(npc.global_position) > 0.02:
		failures.append("S05 迎宾站定 1s 内位置漂移 %.3fm" % standby_position.distance_to(npc.global_position))

	# —— S06 玩家走近：自动开口（不需要按 E），台词逐字一致 ——
	var player := tower.player
	if player == null:
		failures.append("S06 塔楼没有玩家实例")
		_finish_now(tower, failures)
		return
	player.global_position = Vector3(0.0, BASE99_FLOOR_Y + 0.05, 5.0)
	for _frame in 8:
		await get_tree().physics_frame
	await get_tree().create_timer(0.4).timeout
	snapshot = npc.get_snapshot()
	if not bool(snapshot.get("story_beat_delivered", false)):
		failures.append("S06 玩家走进 %.1fm 后 NPC 没有开口（节拍未交付）" % NpcCharacter3D.HAIL_RADIUS)
	if bool(snapshot.get("moving", true)):
		failures.append("S06 开口时 NPC 仍在走动")
	var bark := npc.get_node_or_null("CharacterBark3D") as CharacterBark3D
	var bubble_text := bark.get_current_text() if bark != null else ""
	if bubble_text != FIRST_LINE:
		failures.append("S06 第一句气泡不是用户口径：『%s』" % bubble_text)
	var to_player := player.global_position - npc.global_position
	to_player.y = 0.0
	var expected_yaw := atan2(-to_player.x, -to_player.z)
	var yaw_gap := absf(wrapf(float(snapshot.get("yaw", 0.0)) - expected_yaw, -PI, PI))
	if yaw_gap > 0.20:
		failures.append("S06 开口时没有面向玩家：yaw 误差 %.2f rad" % yaw_gap)

	# —— S07 逐句轮播：第一句放完自动接第二句（玩家不按 E） ——
	var second_line := str(beat_lines[1]) if beat_lines.size() > 1 else ""
	var advanced := false
	for _i in 100:
		await get_tree().create_timer(0.1).timeout
		if bark != null and bark.get_current_text() == second_line:
			advanced = true
			break
	if not advanced:
		failures.append("S07 第一句放完后没有自动接第二句（『%s』）" % second_line)

	# —— S08 跨局落盘：整段说完才记 ——
	var history_key: String = NpcStoryBeatService.history_key(NPC_ID, BEAT_ID)
	var finished := false
	for _i in 100:
		await get_tree().create_timer(0.1).timeout
		if NpcStoryBeatService.is_beat_played(NPC_ID, BEAT_ID):
			finished = true
			break
	if not finished:
		failures.append("S08 整段说完了，服务仍认为节拍没播过")
	if not BaseManager.has_narrative_completed(history_key):
		failures.append("S08 节拍没有写进跨局档案（键 %s）" % history_key)
	if not history_key.begins_with(NpcStoryBeatService.HISTORY_KEY_PREFIX):
		failures.append("S08 节拍历史键没有走 npc_beat: 命名空间：%s" % history_key)
	if BaseManager.get_narrative_history(history_key).is_empty():
		failures.append("S08 节拍历史记录为空")

	# —— S09 气泡放完 → 回到巡逻线 ——
	var resumed_from: Vector3 = npc.global_position
	var resumed := false
	for _i in 120:
		await get_tree().create_timer(0.1).timeout
		if not bool(npc.get_snapshot().get("story_standby", true)) and resumed_from.distance_to(npc.global_position) > 0.10:
			resumed = true
			break
	if not resumed:
		failures.append("S09 台词播完后 NPC 没有恢复巡逻（仍在迎宾站定或没走动）")
	if bool(npc.get_snapshot().get("story_beat_pending", true)):
		failures.append("S09 台词播完后仍挂着待播节拍")

	# —— S10 再回一次基地：不再重复 ——
	player.global_position = Vector3(0.0, BASE99_FLOOR_Y + 0.05, 5.0)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	tower = await _load_tower(failures)
	if tower == null:
		return
	npc = tower.find_npc(NPC_ID)
	if npc == null:
		failures.append("S10 第三次进基地后找不到 NPC")
		_finish_now(tower, failures)
		return
	snapshot = npc.get_snapshot()
	if bool(snapshot.get("story_standby", false)):
		failures.append("S10 节拍已播过，NPC 又站到边上等玩家（不是一次性）")
	if bool(snapshot.get("story_beat_pending", false)):
		failures.append("S10 节拍已播过，重进基地又挂起待播节拍")
	player = tower.player
	if player != null:
		player.global_position = Vector3(0.0, BASE99_FLOOR_Y + 0.05, 5.0)
	# 旧气泡随旧塔楼一起释放，这里重新取新实例的（比较的是"有没有又冒出来"）。
	bark = npc.get_node_or_null("CharacterBark3D") as CharacterBark3D
	for _frame in 8:
		await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout
	if bool(npc.get_snapshot().get("story_beat_delivered", false)):
		failures.append("S10 重进基地后节拍又播了一遍")
	if bark != null and bark.get_current_text() == FIRST_LINE:
		failures.append("S10 重进基地后气泡里仍是那条迎宾台词")

	# —— S12 台词指向的二楼档案室真的存在，档案里也能查到收租人 ——
	var room := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	var archive_facility: Node3D = null
	if room != null:
		for node in room.find_children("*", "Node3D", true, false):
			var script: Variant = node.get_script()
			if script == null or not str((script as Script).resource_path).ends_with("BaseFacility3D.gd"):
				continue
			if str((node as Node3D).get("facility_id")) == ARCHIVE_FACILITY_ID:
				archive_facility = node as Node3D
				break
	if archive_facility == null:
		failures.append("S12 基地里没有『%s』设施 —— 台词让你去二楼看，二楼却没有终端" % ARCHIVE_FACILITY_ID)
	else:
		var clearance := archive_facility.global_position.y - BASE99_FLOOR_Y
		if clearance < SECOND_FLOOR_MIN_CLEARANCE:
			failures.append(
				"S12 档案终端离地只有 %.2fm，不像二楼（至少 %.1fm）" % [clearance, SECOND_FLOOR_MIN_CLEARANCE]
			)
	var encountered := EliteRosterService.get_encountered_elites()
	var ids: Array[String] = []
	for entry in encountered:
		ids.append(str(entry.get("elite_id", "")))
	if not ids.has(ELITE_ID):
		failures.append("S12 已遭遇列表里没有『%s』，档案室看不到它的信息" % ELITE_ID)

	_finish_now(tower, failures)


func _load_tower(failures: Array[String]) -> TowerDescent3D:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if packed == null:
		failures.append("TowerDescent3D 场景加载失败")
		return null
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	for _i in 6:
		await get_tree().process_frame
	await get_tree().physics_frame
	return tower


func _finish_now(owner_node: Node, failures: Array[String]) -> void:
	if owner_node != null and is_instance_valid(owner_node):
		owner_node.queue_free()
		await get_tree().process_frame
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE_NPC_STORY_BEAT_OK: 首遇收租人后回 99F，绿苔站到归航点边上，玩家走进 4m 自动说出指定台词并落盘一次，播完回巡逻线，重进基地不再重复；台词指向的二楼档案终端存在且能查到收租人")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
