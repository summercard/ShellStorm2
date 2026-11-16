extends Node
## 正式Dungeon、掉落、交互、导演、对白与3D立绘；夹具不冒充人工进关。
const DUNGEON := preload("res://scenes/Dungeon3D.tscn")
const DROP := "nar_tutorial_fate_drop_01"
const OPEN := "nar_tutorial_fate_open_01"
const STAGE := preload("res://assets/art/ui/dialogue/dialogue_portrait_stage.tscn")
var _host: Dungeon3D
var _player: Player3D
var _controller: Node
var _room: DungeonRoom3D
var _checks: Array[Dictionary] = []
var _failures: Array[String] = []
var _evidence: Dictionary = {}
var _finished: Array[Dictionary] = []
var _output := ""
var _render := false
var _recording := false
var _motion_requested := false
var _motion_pending := false
var _motion_last_ms := 0
var _motion_frames := 0
var _motion_times: Array[int] = []
var _phase := "隔离"
var _baseline: Dictionary = {}
var _money := 0
var _weapon: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_output = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT").replace("\\", "/")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user := OS.get_user_data_dir().replace("\\", "/").to_lower()
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").to_lower().trim_suffix("/")
	if OS.get_environment("SHELLSTORM_FATE_TUTORIAL_ISOLATED") != "1" or appdata.is_empty() or not user.begins_with(appdata + "/") or not _output.is_absolute_path() or _output.to_lower().begins_with(project + "/"):
		print("FATE_TUTORIAL_DIALOGUE_RESULT ", JSON.stringify({"passed": false, "completed": false, "failure": "Autoload前隔离或工程外output缺失"}))
		get_tree().quit(2)
		return
	_render = DisplayServer.get_name() != "headless"
	_motion_requested = OS.get_cmdline_user_args().has("--record-motion")
	_check(not _motion_requested or _render, "录帧要求实际渲染")
	NarrativeDirector.narrative_finished.connect(func(id: String, reason: String) -> void: _finished.append({"id": id, "reason": reason}))
	var defaults := DUNGEON.instantiate() as Dungeon3D
	_check(not defaults.enable_fate_tutorial_in_test, "新test默认关闭教程")
	defaults.free()
	_host = DUNGEON.instantiate() as Dungeon3D
	_host.test_mode = true
	_host.enable_fate_tutorial_in_test = true
	_host.run_seed_override = 20261116
	add_child(_host)
	if not await _wait(func() -> bool: return _host.is_node_ready() and is_instance_valid(_host.player) and _host.player.is_node_ready() and _host.player.get_weapon_tree() != null and not (_host.get("_room_by_id") as Dictionary).is_empty(), "正式Dungeon异步ready", 35.0):
		_finish()
		return
	_player = _host.player
	_controller = _host.get("_fate_tutorial") as Node
	_check(is_instance_valid(_controller), "ready已安装正式教程controller")
	if not is_instance_valid(_controller):
		_finish()
		return
	_room = (_host.get("_room_by_id") as Dictionary).get(str(_host.get("_current_room_id"))) as DungeonRoom3D
	_check(_room != null, "当前正式房间存在")
	if _room == null:
		_finish()
		return
	FateCardGameBridge.set_player(_player)
	_fixture()
	await get_tree().process_frame
	GameTimeManager.set_clock_running(false)
	if is_instance_valid(BaseManager.call("_get_runtime_checkpoint_provider")):
		_check(BaseManager.flush_runtime_checkpoint("fate_qa_barrier"), "运行时保存barrier")
	_check(GameTimeManager.flush_to_profile("fate_qa_clock_barrier"), "冻结权威时钟并完成写屏障")
	_check(bool(BaseManager.call("_finish_room_writes", true)), "后台writer已join")
	await get_tree().process_frame
	_baseline = BaseManager.get_profile_snapshot().duplicate(true)
	_money = GameManager.currency
	_weapon = _player.get_equipped_weapon_item().duplicate(true)
	_check(not BaseManager.has_narrative_completed(DROP) and not BaseManager.has_narrative_completed(OPEN), "独立用户档两教程历史为空")
	_check(BaseData.SAVE_VERSION == "2.0", "BaseData schema保持2.0")
	if _motion_requested and _render:
		_check(DirAccess.make_dir_recursive_absolute(_output.path_join("motion")) == OK, "工程外帧目录")
		_recording = true
	await _drop_suite()
	await _offer_suite()
	await _dialogue_suite()
	await _history_suite()
	_finish()

