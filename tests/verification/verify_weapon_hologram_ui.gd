extends Node

## 正式 Dungeon3D test_mode fixture；不冒充人工从基地进关的完整流程。
const DUNGEON := preload("res://scenes/Dungeon3D.tscn")
const PANEL := preload("res://scenes/WeaponAssemblyTreePanel.tscn")
const TRANSITION := preload("res://src/ui/weapon_build/WeaponHologramTransition.gd")
var _dungeon: Dungeon3D
var _player: Player3D
var _checks: Array[Dictionary] = []
var _failures: Array[String] = []
var _evidence: Dictionary = {}
var _output := ""
var _render := false
var _stage := "启动"
const MOTION_INTERVAL := 0.09
var _record_motion_requested := false
var _recording := false
var _motion_pending := false
var _motion_elapsed := 0.0
var _motion_frames := 0
var _motion_output := ""
var _motion_started_msec := 0
var _motion_duration := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("WEAPON_HOLOGRAM_VERIFY_ISOLATED") != "1":
		push_error("必须先隔离 APPDATA/custom_user_dir，再启动专项")
		get_tree().quit(2)
		return
	_output = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	var project_dir := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var output_dir := ProjectSettings.globalize_path(_output).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if not _output.is_absolute_path() or output_dir == project_dir or output_dir.begins_with(project_dir + "/"):
		push_error("证据目录必须显式指定且在工程外")
		get_tree().quit(2)
		return
	_render = DisplayServer.get_name() != "headless"
	_record_motion_requested = OS.get_cmdline_user_args().has("--record-motion")
	if _record_motion_requested:
		_check(_render, "连续帧采集禁止headless")
	_check(not _output.is_empty() and not ProjectSettings.globalize_path("user://").begins_with(ProjectSettings.globalize_path("res://")), "证据与用户档隔离")
	_checkpoint()
	var host_started := Time.get_ticks_msec()
	_dungeon = DUNGEON.instantiate() as Dungeon3D
	_dungeon.test_mode = true
	_dungeon.run_seed_override = 20261116
	add_child(_dungeon)
	if not await _wait(func() -> bool: return _dungeon.is_node_ready() and is_instance_valid(_dungeon.player) and _dungeon.player.is_node_ready() and _dungeon.player.get_weapon_tree() != null, "正式宿主异步ready与武器树就绪", 30.0):
		_finish()
		return
	# 先让宿主 deferred 初始化及首帧渲染完成，不把冷启动阻塞计入 K 动画。
	await get_tree().process_frame
	if _render:
		await RenderingServer.frame_post_draw
	await get_tree().process_frame
	_evidence["host_cold_start_seconds"] = (Time.get_ticks_msec() - host_started) / 1000.0
	_player = _dungeon.player
	FateCardGameBridge.set_player(_player)
	var extraction_before := BaseManager.get_extraction_points()
	_check(get_viewport().get_camera_3d() != null, "正式游戏背景相机存在")
	# test_mode 的起始房间偏暗；只给真实玩家背景添加显式验收地板与灯，不画替代UI。
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "VerificationFixtureFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(26, 26)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.29, 0.34)
	material.roughness = 0.9
	floor_mesh.material_override = material
	_dungeon.add_child(floor_mesh)
	floor_mesh.global_position = _player.global_position + Vector3(0, -0.03, 0)
	var light := DirectionalLight3D.new()
	light.name = "VerificationFixtureLight"
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.3
	_dungeon.add_child(light)
	_evidence["background_fixture"] = "正式Dungeon3D、Player3D、游戏相机；专项额外地板与照明"
	_check_effect_brief_catalog()
	await _check_board_and_k()
	await _check_purchases()
	await _check_compatibility_panels()
	_check(BaseManager.get_extraction_points() == extraction_before, "局外抽取点全程不变")
	_finish()

func _check(ok: bool, label: String) -> void:
	_checks.append({"stage": _stage, "label": label, "passed": ok})
	if not ok:
		_failures.append(_stage + " / " + label)
		print("FAIL: ", _failures[-1])
	_checkpoint()

func _set_stage(value: String) -> void:
	_stage = value
	print("QA_STAGE ", value)
	_checkpoint()

