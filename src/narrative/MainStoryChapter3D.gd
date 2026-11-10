class_name MainStoryChapter3D
extends Node
## 主线 3.1/3.2/3.3 的条件、领域命令与演员/锚点投影。
## 台词与时间轴仍由 NarrativeDirector3D + NarrativeScript3D 消费。

const BRIEFING_ID := "nar_main_031_green_briefing"
const BOSS_ID := "nar_main_032_monitor_audience"
const DEPOSIT_ID := "nar_main_033_key_install"
const KEY_RARE_EARTH := "mq_key_rare_earth"
const KEY_SCENE_PATH := "res://assets/art/props/main_story/runtime/rare_earth_key.tscn"

const NPC_ID := "npc_base99_green"
const BOSS_ROOM_ID := "boss"
const FACILITY_ROOM_ID := "facility"
const FACILITY_ID := "mission_operations"
const BRIEFING_DISTANCE_M := 5.0
const BOSS_CONTROL_RETURN_SECONDS := 5.4

var _host: Node = null
var _activation_enemy: Node = null
var _activation_requested := false
var _control_held := false
var _extraction_started := false
var _briefing_succeeded := false
var _deposit_succeeded := false
var _deposit_npc_started := false
var _diagnostics: Array[String] = []
var _briefing_npc_started := false
var _move_target: Variant = null
var _move_anchor := ""
var _key_visual: Node3D = null
var _boss_camera_return_requested := false
var _boss_control_released := false
var _performance_fault := ""
var _player_meet_anchor: Variant = null


func setup(host: Node) -> void:
	_host = host
	set_process(host != null)
	var director := _director()
	if director != null:
		director.call("arm", BRIEFING_ID)
		director.call("arm", BOSS_ID)
		director.call("arm", DEPOSIT_ID)


func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	_sync_activation_control()
	if _activation_requested and _boss_is_lost():
		var director := _director()
		if director != null and bool(director.call("is_playing")) and str(director.call("active_id")) == BOSS_ID:
			director.call("abort", "main_story_boss_lost")
		return
	var director := _director()
	if director == null or bool(director.call("is_playing")):
		return
	if _is_modal_or_unavailable():
		return
	if _is_briefing_ready():
		if bool(director.call("play", BRIEFING_ID, {"priority": 30})):
			_briefing_succeeded = false
		return
	if _is_boss_ready():
		director.call("play", BOSS_ID, {"priority": 30})
		return
	if _is_deposit_ready():
		if bool(director.call("play", DEPOSIT_ID, {"priority": 30})):
			_deposit_succeeded = false


func resolve_actor(actor_id: String) -> Node3D:
	match actor_id:
		"player", "":
			return _player()
		NPC_ID:
			return _npc()
		"boss":
			return _boss()
	return null


