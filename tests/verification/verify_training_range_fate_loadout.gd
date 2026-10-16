extends Node
## 靶场受击契约 + 背包 + 世界命运宿主的验收。
##
## 覆盖两个真实问题：
##   ① 子弹命中靶标曾抛 "Invalid call to take_damage ... Expected 3 argument(s)"：
##      靶标只写了三参签名，而 Projectile3D 走四参调用。
##   ② 靶场没有背包模块、也没有 room_game_mode 宿主，14 张 WORLD 卡一律
##      返回 world_owner_unavailable —— 表现为"卡装不上去"，而不是"效果没生效"。

const PAUSE_REASON := "verify_training_fate_loadout"
## 世界命运的完整名单；缺一张就说明宿主覆盖不全。
const EXPECTED_WORLD_CARD_COUNT := 14


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	if scene == null:
		_finish(["TrainingRange3D scene does not load"])
		return
	var training := scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	await get_tree().physics_frame

	_check_target_damage_contract(training, failures)
	await _check_world_fate_host(training, failures)
	_check_backpack_and_crate(training, failures)
	await _check_kill_loot(training, failures)

	if not training.is_base_data_unchanged():
		failures.append("training range mutated BaseData while exercising backpack and world fate")
	training.queue_free()
	await get_tree().process_frame
	_finish(failures)


## ① 靶标必须接住战斗系统的全部受击调用形态。
func _check_target_damage_contract(training: TrainingRange3D, failures: Array[String]) -> void:
	var target: TrainingTarget3D = null
	for candidate in get_tree().get_nodes_in_group("training_target_3d"):
		if training.is_ancestor_of(candidate) and (candidate as TrainingTarget3D).target_type == "standard":
			target = candidate
			break
	if target == null:
		failures.append("no standard training target to exercise the damage contract")
		return
	# 子弹路径：Projectile3D 走四参（末位击退）。这正是报错的那次调用。
	var before := target.current_hp
	target.call("take_damage", 10, false, Vector3.FORWARD, 2.0)
	if target.current_hp >= before:
		failures.append("four-argument take_damage (projectile path) did not apply damage")
	# 近战路径：WeaponModel3D 走五参。多给一个参数不能炸。
	before = target.current_hp
	target.call("take_damage", 10, false, Vector3.FORWARD, 2.0, true)
	if target.current_hp >= before:
		failures.append("five-argument take_damage (melee path) did not apply damage")
	# 富路径：Projectile3D 检测到 take_projectile_damage 就优先走它（7 参）。
	before = target.current_hp
	target.call(
		"take_projectile_damage", 12, false, Vector3.FORWARD,
		[] as Array[String], {} as Dictionary, null, 0.0
	)
	if target.current_hp >= before:
		failures.append("take_projectile_damage did not apply damage")
	# 仇恨接口：调用方用 has_method 探到就必须能调。
	if not target.has_method("notify_attacked_by"):
		failures.append("training target lost notify_attacked_by; combat callers call it after has_method")
	else:
		target.call("notify_attacked_by", training.player)
	# 近战判定走 damageable_3d 分组；不加这条近战砍不到靶子。
	if not target.is_in_group("damageable_3d"):
		failures.append("training target is not in damageable_3d; melee cannot reach it")
	target.reset_target()


