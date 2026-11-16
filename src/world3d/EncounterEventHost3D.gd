class_name EncounterEventHost3D
extends RefCounted
## EncounterEventDirector3D 的 Dungeon 窄适配器。
## 所有场景私有状态访问集中在这里，Director 不反向读取 Dungeon。

var dungeon: Dungeon3D
var _elite_spawn_serial := 0

# 当前白名单家具最大旋转半径1.159m，留0.091m几何余量。
const SPAWN_VFX_ENVELOPE_M := 1.25
const SPAWN_VFX_MIN_DISTANCE_M := 3.5
const SPAWN_VFX_MAX_HEIGHT_M := 5.7

func _init(owner: Dungeon3D = null) -> void:
	dungeon = owner

func encounter_event_input_hold(instance_id: String, held: bool) -> void:
	if _valid():
		dungeon.set_scripted_input_hold(held, false, "encounter:%s" % instance_id)


func encounter_event_current_room_id() -> String:
	return dungeon._current_room_id if _valid() else ""

func encounter_event_room_busy(room_id: String) -> bool:
	if not _valid():
		return true
	for value in dungeon._encounter_event_director.get_snapshot_rows():
		if str(value.get("room_id", "")) == room_id and not bool(value.get("terminal", false)):
			return true
	return false

func encounter_event_context(room_id: String, _instance_id: String) -> Dictionary:
	if not _valid():
		return {}
	var room := dungeon._room_by_id.get(room_id) as DungeonRoom3D
	var flags: Dictionary = {}
	if NarrativeDirector != null and NarrativeDirector.has_method("get_flags_snapshot"):
		flags = NarrativeDirector.get_flags_snapshot()
	return {
		"player_alive": dungeon.player != null and dungeon.player.current_hp > 0,
		"run_active": not dungeon._completed,
		"current_room_id": dungeon._current_room_id,
		"room_cleared": room != null and room.cleared,
		"flags": flags,
		"completed_events": dungeon._encounter_event_completed_history.duplicate(),
	}