func resolve_anchor(anchor_id: String) -> Variant:
	if _host == null or not is_instance_valid(_host):
		return null
	if anchor_id == "briefing_finish" and _host.has_method("get_facility_spawn_point"):
		# 收尾沿基地中央主通道走近终端；不把玩法镜头还到贴墙吊灯下方。
		return _host.call("get_facility_spawn_point")
	if anchor_id in ["boss_listening", "boss_ramp_top"]:
		var room := _main_story_room(BOSS_ROOM_ID)
		if room != null:
			return room.to_global(Vector3(0.0, 0.08, -14.0) if anchor_id == "boss_listening" else Vector3(0.0, 12.08, 40.0))
	if anchor_id == "boss_duo":
		var player := _player()
		var boss := _boss()
		if player != null and boss != null:
			return (player.global_position + boss.global_position) * 0.5 + Vector3.UP * 1.4
	if anchor_id == "player_front" and _player_meet_anchor is Vector3:
		return _player_meet_anchor
	if anchor_id == "npc_tracking":
		var npc := _npc()
		return npc.global_position + Vector3.UP * 1.7 if npc != null else null
	if anchor_id == "duo_dialogue":
		var player := _player()
		var npc := _npc()
		if player != null and npc != null:
			return (player.global_position + npc.global_position) * 0.5 + Vector3.UP * 1.7
	if anchor_id == "duo":
		var player := _player()
		var npc := _npc()
		if player != null and npc != null:
			return (player.global_position + npc.global_position) * 0.5 + Vector3.UP * 0.9
	if anchor_id == "pedestal_dialogue":
		var npc := _npc()
		var pedestal := _pedestal()
		if npc != null and pedestal != null:
			var slot: Vector3 = pedestal.call("get_anchor", "key_slot_rare_earth")
			return (npc.global_position + slot) * 0.5 + Vector3.UP * 1.4
	if anchor_id in ["pedestal_stand", "key_slot_rare_earth", "pedestal_focus"]:
		var pedestal := _pedestal()
		if pedestal != null:
			return pedestal.call("get_anchor", anchor_id)
	if _host.has_method("resolve_main_story_anchor"):
		var host_anchor: Variant = _host.call("resolve_main_story_anchor", anchor_id)
		if host_anchor is Vector3:
			return host_anchor
	if anchor_id == "player_front":
		var player := _player()
		if player != null:
			return player.global_position - player.global_basis.z.normalized() * 1.25
	if anchor_id == "npc_front":
		var npc := _npc()
		if npc != null:
			return npc.global_position - npc.global_basis.z.normalized() * 1.0
	if anchor_id == "facility":
		var room := _main_story_room(FACILITY_ROOM_ID)
		return room.global_position if room != null else null
	if anchor_id == "boss":
		var boss := _boss()
		return boss.global_position if boss != null else null
	var facility := _main_story_facility(FACILITY_ID)
	if facility == null:
		return null
	if facility.has_method("get_hologram_anchor") and anchor_id in [FACILITY_ID, "operations", "mission_operations"]:
		return facility.call("get_hologram_anchor")
	if facility.has_method("get_narrative_anchor"):
		var facility_anchor: Variant = facility.call("get_narrative_anchor", anchor_id)
		if facility_anchor is Vector3:
			return facility_anchor
	if facility.has_method("resolve_narrative_anchor"):
		var resolved: Variant = facility.call("resolve_narrative_anchor", anchor_id)
		if resolved is Vector3:
			return resolved
	if anchor_id in [FACILITY_ID, "operations", "mission_operations"]:
		return facility.global_position
	return null


func configure_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method("set_story_activation_hold"):
		enemy.call("set_story_activation_hold", true)


func on_key_claimed() -> void:
	var snapshot := _main_story_snapshot()
	if not _key_is_acquired(snapshot):
		return
	if _extraction_started:
		return
	if _host != null and _host.has_method("start_main_story_auto_extraction"):
		_host.call("start_main_story_auto_extraction", 8.0)
		_extraction_started = true


func claim_main_story_key(source: Dictionary, checkpoint: Dictionary = {}) -> Dictionary:
	var base := _root_service("BaseManager")
	if base == null or not base.has_method("claim_main_story_key"):
		return _failed("BaseManager.claim_main_story_key 不可用。")
	var result: Variant = base.call("claim_main_story_key", KEY_RARE_EARTH, source, checkpoint)
	if not result is Dictionary:
		return _failed("主线钥匙领取返回值不是 Dictionary。")
	var output: Dictionary = result as Dictionary
	if bool(output.get("success", false)):
		on_key_claimed()
	return output


