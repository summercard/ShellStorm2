extends Node3D
const FX := "VFX-FAT-ENTRY-BREACH-3D"
var report := {"rows": [], "failures": [], "completed": false}
var tower: TowerDescent3D
var render := false

func _trace_bootstrap_node(node: Node) -> void:
	if node.name in ["Player3D", "WeaponModel3D", "ExpeditionLevel01_3D", "HatBunnyEars", "EarSocketL"]:
		print("VFX_CLEARANCE_BOOT_NODE ", node.name)

func check(ok: bool, message: String) -> void:
	if not ok:
		report.failures.append(message)
		push_error(message)

func _ready() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("2026-11-16_exp01_combat/last_clearance/"):
		get_tree().quit(2)
		return
	get_tree().current_scene = self
	get_tree().node_added.connect(_trace_bootstrap_node)
	render = DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus" and RenderingServer.get_current_rendering_driver_name() == "vulkan"
	report["renderer"] = {"method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name()}
	var seeds: Array = [77001199, 2026]
	if not OS.get_environment("VFX_CLEARANCE_SEED").is_empty():
		seeds = [int(OS.get_environment("VFX_CLEARANCE_SEED"))]
	for seed_value in seeds:
		tower = (load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene).instantiate() as TowerDescent3D
		tower.test_mode = true
		tower.run_seed_override = seed_value
		print("VFX_CLEARANCE_PHASE add_tower ", seed_value)
		add_child(tower)
		print("VFX_CLEARANCE_PHASE added_tower ", seed_value)
		var deadline := Time.get_ticks_msec() + 150000
		while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
			if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_loading_active:
				break
			await get_tree().process_frame
		print("VFX_CLEARANCE_PHASE bootstrap ", tower._main_story_gameplay_started, " rooms=", tower._room_by_id.size())
		if tower._expedition_bootstrap_failed or not tower._main_story_gameplay_started:
			check(false, "正式关卡初始化失败")
			break
		tower.set_process(false)
		tower.set_physics_process(false)
		tower.player.set_process(false)
		tower.player.set_physics_process(false)
		for room_id in ["room_03", "room_04", "room_06", "room_09", "room_10"]:
			var room := tower._room_by_id[room_id] as DungeonRoom3D
			print("VFX_CLEARANCE_PHASE room ", room_id, " ", seed_value)
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			print("VFX_CLEARANCE_PHASE room_active ", room_id)
			var stage: Node = tower._floor_stages.get(tower._room_floor_index.get(room_id, 0))
			if stage != null:
				stage.process_mode = Node.PROCESS_MODE_INHERIT
				stage.call("set_render_state", true, true)
			tower._current_room_id = room_id
			tower.player.global_position = room.global_position + Vector3(0, 0.05, 0)
			var port_id := str(room.encounter.trigger.port_ids[0])
			print("VFX_CLEARANCE_PHASE candidates_begin ", room_id, " cached=", room._spawn_candidates.size(), " triangles=", room._spawn_support_triangles.size(), " blockers=", room._spawn_blockers.size())
			var candidates := room.get_encounter_spawn_candidates(port_id, "", "opposite_entry")
			print("VFX_CLEARANCE_PHASE candidates_done ", room_id, " count=", candidates.size())
			var host := tower._encounter_event_host
			var ranked: Array = []
			var candidate_index := 0
			for point in candidates:
				if candidate_index % 100 == 0:
					print("VFX_CLEARANCE_PHASE scan ", room_id, " ", candidate_index)
				candidate_index += 1
				if room._safe_spawn_geometry_valid(point) and room._safe_spawn_distances_valid(point, tower.player.global_position, 6.0, []):
					ranked.append({"local": str(room.to_local(point)), "distance": host._spawn_vfx_landing_distance(room, point)})
			ranked.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance > b.distance)
			var row := {"seed": seed_value, "room": room_id, "candidate_count": candidates.size(), "legal_count": ranked.size(), "blockers": room._spawn_blockers.size(), "best": ranked.slice(0, 8)}
			if seed_value == 77001199 and room_id == "room_03":
				var old := room.to_global(Vector3(1.3703308, 0, 7.3529434))
				row["old_point_distance"] = host._spawn_vfx_landing_distance(room, old)
				print("VFX_CLEARANCE_PHASE negative_begin ")
				var rejected := host._choose_spawn_vfx_position(room, tower.player.global_position, 6.0, [], [old])
				print("VFX_CLEARANCE_PHASE negative_done ")
				check(not rejected.ok, "负测：旧production零距离点不能再交付VFX怪")
			var compiled := tower._build_room_encounter_config(room)
			compiled["trigger_port_id"] = port_id
			print("VFX_CLEARANCE_PHASE ranked ", room_id, " legal=", ranked.size())
			var started := tower.start_encounter_event(compiled)
			print("VFX_CLEARANCE_PHASE event_started ", room_id)
			check(started.ok, "正式遭遇启动：%s/%d" % [room_id, seed_value])
			if not started.ok:
				continue
			VfxPool.clear_kind(FX)
			var director := tower._encounter_event_director
			director.tick(1.0)
			director.tick(2.0)
			# cap小于模板数量时一波分多批；必须派完并清完前两阶段，不能两次discard冒充两波。
			for attempt in 20:
				var state := director.get_snapshot(str(started.instance_id))
				if state.stage_states[2].started:
					break
				discard(room)
				director.tick(0.01)
			print("VFX_CLEARANCE_PHASE waves_delivered ", room_id)
			var strong: Enemy3D
			for enemy: Enemy3D in tower._enemy_nodes_by_room.get(room_id, []):
				enemy.set_process(false)
				enemy.set_physics_process(false)
				if enemy.enemy_kind == "fat_zombie03_strong":
					strong = enemy
			var effects: Array = VfxPool._active.get(FX, [])
			print("VFX_CLEARANCE_DELIVERY strong=",strong != null," effects=",effects.size()," alive=",tower._enemy_nodes_by_room.get(room_id,[]).size())
			check(strong != null and effects.size() == 1, "第三波SF和真实效果均实到：%s/%d" % [room_id, seed_value])
			if strong != null and effects.size() == 1:
				var effect := effects[0] as Node3D
				effect.set_process(false)
				var snapshot: Dictionary = effect.call("get_presentation_snapshot")
				row["selected_local"] = str(room.to_local(strong.global_position))
				row["landing_distance_m"] = snapshot.landing_distance_m
				row["layout"] = snapshot.layout
				row["presentation_enemy_distance_m"] = effect.global_position.distance_to(strong.global_position)
				check(row.presentation_enemy_distance_m < 0.001, "表现爆心必须与实际SF一致，不用异地表演冒充")
				row["actual_circle_clearance_m"] = host._spawn_vfx_landing_distance(room,strong.global_position)
				row["refined_candidate_count"] = host._refined_spawn_vfx_candidates(room,{"trigger_port_id":port_id,"remote_spawn_policy":"opposite_entry"},candidates).size()
				check(snapshot.landing_distance_m >= EncounterEventHost3D.SPAWN_VFX_MIN_DISTANCE_M or snapshot.layout == "safe_fan", "不足整圆净空必须使用已校验逐家具轨迹")
				check(strong.current_hp == 792, "空间修复不改强化HP")
				check(room._safe_spawn_distances_valid(strong.global_position, tower.player.global_position, 6.0, []), "实际怪位满足玩家6m")
				var allowed := host._refined_spawn_vfx_candidates(room, {"trigger_port_id":port_id,"remote_spawn_policy":"opposite_entry"}, candidates)
				check(allowed.any(func(p: Vector3): return p.is_equal_approx(strong.global_position)), "实际怪位仍在反入口候选半区")
				var failed_geometry := false
				var violations: Array = []
				var initial: Array[Vector3] = []
				var initial_bounds: Array[AABB] = []
				var minimum_travel := INF
				for frame in 221:
					if frame % 30 == 0:
						print("VFX_CLEARANCE_PHASE geometry ", room_id, " frame=", frame)
					var elapsed := frame / 60.0
					effect.set("_elapsed", elapsed)
					effect.call("_on_tick", elapsed, 3.65)
					snapshot = effect.call("get_presentation_snapshot")
					for index in snapshot.transforms.size():
						var transform: Transform3D = room.global_transform.affine_inverse() * snapshot.transforms[index]
						var bounds: AABB = snapshot.bounds[index]
						if frame == 0:
							initial.append(transform.origin)
							initial_bounds.append(transform * bounds)
						if frame == 150:
							minimum_travel = minf(minimum_travel, Vector2(transform.origin.x - initial[index].x, transform.origin.z - initial[index].z).length())
						for corner in 8:
							var p := transform * bounds.get_endpoint(corner)
							if not room._spawn_floor_contains(Vector3(p.x, room.to_local(strong.global_position).y, p.z), 0.001):
								failed_geometry = true
								if violations.size() < 12:
									violations.append({"frame":frame,"piece":index,"kind":"floor","corner":str(p),"aabb":str(transform * bounds),"reach":room._spawn_reach_contains(p),"dimensions":str(room.get_dimensions()),"support_triangles":room._spawn_support_triangles.size(),"host_floor_envelope":room._spawn_floor_contains(room.to_local(strong.global_position), snapshot.landing_distance_m + 1.25)})
						for blocker: AABB in room._spawn_blockers:
							if (transform * bounds).intersects(blocker):
								failed_geometry = true
								if violations.size() < 12:
									violations.append({"frame":frame,"piece":index,"kind":"blocker","blocker":str(blocker),"aabb":str(transform * bounds)})
					if render:
						# 粒子需要真实渲染帧，不能只跳家具时间后截到未模拟的空拖尾。
						await get_tree().process_frame
						await RenderingServer.frame_post_draw
						if frame in [0, 24, 38, 60, 110, 150, 162]:
							await capture(room, strong.global_position, "%d_%s_%03d" % [seed_value, room_id, frame])
				var initial_overlaps := 0
				for i in initial.size():
					for j in i:
						check(initial[i].distance_to(initial[j]) > 0.5, "初始家具不可共点")
						if initial_bounds[i].intersects(initial_bounds[j]):
							initial_overlaps += 1
				row["initial_aabb_overlap_pairs"] = initial_overlaps
				check(initial_overlaps == 0, "正式现场初始家具AABB不相交")
				row["trajectories"] = snapshot.trajectories
				for trajectory: Dictionary in snapshot.trajectories:
					check(trajectory.post_push_distance_m >= 1.5, "每家具爆后实际轨迹长度>=1.5m")
				row["minimum_horizontal_travel_m"] = minimum_travel
				row["geometry_intersection"] = failed_geometry
				row["violations"] = violations
				check(minimum_travel >= 1.5, "五家具每只显著水平飞出>=1.5m")
				check(not failed_geometry, "全生命周期采样家具包络不得穿静态墙/家具或越界")
				effect.call("finish")
			report.rows.append(row)
			print("VFX_CLEARANCE_RESULT ", JSON.stringify(row))
			director.cancel(str(started.instance_id), "test_finished")
			discard(room)
			save()
		tower.queue_free()
		await get_tree().process_frame
	report.completed = true
	save()
	get_tree().quit(0 if report.failures.is_empty() else 1)

