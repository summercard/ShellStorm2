extends Node3D
## 定点探针：「事件 + 战斗」双职房（远征01 room_09）到底装配成了什么。
## 业主裁定 2026-09-26「保留 EVENT、放开规则」—— room_09 既要留住事件终端，又要刷 3 波。
## 本探针走真机 `_on_room_entered` 后逐项断言：房型 / 事件终端 / 事件战斗账 / 波次账 / 门控。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	for value in tower._room_by_id.values():
		(value as DungeonRoom3D).ensure_shell_built()
		(value as DungeonRoom3D).ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var room := tower._room_by_id.get("room_09") as DungeonRoom3D
	if room == null:
		print("PROBE_ROOM09_EVENT_FAIL 找不到 room_09")
		get_tree().quit(1)
		return
	var rid := room.room_id
	print("room_09：room_type=%s  spawn_placements=%d  stages=%d"
		% [room.room_type, room.spawn_placements.size(),
		   (room.encounter.get("stages", []) as Array).size()])

	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	tower._on_room_entered(room)
	await get_tree().process_frame

	print("  事件终端 get_service_station('event')      = %s"
		% ("有 ✔" if room.get_service_station("event") != null else "无 ✘"))
	print("  事件终端 ensure_required_service_station() = %s"
		% ("有 ✔" if room.ensure_required_service_station() != null else "无 ✘"))
	print("  _event_combat_rooms 含本房 = %s" % str(tower._event_combat_rooms.has(rid)))
	print("  _room_wave_totals[本房]    = %s" % str(tower._room_wave_totals.get(rid, "(无)")))
	print("  _room_wave_queues 待发波数 = %d"
		% (tower._room_wave_queues.get(rid, []) as Array).size())
	print("  进房时 room.cleared = %s（应为 false：战斗未清，门不放行）" % str(room.cleared))
	print("  _can_advance_room_wave    = %s" % str(tower._can_advance_room_wave(rid)))

	# 清空全部 3 波，看是否自动续波、末波后是否放行。
	var total := int(tower._room_wave_totals.get(rid, 0))
	for wave_index in range(1, total + 1):
		await _kill_all(rid)
		print("  第 %d 波清空 → pending=%s wave=%d"
			% [wave_index, str(tower._wave_spawn_pending.has(rid)),
			   int(tower._room_wave_numbers.get(rid, 0))])
		if wave_index < total:
			await get_tree().create_timer(2.0 + 0.35).timeout
	await get_tree().process_frame
	print("  终波后 room.cleared = %s（应为 true：3 波清完放行）" % str(room.cleared))
	print("PROBE_ROOM09_EVENT_DONE")
	get_tree().quit(0)


func _kill_all(rid: String) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		for value in tower._enemy_nodes_by_room.get(rid, []) as Array:
			var enemy := value as Enemy3D
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy._die()
				await get_tree().process_frame
		var alive := int(tower._alive_by_room.get(rid, 0))
		var delayed := (tower._pending_delayed_spawns.get(rid, []) as Array).size()
		if alive == 0 and delayed == 0:
			return
		await get_tree().create_timer(0.05).timeout