func encounter_event_spawn(instance_id: String, room_id: String, monster_spec: Dictionary, count: int) -> Dictionary:
	if not _valid():
		return {"ok": false, "reason": "host_unavailable"}
	var vfx_validation := EncounterEventDirector3D.validate_spawn_vfx(monster_spec)
	if not bool(vfx_validation.get("ok", false)):
		return {"ok": false, "spawned": 0, "reason": vfx_validation["error"]}
	if count <= 0:
		return {"ok": false, "spawned": 0, "reason": "monster_count_invalid"}
	# 只查询同一实例的Owner事实；不另存一份关闭状态，也不封禁同event_id的新实例。
	if dungeon._encounter_event_director != null and bool(dungeon._encounter_event_director.get_snapshot(instance_id).get("dispatch_closed", false)):
		return {"ok": false, "spawned": 0, "reason": "dispatch_closed"}
	var room := dungeon._room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not room.is_streamed():
		if room != null and (not str(monster_spec.get("remote_spawn_policy", "")).is_empty() or not str(monster_spec.get("spawn_origin_port_id", "")).is_empty()):
			return {"ok": true, "spawned": 0, "retryable": true}
		return {"ok": false, "reason": "room_not_streamed"}
	if dungeon._room_spawn_blocked.has(room_id):
		if not str(monster_spec.get("remote_spawn_policy", "")).is_empty() or not str(monster_spec.get("spawn_origin_port_id", "")).is_empty():
			return {"ok": true, "spawned": 0, "retryable": true}
		return {"ok": false, "reason": "spawn_position_failed", "failed": true}
	var min_distance := float(monster_spec.get("min_player_distance_m", 0.0))
	var player_world := dungeon.player.global_position if is_instance_valid(dungeon.player) else Vector3.INF
	var occupied: Array[Vector3] = []
	for value in dungeon._enemy_nodes_by_room.get(room_id, []) as Array:
		var enemy := value as Enemy3D
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			occupied.append(enemy.global_position)
	for request: Dictionary in dungeon._reserved_room_spawns.get(room_id, []):
		for point: Vector3 in request.get("positions", []):
			occupied.append(point)
	for entry: Dictionary in dungeon._pending_delayed_spawns.get(room_id, []):
		if entry.get("position") is Vector3:
			occupied.append(entry["position"])
	var candidates: Variant = null
	var remote_policy := str(monster_spec.get("remote_spawn_policy", ""))
	var origin_port_id := str(monster_spec.get("spawn_origin_port_id", ""))
	var restricted := not remote_policy.is_empty() or not origin_port_id.is_empty()
	if restricted:
		candidates = room.get_encounter_spawn_candidates(str(monster_spec.get("trigger_port_id", "")), origin_port_id, remote_policy)
	var positions: Array = []
	var needs_vfx_space := monster_spec.has("spawn_vfx_asset_id")
	# 远端域可用子批逐步涌入，旧事件保持原整批事务语义。
	for _index in count:
		var selection := _choose_spawn_vfx_position(room, player_world, min_distance, occupied, candidates) if needs_vfx_space else room.choose_safe_spawn_position(player_world, min_distance, occupied, candidates)
		if needs_vfx_space and not bool(selection.get("ok", false)):
			var refined := _refined_spawn_vfx_candidates(room, monster_spec, candidates)
			selection = _choose_spawn_vfx_position(room, player_world, min_distance, occupied, refined)
			if not bool(selection.get("ok", false)):
				selection = _choose_spawn_vfx_paths(room, player_world, min_distance, occupied, refined)
			if not bool(selection.get("ok", false)):
				# 视觉净空不能扣住固定编成；只有原怪位也无解才走既有重试/失败。
				selection = room.choose_safe_spawn_position(player_world, min_distance, occupied, candidates)
		if not bool(selection.get("ok", false)):
			if restricted:
				if positions.is_empty():
					return {"ok": true, "spawned": 0, "retryable": true}
				break
			if bool(selection.get("retryable", false)):
				# 排除玩家与旧怪后仍装不下整批，属恒无解，不能永远假称临时拥挤。
				var intrinsic: Array[Vector3] = []
				for _capacity_index in count:
					var capacity := room.choose_safe_spawn_position(Vector3.INF, 0.0, intrinsic)
					if not bool(capacity.get("ok", false)):
						push_error("DungeonRoom3D: 房间 %s 没有可用刷怪落点（count=%d）" % [room_id, count])
						return {"ok": false, "reason": "spawn_position_failed", "failed": true}
					intrinsic.append(capacity["position"] as Vector3)
				return {"ok": true, "spawned": 0, "retryable": true}
			push_error("DungeonRoom3D: 房间 %s 没有可用刷怪落点" % room_id)
			return {"ok": false, "reason": "spawn_position_failed", "failed": true}
		var point: Vector3 = selection["position"]
		positions.append(point)
		occupied.append(point)
	count = positions.size()
	var configs: Array[Dictionary] = []
	for index in count:
		_elite_spawn_serial += 1
		var elite_reservation_id := "%s:elite:%d" % [instance_id, _elite_spawn_serial]
		var generated := dungeon._make_box_enemy(
			str(monster_spec.get("type", "")),
			maxi(1, dungeon.visual_theme.difficulty_rank),
			dungeon._record_index(room_id),
			room,
			elite_reservation_id
		)
		if generated.is_empty():
			_settle_unspawned_elites(configs)
			return {"ok": false, "reason": "spawn_config_failed"}
		# 精英的 encounter_instance_id 属于 EliteRosterService，不能覆盖；
		# Encounter Event 自己使用独立字段，普通怪才复用旧字段作为兼容值。
		generated["encounter_event_instance_id"] = instance_id
		if str(generated.get("encounter_instance_id", "")).is_empty():
			generated["encounter_instance_id"] = instance_id
		generated["encounter_event_reserved"] = true
		generated["room_id"] = room_id
		var persistent_base := str(monster_spec.get("_persistent_id_base", ""))
		if not persistent_base.is_empty():
			generated["persistent_id"] = "%s:%d" % [persistent_base, index]
		for key in ["content_id", "spawn_vfx_asset_id"]:
			if monster_spec.has(key):
				generated[key] = monster_spec[key]
		configs.append(generated)
	var had_nodes := dungeon._enemy_nodes_by_room.has(room_id)
	var before_nodes: Array = (dungeon._enemy_nodes_by_room.get(room_id, []) as Array).duplicate()
	var had_alive := dungeon._alive_by_room.has(room_id)
	var before_alive := int(dungeon._alive_by_room.get(room_id, 0))
	var spawned := dungeon._spawn_enemy_batch(room, configs, true, false, positions)
	var delivered: Array[Enemy3D] = []
	for value in dungeon._enemy_nodes_by_room.get(room_id, []) as Array:
		if value not in before_nodes and is_instance_valid(value) and not value.is_queued_for_deletion() and value is Enemy3D:
			delivered.append(value)
	if spawned != count or delivered.size() != count:
		# 与现有原子刷怪事务一致：撤回本次新增实体及存活账，不撤掉该事件此前成功的批次。
		for value in dungeon._enemy_nodes_by_room.get(room_id, []) as Array:
			if value not in before_nodes and is_instance_valid(value):
				if MonsterAIManager != null:
					MonsterAIManager.unregister_enemy(value)
				value.set_process(false)
				value.queue_free()
		if had_nodes:
			dungeon._enemy_nodes_by_room[room_id] = before_nodes
		else:
			dungeon._enemy_nodes_by_room.erase(room_id)
		if had_alive:
			dungeon._alive_by_room[room_id] = before_alive
		else:
			dungeon._alive_by_room.erase(room_id)
		_settle_unspawned_elites(configs)
		return {
			"ok": false, "spawned": 0, "failed": true,
			"reason": "spawn_position_failed" if spawned < 0 else "spawn_partial",
		}
	# 整批实到确认之后才允许表现；恢复实体不经过此交付出口。
	var asset_id := StringName(monster_spec.get("spawn_vfx_asset_id", ""))
	if not asset_id.is_empty():
		for enemy in delivered:
			_play_spawn_vfx(asset_id, room, enemy)
	return {"ok": true, "spawned": spawned}