func call_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"briefing.prepare":
			return _prepare_briefing()
		"briefing.point_operations":
			return _briefing_point_operations()
		"briefing.complete":
			_briefing_succeeded = true
			_release_briefing()
			return _ok()
		"boss.hold":
			var boss := _boss()
			if boss == null:
				return _failed("数据库首领不可用，3.2 中止。")
			_activation_enemy = boss
			_activation_requested = false
			_boss_camera_return_requested = false
			_boss_control_released = false
			configure_enemy(boss)
			return _done(Callable(self, "_release_boss_hold"))
		"boss.activate":
			return _request_boss_activation()
		"boss.control_hold":
			return _set_control_hold(bool(params.get("held", true)))
		"boss.release_control":
			if not should_return_boss_control():
				return _failed("首领真实激活尚未达到5.4秒，拒绝提前解锁。")
			_release_control()
			_boss_control_released = true
			return _ok()
		"key.claim":
			var claim := claim_main_story_key(
				params.get("source", {}) as Dictionary,
				params.get("checkpoint", {}) as Dictionary
			)
			return _domain_result(claim, "稀土钥匙领取失败。")
		"deposit.prepare":
			return _prepare_deposit()
		"deposit.move_to_player":
			return _move_npc_to("player_front")
		"deposit.move_to_slot":
			return _move_npc_to("pedestal_stand")
		"deposit.key_present":
			return _key_action("present", {})
		"deposit.key_handoff":
			return _key_action("handoff", {})
		"deposit.key_insert":
			var slot: Variant = resolve_anchor("key_slot_rare_earth")
			if not slot is Vector3 or not _npc_at_anchor("pedestal_stand"):
				return _failed("绿苔未到台座站位或缺少插槽，拒绝插入。")
			var pedestal := _pedestal()
			var insert := {"slot": slot, "basis": pedestal.global_basis}
			# 嵌件是 20° 斜孔：钥匙沿着孔轴插进去，而不是垂直砸进台面。
			if pedestal.has_method("get_insert_params"):
				var insert_params: Variant = pedestal.call("get_insert_params")
				if insert_params is Dictionary:
					insert.merge(insert_params as Dictionary, true)
			return _key_action("insert", insert)
		"deposit.gesture":
			return _npc_gesture(str(params.get("name", "present")))
		"deposit.commit":
			return _commit_deposit()
		"deposit.release":
			return _release_deposit()
		"deposit.complete":
			if not _deposit_succeeded:
				return _failed("主线钥匙安装尚未成功，拒绝完成 3.3。")
			return _ok()
	return _degraded("主线指令『%s』未接通。" % action)


func get_snapshot() -> Dictionary:
	var activation := _activation_snapshot()
	return {
		"briefing_id": BRIEFING_ID,
		"boss_id": BOSS_ID,
		"deposit_id": DEPOSIT_ID,
		"key_id": KEY_RARE_EARTH,
		"briefing_succeeded": _briefing_succeeded,
		"activation_requested": _activation_requested,
		"activation_enemy_valid": _activation_enemy != null and is_instance_valid(_activation_enemy),
		"activation": activation,
		"control_held": _control_held,
		"extraction_started": _extraction_started,
		"deposit_succeeded": _deposit_succeeded,
		"diagnostics": _diagnostics.duplicate(),
		"move_anchor": _move_anchor,
		"move_target": _move_target,
		"performance_fault": _performance_fault,
		"key_visual": _key_visual.call("get_snapshot") if is_instance_valid(_key_visual) else {},
		"boss_camera_return_requested": _boss_camera_return_requested,
		"boss_control_released": _boss_control_released,
	}


func should_end_narrative(narrative_id: String) -> bool:
	match narrative_id:
		BRIEFING_ID:
			return _briefing_succeeded
		BOSS_ID:
			return _activation_requested and _activation_is_complete()
		DEPOSIT_ID:
			return _deposit_succeeded
	return true


func can_commit_narrative(narrative_id: String, _reason: String) -> bool:
	match narrative_id:
		BRIEFING_ID:
			return _briefing_succeeded
		BOSS_ID:
			return _activation_is_complete()
		DEPOSIT_ID:
			return _deposit_succeeded
	return true


