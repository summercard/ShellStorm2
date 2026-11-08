extends Node
## 验收入口：**战败归航救援**（`BASE-RESCUE`，2026-11-08 业主设计）。
##
## 覆盖：
##   R01–R02 内容契约（两句用户原话逐字一致、单句长度仍在两行口径内）；
##   R03 没有救援暂存时**不演、不放箱子**；
##   R04 抽签规则（远征场景真实实例）：1–2 件携带物（背包 + 装备）＋ 1–2 件补给，
##        保险格里的那件**不入选**、同一实例不重复；
##   R05 塔楼死亡（非远征）不产生救援清单；
##   R06 有暂存 + 死亡归航入口：玩家趴着（`dead` 终点帧、姿态锁生效）、输入被独占、
##        绿苔钉在归航点边上、浅灰宝箱放在它旁边且装的就是暂存清单；
##   R07 第一句气泡 = 用户原话第一句；R08 自动接第二句；
##   R08b 按连败次数追加的第三句（2 次打趣 / 3 次无语 / 其余随机池，见 `NpcCatalog`）；
##   R09 说完起身：姿态清掉、输入归还、绿苔结束演出；
##   R10 开箱：暂存清空、箱内物资真实落地；R11 十秒后箱子消失并播出收租人离场特效；
##   R13 连续战败计数的所有权：远征战败 +1、塔楼死亡不动、成功撤离清零。
##
## ⚠️ 口径：真实塔楼场景 `TowerDescent3D.tscn`（99F 基地）与真实远征场景
## `ExpeditionLevel01_3D.tscn`。隔离的 `APPDATA` 由套件在 Autoload 之前设置。

