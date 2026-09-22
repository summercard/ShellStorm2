extends Node
## 撤离读条期间阵亡的终局归属验收。
##
## 被盯住的契约（docs/v0.1/09_技术施工_存档结算与复活.md §5.1 离场语义表 +
## 「成功撤离、死亡……事务 ID 幂等；重复请求不能重复发放或扣除」）：
##   撤离读条期间 HP 归零 ⇒ 必须中断撤离读条，且只走一次阵亡结算。
##   既不能「同一次行动先判撤离成功、再判阵亡结算」，也不能一次都不结算。
##
## 修复前实测（四时序全部异常）：
##   塔楼：信标读完判 success=true，返航复位把 `_completed` 打回 false，
##         点死亡确认再判 false ⇒ 同一次行动结算两次；
##   远征：阵亡后信标照常读到 0，一律判 success=true ⇒ 死亡被完全吞掉。
##
## 反向对照（修复不得误伤正常路径）：
##   ① 健康玩家读完信标必须仍然恰好结算 1 次 success=true；
##   ② 阵亡但不撤离必须恰好结算 1 次 success=false；
##   ③ 塔楼成功返航复位之后，新一轮阵亡必须还能正常弹框并结算一次；
##   ④ 结算后的返航窗口内，玩家不应再被伤害拖死。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel99_3D.tscn"
const DEATH_ANIM_S := 1.35
const SETTLE_WAIT_S := 0.6

var _events: Array[String] = []