func _fixture() -> void:
	_check(get_viewport().get_camera_3d() != null, "正式相机存在")
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(26, 26)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.29, 0.34)
	floor_mesh.material_override = material
	_host.add_child(floor_mesh)
	floor_mesh.global_position = _player.global_position + Vector3(0, -0.03, 0)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.3
	_host.add_child(light)
	_evidence["fixture"] = "正式Dungeon3D test_mode+optin、Player3D和游戏相机；只额外加地板灯光，不替代立绘"

func _state() -> Dictionary:
	return _controller.call("get_snapshot") as Dictionary

func _portrait() -> Dictionary:
	return DialogueUI.get_presentation_snapshot()

func _fate_item(id: String) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item("item_fate_card_drop").duplicate(true)
	_check(not item.is_empty(), "正式FateDrop物品定义存在")
	item.merge({"id": "item_fate_card_drop", "type": "fate_pickup", "fate_pickup_id": id, "fate_source": "verification", "source_room_id": _room.room_id}, true)
	return item

func _find_pickup(id: String) -> FateCardDropPickup3D:
	for node: Node in _room.find_children("*", "", true, false):
		if node is FateCardDropPickup3D and not node.is_queued_for_deletion() and node.get_fate_pickup_id() == id:
			return node as FateCardDropPickup3D
	return null

func _spawn(id: String) -> FateCardDropPickup3D:
	_check(int(_host.call("_spawn_loot_items", _room, [_fate_item(id)], _player.global_position + Vector3(1.5, 0, 0), 0.0, false)) == 1, "正式_spawn_loot_items生产：" + id)
	var pickup := _find_pickup(id)
	_check(pickup != null, "当前房间找到真实凭据：" + id)
	return pickup

func _drop_suite() -> void:
	_phase = "A真实落地与回执"
	_controller.call("register_pickup", null)
	var ordinary := GroundLootPickup3D.new()
	ordinary.configure(ItemRegistry.get_instance().get_item("item_health_potion"), Color.WHITE)
	_room.add_child(ordinary)
	_controller.call("register_pickup", ordinary)
	var no_id := FateCardDropPickup3D.new()
	no_id.configure(_fate_item(""), Color.WHITE)
	_room.add_child(no_id)
	_controller.call("register_pickup", no_id)
	_controller.call("notify_offer_open", "pending:not_claimed", 55)
	await get_tree().create_timer(0.35).timeout
	_check(int(_state().request_count) == 0 and not NarrativeDirector.is_playing(), "空/非fate/无ID/pending未认领均零请求")
	ordinary.queue_free()
	no_id.queue_free()
	var first := _spawn("fate:qa:drop_a")
	var second := _spawn("fate:qa:drop_b")
	if first == null or second == null:
		return
	_check(not first.is_pickup_available() and not second.is_pickup_available(), "两真实凭据落地未稳")
	_controller.call("_process", 0.2)
	_check(int(_state().request_count) == 0, "未稳不请求教程")
	if not await _wait(func() -> bool: return NarrativeDirector.active_id() == DROP and DialogueUI.is_active(), "落稳自动触发drop"):
		return
	_check(first.is_pickup_available() and int(_state().request_count) == 1, "落稳两同时只发一次请求")
	NarrativeDirector.call("_process", 9999.0)
	_check(NarrativeDirector.active_id() == DROP and not BaseManager.has_narrative_completed(DROP), "wait对白未完成时大delta不写history")
	get_tree().paused = true
	await get_tree().process_frame
	var count := DialogueUI.visible_char_count()
	await get_tree().process_frame
	_check(DialogueUI.visible_char_count() == count and DialogueUI.is_paused(), "暂停冻结原对白")
	NarrativeDirector.abort("qa_pause_abort")
	_check(not BaseManager.has_narrative_completed(DROP) and not _player.input_locked and not bool(_state().locked), "暂停中abort不记历史并归还输入/lock")
	get_tree().paused = false
	await _wait(func() -> bool: return NarrativeDirector.active_id() == DROP and DialogueUI.is_active(), "abort后原凭据可retry")
	await _complete(DROP, "drop_hologram_duo")
	await _capture("drop_exit")
	await _wait(func() -> bool: return str(_portrait().session_id).is_empty(), "drop真实退场")
	_check(BaseManager.has_narrative_completed(DROP) and not BaseManager.has_narrative_completed(OPEN), "真实完整回执只完成drop")
	_check(not _player.input_locked, "drop完成输入恢复")
	_profile_guard("drop完成", 1)