const NPC_ID := "npc_base99_green"
const EXPECTED_LINES := [
	"啧啧，太危险了，看我把你捞回来了。",
	"感谢我吧，我还帮你捞回了点东西，下次去可要小心了。",
]
## 单句长度上限：演出把气泡换行放宽到 700px（≈14 汉字/行），两行 = 28 字。
## 超过就说明台词被改长了，气泡会排成三行、顶出画面上缘。
const MAX_LINE_CHARS := 28
const VANISH_DELAY_SECONDS := 10.0
const CHEST_NEAR_NPC_M := 1.4
const NPC_NEAR_PLAYER_M := 2.6
const SUPPLY_IDS := ["item_health_potion", "item_ammo_pack", "item_battery_s", "special_grenade"]
## 业主 2026-11-08 给的连败专属台词与随机池（逐字比对）。
const EXPECTED_STREAK_2 := [
	"看见那只僵尸了吗？接下来换你咬它了！",
	"但是你首先得先长上牙齿，啧啧。",
]
const EXPECTED_STREAK_3 := ["…………，你……"]
const EXPECTED_POOL := [
	"别泄气，这点小问题难不住你。",
	"世上无难事，只要肯攀登，以前一个很伟大的人说的。",
	"这次还不错，零件一个没少。",
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	await _run(failures)
	_finish(failures)


func _run(failures: Array[String]) -> void:
	BaseManager.force_save_failure_for_test = false
	BaseManager.replace_rescue_cache_for_test([])

	_check_content(failures)
	await _check_sampling(failures)

	# —— R03 没有暂存：不演、也没有箱子 ——
	var tower := await _load_base_tower(failures, GameEntryFlow.REASON_DEATH_RETURN_99F)
	if tower == null:
		return
	var rescue := tower.find_base_rescue()
	if rescue == null:
		failures.append("R03 99F 基地没有装配救援演出（find_base_rescue 为空）")
	else:
		var snapshot := rescue.get_snapshot()
		if str(snapshot.get("phase", "")) != "idle":
			failures.append("R03 没有救援暂存时阶段应为 idle，实际『%s』" % str(snapshot.get("phase", "")))
		if bool(snapshot.get("chest_present", false)):
			failures.append("R03 没有救援暂存却放出了宝箱")
	await _free_node(tower)

	# —— R06 有暂存 + 死亡归航：趴着、被锁、绿苔站边上、边上浅灰宝箱 ——
	var cache := _make_cache()
	BaseManager.replace_rescue_cache_for_test(cache)
	# 固定成"第 2 次连续战败"：连败变体是**确定的两句**，可以逐字断言。
	# 其余档位（1 次 / 4 次以上）走随机池，那部分在 R08b 用内容接口直接验。
	BaseManager.replace_rescue_defeat_streak_for_test(2)
	tower = await _load_base_tower(failures, GameEntryFlow.REASON_DEATH_RETURN_99F)
	if tower == null:
		return
	rescue = tower.find_base_rescue()
	if rescue == null:
		failures.append("R06 有暂存时仍然没有装配救援演出")
		await _free_node(tower)
		return
	var player := tower.player
	if player == null:
		failures.append("R06 基地里没有玩家实例")
		await _free_node(tower)
		return
	var npc := tower.find_npc(NPC_ID)
	if npc == null:
		failures.append("R06 基地里找不到 NPC『%s』" % NPC_ID)
	await _check_prone_and_staging(failures, tower, rescue, player, npc)
	await _check_lines(failures, npc, rescue)
	await _check_rise(failures, rescue, player, npc)
	await _check_chest_and_vanish(failures, rescue, player)

	# —— R12 暂存已开：重进基地不再演、不再放箱子 ——
	await _free_node(tower)
	tower = await _load_base_tower(failures, GameEntryFlow.REASON_DEATH_RETURN_99F)
	if tower != null:
		var again := tower.find_base_rescue()
		if again != null:
			var again_snapshot := again.get_snapshot()
			if str(again_snapshot.get("phase", "")) != "idle":
				failures.append(
					"R12 暂存已清空，重进基地仍在演：『%s』" % str(again_snapshot.get("phase", ""))
				)
			if bool(again_snapshot.get("chest_present", false)):
				failures.append("R12 暂存已清空，重进基地又放了一只救援箱")
		await _free_node(tower)
	BaseManager.replace_rescue_cache_for_test([])


# —— R01/R02 内容 ——

func _check_content(failures: Array[String]) -> void:
	var lines := NpcCatalog.get_rescue_lines(NPC_ID)
	if lines.size() != EXPECTED_LINES.size():
		failures.append("R01 救援台词应为 %d 句，实际 %d 句" % [EXPECTED_LINES.size(), lines.size()])
		return
	for index in EXPECTED_LINES.size():
		if lines[index] != EXPECTED_LINES[index]:
			failures.append(
				"R01 第 %d 句与业主原话不一致：『%s』" % [index + 1, lines[index]]
			)
	var full := "".join(EXPECTED_LINES)
	if NpcCatalog.get_rescue_full_text(NPC_ID) != full:
		failures.append("R01 救援台词全文与业主原话不一致：『%s』" % NpcCatalog.get_rescue_full_text(NPC_ID))
	for index in lines.size():
		if lines[index].length() > MAX_LINE_CHARS:
			failures.append(
				"R02 第 %d 句 %d 字，超过两行上限 %d 字" % [index + 1, lines[index].length(), MAX_LINE_CHARS]
			)
	# —— R08b 连败台词内容契约 ——
	var streak_2 := NpcCatalog.get_rescue_streak_lines(NPC_ID, 2)
	if streak_2 != EXPECTED_STREAK_2:
		failures.append("R08b 2 次连败台词与业主原话不一致：%s" % str(streak_2))
	var streak_3 := NpcCatalog.get_rescue_streak_lines(NPC_ID, 3)
	if streak_3 != EXPECTED_STREAK_3:
		failures.append("R08b 3 次连败台词与业主原话不一致：%s" % str(streak_3))
	var pool := NpcCatalog.get_rescue_pool_lines(NPC_ID)
	if pool != EXPECTED_POOL:
		failures.append("R08b 随机池与业主原话不一致：%s" % str(pool))
	# 1 次与 4 次以上都从池子里抽：两条不同 pick_index 必须落在池内且互不相同。
	var pick_a := NpcCatalog.get_rescue_streak_lines(NPC_ID, 1, 0)
	var pick_b := NpcCatalog.get_rescue_streak_lines(NPC_ID, 1, 1)
	var pick_c := NpcCatalog.get_rescue_streak_lines(NPC_ID, 7, 2)
	if pick_a.size() != 1 or pick_a[0] != EXPECTED_POOL[0]:
		failures.append("R08b 第 1 次战败没有从随机池取第 0 条：%s" % str(pick_a))
	if pick_b.size() != 1 or pick_b[0] != EXPECTED_POOL[1]:
		failures.append("R08b 随机池第 1 条取错：%s" % str(pick_b))
	if pick_c.size() != 1 or pick_c[0] != EXPECTED_POOL[2]:
		failures.append("R08b 4 次以上战败没有回到随机池：%s" % str(pick_c))
	# 每一句仍然必须在两行口径内。
	for group in [EXPECTED_STREAK_2, EXPECTED_STREAK_3, EXPECTED_POOL]:
		for line_value in group:
			if str(line_value).length() > MAX_LINE_CHARS:
				failures.append("R02 连败台词『%s』超过 %d 字" % [str(line_value), MAX_LINE_CHARS])

	await _check_streak_ownership(failures)


## R13：连续战败计数归 `BaseManager.commit_run_settlement` 所有，三条边界各自断言。
func _check_streak_ownership(failures: Array[String]) -> void:
	BaseManager.replace_rescue_defeat_streak_for_test(0)
	var request := {
		"transaction_id": "verify_rescue_streak:%d" % Time.get_ticks_usec(),
		"success": false,
		"kills": 0,
		"extraction_points": 0,
		"extraction_loot": [],
		"insurance_saved": [],
		"return_checkpoint": {},
		"rescue_items": [],
	}
	if not bool((BaseManager.commit_run_settlement(request) as Dictionary).get("success", false)):
		failures.append("R13 远征死亡结算提交失败，无法验证连败计数")
		return
	if BaseManager.get_rescue_defeat_streak() != 1:
		failures.append("R13 远征战败后连败计数应为 1，实际 %d" % BaseManager.get_rescue_defeat_streak())
	# 塔楼死亡（请求里没有 rescue_items）不动计数。
	var tower_death := request.duplicate(true)
	tower_death["transaction_id"] = "verify_rescue_streak_tower:%d" % Time.get_ticks_usec()
	tower_death.erase("rescue_items")
	BaseManager.commit_run_settlement(tower_death)
	if BaseManager.get_rescue_defeat_streak() != 1:
		failures.append("R13 塔楼死亡不该改变连败计数，实际 %d" % BaseManager.get_rescue_defeat_streak())
	# 成功撤离清零。
	var success_request := {
		"transaction_id": "verify_rescue_streak_ok:%d" % Time.get_ticks_usec(),
		"success": true,
		"kills": 0,
		"extraction_points": 0,
		"extraction_loot": [],
		"return_checkpoint": {},
	}
	BaseManager.commit_run_settlement(success_request)
	if BaseManager.get_rescue_defeat_streak() != 0:
		failures.append("R13 成功撤离后连败计数应清零，实际 %d" % BaseManager.get_rescue_defeat_streak())
	BaseManager.replace_rescue_defeat_streak_for_test(0)


# —— R04/R05 抽签 ——

func _check_sampling(failures: Array[String]) -> void:
	var tower := await _load_expedition_tower(failures)
	if tower == null:
		return
	var inventory := tower.get("_inventory") as InventoryModule
	var insurance := tower.get("_insurance") as InsuranceModule
	if inventory == null or insurance == null:
		failures.append("R04 远征场景缺少背包/保险模块")
		await _free_node(tower)
		return
	# 背包里放确定内容；其中一瓶药水进保险格，用来验证"保险箱里的不入选"。
	var potion := _make_item("item_health_potion")
	_add_to_inventory(inventory, potion, 1)
	var insured := _make_item("item_health_potion")
	_add_to_inventory(inventory, insured, 1)
	_add_to_inventory(inventory, _make_item("item_ammo_pack"), 12)
	_add_to_inventory(inventory, _make_item("item_battery_l"), 1)
	_add_to_inventory(inventory, _make_item("equipment_backpack_2"), 1)
	if not insurance.insure_item_direct(insured):
		failures.append("R04 无法把药水放进保险格（无法验证排除规则）")
	var insured_id := str(insured.get("item_instance_id", ""))
	var grants: Array = tower.call("_plan_rescue_items", inventory.get_slots_snapshot())
	if grants.is_empty():
		failures.append("R04 远征死亡没有抽到任何救援物资")
		await _free_node(tower)
		return
	var run_count := 0
	var supply_count := 0
	var allowed_run_ids := [
		"item_health_potion", "item_ammo_pack", "item_battery_l",
		"equipment_backpack_2", "weapon_pistol", "weapon_starter_rifle",
	]
	var seen := {}
	for value in grants:
		if not value is Dictionary:
			failures.append("R04 救援清单里出现非字典条目")
			continue
		var grant := value as Dictionary
		var item := (grant.get("item", {}) as Dictionary)
		var source := str(grant.get("rescue_source", ""))
		if str(item.get("id", "")) != str(grant.get("item_id", "")):
			failures.append(
				"R04 条目 item_id 与 item.id 不一致（会被地面发放整批退回）：%s vs %s"
					% [str(grant.get("item_id", "")), str(item.get("id", ""))]
			)
		var identity := str(item.get("item_instance_id", ""))
		if not identity.is_empty():
			if seen.has(identity):
				failures.append("R04 同一件物品被抽到了两次：%s" % identity)
			seen[identity] = true
		if source == "run":
			run_count += 1
			if insured_id == identity:
				failures.append("R04 保险格里的那件被当成救援物资抽回来了：%s" % identity)
			if not str(item.get("id", "")) in allowed_run_ids:
				failures.append("R04 救援物资出现意料之外的物品：%s" % str(item.get("id", "")))
		elif source == "supply":
			supply_count += 1
			if not str(item.get("id", "")) in SUPPLY_IDS:
				failures.append("R04 补给出现意料之外的物品：%s" % str(item.get("id", "")))
		else:
			failures.append("R04 条目缺少 rescue_source：%s" % str(grant))
	if run_count < 1 or run_count > 2:
		failures.append("R04 携带物件数应为 1–2，实际 %d" % run_count)
	if supply_count < 1 or supply_count > 2:
		failures.append("R04 补给件数应为 1–2，实际 %d" % supply_count)

	# —— R05 塔楼（非远征）死亡不产生救援清单 ——
	await _free_node(tower)
	var base_tower := await _load_base_tower(failures, GameEntryFlow.REASON_DEATH_RETURN_99F)
	if base_tower != null:
		var base_grants: Array = base_tower.call("_plan_rescue_items", [])
		if not base_grants.is_empty():
			failures.append("R05 塔楼死亡不该抽出救援物资，实际 %d 件" % base_grants.size())
		await _free_node(base_tower)


# —— R06 趴下与站位 ——

func _check_prone_and_staging(
	failures: Array[String], tower: TowerDescent3D, rescue: Base99Rescue3D,
	player: Player3D, npc: NpcCharacter3D
) -> void:
	if not rescue.is_holding_player_input():
		failures.append("R06 演出没有独占玩家输入")
	if not bool(player.get("input_locked")):
		failures.append("R06 演出期间玩家的 input_locked 仍为 false（逐帧锁同步把它顶掉了）")
	var pose := _pose_snapshot(player)
	if not bool(pose.get("active", false)):
		failures.append("R06 玩家没有进入叙事姿态（不是趴着的）")
	elif str(pose.get("clip", "")) != Base99Rescue3D.PRONE_CLIP:
		failures.append("R06 趴着的剪辑不是『%s』，实际『%s』" % [Base99Rescue3D.PRONE_CLIP, str(pose.get("clip", ""))])
	elif absf(float(pose.get("phase", 0.0)) - 1.0) > 0.05:
		failures.append("R06 趴着的相位应停在 1.0（倒地终点帧），实际 %.2f" % float(pose.get("phase", 0.0)))
	if npc == null:
		return
	var npc_snapshot := npc.get_snapshot()
	if not bool(npc_snapshot.get("scripted_appearance", false)):
		failures.append("R06 绿苔没有进入演出站位（仍在巡逻线上）")
	var npc_point: Vector3 = npc_snapshot.get("scripted_point", Vector3.ZERO)
	var to_player := npc_point - player.global_position
	to_player.y = 0.0
	if to_player.length() > NPC_NEAR_PLAYER_M:
		failures.append("R06 绿苔离趴着的玩家 %.2fm，不算『站在边上』" % to_player.length())
	var chest := rescue.get_rescue_chest()
	if chest == null:
		failures.append("R06 演出开始时边上没有宝箱")
		return
	var chest_snapshot := chest.get_chest_snapshot()
	if not bool(chest_snapshot.get("has_explicit_grants", false)):
		failures.append("R06 救援箱没有携带明确奖励清单（会被当成普通箱按池子抽）")
	if int(chest_snapshot.get("explicit_grant_count", 0)) != rescue.get_rescue_grants().size():
		failures.append(
			"R06 箱内清单件数与暂存不一致：%d vs %d"
				% [int(chest_snapshot.get("explicit_grant_count", 0)), rescue.get_rescue_grants().size()]
		)
	if bool(chest_snapshot.get("body_has_palette_texture", true)):
		failures.append("R06 救援箱身板仍绑着色盘贴图（不是浅灰箱，只是压暗了）")
	var body_color: Color = chest_snapshot.get("body_albedo_color", Color.BLACK)
	var tint := Base99Rescue3D.CHEST_TINT
	var color_gap := absf(body_color.r - tint.r) + absf(body_color.g - tint.g) + absf(body_color.b - tint.b)
	if color_gap > 0.08:
		failures.append("R06 救援箱身板色不是约定的浅灰：%s" % str(body_color))
	var to_chest := chest.global_position - npc.global_position
	to_chest.y = 0.0
	if to_chest.length() > CHEST_NEAR_NPC_M:
		failures.append("R06 宝箱离绿苔 %.2fm，不算『它边上』" % to_chest.length())


# —— R07/R08 台词 ——

func _check_lines(
	failures: Array[String], npc: NpcCharacter3D, rescue: Base99Rescue3D
) -> void:
	if npc == null:
		return
	var bark := npc.get_node_or_null("CharacterBark3D") as CharacterBark3D
	if bark == null:
		failures.append("R07 绿苔没有气泡挂载点，台词念不出来")
		return
	var first_ok := false
	for _i in 200:
		await get_tree().create_timer(0.05).timeout
		if bark.get_current_text() == EXPECTED_LINES[0]:
			first_ok = true
			break
	if not first_ok:
		failures.append("R07 第一句气泡不是业主原话：『%s』" % bark.get_current_text())
	var second_ok := false
	for _i in 200:
		await get_tree().create_timer(0.05).timeout
		if bark.get_current_text() == EXPECTED_LINES[1]:
			second_ok = true
			break
	if not second_ok:
		failures.append("R08 第一句放完后没有自动接第二句：『%s』" % bark.get_current_text())
	# —— R08b 第 2 次连败：两句固定台词之后必须接上"僵尸"那句 ——
	var streak_line_index := 0
	for expected_line in EXPECTED_STREAK_2:
		var seen := false
		for _i in 200:
			await get_tree().create_timer(0.05).timeout
			if bark.get_current_text() == expected_line:
				seen = true
				break
		if not seen:
			failures.append(
				"R08b 第二次连败第 %d 句连败台词没出现：『%s』，当前『%s』"
					% [streak_line_index + 1, expected_line, bark.get_current_text()]
			)
		streak_line_index += 1
	var staged_lines: Array = rescue.get_snapshot().get("script_lines", []) as Array
	if staged_lines.size() != EXPECTED_LINES.size() + EXPECTED_STREAK_2.size():
		failures.append(
			"R08b 本次演出应有 %d 句台词，实际 %d 句：%s"
				% [EXPECTED_LINES.size() + EXPECTED_STREAK_2.size(), staged_lines.size(), str(staged_lines)]
		)
	else:
		for index in EXPECTED_STREAK_2.size():
			if str(staged_lines[EXPECTED_LINES.size() + index]) != EXPECTED_STREAK_2[index]:
				failures.append("R08b 快照里的连败台词顺序不对：%s" % str(staged_lines))


# —— R09 起身 ——

func _check_rise(
	failures: Array[String], rescue: Base99Rescue3D, player: Player3D, npc: NpcCharacter3D
) -> void:
	var risen := false
	for _i in 400:
		await get_tree().create_timer(0.05).timeout
		if not rescue.is_holding_player_input():
			risen = true
			break
	if not risen:
		failures.append("R09 两句说完后仍没有交还操作（输入一直被独占）")
	var pose := _pose_snapshot(player)
	if bool(pose.get("active", false)):
		failures.append("R09 起身后叙事姿态没有清掉，玩家会一直僵在倒地剪辑上")
	if bool(player.get("input_locked")):
		failures.append("R09 起身后玩家 input_locked 仍为 true，键盘/开枪全废")
	if str(rescue.get_phase_name()) != "chest_waiting":
		failures.append("R09 起身后阶段应为 chest_waiting，实际『%s』" % rescue.get_phase_name())
	if npc != null and bool(npc.get_snapshot().get("scripted_appearance", true)):
		failures.append("R09 演出结束后绿苔仍被钉在演出站位上")


# —— R10/R11 开箱与消失 ——

func _check_chest_and_vanish(
	failures: Array[String], rescue: Base99Rescue3D, player: Player3D
) -> void:
	var chest := rescue.get_rescue_chest()
	if chest == null:
		failures.append("R10 演出结束后找不到救援箱")
		return
	var room := _find_room_of(chest)
	if room == null:
		failures.append("R10 救援箱不在任何房间里（找不到落地目标）")
		return
	# 走到箱子边上 —— 交互是 1.5m 热区，直接瞬移过去等两帧物理。
	player.global_position = chest.global_position + Vector3(0.0, 0.05, 1.1)
	for _frame in 10:
		await get_tree().physics_frame
	if not chest.perform_interaction(player, {}):
		failures.append("R10 站在箱子边上按 E 没有触发开箱（不在交互范围内）")
		return
	var burst_delay := chest.get_open_burst_delay()
	await get_tree().create_timer(burst_delay + 1.0).timeout
	if not chest.is_opened():
		failures.append("R10 宝箱没有进入已开状态")
	if BaseManager.has_rescue_cache():
		failures.append("R10 开箱后救援暂存没有被清空（会重复发放）")
	var landed := _ground_item_ids(room)
	if landed.is_empty():
		failures.append("R10 开箱后地上没有落下任何物资")
	# —— R11 十秒后消失 + 收租人离场特效 ——
	var vanished := false
	var vfx_seen := false
	for _i in int((VANISH_DELAY_SECONDS + 4.0) / 0.05):
		await get_tree().create_timer(0.05).timeout
		if not vfx_seen and _teleport_out_active():
			vfx_seen = true
		if str(rescue.get_phase_name()) == "vanished":
			vanished = true
			if not vfx_seen:
				vfx_seen = _teleport_out_active()
			break
	if not vanished:
		failures.append("R11 开箱后 %.0fs 内箱子没有消失" % VANISH_DELAY_SECONDS)
	if not vfx_seen:
		failures.append("R11 消失时没有播出收租人离场特效（VFX-TELEPORT-OUT-3D）")
	await get_tree().create_timer(1.4).timeout
	if rescue.get_rescue_chest() != null:
		failures.append("R11 箱子消失后节点没有释放")


# —— 工具 ——

func _pose_snapshot(player: Player3D) -> Dictionary:
	var avatar: Variant = player.get("avatar")
	if avatar is Object and (avatar as Object).has_method("get_narrative_pose_snapshot"):
		return (avatar as Object).call("get_narrative_pose_snapshot") as Dictionary
	return {}


func _teleport_out_active() -> bool:
	var active: Dictionary = VfxPool.get("_active") as Dictionary
	var bucket: Array = active.get(VfxPool3D.FX01_TELEPORT_OUT, []) as Array
	for value in bucket:
		var effect := value as VfxEffectBase3D
		if effect != null and is_instance_valid(effect) and effect.is_inside_tree():
			return true
	return false


func _find_room_of(node: Node) -> DungeonRoom3D:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor is DungeonRoom3D:
			return cursor as DungeonRoom3D
		cursor = cursor.get_parent()
	return null


func _ground_item_ids(room: DungeonRoom3D) -> Array[String]:
	var ids: Array[String] = []
	for node in room.find_children("*", "", true, false):
		var pickup := node as GroundLootPickup3D
		if pickup == null or not is_instance_valid(pickup):
			continue
		var data := pickup.get("item_data") as Dictionary
		if data == null:
			continue
		ids.append(str(data.get("id", "")))
	return ids


func _make_item(item_id: String) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	if item.is_empty():
		push_error("R04 物品注册表里没有『%s』" % item_id)
		return {}
	item["count"] = 1
	return BaseShopService.ensure_item_instance(item)


func _add_to_inventory(inventory: InventoryModule, item: Dictionary, count: int) -> void:
	if item.is_empty():
		return
	if inventory.add_item(item, count) <= 0:
		push_error("R04 物品『%s』放不进背包" % str(item.get("id", "")))


func _make_cache() -> Array:
	var cache: Array = []
	for entry in [["weapon_pistol", "run"], ["item_health_potion", "run"], ["special_grenade", "supply"]]:
		var item_id := str(entry[0])
		var item := _make_item(item_id)
		if item.is_empty():
			continue
		cache.append({
			"kind": "item",
			"item_id": item_id,
			"item": item,
			"count": 1,
			"rescue_source": str(entry[1]),
		})
	return cache


func _load_base_tower(failures: Array[String], reason: String) -> TowerDescent3D:
	GameEntryFlow.request_gameplay_entry(reason, GameEntryFlow.SPAWN_BASE_99F)
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if packed == null:
		failures.append("塔楼场景加载失败")
		return null
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	for _i in 10:
		await get_tree().process_frame
	await get_tree().physics_frame
	return tower


func _load_expedition_tower(failures: Array[String]) -> TowerDescent3D:
	GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT, GameEntryFlow.SPAWN_SAVED_PROGRESS
	)
	var packed := load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene
	if packed == null:
		failures.append("远征01 场景加载失败")
		return null
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	for _i in 10:
		await get_tree().process_frame
	await get_tree().physics_frame
	return tower


func _free_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	for _frame in 3:
		await get_tree().process_frame


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"BASE99_RESCUE_OK: 远征阵亡回 99F 后玩家趴着并被锁住，绿苔站在边上逐句说出"
			+ "业主两句原话，说完起身交还操作，边上浅灰宝箱装的正是 1–2 件携带物"
			+ "（保险格除外）＋ 1–2 件补给，开箱清空暂存、10 秒后用收租人离场特效消失"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
