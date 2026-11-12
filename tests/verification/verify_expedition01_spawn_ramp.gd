extends Node
## 从46c1ca78恢复生产验收A/B/C/D/E/F/G结构；批准曲线不再要求全关单调。
## 主验收调用正式Tower/Room；端点替身只替换随机抽数和身份工厂，不冒充正式名册实到。
const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const BOX_ROOMS := ["room_01", "room_02", "room_05", "room_07", "room_08", "boss"]
const EXPECTED_BONUS := {
	"room_01": [0, 0, 0], "room_02": [0, 0, 0],
	"room_05": [1, 0, 2, 2, 0], "room_07": [2, 2, 2],
	"room_08": [1, 1, 1, 2, 0], "boss": [0, 0, 0, 0],
}
const EXPECTED_MULTIPLIER := {
	"room_01": [1, 1, 1], "room_02": [1, 1, 1],
	"room_05": [1, 1, 1, 1, 1], "room_07": [1, 1, 1],
	"room_08": [1, 1, 1, 1, 1], "boss": [1, 1, 1, 1],
}
const WAVE_BOUNDS := {
	"room_01": [[6, 6]], "room_02": [[7, 8]],
	"room_05": [[31, 31]], "room_07": [[12, 12]],
	"room_08": [[16, 17]], "boss": [[4, 4], [5, 5], [1, 2]],
}
# 历史证据：跨高度整体AABB误封平台时的旧测量，不要求修复后继续偏移。
const LEGACY_DRIFT_EVIDENCE := {"room_08": {4: 20.0}, "boss": {0: 11.07, 3: 4.81}}
# 仅08#4保留已登记20m例外；Boss#1允许现有生产就近足量策略在一格内落地。
const PINNED_DRIFT := {"room_08": {4: 20.0}}
const BOSS_LOCAL_SHIFT_LIMIT_M := 5.0
const TRIGGER_EXPECTED := {
	"room_03": {"shape": "door_entries", "intermission": 3.0, "cap": 8, "waves": [
		{"ranged_caster": 1, "melee_chaser": 4}, {"fat_zombie03": 1, "ranged_caster": 2, "melee_chaser": 4}, {"fat_zombie03": 2, "ranged_caster": 2, "melee_chaser": 4}]},
	"room_04": {"shape": "door_entries", "intermission": 2.5, "cap": 6, "waves": [
		{"ranged_caster": 2, "melee_chaser": 4}, {"ranged_caster": 2, "melee_chaser": 4}]},
	"room_06": {"shape": "door_entries", "intermission": 2.5, "cap": 10, "waves": [
		{"fat_zombie03": 1, "ranged_caster": 2, "melee_chaser": 5},
		{"fat_zombie03": 1, "melee_chaser_strong": 1, "ranged_caster": 2, "melee_chaser": 5},
		{"fat_zombie03": 2, "melee_chaser_strong": 1, "ranged_caster_strong": 1, "ranged_caster": 3, "melee_chaser": 6}]},
	"room_09": {"shape": "door_entries", "intermission": 2.5, "cap": 12, "waves": [
		{"fat_zombie03": 1, "ranged_caster": 2, "melee_chaser": 5},
		{"fat_zombie03": 1, "melee_chaser_strong": 1, "ranged_caster": 3, "melee_chaser": 6},
		{"fat_zombie03": 2, "melee_chaser_strong": 1, "ranged_caster_strong": 1, "ranged_caster": 3, "melee_chaser": 6},
		{"fat_zombie03": 2, "melee_chaser_strong": 2, "ranged_caster_strong": 1, "ranged_caster": 4, "melee_chaser": 7}]},
	"room_10": {"shape": "door_entries", "intermission": 2.0, "cap": 5, "waves": [
		{"ranged_caster": 1, "melee_chaser": 4}, {"ranged_caster": 1, "melee_chaser": 4}]},
}

class CompilerProbe extends Dungeon3D:
	var high := false
	var drop_bonus := false
	var drop_multiplier := false
	func _roll_box_count(spawn: Dictionary, _rng: RandomNumberGenerator) -> int:
		return int(spawn.get("count_max" if high else "count_min", 0))
	func _box_placement_at(placements: Array, index: int) -> Dictionary:
		var out := super._box_placement_at(placements, index)
		if drop_bonus:
			out.erase("box_count_bonus")
		if drop_multiplier:
			out.erase("box_count_multiplier")
		return out
	func _make_box_enemy(type_id: String, _floor: int, _level: int, _room: DungeonRoom3D, _encounter: String = "") -> Dictionary:
		return {"type": type_id}

var failures: Array[String] = []
var tower: TowerDescent3D
var checks := 0
var compiled_boxes := 0
var endpoint_boxes := 0

