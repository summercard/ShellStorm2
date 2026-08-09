extends Node
## 2026-08-07 体验升级验收：移动端音效、单件搜刮、物品辨色、新手出生与死亡确认。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	_verify_audio_contract(failures)
	_verify_single_item_loot(failures)
	_verify_item_colors(failures)
	_verify_tutorial_spawn_data(failures)
	await _verify_timed_search(failures)
	await _verify_death_confirmation(failures)
	_finish(failures)


func _verify_audio_contract(failures: Array[String]) -> void:
	var snapshot := AudioManager.validate_runtime_assets() as Dictionary
	if (
		int(snapshot.get("event_count", 0)) < 31
		or not bool(snapshot.get("mobile_safe", false))
		or not (snapshot.get("missing", []) as Array).is_empty()
		or not (snapshot.get("non_ogg", []) as Array).is_empty()
	):
		failures.append("至少31项运行时音效没有全部切换为移动端安全的OGG资源")


func _verify_single_item_loot(failures: Array[String]) -> void:
	var loot_module := LootModule.get_instance()
	loot_module.set_seed(20260807)
	for floor in [1, 2, 3, 5]:
		var container_loot := loot_module.generate_container_loot("crate", floor)
		if container_loot.size() > 1:
			failures.append("搜索容器一次生成了多件地面物品")
			break
		for item in container_loot:
			if int(item.get("count", 0)) != 1:
				failures.append("搜索容器生成了非单件堆叠")
				break
	for index in 32:
		var enemy_loot := loot_module.generate_enemy_loot({
			"floor": 2,
			"is_elite": index % 7 == 0,
			"is_boss": false,
		})
		var physical_item_count := 0
		for item in enemy_loot:
			if bool(item.get("is_currency", false)):
				continue
			physical_item_count += 1
			if int(item.get("count", 0)) != 1:
				failures.append("怪物物品掉落不是一件一个地面实体")
		if physical_item_count > 1:
			failures.append("单只怪物一次生成了多个实体物品")
			break


func _verify_item_colors(failures: Array[String]) -> void:
	var samples := [
		{"id": "weapon_probe", "type": "weapon"},
		{"id": "backpack_probe", "type": "equipment", "subtype": "backpack"},
		{"id": "heal_probe", "type": "consumable", "use_action": "heal"},
		{"id": "ammo_probe", "type": "consumable", "use_action": "refill_ammo"},
		{"id": "item_room_key", "type": "item", "subtype": "key"},
		{"id": "blueprint_probe", "type": "blueprint"},
	]
	var colors: Array[Color] = []
	for sample in samples:
		var color := ItemModelFactory3D.get_item_color(sample)
		if color.get_luminance() < 0.28:
			failures.append("物品模型仍存在过暗固有色：%s" % str(sample.get("id", "?")))
		colors.append(color)
	for first in colors.size():
		for second in range(first + 1, colors.size()):
			if colors[first].is_equal_approx(colors[second]):
				failures.append("不同物品类型仍共用无法区分的固有色")
				return


func _verify_tutorial_spawn_data(failures: Array[String]) -> void:
	var fresh := BaseData.new()
	if fresh.tutorial_completed:
		failures.append("新存档没有保留一次天台新手出生")
	var completed := BaseData.from_dict({"save_version": "1.4", "tutorial_completed": true})
	if not completed.tutorial_completed:
		failures.append("完成新手后出生标记不能持久化")
	var migrated := BaseData.from_dict({"save_version": "1.3", "total_runs": 2})
	if not migrated.tutorial_completed:
		failures.append("旧进度存档没有迁移为基地出生")


func _verify_timed_search(failures: Array[String]) -> void:
	var furniture := RoomFurniture3D.new()
	furniture.searchable = true
	furniture.size_class = "medium"
	furniture.search_duration = 1.8
	add_child(furniture)
	await get_tree().process_frame
	furniture.process_mode = Node.PROCESS_MODE_DISABLED
	furniture.set("_player_in_range", true)
	furniture.call("_start_search")
	furniture.call("_process", 0.45)
	var partial := furniture.get_asset_snapshot()
	if not bool(partial.get("searching", false)) or bool(partial.get("searched", false)):
		failures.append("搜索仍是按键后瞬间完成，没有持续进度")
	if float(partial.get("search_progress", 0.0)) <= 0.0 or float(partial.get("search_progress", 1.0)) >= 1.0:
		failures.append("搜索进度条没有输出有效的中间进度")
	furniture.call("_process", 2.0)
	var complete := furniture.get_asset_snapshot()
	if not bool(complete.get("searched", false)):
		failures.append("搜索计时完成后没有结算单件战利品")
	furniture.queue_free()
	await get_tree().process_frame


func _verify_death_confirmation(failures: Array[String]) -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 5:
		await get_tree().process_frame
	var player := dungeon.player
	if player == null:
		failures.append("死亡动画验收无法创建玩家")
		dungeon.queue_free()
		return
	var start_position := player.global_position
	player.take_damage(player.max_hp + 50, false, Vector3.RIGHT)
	await get_tree().create_timer(1.5).timeout
	var death_dialog := dungeon.get("_death_dialog") as Control
	if player.get_state_machine_state() != "dead":
		failures.append("致命伤害没有进入死亡状态")
	if player.get_death_animation_progress() < 1.0:
		failures.append("击飞、落地回弹、倒地动画没有完整播放")
	if player.global_position.distance_to(start_position) < 0.15:
		failures.append("死亡动画没有产生可见的击飞位移")
	if death_dialog == null or not death_dialog.visible:
		failures.append("死亡动画结束后没有等待玩家点击的返基地对话框")
	if bool(dungeon.get("_completed")):
		failures.append("玩家未点击确认前行动已自动结束")
	dungeon.queue_free()
	await get_tree().process_frame


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("REQUESTED_EXPERIENCE_UPGRADE_OK: mobile OGG, single-item timed loot, readable item colors, tutorial spawn migration, physical death and click-to-return dialog pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
