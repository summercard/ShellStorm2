extends Node
## 正式room03生产事件取证：不替换关卡encounter、不伪造HUD时钟，启动前隔离userdata。
const SCENE = preload("res://scenes/ExpeditionLevel01_3D.tscn")
var failures: Array[String] = []
var checks := 0
var tower: TowerDescent3D
var out := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\","/")
	out = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	if not appdata.contains("shellstorm-verification.") or out.is_empty() or DisplayServer.get_name() == "headless":
		push_error("必须启动前隔离userdata并使用真实渲染器和工程外截图出口")
		get_tree().quit(1)
		return
	call_deferred("run")

func run() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_loading_active:
			break
		await get_tree().process_frame
	var ready := tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_bootstrap_failed
	check(ready,"正式关卡初始化失败")
	if not ready:
		finish()
		return
	tower.set_process(false)
	tower.player.set_physics_process(false)
	var room := tower._room_by_id["room_03"] as DungeonRoom3D
	var original := room.encounter.duplicate(true)
	tower.player.global_position = room.to_global(Vector3.ZERO)
	tower.force_enter_room_for_test(room.room_id)
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	room.ensure_shell_built()
	room.ensure_detail_built()
	var port := room.get_connection_port_by_id("A")
	var p: Array = port.position_m
	var n: Array = port.outward
	var trigger := room.encounter.trigger as Dictionary
	var inset := float(trigger.inset_m) + float(trigger.depth_m) * 0.5
	tower.player.global_position = room.to_global(Vector3(float(p[0])-float(n[0])*inset,0.5,float(p[1])-float(n[1])*inset))
	tower._tick_room_encounter_triggers(0.0)
	var id := str(tower._room_encounter_active.get(room.room_id,""))
	check(not id.is_empty(),"真实入口未触发正式遭遇")
	if id.is_empty():
		finish()
		return
	var state := tower.get_encounter_event_snapshot(id)
	check(state.config.alert_style == "red_eva" and float(state.preparation_total_sec) == 3.0,"正式03配置非red_eva/3秒")
	check(tower.player.input_locked,"正式03首秒冻结未生效")
	tower._encounter_event_director.tick(0.25)
	await capture("room03_preparation",id,"【接敌】 2.75 秒")
	tower._encounter_event_director.tick(2.75)
	state = tower.get_encounter_event_snapshot(id)
	check(int(state.spawned) > 0 and not tower.player.input_locked,"准备结束真实出怪并释控")
	await capture("room03_combat",id,"【清除入侵者】")
	# 真实击杀出口推动Owner进入间歇，不直接改其stage_states或remaining。
	for enemy: Enemy3D in (tower._enemy_nodes_by_room.get(room.room_id,[]) as Array).duplicate():
		if is_instance_valid(enemy) and enemy.ai_state != "dead":
			tower._on_enemy_killed(enemy,enemy.get_enemy_data())
			enemy.free()
	tower._enemy_nodes_by_room[room.room_id] = []
	state = tower.get_encounter_event_snapshot(id)
	check(state.alert_phase == "intermission" and not tower.player.input_locked,"真实间歇无冻结")
	tower._encounter_event_director.tick(0.37)
	await capture("room03_intermission",id,"【下一批接敌】 2.63 秒")
	check(room.encounter == original,"拍摄过程中改写了生产encounter")
	finish()

func capture(stem: String, id: String, expected: String) -> void:
	tower._tick_encounter_countdown_hud()
	tower._apply_indoor_camera_pose()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var row := tower._hud_countdown_ring.get_snapshot()
	check(row.text == expected,"正式HUD读数:"+stem+" actual="+str(row.text))
	check(tower._current_room_id == "room_03" and (tower._room_by_id["room_03"] as DungeonRoom3D).is_streamed(),"必须是真实room03而非黑底fixture")
	var image := get_viewport().get_texture().get_image()
	check(image != null and image.get_width() >= 1200,"真实视口截图有效")
	var path := out.path_join(stem+".png")
	check(image.save_png(path) == OK,"保存截图失败:"+stem)
	print("ROOM03_ALERT_CAPTURE path=%s state=%s hud=%s" % [path,str(tower.get_encounter_event_snapshot(id).get("alert_phase","")),str(row)])

func finish() -> void:
	if is_instance_valid(tower):
		tower.queue_free()
		await get_tree().process_frame
	print("ROOM03_ALERT_RENDER_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAIL",checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