func _prepare_briefing() -> Dictionary:
	var npc := _npc()
	if npc == null or not npc.has_method("begin_scripted_appearance"):
		return _failed("绿苔 NPC 或脚本接管接口不可用，3.1 中止。")
	var base := _root_service("BaseManager")
	if base != null and base.has_method("accept_main_story"):
		var accepted: Variant = base.call("accept_main_story")
		if accepted is Dictionary and not bool((accepted as Dictionary).get("success", false)):
			return _failed("主线接纳失败，3.1 中止。")
		if accepted is bool and not bool(accepted):
			return _failed("主线接纳失败，3.1 中止。")
	if npc.has_method("begin_scripted_appearance"):
		var player := _player()
		var look := player.global_position if player != null else npc.global_position - npc.global_basis.z
		npc.call("begin_scripted_appearance", npc.global_position, look)
		_briefing_npc_started = true
	return _done(Callable(self, "_release_briefing"))


func _briefing_point_operations() -> Dictionary:
	var anchor: Variant = resolve_anchor(FACILITY_ID)
	if not anchor is Vector3:
		return _failed("情报室 mission_operations 没有稳定锚点，3.1 中止。")
	var npc := _npc()
	if npc != null and npc.has_method("scripted_gesture"):
		npc.call("scripted_gesture", "point")
	return _ok()


func _release_boss_hold() -> void:
	_activation_requested = false
	if _activation_enemy != null and is_instance_valid(_activation_enemy) and _activation_enemy.has_method("set_story_activation_hold"):
		_activation_enemy.call("set_story_activation_hold", false)


func _request_boss_activation() -> Dictionary:
	var boss := _boss()
	if boss == null:
		return _failed("数据库首领不可用，无法激活。")
	if not boss.has_method("request_story_activation"):
		return _failed("数据库首领缺少 request_story_activation()，不写 3.2 历史。")
	configure_enemy(boss)
	var requested: Variant = boss.call("request_story_activation")
	if requested is Dictionary:
		if not bool((requested as Dictionary).get("started", false)) and not bool((requested as Dictionary).get("success", false)):
			return _failed("数据库首领拒绝主线激活。")
	elif requested is bool and not bool(requested):
		return _failed("数据库首领拒绝主线激活。")
	_activation_enemy = boss
	_activation_requested = true
	return _ok()


func _set_control_hold(held: bool) -> Dictionary:
	if _host == null or not _host.has_method("set_scripted_input_hold"):
		return _failed("主线控制锁缺少 set_scripted_input_hold()。")
	_host.call("set_scripted_input_hold", held, true)
	_control_held = held
	return _done(Callable(self, "_release_control")) if held else _ok()


func _release_control() -> void:
	if _host != null and is_instance_valid(_host) and _host.has_method("set_scripted_input_hold"):
		_host.call("set_scripted_input_hold", false, true)
	_control_held = false


func _prepare_deposit() -> Dictionary:
	var npc := _npc()
	var player := _player()
	if npc == null or player == null or not npc.has_method("begin_scripted_appearance"):
		return _failed("3.3 真实演员或接管接口不可用。")
	if not resolve_anchor("pedestal_stand") is Vector3 or not resolve_anchor("key_slot_rare_earth") is Vector3:
		return _failed("3.3 缺少台座站位或插入点。")
	_cleanup_deposit()
	_player_meet_anchor = _resolve_meet_position(player, npc)
	if not _player_meet_anchor is Vector3:
		return _failed("玩家附近没有可交接的安全站位。")
	_deposit_succeeded = false
	_performance_fault = ""
	var scene := load(KEY_SCENE_PATH) as PackedScene
	if scene == null:
		return _failed("3.3 稀土钥匙实体资源不可用。")
	_key_visual = scene.instantiate() as Node3D
	add_child(_key_visual)
	_key_visual.call("setup_performance", player, npc)
	npc.call("begin_scripted_appearance", npc.global_position, player.global_position)
	_deposit_npc_started = true
	return _done(Callable(self, "_cleanup_deposit"))