func _refined_spawn_vfx_candidates(room: DungeonRoom3D, spec: Dictionary, original: Variant) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if original != null:
		result.assign(original)
	var policy := str(spec.get("remote_spawn_policy", ""))
	var origin_id := str(spec.get("spawn_origin_port_id", ""))
	var entry := room.get_connection_port_by_id(str(spec.get("trigger_port_id", "")))
	var origin := room.get_connection_port_by_id(origin_id)
	if (policy == "opposite_entry" and entry.is_empty()) or (not origin_id.is_empty() and origin.is_empty()):
		return result
	var inward := -room._placement_vec2(entry.get("outward", [0.0, 0.0])).normalized()
	var origin_inward := -room._placement_vec2(origin.get("outward", [0.0, 0.0])).normalized()
	var origin_position := room._placement_vec2(origin.get("position_m", [0.0, 0.0]))
	var dimensions := room.get_dimensions()
	var origin_depth := maxf(5.0, (absf(origin_inward.x) * dimensions.x + absf(origin_inward.y) * dimensions.y) * 0.35)
	# 只细化采样，不改原半区/端口带、支持面、可达性或碰撞判定。
	for x in range(ceili(-dimensions.x), floori(dimensions.x) + 1):
		for z in range(ceili(-dimensions.y), floori(dimensions.y) + 1):
			var planar := Vector2(x * 0.5, z * 0.5)
			if policy == "opposite_entry" and (inward.is_zero_approx() or planar.dot(inward) < 0.0):
				continue
			if not origin.is_empty():
				var depth := (planar - origin_position).dot(origin_inward)
				if origin_inward.is_zero_approx() or depth < 0.0 or depth > origin_depth:
					continue
			result.append(room.to_global(Vector3(planar.x, 0.0, planar.y)))
	return result


