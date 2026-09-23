extends Node
## REWARD-SERVICE / WORLD-LOOT：正式场景地面发放、搜索单件和失败报告。

const LEVEL := preload("res://scenes/levels3d/IronFrontier3D.tscn")
const ENEMY_SCENE := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := LEVEL.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 240924
	add_child(dungeon)
	await get_tree().process_frame
	var room := (dungeon.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
	if room == null:
		failures.append("正式场景缺少 start 房间")
	else:
		room.reward_plan = {"search": {"entries": [
			{"kind": "item", "item_id": "item_health_potion", "count": 3},
		]}}
		var before := _ground_items(room)
		dungeon.call("_on_prop_searched", room, {"size_class": "small", "prop_id": "handoff_probe"})
		var after := _ground_items(room)
		if after.size() != before.size() + 1:
			failures.append("搜索没有恰好生成一件地面物")
		else:
			var spawned := after[-1] as GroundLootPickup3D
			if str(spawned.item_data.get("id", "")) != "item_health_potion" or int(spawned.item_data.get("count", 0)) != 1:
				failures.append("搜索未在 grant 层裁剪为一件指定物品")
		if str((dungeon.get("status_label") as Label).text) != "搜索完成 · 1 件物资落地":
			failures.append("搜索成功文案没有依据实际生成数")
		room.reward_plan = {"search": {"spec_id": "missing_search_spec_probe"}}
		dungeon.call("_on_prop_searched", room, {"size_class": "small", "prop_id": "invalid_spec_probe"})
		if str((dungeon.get("status_label") as Label).text) != "搜索失败 · 奖励配置无效":
			failures.append("错误奖励配置被误报为容器为空或搜索成功")
		if _ground_items(room).size() != after.size():
			failures.append("错误奖励配置仍生成了地面物")

		room.reward_plan = {"kill": {"entries": [
			{"kind": "item", "item_id": "item_ammo_pack", "count": 1},
			{"kind": "currency", "currency_id": "extraction_points", "amount": 10},
		]}}
		var multipliers := dungeon.get("_room_currency_multipliers") as Dictionary
		multipliers[room.room_id] = 1.5
		dungeon.set("_room_currency_multipliers", multipliers)
		var alive := dungeon.get("_alive_by_room") as Dictionary
		alive.erase(room.room_id)
		dungeon.set("_alive_by_room", alive)
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		enemy.room_id = room.room_id
		dungeon.get_node("ActiveEnemies").add_child(enemy)
		enemy.global_position = room.global_position
		dungeon.call("_on_enemy_killed", enemy, {
			"enemy_type": "melee_chaser", "floor": 1, "loot_table": "loot_floor_1_2",
		})
		await get_tree().process_frame
		var killed_drops := _ground_items(room)
		if killed_drops.size() != after.size() + 2:
			failures.append("击杀没有按一个实物和一个魂球延迟落地")
		else:
			var found_ammo := false
			var found_currency := false
			for index in range(after.size(), killed_drops.size()):
				var dropped := killed_drops[index].item_data
				if str(dropped.get("id", "")) == "item_ammo_pack" and int(dropped.get("count", 0)) == 1:
					found_ammo = true
				if str(dropped.get("id", "")) == "__currency__" and int(dropped.get("count", 0)) == 15:
					found_currency = true
			if not found_ammo or not found_currency:
				failures.append("击杀 grant 的实物或1.5倍房间魂未原样落地")
		enemy.queue_free()

		var grants := [{
			"kind": "item", "item_id": "item_health_potion",
			"item": ItemRegistry.get_instance().get_item("item_health_potion"), "count": 1,
		}]
		var rejected := dungeon.call("_deliver_ground_rewards", null, grants, Vector3.ZERO, "probe:no_room") as Dictionary
		if not (rejected.get("granted", []) as Array).is_empty() or (rejected.get("rejected", []) as Array).size() != 1:
			failures.append("房间无效时未把地面奖励记为 rejected")
		if _ground_items(room).size() != killed_drops.size():
			failures.append("房间无效后仍生成了地面物")
	dungeon.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("REWARD_GROUND_HANDOFF_OK: search one grant, delayed kill drops, currency multiplier and missing-room rejection")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _ground_items(room: DungeonRoom3D) -> Array[GroundLootPickup3D]:
	var out: Array[GroundLootPickup3D] = []
	for node in get_tree().get_nodes_in_group("ground_loot_3d"):
		if node is GroundLootPickup3D and room.is_ancestor_of(node):
			out.append(node as GroundLootPickup3D)
	return out
