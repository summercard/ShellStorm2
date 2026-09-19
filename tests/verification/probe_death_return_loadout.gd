extends Node

## 探针：玩家死亡返城（回到 99F 基地）时身上到底有什么装备。
## 死亡路径在 commit_run_settlement:601 清空 active_run_snapshot，返城后的
## TowerDescent3D 一定拿不到可恢复快照 —— 等价于 test_mode=true 的
## 「全新场景、不恢复任何快照」状态。本探针读运行时真值，不读设计口径。
##
## A 段：默认冷启动出生（100F 天台）。
## B 段：先登记死亡返城入口契约（REASON_DEATH_RETURN_99F + SPAWN_BASE_99F），
##       走的就是实机死亡返城的同一分支，落在 99F facility。

var failures: Array[String] = []


func _ready() -> void:
	_report_scene_contract()
	await _probe_spawn("A_cold_start_rooftop", false)
	await _probe_spawn("B_death_return_99f", true)
	_finish()


func _probe_spawn(tag: String, as_death_return: bool) -> void:
	if as_death_return:
		GameEntryFlow.request_gameplay_entry(
			GameEntryFlow.REASON_DEATH_RETURN_99F, GameEntryFlow.SPAWN_BASE_99F
		)
	var tower = load("res://scenes/TowerDescent3D.tscn").instantiate()
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for frame in range(3):
		await get_tree().process_frame

	var player = tower.player
	if player == null:
		failures.append("%s 塔楼场景没有玩家节点" % tag)
		return

	var entry: Dictionary = tower.get_entry_context_snapshot()
	print("PROBE[", tag, "] entry_reason=", str(entry.get("reason", "")),
		" spawn_target=", str(entry.get("spawn_target", "")))
	print("PROBE[", tag, "] room=", str(tower.get("_current_room_id")),
		" pos=", player.global_position)
	print("PROBE[", tag, "] start_with_weapon=", str(player.start_with_weapon),
		" active_slot=", player.get_active_weapon_slot(),
		" restore_snapshot_empty=", str((tower.get("_runtime_restore_snapshot") as Dictionary).is_empty()))

	var equipped_count := 0
	var slot_zero: Dictionary = {}
	for slot_index in range(2):
		var item: Dictionary = player.get_equipped_weapon_item_for_slot(slot_index)
		if slot_index == 0:
			slot_zero = item
		var is_empty: bool = item.is_empty()
		if not is_empty:
			equipped_count += 1
		print("PROBE[", tag, "] slot", slot_index,
			" empty=", str(is_empty),
			" assembly_id=", str(item.get("assembly_id", "")),
			" content_id=", str(item.get("weapon_content_id", "")),
			" instance=", str(item.get("weapon_instance_id", "")),
			" ammo=", str(item.get("current_ammo", "")),
			" name=", str(item.get("name", "")),
			" assembly_snapshot=", str(item.get("assembly_snapshot", {})))

	var inventory = tower.get_inventory_module()
	var insurance = tower.get_insurance_module()
	var quick = tower.get("_quick_inventory")
	print("PROBE[", tag, "] inventory=", inventory.get_used_slots() if inventory != null else -1,
		"/", inventory.get_capacity() if inventory != null else -1,
		" insurance=", insurance.get_used_slots() if insurance != null else -1,
		" quick=", quick.get_used_slots() if quick != null else -1)
	print("PROBE[", tag, "] equipped_weapon_count=", equipped_count)

	# 核心断言
	if slot_zero.is_empty():
		failures.append("%s 主武器栏为空（与实机观察矛盾）" % tag)
	else:
		var assembly_id := str(slot_zero.get("assembly_id", ""))
		# 出厂枪身份只认 BlueprintRegistry 的常量，换初始枪不必再改本探针。
		var expected_starting_gun := BlueprintRegistry.DEFAULT_STARTING_GUN_ID
		if assembly_id != expected_starting_gun:
			failures.append("%s 主武器不是出厂枪 %s，而是 %s" % [tag, expected_starting_gun, assembly_id])
		var instance_id := str(slot_zero.get("weapon_instance_id", ""))
		if instance_id.is_empty():
			failures.append("%s 主武器没有稳定实例ID" % tag)
		if insurance != null and insurance.has_weapon_instance(instance_id):
			failures.append("%s 出厂枪竟然来自保险格，契约被误接" % tag)
		if inventory != null:
			for occupied in inventory.get_occupied_slots():
				var occupied_item := occupied.get("item", {}) as Dictionary
				if str(occupied_item.get("weapon_instance_id", "")) == instance_id:
					failures.append("%s 出厂枪同时存在于背包里，出现双份" % tag)
					break
	if as_death_return and str(tower.get("_current_room_id")) != "facility":
		failures.append("死亡返城没有落在 99F facility，而是 %s" % str(tower.get("_current_room_id")))

	player.queue_free()
	remove_child(tower)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## 结构契约：塔楼/地牢场景的 Player3D 实例没有关掉 start_with_weapon。
func _report_scene_contract() -> void:
	for path in ["res://scenes/Player3D.tscn", "res://scenes/Dungeon3D.tscn", "res://scenes/TowerDescent3D.tscn"]:
		var text := _read_text(path)
		print("PROBE scene_override path=", path, " start_with_weapon_overridden=", str(text.contains("start_with_weapon")))


func _read_text(res_path: String) -> String:
	var file := FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _finish() -> void:
	if failures.is_empty():
		print("PROBE_DEATH_RETURN_LOADOUT_OK: 返城后玩家手上始终是 BlueprintRegistry.DEFAULT_STARTING_GUN_ID 指定的出厂枪，来自 Player3D.start_with_weapon，与死亡结算无关")
	else:
		for message in failures:
			push_error(message)
		print("PROBE_DEATH_RETURN_LOADOUT_FAILED count=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