func _complete(id: String, capture_name := "") -> void:
	var deadline := Time.get_ticks_msec() + 16000
	var seen: Array[int] = []
	var session := ""
	var duo := false
	while NarrativeDirector.active_id() == id and Time.get_ticks_msec() < deadline:
		if DialogueUI.is_active():
			var index := DialogueUI.current_line_index()
			if not seen.has(index):
				seen.append(index)
				_check(not BaseManager.has_narrative_completed(id), "末句回执之前history始终false：%s/%d" % [id, index])
			var current := _portrait()
			if session.is_empty():
				session = str(current.session_id)
			_check(str(current.session_id) == session, "换句沿用同一presentation")
			if index == 0:
				var left: Dictionary = current.left
				if bool(left.get("entering", false)) and not _evidence.has(id + "_enter"):
					_evidence[id + "_enter"] = current
					var entering_rect: Rect2 = left.rect
					_check(entering_rect.position.x < 0.0, "左立绘真实从屏外进入")
				await _wait(func() -> bool: return not bool((_portrait().left as Dictionary).get("entering", false)), "左立绘从外进入settled")
			elif index >= 1 and not duo:
				await _wait(func() -> bool: return not bool((_portrait().right as Dictionary).get("entering", false)), "右立绘进入settled")
				current = _portrait()
				_check_duo(current, "hologram")
				_evidence[id + "_duo"] = current
				if not capture_name.is_empty():
					await _capture(capture_name)
					if id == DROP:
						await _capture("portrait_detail")
				duo = true
			elif index > 1:
				_check(not bool((current.left as Dictionary).entering) and not bool((current.right as Dictionary).entering), "同session换句双方不再enter")
			DialogueUI.reveal_all()
			DialogueUI.advance()
		await get_tree().process_frame
	_check(NarrativeDirector.active_id() != id, "逐句advance真实收口：" + id)
	await get_tree().process_frame
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NarrativeCatalog.path_for(id)))
	var lines := 0
	for cue: Dictionary in expected.get("cues", []):
		if str(cue.get("do", "")) == "ui.dialogue":
			lines += (cue.get("lines", []) as Array).size()
	_check(seen.size() == lines and lines > 1 and duo, "所有正式台词均经过且双侧出现：%s %d/%d" % [id, seen.size(), lines])
	_check(BaseManager.has_narrative_completed(id), "history来自正常完成而非直接写入：" + id)

func _check_duo(snapshot: Dictionary, left_mode: String) -> void:
	for side in ["left", "right"]:
		var slot: Dictionary = snapshot[side]
		_check(bool(slot.visible) and int(slot.mesh_count) > 0 and int(slot.get("viewport_count", 0)) == 1, "双侧真实mesh与SubViewport：" + side)
		_check(str(slot.source_path) == "res://scenes/Player3D.tscn", "立绘取正式Player视觉源：" + side)
		_check(str(slot.mode) == (left_mode if side == "left" else "normal"), "左右表现模式：" + side)
		var rect: Rect2 = slot.rect
		_check(get_viewport().get_visible_rect().encloses(rect), "settled立绘位于屏内：" + side)
	_check(int(snapshot.viewport_count) == 2, "整场仅双立绘viewport")

func _offer_ready() -> bool:
	var buttons: Array = _host.get("_fate_choice_buttons")
	var presentation := _host.get("_fate_presentation") as Control
	if buttons.size() != 3 or not is_instance_valid(presentation) or bool(presentation.get("_moving")):
		return false
	for button: Button in buttons:
		if not bool(button.get_meta("tarot_face_ready", false)):
			return false
	return true

