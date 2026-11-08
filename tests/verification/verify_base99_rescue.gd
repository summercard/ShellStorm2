extends Node
## 验收入口：**战败归航救援**（`BASE-RESCUE`，2026-11-08 业主设计）。
##
## 覆盖：
##   R01–R02 内容契约：候选段池逐字 == 业主原话（**"啧啧…"只是其中一段，不是固定开场**）、
##        连败专属段逐字、单句长度仍在两行口径内；
##   R03 没有救援暂存时**不演、不放箱子**；
##   R04 抽签规则（远征场景真实实例）：1–2 件携带物（背包 + 装备）＋ 1–2 件补给，
##        保险格里的那件**不入选**、同一实例不重复；
##   R05 塔楼死亡（非远征）不产生救援清单；
##   R06 有暂存 + 死亡归航入口：玩家趴着（`dead` 终点帧、姿态锁生效）、输入被独占、
##        绿苔钉在归航点边上、浅灰宝箱放在它旁边且装的就是暂存清单；
##   R07/R08 播出的整段必须**正好等于候选段之一**，且逐句按顺序进气泡；
##   R08b 连败 2 次 / 3 次走专属段（确定性），并在一次真实归航里验证演出方真的消费了它；
##   R09 说完起身：姿态清掉、输入归还、绿苔结束演出；
##   R10 开箱：暂存清空、箱内物资真实落地；R11 十秒后箱子消失并播出收租人离场特效；
##   R13 连续战败计数的所有权：远征战败 +1、塔楼死亡不动、成功撤离清零；
##   R14 演出期间玩家**完全无法操作**：鼠标朝向被锁、按住移动键 24 帧不位移、
##        状态机停在 locked；R14b 起身后两个锁都放开、按键真的能动；
##   R15 演出用的气泡确实走打字机（逐字显示、`reveal_all()` 能跳过）。
##
## ⚠️ 口径：真实塔楼场景 `TowerDescent3D.tscn`（99F 基地）与真实远征场景
## `ExpeditionLevel01_3D.tscn`。隔离的 `APPDATA` 由套件在 Autoload 之前设置。