func _wait(predicate: Callable, label: String, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	_check(false, "等待超时：" + label)
	return false

func _panel_idle(panel: Control) -> bool:
	return not panel.has_meta(TRANSITION.TWEEN_KEY)

func _board_snapshot(board: Control) -> Dictionary:
	return board.call("get_presentation_snapshot") as Dictionary

func _check_inactive_back_palette(board: Control, label: String) -> void:
	var empty_count := 0
	var dark_palette_ok := true
	var occupied_unchanged := true
	for socket: Control in board.get("_sockets") as Array:
		if bool(socket.get("occupied")):
			var face := socket.find_child("SocketFace", true, false) as TextureRect
			occupied_unchanged = occupied_unchanged and face != null and face.material == null and face.modulate == Color.WHITE
			continue
		empty_count += 1
		var back := socket.find_child("TarotCardBack", true, false) as TextureRect
		if back == null or not back.material is ShaderMaterial:
			dark_palette_ok = false
			continue
		var material := back.material as ShaderMaterial
		var ink: Color = material.get_shader_parameter("ink_color")
		var base: Color = material.get_shader_parameter("base_color")
		var luma := ink.r * 0.2126 + ink.g * 0.7152 + ink.b * 0.0722
		dark_palette_ok = dark_palette_ok and luma <= 0.30 and ink.b >= ink.g and ink.g >= ink.r and ink.b - ink.r <= 0.12
		dark_palette_ok = dark_palette_ok and maxf(base.r, maxf(base.g, base.b)) <= 0.05 and is_equal_approx(ink.a, 1.0)
	_check(empty_count > 0 and dark_palette_ok, label + "空巢含下一槽使用低亮度灰蓝卡背")
	_check(occupied_unchanged, label + "已刻印卡面不附加压暗材质")

func _check_board_and_k() -> void:
	_set_stage("正式K页与8/10/12巢")
	var instance := _player.get_equipped_weapon_instance()
	_check(instance != null, "真实武器实例存在")
	if instance == null:
		return
	instance.fate_slot_capacity = 12
	instance.fate_upgrades.clear()
	var tree := _player.get_weapon_tree()
	var root := tree.get_root()
	var attachment := BlueprintRegistry.create_assembly_node("attach_big_mag")
	_check(attachment != null and tree.mount(root, AssemblyNode.SlotType.MAGAZINE, attachment), "真实可换配件装配")
	for card: FateCard in [FateCardPresets.overclock(), FateCardPresets.armor_pierce(), FateCardPresets.chain_lightning(), FateCardPresets.gun_on_gun()]:
		if card.get_stable_card_id() == FateCardPresets.armor_pierce().get_stable_card_id():
			card.set_orientation(FateCard.Orientation.REVERSED)
		# 每次正式提交都会重建运行树，不得复用上次提交前的 root。
		var source: AssemblyNode = _player.get_weapon_tree().get_root() if FateCardGameBridge.requires_source_selection(card) else null
		var result := FateCardGameBridge.apply_card(card, source)
		_check(bool(result.get("success", false)), "领域应用四种不同卡：" + card.get_stable_card_id())
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.physical_keycode = KEY_K
	key.pressed = true
	var k_cold_started := Time.get_ticks_msec()
	_start_motion()
	_dungeon.call("_unhandled_input", key)
	var panel := _dungeon.get("_weapon_panel") as WeaponAssemblyTreePanel
	_check(panel != null and panel.scene_file_path == PANEL.resource_path, "K入口实例化正式PackedScene")
	if panel == null:
		return
	_check(_player.input_locked, "K展开即时锁住玩家")
	var anchor := panel.pivot_offset
	var expected := TRANSITION._project_anchor(panel, _player)
	_check(anchor.distance_to(expected) < 1.0, "K动画锚点来自真实武器投影")
	var board := panel.get_build_board()
	_check(panel.is_node_ready() and board.is_node_ready() and board.is_inside_tree() and board.get("_weapon_tree") == _player.get_weapon_tree(), "K计时前正式board已ready并绑定当前树")
	# 首次可见的 SubViewport/卡面会冷渲染；只分离这一帧，不等待动画完成、不手动推进Tween。
	await get_tree().process_frame
	if _render:
		await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var k_timing: Dictionary = {"cold_entry_seconds": (Time.get_ticks_msec() - k_cold_started) / 1000.0,
		"animation_timeout_seconds": 8.0, "paused": get_tree().paused, "panel_process_mode": panel.process_mode,
		"idle_after_first_frame": _panel_idle(panel)}
	_evidence["k_timing"] = k_timing
	_checkpoint()
	var animation_started := Time.get_ticks_msec()
	var animation_finished := await _wait(func() -> bool: return _panel_idle(panel), "K展开动画完成")
	k_timing["animation_wait_seconds"] = (Time.get_ticks_msec() - animation_started) / 1000.0
	k_timing["completed"] = animation_finished
	if not animation_finished:
		var tween: Tween = panel.get_meta(TRANSITION.TWEEN_KEY) if panel.has_meta(TRANSITION.TWEEN_KEY) else null
		k_timing["tween_valid"] = tween != null and tween.is_valid()
		k_timing["tween_running"] = tween != null and tween.is_running()
		k_timing["tween_elapsed"] = tween.get_total_elapsed_time() if tween != null and tween.is_valid() else -1.0
	_checkpoint()
	_check(board.scene_file_path == "res://assets/art/ui/weapon_build/weapon_build_board.tscn", "正式共享board场景")
	var before := _player.get_equipped_weapon_item().duplicate(true)
	for capacity in [8, 10, 12]:
		_player.get_equipped_weapon_instance().fate_slot_capacity = capacity
		panel.refresh_from_owner()
		var snapshot := _board_snapshot(board)
		_check(int(snapshot.slot_count) == capacity and (snapshot.cards as Array).size() == capacity, "%d巢数量" % capacity)
		for entry: Dictionary in snapshot.cards:
			_check(bool(entry.shows_back) == (not bool(entry.occupied)), "%d巢卡面/空卡背：%d" % [capacity, int(entry.slot_index)])
		for segment: Dictionary in snapshot.flow_segments:
			_check(bool(segment.active) == (int(segment.to_slot) <= int(snapshot.used)), "flow只激活已刻印链路：%d/%d" % [capacity, int(segment.to_slot)])
	_player.get_equipped_weapon_instance().fate_slot_capacity = 12
	panel.refresh_from_owner()
	var snapshot := _board_snapshot(board)
	_check(int(snapshot.used) == 4, "四张不同卡已刻槽")
	_check(int(snapshot.branch_count) > 0, "真实挂枪分支可见")
	var preview := snapshot.preview as Dictionary
	_check(int(preview.get("mesh_count", 0)) > 0 and bool(preview.get("uses_world_model_factory", false)), "真实3D原枪模型工厂")
	var sockets := board.get("_sockets") as Array
	var reversed_face := (sockets[1] as Node).find_child("SocketFace", true, false) as TextureRect
	_check(reversed_face != null and reversed_face.texture != null and is_equal_approx(reversed_face.rotation, PI), "逆位真实贴图旋转180度")
	var empty_back := (sockets[11] as Node).find_child("TarotCardBack", true, false) as TextureRect
	_check(empty_back != null and empty_back.texture != null, "第12空巢真实卡背纹理")
	_check_inactive_back_palette(board, "K页")
	_check_socket_captions(board, "K页")
	var global_back_host := Control.new()
	add_child(global_back_host)
	var global_back := FateCardView.build_back_layer(global_back_host)
	_check(global_back != null and global_back.material == null and global_back.modulate == Color.WHITE, "全局翻牌卡背不受空巢暗色影响")
	global_back_host.queue_free()
	await _capture("k_build")
	board.call("ensure_slot_visible", 12)
	await _wait(func() -> bool:
		var scroll := board.get("_scroll") as ScrollContainer
		return scroll.get_global_rect().encloses(board.call("get_slot_global_rect", 12) as Rect2), "滚动第12槽进入裁剪区")
	_check(int(_board_snapshot(board).scroll_horizontal) > 0, "第12槽确实发生横向滚动")
	await _capture("k_slot12")
	board.call("refresh_from_owner")
	_check(before == _player.get_equipped_weapon_item(), "只读刷新与滚动不改变领域快照")
	var center := panel.get_global_rect().get_center()
	_check(center.distance_to(get_viewport().get_visible_rect().get_center()) < 2.0, "K页动画后居中")
	panel.hide_panel()
	_check(panel.visible and _player.input_locked, "K关闭动画结束前保持可见与输入锁")
	panel.show_panel()
	panel.hide_panel()
	panel.show_panel()
	await _wait(func() -> bool: return _panel_idle(panel), "快速开闭最终展开")
	_check(panel.visible and panel.scale.is_equal_approx(Vector2.ONE) and panel.get_global_rect().get_center().distance_to(center) < 1.0, "快速开闭无缩放累积及布局漂移")
	var original := _player.get_equipped_weapon_item().duplicate(true)
	var candidate := WeaponInstance.from_item(ItemRegistry.get_instance().get_item("weapon_shotgun"))
	var other := candidate.to_item_dictionary() if candidate != null else {}
	var switched := _player.equip_weapon_item(other)
	_evidence["weapon_switch_result"] = switched
	_check(bool(switched.get("success", false)), "真实切换武器")
	await _wait(func() -> bool: return str(_board_snapshot(board).get("weapon_instance_id", "")) == _player.get_equipped_weapon_instance_id(), "切枪自动重绑")
	_check(int(_board_snapshot(board).used) == 0, "新枪不继承旧枪刻槽")
	_check(bool(_player.equip_weapon_item(original).get("success", false)), "恢复原武器")
	await _wait(func() -> bool: return int(_board_snapshot(board).used) == 4, "原枪重绑恢复四槽")
	_evidence["k_board"] = _board_snapshot(board)
	panel.hide_panel()
	await _wait(func() -> bool: return not panel.visible, "K关闭完整动画")
	_check(not _player.input_locked, "K完全关闭后释放输入")

func _check_effect_brief_catalog() -> void:
	var expected := {
		"fate_scale_node": ["放大增伤", "缩小提速"], "fate_overclock": ["高速连射", "慢射重击"],
		"fate_armor_pierce": ["滚石弹", "碎石击退"], "fate_bullet_carry_gun": ["携枪前射", "携枪后射"],
		"fate_gun_on_gun": ["副枪跟射", "背挂跟射"], "fate_attachment_parasite": ["命中触发", "换弹触发"],
		"fate_living_bullet": ["追踪近敌", "追踪远敌"], "fate_turret_on_land": ["落地炮台", "移动炮台"],
		"fate_home_on_land": ["返航伤敌", "回程增伤"], "fate_bullet_return": ["命中折返", "返枪补弹"],
		"fate_chain_lightning": ["连锁闪电", "五连闪电"], "fate_bounce_bullet": ["墙壁弹跳", "反弹增伤"],
		"fate_barrage_copy": ["双波弹幕", "前后弹幕"], "fate_fuse_fire": ["火焰灼烧", "长效灼烧"],
		"fate_fuse_frost": ["命中冻结", "命中减速"], "fate_fuse_poison": ["叠毒伤害", "延时毒爆"],
		"fate_out_of_control": ["随机乱射", "锥形乱射"], "fate_gluttony": ["命中成长", "未中蓄势"],
		"fate_explode_reload": ["换弹爆炸", "换弹聚怪"], "fate_every_seventh": ["七发爆破", "换弹强首发"],
		"fate_crit_kill": ["击杀必暴", "暴杀增伤"], "fate_huge_scale": ["巨化增伤", "缩体疾速"]}
	var count := 0
	for card: FateCard in FateCardPresets.playable_presets():
		if card.scope != FateCard.Scope.WEAPON:
			continue
		var id := card.get_stable_card_id()
		_check(expected.has(id), "武器卡摘要独立映射覆盖：" + id)
		for reversed in [false, true]:
			var text := GameText.fate_effect_brief(id, reversed)
			_check(text.length() >= 1 and text.length() <= 5, "武器正逆摘要1至5字：%s/%s" % [id, reversed])
			_check(expected.has(id) and text == str(expected.get(id, ["", ""])[1 if reversed else 0]), "摘要准确映射：%s/%s" % [id, reversed])
			count += 1
	_check(count == 44, "22武器正逆共44摘要非零全覆盖")

func _check_scope_badge(face: TextureRect, badge: Control, label: String) -> void:
	_check(badge != null and badge.get_script().resource_path == "res://src/ui/weapon_build/FateScopeGlyph.gd" and badge.get_child_count() == 0, label + "scope纯向量无文字纹理子节点")
	if badge == null or face == null:
		return
	var actual := FateCardView.contained_texture_rect((face.get_parent() as Control).size, face.texture)
	_check(badge.position.distance_to(actual.position + Vector2(2, 2)) < 0.1 and is_zero_approx(badge.rotation), label + "scope位于实际卡面左上且不随逆位旋转")

func _check_socket_captions(board: Control, label: String) -> void:
	for socket: Control in board.get("_sockets") as Array:
		var brief := socket.find_child("EffectBrief", true, false) as Label
		var occupied := bool(socket.get("occupied"))
		_check(brief != null and brief.visible == occupied and (occupied or brief.text.is_empty()), label + "仅已装显示摘要，空巢/在途无label")
		if not occupied or brief == null:
			continue
		var record: Dictionary = socket.get("record")
		_check(brief.text == GameText.fate_effect_brief(str(record.get("stable_card_id", "")), str(record.get("orientation", "UPRIGHT")) == "REVERSED"), label + "已装摘要与记录方位一致")
		var art := socket.get("_art") as Control
		var face := socket.find_child("SocketFace", true, false) as TextureRect
		var actual := FateCardView.contained_texture_rect(art.size, face.texture if face != null else null)
		_check(brief.position.y >= art.position.y + actual.end.y and brief.position.y + brief.size.y <= socket.size.y + 0.1, label + "footer位于实际卡面下且不溢出")
		var branch := socket.get("_branch") as Label
		_check(branch.text.is_empty() or branch.position.y >= brief.position.y + brief.size.y, label + "footer不与挂枪来源重叠")
		_check_scope_badge(face, socket.find_child("FateScopeBadge", true, false) as Control, label)

func _check_candidate_captions() -> void:
	var buttons: Array = _dungeon.get("_fate_choice_buttons")
	var choices: Array = _dungeon.get("_door_fate_choices")
	for index in mini(buttons.size(), choices.size()):
		var button := buttons[index] as Button
		var caption := button.get_meta("tarot_caption_label") as Label
		var id := str(button.get_meta("tarot_stable_card_id"))
		var card := choices[index] as FateCard
		_check(caption != null and caption.get_theme_font_size("font_size") == 18 and caption.text == FateCardView.caption_text(card, "", false), "候选功能18字号且不附加weaponname：" + id)
		_check_scope_badge(button.get_meta("tarot_face_node") as TextureRect, button.find_child("FateScopeBadge", true, false) as Control, "候选")

func _currency(target: int) -> void:
	var delta := target - GameManager.currency
	if delta > 0:
		GameManager.add_currency(delta)
	elif delta < 0:
		GameManager.spend_currency(-delta)

func _offers_ready() -> bool:
	var buttons := _dungeon.get("_fate_choice_buttons") as Array
	if buttons.size() != 3:
		return false
	var presentation := _dungeon.get("_fate_presentation") as Control
	if presentation == null or bool(presentation.get("_moving")):
		return false
	for button: Button in buttons:
		if not bool(button.get_meta("tarot_face_ready", false)):
			return false
	return true

func _open_offer(cards: Array[FateCard]) -> void:
	_dungeon.call("_close_door_fate_overlay")
	_check(_dungeon.show_reference_fate_overlay_for_test(), "正式购卡宿主打开")
	# 只替换fixture的候选输入，UI、报价、确认、提交均由正式宿主执行。
	var choices := _dungeon.get("_door_fate_choices") as Array
	choices.assign(cards)
	var quotes: Dictionary = {}
	for card in cards:
		quotes[card.get_stable_card_id()] = int(Dungeon3D.FATE_PRICE_BY_RARITY[int(card.card_rarity)])
	_dungeon.set("_fate_door_quote", quotes)
	_dungeon.call("_build_door_fate_overlay")
	await _wait(_offers_ready, "board入场/下移/三卡翻面完成")

func _press(index: int) -> void:
	var buttons := _dungeon.get("_fate_choice_buttons") as Array
	(buttons[index] as Button).pressed.emit()

func _confirm_ready() -> bool:
	return is_instance_valid(_dungeon.get("_fate_confirm"))

func _answer(accepted: bool) -> void:
	var confirm := _dungeon.get("_fate_confirm") as Control
	if confirm == null:
		_check(false, "确认控件存在")
		return
	for node: Node in confirm.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == ("是" if accepted else "否"):
			button.pressed.emit()
			return
	_check(false, "真实确认按钮存在")

func _not_busy() -> bool:
	return not bool(_dungeon.get("_fate_purchase_busy")) and not bool(_dungeon.get("_fate_feedback_locked"))

func _check_purchases() -> void:
	_set_stage("三卡稳定态与默认否确认")
	_currency(9999)
	await _open_offer([FateCardPresets.overclock(), FateCardPresets.fate_extra_loot(), FateCardPresets.fate_bless_dead()])
	var board := _dungeon.get("_fate_board") as Control
	var overlay := _dungeon.get("_fate_overlay") as Control
	_check(board.get_script().resource_path == "res://src/ui/weapon_build/WeaponBuildBoard.gd", "上三卡与下board正式共享实现")
	_check((_dungeon.get("_fate_presentation") as Node).get("row").get_child_count() == 3, "上方恰好三张正式候选")
	_check(int(_board_snapshot(board).used) == 4, "购卡board同源显示原枪四槽")
	_check_inactive_back_palette(board, "购卡构建板")
	var loot := _dungeon.find_child("RunLootReadout", true, false) as Label
	_check(loot != null and loot.is_visible_in_tree() and loot.get_theme_font_size("font_size") >= 30, "唯一金币读数放大可见")
	_check(overlay.find_child("FateCurrencyBalance", true, false) == null, "无第二金币余额")
	var exit_button := overlay.find_child("FateExitButton", true, false) as Button
	_check(exit_button != null and exit_button.size.x >= 180 and exit_button.size.y >= 40, "底部大退出按钮")
	_check_candidate_captions()
	_check_socket_captions(board, "购卡页")
	await _capture("purchase_stable")
	var money := GameManager.currency
	var item := _player.get_equipped_weapon_item().duplicate(true)
	_press(0)
	if not await _wait(_confirm_ready, "武器不可逆确认出现"):
		return
	var focus := get_viewport().gui_get_focus_owner() as Button
	_check(focus != null and focus.text == "否", "确认默认焦点否")
	_check(GameManager.currency == money and _player.get_equipped_weapon_item() == item, "确认前不扣款不刻槽")
	await _capture("confirmation")
	_answer(false)
	await _wait(_not_busy, "否取消事务完成")
	_check(GameManager.currency == money and _player.get_equipped_weapon_item() == item, "否取消保持领域和金币")
	_set_stage("成功提交一次与飞卡")
	_press(0)
	if not await _wait(_confirm_ready, "再次确认"):
		return
	_answer(true)
	await _wait(func() -> bool: return int(_board_snapshot(board).get("pending_slot", -1)) > 0, "成功飞卡pending阶段")
	_check(bool(_dungeon.get("_fate_purchase_busy")), "提交期间保持忙锁")
	_check_socket_captions(board, "在途")
	var deducted := GameManager.currency
	var used := _player.get_equipped_weapon_instance().fate_upgrades.size()
	_dungeon.call("_on_door_fate_selected", 0)
	_dungeon.call("_cancel_door_fate_selection")
	_check(GameManager.currency == deducted and _player.get_equipped_weapon_instance().fate_upgrades.size() == used and bool(_dungeon.get("_door_fate_active")) and not bool(_dungeon.get("_fate_overlay_closing")), "提交中拒绝重复购买和退出")
	var flight := board.get("_flight_surface") as Control
	await _wait(func() -> bool: return flight.get_child_count() > 0 or (board.get("_effects") as Control).get_child_count() > 0, "实际飞卡或脉冲节点")
	_capture_install_impact(board)
	await _capture("install_motion")
	await _wait(_not_busy, "完整飞卡与脉冲结束")
	_check(money - GameManager.currency == int(_dungeon.call("_fate_price", FateCardPresets.overclock())), "成功仅扣一次准确报价")
	_check(_player.get_equipped_weapon_instance().fate_upgrades.size() == 5 and int(_board_snapshot(board).used) == 5, "成功仅新增一个永久槽且board落巢")
	_dungeon.call("_on_door_fate_selected", 0)
	_check(GameManager.currency == deducted, "已购卡重复提交不扣钱")
	await _capture("assembled")
	_stop_motion()
	_evidence["assembled_board"] = _board_snapshot(board)
	_set_stage("世界角色卡不占枪槽")
	for index in [1, 2]:
		_press(index)
		await _wait(_not_busy, "世界/角色反馈完整结束")
		_check(_player.get_equipped_weapon_instance().fate_upgrades.size() == 5, "作用域卡不占枪槽：%d" % index)
		_check(bool((_dungeon.get("_door_fate_purchased") as Array)[index]), "作用域卡正式提交：%d" % index)
	_set_stage("同offer持久化候选冻结")
	var saved: Dictionary = _dungeon.call("_export_door_fate_snapshot")
	var json_saved: Dictionary = JSON.parse_string(JSON.stringify(saved))
	_dungeon.call("_close_door_fate_overlay")
	_check(bool(_dungeon.call("_import_door_fate_snapshot", json_saved)), "同offer JSON读档成功")
	_dungeon.call("_restore_pending_door_fate_overlay")
	await _wait(_offers_ready, "读档表现稳定")
	var restored: Dictionary = _dungeon.call("_export_door_fate_snapshot")
	_evidence["offer_before_reload"] = saved
	_evidence["offer_after_reload"] = restored
	var same_offer := int(saved.offer_id) == int(restored.offer_id) and (saved.cards as Array).size() == (restored.cards as Array).size()
	for index in mini((saved.cards as Array).size(), (restored.cards as Array).size()):
		var old: Dictionary = saved.cards[index]
		var current: Dictionary = restored.cards[index]
		for field in ["stable_card_id", "orientation", "purchased"]:
			same_offer = same_offer and old[field] == current[field]
		same_offer = same_offer and is_equal_approx(float(old.orientation_roll), float(current.orientation_roll)) and int(old.price) == int(current.price)
	for id: String in saved.quotes:
		same_offer = same_offer and restored.quotes.has(id) and int(saved.quotes[id]) == int(restored.quotes.get(id, -1))
	_check(same_offer, "读档候选方位报价已购位及offer_id不变")
	_set_stage("金币不足与满槽拒绝")
	_currency(0)
	await _open_offer([FateCardPresets.overclock(), FateCardPresets.fate_extra_loot(), FateCardPresets.fate_bless_dead()])
	_dungeon.call("_on_door_fate_selected", 0)
	_check(GameManager.currency == 0 and not _confirm_ready() and str(_dungeon.call("_fate_card_block_reason", 0)) == "insufficient", "金币不足不扣款不进入确认")
	_currency(9999)
	var instance := _player.get_equipped_weapon_instance()
	var capacity := instance.fate_slot_capacity
	instance.fate_slot_capacity = instance.fate_upgrades.size()
	_dungeon.call("_refresh_door_fate_prices")
	money = GameManager.currency
	_dungeon.call("_on_door_fate_selected", 0)
	_check(GameManager.currency == money and str(_dungeon.call("_fate_card_block_reason", 0)) == "slot_full", "满槽拒绝且零扣款")
	instance.fate_slot_capacity = capacity
	_set_stage("来源取消退款")
	await _open_offer([FateCardPresets.gun_on_gun(), FateCardPresets.fate_extra_loot(), FateCardPresets.fate_bless_dead()])
	money = GameManager.currency
	item = _player.get_equipped_weapon_item().duplicate(true)
	_press(0)
	if await _wait(_confirm_ready, "组合卡确认"):
		_answer(true)
		if await _wait(func() -> bool: return FateCardGameBridge.get_node_or_null("FateSourceSelectionPanel") != null, "真实来源选择窗口"):
			_check(GameManager.currency < money, "来源等待阶段真实预扣款")
			var source := FateCardGameBridge.get_node("FateSourceSelectionPanel")
			source.call("cancel")
			await _wait(_not_busy, "来源取消完整退款")
			_check(GameManager.currency == money and item == _player.get_equipped_weapon_item(), "来源取消全额退款且不刻槽")
			_check(not bool((_dungeon.get("_door_fate_purchased") as Array)[0]), "来源取消不标记已购")
	_set_stage("购卡完整退场")
	_dungeon.call("_cancel_door_fate_selection")
	_check(_player.input_locked, "购卡退场动画结束前输入仍锁")
	await _wait(func() -> bool: return not bool(_dungeon.get("_door_fate_active")) and _dungeon.get("_fate_overlay") == null, "购卡退场与节点清理")
	_check(not _player.input_locked, "购卡退场结束解锁")

func _profile_diff(before: Variant, after: Variant, path := "") -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key: Variant in after:
			if not keys.has(key):
				keys.append(key)
		for key: Variant in keys:
			var field := path + "/" + str(key)
			if not before.has(key) or not after.has(key):
				changes.append({"field": field, "before": before.get(key), "after": after.get(key)})
			else:
				changes.append_array(_profile_diff(before[key], after[key], field))
	elif before is Array and after is Array:
		if before.size() != after.size():
			changes.append({"field": path + "/size", "before": before.size(), "after": after.size()})
		for index in mini(before.size(), after.size()):
			changes.append_array(_profile_diff(before[index], after[index], path + "/" + str(index)))
	elif before != after:
		changes.append({"field": path, "before": before, "after": after})
	return changes

func _save_activity() -> Dictionary:
	var timer := BaseManager.get("_runtime_checkpoint_timer") as Timer
	return {"runtime_provider": is_instance_valid(BaseManager.call("_get_runtime_checkpoint_provider")),
		"runtime_dirty": BaseManager.get("_runtime_checkpoint_dirty"),
		"runtime_reason": BaseManager.get("_pending_runtime_reason"),
		"timer_running": timer != null and not timer.is_stopped(),
		"background_writer": BaseManager.get("_room_writer") != null,
		"pending_payload": not (BaseManager.get("_pending_room_payload") as Dictionary).is_empty(),
		"clock_running": GameTimeManager.clock_running,
		"world_time": GameTimeManager.get_elapsed_game_seconds(),
		"last_save_reason": BaseManager.get_profile_snapshot().get("last_save_reason", "")}

func _compatibility_checkpoint(label: String, profile: Dictionary, disk: Variant) -> void:
	var changes := _profile_diff(profile, BaseManager.get_profile_snapshot())
	var disk_now: Variant = JSON.parse_string(FileAccess.get_file_as_string(BaseManager.save_path)) if FileAccess.file_exists(BaseManager.save_path) else null
	var entry := {"phase": label, "profile_changes": changes, "disk_changes": _profile_diff(disk, disk_now), "save_activity": _save_activity()}
	(_evidence["compatibility_phases"] as Array).append(entry)
	print("QA_PROFILE_DEBUG ", JSON.stringify(entry))
	_checkpoint()

func _check_compatibility_panels() -> void:
	_set_stage("兼容占卜与训练面板smoke")
	_evidence["compatibility_phases"] = []
	var before_freeze := BaseManager.get_profile_snapshot()
	var disk_before_freeze: Variant = JSON.parse_string(FileAccess.get_file_as_string(BaseManager.save_path)) if FileAccess.file_exists(BaseManager.save_path) else null
	_compatibility_checkpoint("无面板：购卡退场后保存活动", before_freeze, disk_before_freeze)
	await get_tree().process_frame
	await get_tree().process_frame
	_compatibility_checkpoint("无面板：逐帧时钟与延迟事务差异", before_freeze, disk_before_freeze)
	var old_host_mode := _dungeon.process_mode
	var clock_running := GameTimeManager.clock_running
	# 只冻结上个购卡fixture的后台玩法与权威时钟；不禁用保存服务或面板回调。
	_dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	GameTimeManager.set_clock_running(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var provider := BaseManager.call("_get_runtime_checkpoint_provider") as Node
	if provider != null:
		_check(BaseManager.flush_runtime_checkpoint("verification_compatibility_barrier"), "兼容基线收齐运行时保存barrier")
	_check(GameTimeManager.flush_to_profile("verification_compatibility_clock_barrier"), "兼容基线收齐时钟与后台写barrier")
	_check(bool(BaseManager.call("_finish_room_writes", true)), "兼容基线后台writer已join")
	_compatibility_checkpoint("无面板：冻结旧事务并收齐barrier", before_freeze, disk_before_freeze)
	var profile := BaseManager.get_profile_snapshot().duplicate(true)
	var save_path := BaseManager.save_path
	var save_existed := FileAccess.file_exists(save_path)
	var save_digest := FileAccess.get_sha256(save_path) if save_existed else ""
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path)) if save_existed else null
	await get_tree().process_frame
	await get_tree().process_frame
	var activity := _save_activity()
	_check(not bool(activity.runtime_dirty) and not bool(activity.timer_running) and not bool(activity.background_writer) and not bool(activity.pending_payload), "兼容基线无在途保存事务")
	_check(BaseManager.get_profile_snapshot() == profile and FileAccess.file_exists(save_path) == save_existed and (not save_existed or FileAccess.get_sha256(save_path) == save_digest), "兼容基线无面板时全字段与档摘要稳定")
	_compatibility_checkpoint("无面板：最终基线稳定性", profile, disk)
	var money := GameManager.currency
	var item := _player.get_equipped_weapon_item().duplicate(true)
	var bridge_player: Node = FateCardGameBridge.get("_player")
	var setting := "accessibility/reduce_motion"
	var had_setting := ProjectSettings.has_setting(setting)
	var previous_motion: Variant = ProjectSettings.get_setting(setting) if had_setting else null
	for reduced in [false, true]:
		ProjectSettings.set_setting(setting, reduced)
		var menu := (load("res://scenes/DivinationMenu.tscn") as PackedScene).instantiate() as DivinationMenu
		var menu_id := menu.get_instance_id()
		menu.set_player(_player)
		add_child(menu)
		var board := menu.get("_board") as Control
		_check(not (menu.get("_upper") as Control).visible, "占卜入场前隐藏候选：%s" % reduced)
		_check(not bool((menu.card_options_container.get_child(0).get_meta("tarot_button") as Button).get_meta("tarot_face_ready", false)), "占卜不抢先翻卡")
		await _wait(func() -> bool:
			var current := instance_from_id(menu_id) as DivinationMenu
			if current == null or bool(current.get("_opening")):
				return false
			for column: Node in current.card_options_container.get_children():
				if not bool((column.get_meta("tarot_button") as Button).get_meta("tarot_face_ready", false)):
					return false
			return true, "占卜投影下移后翻卡完成")
		var snapshot := _board_snapshot(board)
		_check(str(snapshot.get("weapon_instance_id", "")) == _player.get_equipped_weapon_instance_id() and int(snapshot.used) == _player.get_equipped_weapon_instance().fate_upgrades.size(), "占卜board绑定真实枪与槽")
		_check(board.position.is_equal_approx(Vector2.ZERO) and not board.get_parent() is Container, "占卜归位且不受Container重排")
		_check(menu.pending_card == null and GameManager.currency == money and _player.get_equipped_weapon_item() == item, "占卜仅展示不预选不付钱不刻槽")
		menu.call("_close")
		menu.call("_close")
		_check(is_instance_valid(menu) and not menu.is_queued_for_deletion(), "占卜等待关闭动画且防重入")
		await _wait(func() -> bool: return instance_from_id(menu_id) == null, "占卜完整关闭")
		_compatibility_checkpoint("占卜完整关闭：%s" % reduced, profile, disk)
		var paused_before := get_tree().paused
		var input_before := _player.input_locked
		# 第二轮叠加独立暂停原因，确认面板只释放自己的暂停。
		if reduced:
			Global.acquire_pause("verification_compatibility_hold")
		var bench := (load("res://src/training3d/TrainingFateBenchPanel.gd") as Script).new() as TrainingFateBenchPanel
		var bench_id := bench.get_instance_id()
		bench.set_player(_player)
		var closed_states: Array[bool] = []
		bench.closed.connect(func() -> void:
			var current := instance_from_id(bench_id) as TrainingFateBenchPanel
			closed_states.append(current != null and not bool(current.get("_opening")) and not (current.get("_board") as Control).visible))
		add_child(bench)
		var grid := bench.get("_grid") as GridContainer
		_check(grid.get_child_count() == 48 and grid.get_child_count() == FateCardPresets.playable_presets().size(), "训练保留48张全量卡池")
		_check(not grid.visible and get_tree().paused and _player.input_locked, "训练入场隐藏全量列表并保持暂停输入锁")
		await _wait(func() -> bool:
			var current := instance_from_id(bench_id)
			return current != null and not bool(current.get("_opening")), "训练投影下移完成")
		board = bench.get("_board") as Control
		snapshot = _board_snapshot(board)
		_check(grid.visible and board.position.is_equal_approx(Vector2.ZERO) and not board.get_parent() is Container, "训练归位后显示全量卡池")
		_check(str(snapshot.get("weapon_instance_id", "")) == _player.get_equipped_weapon_instance_id() and int(snapshot.used) == _player.get_equipped_weapon_instance().fate_upgrades.size(), "训练board同源真实枪槽")
		bench.call("_on_card_pressed", FateCardPresets.overclock())
		if await _wait(func() -> bool:
			var current := instance_from_id(bench_id)
			return current != null and is_instance_valid(current.get("_confirm")), "训练原有武器确认"):
			var confirm := bench.get("_confirm") as Control
			var focus := get_viewport().gui_get_focus_owner() as Button
			_check(focus != null and focus.text == "否", "训练确认默认否")
			if focus != null and focus.text == "否":
				focus.pressed.emit()
			else:
				confirm.call("cancel")
			await _wait(func() -> bool:
				var current := instance_from_id(bench_id)
				return current != null and not bool(current.get("_busy")), "训练确认否完成")
			bench.call("_on_card_pressed", FateCardPresets.overclock())
			bench.call("_close")
			await _wait(func() -> bool:
				var current := instance_from_id(bench_id)
				return current != null and not bool(current.get("_busy")), "训练关闭优先取消确认")
			_check(not bool(bench.get("_closing")) and not is_instance_valid(bench.get("_confirm")), "训练取消确认不关闭上层面板")
		_check(GameManager.currency == money and _player.get_equipped_weapon_item() == item, "训练确认否不扣钱不改枪")
		bench.set("_busy", true)
		bench.call("_close")
		_check(not bool(bench.get("_closing")), "训练busy拒绝关闭")
		bench.set("_busy", false)
		bench.call("_close")
		bench.call("_close")
		_check(closed_states.is_empty() and get_tree().paused and _player.input_locked, "训练关闭动画结束前不发closed不解锁")
		await _wait(func() -> bool: return instance_from_id(bench_id) == null, "训练完整关闭")
		_compatibility_checkpoint("训练完整关闭：%s" % reduced, profile, disk)
		await get_tree().process_frame
		_check(closed_states == [true] and not Global.has_pause_reason("training_fate_bench"), "训练关闭一次且释放自身暂停")
		if reduced:
			_check(get_tree().paused and Global.has_pause_reason("verification_compatibility_hold"), "训练关闭保留其它暂停锁")
			Global.release_pause("verification_compatibility_hold")
		_check(get_tree().paused == paused_before and _player.input_locked == input_before, "训练关闭后暂停与宿主输入状态回归")
	ProjectSettings.set_setting(setting, previous_motion if had_setting else null)
	# 覆盖正式保存防抖窗口，不能让面板新排队的写入逃过摘要断言。
	await get_tree().create_timer(BaseManager.RUNTIME_SAVE_DEBOUNCE_SECONDS + 0.1).timeout
	_check(bool(BaseManager.call("_finish_room_writes", true)), "兼容smoke结束收齐新writer且不丢失事务")
	_compatibility_checkpoint("面板结束：防抖窗口与后台写完成", profile, disk)
	_check(FateCardGameBridge.get("_player") == bridge_player and bridge_player == _player, "兼容smoke保持当前玩家bridge")
	_check(BaseManager.get_profile_snapshot() == profile, "兼容展示与确认否不改BaseData")
	_check(FileAccess.file_exists(save_path) == save_existed and (not save_existed or FileAccess.get_sha256(save_path) == save_digest), "兼容smoke不创建或写入用户档")
	activity = _save_activity()
	_check(not bool(activity.runtime_dirty) and not bool(activity.timer_running) and not bool(activity.background_writer) and not bool(activity.pending_payload), "兼容smoke不遗留延迟保存事务")
	_dungeon.process_mode = old_host_mode
	GameTimeManager.set_clock_running(clock_running)