func _move_npc_to(anchor_id: String) -> Dictionary:
	var npc := _npc()
	var point: Variant = resolve_anchor(anchor_id)
	if npc == null or not point is Vector3:
		return _failed("绿苔移动目标锚点『%s』不可用，3.3 中止。" % anchor_id)
	if not npc.has_method("scripted_move_to"):
		return _failed("绿苔缺少 scripted_move_to()，3.3 中止。")
	if npc.has_method("clear_scripted_facing"):
		npc.call("clear_scripted_facing")
	if not bool(npc.call("scripted_move_to", point as Vector3, 3.2)):
		return _failed("绿苔拒绝脚本化移动，3.3 中止。")
	_move_target = point
	_move_anchor = anchor_id
	return _ok()


func _npc_gesture(name: String) -> Dictionary:
	var npc := _npc()
	if npc == null or not npc.has_method("scripted_gesture"):
		return _failed("绿苔缺少 scripted_gesture()，3.3 中止。")
	if not bool(npc.call("scripted_gesture", name)):
		return _failed("绿苔手势『%s』不可用，3.3 中止。" % name)
	return _ok()


func _commit_deposit() -> Dictionary:
	if not _npc_at_anchor("pedestal_stand") or _key_visual == null or not bool(_key_visual.call("is_insertion_complete")):
		return _failed("绿苔或钥匙尚未到插入接触点，拒绝安装事务。")
	var base := _root_service("BaseManager")
	if base == null or not base.has_method("deposit_main_story_key"):
		return _failed("BaseManager.deposit_main_story_key 不可用，3.3 中止。")
	var result: Variant = base.call("deposit_main_story_key", KEY_RARE_EARTH)
	if not result is Dictionary:
		return _failed("钥匙安装返回值不是 Dictionary，3.3 中止。")
	var output := result as Dictionary
	if not bool(output.get("success", false)):
		return _failed("钥匙安装未提交成功：%s" % str(output.get("reason", "unknown")))
	_deposit_succeeded = true
	var pedestal := _pedestal()
	if pedestal != null:
		pedestal.call("apply_main_story_key_visual", KEY_RARE_EARTH)
	_key_visual.hide()
	return _ok()


func _release_deposit() -> Dictionary:
	_cleanup_deposit()
	return _ok()


func _release_briefing() -> void:
	var npc := _npc()
	if _briefing_npc_started and npc != null and npc.has_method("end_scripted_appearance"):
		npc.call("end_scripted_appearance")
	_briefing_npc_started = false


func _resolve_meet_position(player: Node3D, npc: Node3D) -> Variant:
	var toward := npc.global_position - player.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.001:
		toward = -player.global_basis.z
	var room := _main_story_room(FACILITY_ROOM_ID)
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.57, -1.57, 3.14]:
		var point := player.global_position + toward.normalized().rotated(Vector3.UP, float(angle)) * 1.1
		point.y = npc.global_position.y
		if room != null and room.has_method("is_narrative_floor_position_valid"):
			if not bool(room.call("is_narrative_floor_position_valid", point)):
				continue
		return point
	return null


func _cleanup_deposit() -> void:
	_player_meet_anchor = null
	_move_target = null
	_move_anchor = ""
	if is_instance_valid(_key_visual):
		_key_visual.call("cleanup_performance")
		_key_visual.queue_free()
	_key_visual = null
	var npc := _npc()
	if _deposit_npc_started and npc != null and npc.has_method("end_scripted_appearance"):
		npc.call("end_scripted_appearance")
	_deposit_npc_started = false


func _key_action(action: String, params: Dictionary) -> Dictionary:
	if not is_instance_valid(_key_visual):
		return _failed("3.3 临时钥匙已丢失。")
	if action == "present" and not _npc_at_anchor("player_front"):
		return _failed("绿苔未到玩家身前，拒绝空交接。")
	if not bool(_key_visual.call("perform", action, params)):
		return _failed("钥匙动作『%s』缺少真实手部挂点或前置状态。" % action)
	return _ok()


