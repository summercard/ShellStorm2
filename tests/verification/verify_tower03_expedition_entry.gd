extends Node3D
## 入口来源、实际碰撞、返回携带与旧档兼容专项；APPDATA必须在启动前隔离。
const TOWER = preload("res://scenes/TowerDescent3D.tscn")
const EXPEDITION = preload("res://scenes/ExpeditionLevel01_3D.tscn")
var failures: Array[String] = []
var completed := false

func _ready() -> void:
	get_tree().create_timer(100).timeout.connect(func():
		if not completed:
			push_error("TOWER03_ENTRY_TIMEOUT")
			get_tree().quit(2))
	BaseManager.save_path = "user://tower03_entry_verify_%d.json" % OS.get_process_id()
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_SCENE_REENTRY, GameEntryFlow.SPAWN_BASE_99F)
	var tower: TowerDescent3D = TOWER.instantiate()
	tower.test_mode = false
	tower.run_seed_override = 12345
	add_child(tower)
	await settle()
	tower.player.set_physics_process(false)
	var door := tower.get_node("Blocks/Rooftop/CrossTowerRoute/Expedition01Entrance") as RooftopExpeditionEntrance3D
	tower.player.global_position = ExpeditionEntryContext.TOWER03_SPAWN
	tower.player.set_input_locked(false)
	check(not door.get_interaction_candidate(tower.player).is_empty(), "门前没有交互候选")
	var old_checkpoint := BaseManager.get_active_run_checkpoint()
	check(door.perform_interaction(tower.player, {}), "门交互未打开确认")
	check(door._dialog.dialog_text == "是否进入远征关卡01？", "确认文字错误")
	check(tower.player.input_locked, "确认框没有锁输入")
	door._dialog.hide()
	door._cancel()
	check(not tower.player.input_locked, "取消没有恢复输入")
	check(BaseManager.get_active_run_checkpoint() == old_checkpoint, "取消写入了检查点")
	tower.player.global_position += Vector3.RIGHT * 10
	check(door.get_interaction_candidate(tower.player).is_empty(), "远处仍能激活")
	tower.player.global_position = ExpeditionEntryContext.TOWER03_SPAWN
	await verify_physics(tower)
	# 保存拒绝与回滚对照；基地出发须显式覆盖旧来源。
	var before_failure := BaseManager.get_active_run_checkpoint()
	BaseManager.force_save_failure_for_test = true
	var rejected := ExpeditionDepartureService.prepare(tower, ExpeditionEntryContext.TOWER03)
	check(not bool(rejected.get("success", false)), "保存失败仍然出发")
	check(BaseManager.get_active_run_checkpoint() == before_failure, "保存失败修改了检查点")
	BaseManager.force_save_failure_for_test = false
	var base_ticket := ExpeditionDepartureService.prepare(tower, ExpeditionEntryContext.BASE)
	check(bool(base_ticket.get("success", false)), "基地准备事务失败")
	check(str(BaseManager.get_active_run_checkpoint().get(ExpeditionEntryContext.SOURCE_KEY, "")) == ExpeditionEntryContext.BASE, "基地没有重置来源")
	ExpeditionDepartureService.rollback(base_ticket)
	check(BaseManager.get_active_run_checkpoint() == base_ticket.get("previous"), "出发回滚没有恢复快照")
	# 正式准备事务与卸载：出发来源及携带标记不能被卸载回写吃掉。
	var ticket := ExpeditionDepartureService.prepare(tower, ExpeditionEntryContext.TOWER03)
	check(bool(ticket.get("success", false)), "天台出发事务失败")
	var carry := BaseManager.get_active_run_checkpoint()
	check(str(carry.get(ExpeditionEntryContext.SOURCE_KEY, "")) == ExpeditionEntryContext.TOWER03, "出发来源丢失")
	tower.queue_free()
	await settle()
	check(BaseManager.get_active_run_checkpoint() == carry, "卸载覆盖出发标记")
	var expedition := await spawn_expedition()
	check(expedition._expedition_entry_source == ExpeditionEntryContext.TOWER03, "远征没读取天台来源")
	var action := expedition.build_runtime_save_snapshot()
	check(str(action.get(ExpeditionEntryContext.SOURCE_KEY, "")) == ExpeditionEntryContext.TOWER03, "行动存档没保留来源")
	check(BaseManager.set_active_run_checkpoint(action, "tower03_resume"), "保存行动失败")
	expedition.queue_free()
	await settle()
	expedition = await spawn_expedition()
	check(expedition._expedition_entry_source == ExpeditionEntryContext.TOWER03, "重启续局来源丢失")
	check(expedition._request_return_entry_context(false) > 0, "死亡入口登记失败")
	check(str(GameEntryFlow.peek_pending_entry().get("spawn_target", "")) == GameEntryFlow.SPAWN_TOWER03_ROOFTOP, "死亡返回目标错误")
	check(expedition._write_successful_extraction_carry_checkpoint(), "成功携带交接失败")
	var successful := BaseManager.get_active_run_checkpoint()
	check(str(successful.get("scope", "")) == "base" and str(successful.get("runtime_map_id", "bad")) == "", "撤离标记仍可续战局")
	check(str(successful.get(ExpeditionEntryContext.RETURN_KEY, "")) == ExpeditionEntryContext.TOWER03, "撤离返回来源丢失")
	expedition.queue_free()
	await settle()
	var returned := await spawn_return()
	check(returned.player.global_position.distance_to(ExpeditionEntryContext.TOWER03_SPAWN) < .15, "延迟携带恢复覆盖了塔3落点")
	check(returned._current_room_id == "start", "返航房间归属错误")
	var returned_checkpoint := returned.build_runtime_save_snapshot()
	check(str(returned_checkpoint.get(ExpeditionEntryContext.RETURN_KEY, "")) == ExpeditionEntryContext.TOWER03, "天台下线锚点丢失")
	BaseManager.unregister_runtime_checkpoint_provider(returned, false)
	returned.queue_free()
	await settle()
	# 结算原子保存死亡来源；保险与其他结算字段使用同一事务。
	var commit := BaseManager.commit_run_settlement({"transaction_id": "tower03_death", "success": false,
		"return_checkpoint": ExpeditionEntryContext.return_marker(ExpeditionEntryContext.TOWER03)})
	check(bool(commit.get("success", false)), "死亡事务失败")
	check(str(BaseManager.get_active_run_checkpoint().get(ExpeditionEntryContext.RETURN_KEY, "")) == ExpeditionEntryContext.TOWER03, "死亡事务没有保存返回标记")
	returned = await spawn_return()
	check(returned.player.global_position.distance_to(ExpeditionEntryContext.TOWER03_SPAWN) < .15, "死亡标记重启落点错误")
	BaseManager.unregister_runtime_checkpoint_provider(returned, false)
	returned.queue_free()
	await settle()
	# 退出分支会清携带物，保持原损失规则，但登记同一来源。
	BaseManager.set_active_run_checkpoint(action, "tower03_retreat")
	expedition = await spawn_expedition()
	expedition._confirm_expedition_exit()
	check(str(GameEntryFlow.peek_pending_entry().get("spawn_target", "")) == GameEntryFlow.SPAWN_TOWER03_ROOFTOP, "退出返回目标错误")
	expedition.queue_free()
	await settle()
	# 基地、旧档、非法来源负向对照，不能沿用前一次天台来源。
	BaseManager.clear_active_run_checkpoint("legacy")
	expedition = await spawn_expedition()
	check(expedition._expedition_entry_source == ExpeditionEntryContext.BASE, "旧档默认来源错误")
	expedition._request_return_entry_context(true)
	check(str(GameEntryFlow.peek_pending_entry().get("spawn_target", "")) == GameEntryFlow.SPAWN_BASE_99F, "基地返航受到天台污染")
	check(ExpeditionEntryContext.normalize("bad") == ExpeditionEntryContext.BASE, "非法来源没回退基地")
	expedition.queue_free()
	await settle()
	completed = true
	if failures.is_empty():
		print("TOWER03_EXPEDITION_ENTRY_OK")
		get_tree().quit(0)
	else:
		for message in failures:
			push_error(message)
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func settle() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame

func spawn_expedition() -> TowerDescent3D:
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	var result: TowerDescent3D = EXPEDITION.instantiate()
	result.test_mode = true
	result.run_seed_override = 12345
	add_child(result)
	await settle()
	result.player.set_physics_process(false)
	return result

func spawn_return() -> TowerDescent3D:
	# 无显式请求模拟重启：持久化返回标记本身须足以路由。
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_RUNTIME_RESTORE)
	var result: TowerDescent3D = TOWER.instantiate()
	result.test_mode = false
	result.run_seed_override = 12345
	add_child(result)
	await settle()
	result.player.set_physics_process(false)
	return result

func verify_physics(tower: TowerDescent3D) -> void:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var source := tower.player.get_node("VirtualCollisionCapsule") as CollisionShape3D
	shape.shape = source.shape.duplicate()
	shape.position = source.position
	body.add_child(shape)
	add_child(body)
	body.collision_layer = 0
	body.collision_mask = 1
	body.floor_snap_length = .35
	for x in [-37.0, -30.0]:
		body.global_position = Vector3(x, .08, -171.0)
		body.velocity = Vector3.ZERO
		for i in 180:
			await get_tree().physics_frame
			body.velocity = Vector3(0, body.velocity.y - 18.0 / 60.0, -2.0)
			body.move_and_slide()
		check(body.global_position.z < -174.1 and body.global_position.y > 1.25, "短梯上行阻挡或跌落 x=%s pos=%s" % [x, body.global_position])
		for i in 180:
			await get_tree().physics_frame
			body.velocity = Vector3(0, body.velocity.y - 18.0 / 60.0, 2.0)
			body.move_and_slide()
		check(body.global_position.z > -171.5 and body.global_position.y < .2, "短梯下行阻挡 x=%s pos=%s" % [x, body.global_position])
	var space := get_world_3d().direct_space_state
	for x in [-40.0, -34.0]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 2, -172.0), Vector3(x, 2, -174.0), 1)
		check(not space.intersect_ray(query).is_empty(), "平台栏杆缺少阻挡 x=%s" % x)
	var spawn := ExpeditionEntryContext.TOWER03_SPAWN
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(spawn + Vector3.UP, spawn - Vector3.UP, 1))
	check(not ground.is_empty() and absf(ground.position.y) < .02, "返航落点没有屋面承重")
	body.queue_free()