func _choose_spawn_vfx_position(room: DungeonRoom3D, player_world: Vector3, min_distance: float, occupied: Array[Vector3], candidates: Variant) -> Dictionary:
	room._prepare_safe_spawn_selection()
	var pool: Array[Vector3] = []
	if candidates == null:
		for point in room._spawn_candidates:
			pool.append(room.to_global(point))
	else:
		pool.assign(candidates)
	var selected := Vector3.INF
	var best_distance := -1.0
	for point in pool:
		if not room._safe_spawn_geometry_valid(point) or not room._safe_spawn_distances_valid(point, player_world, min_distance, occupied):
			continue
		var distance := _spawn_vfx_landing_distance(room, point)
		if distance >= SPAWN_VFX_MIN_DISTANCE_M and distance > best_distance:
			best_distance = distance
			selected = point
	if not selected.is_finite():
		return {"ok": false, "retryable": true, "reason": "spawn_vfx_space_occupied"}
	return {"ok": true, "position": selected, "landing_distance_m": best_distance}


func _choose_spawn_vfx_paths(room: DungeonRoom3D, player_world: Vector3, min_distance: float, occupied: Array[Vector3], candidates: Array[Vector3]) -> Dictionary:
	var ranked: Array[Dictionary] = []
	for point in candidates:
		if room._safe_spawn_geometry_valid(point) and room._safe_spawn_distances_valid(point, player_world, min_distance, occupied):
			ranked.append({"point":point,"clearance":_spawn_vfx_landing_distance(room,point)})
	ranked.sort_custom(func(a: Dictionary,b: Dictionary): return a.clearance > b.clearance)
	for row in ranked:
		var plan := _plan_spawn_vfx_paths(room, row.point)
		if not plan.is_empty():
			return {"ok":true, "position":row.point}
	return {"ok":false}


func _plan_spawn_vfx_paths(room: DungeonRoom3D, world_point: Vector3) -> Dictionary:
	var center := room.to_local(world_point)
	for rotation in 16:
		var yaw := rotation * TAU / 16.0
		var starts: Array[Vector3] = []
		var initial_ok := true
		for index in 5:
			var angle := TAU * index / 5.0 + yaw
			var start := Vector3(sin(angle),0,-cos(angle)) * 1.56
			if not _spawn_vfx_path_clear(room, center + start, center + start):
				initial_ok = false
				break
			starts.append(start)
		if not initial_ok:
			continue
		var paths: Array[Dictionary] = []
		for index in 5:
			var start := starts[index]
			for direction_index in 32:
				var angle := TAU * index / 5.0 + yaw + direction_index * TAU / 32.0
				var direction := Vector3(sin(angle),0,-cos(angle))
				var end := start + direction * 1.86
				if not _spawn_vfx_path_clear(room, center + start, center + end):
					continue
				var world_start := room.global_basis * start
				paths.append({"start":world_start,"push":world_start + room.global_basis * direction * 0.16,
					"end":room.global_basis * end,"direction":room.global_basis * direction,
					"yaw":(-TAU * index / 5.0 if index == 0 or index == 3 else PI * 0.5 - TAU * index / 5.0) - yaw})
				break
			if paths.size() != index + 1:
				break
		if paths.size() == 5:
			return {"piece_paths":paths,"forward":Vector3.FORWARD,"layout":"safe_fan"}
	return {}


