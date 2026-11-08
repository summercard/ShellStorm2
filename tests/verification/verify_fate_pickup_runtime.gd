extends Node
## 持久化端到端验收：正式远征03、GroundLoot 唯一构造口、命运卡凭据、宝箱 pending、拟态恢复。
##
## APPDATA、FATE_PICKUP_PROBE_DIR 与 FATE_PICKUP_APPDATA 必须由启动器在 Autoload 之前设置。
## `故障注入` 标记的步骤只验证既有失败收口/兼容入口，不冒充自然游玩流程。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const RUN_SEED := 77003244
const LANDING_WAIT_S := GroundLootPickup3D.SPAWN_FIRST_LANDING_S \
	+ GroundLootPickup3D.SPAWN_BOUNCE_DURATIONS_S[0] \
	+ GroundLootPickup3D.SPAWN_BOUNCE_DURATIONS_S[1]
const OUTPUT_ENV := "FATE_PICKUP_PROBE_DIR"
const APPDATA_ENV := "FATE_PICKUP_APPDATA"

var _failures: Array[String] = []
var _injected_faults: Array[String] = []
var _dungeon: Dungeon3D
var _report_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_report_dir = OS.get_environment(OUTPUT_ENV).replace("\\", "/")
	if not _verify_isolation():
		_finish(2)
		return
	if _report_dir.is_empty() or not _report_dir.is_absolute_path():
		_fail("未执行：缺少由 scripts/workspace_paths.py 定位的工程外产物目录")
		_finish(2)
		return
	DirAccess.make_dir_recursive_absolute(_report_dir)
	print("FATE_PICKUP_PROBE appdata=%s user_data=%s output=%s" % [
		OS.get_environment(APPDATA_ENV), OS.get_user_data_dir(), _report_dir
	])

	_dungeon = EXPEDITION_SCENE.instantiate() as Dungeon3D
	if _dungeon == null:
		_fail("正式远征03场景实例化失败")
		_finish(1)
		return
	_dungeon.test_mode = true
	_dungeon.run_seed_override = RUN_SEED
	add_child(_dungeon)
	await _wait_for_dungeon()
	if _dungeon.player == null or (_dungeon.get("_room_by_id") as Dictionary).is_empty():
		_fail("正式远征03未完成运行时装配")
		_finish(1)
		return

	var start := (_dungeon.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
	var chest_room := await _find_chest_room()
	if start == null or chest_room == null:
		_fail("正式远征03缺少 start 或宝箱房")
		_finish(1)
		return

	await _verify_character_fate_chain(chest_room)
	await _verify_fate_pickup_matrix(chest_room)
	await _verify_normal_chest_pending(chest_room, start)
	await _verify_mimic_snapshot_and_kill(chest_room, start)
	_verify_old_mimic_identity(chest_room.room_id)

	_finish(0 if _failures.is_empty() else 1)


func _verify_isolation() -> bool:
	var appdata := OS.get_environment(APPDATA_ENV).replace("\\", "/").trim_suffix("/")
	if appdata.is_empty() or not appdata.is_absolute_path():
		_fail("未执行：APPDATA 未由启动器隔离")
		return false
	var user_dir := OS.get_user_data_dir().replace("\\", "/").to_lower()
	if not user_dir.begins_with(appdata.to_lower() + "/") and user_dir != appdata.to_lower():
		_fail("未执行：Godot user:// 不在隔离 APPDATA 下：%s" % OS.get_user_data_dir())
		return false
	return true


func _wait_for_dungeon() -> void:
	for _frame in range(300):
		if _dungeon != null and not (_dungeon.get("_room_by_id") as Dictionary).is_empty():
			return
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _verify_character_fate_chain(room: DungeonRoom3D) -> void:
	print("--- 角色二级命运：Enemy3D → kill_recorded → MapFateTriggers → 专用凭据 ---")
	await _enter_room(room)
	var player := _dungeon.player
	var old_rules := (player.get_character_fate_snapshot().get("kill_rules", []) as Array).duplicate(true)
	var duplicate_rule := {
		"kill_threshold": 1,
		"grant_probability": 1.0,
		"chance": 1.0,
		"currency_cost": 30,
		"kills": 0,
	}
	player._character_fate["kill_rules"] = [duplicate_rule.duplicate(true), duplicate_rule.duplicate(true)]
	var trigger := _dungeon.get("_map_fate_triggers") as MapFateTriggers
	_check(trigger != null, "正式远征缺少 MapFateTriggers 宿主")
	var direct_requests := player.on_fate_kill_recorded()
	_check(direct_requests.size() == 2, "双同规则没有逐条生成请求")
	_check(str(direct_requests[0].get("request_id", "")) != str(direct_requests[1].get("request_id", "")), "双同规则 request_id 发生碰撞")
	# 使用正式 _spawn_enemy_batch 生成一只低血量普通 Enemy3D 作为自然链路夹具。
	# 这不是伪造 kill_recorded：实例化、连接 killed、登记房间成员和死亡回调都走生产入口；
	# 只避免把抓握大师/拟态箱等有特殊无敌语义的现有实体误当成普通可击杀对象。
	var enemy_room := room
	await _enter_room(enemy_room)
	var live_enemy: Enemy3D = _spawn_formal_character_verification_enemy(enemy_room)
	var saved_room_id := str(_dungeon.get("_current_room_id"))
	_dungeon.set("_current_room_id", "verification_missing_room")
	_injected_faults.append("角色凭据落地失败通过错误 current_room_id 注入")
	var deferred_report := _dungeon.spawn_character_fate_pickups([direct_requests[0]])
	_check((deferred_report.get("deferred", []) as Array).size() == 1, "角色凭据落地失败没有保留 deferred")
	_check(((_dungeon.get("_character_fate_delivery") as Dictionary).get("pending:%s" % direct_requests[0].get("request_id", ""), {}) as Dictionary).get("status", "") == "pending", "失败落地未保留 pending 账")
	_dungeon.set("_current_room_id", saved_room_id)
	var retry_report := _dungeon.spawn_character_fate_pickups([direct_requests[0]])
	_check((retry_report.get("granted", []) as Array).size() == 1, "角色凭据 pending 重试未按原请求落地")
	if live_enemy == null:
		_fail("角色命运自然路径没有找到可直接击杀的正式 Enemy3D")
	else:
		# 自然路径：真实 Enemy3D.killed → Dungeon3D._on_enemy_killed → kill_recorded → MapFateTriggers → Player3D。
		# 不能随便取房间里的第一只：抓握大师在同房仍有其它活怪时正式规则就是无敌，
		# 拟态箱也有自己的结算链。这里仅筛掉这两类测试对象，不改变生产逻辑。
		print("角色自然击杀 target kind=%s hp=%d room=%s" % [
			live_enemy.enemy_kind, live_enemy.current_hp, live_enemy.room_id
		])
		live_enemy.take_damage(999999)
		print("角色自然击杀 after_damage kind=%s hp=%d/%d state=%s queued=%s invulnerable=%s elite_defeat=%s" % [
			live_enemy.enemy_kind, live_enemy.current_hp, live_enemy.max_hp, live_enemy.ai_state,
			live_enemy.is_queued_for_deletion(), bool(live_enemy.call("_is_egt_invulnerable")),
			bool(live_enemy.get("_elite_defeat_active"))
		])
		for _frame in range(30):
			await get_tree().process_frame
			if not is_instance_valid(live_enemy) or live_enemy.ai_state == "dead":
				break
		if is_instance_valid(live_enemy):
			print("角色自然击杀 after_wait kind=%s hp=%d/%d state=%s queued=%s invulnerable=%s elite_defeat=%s" % [
				live_enemy.enemy_kind, live_enemy.current_hp, live_enemy.max_hp, live_enemy.ai_state,
				live_enemy.is_queued_for_deletion(), bool(live_enemy.call("_is_egt_invulnerable")),
				bool(live_enemy.get("_elite_defeat_active"))
			])
	_check(not is_instance_valid(live_enemy) or live_enemy.ai_state == "dead", "正式 Enemy3D 未通过击杀入口进入 dead")
	var delivery := _dungeon.get("_character_fate_delivery") as Dictionary
	_check(delivery.size() >= 2, "真实 Enemy3D kill_recorded 链没有写入角色凭据投递账")
	var landed_ids: Array = []
	var landed_request: Dictionary = {}
	for key in delivery.keys():
		var row := delivery[key] as Dictionary
		if str(row.get("status", "")) == "landed":
			landed_ids.append(str(key))
			if landed_request.is_empty():
				landed_request = (row.get("request", {}) as Dictionary).duplicate(true)
	_check(landed_ids.size() >= 2, "角色凭据未按正式发放结果确认 landed")
	_check(int(landed_request.get("currency_cost", -1)) == 30, "角色凭据投递账丢失 currency_cost")
	if not landed_request.is_empty():
		var duplicate_report := _dungeon.spawn_character_fate_pickups([landed_request])
		_check((duplicate_report.get("duplicate", []) as Array).size() == 1, "角色凭据重复提交未被幂等拒绝")
	var delivery_before := (_dungeon.get("_character_fate_delivery") as Dictionary).duplicate(true)
	var delivery_json: Variant = JSON.parse_string(JSON.stringify(_dungeon.call("_export_character_fate_delivery_snapshot")))
	_check(delivery_json is Dictionary and bool(_dungeon.call("_import_character_fate_delivery_snapshot", delivery_json)), "角色凭据账 JSON 往返失败")
	var delivery_after := (_dungeon.get("_character_fate_delivery") as Dictionary).duplicate(true)
	if delivery_after != delivery_before:
		print("角色凭据账快照 before=%s" % JSON.stringify(delivery_before))
		print("角色凭据账快照 after=%s" % JSON.stringify(delivery_after))
	_check(_same_character_delivery_semantics(delivery_before, delivery_after), "角色凭据账 JSON 往返改变 landed/pending 状态")
	player._character_fate["kill_rules"] = old_rules


func _verify_fate_pickup_matrix(room: DungeonRoom3D) -> void:
	print("--- 命运卡凭据：唯一 GroundLoot 构造口与拒绝矩阵 ---")
	await _enter_room(room)
	var item := _fate_item(room.room_id, "fate:runtime:primary")
	var delivery := _dungeon.call(
		"_deliver_ground_rewards", room,
		[{"kind": "item", "item_id": "item_fate_card_drop", "item": item, "count": 1}],
		room.global_position, "verification:fate_primary", false
	) as Dictionary
	_check((delivery.get("granted", []) as Array).size() == 1, "命运卡未通过 GroundLoot 唯一构造口生成")
	var pickup := _find_fate_pickup(room, "fate:runtime:primary")
	if pickup == null:
		_fail("唯一构造口生成后找不到命运卡凭据")
		return
	pickup.set_pickup_distance_m(2.0)
	_dungeon.player.global_position = pickup.global_position
	var forged_candidate := {
		"available": true,
		"interaction_id": "fate_card_drop:forged",
		"fate_pickup_id": "forged",
	}
	var before_id := pickup.get_fate_pickup_id()

	# 掉落动画期间拒绝；这是自然流程，不是故障注入。
	_check(pickup.get_interaction_candidate(_dungeon.player).is_empty(), "落地动画期间错误提供命运卡候选")
	_check(not pickup.perform_interaction(_dungeon.player, forged_candidate), "落地动画期间接受伪造 candidate")
	await _wait(LANDING_WAIT_S + 0.05)
	_dungeon.player.global_position = pickup.global_position
	await get_tree().process_frame
	var candidate := pickup.get_interaction_candidate(_dungeon.player)
	_check(not candidate.is_empty(), "落地后没有合法命运卡候选")
	_check(not pickup.is_pickup_accepted(), "玩家靠近后命运卡凭据自动拾取")

	# 故障注入：空 fate_pickup_id 不能由正式构造口生成。
	var empty_item := _fate_item(room.room_id, "")
	var empty_pickup: Variant = _dungeon.call("_create_ground_pickup", empty_item)
	_injected_faults.append("空 fate_pickup_id 通过唯一构造口注入")
	_check(empty_pickup == null, "空 fate_pickup_id 未被唯一 GroundLoot 构造口拒绝")

	# 远距拒绝，凭据仍在。
	_dungeon.player.global_position = pickup.global_position + Vector3(10.0, 0.0, 0.0)
	_check(not pickup.perform_interaction(_dungeon.player, candidate), "远距离命运卡交互未拒绝")
	_check(_credential_alive(pickup, before_id), "远距离拒绝后命运卡凭据未保留")

	# 故障注入：伪造 candidate 不得越过专用 provider 的 ID 校验。
	_injected_faults.append("伪造 candidate 通过专用 provider 注入")
	_dungeon.player.global_position = pickup.global_position
	_check(not pickup.perform_interaction(_dungeon.player, forged_candidate), "伪造 candidate 未拒绝")
	_check(_credential_alive(pickup, before_id), "伪造 candidate 拒绝后凭据未保留")

	# 故障注入：当前房间账切到不存在房间，不能认领不属于当前事务的凭据。
	var saved_room_id := str(_dungeon.get("_current_room_id"))
	_dungeon.set("_current_room_id", "verification_missing_room")
	_injected_faults.append("错误房间通过 current_room_id 注入")
	_check(not pickup.perform_interaction(_dungeon.player, candidate), "错误房间交互未拒绝")
	_check(_credential_alive(pickup, before_id), "错误房间拒绝后凭据未保留")
	_dungeon.set("_current_room_id", saved_room_id)

	# 故障注入：模态忙时拒绝；不消费凭据。
	_dungeon.set("_door_fate_active", true)
	_injected_faults.append("模态忙通过 _door_fate_active 注入")
	_check(not pickup.perform_interaction(_dungeon.player, candidate), "模态窗口忙时命运卡交互未拒绝")
	_check(_credential_alive(pickup, before_id), "模态忙拒绝后凭据未保留")
	_dungeon.set("_door_fate_active", false)

	# source_room_id 是统一 controller 的房间归属边界；这里同样作为拒绝收口检查。
	var original_source := str(pickup.item_data.get("source_room_id", ""))
	pickup.item_data["source_room_id"] = "verification_wrong_room"
	_injected_faults.append("source_room_id 错误通过凭据数据注入")
	_check(not pickup.perform_interaction(_dungeon.player, candidate), "错误 source_room_id 未拒绝")
	_check(_credential_alive(pickup, before_id), "错误 source_room_id 拒绝后凭据未保留")
	pickup.item_data["source_room_id"] = original_source

	# 成功路径必须走已确认存在的 FateCardDropPickup3D.perform_interaction。
	_check(pickup.perform_interaction(_dungeon.player, candidate), "合法命运卡 perform_interaction 未打开 offer")
	_check(bool((_dungeon.get("_fate_pickup_claimed") as Dictionary).get(before_id, false)), "成功后 claim 账未写入")
	_check(pickup.is_pickup_accepted(), "成功交互后凭据未 accept")
	_check(not pickup.perform_interaction(_dungeon.player, candidate), "claim 后重复交互未拒绝")
	await get_tree().process_frame
	_check(bool(_dungeon.get("_door_fate_active")), "合法命运卡交互未打开 offer")
	_check(str(_dungeon.get("_fate_offer_source")) == "pickup", "offer source 不是 pickup")
	_check(str(_dungeon.get("_fate_offer_pickup_id")) == before_id, "offer 未绑定原 fate_pickup_id")

	# offer 内容冻结：正式 door fate snapshot JSON 往返不能重抽。
	var offer_before := _dungeon.call("_export_door_fate_snapshot") as Dictionary
	var offer_json := JSON.stringify(offer_before)
	var offer_after_json: Variant = JSON.parse_string(offer_json)
	_check(offer_after_json is Dictionary, "命运卡 offer JSON 往返失败")
	_check(bool(_dungeon.call("_import_door_fate_snapshot", offer_after_json)), "命运卡 offer 快照导入失败")
	var offer_after := _dungeon.call("_export_door_fate_snapshot") as Dictionary
	_check(_same_offer_cards(offer_before.get("cards", []) as Array, offer_after.get("cards", []) as Array), "JSON 往返后 offer 卡面被重抽")
	_check(_same_offer_quotes(offer_before.get("quotes", {}) as Dictionary, offer_after.get("quotes", {}) as Dictionary), "JSON 往返后 offer 报价未冻结")
	_check((offer_after.get("claimed_pickups", {}) as Dictionary).get(before_id, false), "JSON 往返后 claim 账丢失")

	_dungeon.call("_capture_room_runtime_state", room.room_id)
	var captured := (_dungeon.get("_segment_runtime_state") as Dictionary).get(room.room_id, {}) as Dictionary
	var captured_ground := captured.get("ground_items", []) as Array
	for value in captured_ground:
		var row := value as Dictionary
		_check(str((row.get("item_data", {}) as Dictionary).get("fate_pickup_id", "")) != before_id, "已 claim 凭据被写回地面快照")
	_dungeon.call("_close_door_fate_overlay")
	await get_tree().process_frame
	_check(not bool(_dungeon.get("_door_fate_active")), "offer 收尾后模态仍占用")
	print("命运卡拒绝矩阵、主动交互、claim 与 JSON offer 冻结：完成")


func _verify_normal_chest_pending(chest_room: DungeonRoom3D, start: DungeonRoom3D) -> void:
	print("--- 普通宝箱：冻结、切房保留、重入单次补发 ---")
	await _enter_room(chest_room)
	var chest := _find_unopened_chest(chest_room, false)
	if chest == null:
		chest = _spawn_verification_chest(chest_room, "verification_normal_chest", false)
	if chest == null:
		_fail("没有可用于普通宝箱 pending 验收的箱子")
		return
	chest.mimic = false
	chest.set("_player_in_range", true)
	var candidate := chest.get_interaction_candidate(_dungeon.player)
	_check(not candidate.is_empty(), "普通宝箱没有合法交互候选")
	_check(chest.perform_interaction(_dungeon.player, candidate), "普通宝箱 perform_interaction 失败")
	var chest_id := chest.chest_id
	var burst_delay := chest.get_open_burst_delay()
	var pending_before := chest_room.get_pending_chest_grants()
	var state_before := (pending_before.get(chest_id, {}) as Dictionary).duplicate(true)
	_check(str(state_before.get("status", "")) == "frozen", "普通宝箱开箱后 pending 未冻结")
	_check(not (state_before.get("grants", []) as Array).is_empty(), "普通宝箱冻结账没有 grants")

	# 故障注入：在爆点前切换当前房，模拟中断；pending 必须由房间 Owner 保留。
	_injected_faults.append("普通宝箱爆点前 force_enter_room_for_test 切房")
	_dungeon.call("force_enter_room_for_test", start.room_id)
	_dungeon.player.global_position = start.global_position + Vector3(0.0, 0.5, 0.0)
	await _wait(burst_delay + 0.12)
	var pending_after_interrupt := chest_room.get_pending_chest_grants()
	_check(pending_after_interrupt.has(chest_id), "切房中断后普通宝箱 pending 丢失")
	_check(
		(pending_after_interrupt.get(chest_id, {}) as Dictionary).get("grants", []) == state_before.get("grants", []),
		"切房中断后普通宝箱 grants 被重新抽取或改变"
	)

	var loot_before_reenter := _room_loot(chest_room).size()
	await _enter_room(chest_room)
	await get_tree().process_frame
	var after_reenter := _room_loot(chest_room).size()
	_check(after_reenter > loot_before_reenter, "重入后普通宝箱 pending 没有补发")
	_check(not chest_room.get_pending_chest_grants().has(chest_id), "普通宝箱补发后 pending 未清账")
	_dungeon.call("_resume_pending_chest_grants", chest_room)
	await get_tree().process_frame
	_check(_room_loot(chest_room).size() == after_reenter, "普通宝箱 pending 被重复补发")
	print("普通宝箱 pending frozen → 切房保留 → 重入补发一次 → 清账：完成")


func _verify_mimic_snapshot_and_kill(chest_room: DungeonRoom3D, start: DungeonRoom3D) -> void:
	print("--- 拟态宝箱：快照重建、真正 free、身份与击杀结算 ---")
	await _enter_room(chest_room)
	var chest := _find_unopened_chest(chest_room, true)
	if chest == null:
		chest = _spawn_verification_chest(chest_room, "verification_mimic_chest", true)
	if chest == null:
		_fail("没有可用于拟态宝箱验收的箱子")
		return
	chest.mimic = true
	chest.mimic_monster_kind = "egt_mimic"
	chest.set("_player_in_range", true)
	var candidate := chest.get_interaction_candidate(_dungeon.player)
	_check(chest.perform_interaction(_dungeon.player, candidate), "拟态宝箱 perform_interaction 失败")
	await get_tree().process_frame
	var pending := chest_room.get_pending_chest_grants().get(chest.chest_id, {}) as Dictionary
	_check(str(pending.get("status", "")) == "mimic_alive", "拟态开箱后 pending 不是 mimic_alive")
	_check(chest.is_opened(), "拟态箱未进入 opened 状态")
	_check(bool(chest.get_chest_snapshot().get("mimic", false)), "拟态箱 snapshot 未保留 mimic")

	var mimic := _find_mimic_enemy(chest_room.room_id)
	if mimic == null:
		_fail("拟态开箱没有生成 chest_mimic 敌人")
		return
	var persistent_id := mimic.get_persistent_id()
	_check(bool(mimic.get_enemy_data().get("chest_mimic", false)), "拟态敌人缺少 chest_mimic 身份")
	_check(str(mimic.get_enemy_data().get("chest_id", "")) == chest.chest_id, "拟态敌人 chest_id 未绑定箱子")
	_check(not bool(mimic.get_enemy_data().get("counts_for_room_clear", true)), "拟态敌人错误计入清房")
	var cleared_before := chest_room.cleared

	# 故障注入：采集正式 runtime snapshot 后真正 free 旧敌人，再用正式恢复入口重建。
	_dungeon.call("_capture_room_runtime_state", chest_room.room_id)
	var runtime_state := (_dungeon.get("_segment_runtime_state") as Dictionary).get(chest_room.room_id, {}) as Dictionary
	var saved_enemy_rows := runtime_state.get("enemies", []) as Array
	_check(saved_enemy_rows.size() > 0, "拟态敌人未进入正式 runtime snapshot")
	mimic.queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(mimic), "拟态 snapshot 验收未真正释放旧敌人节点")
	(_dungeon.get("_enemy_nodes_by_room") as Dictionary)[chest_room.room_id] = []
	_dungeon.call("_restore_room_runtime_state", chest_room.room_id)
	await get_tree().process_frame
	var restored := _find_mimic_enemy(chest_room.room_id)
	_check(restored != null, "正式 runtime snapshot 未恢复拟态敌人")
	if restored == null:
		return
	_check(restored != mimic, "拟态恢复复用了旧敌人实例，没有验证重新实例化")
	_check(restored.get_persistent_id() == persistent_id, "拟态恢复 persistent_id 改变")
	_check(str(restored.get_enemy_data().get("chest_id", "")) == chest.chest_id, "拟态恢复 chest_id 改变")
	_check(bool(restored.get_enemy_data().get("chest_mimic", false)), "拟态恢复 chest_mimic 丢失")
	_check(not bool(restored.get_enemy_data().get("counts_for_room_clear", true)), "拟态恢复后错误计入清房")
	_check(chest_room.cleared == cleared_before, "拟态恢复改变房间清算状态")

	# 击杀必须走正式 Enemy3D → Dungeon3D._on_enemy_killed 链，且不自动弹 offer。
	_dungeon.player.global_position = restored.global_position + Vector3(4.0, 0.0, 0.0)
	restored.take_damage(999999)
	for _frame in range(8):
		await get_tree().process_frame
		if not is_instance_valid(restored) or restored.ai_state == "dead":
			break
	_check(not is_instance_valid(restored) or restored.ai_state == "dead", "拟态敌人击杀未进入 dead")
	await get_tree().process_frame
	_check(not chest_room.get_pending_chest_grants().has(chest.chest_id), "拟态击杀后 pending 未发放并清账")
	_check(_room_loot(chest_room).size() > 0, "拟态击杀后没有箱内地面奖励")
	_check(not bool(_dungeon.get("_door_fate_active")), "拟态击杀后自动弹出命运卡 offer")
	_check(chest_room.cleared == cleared_before, "拟态击杀错误计入清房")
	print("拟态 snapshot 重建、旧敌人 free、身份恢复、击杀 pending 与清房边界：完成")