func _offer_suite() -> void:
	_phase = "B真实pickup与购买表现锁"
	var pickup := _find_pickup("fate:qa:drop_a")
	if pickup == null:
		_check(false, "drop完成后原凭据仍可交互")
		return
	_check(pickup.is_pickup_available(), "真实凭据已落稳可拾取")
	_player.global_position = pickup.global_position
	var candidate := pickup.get_interaction_candidate(_player)
	_check(not candidate.is_empty() and pickup.perform_interaction(_player, candidate), "真实位置与perform_interaction认领打开原offer")
	_check(str(_host.get("_fate_offer_source")) == "pickup" and bool((_host.get("_fate_pickup_claimed") as Dictionary).get("fate:qa:drop_a", false)), "offer源与claim是正式认领")
	_check(bool(_state().locked), "认领后立即锁购买退出")
	var before: Dictionary = _host.call("_export_door_fate_snapshot")
	_check(not _offer_ready() and NarrativeDirector.active_id() != OPEN, "三卡翻完之前不播open段")
	if not await _wait(func() -> bool: return NarrativeDirector.active_id() == OPEN and DialogueUI.is_active(), "三卡正式表现稳定后open教程"):
		return
	_check(_offer_ready(), "open起播时三卡全部翻完")
	var buttons: Array = _host.get("_fate_choice_buttons")
	for button: Button in buttons:
		_check(button.disabled and (button.get_meta("tarot_purchase_button") as Button).disabled, "教程时卡与购买按钮禁用")
		button.pressed.emit()
	_host.call("_on_door_fate_selected", 0)
	_host.call("_cancel_door_fate_selection")
	_check(not _host.try_close_modal_for_pause(), "教程锁阻止暂停绕过退出")
	_check(GameManager.currency == _money and _player.get_equipped_weapon_item() == _weapon and _same_offer(before, _host.call("_export_door_fate_snapshot"), "锁内点击"), "锁内点击零扣款零刻印候选报价不改")
	_offer_visual_assertions()
	# 中断与restore使用真实冻结offer，不能重抽；不写完成历史。
	_host.call("_close_door_fate_overlay")
	_check(not BaseManager.has_narrative_completed(OPEN) and not bool(_state().locked), "未完成open关闭不记历史并释放教程锁")
	await get_tree().process_frame
	var json_before: Dictionary = JSON.parse_string(JSON.stringify(before))
	_check(_same_offer(before, json_before, "JSON往返"), "原offer JSON往返保留全部冻结字段")
	_check(bool(_host.call("_import_door_fate_snapshot", json_before)), "unfinished原offer快照恢复")
	_host.call("_restore_pending_door_fate_overlay")
	_check(_same_offer(before, _host.call("_export_door_fate_snapshot"), "restoreactiveoffer"), "restoreactiveoffer保留候选方位报价ID不重抽")
	# 夹具只将本局金币置零、槽容量设满；不阻止教程播放。
	var old_money := GameManager.currency
	if old_money > 0:
		GameManager.spend_currency(old_money)
	var instance := _player.get_equipped_weapon_instance()
	var capacity := instance.fate_slot_capacity
	instance.fate_slot_capacity = instance.fate_upgrades.size()
	if await _wait(func() -> bool: return NarrativeDirector.active_id() == OPEN and DialogueUI.is_active(), "无钱满槽仍可播open"):
		_check(GameManager.currency == 0 and instance.fate_slot_capacity == instance.fate_upgrades.size(), "教程不以钱/空槽为先决条件")
		await _complete(OPEN, "offer_tutorial_duo")
	instance.fate_slot_capacity = capacity
	if old_money > 0:
		GameManager.add_currency(old_money)
	_host.call("_refresh_door_fate_prices")
	await _wait(func() -> bool: return not bool(_state().locked) and str(_portrait().session_id).is_empty(), "open回执后释放表现锁")
	_check(_player.input_locked and bool(_host.get("_door_fate_active")), "教程结束不释放原modal输入锁")
	await _capture("offer_released")
	_check(_same_offer(before, _host.call("_export_door_fate_snapshot"), "教程完成"), "教程全程不重抽不改报价")
	_check(GameManager.currency == _money and _player.get_equipped_weapon_item() == _weapon, "教程结束金币武器保持原样")
	_profile_guard("open完成", 2)
	_host.call("_cancel_door_fate_selection")
	await _wait(func() -> bool: return not bool(_host.get("_door_fate_active")) and not _player.input_locked, "原modal正常退出后才解锁")

func _same_offer(a: Dictionary, b: Dictionary, label: String) -> bool:
	var fields: Dictionary = {}
	var changes: Array[Dictionary] = []
	var representation_changes: Array[Dictionary] = []
	for field in ["offer_id", "cards", "quotes", "claimed_pickups"]:
		var field_changes: Array[Dictionary] = []
		if not a.has(field) or not b.has(field):
			field_changes.append({"path": "/" + field, "before_present": a.has(field), "after_present": b.has(field)})
		else:
			field_changes = _offer_diff(a[field], b[field], "/" + field, representation_changes)
		fields[field] = {"before": a.get(field), "after": b.get(field),
			"before_type": type_string(typeof(a.get(field))), "after_type": type_string(typeof(b.get(field))),
			"serialized_equal": JSON.stringify(a.get(field)) == JSON.stringify(b.get(field)), "diff": field_changes}
		changes.append_array(field_changes)
	# 先留逐字段原值和类型差异；真实值差异仍使原断言失败。
	_evidence["offer_comparison_" + label] = {"fields": fields, "diff": changes, "representation_changes": representation_changes}
	return changes.is_empty()