func _spawn_vfx_path_clear(room: DungeonRoom3D, start: Vector3, end: Vector3) -> bool:
	# 0.2m步长加半步膨胀覆盖连续线段，任意翻滚包络不依赖采样姿态。
	const RADIUS := 1.35
	var sweep := AABB(Vector3(minf(start.x,end.x)-RADIUS,start.y+0.01,minf(start.z,end.z)-RADIUS),
		Vector3(absf(end.x-start.x)+RADIUS*2.0,SPAWN_VFX_MAX_HEIGHT_M,absf(end.z-start.z)+RADIUS*2.0))
	for blocker: AABB in room._spawn_blockers:
		if sweep.intersects(blocker):
			return false
	var steps := maxi(1, ceili(start.distance_to(end) / 0.2))
	for step in steps + 1:
		var point := start.lerp(end,float(step)/steps)
		if not room._spawn_floor_contains(point, RADIUS):
			return false
		# 可达性网格不是连续地砖判定；不能只验包络中心而漏掉角点落入隔离域。
		for x in range(-3,4):
			for z in range(-3,4):
				if not room._spawn_reach_contains(point + Vector3(x * RADIUS / 3.0,0,z * RADIUS / 3.0)):
					return false
	return true


func _spawn_vfx_pool() -> Node:
	return VfxPool


func _play_spawn_vfx(asset_id: StringName, room: DungeonRoom3D, enemy: Enemy3D) -> void:
	var pool: Variant = _spawn_vfx_pool()
	if pool == null or not pool.has_effect(asset_id):
		push_warning("EncounterEventHost3D: 入场效果不可用 %s；怪物已交付" % asset_id)
		return
	var point := enemy.global_position
	var forward := dungeon.player.global_position - point if is_instance_valid(dungeon.player) else room.global_position - point
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -room.global_basis.z
	var landing_distance := _spawn_vfx_landing_distance(room, point)
	var paths: Dictionary = {}
	if landing_distance < SPAWN_VFX_MIN_DISTANCE_M:
		paths = _plan_spawn_vfx_paths(room, point)
		if paths.is_empty():
			push_warning("EncounterEventHost3D: 无安全表演轨迹，跳过入场效果；固定怪物已交付")
			return
	var context := {
		"seed": enemy.get_persistent_id().hash(),
		"floor_y": point.y,
		"forward": forward.normalized(),
		"landing_distance_m": landing_distance,
	}
	context.merge(paths, true)
	if pool.acquire(asset_id, point, Color.WHITE, 1.0, context) == null:
		push_warning("EncounterEventHost3D: 入场效果借出失败 %s；怪物已交付" % asset_id)


func _spawn_vfx_landing_distance(room: DungeonRoom3D, world_point: Vector3) -> float:
	var point := room.to_local(world_point)
	if not room._spawn_floor_contains(point, SPAWN_VFX_ENVELOPE_M):
		return 0.0
	var low := 0.0
	var high := 4.0
	for _step in 10:
		var distance := (low + high) * 0.5
		if room._spawn_floor_contains(point, distance + SPAWN_VFX_ENVELOPE_M):
			low = distance
		else:
			high = distance
	# 覆盖从初始摆位到落地的整圆扫掠；地板/高于最高家具的顶层不伪装成XZ障碍。
	for bounds: AABB in room._spawn_blockers:
		if bounds.end.y <= point.y + 0.01 or bounds.position.y >= point.y + SPAWN_VFX_MAX_HEIGHT_M:
			continue
		var nearest := Vector2(
			clampf(point.x, bounds.position.x, bounds.end.x),
			clampf(point.z, bounds.position.z, bounds.end.z)
		)
		low = minf(low, maxf(0.0, Vector2(point.x, point.z).distance_to(nearest) - SPAWN_VFX_ENVELOPE_M - 0.05))
	return low