func _process(delta: float) -> void:
	if not _recording:
		return
	_motion_elapsed += delta
	if _motion_elapsed >= MOTION_INTERVAL and not _motion_pending:
		_motion_elapsed = fmod(_motion_elapsed, MOTION_INTERVAL)
		_motion_pending = true
		_capture_motion_frame()

func _start_motion() -> void:
	if not _record_motion_requested or not _render:
		return
	_motion_output = _output.path_join("motion")
	var error := DirAccess.make_dir_recursive_absolute(_motion_output)
	_check(error == OK, "工程外连续帧目录可用")
	if error != OK:
		return
	_motion_started_msec = Time.get_ticks_msec()
	_motion_elapsed = MOTION_INTERVAL
	_recording = true
	_evidence["motion_window"] = "初次K按键前至首次成功飞卡落巢完成；不含来源选择等待"
	_checkpoint()

func _capture_motion_frame() -> void:
	await RenderingServer.frame_post_draw
	if not _recording:
		_motion_pending = false
		return
	var image := get_viewport().get_texture().get_image()
	var path := _motion_output.path_join("frame_%05d.png" % _motion_frames)
	if image == null or image.is_empty():
		_check(false, "连续帧真实viewport回读非空")
		_stop_motion()
	elif image.save_png(path) != OK:
		_check(false, "连续帧保存：" + path)
		_stop_motion()
	else:
		_motion_frames += 1
	_motion_pending = false