func _npc_at_anchor(anchor_id: String) -> bool:
	var npc := _npc()
	var point: Variant = resolve_anchor(anchor_id)
	if npc == null or not point is Vector3:
		return false
	var offset: Vector3 = npc.global_position - (point as Vector3)
	offset.y = 0.0
	return offset.length() <= 0.24


## 导演在 tick 镜头之后、推进时间和每条 cue 派发之后都查询。
## 这里只判定；移动、手部动画、钥匙轨迹由各实体表现脚本负责。
func should_advance_narrative() -> bool:
	var director := _director()
	if director != null and str(director.call("active_id")) == BRIEFING_ID:
		var walking_player := _player()
		if walking_player != null and float(walking_player.get("_narrative_walk_remaining")) > 0.0:
			return false
	if _deposit_npc_started and (_npc() == null or _player() == null or _pedestal() == null or not is_instance_valid(_key_visual)):
		_abort_performance("安装演出中演员、设施或钥匙丢失")
		return false
	if director != null and str(director.call("active_id")) == BOSS_ID and _activation_requested:
		return _activation_is_complete()
	if _move_target is Vector3:
		var npc := _npc()
		if npc == null:
			_abort_performance("移动中绿苔丢失")
			return false
		var offset: Vector3 = npc.global_position - (_move_target as Vector3)
		offset.y = 0.0
		var snapshot: Dictionary = npc.call("get_snapshot")
		if bool(snapshot.get("scripted_moving", snapshot.get("moving", false))) or offset.length() > 0.24:
			return false
		_move_target = null
		_move_anchor = ""
	if is_instance_valid(_key_visual) and bool(_key_visual.call("is_busy")):
		return false
	return true


func _abort_performance(reason: String) -> void:
	_performance_fault = reason
	_diagnostics.append(reason)
	var director := _director()
	if director != null:
		director.call_deferred("abort", "main_story_performance:" + reason)


func _pedestal() -> Node3D:
	if _host != null and _host.has_method("get_main_story_pedestal"):
		var node: Variant = _host.call("get_main_story_pedestal")
		if node is Node3D and is_instance_valid(node):
			return node as Node3D
	var facility := _main_story_facility(FACILITY_ID)
	if facility != null:
		for child in facility.get_children():
			if child.has_method("get_anchor") and child.has_method("apply_main_story_key_visual"):
				return child as Node3D
	return null


func _exit_tree() -> void:
	var director := _director()
	if director != null and str(director.call("active_id")) in [BRIEFING_ID, BOSS_ID, DEPOSIT_ID]:
		director.call("abort", "main_story_controller_unloaded")
	_release_briefing()
	_cleanup_deposit()
	_release_control()
	_release_boss_hold()


func should_return_boss_control() -> bool:
	var director := _director()
	if not _activation_requested or _boss_control_released or director == null or str(director.call("active_id")) != BOSS_ID:
		return false
	var snapshot := _activation_snapshot()
	var elapsed := float(snapshot.get("elapsed", snapshot.get("activation_elapsed", 0.0)))
	return elapsed >= BOSS_CONTROL_RETURN_SECONDS


func should_restore_boss_camera() -> bool:
	return _activation_requested and float(_activation_snapshot().get("elapsed", 0.0)) >= 4.4


func _sync_activation_control() -> void:
	if not _activation_requested or _boss_control_released:
		return
	var director := _director()
	if director == null or str(director.call("active_id")) != BOSS_ID:
		return
	if should_restore_boss_camera() and not _boss_camera_return_requested:
		if director.has_method("restore_main_story_camera"):
			director.call("restore_main_story_camera", 1.0)
			_boss_camera_return_requested = true
	if should_return_boss_control():
		if director.has_method("release_main_story_control"):
			director.call("release_main_story_control")
			_release_control()
			_boss_control_released = true
			if _host.has_method("refresh_player_input_lock"):
				_host.call("refresh_player_input_lock")