func _ready() -> void:
	var failures: Array[String] = []
	_check_one_transaction_id_per_run(failures)
	await _check_case(failures, "塔楼·信标先读完", TOWER_SCENE, 0.5)
	await _check_case(failures, "塔楼·死亡框先出现", TOWER_SCENE, 4.5)
	await _check_case(failures, "远征·信标先读完", EXPEDITION_SCENE, 0.5)
	await _check_case(failures, "远征·死亡框先出现", EXPEDITION_SCENE, 4.5)
	await _check_healthy_extraction_still_succeeds(failures)
	await _check_death_without_extraction(failures)
	await _check_new_run_death_after_return(failures)
	await _check_return_window_protects_player(failures)
	if failures.is_empty():
		print(
			"DEATH_DURING_EXTRACTION_FLOW_OK: 撤离读条期间阵亡一律中断读条并只结算一次阵亡；"
			+ "成功与死亡共用同一行动事务 ID；正常撤离、无撤离阵亡、返航后新一轮阵亡"
			+ "与返航窗口保护四条反向对照全部保持原行为"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 静态契约：同一次行动的成功与死亡必须拿到同一个事务 ID，幂等才有意义。
func _check_one_transaction_id_per_run(failures: Array[String]) -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	if scene == null:
		failures.append("事务 ID 契约：塔楼场景无法加载")
		return
	var tower := scene.instantiate()
	tower.set("test_mode", true)
	add_child(tower)
	var success_id := str(tower.call("_get_run_settlement_transaction_id", true))
	var death_id := str(tower.call("_get_run_settlement_transaction_id", false))
	if success_id.is_empty() or death_id.is_empty():
		failures.append("事务 ID 契约：行动结算事务 ID 为空")
	elif success_id != death_id:
		failures.append(
			"同一次行动的成功与死亡拿到了两个不同的事务 ID，幂等去重形同虚设：%s / %s"
			% [success_id, death_id]
		)
	tower.queue_free()


## 四种时序统一判据：只结算一次、且必须是阵亡。
func _check_case(failures: Array[String], label: String, scene_path: String, remaining: float) -> void:
	_events.clear()
	var scene := await _spawn(scene_path)
	if scene == null:
		failures.append("%s：场景无法实例化" % label)
		return
	var player := scene.get("player") as Player3D
	var beacon := _make_beacon(scene)
	if player == null or beacon == null:
		failures.append("%s：无法准备玩家或撤离信标" % label)
		await _despawn(scene)
		return
	beacon.force_start_for_test()
	beacon.set("_remaining", remaining)
	player.take_damage(99999)
	if player.current_hp > 0:
		failures.append("%s：构造阵亡失败，玩家仍存活" % label)
		await _despawn(scene)
		return
	# 等足「死亡动画 + 信标原本读完的时刻」，让两条路径都有机会抢跑。
	await get_tree().create_timer(DEATH_ANIM_S + remaining + 1.0).timeout
	scene.call("_confirm_death_return")
	await get_tree().create_timer(SETTLE_WAIT_S).timeout
	if bool(beacon.get("_active")):
		failures.append("%s：阵亡之后撤离信标仍在读条" % label)
	_assert_only_death_settlement(failures, label)
	await _despawn(scene)


## 反向对照①：健康玩家读完信标，必须仍然恰好结算一次成功撤离。
func _check_healthy_extraction_still_succeeds(failures: Array[String]) -> void:
	_events.clear()
	var scene := await _spawn(TOWER_SCENE)
	if scene == null:
		failures.append("反向对照①：塔楼场景无法实例化")
		return
	var beacon := _make_beacon(scene)
	if beacon == null:
		failures.append("反向对照①：无法建立撤离信标")
		await _despawn(scene)
		return
	beacon.force_start_for_test()
	beacon.set("_remaining", 0.4)
	await get_tree().create_timer(1.2).timeout
	_assert_only_success_settlement(failures, "反向对照①健康玩家撤离")
	await _despawn(scene)


## 反向对照②：阵亡但不碰撤离点，必须恰好结算一次阵亡。
func _check_death_without_extraction(failures: Array[String]) -> void:
	_events.clear()
	var scene := await _spawn(TOWER_SCENE)
	if scene == null:
		failures.append("反向对照②：塔楼场景无法实例化")
		return
	var player := scene.get("player") as Player3D
	if player == null:
		failures.append("反向对照②：拿不到玩家")
		await _despawn(scene)
		return
	player.take_damage(99999)
	await get_tree().create_timer(DEATH_ANIM_S + 0.6).timeout
	scene.call("_confirm_death_return")
	await get_tree().create_timer(SETTLE_WAIT_S).timeout
	_assert_only_death_settlement(failures, "反向对照②无撤离阵亡")
	await _despawn(scene)


## 反向对照③：成功返航复位之后，新一轮阵亡必须还能弹框并结算一次。
func _check_new_run_death_after_return(failures: Array[String]) -> void:
	_events.clear()
	var scene := await _spawn(TOWER_SCENE)
	if scene == null:
		failures.append("反向对照③：塔楼场景无法实例化")
		return
	var player := scene.get("player") as Player3D
	var beacon := _make_beacon(scene)
	if player == null or beacon == null:
		failures.append("反向对照③：无法准备玩家或撤离信标")
		await _despawn(scene)
		return
	beacon.force_start_for_test()
	beacon.set("_remaining", 0.4)
	await get_tree().create_timer(1.2).timeout
	_assert_only_success_settlement(failures, "反向对照③第一次撤离")
	if bool(scene.get("_completed")):
		failures.append("反向对照③：成功返航之后行动仍锁在已结算状态，新一轮无法开始")
		await _despawn(scene)
		return
	player.take_damage(99999)
	await get_tree().create_timer(DEATH_ANIM_S + 0.6).timeout
	if scene.get("_death_dialog") == null:
		failures.append("反向对照③：成功返航之后新一轮阵亡没有弹出死亡确认框")
		await _despawn(scene)
		return
	scene.call("_confirm_death_return")
	await get_tree().create_timer(SETTLE_WAIT_S).timeout
	if _events.count("success") != 1 or _events.count("failure") != 1:
		failures.append(
			"反向对照③：返航后新一轮阵亡应各结算一次成功与阵亡，实际 %s" % str(_events)
		)
	await _despawn(scene)


## 反向对照④：结算已提交后的保护必须挡住伤害，且解除后要能正常受伤。
## 注：test_mode 下 `_return_successful_extraction_to_facility` 不带 0.8s 返航等待，
## 保护窗口被压缩为 0，所以这里直接盯机制本身，不依赖场景时序。
func _check_return_window_protects_player(failures: Array[String]) -> void:
	var scene := await _spawn(TOWER_SCENE)
	if scene == null:
		failures.append("反向对照④：塔楼场景无法实例化")
		return
	var player := scene.get("player") as Player3D
	if player == null:
		failures.append("反向对照④：拿不到玩家")
		await _despawn(scene)
		return
	player.hold_post_settlement_invulnerability()
	var hp_before := player.current_hp
	player.take_damage(99999)
	if player.current_hp != hp_before:
		failures.append(
			"反向对照④：结算已提交后仍能被伤害（%d → %d），残留拦截怪可以污染已写盘的结果"
			% [hp_before, player.current_hp]
		)
		await _despawn(scene)
		return
	player.release_post_settlement_invulnerability()
	player.take_damage(1)
	if player.current_hp >= hp_before:
		failures.append("反向对照④：解除结算后保护之后玩家仍然免疫伤害，保护会糊住后续行动")
	await _despawn(scene)


func _assert_only_death_settlement(failures: Array[String], label: String) -> void:
	if "success" in _events:
		failures.append("%s：阵亡被判成撤离成功，结算序列 %s" % [label, str(_events)])
	if _events.count("failure") != 1:
		failures.append(
			"%s：阵亡应恰好结算 1 次，实际 %d 次，结算序列 %s"
			% [label, _events.count("failure"), str(_events)]
		)


func _assert_only_success_settlement(failures: Array[String], label: String) -> void:
	if "failure" in _events:
		failures.append("%s：健康撤离被判成阵亡，结算序列 %s" % [label, str(_events)])
	if _events.count("success") != 1:
		failures.append(
			"%s：成功撤离应恰好结算 1 次，实际 %d 次，结算序列 %s"
			% [label, _events.count("success"), str(_events)]
		)


func _record_settlement(success: bool, _summary: Dictionary) -> void:
	_events.append("success" if success else "failure")


func _spawn(scene_path: String) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate()
	scene.set("test_mode", true)
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	scene.run_completed.connect(_record_settlement)
	return scene


func _despawn(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## 信标必须通过 Dungeon3D 的真实接线创建，否则「信号没接上」会被误判成漏结算。
func _make_beacon(scene: Node) -> ExtractionBeacon3D:
	var room_ids: Array[String] = []
	var current := str(scene.get("_current_room_id"))
	if not current.is_empty():
		room_ids.append(current)
	var rooms: Variant = scene.get("_rooms")
	if rooms is Array:
		for value in rooms as Array:
			var room := value as DungeonRoom3D
			if room != null and is_instance_valid(room):
				room_ids.append(room.room_id)
	for room_id in room_ids:
		var room := (scene.get("_room_by_id") as Dictionary).get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var beacon := scene.call(
			"_create_extraction_beacon", room, "STANDARD", 30.0, false, Vector3(0, 0, 2.0)
		) as ExtractionBeacon3D
		if beacon != null:
			return beacon
	return null