func _stop_motion() -> void:
	if _recording:
		_motion_duration = (Time.get_ticks_msec() - _motion_started_msec) / 1000.0
		_recording = false
		print("MOTION_FRAMES ", _motion_frames, " OUTPUT ", _motion_output)
		_checkpoint()

func _motion_info() -> Dictionary:
	return {"requested": _record_motion_requested, "recording": _recording, "output": _motion_output,
		"video_frames": _motion_frames, "interval_seconds": MOTION_INTERVAL, "nominal_fps": 1.0 / MOTION_INTERVAL,
		"duration_seconds": (Time.get_ticks_msec() - _motion_started_msec) / 1000.0 if _recording else _motion_duration,
		"frame_pattern": "frame_%05d.png", "encoded_video": false}

func _capture_install_impact(board: Control) -> void:
	if not _render:
		return
	# 并行观察真实Effects，不在原QA链路插入额外等待或推进正式动画。
	var effects := board.get("_effects") as Control
	var deadline := Time.get_ticks_msec() + 8000
	while is_instance_valid(effects) and effects.get_child_count() == 0 and not _not_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(effects) or effects.get_child_count() == 0:
		_check(false, "补充截图检测到真实落巢Effects")
		return
	var impact := effects.get_child(0) as CanvasItem
	await get_tree().create_timer(0.08).timeout
	_check(is_instance_valid(impact) and impact.is_visible_in_tree(), "峰值截图时真实落巢特效仍可见")
	if is_instance_valid(impact) and impact.is_visible_in_tree():
		await _capture("install_impact")

