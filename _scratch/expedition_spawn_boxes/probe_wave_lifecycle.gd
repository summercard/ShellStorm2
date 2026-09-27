extends Node3D
## 生命周期监视探针：从场景 `_ready` 起逐帧盯 `room_01` 的**波次账**，
## 只在四元组变化时打印，用于定位「`_spawn_box_waves` 返回 2 波、`_room_wave_totals` 却是 1」
## 是哪一帧、由哪种生命周期事件（预生成 / 流送回灌 / 进房修复）写进去的。
##
## 时间轴：f000 场景就绪 → f120 建壳（复刻真机流送）→ f240 进 room_01 → f400 收尾报告。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const TARGET := "room_01"

var tower: TowerDescent3D
var room: DungeonRoom3D
var prev: Array = []
var frames := 0


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	room = tower._room_by_id.get(TARGET) as DungeonRoom3D
	if room == null:
		print("LIFECYCLE_FAIL 找不到 %s" % TARGET)
		get_tree().quit(1)
		return
	print("LIFECYCLE 起始：_room_by_id 有 %d 房；%s 存在=%s"
		% [tower._room_by_id.size(), TARGET, str(room != null)])
	_watch("scene_ready")

	while frames < 520:
		await get_tree().process_frame
		frames += 1
		if frames == 120:
			for value in tower._room_by_id.values():
				(value as DungeonRoom3D).ensure_shell_built()
				(value as DungeonRoom3D).ensure_detail_built()
			_watch("f120_建壳后")
		if frames == 260:
			tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
			tower._on_room_entered(room)
			_watch("f260_进房后")
		_watch("f%03d" % frames)

	_report()
	get_tree().quit(0)


## 只在「波次账」变化时打印一行（附 lifecycle 上下文）。
func _watch(tag: String) -> void:
	var queue := tower._room_wave_queues.get(TARGET, []) as Array
	var now := [
		int(tower._room_wave_totals.get(TARGET, -1)),
		queue.size(),
		int(tower._room_wave_numbers.get(TARGET, -1)),
		int(tower._alive_by_room.get(TARGET, -1)),
		int((tower._enemy_nodes_by_room.get(TARGET, []) as Array).size()),
		int(tower._pending_delayed_spawns.get(TARGET, [] as Array).size()),
		1 if tower._spawned_rooms.has(TARGET) else 0,
		1 if tower._segment_runtime_state.has(TARGET) else 0,
		1 if tower._wave_spawn_pending.has(TARGET) else 0,
		1 if room.cleared else 0,
		1 if room.is_streamed() else 0,
	]
	if now == prev:
		return
	print("  [%s] totals=%d 队列=%d waveNo=%d alive=%d 名单=%d 延迟=%d | spawned=%d 快照=%d pending=%d cleared=%d streamed=%d"
		% [tag, now[0], now[1], now[2], now[3], now[4], now[5], now[6], now[7], now[8], now[9], now[10]])
	prev = now


func _report() -> void:
	print("LIFECYCLE 终态：totals=%d 队列=%d alive=%d 名单=%d"
		% [int(tower._room_wave_totals.get(TARGET, -1)),
		   int((tower._room_wave_queues.get(TARGET, []) as Array).size()),
		   int(tower._alive_by_room.get(TARGET, -1)),
		   int((tower._enemy_nodes_by_room.get(TARGET, []) as Array).size())])
	print("LIFECYCLE_DONE")
