extends Node3D
## 正式生产接线与逐发命中；故障替身仅用于独立拒绝/回滚路径。
const FX := "VFX-FAT-ENTRY-BREACH-3D"
const SOURCE := "res://art_source/design/whitebox/tower_zones/expedition_01/v001/data/"
var checks := 0
var failures: Array[String] = []
var tower: TowerDescent3D
var projectiles: Array[Projectile3D] = []

class FaultRoom extends DungeonRoom3D:
	var retry := false
	func _ready() -> void:
		pass
	func is_streamed() -> bool:
		return true
	func _prepare_safe_spawn_selection() -> void:
		_spawn_candidates.assign([Vector3.ZERO, Vector3(8, 0, 0)])
	func _safe_spawn_geometry_valid(_point: Vector3) -> bool:
		return not retry
	func _spawn_floor_contains(_point: Vector3, _radius: float) -> bool:
		return true
	func get_encounter_spawn_candidates(_trigger_port: String, _origin_port := "", _policy := "") -> Array[Vector3]:
		return []
	func choose_safe_spawn_position(_player: Vector3 = Vector3.INF, _distance: float = 0.0, occupied: Array[Vector3] = [], _candidates: Variant = null, _prepared := false) -> Dictionary:
		return {"ok": false, "retryable": true} if retry else {"ok": true, "position": Vector3(occupied.size() * 8, 0, 0)}

class FaultDungeon extends Dungeon3D:
	var fault := "config"
	var fixture_root: Node3D
	func _make_box_enemy(_type: String, _floor: int, _level: int, _room: DungeonRoom3D, _id := "") -> Dictionary:
		return {} if fault == "config" else {"enemy_type": "melee_chaser"}
	func _spawn_enemy_batch(room: DungeonRoom3D, _configs: Array[Dictionary], _additive: bool, _reserved := false, _positions: Array = [], _prepared := false, _roaming: Dictionary = {}) -> int:
		if fault == "batch":
			return -1
		var enemy := (load("res://scenes/enemies/fat_zombie03.tscn") as PackedScene).instantiate() as Enemy3D
		fixture_root.add_child(enemy)
		enemy.global_position = room.global_position
		_enemy_nodes_by_room[room.room_id] = [enemy]
		_alive_by_room[room.room_id] = 1
		return 1

class NoVisualSpaceHost extends EncounterEventHost3D:
	func _choose_spawn_vfx_position(_room: DungeonRoom3D, _player: Vector3, _distance: float, _occupied: Array[Vector3], _candidates: Variant) -> Dictionary:
		return {"ok":false}
	func _choose_spawn_vfx_paths(_room: DungeonRoom3D, _player: Vector3, _distance: float, _occupied: Array[Vector3], _candidates: Array[Vector3]) -> Dictionary:
		return {"ok":false}
	func _refined_spawn_vfx_candidates(_room: DungeonRoom3D, _spec: Dictionary, _original: Variant) -> Array[Vector3]:
		return []
	func _play_spawn_vfx(_asset: StringName, _room: DungeonRoom3D, _enemy: Enemy3D) -> void:
		pass

class MissingPool extends Node:
	var unavailable := true
	func has_effect(_asset_id: StringName) -> bool:
		return not unavailable
	func acquire(_asset_id: StringName, _point: Vector3, _color: Color, _size: float, _context: Dictionary) -> VfxEffectBase3D:
		return null

class MissingVfxHost extends EncounterEventHost3D:
	var pool: Node
	func _spawn_vfx_pool() -> Node:
		return pool

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func config(spec: Dictionary) -> Dictionary:
	return {"schema_version": 1, "event_id": "generic_spawn", "room_id": "generic_room", "duration_sec": 10.0, "completion": "clear", "stages": [{"at_sec": 0.0, "monsters": [spec]}]}