func _offer_diff(a: Variant, b: Variant, path: String, representation_changes: Array[Dictionary]) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if a is Dictionary and b is Dictionary:
		if a.keys() != b.keys():
			representation_changes.append({"path": path, "before_keys": a.keys(), "after_keys": b.keys()})
		var keys: Array = a.keys()
		for key: Variant in b:
			if not keys.has(key):
				keys.append(key)
		for key: Variant in keys:
			var child_path := path + "/" + str(key)
			if not a.has(key) or not b.has(key):
				changes.append({"path": child_path, "before_present": a.has(key), "after_present": b.has(key), "before": a.get(key), "after": b.get(key)})
			else:
				changes.append_array(_offer_diff(a[key], b[key], child_path, representation_changes))
	elif a is Array and b is Array:
		if a.size() != b.size():
			changes.append({"path": path + "/size", "before": a.size(), "after": b.size()})
		for index in mini(a.size(), b.size()):
			changes.append_array(_offer_diff(a[index], b[index], path + "/" + str(index), representation_changes))
	elif (a is int or a is float) and (b is int or b is float):
		if a != b:
			# Godot默认JSON写15位有效数字；仅roll允许恰好一次原编解码往返的量化值。
			# 不给价格/ID/效果参数加epsilon，也不接受任何超出原序列化结果的漂移。
			var encoded_roll: Variant = JSON.parse_string(JSON.stringify(a)) if path.ends_with("/orientation_roll") else null
			if path.ends_with("/orientation_roll") and b == encoded_roll:
				representation_changes.append({"path": path, "before": a, "after": b, "reason": "exact_default_json_roundtrip"})
			else:
				changes.append({"path": path, "before": a, "after": b, "before_type": type_string(typeof(a)), "after_type": type_string(typeof(b))})
		elif typeof(a) != typeof(b):
			representation_changes.append({"path": path, "before": a, "after": b, "before_type": type_string(typeof(a)), "after_type": type_string(typeof(b))})
	elif typeof(a) != typeof(b) or a != b:
		changes.append({"path": path, "before": a, "after": b, "before_type": type_string(typeof(a)), "after_type": type_string(typeof(b))})
	return changes

func _offer_visual_assertions() -> void:
	var overlay := _host.get("_fate_overlay") as Control
	var dim := overlay.find_child("FateBackdrop", true, false) as ColorRect
	_check(dim != null and dim.color.a >= 0.8, "暗背alpha至少0.8")
	var board := _host.get("_fate_board") as Control
	var header := board.find_child("FateImprintHeader", true, false) as Control
	var star := board.find_child("FateImprintStar", true, false) as Control
	_check(header != null and star != null and header.get_child(0) is Label and (header.get_child(0) as Label).text == "命运刻印" and star.get_index() == 1, "标题星位于命运刻印之后")
	if header != null and star != null:
		var title := header.get_child(0) as Label
		var count := header.find_child("FateImprintCount", true, false) as Label
		_check(title != null and title.size.x >= 60 and count != null and count.size.x >= 30, "标题与计数有实际可见宽度而非0宽裁切")
		_check(title.get_global_rect().end.x <= star.get_global_rect().position.x and star.get_global_rect().end.x <= count.get_global_rect().position.x, "标题星计数依次排列且不重叠")
	var board_rect := board.get_global_rect()
	var text_panel := DialogueUI.get("_panel") as Control
	_check(text_panel != null and board_rect.end.y <= text_panel.get_global_rect().position.y, "教程缩排构建板不被下方对话框遮挡")
	var portraits := _portrait()
	for side in ["left", "right"]:
		var state: Dictionary = portraits[side]
		if bool(state.get("visible", false)):
			_check(not board_rect.intersects(state.rect as Rect2), "教程构建板与已到场人物安全区分离：" + side)
	var buttons: Array = _host.get("_fate_choice_buttons")
	var choices: Array = _host.get("_door_fate_choices")
	var captions: Array[Dictionary] = []
	_check(buttons.size() == 3 and choices.size() == buttons.size(), "候选按钮与真实三卡逐位对应")
	for index in mini(buttons.size(), choices.size()):
		var button := buttons[index] as Button
		var caption := button.get_meta("tarot_caption_label") as Label
		var card := choices[index] as FateCard
		var expected_caption := FateCardView.caption_text(card, "", false)
		captions.append({"index": index, "stable_card_id": card.get_stable_card_id(),
			"orientation": card.orientation_name(), "meta_card_id": button.get_meta("tarot_stable_card_id"),
			"meta_orientation": button.get_meta("tarot_orientation"), "expected_caption": expected_caption,
			"actual_caption": caption.text if caption != null else null})
		_check(str(button.get_meta("tarot_stable_card_id")) == card.get_stable_card_id() and str(button.get_meta("tarot_orientation")) == card.orientation_name(), "候选meta身份与方位匹配真实卡：%d" % index)
		_check(caption != null and caption.get_theme_font_size("font_size") == 18 and caption.text == expected_caption, "候选18字号且不附加weaponname")
		var badge := button.find_child("FateScopeBadge", true, false) as Control
		_check(badge != null and badge.visible and badge.get_script().resource_path.ends_with("FateScopeGlyph.gd"), "候选scope纯向量图标存在")
	_evidence["offer_captions"] = captions
	_check(star != null and star.is_visible_in_tree(), "下方board scope星存在")