func _capture(label: String) -> void:
	if not _render or _output.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _output.path_join(label + ".png")
	_check(image != null and not image.is_empty(), "真实viewport截图非空：" + label)
	if image != null and not image.is_empty():
		_check(image.save_png(path) == OK, "截图保存：" + label)
		print("CAPTURE ", path)

func _checkpoint(completed := false) -> void:
	if _output.is_empty():
		return
	var file := FileAccess.open(_output.path_join("weapon_hologram_result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"completed": completed, "passed": completed and _failures.is_empty(), "fixture": "正式Dungeon3D test_mode + 正式K页PackedScene；非人工全流程", "stage": _stage, "checks": _checks, "failures": _failures, "evidence": _evidence, "rendered": _render, "output": _output, "motion": _motion_info(), "user_dir": ProjectSettings.globalize_path("user://"), "uncovered": ["人工基地进关全流程", "视频编码（由主代理ffmpeg打包）", "所有卡牌穷举"]}, "\t"))

func _finish() -> void:
	_stop_motion()
	_checkpoint(true)
	print("WEAPON_HOLOGRAM_UI_RESULT ", JSON.stringify({"passed": _failures.is_empty(), "checks": _checks.size(), "failures": _failures, "completed": true, "fixture": true, "rendered": _render, "output": _output, "motion": _motion_info()}))
	get_tree().quit(0 if _failures.is_empty() else 1)