func _ready() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("2026-11-16_exp01_combat/integration/"):
		get_tree().quit(2)
		return
	get_tree().current_scene = self
	await get_tree().process_frame
	validation()
	await fault_paths()
	await production()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "completed": true}
	var file := FileAccess.open(OS.get_environment("COMBAT_INTEGRATION_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SPAWN_VFX_COMBAT_INTEGRATION ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func validation() -> void:
	var spec := {"type": "fat_zombie03_strong", "count": 2, "spawn_vfx_asset_id": FX}
	check(EncounterEventDirector3D.validate_config(config(spec)).ok, "通用monster合法白名单字段")
	var absent := spec.duplicate(true)
	absent.erase("spawn_vfx_asset_id")
	check(EncounterEventDirector3D.validate_config(config(absent)).ok, "缺省字段保持旧行为")
	var room := {"encounter": {"trigger": {"radius_m": 4.0}, "duration_sec": 10.0, "completion": "clear", "stages": [{"monsters": [spec]}]}}
	check(LevelPlanValidator._validate_encounter(room, "generic_room", 0).is_empty(), "源计划接受合法表现字段")
	for bad in ["", "VFX-UNKNOWN-3D", "res://bad.tscn", 1, true, null, [], {}]:
		var rejected := spec.duplicate(true)
		rejected["spawn_vfx_asset_id"] = bad
		check(not EncounterEventDirector3D.validate_config(config(rejected)).ok, "Director严格拒绝非法AssetID类型/值：" + str(bad))
		var bad_room := room.duplicate(true)
		bad_room.encounter.stages[0].monsters = [rejected]
		check(not LevelPlanValidator._validate_encounter(bad_room, "generic_room", 0).is_empty(), "源计划拒绝非法AssetID：" + str(bad))
		var convenience := config(rejected)
		convenience.erase("stages")
		convenience["monsters"] = [rejected]
		check(not EncounterEventDirector3D.validate_config(convenience).ok, "简写编译不能绕过白名单")
	var unknown := spec.duplicate(true)
	unknown["spawn_vfx_asset_typo"] = FX
	check(not EncounterEventDirector3D.validate_config(config(unknown)).ok, "拒绝拼错字段而非吞掉")
	var bad_room := room.duplicate(true)
	bad_room.encounter.stages[0].monsters = [unknown]
	check(not LevelPlanValidator._validate_encounter(bad_room, "generic_room", 0).is_empty(), "源计划也拒绝拼错字段")
	for interval in [0.0, 0.5]:
		var convenience := config(spec)
		convenience.erase("stages")
		convenience["monsters"] = [spec]
		convenience["interval_sec"] = interval
		var result := EncounterEventDirector3D.validate_config(convenience)
		check(result.ok, "简写合法配置通过")
		for stage: Dictionary in result.config.stages:
			check(stage.monsters[0].spawn_vfx_asset_id == FX, "简写/逐只排程保留AssetID")

func fault_paths() -> void:
	var dungeon := FaultDungeon.new()
	dungeon.fixture_root = self
	dungeon.visual_theme = DungeonTheme3D.new()
	var room := FaultRoom.new()
	add_child(room)
	room.room_id = "generic_room"
	dungeon._room_by_id[room.room_id] = room
	var host := EncounterEventHost3D.new(dungeon)
	var spec := {"type": "fat_zombie03_strong", "count": 2, "spawn_vfx_asset_id": FX}
	var before := VfxPool.active_count(FX)
	var rejected := spec.duplicate(true)
	rejected.spawn_vfx_asset_id = "invalid"
	check(not host.encounter_event_spawn("fault", room.room_id, rejected, 2).ok, "Host直调也拒绝非法AssetID")
	check(not host.encounter_event_spawn("fault", room.room_id, spec, 0).ok, "零数量拒绝不空播")
	room.retry = true
	spec.remote_spawn_policy = "opposite_entry"
	var retry := host.encounter_event_spawn("fault", room.room_id, spec, 2)
	check(retry.ok and retry.spawned == 0 and retry.retryable, "无合法落点retryable0")
	room.retry = false
	spec.erase("remote_spawn_policy")
	check(not host.encounter_event_spawn("fault", room.room_id, spec, 2).ok, "配置生成失败")
	dungeon.fault = "batch"
	check(not host.encounter_event_spawn("fault", room.room_id, spec, 2).ok, "实体批次失败")
	dungeon.fault = "partial"
	var rolled_back := host.encounter_event_spawn("fault", room.room_id, spec, 2)
	check(not rolled_back.ok and rolled_back.reason == "spawn_partial", "部分实体生成触发整批回滚")
	check(not dungeon._enemy_nodes_by_room.has(room.room_id) and not dungeon._alive_by_room.has(room.room_id), "回滚恢复原实体集合和存活账")
	check(VfxPool.active_count(FX) == before, "拒绝/失败/retryable0/rollback全部不空播")
	var missing_host := MissingVfxHost.new(dungeon)
	var missing_pool := MissingPool.new()
	missing_host.pool = missing_pool
	for missing in [true, false]:
		missing_pool.unavailable = missing
		var delivered := missing_host.encounter_event_spawn("missing", room.room_id, spec, 1)
		check(delivered.ok and delivered.spawned == 1 and dungeon._alive_by_room[room.room_id] == 1, "资源缺失/借出失败仅warning，成功实体不回滚")
		for enemy: Enemy3D in dungeon._enemy_nodes_by_room[room.room_id]:
			enemy.queue_free()
		dungeon._enemy_nodes_by_room.erase(room.room_id)
		dungeon._alive_by_room.erase(room.room_id)
	var no_space := NoVisualSpaceHost.new(dungeon)
	var fixed := no_space.encounter_event_spawn("fixed_without_visual_space", room.room_id, spec, 1)
	check(fixed.ok and fixed.spawned == 1, "视觉无净空不能无限扣住固定SF")
	for enemy: Enemy3D in dungeon._enemy_nodes_by_room.get(room.room_id, []):
		enemy.queue_free()
	missing_pool.free()
	room.free()
	dungeon.free()
	await get_tree().process_frame

func actors(room: DungeonRoom3D) -> Array:
	return tower._enemy_nodes_by_room.get(room.room_id, []) as Array

func freeze_actors(room: DungeonRoom3D) -> void:
	for enemy: Enemy3D in actors(room):
		enemy.set_process(false)
		enemy.set_physics_process(false)

func discard(room: DungeonRoom3D) -> void:
	for enemy: Enemy3D in actors(room):
		MonsterAIManager.unregister_enemy(enemy)
		enemy.queue_free()
	tower._enemy_nodes_by_room[room.room_id] = []
	tower._alive_by_room[room.room_id] = 0

func production() -> void:
	tower = (load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_loading_active:
			break
		await get_tree().process_frame
	check(not tower._expedition_bootstrap_failed and tower._main_story_gameplay_started and tower._room_by_id.has("room_10"), "正式关卡生产初始化")
	if not tower._room_by_id.has("room_10"):
		return
	tower.set_process(false)
	tower.set_physics_process(false)
	tower.player.set_physics_process(false)
	var room := tower._room_by_id["room_03"] as DungeonRoom3D
	room.ensure_shell_built()
	room.ensure_detail_built()
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	tower._current_room_id = room.room_id
	tower.player.global_position = room.global_position + Vector3(0, 0.05, 0)
	var floor_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "floors/floor_00.json"))
	var source_encounter: Dictionary = {}
	for row: Dictionary in floor_data.rooms:
		if str(row.key).ends_with("room_03"):
			source_encounter = row.encounter
	check(not source_encounter.is_empty() and room.encounter == source_encounter, "权威源JSON经正式生成器到运行房间字段完全一致")
	var compiled := tower._build_room_encounter_config(room)
	compiled["trigger_port_id"] = str(room.encounter.trigger.port_ids[0])
	check(compiled.duration_sec == 40.0 and compiled.stages.size() == 4, "正式编译40秒和独立普通末模板")
	check(compiled.stages[2].monsters[0].spawn_vfx_asset_id == FX, "源字段到Dungeon正式编译保留")
	var director := tower._encounter_event_director
	var started := tower.start_encounter_event(compiled)
	check(started.ok, "生产Director接受正式编译")
	if not started.ok:
		return
	var id: String = started.instance_id
	VfxPool.clear_kind(FX)
	director.tick(1.0)
	check(director.get_snapshot(id).spawned == 0, "冻结时不出怪不播特效")
	director.tick(2.0)
	print("SPAWN_VFX_ROOM streamed=", room.is_streamed(), " current=", tower._current_room_id, " first_batch_spawned=", director.get_snapshot(id).spawned)
	for wave in 2:
		freeze_actors(room)
		check(not actors(room).is_empty() and VfxPool.active_count(FX) == 0, "前两波真实出怪且不播第三波效果")
		discard(room)
		director.tick(0.01)
	freeze_actors(room)
	check(VfxPool.active_count(FX) == 1, "第三波成功实到只借出一次真实VFX")
	var strong: Enemy3D
	for enemy: Enemy3D in actors(room):
		if enemy.enemy_kind == "fat_zombie03_strong":
			strong = enemy
	check(strong != null and strong.max_hp == 792 and strong.current_hp == 792, "生产强化胖子792HP")
	var effects: Array = VfxPool._active.get(FX, [])
	check(effects.size() == 1 and effects[0].scene_file_path.ends_with("vfx_fat_entry_breach_root_top3d.tscn"), "池实际实例来自独立正式Prefab")
	if strong != null and effects.size() == 1:
		var effect := effects[0] as VfxEffectBase3D
		effect.set_process(false)
		var snapshot: Dictionary = effect.call("get_presentation_snapshot")
		check(effect.global_position.is_equal_approx(strong.global_position), "VFX使用实际交付怪物位置")
		check(snapshot.seed == strong.get_persistent_id().hash() and is_equal_approx(snapshot.floor_y, strong.global_position.y), "context稳定持久ID/hash和真实脚底高度")
		check(effect.effect_color == Color.WHITE and effect.effect_size == 1.0, "生产调用白色原尺寸")
		var toward := tower.player.global_position - strong.global_position
		toward.y = 0.0
		check((-effect.global_basis.z).dot(toward.normalized()) > 0.999, "forward指向实际玩家")
		check(strong.enemy_data.spawn_vfx_asset_id == FX and strong.enemy_data.death_explosion.warning_sec == 1.0, "实际怪物保留表现字段与1秒预警")
		var radius := 0.0
		for bounds: AABB in snapshot.bounds:
			for corner in 8:
				radius = maxf(radius, bounds.get_endpoint(corner).length())
		check(radius <= EncounterEventHost3D.SPAWN_VFX_ENVELOPE_M, "实际视觉家具任意姿态包络不超过Host契约")
		check(snapshot.landing_distance_m >= EncounterEventHost3D.SPAWN_VFX_MIN_DISTANCE_M, "正式现场拒绝distance0，保证显著水平飞出")
		var point := room.to_local(strong.global_position)
		check(room._spawn_floor_contains(point, float(snapshot.landing_distance_m) + radius), "完整径向家具包络不跨房间边界/凹角")
		for time in [0.0, 0.4, 0.8, 1.2, 1.8, 2.2]:
			effect.call("_on_tick", time, effect.lifetime)
			var visual: Dictionary = effect.call("get_presentation_snapshot")
			for index in visual.transforms.size():
				for corner in 8:
					var world: Vector3 = visual.transforms[index] * (visual.bounds[index] as AABB).get_endpoint(corner)
					var local := room.to_local(world)
					check(room._spawn_floor_contains(Vector3(local.x, point.y, local.z), 0.001), "实际飞出家具角点始终位于合法房间内")
		var saved := director.export_snapshot()
		check(director.import_snapshot(JSON.parse_string(JSON.stringify(saved))).ok, "Director快照JSON往返")
		check(director.get_snapshot(id).config.stages[2].monsters[0].spawn_vfx_asset_id == FX, "Director规范化快照保留AssetID")
		director.tick(0.01)
		check(VfxPool.active_count(FX) == 1, "事件快照恢复既有实体不补播")
		check(director.get_snapshot(id).stage_states[2].pending[0].spawn_vfx_asset_id == FX, "恢复pending仍保留表现字段")
		tower._capture_room_runtime_state(room.room_id)
		tower._hibernate_room_entities(room.room_id)
		await get_tree().process_frame
		tower._restore_room_runtime_state(room.room_id)
		freeze_actors(room)
		check(VfxPool.active_count(FX) == 1, "真实房间流送恢复已有实体不补播")
	for wave in 3:
		discard(room)
		director.tick(0.01)
		freeze_actors(room)
		check(VfxPool.active_count(FX) == 1, "独立末模板循环不重复入场效果")
		for enemy: Enemy3D in actors(room):
			check(enemy.enemy_kind != "fat_zombie03_strong", "普通末模板不含强化胖子")
	director.tick(40.0)
	discard(room)
	director.tick(0.01)
	var before_batch := VfxPool.active_count(FX)
	var batch := tower._encounter_event_host.encounter_event_spawn("generic_batch", room.room_id, {"type": "fat_zombie03_strong", "spawn_vfx_asset_id": FX, "_persistent_id_base": "generic_batch:0"}, 2)
	check(batch.ok and batch.spawned == 2 and VfxPool.active_count(FX) == before_batch + 2, "同批两只实际实体全量交付后逐只借出效果")
	freeze_actors(room)
	discard(room)
	await damage_hits(room)
	tower.queue_free()
	await get_tree().process_frame

func damage_hits(room: DungeonRoom3D) -> void:
	var tree := BlueprintRegistry.build_weapon_tree("bp_pistol", "mod_bullet_standard")
	add_child(tree)
	var weapon := WeaponModel3D.new()
	add_child(weapon)
	check(weapon.configure_from_tree(tree), "新建Blueprint标准弹豌豆手枪接生产WeaponModel")
	weapon._critical_chance = 0.0
	weapon.set_damage_multiplier(1.0)
	check(weapon.damage == 33 and tree.get_computed_stats().damage == 25 and tree.get_computed_stats().bullet_damage == 8, "生产伤害计算25+8=33无配件无命运")
	weapon.projectile_spawned.connect(func(projectile: Projectile3D): projectiles.append(projectile))
	for entry in [["melee_chaser", 99, 3], ["fat_zombie03", 198, 6], ["fat_zombie03_strong", 792, 24]]:
		var data := tower._make_box_enemy(entry[0], 1, 0, room)
		var enemy := (load("res://scenes/enemies/fat_zombie03.tscn") as PackedScene).instantiate() as Enemy3D
		add_child(enemy)
		enemy.configure_from_enemy_data(data)
		enemy.global_position = room.global_position
		enemy.set_process(false)
		enemy.set_physics_process(false)
		check(enemy.current_hp == entry[1], "生产MonsterInjector→实际Enemy HP：" + str(entry[0]))
		var hits := 0
		while enemy.current_hp > 0 and hits < 20:
			if weapon.is_reloading():
				weapon._process(weapon.reload_time + 0.01)
			if weapon.current_ammo == 0:
				check(weapon.request_reload(), "弹匣空时走生产换弹")
				weapon._process(weapon.reload_time + 0.01)
			weapon._cooldown = 0.0
			projectiles.clear()
			check(weapon._fire_now(Vector3.FORWARD, null, 1.0) and projectiles.size() == 1, "生产手枪实际发出单颗标准弹")
			if projectiles.size() != 1:
				break
			var projectile := projectiles[0]
			check(projectile.damage == 33 and not projectile.critical, "实际生产弹体伤害33且暴击关闭")
			var before := enemy.current_hp
			projectile._hit_target(enemy)
			hits += 1
			check(enemy.current_hp == maxi(0, before - 33), "实际take_projectile_damage逐发扣血")
			print("SPAWN_VFX_DAMAGE type=%s hit=%d projectile_damage=%d hp=%d->%d" % [entry[0], hits, projectile.damage, before, enemy.current_hp])
		check(hits == entry[2] and enemy.current_hp == 0, "%s实际命中%d枪到HP0" % [entry[0], entry[2]])
		if entry[0] != "melee_chaser":
			check(enemy.ai_state == "death_warning" and is_equal_approx(enemy.export_runtime_state().death_warning_remaining_sec, 1.0), "生产普通/强化胖子致死进入1秒预警")
		enemy.queue_free()
	weapon.queue_free()
	tree.queue_free()