func _activation_is_complete() -> bool:
	var snapshot := _activation_snapshot()
	return bool(snapshot.get("completed", snapshot.get("activation_completed", false)))


func _activation_snapshot() -> Dictionary:
	var boss := _activation_enemy if _activation_enemy != null and is_instance_valid(_activation_enemy) else _boss()
	if boss == null or not boss.has_method("get_story_activation_snapshot"):
		return {}
	var result: Variant = boss.call("get_story_activation_snapshot")
	return result as Dictionary if result is Dictionary else {}


func _boss_is_lost() -> bool:
	if _activation_enemy == null or not is_instance_valid(_activation_enemy):
		return true
	if bool(_activation_snapshot().get("completed", false)):
		return false
	var state := str(_activation_enemy.get("ai_state"))
	return state == "dead" or int(_activation_enemy.get("current_hp")) <= 0


func _is_briefing_ready() -> bool:
	if _completed(BRIEFING_ID) or not _is_player_in_facility():
		return false
	if not _facility_light_is_on():
		return false
	var npc := _npc()
	var player := _player()
	return npc != null and player != null and npc.global_position.distance_to(player.global_position) <= BRIEFING_DISTANCE_M


func _is_boss_ready() -> bool:
	if _completed(BOSS_ID) or not _is_boss_room():
		return false
	var boss := _boss()
	if boss == null or not is_instance_valid(boss):
		return false
	var activation: Variant = boss.call("get_story_activation_snapshot") if boss.has_method("get_story_activation_snapshot") else {}
	if activation is Dictionary and bool((activation as Dictionary).get("completed", false)):
		return false
	return true


func _is_deposit_ready() -> bool:
	if _completed(DEPOSIT_ID) or not _is_player_in_facility():
		return false
	var snapshot := _main_story_snapshot()
	if not _key_is_acquired(snapshot) or _key_is_deposited(snapshot):
		return false
	var rescue: Variant = _host.call("find_base_rescue") if _host.has_method("find_base_rescue") else null
	if rescue != null and is_instance_valid(rescue):
		if rescue.has_method("is_holding_player_input") and bool(rescue.call("is_holding_player_input")):
			return false
		if rescue.has_method("get_phase_name") and str(rescue.call("get_phase_name")) == "cutscene":
			return false
	return _npc() != null


func _is_modal_or_unavailable() -> bool:
	if _host == null or not is_instance_valid(_host):
		return true
	if _host.has_method("get_active_facility_menu") and _host.call("get_active_facility_menu") != null:
		return true
	var director := _director()
	return director != null and bool(director.call("is_player_input_locked"))


func _is_player_in_facility() -> bool:
	if _host.has_method("is_player_inside_facility"):
		return bool(_host.call("is_player_inside_facility"))
	return _current_room_id() == FACILITY_ROOM_ID


func _is_boss_room() -> bool:
	var current := _current_room_id()
	if current == BOSS_ROOM_ID:
		return true
	var room := _main_story_room(BOSS_ROOM_ID)
	var player := _player()
	return room != null and player != null and room.has_method("contains_world_position") and bool(room.call("contains_world_position", player.global_position))


func _facility_light_is_on() -> bool:
	var room := _main_story_room(FACILITY_ROOM_ID)
	if room == null:
		return false
	if room.has_method("is_room_light_on"):
		return bool(room.call("is_room_light_on"))
	var state := _find_light_state(room)
	return bool(state.get("found", false)) and bool(state.get("on", false))


func _find_light_state(node: Node) -> Dictionary:
	if node.has_method("is_light_on"):
		return {"found": true, "on": bool(node.call("is_light_on"))}
	for child in node.get_children():
		var found := _find_light_state(child)
		if bool(found.get("found", false)):
			return found
	return {"found": false, "on": false}