## 截止只撤回尚未实到的配置；实体、休眠敌人及事件终态仍由各自Owner持有。
func encounter_event_close_dispatch(instance_id: String) -> Dictionary:
	if not _valid():
		return {"ok": false, "reason": "host_unavailable"}
	if instance_id.is_empty():
		return {"ok": false, "reason": "instance_id_required"}
	var dropped := 0
	var cancelled_configs: Array[Dictionary] = []
	for room_id_value in dungeon._reserved_room_spawns.keys():
		var room_id := str(room_id_value)
		var requests := dungeon._reserved_room_spawns[room_id] as Array
		var removed := _drop_reserved_event_configs(requests, instance_id)
		cancelled_configs.append_array(removed)
		dropped += removed.size()
		if not removed.is_empty():
			dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - dungeon._combat_config_count(removed))
		if not removed.is_empty() and requests.is_empty():
			dungeon._reserved_room_spawns.erase(room_id)
	for room_id_value in dungeon._pending_delayed_spawns.keys():
		var room_id := str(room_id_value)
		var entries := dungeon._pending_delayed_spawns[room_id] as Array
		var removed := _drop_delayed_event_configs(entries, instance_id)
		cancelled_configs.append_array(removed)
		dropped += removed.size()
		if not removed.is_empty():
			dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - dungeon._combat_config_count(removed))
		if not removed.is_empty() and entries.is_empty():
			dungeon._pending_delayed_spawns.erase(room_id)
	# 休眠/存盘镜像会被restore重新入队；只过滤队列副本及其计数，不碰enemies。
	# 镜像不是第二份预约，不能重复增加dropped或重复结算精英。
	for state_value in dungeon._segment_runtime_state.values():
		var state := state_value as Dictionary
		var removed := _drop_reserved_event_configs(state.get("reserved_spawns", []) as Array, instance_id)
		removed.append_array(_drop_delayed_event_configs(state.get("pending_delayed_spawns", []) as Array, instance_id))
		if not removed.is_empty() and state.has("alive_count"):
			state["alive_count"] = maxi(0, int(state["alive_count"]) - dungeon._combat_config_count(removed))
	# 队列及镜像先同步完，再调用可能发信号/写档的既有精英释放方法。
	_settle_unspawned_elites(cancelled_configs)
	return {"ok": true, "dropped": dropped}


func _drop_reserved_event_configs(requests: Array, instance_id: String) -> Array[Dictionary]:
	var removed: Array[Dictionary] = []
	for request_index in range(requests.size() - 1, -1, -1):
		var request := requests[request_index] as Dictionary
		var configs := request.get("configs", []) as Array
		var positions := request.get("positions", []) as Array
		var before_count := configs.size()
		# positions是与configs按下标对应的[x,y,z]前缀，不能重建时错位或造补位。
		for index in range(configs.size() - 1, -1, -1):
			var config := configs[index] as Dictionary
			if _encounter_owner_id(config) != instance_id:
				continue
			removed.append(config)
			configs.remove_at(index)
			if index < positions.size():
				positions.remove_at(index)
		if configs.size() != before_count and configs.is_empty():
			requests.remove_at(request_index)
	return removed


func _drop_delayed_event_configs(entries: Array, instance_id: String) -> Array[Dictionary]:
	var removed: Array[Dictionary] = []
	for index in range(entries.size() - 1, -1, -1):
		var entry := entries[index] as Dictionary
		var config := entry.get("config", {}) as Dictionary
		if _encounter_owner_id(config) == instance_id:
			removed.append(config)
			# 整条移除，serial/position/due_msec随配置一起撤销；timeout找不到serial即返回。
			entries.remove_at(index)
	return removed


func encounter_event_live_count(instance_id: String) -> int:
	if not _valid():
		return 0
	var count := 0
	var instantiated_rooms: Dictionary = {}
	for room_id_value in dungeon._enemy_nodes_by_room.keys():
		var room_id := str(room_id_value)
		var room_count := 0
		for node in dungeon._enemy_nodes_by_room[room_id] as Array:
			var enemy := node as Enemy3D
			if enemy != null and is_instance_valid(enemy) and dungeon._counts_for_room_clear(enemy.enemy_data) and _encounter_owner_id(enemy.get_enemy_data()) == instance_id:
				room_count += 1
		if room_count > 0:
			instantiated_rooms[room_id] = true
			count += room_count
		# A hibernated room has no Enemy3D nodes; its stable runtime snapshot is
		# the authoritative live set until the room is streamed again.
		if room_count == 0 and not _room_is_streamed(room_id):
			var runtime_state := dungeon._segment_runtime_state.get(room_id, {}) as Dictionary
			for enemy_state_value in runtime_state.get("enemies", []) as Array:
				var enemy_state := enemy_state_value as Dictionary
				var enemy_data := enemy_state.get("enemy_data", {}) as Dictionary
				if dungeon._counts_for_room_clear(enemy_data) and _encounter_owner_id(enemy_data) == instance_id:
					count += 1
	for request_value in dungeon._reserved_room_spawns.values():
			for request in request_value as Array:
				for config in (request as Dictionary).get("configs", []) as Array:
					if dungeon._counts_for_room_clear(config as Dictionary) and _encounter_owner_id(config as Dictionary) == instance_id:
						count += 1
	for entry_value in dungeon._pending_delayed_spawns.values():
			for entry in entry_value as Array:
				var payload := (entry as Dictionary).get("config", {}) as Dictionary
				if dungeon._counts_for_room_clear(payload) and _encounter_owner_id(payload) == instance_id:
					count += 1
	return count

