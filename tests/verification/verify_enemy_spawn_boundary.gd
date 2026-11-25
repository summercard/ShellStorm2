extends Node3D
## 真实分裂/召唤旁路、读取旧越界位置、旋转与凹口；进程启动前须隔离用户目录。
const LEVEL := preload("res://scenes/ExpeditionLevel03_3D.tscn")
var failures: Array[String] = []
var checks := 0

class CollisionProbeRoom extends DungeonRoom3D:
	var scans := 0

	func _collect_spawn_blockers() -> void:
		scans += 1
		super()


class BoxCompilerProbe extends Dungeon3D:
	var enable_on_elite: CollisionShape3D
	var elite_calls := 0

	func _make_box_enemy(kind: String, _floor: int, _level: int, _room: DungeonRoom3D, _encounter: String = "") -> Dictionary:
		if kind == "elite" and is_instance_valid(enable_on_elite):
			elite_calls += 1
			enable_on_elite.disabled = false
		return {"enemy_type": kind}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _ready() -> void:
	_verify_same_call_geometry_batch()
	if "--batch-only" not in OS.get_cmdline_user_args():
		await _geometry()
		await _runtime()
	for failure in failures:
		push_error(failure)
	print("ENEMY_SPAWN_BOUNDARY_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _make_batch_room(angle: float) -> CollisionProbeRoom:
	var room := CollisionProbeRoom.new()
	room.configure({"room_id": "box_batch", "room_type": "COMBAT", "seed": 701,
		"custom_dimensions": Vector2(24, 24)})
	room.rotation_degrees.y = angle
	room.position = Vector3(36, 8, -21)
	var scope := Node3D.new()
	add_child(scope)
	scope.add_child(room)
	# Lightweight fixture: only directly attached collision members, no content spawners.
	room._detail_built = true
	room._spawn_reach_probe_frame = -1
	return room


func _add_batch_blocker(room: DungeonRoom3D, center: Vector3, size: Vector3) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.position = center
	var collision := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = size
	collision.shape = geometry
	body.add_child(collision)
	room.add_child(body)
	return collision


func _verify_same_call_geometry_batch() -> void:
	var compiler := BoxCompilerProbe.new()
	compiler.run_seed = 41021
	for angle in [0.0, 90.0]:
		var room := _make_batch_room(angle)
		var reference := _make_batch_room(angle)
		_add_batch_blocker(room, Vector3(0, 1, 0), Vector3(2, 2, 4))
		_add_batch_blocker(reference, Vector3(0, 1, 0), Vector3(2, 2, 4))
		room.spawn_placements = [
			{"box": "box_wall_arc", "center_m": [-6, 0]},
			{"box": "box_wall_arc", "center_m": [6, 0], "rotation_deg": 45, "delay_sec": 0.25},
			{"box": "box_room_spread", "center_m": [5, 6], "size_m": [6, 5]},
		]
		room.encounter = {"stages": [{"boxes": [0, 1]}, {"boxes": [2]}]}
		var observed := compiler._spawn_box_waves(room, 1, 0)
		var rng := RandomNumberGenerator.new()
		rng.seed = compiler.run_seed ^ reference.room_id.hash() ^ 0x424f5831
		var expected: Array = []
		for stage: Dictionary in room.encounter["stages"]:
			var entries: Array[Dictionary] = []
			for index: int in stage["boxes"]:
				# Standalone calls still read live geometry; do not pass the reuse marker.
				compiler._collect_box_stage_entries(reference, room.spawn_placements, index, 1, 0, rng, entries)
			expected.append(entries)
		check(expected.size() == 2 and not expected[0].is_empty() and not expected[1].is_empty(), "复用对照不能是空编成")
		check(observed == expected, "批内复用改变盒顺序、稳定 ID、落点或延迟（角度 %s）" % angle)
		check(room.scans == 1 and reference.scans == 3, "同批应只采集一次，独立三盒仍逐次采集：%d/%d" % [room.scans, reference.scans])
		check(room._spawn_reach_evaluated and room._spawn_reach_active and room._spawn_candidates == reference._spawn_candidates,
			"首次可达性闸门未正确生效，或重排了候选池")
		var same_tick := Engine.get_physics_frames()
		var cover := _add_batch_blocker(room, Vector3(0, 1, 0), Vector3(30, 2, 30))
		check(compiler._spawn_box_waves(room, 1, 0).is_empty() and room.scans == 2,
			"第二次编排沿用了上一批阻挡物，或重复采集")
		cover.disabled = true
		check(compiler._spawn_box_waves(room, 1, 0) == observed and room.scans == 3 and Engine.get_physics_frames() == same_tick,
			"同物理帧禁用阻挡后仍使用旧几何，或编排意外让帧")
		room.get_parent().free()
		reference.get_parent().free()

	var identity_room := _make_batch_room(0.0)
	var cover := _add_batch_blocker(identity_room, Vector3(0, 1, 0), Vector3(30, 2, 30))
	cover.disabled = true
	identity_room.spawn_placements = [
		{"box": "box_center_elite", "center_m": [-6, 0], "size_m": [6, 5]},
		{"box": "box_wall_arc", "center_m": [6, 0]},
	]
	var before := compiler._spawn_box_waves(identity_room, 1, 0)
	check(before.size() == 1 and before[0].any(func(entry: Dictionary) -> bool: return entry.persistent_id.begins_with("box_batch:box_1:")),
		"身份回调对照未覆盖第二盒")
	compiler.enable_on_elite = cover
	identity_room.scans = 0
	var after := compiler._spawn_box_waves(identity_room, 1, 0)
	check(compiler.elite_calls == 1 and not cover.disabled, "身份工厂的几何改变未发生")
	check(after.size() == 1 and not after[0].is_empty() and after[0].all(func(entry: Dictionary) -> bool: return entry.persistent_id.begins_with("box_batch:box_0:")),
		"身份回调之后的盒没有使用当下碰撞")
	check(identity_room.scans == 2, "身份工厂改变碰撞后，下一普通盒必须重新采集")
	identity_room.get_parent().free()
	compiler.free()


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