## ② 全部 WORLD 卡必须能在靶场落地，而不是返回 world_owner_unavailable。
func _check_world_fate_host(training: TrainingRange3D, failures: Array[String]) -> void:
	var host := training.get_world_game_mode()
	if host == null:
		failures.append("training range has no room_game_mode host")
		return
	if not host.is_in_group("room_game_mode"):
		failures.append("world fate host is not registered in the room_game_mode group")
	var world_ids: Array = FateCard.WORLD_SCOPE_IDS
	if world_ids.size() != EXPECTED_WORLD_CARD_COUNT:
		failures.append(
			"WORLD_SCOPE_IDS count changed: %d (expected %d); the host coverage list needs review"
			% [world_ids.size(), EXPECTED_WORLD_CARD_COUNT]
		)
	var rejected: Array[String] = []
	for card_id_value in world_ids:
		var card := FateCardPresets.get_by_card_id(str(card_id_value))
		if card == null:
			rejected.append("%s(no preset)" % str(card_id_value))
			continue
		var result: Dictionary = await FateCardGameBridge.apply_card_with_source_selection(card, training)
		if not bool(result.get("success", false)):
			rejected.append("%s(%s)" % [str(card_id_value), str(result.get("message", ""))])
	if not rejected.is_empty():
		failures.append("WORLD fate cards rejected in training range: %s" % ", ".join(rejected))
	# fate_bless_dead 是**角色卡**，落点是玩家的角色命运态，不经世界宿主。
	# 这里一并验证，是因为它和世界卡共用同一张卡池 —— 别把"没落到宿主"误判成失败。
	var bless := FateCardPresets.get_by_card_id("fate_bless_dead")
	if bless != null:
		var bless_result: Dictionary = await FateCardGameBridge.apply_card_with_source_selection(bless, training)
		if not bool(bless_result.get("success", false)):
			failures.append("fate_bless_dead rejected in training range: %s" % str(bless_result.get("message", "")))
		else:
			var fate_snapshot := training.player.get_character_fate_snapshot()
			var blessings: Array = fate_snapshot.get("blessings", [])
			if blessings.is_empty():
				failures.append("fate_bless_dead reported success but the player recorded no blessing")


## ③ 背包必须存在，且补给箱真的把"下一箱"命运兑现进背包。
func _check_backpack_and_crate(training: TrainingRange3D, failures: Array[String]) -> void:
	var inventory := training.get_inventory()
	if inventory == null:
		failures.append("training range has no backpack module")
		return
	if inventory.get_used_slots() != 0:
		failures.append("test backpack should start empty, got %d used slots" % inventory.get_used_slots())
	var host := training.get_world_game_mode()
	if host == null:
		return
	host.set_extra_loot_next_chest(true)
	host.set_next_chest_quality_boost(2)
	var before := inventory.get_used_slots()
	training.call("_on_supply_crate_activated", null)
	var after := inventory.get_used_slots()
	if after <= before:
		failures.append("supply crate did not put anything into the backpack")
	if host.chest_extra_count != 0 or host.chest_quality_boost != 0:
		failures.append("supply crate did not consume the pending chest fate state")
	# 清空接口必须可用，否则测试者没法复位。
	training.clear_backpack()
	if inventory.get_used_slots() != 0:
		failures.append("clear_backpack did not empty the test backpack")


## ④ 击杀要把测试物资放进背包（让依赖掉落的卡有落点）。
func _check_kill_loot(training: TrainingRange3D, failures: Array[String]) -> void:
	var inventory := training.get_inventory()
	if inventory == null:
		return
	training.clear_backpack()
	var pads := get_tree().get_nodes_in_group("training_spawn_pad_3d")
	var pad: TrainingSpawnPad3D = null
	for candidate in pads:
		if training.is_ancestor_of(candidate):
			pad = candidate
			break
	if pad == null:
		failures.append("no training spawn pad to kill from")
		return
	if pad.spawn_wave() <= 0:
		failures.append("training spawn pad produced no enemies")
		return
	await get_tree().physics_frame
	var victim: Enemy3D = null
	for child in training.get_node("Enemies").get_children():
		if child is Enemy3D:
			victim = child
			break
	if victim == null:
		failures.append("spawned wave has no Enemy3D to kill")
		return
	victim.take_damage(victim.max_hp + 9999, false, Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame
	if inventory.get_used_slots() <= 0:
		failures.append("killing an enemy did not deliver test loot into the backpack")
	pad.clear_wave()


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"TRAINING_RANGE_FATE_LOADOUT_OK: target accepts 3/4/5-arg and projectile damage, all %d WORLD fate cards apply via the range host, backpack exists and crate/kill loot land in it, BaseData untouched"
			% EXPECTED_WORLD_CARD_COUNT
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
