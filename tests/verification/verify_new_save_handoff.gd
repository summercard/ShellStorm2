extends Node
## 新档 98F 剧情地面枪 → 99F 下线 → 读档 → 拾取 → 再读档的所有权验收。

const TEST_PATH := "user://new_save_handoff_probe.json"
const TOWER_SCENE := preload("res://scenes/TowerDescent3D.tscn")
const ROOM_ID := "floor_01_exit"
const ITEM_ID := "weapon_sprinkler"
const SPAWN_KEY := "nar_tower_opening_01_wake:starter_weapon"
const SEED := 990098

var _failures: Array[String] = []


func _ready() -> void:
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	_cleanup()
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	var first := await _create_tower()
	if first == null:
		await _finish(null, original_path, original_data)
		return
	_check(str(first.get("_current_room_id")) == ROOM_ID, "新档先落 98F 办公室")
	_check(first.player.get_equipped_weapon_item_for_slot(0).is_empty(), "新档开场身上无枪")
	var room := _room(first)
	if room == null:
		_failures.append("98F 办公室未生成")
		await _finish(first, original_path, original_data)
		return
	var wake := NarrativeScript3D.load_from_id("nar_tower_opening_01_wake")
	var authored_spawn: Dictionary = {}
	if wake != null and wake.is_valid():
		for cue in wake.cues:
			if str(cue.get("do", "")) == "scene.spawn_item":
				authored_spawn = cue
				break
	_check(
		str(authored_spawn.get("spawn_key", "")) == SPAWN_KEY
		and str(authored_spawn.get("item_id", "")) == ITEM_ID
		and str(authored_spawn.get("point_room", "")) == ROOM_ID,
		"正式开场剧本声明了与持久化一致的刷物键、物品和房间",
	)
	var origin := room.global_position + TowerDescent3D.NEW_GAME_OPENING_DROP_OFFSET
	_check(first.narrative_spawn_item(ROOM_ID, ITEM_ID, 1, origin, false, SPAWN_KEY) == 1,
		"剧情命令可通过奖励服务刷正式地面枪")
	_check(_ground_count(first) == 1, "开场枪只有一件")
	_check(first.narrative_spawn_item(ROOM_ID, ITEM_ID, 1, origin, false, SPAWN_KEY) == 1
		and _ground_count(first) == 1, "相同剧情刷物键重复调用不复制")
	var original_drop := _ground_pickup(first)
	var original_instance_id := str(original_drop.item_data.get("weapon_instance_id", "")) if original_drop != null else ""
	_check(not original_instance_id.is_empty(), "开场枪有稳定武器实例 ID")
	_move_to_base(first)
	_check(BaseManager.flush_runtime_checkpoint("new_save_base_logout"), "99F 下线快照写盘成功")
	var saved := BaseManager.get_active_run_checkpoint()
	_check(str(saved.get("scope", "")) == "base", "下线快照属于基地作用域")
	_check(_saved_ground_count(saved) == 1, "基地快照仍保存 98F 未拾取地面枪")
	_check(bool((saved.get("world_state", {}) as Dictionary).get("narrative_spawned_keys", {}).get(SPAWN_KEY, false)),
		"基地快照保存剧情刷物键")
	await _dispose(first)
	BaseManager.data = BaseData.new()
	BaseManager.load_base()
	var second := await _create_tower()
	if second == null:
		await _finish(null, original_path, original_data)
		return
	_check(str(second.get("_current_room_id")) == "facility", "已有基地快照重登固定落 99F")
	_check(second.player.global_position.distance_to(TowerDescent3D.FACILITY_LOGOUT_SPAWN) < 0.2,
		"基地重登不用旧房间坐标")
	_check(2 in (second.get("_generated_floor_indices") as Array), "重登已重建 98F 楼层")
	_check(bool((second.get("_narrative_spawned_keys") as Dictionary).get(SPAWN_KEY, false)),
		"刷物键跨磁盘重载恢复")
	var restored_room := _room(second)
	if restored_room != null:
		second.player.global_position = restored_room.global_position + Vector3.UP * 0.05
		second.call("_on_room_entered", restored_room)
		await get_tree().process_frame
		_check(_ground_count(second) == 1, "回 98F 房间时未拾取枪恢复为一件")
		var restored_drop := _ground_pickup(second)
		_check(restored_drop != null and str(restored_drop.item_data.get("weapon_instance_id", "")) == original_instance_id,
			"地面枪实例 ID 跨重载不变")
		_check(second.narrative_spawn_item(ROOM_ID, ITEM_ID, 1, origin, false, SPAWN_KEY) == 1
			and _ground_count(second) == 1, "剧本中断重播不复制已恢复的枪")
		if restored_drop != null:
			second.call("_on_ground_loot_requested", restored_drop, restored_drop.item_data.duplicate(true))
			_check(second.get_inventory_module().has_item(ITEM_ID), "拾取后枪进入背包")
			_check(_saved_ground_count(second.build_runtime_save_snapshot()) == 0,
				"拾取动画未结束时快照也不再记地面枪")
			_check(second.narrative_spawn_item(ROOM_ID, ITEM_ID, 1, origin, false, SPAWN_KEY) == 1
				and _ground_count(second) == 0, "已拾取后剧本重播不能再刷枪")
	_move_to_base(second)
	_check(BaseManager.flush_runtime_checkpoint("new_save_pickup_logout"), "拾取后基地快照写盘成功")
	await _dispose(second)
	BaseManager.data = BaseData.new()
	BaseManager.load_base()
	var third := await _create_tower()
	if third != null:
		_check(str(third.get("_current_room_id")) == "facility", "再次重登仍落 99F")
		_check(third.get_inventory_module().has_item(ITEM_ID), "已拾取枪跨基地重登归背包")
		_check(_saved_ground_count(third.build_runtime_save_snapshot()) == 0,
			"已拾取枪不会同时留在 98F 地面")
		_check(not third.call("_snapshot_matches_runtime_map", {"runtime_map_id": "expedition_01"}),
			"塔楼不接收远征地图快照")
	await _finish(third, original_path, original_data)