## 事件猎杀：把玩家位置持续押给**事件归属的已实例化敌人**。
##
## 为什么只认已实例化的：预约 / 延迟队列里的条目还没有 `Enemy3D` 节点，
## 没有"记录"可写。它们实到之后的下一帧就会被盖上（本方法由 Director 每帧调用）
## —— 与其在三处队列里各写一遍、把同一事实存三份，不如让它晚一帧。
##
## 为什么走 `MonsterAIManager.set_hunt_target` 而不是直接改敌人字段：
## 感知、记忆、开火令牌的唯一真源都在那边；这里只做"谁算这个事件的怪"的判定。
func encounter_event_hunt(instance_id: String) -> Dictionary:
	if not _valid():
		return {"ok": false, "reason": "host_unavailable"}
	var target := _hunt_target()
	if target == null:
		return {"ok": false, "reason": "no_hunt_target"}
	if MonsterAIManager == null:
		return {"ok": false, "reason": "ai_manager_unavailable"}
	var stamped := 0
	for room_id_value in dungeon._enemy_nodes_by_room.keys():
		for node in dungeon._enemy_nodes_by_room[room_id_value] as Array:
			var enemy := node as Enemy3D
			if enemy == null or not is_instance_valid(enemy):
				continue
			if _encounter_owner_id(enemy.get_enemy_data()) != instance_id:
				continue
			if MonsterAIManager.set_hunt_target(enemy, target):
				stamped += 1
	return {"ok": true, "stamped": stamped}


## 猎杀目标 = 活着的玩家。死了就没有目标可押 —— 返回 null 让上层如实以"没有目标"收场，
## 而不是押给一具尸体（那会让怪围着尸体转）。
func _hunt_target() -> Node3D:
	var candidate := dungeon.player
	if candidate == null or not is_instance_valid(candidate):
		return null
	if float(candidate.current_hp) <= 0.0:
		return null
	return candidate as Node3D


func encounter_event_despawn(instance_id: String, _reason: String) -> Dictionary:
	if not _valid():
		return {"ok": false, "error": "host_unavailable"}
	var removed := 0
	for room_id_value in dungeon._enemy_nodes_by_room.keys():
		var room_id := str(room_id_value)
		var members := dungeon._enemy_nodes_by_room[room_id] as Array
		for value in members.duplicate():
			var enemy := value as Enemy3D
			if enemy == null or not is_instance_valid(enemy):
				continue
			var enemy_data := enemy.get_enemy_data()
			if _encounter_owner_id(enemy_data) != instance_id:
				continue
			_settle_elite_for_despawn(enemy_data, room_id)
			members.erase(enemy)
			dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - 1)
			if MonsterAIManager != null:
				MonsterAIManager.unregister_enemy(enemy)
			enemy.set_process(false)
			enemy.queue_free()
			removed += 1
	for room_id_value in dungeon._reserved_room_spawns.keys():
		var room_id := str(room_id_value)
		var requests := dungeon._reserved_room_spawns[room_id] as Array
		for request_value in requests.duplicate():
			var request := request_value as Dictionary
			var configs := request.get("configs", []) as Array
			var kept_configs: Array = []
			var kept_positions: Array = []
			for index in configs.size():
				var config := configs[index] as Dictionary
				if _encounter_owner_id(config) == instance_id:
					dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - 1)
					_settle_unspawned_elites([config])
					removed += 1
					continue
				kept_configs.append(config)
				var positions := request.get("positions", []) as Array
				if index < positions.size():
					kept_positions.append(positions[index])
			if kept_configs.is_empty():
				requests.erase(request)
			else:
				request["configs"] = kept_configs
				request["positions"] = kept_positions
		if requests.is_empty():
			dungeon._reserved_room_spawns.erase(room_id)
	for room_id_value in dungeon._pending_delayed_spawns.keys():
		var room_id := str(room_id_value)
		var entries := dungeon._pending_delayed_spawns[room_id] as Array
		for entry_value in entries.duplicate():
			var entry := entry_value as Dictionary
			var payload := entry.get("config", {}) as Dictionary
			if _encounter_owner_id(payload) != instance_id:
				continue
			entries.erase(entry)
			dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - 1)
			_settle_unspawned_elites([payload])
			removed += 1
		if entries.is_empty():
			dungeon._pending_delayed_spawns.erase(room_id)
	return {"ok": true, "removed": removed}