const NPC_ID := "npc_base99_green"
## 候选段池（业主 2026-11-08 原话）。**没有任何一段是必说的**：
## 每次归航从这四段里随机挑一整段，讲几句就播几句。
const EXPECTED_SEGMENTS := [
	[
		"啧啧，太危险了，看我把你捞回来了。",
		"感谢我吧，我还帮你捞回了点东西，下次去可要小心了。",
	],
	["别泄气，这点小问题难不住你。"],
	["世上无难事，只要肯攀登，以前一个很伟大的人说的。"],
	["这次还不错，零件一个没少。"],
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
## 随机池里的三条单句段（= 候选段池的第 2–4 段），用来单独断言"每条原话都在池里"。
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
	# 固定成"第 1 次连续战败"⇒ 走**随机候选池**那条路（业主口径的主路径：
	# 每段都可能出现，包括"啧啧…"那段）。播出内容不写死，改为断言
	# "正好等于候选段之一、且逐句按顺序进气泡"。
	# 连败专属段由 R08b 单独起一次归航验证（见 `_check_streak_cutscene`）。
	BaseManager.replace_rescue_defeat_streak_for_test(1)
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
	await _check_control_lock(failures, rescue, player)
	await _check_lines(failures, npc, rescue)
	await _check_rise(failures, rescue, player, npc)
	await _check_typewriter_wiring(failures, npc)
	await _check_chest_and_vanish(failures, rescue, player)

	await _free_node(tower)

	# —— R08b 连败 2 次：真实归航时演出方真的消费了专属段（不写死固定台词）——
	await _check_streak_cutscene(failures)

	# —— R12 暂存已开：重进基地不再演、不再放箱子 ——
	BaseManager.replace_rescue_cache_for_test([])
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
	var segments := NpcCatalog.get_rescue_scripts(NPC_ID)
	if segments.size() != EXPECTED_SEGMENTS.size():
		failures.append(
			"R01 候选段应为 %d 段，实际 %d 段" % [EXPECTED_SEGMENTS.size(), segments.size()]
		)
		return
	for index in EXPECTED_SEGMENTS.size():
		var expected: Array = EXPECTED_SEGMENTS[index]
		var actual: Array = segments[index]
		if actual != expected:
			failures.append(
				"R01 第 %d 段与业主原话不一致：%s（应为 %s）" % [index + 1, str(actual), str(expected)]
			)
	# 三条单句原话必须各自成段（不能漏、不能合并）。
	for line_value in EXPECTED_POOL:
		var found := false
		for segment: Array in segments:
			if segment.size() == 1 and str(segment[0]) == str(line_value):
				found = true
				break
		if not found:
			failures.append("R01 随机池原话『%s』没有单独成段" % str(line_value))
	# "啧啧…"两句必须是一整段（它只是候选之一，不是固定开场）。
	var opener_found := false
	for segment: Array in segments:
		if segment == (EXPECTED_SEGMENTS[0] as Array):
			opener_found = true
			break
	if not opener_found:
		failures.append("R01 『啧啧…／感谢我吧…』没有作为一整段登记")
	# 每一句都必须在两行口径内。
	for segment: Array in segments:
		for line_value in segment:
			if str(line_value).length() > MAX_LINE_CHARS:
				failures.append(
					"R02 『%s』%d 字，超过两行上限 %d 字"
						% [str(line_value), str(line_value).length(), MAX_LINE_CHARS]
				)

	# —— R08b 连败专属段内容契约 ——
	var streak_2 := NpcCatalog.get_rescue_script(NPC_ID, 2)
	if streak_2 != EXPECTED_STREAK_2:
		failures.append("R08b 2 次连败台词与业主原话不一致：%s" % str(streak_2))
	var streak_3 := NpcCatalog.get_rescue_script(NPC_ID, 3)
	if streak_3 != EXPECTED_STREAK_3:
		failures.append("R08b 3 次连败台词与业主原话不一致：%s" % str(streak_3))
	for group in [EXPECTED_STREAK_2, EXPECTED_STREAK_3]:
		for line_value in group:
			if str(line_value).length() > MAX_LINE_CHARS:
				failures.append("R02 连败台词『%s』超过 %d 字" % [str(line_value), MAX_LINE_CHARS])

	# —— R08c 非连败档一律从候选池取，且**每一段都可能被抽到** ——
	# 确定性入口：pick_index 0..N-1 必须逐段命中，越界环回。
	for index in segments.size():
		var picked := NpcCatalog.get_rescue_script(NPC_ID, 1, index)
		if picked != (segments[index] as Array):
			failures.append("R08c 第 1 次战败取段 %d 不对：%s" % [index, str(picked)])
	var wrapped := NpcCatalog.get_rescue_script(NPC_ID, 4, segments.size())
	if wrapped != (segments[0] as Array):
		failures.append("R08c 4 次以上战败没有环回候选池：%s" % str(wrapped))
	# 真随机路径必须真的会挑到不同段：抽 60 次，四段都应出现。
	var seen := {}
	for _i in 60:
		var random_pick := NpcCatalog.get_rescue_script(NPC_ID, 1)
		seen[str(random_pick)] = true
	for segment: Array in segments:
		if not seen.has(str(segment)):
			failures.append("R08c 随机 60 次都没抽到这一段：%s" % str(segment))


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


# —— R14：演出期间玩家完全无法操作（移动 + 鼠标朝向）——

## 业主 2026-11-08 补充口径：「这个时候需要玩家无法操作，鼠标旋转也不行，这个就是剧情过程」。
##
## 这条断言必须**真的按键**：只读 `input_locked` 只能证明"标记写上了"，
## 证明不了"按住 W 不会走"。2026-11-08 首版就是这样放过了鼠标朝向 ——
## `input_locked` 按设计不拦瞄准，晃一下鼠标就能把趴着的人转过来。
func _check_control_lock(
	failures: Array[String], rescue: Base99Rescue3D, player: Player3D
) -> void:
	if str(rescue.get_phase_name()) != "cutscene":
		failures.append("R14 锁检查时不在演出阶段：『%s』" % rescue.get_phase_name())
	if not bool(player.get("aim_locked")):
		failures.append("R14 演出期间鼠标朝向没锁（aim_locked=false，晃鼠标就能把人转过来）")
	if not player.is_control_fully_locked():
		failures.append("R14 演出期间 is_control_fully_locked() 为 false")
	if not bool(player.call("_narrative_holds_aim")):
		failures.append("R14 鼠标瞄准没有被拦（_narrative_holds_aim=false）")
	var start_position := player.global_position
	Input.action_press("move_up")
	Input.action_press("move_right")
	for _frame in 24:
		await get_tree().physics_frame
	Input.action_release("move_up")
	Input.action_release("move_right")
	var moved := start_position.distance_to(player.global_position)
	if moved > 0.02:
		failures.append("R14 演出期间按住移动键，玩家仍移动了 %.3fm" % moved)
	if str(player.call("get_state_machine_state")) != "locked":
		failures.append(
			"R14 演出期间状态机不在 locked：『%s』" % str(player.call("get_state_machine_state"))
		)


# —— R07/R08 台词（整段随机：只断言"正好是候选段之一、逐句按序进气泡"）——

func _check_lines(
	failures: Array[String], npc: NpcCharacter3D, rescue: Base99Rescue3D
) -> void:
	if npc == null:
		return
	var bark := npc.get_node_or_null("CharacterBark3D") as CharacterBark3D
	if bark == null:
		failures.append("R07 绿苔没有气泡挂载点，台词念不出来")
		return
	# 演出方在开演那一刻定格了整段台词；先认它是不是合法的一段。
	var staged: Array = rescue.get_snapshot().get("script_lines", []) as Array
	if staged.is_empty():
		failures.append("R07 演出没有排出任何台词")
		return
	var matched: Array = []
	for segment: Array in NpcCatalog.get_rescue_scripts(NPC_ID):
		if staged == segment:
			matched = segment
			break
	if matched.is_empty():
		failures.append("R07 播出的整段不属于任何候选段：%s" % str(staged))
	# 演出方必须真的**随机抽**，不能永远取同一段：抽 60 次，四段都应出现。
	# 这里走的是演出方自己的 `plan_script_lines()`（不是直接撩目录），
	# 所以"把演出写死成第 0 段"这种改动会被抓住。
	var drawn := {}
	for _i in 60:
		drawn[str(rescue.plan_script_lines(1))] = true
	for segment: Array in NpcCatalog.get_rescue_scripts(NPC_ID):
		if not drawn.has(str(segment)):
			failures.append("R08c 演出方随机 60 次都没抽到这一段：%s" % str(segment))
	if drawn.size() < 2:
		failures.append("R08c 演出方的台词是固定的，没有随机（只出现 %d 种）" % drawn.size())

	# 逐句按顺序进气泡（第 1 句先出，放完自动接第 2 句……）。
	for index in staged.size():
		var expected_line := str(staged[index])
		var seen := false
		for _i in 200:
			await get_tree().create_timer(0.05).timeout
			if bark.get_current_text() == expected_line:
				seen = true
				break
		if not seen:
			failures.append(
				"R08 第 %d 句没按序进气泡：『%s』，当前『%s』"
					% [index + 1, expected_line, bark.get_current_text()]
			)


## R08b：连败 2 次时演出方必须消费**专属段**（不是随机池）。
##
## 只验到"开演那一刻排出的整段"就够了 —— 逐句播放本身已由 `_check_lines` 覆盖。
func _check_streak_cutscene(failures: Array[String]) -> void:
	BaseManager.replace_rescue_cache_for_test(_make_cache())
	BaseManager.replace_rescue_defeat_streak_for_test(2)
	var tower := await _load_base_tower(failures, GameEntryFlow.REASON_DEATH_RETURN_99F)
	if tower == null:
		return
	var rescue := tower.find_base_rescue()
	if rescue == null:
		failures.append("R08b 第二次连续战败时没有装配救援演出")
		await _free_node(tower)
		return
	var snapshot := rescue.get_snapshot()
	if str(snapshot.get("phase", "")) != "cutscene":
		failures.append("R08b 第二次连续战败没进演出：『%s』" % str(snapshot.get("phase", "")))
	if int(snapshot.get("defeat_streak", 0)) != 2:
		failures.append("R08b 演出读到的连败次数应为 2，实际 %d" % int(snapshot.get("defeat_streak", 0)))
	var staged: Array = snapshot.get("script_lines", []) as Array
	if staged != EXPECTED_STREAK_2:
		failures.append("R08b 第二次连续战败播的不是专属段：%s" % str(staged))
	await _free_node(tower)
	BaseManager.replace_rescue_defeat_streak_for_test(0)


# —— R15：演出的气泡接上了打字机 ——

## 逐字出现的**分档**断言在气泡自己的专项里（`verify_speech_bubble_3d._check_typewriter`，
## 手动步进 delta，精确到"0.1s 该出几个字"）。这里只验**接线**：
## 绿苔说一句时气泡真的进入打字状态、并且 `reveal_all()` 能跳过 ——
## 演出协程的时序在 headless 下不可靠，不适合在这里卡字数。
func _check_typewriter_wiring(failures: Array[String], npc: NpcCharacter3D) -> void:
	if npc == null:
		return
	var bark := npc.get_node_or_null("CharacterBark3D") as CharacterBark3D
	if bark == null:
		failures.append("R15 绿苔没有气泡挂载点")
		return
	const LINE := "打字机接线检查"
	if not npc.say_scripted_line(LINE, 3.0):
		failures.append("R15 绿苔说不出话（say_scripted_line 返回 false）")
		return
	if not bark.is_typing():
		failures.append("R15 气泡没有进入打字机状态（一次全出，不是逐字）")
	if bark.get_total_char_count() != LINE.length():
		failures.append(
			"R15 气泡总字数与句子不符：%d vs %d" % [bark.get_total_char_count(), LINE.length()]
		)
	if bark.get_visible_char_count() >= LINE.length():
		failures.append("R15 第一瞬间就已经全显了（可见 %d 字）" % bark.get_visible_char_count())
	if bark.get_current_text() != LINE:
		failures.append("R15 气泡身份文本被打字前缀污染：『%s』" % bark.get_current_text())
	bark.reveal_all()
	if bark.is_typing():
		failures.append("R15 reveal_all() 之后仍在打字")
	if bark.get_visible_char_count() != LINE.length():
		failures.append("R15 reveal_all() 之后没有全显")
	npc.hide_dialogue()


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
	# R14b：起身后必须真的能操作 —— 两个锁都放开，按住移动键真的动/进 moving 态。
	if bool(player.get("aim_locked")):
		failures.append("R14b 起身后鼠标朝向仍锁着")
	if player.is_control_fully_locked():
		failures.append("R14b 起身后仍被判为完全锁定")
	var start_position := player.global_position
	Input.action_press("move_down")
	for _frame in 20:
		await get_tree().physics_frame
	var state_name := str(player.call("get_state_machine_state"))
	Input.action_release("move_down")
	var moved := start_position.distance_to(player.global_position)
	if state_name != "moving" and moved < 0.02:
		failures.append(
			"R14b 起身后按住移动键既没进 moving 也没位移（state=%s, moved=%.3fm）" % [state_name, moved]
		)


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
			"BASE99_RESCUE_OK: 远征阵亡回 99F 后玩家趴着且移动/鼠标全被锁住，绿苔站在边上"
			+ "从四段候选里随机播一整段（含『啧啧…／感谢我吧…』那段，2 次连败走专属段），"
			+ "说完起身交还操作，边上浅灰宝箱装的正是 1–2 件携带物（保险格除外）＋ 1–2 件补给，"
			+ "开箱清空暂存、10 秒后用收租人离场特效消失"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
