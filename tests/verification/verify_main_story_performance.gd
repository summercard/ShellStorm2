extends Node
## 必须在 Autoload 前隔离 APPDATA。使用真实塔楼、NPC、控制器和领域服务，不替换控制器。

const BASE_SCENE := preload("res://scenes/TowerDescent3D.tscn")
const KEY := "mq_key_rare_earth"
var tower: Node3D
var controller: Node
var npc: Node3D
var failures: Array[String] = []
var checks := 0
var samples: Array[Dictionary] = []
var _old_data: Resource
var _old_save_path := ""
var _capture_dir := ""
var _shot_camera: Camera3D

func _ready() -> void:
	if OS.get_environment("SHELLSTORM_MAIN_STORY_ISOLATED") != "1" or not "main_story_performance" in ProjectSettings.globalize_path("user://"):
		push_error("主线表演验收拒绝未在 Autoload 前隔离的用户目录")
		get_tree().quit(2)
		return
	_capture_dir = OS.get_environment("SHELLSTORM_MAIN_STORY_CAPTURE_DIR")
	await _run()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("MAIN_STORY_PERFORMANCE_FAIL ", message)

func _instruction(action: String) -> bool:
	var result: Dictionary = controller.call("call_instruction", action, {})
	check(bool(result.get("ok", false)), action + "：" + str(result.get("reason", "")))
	return bool(result.get("ok", false))

func _wait_barrier(label: String) -> void:
	var elapsed := 0.0
	while not bool(controller.call("should_advance_narrative")) and elapsed < 25.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	check(elapsed < 25.0, label + "真实到位屏障解除")
	samples.append({"label": label, "elapsed": elapsed, "npc_position": npc.global_position, "controller": controller.call("get_snapshot")})