func _verify_old_mimic_identity(room_id: String) -> void:
	# 故障注入：只保留旧存档的 persistent_id，不伪称完整自然读档流程。
	var config := {"enemy_type": "", "chest_id": "", "counts_for_room_clear": true}
	var old_id := "chest_mimic:%s:legacy_chest" % room_id
	_dungeon.call("_restore_chest_mimic_identity", config, old_id, room_id)
	_injected_faults.append("旧 persistent_id-only 拟态快照兼容入口注入")
	_check(bool(config.get("chest_mimic", false)), "旧 persistent_id-only 快照未恢复 chest_mimic")
	_check(str(config.get("chest_id", "")) == "legacy_chest", "旧 persistent_id-only 快照未推导 chest_id")
	_check(str(config.get("enemy_type", "")) == "egt_mimic", "旧 persistent_id-only 快照未补 enemy_type")
	_check(not bool(config.get("counts_for_room_clear", true)), "旧 persistent_id-only 拟态快照错误计入清房")


func _fate_item(room_id: String, pickup_id: String) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item("item_fate_card_drop").duplicate(true)
	item["type"] = "fate_pickup"
	item["id"] = "item_fate_card_drop"
	item["fate_pickup_id"] = pickup_id
	item["fate_source"] = "verification"
	item["source_room_id"] = room_id
	return item


