extends Node3D
## 真实分裂/召唤旁路、读取旧越界位置、旋转与凹口；进程启动前须隔离用户目录。
const LEVEL := preload("res://scenes/ExpeditionLevel03_3D.tscn")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _ready() -> void:
	await _geometry()
	await _runtime()
	for failure in failures:
		push_error(failure)
	print("ENEMY_SPAWN_BOUNDARY_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _geometry() -> void:
	for degrees in [0, 90, 180, 270]:
		var room := DungeonRoom3D.new()
		var tiles: Array = []
		for x in [-5, 0, 5]:
			for z in [-5, 0, 5]:
				if x >= 0 and z >= 0:
					continue
				tiles.append({"slot_role":"floor_tile", "position":Vector3(x,0,z)})
		room.configure({"room_id":"boundary_l", "custom_dimensions":Vector2(15,15), "authored_layout_shell":true, "authored_layout_instances":tiles})
		room.position = Vector3(37, 8, -29)
		room.rotation_degrees.y = degrees
		add_child(room)
		room.process_mode = Node.PROCESS_MODE_DISABLED
		var valid := room.to_global(Vector3(-5, -3, -5))
		check(room.resolve_enemy_spawn_position(valid) == valid, "合法多标高原位被改动 rotation=%d" % degrees)
		for local in [Vector3(9,0.05,0),Vector3(-9,0.05,0),Vector3(0,0.05,9),Vector3(0,0.05,-9),Vector3(4,0.05,4)]:
			var point := room.resolve_enemy_spawn_position(room.to_global(local))
			check(point.is_finite(), "边界/凹口未找到合法替代点 rotation=%d" % degrees)
			if point.is_finite():
				var result := room.to_local(point)
				check(room.call("_spawn_floor_contains", result, 1.15), "替代点仍在房外/凹口 rotation=%d" % degrees)
				check(is_equal_approx(result.y, local.y), "边界修复改变原有高度")
		check(not room.resolve_enemy_spawn_position(Vector3.INF).is_finite(), "非有限点被伪造成合法点")
		room.queue_free()
		await get_tree().process_frame
	var tiny := DungeonRoom3D.new()
	tiny.configure({"room_id":"no_capacity", "custom_dimensions":Vector2(1,1)})
	add_child(tiny)
	check(not tiny.resolve_enemy_spawn_position(Vector3(5,0,5)).is_finite(), "没有合法空间时错误回退房外/房心")
	tiny.queue_free()
	await get_tree().process_frame

func _runtime() -> void:
	var tower := LEVEL.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 42
	add_child(tower)
	for frame in 15:
		await get_tree().process_frame
	var room: DungeonRoom3D
	for value in tower._rooms:
		if value is DungeonRoom3D and not value.spawn_placements.is_empty():
			room = value
			break
	check(room != null, "真实关卡无敌对房，禁止空覆盖")
	if room == null:
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	for frame in 3:
		await get_tree().physics_frame
	var config: Dictionary = tower._monster_injector.generate_split_child("egt_blobulon",1,1)
	var configs: Array[Dictionary] = [config]
	var safe := room.spawn_point_for_index(0)
	check(safe.is_finite(), "真实房无合法初始落点")
	if not safe.is_finite():
		return
	tower.call("_spawn_enemy_batch",room,configs,true,false,[safe])
	var source: Enemy3D = tower._enemy_nodes_by_room[room.room_id].back()
	source.set_physics_process(false)
	var half := room.get_dimensions()*0.5
	var anchor := room.to_global(Vector3(half.x+5,-3,0))
	var anchor_config := {"narrative_spawned":true,"narrative_placement":"world_anchor"}
	check(tower.call("_resolve_spawn_position",room,anchor_config,0,[anchor]) == anchor, "世界锚点剧情被压回房间平面")
	# 先放合法实例，再模拟走到墙边；修复不能靠挪动初始母体蒙绿。
	source.global_position = room.to_global(Vector3(0,0.05,half.y-1))
	check(room.contains_world_position(source.global_position), "反向对照母体必须在房内")
	var count_before: int = tower._enemy_nodes_by_room[room.room_id].size()
	tower.call("_on_split_requested",source,"egt_blobuloid",2)
	tower.call("_flush_reserved_room_spawns",room.room_id)
	check(tower._enemy_nodes_by_room[room.room_id].size() == count_before+2, "边界修复丢了分裂子怪")
	_verify_children(tower, room, source, "split")
	# 召唤走另一条预约入口，仍必须被唯一实例化出口拦下越界偏移。
	source.global_position = room.to_global(Vector3(half.x-1,0.05,0))
	count_before = tower._enemy_nodes_by_room[room.room_id].size()
	tower.call("_on_summon_requested",source,1)
	tower.call("_flush_reserved_room_spawns",room.room_id)
	check(tower._enemy_nodes_by_room[room.room_id].size() == count_before+1, "边界修复丢了召唤怪")
	_verify_children(tower,room,source,"summon")
	check(tower._reserved_spawn_count(room.room_id) == 0, "预约实到后存活账未清")
	# 旧快照越界：只修位置，持久ID、血量、攻击冷却不能被重置。
	var hp := source.current_hp
	var persistent := source.get_persistent_id()
	source.set("_attack_timer",0.73)
	source.global_position = room.to_global(Vector3(half.x+2,0.05,0))
	check(tower.call("_repair_restored_enemy_room_position",source,room), "旧越界位置没有修复")
	check(room.contains_world_position(source.global_position), "旧快照修后仍越界")
	check(source.current_hp == hp and source.get_persistent_id() == persistent and is_equal_approx(float(source.get("_attack_timer")),0.73), "位置修复重置了战斗状态")
	tower.queue_free()
	await get_tree().process_frame

func _verify_children(tower: TowerDescent3D, room: DungeonRoom3D, source: Enemy3D, label: String) -> void:
	for value in tower._enemy_nodes_by_room[room.room_id]:
		var enemy := value as Enemy3D
		enemy.set_physics_process(false)
		if enemy == source:
			continue
		check(room.contains_world_position(enemy.global_position), "%s子怪出生在房外：%s" % [label,room.to_local(enemy.global_position)])