func _ready() -> void:
	var app := OS.get_environment("APPDATA").replace("\\", "/").to_lower()
	var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower()
	_check(app != local and app.get_base_dir() == local.get_base_dir(), "APPDATA/LOCALAPPDATA未独立隔离")
	_check(app.contains("shellstorm-verification") and local.contains("shellstorm-verification"), "启动前须使用标准shellstorm-verification隔离目录")
	if not failures.is_empty():
		_finish()
		return
	if "--preplaced-unit-only" in OS.get_cmdline_user_args():
		_verify_preplaced_validator()
		_verify_preplaced_unit()
		_finish()
		return
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://spawn_ramp_%d.json" % OS.get_process_id()
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	print("SPAWN_RAMP_BOOT_BEGIN")
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.size() == 13 and tower._main_story_gameplay_started and not tower._expedition_loading_active:
			break
		await get_tree().process_frame
	var ready := tower._room_by_id.size() == 13 and tower._main_story_gameplay_started and not tower._expedition_loading_active and not tower._expedition_bootstrap_failed
	_check(ready, "120秒内正式13房未就绪 rooms=%d" % tower._room_by_id.size())
	if not ready:
		_finish()
		return
	print("SPAWN_RAMP_RUNTIME_READY")
	tower.set_process(false)
	if "--preplaced-only" in OS.get_cmdline_user_args():
		tower.player.set_physics_process(false)
		tower.get_node("ActiveEnemies").process_mode = Node.PROCESS_MODE_DISABLED
		_verify_preplaced_validator()
		await _verify_preplaced_no_kills()
		_finish()
		return
	for value in tower._room_by_id.values():
		var room := value as DungeonRoom3D
		room.ensure_shell_built()
		room.ensure_detail_built()
		_check(room._shell_built and room._detail_built, "%s壳体/细节未就绪" % room.room_id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if "--negative-bonus" in OS.get_cmdline_user_args():
		_verify_negative_bonus_only()
		_finish()
		return
	_verify_bonus_field()
	_verify_multiplier_field()
	_verify_counts()
	_verify_strong_squad_overrides()
	_verify_drift()
	_verify_trigger_encounters()
	_verify_legacy_trigger_compatibility()
	_verify_endpoints_and_negative_controls()
	_finish()

func _verify_preplaced_validator() -> void:
	var valid := {"spawn_mode": "preplaced", "intermission_sec": 0.0, "min_player_distance_m": 6.0, "stages": [{"boxes": [0]}]}
	_check(LevelPlanValidator._validate_encounter({"encounter": valid}, "fixture", 1).is_empty(), "预置模式合法数据可通过")
	for mutation in [{"spawn_mode": "typo"}, {"spawn_mode": true}, {"trigger": {"shape": "circle"}}, {"intermission_sec": 1.0}, {"min_player_distance_m": -1.0}, {"stages": [{"boxes": [0]}, {"boxes": [0]}]}]:
		var invalid := valid.duplicate(true)
		invalid.merge(mutation, true)
		_check(not LevelPlanValidator._validate_encounter({"encounter": invalid}, "fixture", 1).is_empty(), "预置负向数据必须拒绝：%s" % mutation)


func _verify_preplaced_unit() -> void:
	var room := DungeonRoom3D.new()
	room.room_id = "preplaced_unit"
	room.room_type = "COMBAT"
	room.custom_dimensions = Vector2(30, 30)
	room.encounter = {"spawn_mode": "preplaced", "intermission_sec": 0.0, "min_player_distance_m": 0.0}
	add_child(room)
	var compiler := CompilerProbe.new()
	var raw := {"box": "box_center_elite", "center_m": [2.5, 2.5], "delay_sec": 2.0, "count_bonus": 2, "spawn_overrides": [{"type": "melee_chaser", "count": 1, "delay_sec": 0.5}, {"type": "melee_chaser_strong", "count": 1}]}
	var entries: Array[Dictionary] = []
	compiler._collect_box_stage_entries(room, [raw], 0, 1, 0, RandomNumberGenerator.new(), entries)
	_check(entries.size() == 4, "紧盒编译4只不截断")
	for entry in entries:
		_check(entry["spawn_delay_sec"] == 0.0, "预置必须覆盖实例及共享条目延迟")
	var pick := compiler._preselect_preplaced_room(room, entries)
	_check(pick.ok and (pick.positions as Array).size() == 4, "4x4盒按2米间距一次排满4只")
	var pool: Array[Vector3] = []
	for x in range(-4, 5):
		for z in range(-6, 7):
			pool.append(room.to_global(Vector3(x, 0, z)))
	var dense := room.preplaced_points_in_box(pool, 16, 1.7, Vector3.INF, 0.0, [], 77)
	_check(dense.size() == 16, "小盒intrinsic按真实身体1.7米排满16，不用2.4米离墙口径")
	for index in dense.size():
		for previous in dense.slice(0, index):
			_check(dense[index].distance_to(previous) >= 1.7 - 0.001, "密集盒身体不重叠")
	var legacy := room.encounter
	room.encounter = {}
	var old: Array[Dictionary] = []
	compiler._collect_box_stage_entries(room, [raw], 0, 1, 0, RandomNumberGenerator.new(), old)
	_check(old[0]["spawn_delay_sec"] == 2.5 and not old[0].has("spawn_preplaced_box"), "旧默认模式延迟与能力键不变")
	room.encounter = legacy
	var broken := entries.duplicate(true)
	broken[0].erase("spawn_preplaced_box")
	_check(not compiler._preselect_preplaced_room(room, broken).ok, "负向缺编译键不走旧延迟")
	broken = entries.duplicate(true)
	broken[0]["spawn_delay_sec"] = 0.5
	_check(not compiler._preselect_preplaced_room(room, broken).ok, "负向延迟编译必须拒绝")
	broken = entries.duplicate(true)
	broken[0]["spawn_safe_candidates"] = []
	var rejected := compiler._preselect_preplaced_room(room, broken)
	_check(not rejected.ok and rejected.error == "preplaced_capacity_insufficient" and not compiler._pending_delayed_spawns.has(room.room_id), "负向空盒容量显式拒绝，不创建temporal pending")
	print("SPAWN_RAMP_PREPLACED_UNIT checks=%d failures=%d" % [checks, failures.size()])
	compiler.free()
	room.free()


func _verify_preplaced_no_kills() -> void:
	for key in ["room_01", "room_02", "room_05", "room_07", "room_08"]:
		var room := tower._room_by_id[key] as DungeonRoom3D
		var original := room.encounter.duplicate(true)
		_check(room.encounter.get("spawn_mode", "") == "preplaced", "%s正式数据缺preplaced，不允许测试内补键" % key)
		if room.encounter.get("spawn_mode", "") != "preplaced":
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_shell_built()
		room.ensure_detail_built()
		await get_tree().physics_frame
		var port := room.get_connection_port_by_id("A")
		var position := room._placement_vec2(port["position_m"]) - room._placement_vec2(port["outward"]) * 3.5
		tower.player.global_position = room.to_global(Vector3(position.x, 0.5, position.y))
		var waves := tower._spawn_box_waves(room, maxi(1, tower.visual_theme.difficulty_rank), _floor_level(room))
		_check(waves.size() == 1, "%s编译必须单波" % key)
		if waves.size() != 1:
			continue
		var compiled: Array[Dictionary] = []
		compiled.assign(waves[0])
		var bounds: Array = WAVE_BOUNDS[key][0]
		_check(compiled.size() >= int(bounds[0]) and compiled.size() <= int(bounds[1]), "%s编译数量不符" % key)
		for entry in compiled:
			_check(entry.get("spawn_delay_sec", -1.0) == 0.0 and entry.has("spawn_preplaced_box"), "%s共享盒条目及placement延迟均须归零" % key)
		var missing := compiled.duplicate(true)
		missing[0].erase("spawn_preplaced_box")
		_check(not tower._preselect_preplaced_room(room, missing).ok, "%s负向丢编译能力键必须拒绝" % key)
		var delayed := compiled.duplicate(true)
		delayed[0]["spawn_delay_sec"] = 0.5
		_check(not tower._preselect_preplaced_room(room, delayed).ok, "%s负向延迟回归必须拒绝" % key)
		var impossible := compiled.duplicate(true)
		impossible[0]["spawn_safe_candidates"] = []
		_check(not tower._preselect_preplaced_room(room, impossible).ok and (tower._enemy_nodes_by_room.get(key, []) as Array).is_empty(), "%s负向空域不得半房提交" % key)
		tower.force_enter_room_for_test(key)
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		var members: Array = tower._enemy_nodes_by_room.get(key, [])
		print("SPAWN_RAMP_PREPLACED_COMMIT room=%s expected=%d actual=%d delayed=%d reserved=%d blocked=%s checks=%d" % [key, compiled.size(), members.size(), tower._pending_delayed_spawn_count(key), tower._reserved_spawn_count(key), tower._room_spawn_blocked.has(key), checks])
		_check(not tower._room_spawn_blocked.has(key), "%s预置容量不足，见精确生产拒绝日志" % key)
		if tower._room_spawn_blocked.has(key):
			continue
		_check(members.size() == compiled.size(), "%s首波实际全量实到 actual=%d expected=%d" % [key, members.size(), compiled.size()])
		_check(tower._reserved_spawn_count(key) == 0 and (tower._pending_delayed_spawns.get(key, []) as Array).is_empty(), "%s提交后pending必须立即为空" % key)
		var snapshot := {}
		var occupied: Array[Vector3] = []
		var box_points := {}
		var configs_by_id := {}
		for entry in compiled:
			configs_by_id[entry["persistent_id"]] = entry
		for enemy: Enemy3D in members:
			var point := enemy.global_position
			var config: Dictionary = configs_by_id[enemy.get_persistent_id()]
			_check((config["spawn_safe_candidates"] as Array).has(point), "%s实体不得越出冻结resolved域" % key)
			_check(Vector2(point.x - tower.player.global_position.x, point.z - tower.player.global_position.z).length() >= 6.0, "%s初始安全6m" % key)
			for previous in occupied:
				_check(point.distance_to(previous) >= 1.7 - 0.001, "%s跨盒身体不重叠" % key)
			var box_index := int(config["spawn_preplaced_box"])
			for previous: Vector3 in box_points.get(box_index, []):
				_check(point.distance_to(previous) >= maxf(1.7, float(config["spawn_box_min_spacing_m"])) - 0.001, "%s盒内声明间距保留" % key)
			if not box_points.has(box_index):
				box_points[box_index] = []
			box_points[box_index].append(point)
			occupied.append(point)
			snapshot[enemy.get_instance_id()] = point
		# 不杀一只怪，保留所有占位；玩家越过初始区后等待真实计时器，而不是释放空间等补刷。
		tower.player.global_position = room.to_global(Vector3(-position.x, 0.5, -position.y))
		await get_tree().create_timer(2.1).timeout
		var after: Array = tower._enemy_nodes_by_room.get(key, [])
		_check(after.size() == snapshot.size(), "%s前进后不得新增实体" % key)
		for enemy: Enemy3D in after:
			_check(snapshot.has(enemy.get_instance_id()) and enemy.global_position.is_equal_approx(snapshot.get(enemy.get_instance_id(), Vector3.INF)), "%s存活怪身份与位置稳定，不追玩家迁移" % key)
		_check(tower._reserved_spawn_count(key) == 0 and (tower._pending_delayed_spawns.get(key, []) as Array).is_empty(), "%s前进后pending仍空" % key)
		_check(int(tower._room_wave_totals.get(key, 0)) == 1 and (tower._room_wave_queues.get(key, []) as Array).is_empty() and not room.cleared, "%s不杀怪无第二波且不发清房奖" % key)
		_check(room.encounter == original, "%s不得覆盖生产encounter" % key)
		print("SPAWN_RAMP_PREPLACED room=%s expected=%d actual=%d pending=0 no_kills=true stable=true checks=%d" % [key, compiled.size(), after.size(), checks])
		# 足量、空pending及前进后稳定均验完，才单独驱动击杀出口检查清房，不借击杀腾位补刷。
		for enemy: Enemy3D in after.duplicate():
			tower._on_enemy_killed(enemy, enemy.get_enemy_data())
			enemy.free()
		await get_tree().create_timer(2.1).timeout
		_check(room.cleared and int(tower._alive_by_room.get(key, -1)) == 0, "%s整群清完正式清房" % key)
		_check((tower._enemy_nodes_by_room.get(key, []) as Array).is_empty() and (tower._room_wave_queues.get(key, []) as Array).is_empty() and not tower._wave_spawn_pending.has(key), "%s清完不出现第二波实体或波次预约" % key)
		_check(tower._reserved_spawn_count(key) == 0 and (tower._pending_delayed_spawns.get(key, []) as Array).is_empty() and int(tower._room_wave_totals.get(key, 0)) == 1, "%s清完仍无延迟或预约且只有一波" % key)
		print("SPAWN_RAMP_PREPLACED_CLEAR room=%s cleared=%s second_wave=false checks=%d" % [key, room.cleared, checks])


func _finish() -> void:
	for failure in failures:
		print("EXPEDITION01_SPAWN_RAMP_FAIL " + failure)
	print("EXPEDITION01_SPAWN_RAMP_DONE checks=%d compiled_boxes=%d endpoint_boxes=%d failures=%d" % [checks, compiled_boxes, endpoint_boxes, failures.size()])
	if failures.is_empty():
		print("EXPEDITION01_SPAWN_RAMP_OK")
	if is_instance_valid(tower):
		tower.queue_free()
	get_tree().quit(0 if failures.is_empty() else 1)

# A/B/G：实际归一映射，身份条目不接受bonus或multiplier。
func _verify_bonus_field() -> void:
	for key in BOX_ROOMS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			_check(false, "缺少盒式房%s" % key)
			continue
		var expected: Array = EXPECTED_BONUS[key]
		_check(room.spawn_placements.size() == expected.size(), "%s盒数漂移" % key)
		for i in mini(expected.size(), room.spawn_placements.size()):
			var raw: Dictionary = room.spawn_placements[i]
			var resolved := tower._box_placement_at(room.spawn_placements, i)
			_check(int(raw.get("count_bonus", 0)) == expected[i], "%s#%d数据bonus漂移" % [key, i])
			_check(int(resolved.get("box_count_bonus", -1)) == expected[i], "%s#%d生产bonus映射断裂" % [key, i])
			_verify_bonus_lands_on_grunt(key, i, raw, resolved)

func _verify_bonus_lands_on_grunt(key: String, index: int, raw: Dictionary, resolved: Dictionary) -> void:
	if int(resolved.get("box_count_bonus", 0)) > 0:
		_check(_box_has_grunt(_expected_box(raw)), "%s#%d没有承载增量的普通条目" % [key, index])

func _verify_multiplier_field() -> void:
	for key in BOX_ROOMS:
		var room := tower._room_by_id[key] as DungeonRoom3D
		var expected: Array = EXPECTED_MULTIPLIER[key]
		_check(room.spawn_placements.size() == expected.size(), "%s倍率盒数漂移" % key)
		for i in mini(expected.size(), room.spawn_placements.size()):
			var raw: Dictionary = room.spawn_placements[i]
			var resolved := tower._box_placement_at(room.spawn_placements, i)
			_check(int(raw.get("count_multiplier", 1)) == expected[i], "%s#%d数据倍率漂移" % [key, i])
			_check(int(resolved.get("box_count_multiplier", -1)) == expected[i], "%s#%d生产倍率映射断裂" % [key, i])
			_check(_box_has_grunt(_expected_box(raw)), "%s#%d无倍率承载条目" % [key, i])

func _box_has_grunt(box: Dictionary) -> bool:
	for spawn: Dictionary in box.get("spawns", []):
		if str(spawn["type"]) not in ["elite", "boss"] and int(spawn["count_max"]) > 0:
			return true
	return false

# C/D：六房均走正式_collect_box_stage_entries及_spawn_box_waves，不以JSON总和代替。
func _verify_counts() -> void:
	for key in BOX_ROOMS:
		_replay_room(tower._room_by_id[key] as DungeonRoom3D, key)

func _replay_room(room: DungeonRoom3D, key: String) -> void:
	var stages := tower._resolve_encounter_stages(room.encounter, room.spawn_placements.size())
	var expected: Array = WAVE_BOUNDS[key]
	_check(stages.size() == expected.size(), "%s生产阶段数漂移" % key)
	if key != "boss":
		_check(stages.size() == 1 and stages[0].size() == room.spawn_placements.size(), "%s普通房必须一次完整提交所有盒" % key)
		_check(float(room.encounter.get("intermission_sec", -1)) == 0.0, "%s普通房间歇必须显式0" % key)
	var rng := RandomNumberGenerator.new()
	rng.seed = tower.run_seed ^ room.room_id.hash() ^ 0x424f5831
	var floor_number := maxi(1, tower.visual_theme.difficulty_rank)
	var level := _floor_level(room)
	var counts: Array = []
	for stage_index in stages.size():
		var entries: Array[Dictionary] = []
		for instance in stages[stage_index]:
			var begin := entries.size()
			tower._collect_box_stage_entries(room, room.spawn_placements, int(instance), floor_number, level, rng, entries)
			var actual: Array[Dictionary] = []
			actual.assign(entries.slice(begin))
			var raw: Dictionary = room.spawn_placements[int(instance)]
			var bounds := _design_bounds(_expected_box(raw), int(raw.get("count_bonus", 0)), int(raw.get("count_multiplier", 1)))
			_check(actual.size() >= bounds["lo"] and actual.size() <= bounds["hi"], "%s#%d正式编译%d不在%d..%d，容量/名册/编译缺失" % [key, instance, actual.size(), bounds["lo"], bounds["hi"]])
			_check(_id_realized(actual) == bounds["id"], "%s#%d正式身份实际%d!=%d，不能以配置占位冒充实到" % [key, instance, _id_realized(actual), bounds["id"]])
			if key != "boss":
				for config: Dictionary in actual:
					_check(float(config.get("spawn_delay_sec", 0.0)) == 0.0, "%s#%d预置编译仍有延迟" % [key, instance])
			_verify_box_domain(room, raw, actual, int(bounds["hi"]))
			compiled_boxes += 1
		counts.append(entries.size())
		if stage_index < expected.size():
			_check(entries.size() >= expected[stage_index][0] and entries.size() <= expected[stage_index][1], "%s波%d正式数量%d超预期%s" % [key, stage_index, entries.size(), expected[stage_index]])
	var waves := tower._spawn_box_waves(room, floor_number, level)
	_check(waves.size() == stages.size(), "%s生产整房编译丢空波" % key)
	for i in mini(waves.size(), counts.size()):
		_check((waves[i] as Array).size() == counts[i], "%s整房/逐盒编译数量不一致" % key)
	print("SPAWN_RAMP_PRODUCTION room=%s waves=%s" % [key, counts])

func _verify_strong_squad_overrides() -> void:
	var cases := [
		["room_05", 2, {"melee_chaser": 3, "melee_chaser_strong": 1}],
		["room_07", 0, {"melee_chaser": 3, "melee_chaser_strong": 1}],
		["room_08", 3, {"melee_chaser": 3, "ranged_caster_strong": 1}],
		["boss", 0, {"boss": 1, "melee_chaser_strong": 1, "ranged_caster_strong": 1, "summoner": 1}],
	]
	var overrides := 0
	for key in BOX_ROOMS:
		var room := tower._room_by_id[key] as DungeonRoom3D
		for raw: Dictionary in room.spawn_placements:
			if raw.has("spawn_overrides"):
				overrides += 1
			for spawn: Dictionary in _expected_box(raw)["spawns"]:
				_check(spawn["type"] != "elite", "%s仍声明失效唯一精英槽" % key)
	_check(overrides == 5, "四个强化替换加05桥心延迟覆盖共五个实例")
	var bridge := tower._room_by_id["room_05"] as DungeonRoom3D
	var bridge_entries: Array[Dictionary] = []
	tower._collect_box_stage_entries(bridge, bridge.spawn_placements, 4, 1, 0, RandomNumberGenerator.new(), bridge_entries)
	_check(bridge_entries.size() == 16, "桥心延迟覆盖不得改变16只编成")
	for item: Array in cases:
		var room := tower._room_by_id[item[0]] as DungeonRoom3D
		var index := int(item[1])
		var raw: Dictionary = room.spawn_placements[index]
		_check(raw.has("spawn_overrides"), "%s#%d实例替换丢失" % [item[0], index])
		var entries: Array[Dictionary] = []
		tower._collect_box_stage_entries(room, room.spawn_placements, index, maxi(1, tower.visual_theme.difficulty_rank), _floor_level(room), RandomNumberGenerator.new(), entries)
		var actual := {}
		for entry in entries:
			_check(not bool(entry.get("is_elite", false)) and str(entry.get("type", "")) != "elite", "%s正式编译仍产唯一精英" % item[0])
			var kind := str(entry.get("enemy_type", entry.get("type", "")))
			actual[kind] = int(actual.get(kind, 0)) + 1
		# 概率升级可以升级普通M；明确指定SM/SR必须至少各有声明数量。
		var required: Dictionary = item[2]
		_check(entries.size() == 4, "%s#%d强化小队正式编译不是4只：%s" % [item[0], index, actual])
		for kind: String in required:
			if kind.ends_with("_strong"):
				_check(int(actual.get(kind, 0)) >= int(required[kind]), "%s#%d显式强化%s未生效：%s" % [item[0], index, kind, actual])
		if item[0] == "room_05":
			_check(actual == required, "05抑制随机升级但指定SM应保留：%s" % actual)
		if item[0] == "boss":
			_check(int(actual.get("boss", 0)) == 1 and int(actual.get("summoner", 0)) == 1, "Boss本体/召唤者丢失：%s" % actual)
		print("SPAWN_RAMP_STRONG_SQUAD room=%s box=%d actual=%s" % [item[0], index, actual])

# E/F：旧快照只作历史说明；修复后的契约按真实需求、足量、承重和有限授权域验收。
func _verify_drift() -> void:
	var drifted := {}
	for key in BOX_ROOMS:
		var room := tower._room_by_id[key] as DungeonRoom3D
		for i in room.spawn_placements.size():
			var raw: Dictionary = room.spawn_placements[i]
			var box := _expected_box(raw)
			var p := tower._box_placement_at(room.spawn_placements, i)
			var center: Vector2 = p["box_center"]
			var spacing := float(box.get("min_spacing_m", 0.0))
			var recess := int(box.get("wall_recess_tiles", SpawnBoxCatalog.DEFAULT_WALL_RECESS_TILES))
			var required := int(_design_bounds(box, int(raw.get("count_bonus", 0)), int(raw.get("count_multiplier", 1)))["hi"])
			var resolved := room.resolve_spawn_box_center_local(center, p["box_size"], required, p["box_rotation"], spacing, recess)
			var drift := center.distance_to(resolved)
			_check(resolved.is_finite(), "%s#%d落地盒心非有限" % [key, i])
			if drift > 0.001:
				if not drifted.has(key):
					drifted[key] = {}
				drifted[key][i] = drift
				_check(int(raw.get("count_bonus", 0)) == 0, "%s#%d加量盒需漂移%.2fm" % [key, i, drift])
			var points := room.spawn_points_in_box(center, p["box_size"], required, p["box_rotation"], spacing, recess)
			var finite := 0
			for point in points:
				if point.is_finite():
					finite += 1
			_check(finite == required, "%s#%d落地容量%d<需求%d（独立于安全队列）" % [key, i, finite, required])
			if key == "boss":
				if i == 1:
					_check(drift <= BOSS_LOCAL_SHIFT_LIMIT_M, "boss#1漂移%.3fm超过一格5m" % drift)
					_verify_boss_landing_policy(room, p, box, required, resolved)
				else:
					_check(drift <= 0.001, "boss#%d修复后必须保持原盒心，实测%.3fm" % [i, drift])
				_verify_boss_supported_domain(room, p, resolved, points, i)
			elif PINNED_DRIFT.has(key) and (PINNED_DRIFT[key] as Dictionary).has(i):
				_check(absf(drift - float(PINNED_DRIFT[key][i])) <= 0.01, "%s#%d已登记漂移变化：%.3fm" % [key, i, drift])
			else:
				_check(drift <= 0.001, "%s#%d未授权新增漂移%.3fm" % [key, i, drift])
			print("SPAWN_RAMP_CAPACITY room=%s box=%d required=%d finite=%d declared=%s landed=%s drift=%.3f" % [key, i, required, finite, center, resolved, drift])
	print("SPAWN_RAMP_LEGACY_DRIFT_EVIDENCE=" + JSON.stringify(LEGACY_DRIFT_EVIDENCE))
	print("SPAWN_RAMP_DRIFT_SNAPSHOT=" + JSON.stringify(drifted))

func _verify_boss_landing_policy(room: DungeonRoom3D, p: Dictionary, box: Dictionary, required: int, resolved: Vector2) -> void:
	var center: Vector2 = p["box_center"]
	var snapped := room.snap_box_center_to_tile(center, int(box.get("wall_recess_tiles", 1)))
	var half: Vector2 = (p["box_size"] as Vector2) * 0.5
	var angle := deg_to_rad(float(p["box_rotation"]))
	var clearance := room._spawn_clearance()
	var spacing := maxf(room.ENEMY_BODY_RADIUS_M * 2.0 + 0.1, float(box.get("min_spacing_m", 0.0)))
	var seed_value := room._box_pick_seed(snapped, half)
	var original := room._box_sample_points(snapped, half, cos(angle), sin(angle), clearance)
	var original_fits := room._fits_in_box(original, spacing, required, seed_value)
	var policy := room._resolve_box_pool(snapped, half, cos(angle), sin(angle), clearance, spacing, seed_value, required)
	_check((policy["center"] as Vector2).distance_to(resolved) <= 0.001, "boss#1公开落地结果与生产_resolve_box_pool策略不一致")
	var pool: Array[Vector3] = policy["pool"]
	_check(room._fits_in_box(pool, spacing, required, seed_value), "boss#1生产策略落入容量不足fallback，不得当作合法迁移")
	if center.distance_to(resolved) > 0.001:
		_check(not original_fits, "boss#1原盒足量却擅自移位")
		var nearby: Array = []
		for candidate: Vector3 in room._spawn_candidates:
			var anchor := Vector2(candidate.x, candidate.z)
			if anchor.distance_to(snapped) <= room.SPAWN_BOX_SHIFT_RADIUS_M:
				nearby.append({"anchor": anchor, "distance": anchor.distance_to(snapped)})
		nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
		var first_fit := Vector2.INF
		for index in mini(nearby.size(), room.SPAWN_BOX_SHIFT_TRIES):
			var anchor: Vector2 = nearby[index]["anchor"]
			var trial := room._box_sample_points(anchor, half, cos(angle), sin(angle), clearance)
			if room._fits_in_box(trial, spacing, required, seed_value):
				first_fit = anchor
				break
		_check(first_fit.is_finite() and first_fit.distance_to(resolved) <= 0.001, "boss#1不是生产有限搜索中的最近足量候选")
	print("SPAWN_RAMP_BOSS_POLICY original_fits=%s required=%d pool=%d shift_limit=5m landed=%s" % [original_fits, required, pool.size(), resolved])

func _verify_boss_supported_domain(room: DungeonRoom3D, p: Dictionary, resolved: Vector2, points: Array[Vector3], index: int) -> void:
	var half: Vector2 = (p["box_size"] as Vector2) * 0.5
	var angle := deg_to_rad(float(p["box_rotation"]))
	var radius := room._spawn_clearance()
	var pool := room._box_sample_points(resolved, half, cos(angle), sin(angle), radius)
	_check(not room._spawn_support_triangles.is_empty(), "boss#%d缺实际承重三角形，禁止仅按平面包围盒放行" % index)
	_check(not pool.is_empty(), "boss#%d落地盒域无合法候选" % index)
	for candidate: Vector3 in pool:
		_verify_boss_supported_point(room, candidate, resolved, half, angle, radius, index)
	for point: Vector3 in points:
		_check(point.is_finite(), "boss#%d容量点非有限" % index)
		if point.is_finite():
			_verify_boss_supported_point(room, room.to_local(point), resolved, half, angle, radius, index)
	print("SPAWN_RAMP_BOSS_SUPPORT box=%d candidates=%d points=%d footprint=full_triangles+physics supported_domain_checked=true" % [index, pool.size(), points.size()])

func _verify_boss_supported_point(room: DungeonRoom3D, local: Vector3, resolved: Vector2, half: Vector2, angle: float, radius: float, index: int) -> void:
	var offset := room._box_local_point(local, resolved, cos(angle), sin(angle))
	_check(absf(offset.x) <= half.x + 0.001 and absf(offset.y) <= half.y + 0.001, "boss#%d候选/容量点越出resolved授权盒域" % index)
	_check(room._spawn_floor_contains(local, radius) and room._spawn_obstacle_free(local), "boss#%d候选几何/障碍判定非法" % index)
	_check(room._spawn_surface_contains(local, radius), "boss#%d完整敌人足迹缺同标高承重" % index)
	_check(room._narrative_floor_supported(room.to_global(local)), "boss#%d物理射线未找到同层真实支撑" % index)

func _verify_box_domain(room: DungeonRoom3D, raw: Dictionary, entries: Array[Dictionary], required: int) -> void:
	var p := tower._box_placement_at([raw], 0)
	var box := _expected_box(raw)
	var landed := room.resolve_spawn_box_center_local(p["box_center"], p["box_size"], required, p["box_rotation"], float(box.get("min_spacing_m", 0.0)), int(box.get("wall_recess_tiles", 1)))
	var half: Vector2 = (p["box_size"] as Vector2) * 0.5
	var angle := deg_to_rad(float(p["box_rotation"]))
	for config in entries:
		var point: Vector3 = config.get("spawn_position", Vector3.INF)
		_check(point.is_finite(), "%s生产落点非有限" % room.room_id)
		if not point.is_finite():
			continue
		var local := room.to_local(point)
		var rel := room._box_local_point(local, landed, cos(angle), sin(angle))
		if str(config.get("boss_content_id", "")) == "boss_monitor002":
			# 生产契约明确只把Boss本体放回作者中心；随从仍必须在盒域内。
			var anchor := room.boss_spawn_position_world()
			_check(Vector2(point.x - anchor.x, point.z - anchor.z).length() <= 0.01, "%s首领未落作者指定锚点" % room.room_id)
		else:
			_check(absf(rel.x) <= half.x + 0.01 and absf(rel.y) <= half.y + 0.01, "%s生产点越出实际落地盒域" % room.room_id)
		_check(room.resolve_enemy_spawn_position(point).distance_to(point) < 0.01, "%s生产落点还需二次平移" % room.room_id)
		if config.has("spawn_safe_candidates"):
			var pool: Array = config["spawn_safe_candidates"]
			_check(not pool.is_empty(), "%s安全候选为空" % room.room_id)
			for candidate: Vector3 in pool:
				var offset := room._box_local_point(room.to_local(candidate), landed, cos(angle), sin(angle))
				_check(absf(offset.x) <= half.x + 0.01 and absf(offset.y) <= half.y + 0.01, "%s候选越授权盒域" % room.room_id)
			var selection := tower._select_box_spawn_position(room, config)
			if bool(selection.get("ok", false)):
				_check(pool.has(selection["position"]), "%s实际安全选点移出冻结域" % room.room_id)
				_check(room.is_safe_spawn_position_valid(selection["position"], tower.player.global_position, 6.0, []), "%s实际安全选点验证失败" % room.room_id)
			else:
				_check(bool(selection.get("retryable", false)), "%s盒域硬失败" % room.room_id)

# 独立预期只用于断言；绝不把这里归一的override喂回生产编译器。
func _expected_box(raw: Dictionary) -> Dictionary:
	var box := SpawnBoxCatalog.load_box(str(raw["box"]))
	if raw.has("spawn_overrides"):
		var spawns: Array[Dictionary] = []
		for entry: Dictionary in raw["spawn_overrides"]:
			var count: Variant = entry["count"]
			spawns.append({"type": entry["type"], "count_min": int(count.get("min", 0)) if count is Dictionary else int(count), "count_max": int(count.get("max", 0)) if count is Dictionary else int(count), "delay_sec": float(entry.get("delay_sec", 0.0))})
		box["spawns"] = spawns
	return box

func _design_bounds(box: Dictionary, bonus: int, multiplier: int = 1) -> Dictionary:
	var lo := 0
	var hi := 0
	var identities := 0
	var used := false
	for spawn: Dictionary in box.get("spawns", []):
		var a := int(spawn.get("count_min", 0))
		var b := int(spawn.get("count_max", a))
		if str(spawn["type"]) in ["elite", "boss"]:
			identities += b
		else:
			a *= multiplier
			b *= multiplier
			if not used and b > 0:
				a += bonus
				b += bonus
				used = true
		lo += a
		hi += b
	return {"lo": lo, "hi": hi, "id": identities}

func _id_realized(entries: Array[Dictionary]) -> int:
	var count := 0
	for entry in entries:
		if bool(entry.get("is_elite", false)) or str(entry.get("type", "")) in ["elite", "boss"] or str(entry.get("enemy_kind", "")) == "boss" or not str(entry.get("boss_content_id", "")).is_empty():
			count += 1
	return count

func _floor_level(room: DungeonRoom3D) -> int:
	return clampi(int(float(tower._record_index(room.room_id)) / maxf(1.0, float(tower._records.size() - 1)) * 3.0), 0, 3)

# 两端量通过继承正式编译器强制最小/最大抽数；身份工厂替身不影响正式场景验收。
func _verify_negative_bonus_only() -> void:
	var room := tower._room_by_id["room_07"] as DungeonRoom3D
	var probe := CompilerProbe.new()
	var raw: Dictionary = room.spawn_placements[0].duplicate(true)
	var normal: Array[Dictionary] = []
	probe._collect_box_stage_entries(room, [raw], 0, 1, 0, RandomNumberGenerator.new(), normal)
	_check(normal.size() == 4, "负向前提：继承正式编译正对照不是4只")
	_check(_id_realized(normal) == 0, "负向前提：本关强化小队不得含唯一精英身份")
	probe.drop_bonus = true
	var broken: Array[Dictionary] = []
	probe._collect_box_stage_entries(room, [raw], 0, 1, 0, RandomNumberGenerator.new(), broken)
	_check(int(probe._box_placement_at([raw], 0).get("box_count_bonus", -1)) != 2, "故障注入未生效")
	print("SPAWN_RAMP_NEGATIVE bonus_mapping_removed expected=4 actual=%d detected=%s" % [broken.size(), broken.size() != 4])
	_check(broken.size() == 4, "故障注入：缺bonus映射使生产编译少怪，预期退出1")
	probe.free()

func _verify_endpoints_and_negative_controls() -> void:
	var probe := CompilerProbe.new()
	for high in [false, true]:
		probe.high = high
		for key in BOX_ROOMS:
			var room := tower._room_by_id[key] as DungeonRoom3D
			for i in room.spawn_placements.size():
				var raw: Dictionary = room.spawn_placements[i]
				var bounds := _design_bounds(_expected_box(raw), int(raw.get("count_bonus", 0)), int(raw.get("count_multiplier", 1)))
				var entries: Array[Dictionary] = []
				probe._collect_box_stage_entries(room, room.spawn_placements, i, 1, 0, RandomNumberGenerator.new(), entries)
				_check(entries.size() == bounds["hi" if high else "lo"], "%s#%d生产端点编译数量不符 high=%s" % [key, i, high])
				_check(_id_realized(entries) == bounds["id"], "%s#%d生产端点身份数漂移" % [key, i])
				_verify_type_counts(entries, _expected_box(raw), int(raw.get("count_bonus", 0)), int(raw.get("count_multiplier", 1)), high, "%s#%d" % [key, i])
				print("SPAWN_RAMP_ENDPOINT room=%s box=%d high=%s expected=%d actual=%d identities=%d" % [key, i, high, bounds["hi" if high else "lo"], entries.size(), _id_realized(entries)])
				endpoint_boxes += 1
	var room := tower._room_by_id["room_07"] as DungeonRoom3D
	var raw: Dictionary = room.spawn_placements[0].duplicate(true)
	var bad := probe._box_placement_at([raw], 0)
	_check(int(bad.get("box_count_bonus", -1)) == 2, "端点替身继承生产映射正对照失败")
	probe.drop_bonus = true
	bad = probe._box_placement_at([raw], 0)
	_check(int(bad.get("box_count_bonus", -1)) != 2, "负向对照未识别缺bonus映射")
	var broken: Array[Dictionary] = []
	probe._collect_box_stage_entries(room, [raw], 0, 1, 0, RandomNumberGenerator.new(), broken)
	_check(broken.size() != 4, "负向对照：生产编译丢bonus仍被误判通过")
	print("SPAWN_RAMP_NEGATIVE bonus_mapping_removed expected=4 actual=%d detected=%s" % [broken.size(), broken.size() != 4])
	if "--negative-bonus" in OS.get_cmdline_user_args():
		_check(broken.size() == 4, "故障注入：缺bonus映射使生产编译少怪，预期退出1")
	probe.drop_bonus = false
	# 用同一正式编译函数确认身份不吃倍率和增量，普通两条都吃倍率，仅首条吃bonus。
	for box_id in ["box_center_elite", "box_boss_arena", "box_room_spread"]:
		var placement := {"box": box_id, "center_m": raw["center_m"], "count_bonus": 2, "count_multiplier": 2, "size_m": [20.0, 20.0]}
		var bounds := _design_bounds(SpawnBoxCatalog.load_box(box_id), 2, 2)
		var entries: Array[Dictionary] = []
		probe._collect_box_stage_entries(room, [placement], 0, 1, 0, RandomNumberGenerator.new(), entries)
		_check(entries.size() == bounds["hi"] and _id_realized(entries) == bounds["id"], "%s身份被倍率/bonus污染或普通增量失效" % box_id)
		_verify_type_counts(entries, SpawnBoxCatalog.load_box(box_id), 2, 2, true, box_id)
		probe.drop_multiplier = true
		var missing: Array[Dictionary] = []
		probe._collect_box_stage_entries(room, [placement], 0, 1, 0, RandomNumberGenerator.new(), missing)
		_check(missing.size() != entries.size(), "%s负向对照未识别缺倍率映射" % box_id)
		probe.drop_multiplier = false
	probe.free()

func _verify_type_counts(entries: Array[Dictionary], box: Dictionary, bonus: int, multiplier: int, high: bool, label: String) -> void:
	var expected := {}
	var used := false
	for spawn: Dictionary in box.get("spawns", []):
		var type_id := str(spawn["type"])
		var count := int(spawn["count_max" if high else "count_min"])
		if type_id not in ["elite", "boss"] and count > 0:
			count *= multiplier
			if not used:
				count += bonus
				used = true
		expected[type_id] = int(expected.get(type_id, 0)) + count
	var actual := {}
	for entry in entries:
		var type_id := str(entry.get("type", ""))
		actual[type_id] = int(actual.get(type_id, 0)) + 1
	_check(actual == expected, "%s逐怪种编译%s!=%s；身份或首条增量分配错误" % [label, actual, expected])

func _verify_trigger_encounters() -> void:
	for key in TRIGGER_EXPECTED:
		var room := tower._room_by_id[key] as DungeonRoom3D
		var expected: Dictionary = TRIGGER_EXPECTED[key]
		var e := room.encounter
		_check(room.spawn_placements.is_empty(), "%s触发房残留盒子" % key)
		_verify_trigger_shape(key, room, e.get("trigger", {}), expected)
		var compiled := tower._build_room_encounter_config(room)
		_check(float(e.get("duration_sec", -1)) == 0.0 and compiled.get("duration_sec", -1) == 0.0, "%s无截止时长透传失败" % key)
		for field in ["completion", "stage_advance"]:
			_check(e.get(field) == "clear" and compiled.get(field) == "clear", "%s:%s不是clear" % [key, field])
		_check(bool(e.get("seal_room", false)) and bool(e.get("light_on_finish", false)) and bool(e.get("hunt_player", false)), "%s封门/开灯/猎杀开关漂移" % key)
		_check(bool(e.get("hud_countdown", false)) and bool(compiled.get("hud_countdown", false)), "%s准备HUD开关未透传" % key)
		var preparation := 2.0 if key in ["room_04", "room_10"] else 3.0
		if key == "room_03":
			preparation = 60.0  # 正式节奏：完整准备倒计时结束才允许首波派发。
		var freeze := 1.0 if key == "room_03" else 0.0
		_check(compiled.get("preparation_sec") == preparation and compiled.get("freeze_player_sec") == freeze, "%s准备/冻结未透传" % key)
		_check(compiled.get("remote_spawn_policy") == "opposite_entry" and str(e.get("spawn_origin_port_id", "")).is_empty(), "%s远端必须按实际入口决定" % key)
		for field in ["alert_style", "alert_text", "alert_beep_interval_sec", "alert_pulse"]:
			_check(compiled.has(field) and compiled[field] == e[field], "%s:%s告警键未透传" % [key, field])
		_check(compiled.get("max_alive") == expected["cap"] and compiled.get("intermission_sec") == expected["intermission"], "%s容量/间歇透传失败" % key)
		_check(compiled.get("min_player_distance_m") == 6.0, "%s最小距离透传失败" % key)
		var stages: Array = compiled.get("stages", [])
		_check(stages.size() == (expected["waves"] as Array).size(), "%s编译波数漂移" % key)
		for i in mini(stages.size(), (expected["waves"] as Array).size()):
			var actual := {}
			for monster: Dictionary in stages[i]["monsters"]:
				actual[monster["type"]] = int(actual.get(monster["type"], 0)) + int(monster["count"])
			_check(actual == expected["waves"][i], "%s波%d生产编成%s!=%s" % [key, i, actual, expected["waves"][i]])
		var start_delay := 0.0 if key == "room_03" else preparation
		_check(float(stages[0].get("at_sec", -1)) == start_delay, "%s首波延时应为%.1f秒" % [key, start_delay])
		if key == "room_03":
			_check(stages[1]["monsters"][0].get("min_player_distance_m") == 8.0, "第二批首胖8米丢失")

func _verify_legacy_trigger_compatibility() -> void:
	var room := tower._room_by_id["room_03"] as DungeonRoom3D
	var saved := room.encounter
	room.encounter = {"duration_sec": 60.0, "start_delay_sec": 1.0, "stage_advance": "time", "hunt_player": true, "hud_countdown": true, "stages": [{"monsters": [{"type": "melee_chaser", "count": 5}, {"type": "strong_random", "count": 2}]}]}
	var config := tower._build_room_encounter_config(room)
	room.encounter = saved
	_check(config["duration_sec"] == 60.0 and config["completion"] == "timer" and config["stage_advance"] == "time", "旧计时配置兼容失效")
	_check(config["hud_countdown"] and config["hunt_player"] and config["max_alive"] == 2147483647 and config["intermission_sec"] == 0.0, "旧计时缺省/表现兼容失效")
	var amount := 0
	for monster: Dictionary in config["stages"][0]["monsters"]:
		amount += int(monster["count"])
		_check(monster["type"] != "strong_random", "旧strong_random未解析具体变种")
	_check(amount == 7, "旧编成解析丢怪")
	print("SPAWN_RAMP_LEGACY_COMPAT_DONE")

func _verify_trigger_shape(key: String, room: DungeonRoom3D, trigger: Dictionary, expected: Dictionary) -> void:
	var shape := str(trigger.get("shape", "circle"))
	_check(shape == expected["shape"], "%s触发形状漂移" % key)
	_check(trigger.get("port_ids", []) == ["A", "B"], "%s必须按运行时A/B门位触发" % key)
	_check(trigger.get("inset_m") == 2.0 and trigger.get("depth_m") == 3.0, "%s入口条带尺寸漂移" % key)
	for port_id in ["A", "B"]:
		var port := room.get_connection_port_by_id(port_id)
		_check(not port.is_empty() and not str(port.get("target", "")).is_empty(), "%s缺有效端口%s" % [key, port_id])
		var position := room._placement_vec2(port.get("position_m", []))
		var outward := room._placement_vec2(port.get("outward", []))
		var local := position - outward * 3.0
		var match_result := room.match_door_entry_trigger(trigger, room.to_global(Vector3(local.x, 0.5, local.y)))
		_check(str(match_result.get("port_id", "")) == port_id, "%s端口%s内侧触发失效" % [key, port_id])

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