func _completed(narrative_id: String) -> bool:
	var base := _root_service("BaseManager")
	if base != null and base.has_method("has_narrative_completed") and bool(base.call("has_narrative_completed", narrative_id)):
		return true
	var snapshot := _main_story_snapshot()
	for key in ["completed", "chapters", "narratives", "history"]:
		var value: Variant = snapshot.get(key, {})
		if value is Dictionary and bool((value as Dictionary).get(narrative_id, false)):
			return true
	return bool(snapshot.get(narrative_id, false))


func _key_is_acquired(snapshot: Dictionary) -> bool:
	var keys: Variant = snapshot.get("keys", {})
	if keys is Dictionary:
		var row: Variant = (keys as Dictionary).get(KEY_RARE_EARTH, {})
		if row is Dictionary:
			var state := str((row as Dictionary).get("state", ""))
			return state in ["acquired", "deposited"] or bool((row as Dictionary).get("acquired", false))
	return bool(snapshot.get("rare_earth_acquired", false))


func _key_is_deposited(snapshot: Dictionary) -> bool:
	var keys: Variant = snapshot.get("keys", {})
	if keys is Dictionary:
		var row: Variant = (keys as Dictionary).get(KEY_RARE_EARTH, {})
		if row is Dictionary:
			var state := str((row as Dictionary).get("state", ""))
			return state == "deposited" or bool((row as Dictionary).get("deposited", false))
	return bool(snapshot.get("rare_earth_deposited", false))


func _main_story_snapshot() -> Dictionary:
	var base := _root_service("BaseManager")
	if base != null and base.has_method("get_main_story_snapshot"):
		var result: Variant = base.call("get_main_story_snapshot")
		return result as Dictionary if result is Dictionary else {}
	return {}


func _current_room_id() -> String:
	if _host == null:
		return ""
	if _host.has_method("get_current_room_id"):
		return str(_host.call("get_current_room_id"))
	var value: Variant = _host.get("current_room")
	if value is String:
		return value as String
	if value is Node:
		return str((value as Node).get("room_id"))
	return str(_host.get("current_room_id"))


func _player() -> Node3D:
	if _host != null:
		var value: Variant = _host.get("player")
		if value is Node3D and is_instance_valid(value):
			return value as Node3D
	return get_tree().get_first_node_in_group("player_3d") as Node3D


func _npc() -> Node3D:
	if _host != null and _host.has_method("find_npc"):
		return _host.call("find_npc", NPC_ID) as Node3D
	return null


func _boss() -> Node3D:
	if _host != null and _host.has_method("get_main_story_boss"):
		return _host.call("get_main_story_boss") as Node3D
	return null


func _main_story_room(room_id: String) -> Node3D:
	if _host != null and _host.has_method("get_main_story_room"):
		return _host.call("get_main_story_room", room_id) as Node3D
	return null


func _main_story_facility(facility_id: String) -> Node3D:
	if _host != null and _host.has_method("get_main_story_facility"):
		return _host.call("get_main_story_facility", facility_id) as Node3D
	return null


func _director() -> Node:
	return _root_service("NarrativeDirector")


func _root_service(service_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(NodePath(service_name))


static func _ok() -> Dictionary:
	return {"ok": true, "degraded": false, "reason": "", "restore": Callable()}


static func _done(restore: Callable) -> Dictionary:
	return {"ok": true, "degraded": false, "reason": "", "restore": restore}


static func _failed(reason: String) -> Dictionary:
	return {"ok": false, "degraded": false, "reason": reason, "restore": Callable()}


static func _degraded(reason: String) -> Dictionary:
	return {"ok": false, "degraded": true, "reason": reason, "restore": Callable()}


static func _domain_result(result: Dictionary, fallback: String) -> Dictionary:
	if bool(result.get("success", false)):
		return _ok()
	return _failed("%s %s" % [fallback, str(result.get("reason", "unknown"))])