func discard(room: DungeonRoom3D) -> void:
	for enemy: Enemy3D in tower._enemy_nodes_by_room.get(room.room_id, []):
		MonsterAIManager.unregister_enemy(enemy)
		enemy.queue_free()
	tower._enemy_nodes_by_room[room.room_id] = []
	tower._alive_by_room[room.room_id] = 0

func capture(room: DungeonRoom3D, point: Vector3, label: String) -> void:
	tower.player.global_position = point + Vector3(0, 0.05, 0)
	tower.player.reset_debug_camera_adjustments()
	tower.player.camera_feedback.reset()
	for frame in 90:
		tower._update_camera_profile(1.0 / 60.0)
		tower._apply_indoor_camera_pose()
	tower.player.camera.current = true
	# Camera3D平滑在渲染帧更新；先送出新相机姿态，避免上一房画面冒充本帧证据。
	tower.player.camera.reset_physics_interpolation()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(OS.get_environment("VFX_CLEARANCE_OUTPUT").path_join(label + ".png")) == OK, "正式Forward+截图保存")
	# 截图不改变后续派发玩家安全距离。
	tower.player.global_position = room.global_position + Vector3(0, 0.05, 0)

func save() -> void:
	var file := FileAccess.open(OS.get_environment("VFX_CLEARANCE_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