func encounter_event_apply_result(action: Dictionary) -> Dictionary:
	if not _valid():
		return {"ok": false, "error": "host_unavailable"}
	match str(action.get("type", "")):
		"flag":
			if NarrativeDirector == null or not NarrativeDirector.has_method("set_flag"):
				return {"ok": false, "error": "result_action_failed"}
			NarrativeDirector.set_flag(str(action["key"]), action.get("value", true))
			return {"ok": true}
		"hint":
			if dungeon.status_label == null:
				return {"ok": false, "error": "result_action_failed"}
			dungeon.status_label.text = str(action["text"])
			return {"ok": true}
		"light":
			# 房间灯光的所有权仍在房间系统（`DungeonRoom3D.set_room_light_on()`），
			# 这里只做转发 —— 不自己开关 Light3D、也不猜房间有没有灯。
			# 房间不存在或没有可控灯 ⇒ 如实返回失败，不假装成功。
			var light_room := dungeon._room_by_id.get(str(action.get("room_id", ""))) as DungeonRoom3D
			if light_room == null or not light_room.has_method("set_room_light_on"):
				return {"ok": false, "error": "light_room_unavailable"}
			if not bool(light_room.call("set_room_light_on", bool(action.get("on", true)))):
				return {"ok": false, "error": "light_room_unavailable"}
			return {"ok": true}
	return {"ok": false, "error": "result_action_failed"}

func _settle_unspawned_elites(configs: Array, from_index := 0) -> void:
	if EliteRosterService == null:
		return
	for index in range(clampi(from_index, 0, configs.size()), configs.size()):
		var config := configs[index] as Dictionary
		_settle_elite_for_despawn(config, str(config.get("room_id", "")))

func _settle_elite_for_despawn(enemy_data: Dictionary, room_id: String) -> void:
	var elite_id := str(enemy_data.get("elite_id", ""))
	var encounter_id := str(enemy_data.get("encounter_instance_id", ""))
	if elite_id.is_empty() or encounter_id.is_empty() or EliteRosterService == null:
		return
	EliteRosterService.settle(elite_id, encounter_id, "despawned", {
		"floor_number": int(enemy_data.get("floor_number", enemy_data.get("floor", 0))),
		"room_id": room_id,
	})

func _encounter_owner_id(enemy_data: Dictionary) -> String:
	var event_id := str(enemy_data.get("encounter_event_instance_id", ""))
	return event_id if not event_id.is_empty() else str(enemy_data.get("encounter_instance_id", ""))

func _room_is_streamed(room_id: String) -> bool:
	var room := dungeon._room_by_id.get(room_id) as DungeonRoom3D
	return room != null and is_instance_valid(room) and room.is_streamed()

func _valid() -> bool:
	return dungeon != null and is_instance_valid(dungeon)