func _find_chest_room() -> DungeonRoom3D:
	for value in (_dungeon.get("_rooms") as Array):
		var room := value as DungeonRoom3D
		if room != null and not room.chest_placements.is_empty():
			return room
	return null


func _enter_room(room: DungeonRoom3D) -> void:
	_dungeon.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	_dungeon.call("force_enter_room_for_test", room.room_id)
	for _frame in range(5):
		await get_tree().process_frame
	room.ensure_detail_built()
	for _frame in range(3):
		await get_tree().process_frame


func _find_fate_pickup(room: DungeonRoom3D, pickup_id: String) -> FateCardDropPickup3D:
	for node in room.find_children("*", "", true, false):
		var pickup := node as FateCardDropPickup3D
		if pickup != null and not pickup.is_queued_for_deletion() and pickup.get_fate_pickup_id() == pickup_id:
			return pickup
	return null


func _credential_alive(pickup: FateCardDropPickup3D, pickup_id: String) -> bool:
	return is_instance_valid(pickup) and not pickup.is_queued_for_deletion() \
		and not pickup.is_pickup_accepted() and pickup.get_fate_pickup_id() == pickup_id


func _same_character_delivery_semantics(before: Dictionary, after: Dictionary) -> bool:
	if before.keys().size() != after.keys().size():
		return false
	for key in before:
		if not after.has(key):
			return false
		var before_row := before[key] as Dictionary
		var after_row := after[key] as Dictionary
		if str(before_row.get("status", "")) != str(after_row.get("status", "")):
			return false
		if str(before_row.get("room_id", "")) != str(after_row.get("room_id", "")):
			return false
		if int(before_row.get("currency_cost", 0)) != int(after_row.get("currency_cost", 0)):
			return false
		var before_request := before_row.get("request", {}) as Dictionary
		var after_request := after_row.get("request", {}) as Dictionary
		for request_key in ["kind", "request_id", "reward_id"]:
			if str(before_request.get(request_key, "")) != str(after_request.get(request_key, "")):
				return false
		for request_key in ["rule_index", "kills", "currency_cost"]:
			if int(before_request.get(request_key, 0)) != int(after_request.get(request_key, 0)):
				return false
	return true