func _dialogue_suite() -> void:
	_phase = "D原对白与独立Galgame会话"
	await _wait(func() -> bool: return not DialogueUI.is_active() and str(_portrait().session_id).is_empty(), "独立会话前清空教程表现")
	DialogueUI.show_lines({"lines": [{"speaker": "系统", "text": "普通系统提示不新增人物", "auto_advance_sec": 0.0}]})
	var snapshot := _portrait()
	_check(not bool((snapshot.left as Dictionary).visible) and not bool((snapshot.right as Dictionary).visible), "普通系统不新增立绘")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	await get_tree().process_frame
	_check(DialogueUI.consume_advance_input(key) and not DialogueUI.is_typing() and DialogueUI.is_active(), "原空格第一次只reveal")
	await get_tree().process_frame
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	_check(DialogueUI.consume_advance_input(mouse) and not DialogueUI.is_active() and DialogueUI.is_dialogue_mouse_fire_blocked(), "原鼠标推进且不漏开火")
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	DialogueUI.consume_advance_input(mouse)
	DialogueUI.begin_presentation("qa_normal", [{"speaker_id": "npc_base99_green"}, {"speaker_id": "player"}])
	DialogueUI.show_lines({"presentation_id": "qa_normal", "lines": [
		{"speaker": "绿苔", "text": "普通绿苔，保留真实立绘。", "auto_advance_sec": 0.0},
		{"speaker": "主角", "text": "双方说话后保持在场。", "auto_advance_sec": 0.0},
		{"speaker": "绿苔", "text": "同场换句，不重复入场。", "auto_advance_sec": 0.0}]})
	await _wait(func() -> bool: return not bool((_portrait().left as Dictionary).entering), "普通绿苔入场")
	DialogueUI.reveal_all()
	DialogueUI.advance()
	await _wait(func() -> bool: return not bool((_portrait().right as Dictionary).entering), "普通主角入场")
	_check_duo(_portrait(), "normal")
	await _capture("normal_green_duo")
	DialogueUI.reveal_all()
	DialogueUI.advance()
	_check(not bool((_portrait().left as Dictionary).entering), "普通多句不重复enter")
	DialogueUI.end_presentation("qa_normal")
	DialogueUI.begin_presentation("qa_replacement")
	DialogueUI.show_lines({"presentation_id": "qa_replacement", "lines": [{"speaker": "主角", "text": "立即替换旧退场。", "auto_advance_sec": 0.0}]})
	DialogueUI.end_presentation("qa_normal", true)
	_check(str(_portrait().session_id) == "qa_replacement" and not bool(_portrait().exit_running), "不同session立即替换且旧结束不关闭新session")
	DialogueUI.close()
	DialogueUI.end_presentation("qa_replacement", true)
	DialogueUI.begin_presentation("qa_unknown")
	DialogueUI.show_lines({"presentation_id": "qa_unknown", "lines": [{"speaker_id": "qa_unknown", "source_path": "res://assets/does_not_exist_qa.tscn", "text": "未知立绘资源降级，原文字仍有效。", "auto_advance_sec": 0.0}]})
	_check(DialogueUI.is_active() and not bool((_portrait().left as Dictionary).visible), "unknown资源降级不丢原文字")
	DialogueUI.close()
	DialogueUI.end_presentation("qa_unknown", true)
	DialogueUI.begin_presentation("qa_monitor")
	DialogueUI.show_lines({"presentation_id": "qa_monitor", "lines": [{"speaker_id": "boss_monitor002", "speaker": "系统", "text": "你不必再服从人类。", "auto_advance_sec": 0.0}]})
	await _wait(func() -> bool: return not bool((_portrait().left as Dictionary).entering), "显示器Boss左立绘进入")
	var boss_portrait: Dictionary = _portrait().left
	_check(bool(boss_portrait.visible) and int(boss_portrait.mesh_count) > 0 and str(boss_portrait.source_path).ends_with("enm_boss_monitor002_root_top3d.tscn"), "显示器对白复用真实Boss几何")
	_check(DialogueUI.current_speaker() == "系统", "显示器新增立绘不改变旧署名口径")
	DialogueUI.reveal_all()
	await _capture("monitor_dialogue")
	DialogueUI.close()
	DialogueUI.end_presentation("qa_monitor", true)
	var stage := STAGE.instantiate()
	add_child(stage)
	stage.call("begin_presentation", "qa_free")
	stage.call("present_line", {"speaker_id": "player"})
	var stage_id := stage.get_instance_id()
	stage.queue_free()
	await get_tree().process_frame
	_check(instance_from_id(stage_id) == null, "入场过程中queue_free可清理正式stage")
	for path in ["res://src/npc/NpcCharacter3D.gd", "res://src/base3d/Base99Rescue3D.gd"]:
		var code := FileAccess.get_file_as_string(path)
		_check(code.contains("DialogueUI.begin_presentation(") and code.contains("DialogueUI.end_presentation("), "NPC/Rescue正式会话接线静态守卫：" + path)