func _run() -> void:
	_old_data = BaseManager.data
	_old_save_path = BaseManager.save_path
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://performance.json"
	BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {KEY: {"state": "acquired"}}}
	BaseManager.replace_narrative_history_for_test({MainStoryChapter3D.BRIEFING_ID: {"completed_count": 1}})
	NarrativeDirector.reset_for_test()
	NarrativeDirector.set_process(false)
	tower = BASE_SCENE.instantiate() as Node3D
	tower.set("test_mode", true)
	tower.set("force_main_story_for_test", true)
	tower.set("run_seed_override", 77001199)
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.set_process(false)
	controller = tower.call("get_main_story_controller") as Node
	check(controller != null, "正式塔楼已装配主线控制器")
	if controller == null:
		await _finish()
		return
	controller.set_process(false)
	NarrativeDirector.abort("performance_fixture_ready")
	NarrativeDirector.bind_dungeon_for_test(tower)
	var player := tower.get("player") as Node3D
	player.set_physics_process(false)
	npc = tower.call("find_npc", "npc_base99_green") as Node3D
	check(npc != null, "真实绿苔已装配")
	if npc == null:
		await _finish()
		return
	var room := tower.call("get_main_story_room", "facility") as Node3D
	room.call("ensure_shell_built")
	room.call("ensure_detail_built")
	tower.set("_current_room_id", "facility")
	player.global_position = tower.call("get_facility_spawn_point")
	var player_initial := player.global_position
	var npc_initial := npc.global_position
	var pedestal := tower.get("_main_story_pedestal") as Node3D
	check(pedestal != null, "真实设施已附加四槽台座")
	check(controller.call("resolve_anchor", "pedestal_stand") is Vector3, "站位锚点存在")
	var stand: Vector3 = controller.call("resolve_anchor", "pedestal_stand")
	var slot: Vector3 = controller.call("resolve_anchor", "key_slot_rare_earth")
	check(absf(slot.y - stand.y) > 0.7, "插入点和NPC地面站位不混用")
	# 本轮业主改造：不再立一块独立台座，四孔嵌件直接嵌在主门下方低矮设备柜台面上。
	var insert_view: Dictionary = pedestal.call("get_snapshot")
	check(bool(insert_view.get("insert_loaded", false)), "四孔嵌件真实实例化")
	check(str(insert_view.get("insert_asset_id", "")) == "PRP-BASE99-MAIN-STORY-KEY-INSERT", "嵌件使用正式资产ID")
	check(int(insert_view.get("socket_glows", 0)) == 4, "嵌件四个槽灯可独立取到")
	var insert_origin := pedestal.global_position
	var art := tower.get("_facility_art_layout") as Node3D
	check(art != null and pedestal.get_parent() == art, "嵌件挂在 99F 美术布置层下，跟随房间流送")
	var expected := art.to_global(Vector3(5.0, 1.38, -3.77)) if art != null else Vector3.ZERO
	check(insert_origin.distance_to(expected) < 0.05, "嵌件落在主门低柜台面中央")
	check(absf((insert_origin.y - room.global_position.y) - 1.38) < 0.05, "嵌件坐在台面上 y=1.38，不是地面")
	check(absf(stand.y - room.global_position.y) < 0.05, "绿苔站位回到地面")
	var insert_params: Dictionary = pedestal.call("get_insert_params")
	check((insert_params.get("basis", Basis.IDENTITY) as Basis).z.y > 0.3, "插入轴是 20° 斜孔轴而非竖直向下")
	check(float((insert_params.get("origin_offset", Vector3.ZERO) as Vector3).y) > 0.05, "插到位的钥匙柄抬到孔口上方")
	if _instruction("deposit.prepare"):
		check(npc.global_position.distance_to(npc_initial) < 0.01, "prepare没有瞬移绿苔")
		var too_early: Dictionary = controller.call("call_instruction", "deposit.commit", {})
		check(not bool(too_early.get("ok", false)), "NPC未到与钥匙未插时拒绝事务")
		_instruction("deposit.move_to_player")
		check(not bool(controller.call("should_advance_narrative")), "跑来期间真实屏障阻止下一cue")
		await _wait_barrier("跑来")
		check(npc.global_position.distance_to(npc_initial) > 0.5, "绿苔真实改变位置")
		check(Vector2(npc.global_position.x - player.global_position.x, npc.global_position.z - player.global_position.z).length() <= 1.35, "接近点不被出生规则推远，手臂无需过度伸长")
		await _capture("01_arrival", player)
		_instruction("deposit.key_present")
		await _wait_barrier("拿出钥匙")
		await _capture("02_present", player)
		_instruction("deposit.key_handoff")
		await _wait_barrier("手部接触交接")
		var state: Dictionary = controller.call("get_snapshot")
		check(bool(state.get("key_visual", {}).get("handoff_done", false)), "同一钥匙实例已在接触点换父级")
		check(str(state.get("key_visual", {}).get("parent", "")) == "HandJointR", "临时钥匙挂于绿苔真实手部")
		await _capture("03_handoff", npc)
		_instruction("deposit.move_to_slot")
		await _wait_barrier("跑至设施台下")
		check(Vector2(npc.global_position.x - stand.x, npc.global_position.z - stand.z).length() <= 0.24, "绿苔站在独立站位")
		_instruction("deposit.key_insert")
		await _wait_barrier("钥匙插入接触")
		await _capture("04_insert", pedestal)
		BaseManager.force_save_failure_for_test = true
		print("MAIN_STORY_EXPECTED_FAILURE_BEGIN deposit_save")
		var rejected: Dictionary = controller.call("call_instruction", "deposit.commit", {})
		print("MAIN_STORY_EXPECTED_FAILURE_END deposit_save")
		check(not bool(rejected.get("ok", false)), "安装保存失败不显示解锁成功")
		check(str(BaseManager.get_main_story_snapshot().get("keys", {}).get(KEY, {}).get("state", "")) == "acquired", "保存失败钥匙所有权仍待交付")
		BaseManager.force_save_failure_for_test = false
		_instruction("deposit.commit")
		check(str(BaseManager.get_main_story_snapshot().get("keys", {}).get(KEY, {}).get("state", "")) == "deposited", "安装事务真实落盘")
		var view: Dictionary = pedestal.call("get_snapshot")
		check(int(view.get("installed_count", 0)) == 1 and is_equal_approx(float(view.get("ring_fraction", 0.0)), 0.25), "第一槽与四分之一环来自永久快照")
		check(bool(view.get("persistent_key_visible", false)), "永久钥匙实体留在第一槽")
		await _capture("05_deposited", pedestal)
		_instruction("deposit.release")
		check(not bool(npc.call("is_scripted_appearance")), "结束归还NPC巡逻")
		check(player.global_position.distance_to(player_initial) < 0.01, "玩家始终保持原站位")
		var reload_pedestal := load("res://assets/art/props/main_story/runtime/main_story_pedestal.tscn") as PackedScene
		var preview := reload_pedestal.instantiate() as Node3D
		add_child(preview)
		check(bool((preview.call("get_snapshot") as Dictionary).get("persistent_key_visible", false)), "独立Prefab读档恢复钥匙")
		preview.queue_free()
	# 真实导演收口回调检查，不以手动释放冒充导演已接。
	BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {KEY: {"state": "acquired"}}}
	check(NarrativeDirector.play(MainStoryChapter3D.DEPOSIT_ID), "正式3.3 JSON可由导演启动")
	NarrativeDirector.call("_process", 0.01)
	check(bool(npc.call("is_scripted_appearance")), "导演prepare真实接管NPC")
	NarrativeDirector.abort("performance_abort_check")
	check(not bool(npc.call("is_scripted_appearance")), "abort占用回调清理NPC")
	check(not NarrativeDirector.is_player_input_locked(), "abort归还适配器输入锁")
	var state_after: Dictionary = controller.call("get_snapshot")
	check((state_after.get("key_visual", {}) as Dictionary).is_empty(), "abort回收临时钥匙")
	check(NarrativeDirector.play(MainStoryChapter3D.DEPOSIT_ID), "中止后可重新开始3.3")
	NarrativeDirector.call("_process", 0.01)
	NarrativeDirector.skip()
	check(not bool(npc.call("is_scripted_appearance")), "skip归还NPC")
	check(not BaseManager.has_narrative_completed(MainStoryChapter3D.DEPOSIT_ID), "未安装时skip不写假完成")
	check(NarrativeDirector.has_method("release_main_story_control") and NarrativeDirector.has_method("restore_main_story_camera"), "导演真实progress交还公共接口已接（跨模块）")
	await _finish()

func _capture(label: String, target: Node3D) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	# 玩家相机每帧可能重新 make_current，这里用独立相机并在拍摄前重复夺取。
	var player := tower.get("player") as Node3D
	var player_camera := player.get("camera") as Camera3D
	if player_camera != null:
		player_camera.current = false
	if _shot_camera == null or not is_instance_valid(_shot_camera):
		_shot_camera = Camera3D.new()
		_shot_camera.fov = 48.0
		add_child(_shot_camera)
	var center: Vector3 = target.global_position + Vector3.UP * 0.55
	_shot_camera.global_position = center + Vector3(1.55, 1.35, 1.75)
	_shot_camera.look_at(center)
	_shot_camera.current = true
	await RenderingServer.frame_post_draw
	_shot_camera.current = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_capture_dir.path_join(label + ".png"))

func _finish() -> void:
	NarrativeDirector.abort("performance_cleanup")
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame
	BaseManager.data = _old_data as BaseData
	BaseManager.save_path = _old_save_path
	if not _capture_dir.is_empty():
		var file := FileAccess.open(_capture_dir.path_join("performance.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "samples": samples}, "  "))
	print("MAIN_STORY_PERFORMANCE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