func _same_offer_cards(before: Array, after: Array) -> bool:
	if before.size() != after.size():
		return false
	for index in range(before.size()):
		var before_row := before[index] as Dictionary
		var after_row := after[index] as Dictionary
		if before_row.get("stable_card_id", "") != after_row.get("stable_card_id", ""):
			return false
		if str(before_row.get("orientation", "")) != str(after_row.get("orientation", "")):
			return false
		if not is_equal_approx(float(before_row.get("orientation_roll", 0.0)), float(after_row.get("orientation_roll", 0.0))):
			return false
		if int(before_row.get("price", 0)) != int(after_row.get("price", 0)):
			return false
	return true


func _same_offer_quotes(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for key in before:
		if not after.has(key) or int(before[key]) != int(after[key]):
			return false
	return true


func _room_loot(room: DungeonRoom3D) -> Array:
	var result: Array = []
	for node in room.find_children("*", "", true, false):
		if node is GroundLootPickup3D and not (node as GroundLootPickup3D).is_queued_for_deletion():
			result.append(node)
	return result


func _find_unopened_chest(room: DungeonRoom3D, prefer_mimic: bool) -> TreasureChest3D:
	for chest in room.get_treasure_chests():
		if not chest.is_opened() and (not prefer_mimic or chest.mimic):
			return chest
	if prefer_mimic:
		for chest in room.get_treasure_chests():
			if not chest.is_opened():
				return chest
	return null


func _spawn_verification_chest(room: DungeonRoom3D, chest_id: String, mimic: bool) -> TreasureChest3D:
	return room.spawn_runtime_chest({
		"id": chest_id,
		"quality": "rare",
		"chest_tier": "advanced",
		"reward_pool_id": "loot_floor_1_2",
		"drop_count": 2,
		"mimic": mimic,
		"mimic_monster_kind": "egt_mimic",
	}, Vector2(0.0, 0.0))


func _find_live_enemy(room_id: String) -> Enemy3D:
	var rows := (_dungeon.get("_enemy_nodes_by_room") as Dictionary).get(room_id, []) as Array
	for value in rows:
		var enemy := value as Enemy3D
		if enemy == null or not is_instance_valid(enemy) or enemy.ai_state in ["dead", "defeated"]:
			continue
		var data := enemy.get_enemy_data()
		print("角色自然击杀候选 room=%s kind=%s hp=%d/%d state=%s arms=%s chest=%s inv=%s" % [
			room_id, enemy.enemy_kind, enemy.current_hp, enemy.max_hp, enemy.ai_state,
			enemy.get("arms_taker_combat") != null, bool(data.get("chest_mimic", false)),
			bool(enemy.call("_is_egt_invulnerable"))
		])
		# 自然击杀链必须选能接受普通伤害的正式 Enemy3D；抓握大师的生产规则是
		# 同房仍有其它活怪时正式无敌，Arms Taker 则可能正处于不可伤害阶段。
		if enemy.get("arms_taker_combat") != null:
			continue
		if bool(data.get("chest_mimic", false)):
			continue
		if bool(enemy.call("_is_egt_invulnerable")):
			continue
		return enemy
	return null


func _find_mimic_enemy(room_id: String) -> Enemy3D:
	for value in (_dungeon.get("_enemy_nodes_by_room") as Dictionary).get(room_id, []) as Array:
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and bool(enemy.get_meta("chest_mimic", false)):
			return enemy
	return null


func _spawn_formal_character_verification_enemy(room: DungeonRoom3D) -> Enemy3D:
	var injector := _dungeon.get("_monster_injector") as RefCounted
	if injector == null:
		_fail("正式 Enemy3D 自然链路夹具缺少 MonsterInjector")
		return null
	var difficulty := 0
	var theme: Variant = _dungeon.get("visual_theme")
	if theme != null:
		difficulty = int(theme.get("difficulty_rank"))
	var config: Dictionary = injector.generate_box_enemy("melee_chaser", difficulty, 0)
	config["hp"] = 1
	config["max_hp"] = 1
	config["persistent_id"] = "verification_character_fate_enemy"
	var spawn_point := room.spawn_point_for_index(0)
	if not spawn_point.is_finite():
		spawn_point = room.global_position + Vector3.UP * 0.1
	var configs: Array[Dictionary] = [config]
	var positions: Array = [spawn_point]
	var spawned := int(_dungeon.call("_spawn_enemy_batch", room, configs, true, false, positions))
	if spawned != 1:
		_fail("正式 Enemy3D 自然链路夹具未通过 _spawn_enemy_batch 生成")
		return null
	for value in (_dungeon.get("_enemy_nodes_by_room") as Dictionary).get(room.room_id, []) as Array:
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and enemy.get_persistent_id() == str(config["persistent_id"]):
			return enemy
	_fail("正式 Enemy3D 自然链路夹具生成后未进入房间敌人登记")
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	print("FATE_PICKUP_PROBE_FAIL: %s" % message)


func _finish(exit_code: int) -> void:
	if _dungeon != null and is_instance_valid(_dungeon):
		_dungeon.queue_free()
	await get_tree().process_frame
	var report := {
		"exit_code": exit_code,
		"failures": _failures.duplicate(),
		"injected_faults": _injected_faults.duplicate(),
		"unexpected_failures": _failures.duplicate(),
		"unexecuted": ["无" if exit_code != 2 else "正式运行链路未执行"],
		"user_data_dir": OS.get_user_data_dir(),
	}
	if not _report_dir.is_empty() and _report_dir.is_absolute_path():
		var file := FileAccess.open(_report_dir.path_join("result.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
	print("FATE_PICKUP_PROBE_RESULT exit_code=%d failures=%d injected_faults=%d unexecuted=%s" % [
		exit_code, _failures.size(), _injected_faults.size(), str(report["unexecuted"])
	])
	get_tree().quit(exit_code)