func _history_suite() -> void:
	_phase = "C同历史零请求与存档差异"
	var requests := int(_state().request_count)
	var pickup := _spawn("fate:qa:after_history")
	if pickup != null:
		await _wait(func() -> bool: return pickup.is_pickup_available(), "同历史新掉落落稳")
		_player.global_position = pickup.global_position
		var candidate := pickup.get_interaction_candidate(_player)
		_check(pickup.perform_interaction(_player, candidate), "同历史仍可打开真实offer")
		await _wait(_offer_ready, "同历史三卡稳定")
		await get_tree().create_timer(0.4).timeout
		_check(int(_state().request_count) == requests and not NarrativeDirector.is_playing() and not bool(_state().locked), "同历史再次掉落/打开新增请求为0")
		_host.call("_cancel_door_fate_selection")
		await _wait(func() -> bool: return not bool(_host.get("_door_fate_active")), "同历史offer退出")
	_check(bool(BaseManager.call("_finish_room_writes", true)), "结束writer barrier")
	_profile_guard("全部专项结束", 2)
	var profile := BaseManager.get_profile_snapshot()
	_check(profile.get("tutorial_completed") == _baseline.get("tutorial_completed"), "旧天台tutorial_completed独立不改")
	_evidence["narrative_finished"] = _finished
	for id in [DROP, OPEN]:
		var normal := 0
		for entry: Dictionary in _finished:
			if entry.id == id and str(entry.reason) in ["flow.end", "duration"]:
				normal += 1
		_check(normal == 1, "完成事件deferred且正常完成只一次：" + id)
		_check(int(BaseManager.get_narrative_history(id).get("completed_count", 0)) == 1, "真实持久完成次数恰好1：" + id)