func _create_tower() -> TowerDescent3D:
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	if tower == null:
		_failures.append("塔楼场景加载失败")
		return null
	tower.test_mode = false
	tower.run_seed_override = SEED
	add_child(tower)
	for _frame in 30:
		await get_tree().process_frame
		if bool(tower.get("_runtime_persistence_active")):
			break
	_check(bool(tower.get("_runtime_persistence_active")), "运行时存档提供者已经注册")
	return tower


func _room(tower: TowerDescent3D) -> DungeonRoom3D:
	return (tower.get("_room_by_id") as Dictionary).get(ROOM_ID) as DungeonRoom3D


func _ground_pickup(tower: TowerDescent3D) -> GroundLootPickup3D:
	var room := _room(tower)
	if room == null:
		return null
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		var pickup := value as GroundLootPickup3D
		if pickup != null and room.is_ancestor_of(pickup) and not pickup.is_pickup_accepted():
			return pickup
	return null


func _ground_count(tower: TowerDescent3D) -> int:
	var room := _room(tower)
	if room == null:
		return 0
	var count := 0
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		var pickup := value as GroundLootPickup3D
		if pickup != null and room.is_ancestor_of(pickup) and not pickup.is_pickup_accepted():
			count += 1
	return count


func _saved_ground_count(snapshot: Dictionary) -> int:
	var world := snapshot.get("world_state", {}) as Dictionary
	var rooms := world.get("segment_runtime_state", {}) as Dictionary
	var state := rooms.get(ROOM_ID, {}) as Dictionary
	return (state.get("ground_items", []) as Array).size()


func _move_to_base(tower: TowerDescent3D) -> void:
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null:
		_failures.append("99F 基地房间不存在")
		return
	tower.player.global_position = TowerDescent3D.FACILITY_LOGOUT_SPAWN
	tower.call("_on_room_entered", facility)


func _dispose(tower: TowerDescent3D) -> void:
	if tower != null and is_instance_valid(tower):
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(tower: TowerDescent3D, original_path: String, original_data: BaseData) -> void:
	await _dispose(tower)
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()
	call_deferred("_report")


func _report() -> void:
	if _failures.is_empty():
		print("NEW_SAVE_HANDOFF_OK: 98F ground gun, 99F logout, restart, pickup and replay are ownership-safe")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