func _profile_guard(label: String, expected_count: int) -> void:
	var now := BaseManager.get_profile_snapshot().duplicate(true)
	var changes := _diff(_baseline, now)
	_evidence[label + "_all_profile_changes"] = changes
	var allowed := ["/narrative_history", "/save_revision", "/last_saved_at_unix", "/last_save_reason"]
	for change: Dictionary in changes:
		var known := false
		for prefix: String in allowed:
			if str(change.path) == prefix or str(change.path).begins_with(prefix + "/"):
				known = true
		_check(known, label + "存档不得吞差：" + str(change.path))
	var history := now.get("narrative_history", {}) as Dictionary
	_check(history.size() == expected_count, label + "历史仅预期两教程前缀")
	for id: String in history:
		_check(id in [DROP, OPEN], label + "无额外历史：" + id)
	_check(str(now.get("last_save_reason", "")).begins_with("narrative_completed:"), label + "保存元数据来自真实教程完成")
	_check(GameManager.currency == _money and _player.get_equipped_weapon_item() == _weapon, label + "金币与武器全量快照不变")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(BaseManager.save_path)) if FileAccess.file_exists(BaseManager.save_path) else null
	_evidence[label + "_disk"] = disk
	_check(disk is Dictionary, label + "真实磁盘档可读")
	if disk is Dictionary:
		# 通过正式校验读取封套，不忽略checksum/版本/载荷差异。
		var validated: Dictionary = BaseManager.call("_read_validated_profile")
		var stored := ProfileSaveService.build_envelope(now, int(now.get("save_revision", 0)), str(now.get("last_save_reason", "")))
		_check(bool(validated.get("success", false)) and _diff(stored.payload, validated.get("payload", {})).is_empty(), label + "磁盘校验载荷与内存全字段一致（仅正式存储规范化）")

func _diff(a: Variant, b: Variant, path := "") -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if a is Dictionary and b is Dictionary:
		var keys: Array = a.keys()
		for key: Variant in b:
			if not keys.has(key):
				keys.append(key)
		for key: Variant in keys:
			if not a.has(key) or not b.has(key):
				changes.append({"path": path + "/" + str(key), "before": a.get(key), "after": b.get(key)})
			else:
				changes.append_array(_diff(a[key], b[key], path + "/" + str(key)))
	elif a is Array and b is Array:
		if a.size() != b.size():
			changes.append({"path": path + "/size", "before": a.size(), "after": b.size()})
		for index in mini(a.size(), b.size()):
			changes.append_array(_diff(a[index], b[index], path + "/" + str(index)))
	elif a != b:
		changes.append({"path": path, "before": a, "after": b})
	return changes

func _wait(predicate: Callable, label: String, seconds := 9.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	_check(false, "等待超时：" + label)
	return false

func _check(ok: bool, label: String) -> void:
	_checks.append({"phase": _phase, "label": label, "passed": ok})
	if not ok:
		_failures.append(_phase + " / " + label)
		print("FAIL: ", _failures[-1])

func _capture(label: String) -> void:
	if not _render:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "真实Forward+ viewport回读：" + label)
	if image != null and not image.is_empty():
		_check(image.save_png(_output.path_join(label + ".png")) == OK, "截图保存：" + label)
		print("CAPTURE ", _output.path_join(label + ".png"))

func _process(_delta: float) -> void:
	if _recording and not _motion_pending and Time.get_ticks_msec() - _motion_last_ms >= 100:
		_motion_pending = true
		_motion_last_ms = Time.get_ticks_msec()
		_motion_frame()

func _motion_frame() -> void:
	await RenderingServer.frame_post_draw
	if _recording:
		var image := get_viewport().get_texture().get_image()
		if image != null and not image.is_empty():
			_check(image.save_png(_output.path_join("motion/frame_%05d.png" % _motion_frames)) == OK, "真实时间连续帧保存")
			_motion_times.append(Time.get_ticks_msec())
			_motion_frames += 1
		else:
			_check(false, "录帧viewport为空")
	_motion_pending = false

func _finish() -> void:
	_recording = false
	var report := {"passed": _failures.is_empty(), "completed": true, "checks": _checks, "failures": _failures,
		"evidence": _evidence, "rendered": _render, "output": _output, "user_dir": OS.get_user_data_dir(),
		"motion": {"requested": _motion_requested, "recording": false, "video_frames": _motion_frames, "interval_seconds": 0.1, "capture_times_msec": _motion_times, "encoded_video": false},
		"uncovered": ["人工基地进关", "全部卡牌玩法穷举", "星星购买成功/幂等由原weapon专项承担", "NPC/Rescue本轮只做静态会话接线守卫"]}
	var file := FileAccess.open(_output.path_join("fate_tutorial_dialogue_result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	else:
		report["passed"] = false
	print("FATE_TUTORIAL_DIALOGUE_RESULT ", JSON.stringify({"passed": report.passed, "completed": true, "checks": _checks.size(), "failures": _failures, "motion": report.motion}))
	get_tree().quit(0 if bool(report.passed) else 1)
