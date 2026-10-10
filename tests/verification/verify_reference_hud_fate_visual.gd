extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const OUTPUT_DIR := "res://outputs/verification"


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 10:
		await get_tree().process_frame
	dungeon.force_enter_room_for_test("main_01")
	var minimap := dungeon.get_node("HUD/DungeonMinimap3D") as DungeonMinimap3D
	# Freeze dungeon feed so this screenshot can hold two deterministic runtime enemy markers.
	dungeon.set_process(false)
	minimap.set_enemy_positions([
		dungeon.player.global_position + Vector3(4.0, 0.0, 2.0),
		dungeon.player.global_position + Vector3(-3.0, 0.0, -2.0),
	])
	for _frame in 3:
		await get_tree().process_frame

	var hud := dungeon.get_node_or_null("HUD/ReferenceCombatHUD") as Control
	_check(hud != null, "Reference combat HUD root is missing", failures)
	if hud != null:
		var player_status := hud.find_child("PlayerStatusBlock", true, false) as Control
		_check(player_status != null, "Player status block is missing", failures)
		_check(player_status != null and player_status.size.x <= 280.0, "Reference HUD was not reduced to 80% scale", failures)
		_check(hud.find_child("CurrentWeaponPanel", true, false) != null, "Bottom weapon panel is missing", failures)
		_check(hud.find_child("QuickItemHUD_0", true, false) != null and hud.find_child("QuickItemHUD_1", true, false) != null, "Two HUD quick-item panels are missing", failures)
		# 主界面右下角的 R/SHIFT/F/E 四个动作键图标已移除；保留反向断言防止误恢复。
		_check(hud.find_child("ActionKeyStrip", true, false) == null, "Bottom-right action key strip was restored", failures)
		var projected_textures := hud.find_children("ProjectedTexture", "TextureRect", true, false)
		var all_textures := hud.find_children("*", "TextureRect", true, false)
		_check(all_textures.size() == projected_textures.size() and projected_textures.size() >= 1 and projected_textures.size() <= 3, "HUD weapon/quick slots do not exclusively use lazy shared 3D projections", failures)
	var weapon_model := dungeon.get_hud_weapon_model_snapshot()
	_check(bool(weapon_model.get("uses_world_model_factory", false)), "HUD weapon does not reuse the backpack 3D model factory", failures)
	_check(str(weapon_model.get("model_kind", "")) == "weapon" and int(weapon_model.get("mesh_count", 0)) > 0, "HUD weapon 3D projection is empty", failures)
	var weapon_rebuilds := int(weapon_model.get("rebuild_count", 0))
	dungeon.call("_on_ammo_changed", 11, 12)
	_check(int(dungeon.get_hud_weapon_model_snapshot().get("rebuild_count", -1)) == weapon_rebuilds, "HUD weapon model rebuilds on ordinary ammo updates", failures)
	_check(absf(minimap.size.x - minimap.size.y) <= 2.0 and minimap.size.x <= 225.0, "Tactical minimap is not circular or 80% scale", failures)
	_check(minimap.get_snapshot().get("enemy_marker_count", 0) == 2, "Minimap enemy dots are not fed by runtime data", failures)
	_check(_capture("reference_combat_hud.png"), "Could not capture reference combat HUD", failures)
	# —— 2026-10-08（`0.2-PLAYER-001` 追记五）：换弹环搬到 HUD 武器图标上 ——
	# 真源是主人的标注图：红圈**外径 75 px**、**圈心 = 武器图标控件矩形中心**。
	# 本段逐条量可控件的几何与显隐，再真跑一次换弹验「进度跟武器计时器」与「图标弹一下」。
	# 世界空间那一版环的退役由 `verify_3d_reload_state_flow` 的反向钉子管，两边不重叠。
	var reload_ring := hud.find_child("HudReloadRing", true, false) as HudReloadRing
	var weapon_icon := hud.find_child("CurrentWeaponModelIcon3D", true, false) as Control
	_check(reload_ring != null, "HUD reload ring is missing", failures)
	_check(weapon_icon != null, "HUD weapon icon is missing", failures)
	if reload_ring != null:
		var ring_snapshot := reload_ring.get_snapshot()
		_check(
			absf(float(ring_snapshot.get("outer_diameter_px", 0.0)) - 75.0) <= 0.5,
			"HUD reload ring is not the annotated 75 px circle: %s" % ring_snapshot.get("outer_diameter_px"),
			failures
		)
		_check(not reload_ring.visible, "HUD reload ring shows while nothing is reloading", failures)
		# 线宽与发光：2026-10-09 主人返工「太粗了 细一点」⇒ 比例由 0.2226 下调到 0.13。
		# 0.13 的来源是**主人红笔实测**（核心亮带 5 px ÷ 外半径 37.5 = 0.1333），
		# 所以这里同时钉住主干（4.875 px）与发光（×1.8 = 8.8 px）两条 —— 只钉主干挡不住
		# "主干细了、发光还铺 20 px"这种"看着仍然粗"的形态，而那正是返工的原始症状。
		var ring_thickness := float(ring_snapshot.get("thickness_px", 0.0))
		_check(
			ring_thickness >= 4.0 and ring_thickness <= 5.8,
			"HUD reload ring stroke is not the annotated red-pen weight (%.3f px, expected ~4.875)"
			% ring_thickness,
			failures
		)
		var ring_glow_width := float(ring_snapshot.get("glow_width_px", 999.0))
		_check(
			ring_glow_width <= 10.5,
			"HUD reload ring glow spreads too wide to read as a thin ring (%.3f px)" % ring_glow_width,
			failures
		)
		_check(
			float((ring_snapshot.get("glow_color") as Color).a) <= 0.45,
			"HUD reload ring glow is too opaque to read as a thin ring (alpha %.3f)"
			% (ring_snapshot.get("glow_color") as Color).a,
			failures
		)
		# 位置是每帧从图标矩形现算的 —— 这里手动推一次 tick（本场景冻结了 dungeon 的 _process）。
		dungeon.call("_tick_hud_reload_feedback", 0.0)
		if weapon_icon != null:
			var ring_center := reload_ring.global_position + reload_ring.size * 0.5
			var icon_center := weapon_icon.get_global_rect().get_center()
			_check(
				ring_center.distance_to(icon_center) <= 1.0,
				"HUD reload ring is not centred on the weapon icon (offset %s)" % (ring_center - icon_center),
				failures
			)
		# 弹跳曲线是**纯函数**，逐点断言：起止都精确归 1、峰值落在设计带内、
		# 回落深度不失控。回落下沿 = `1 − 0.35 × PEAK` = 0.895（回弹感），
		# 所以下界取 0.85 而不是 0.9 —— 0.9 会把设计好的回弹直接判红。
		_check(is_equal_approx(Dungeon3D.hud_weapon_icon_pop_scale(0.0), 1.0), "Weapon icon pop does not start at 1.0", failures)
		_check(is_equal_approx(Dungeon3D.hud_weapon_icon_pop_scale(1.0), 1.0), "Weapon icon pop does not settle back to 1.0", failures)
		var pop_peak := 0.0
		var pop_low := 99.0
		for sample in range(101):
			var value := Dungeon3D.hud_weapon_icon_pop_scale(float(sample) / 100.0)
			pop_peak = maxf(pop_peak, value)
			pop_low = minf(pop_low, value)
		_check(
			pop_peak >= 1.2 and pop_peak <= 1.5 and pop_low >= 0.85,
			"Weapon icon pop curve is out of range (peak %.3f low %.3f)" % [pop_peak, pop_low],
			failures
		)
		# 真跑一次换弹：环显形（进度 0 = 空环）→ 图标绕中心弹一下再收回 → 进度跟计时器 → 结束即收。
		var hud_weapon := dungeon.player.weapon
		var hud_inventory := dungeon.get("_inventory") as InventoryModule
		if hud_inventory != null:
			hud_inventory.add_item(ItemRegistry.get_instance().get_item("item_ammo_pack"), 6)
		hud_weapon.current_ammo = maxi(0, hud_weapon.magazine_size - 3)
		if not dungeon.player.request_reload():
			_check(false, "Cannot start a reload to exercise the HUD reload ring", failures)
		else:
			var hud_reload_duration := float(dungeon.player.get_reload_snapshot().get("duration", hud_weapon.reload_time))
			_check(reload_ring.visible, "HUD reload ring did not appear when the reload started", failures)
			_check(
				is_equal_approx(reload_ring.progress, 0.0),
				"HUD reload ring did not start as an empty ring: %.3f" % reload_ring.progress,
				failures
			)
			var icon_scale_peak := 1.0
			var icon_scale_low := 99.0
			var pop_steps := int(ceil(Dungeon3D.HUD_WEAPON_ICON_POP_DURATION / 0.01))
			for _step in range(pop_steps):
				dungeon.call("_tick_hud_reload_feedback", 0.01)
				if weapon_icon != null:
					icon_scale_peak = maxf(icon_scale_peak, weapon_icon.scale.x)
					icon_scale_low = minf(icon_scale_low, weapon_icon.scale.x)
			_check(icon_scale_peak >= 1.2, "Weapon icon did not pop up on reload (peak %.3f)" % icon_scale_peak, failures)
			_check(icon_scale_low >= 0.85, "Weapon icon shrank too much while popping (low %.3f)" % icon_scale_low, failures)
			if weapon_icon != null:
				_check(
					is_equal_approx(weapon_icon.scale.x, 1.0),
					"Weapon icon pop did not settle back to 1.0 (%.3f)" % weapon_icon.scale.x,
					failures
				)
				_check(
					weapon_icon.pivot_offset.is_equal_approx(Vector2.ZERO),
					"Weapon icon kept a pop pivot after settling",
					failures
				)
			hud_weapon.call("_process", hud_reload_duration * 0.5)
			dungeon.call("_tick_hud_reload_feedback", 0.0)
			_check(
				absf(reload_ring.progress - 0.5) <= 0.02,
				"HUD reload ring does not follow the weapon timer: %.3f" % reload_ring.progress,
				failures
			)
			# ⚠️ 必须先让引擎画出**新的一帧**再截：`_capture` 直接读视口纹理，
			# 中间没有 await 时拿到的还是"换弹开始前"那一帧（实测两张 PNG 逐字节相同、
			# 差异 bbox 为空 —— 一张看不出环的"证据"比没有证据更糟）。
			await RenderingServer.frame_post_draw
			_check(_capture("hud_reload_ring.png"), "Could not capture the HUD reload ring", failures)
			hud_weapon.call("_process", hud_reload_duration)
			dungeon.call("_tick_hud_reload_feedback", 0.0)
			_check(not reload_ring.visible, "HUD reload ring stayed visible after the reload finished", failures)
	dungeon.call("_toggle_full_map")
	for _frame in 3:
		await get_tree().process_frame
	var full_map := dungeon.get("_full_map_control") as DungeonMinimap3D
	_check(full_map != null and bool(full_map.get_snapshot().get("full_map_mode", false)), "M full-floor map overlay is missing", failures)
	_check(_capture("full_floor_explored_map.png"), "Could not capture full-floor map", failures)
	dungeon.call("_close_full_map")

	var initial_reduce_motion: Variant = ProjectSettings.get_setting("accessibility/reduce_motion", false)
	ProjectSettings.set_setting("accessibility/reduce_motion", false)
	_check(dungeon.show_reference_fate_overlay_for_test(), "Could not open deterministic fate overlay", failures)
	for _frame in 2:
		await get_tree().process_frame
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	_check(overlay != null, "Fate overlay is missing", failures)
	if overlay != null:
		var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
		_check(cards.size() == 3, "Fate overlay does not show three vertical cards", failures)
		for card_node in cards:
			var flip_card := card_node as Button
			_check(flip_card.disabled, "Tarot card is clickable before flip completes", failures)
			_check(flip_card.find_child("TarotCardBack", true, false) != null, "Tarot card back is missing", failures)
	for _frame in 48:
		await get_tree().process_frame
	if overlay != null:
		var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
		var all_text := _collect_label_text(overlay)
		# 卡面已换成塔罗位图：作用域标签/方位标签/卡名不再由文字承载（图里已有）。
		# 顶部协议提示和底部信息条按最新视觉需求移除，只保留标题。
		_check("命 运 卡 三 选 一" in all_text, "Fate overlay title is missing", failures)
		_check("当前信息" not in all_text, "Fate overlay still contains the removed bottom information bar", failures)
		_check("FATE PROTOCOL / SELECT ONE" not in all_text, "Fate overlay still contains the removed top protocol label", failures)
		for card in cards:
			var card_control := card as Control
			var card_button := card_control as Button
			_check(bool(card_control.get_meta("tarot_face_ready", false)), "Tarot face did not finish flipping", failures)
			_check(not card_button.disabled, "Tarot card stayed disabled after flip", failures)
			_check(card_control.size.y > card_control.size.x, "Fate choice is not a vertical card", failures)
			var card_view := card_button.get_meta("fate_feedback_view") as Control
			var feedback := card_button.find_child("FateCardFeedback", true, false) as Control
			_check(card_view != null, "Fate card visual column is missing", failures)
			_check(feedback != null, "Fate card feedback layer is missing", failures)
			_check(feedback != null and feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Fate feedback layer blocks card input", failures)
			_check(card_view.scale.is_equal_approx(Vector2.ONE), "Fate card is not at neutral scale after reveal", failures)
			# 手柄/键盘焦点与鼠标共用视觉反馈，但焦点不写入鼠标态。
			dungeon.call("_on_reference_fate_card_focus", card_button, true)
			_check(bool(card_button.get_meta("fate_feedback_focused", false)), "Fate card focus feedback did not activate", failures)
			_check(not bool(card_button.get_meta("fate_feedback_hovered", false)), "Focus feedback forged mouse hover state", failures)
			dungeon.call("_on_reference_fate_card_focus", card_button, false)
			if feedback != null:
				var expected_scope_color: Color = card_button.get_meta("tarot_scope_color") as Color
				_check((feedback.get("accent_color") as Color).is_equal_approx(expected_scope_color), "Fate feedback particle color does not match scope color", failures)
			# 真跑悬停进入/退出，并立即反向切换，确保共享 tween 不留下残余缩放。
			dungeon.call("_on_reference_fate_card_hover", card_button, true)
			await get_tree().create_timer(0.1).timeout
			_check(card_view.scale.x > 1.0, "Fate card hover did not enlarge the card", failures)
			if card_button.name == "FateChoiceCard_0":
				await RenderingServer.frame_post_draw
				_check(_capture("fate_feedback_hover.png"), "Could not capture fate feedback hover", failures)
			dungeon.call("_on_reference_fate_card_hover", card_button, false)
			dungeon.call("_on_reference_fate_card_hover", card_button, true)
			dungeon.call("_on_reference_fate_card_hover", card_button, false)
			await get_tree().create_timer(0.2).timeout
			_check(card_view.scale.is_equal_approx(Vector2.ONE), "Fate card hover tween did not recover after rapid enter/exit", failures)
			_check(card_control.size.x >= 250.0 and card_control.size.y >= 420.0, "Fate cards are too small to dominate the choice screen", failures)
			_check(card_control.size.x <= 300.0 and card_control.size.y <= 500.0, "Fate card exceeds its 80%-scaled layout budget", failures)
			_check_fate_card_art(card as Button, failures)
		var reversed_cards := cards.filter(func(value: Node) -> bool: return str(value.get_meta("tarot_orientation", "")) == "逆位")
		_check(reversed_cards.size() == 1, "Deterministic visual offer does not contain exactly one reversed card", failures)
		if reversed_cards.size() == 1:
			# 图卡模式的新契约：**只把卡面图案绕中心倒置**，按钮与卡下功能文字都不旋转。
			var reversed_card := reversed_cards[0] as Control
			var reversed_face := reversed_card.find_child("TarotArtFace", true, false) as Control
			_check(reversed_face != null and absf(absf(reversed_face.get_global_transform().get_rotation()) - PI) < 0.01, "Reversed card art layer is no longer inverted", failures)
			_check(absf(reversed_card.rotation) < 0.01, "Reversed card rotated the whole button instead of only the art layer", failures)
		for card in cards:
			_check_tarot_caption_upright(card as Button, failures)
		var reversed_description := FateCardPresets.fate_reinforce()
		reversed_description.set_orientation(FateCard.Orientation.REVERSED, 0.8)
		_check(reversed_description.short_description in all_text, "Reversed effect text was replaced by upright text", failures)
		# 点击反馈锁住整组三列：第二张直调也不能穿透；关闭来源/弹窗后必须恢复。
		var locked_first := cards[0] as Button
		var locked_second := cards[1] as Button
		dungeon.call("_on_reference_fate_card_pressed", locked_first, 0)
		_check(bool(dungeon.get("_fate_feedback_locked")), "Fate card feedback did not lock after click", failures)
		_check(locked_first.disabled and locked_second.disabled, "Click feedback did not disable all fate cards", failures)
		dungeon.call("_on_reference_fate_card_pressed", locked_second, 1)
		_check(int(dungeon.get("_fate_feedback_selected_index")) == 0, "Second card changed the locked selection", failures)
		await get_tree().create_timer(0.08).timeout
		await RenderingServer.frame_post_draw
		_check(_capture("fate_feedback_impact.png"), "Could not capture fate feedback impact", failures)
		dungeon.call("_close_door_fate_overlay")
		_check(not bool(dungeon.get("_fate_feedback_locked")), "Fate card feedback lock was not cleared on close", failures)
		_check(dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null, "Fate overlay was not cleaned up after close", failures)
		_check(dungeon.show_reference_fate_overlay_for_test(), "Could not reopen fate overlay after feedback close", failures)
		await get_tree().create_timer(0.5).timeout
	_check(_capture("reference_fate_three_choice.png"), "Could not capture reference tarot overlay", failures)

	# 减少动效同样保留逆位框/图案与正向文字。
	ProjectSettings.set_setting("accessibility/reduce_motion", true)
	dungeon.call("_close_door_fate_overlay")
	_check(dungeon.show_reference_fate_overlay_for_test(), "Could not reopen reduced-motion offer", failures)
	await get_tree().create_timer(0.3).timeout
	var reduced_overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	if reduced_overlay != null:
		for card in reduced_overlay.find_children("FateChoiceCard_*", "Button", true, false):
			_check_fate_card_art(card as Button, failures)
			_check_tarot_caption_upright(card as Button, failures)
	else:
		_check(false, "Reduced-motion overlay is missing", failures)
	await _check_simple_tarot_entries(failures)
	ProjectSettings.set_setting("accessibility/reduce_motion", initial_reduce_motion)

	dungeon.queue_free()
	await get_tree().process_frame
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 4242
	add_child(tower)
	for _frame in 10:
		await get_tree().process_frame
	var tower_info := tower.get_node_or_null("HUD/TowerCurrentInfoHUD") as Control
	var tower_player_status := tower.get_node_or_null("HUD/ReferenceCombatHUD/PlayerStatusBlock") as Control
	_check(tower_info != null, "Tower current information panel is missing", failures)
	if tower_info != null and tower_player_status != null:
		_check(tower_info.global_position.y >= tower_player_status.get_global_rect().end.y + 20.0, "Tower current information was not moved below player status", failures)
		_check(tower_info.find_children("*", "ProgressBar", true, false).is_empty(), "Tower current information still contains the duplicate gray HP bar", failures)
	_check(_capture("reference_tower_hud_compact.png"), "Could not capture compact tower HUD", failures)

	if failures.is_empty():
		print("REFERENCE_HUD_FATE_VISUAL_OK: reversed frames/ornaments stay inverted, all face text stays upright; normal/reduced motion and three entry points verified; reload ring sits on the 75 px annotated circle centred on the weapon icon and the icon pops")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 图卡模式契约：每张卡必须有**卡面位图**，且贴图路径必须与这张牌的身份对得上
## （防「图装错牌」——光看有没有 TextureRect 是查不出装错的）。卡背层必须存在且翻面后隐藏。
func _check_fate_card_art(button: Button, failures: Array[String]) -> void:
	_check(bool(button.get_meta("tarot_art_mode", false)), "Fate card fell back to the programmatic face while tarot art exists", failures)
	var face := button.find_child("TarotArtFace", true, false) as TextureRect
	_check(face != null, "Fate card is missing its tarot art layer", failures)
	if face == null:
		return
	_check(face.visible, "Fate card art layer never became visible", failures)
	_check(face.texture != null, "Fate card art layer has no texture", failures)
	var scan_material := face.material as ShaderMaterial
	_check(scan_material != null and scan_material.shader != null, "Fate card art layer is missing the scan-light shader", failures)
	if scan_material != null and scan_material.shader != null:
		var shader_code := scan_material.shader.code
		_check("visible_mask" in shader_code and "smoothstep(0.045, 0.16, luminance)" in shader_code, "Scan-light shader has no luminance gate for black regions", failures)
		_check("scan_strength" in shader_code and "scan_width" in shader_code, "Scan-light shader tuning uniforms are missing", failures)
	if face.texture != null:
		var stable_id := str(button.get_meta("tarot_stable_card_id", ""))
		var expected := "res://assets/art/ui/fate_cards/ui_fate_card_%s_v001.png" % stable_id.trim_prefix("fate_")
		_check(face.texture.resource_path == expected, "Fate card art does not match its card identity: %s != %s" % [face.texture.resource_path, expected], failures)
	var back := button.find_child("TarotCardBack", true, false) as TextureRect
	_check(back != null, "Tarot card back layer is missing", failures)
	if back != null:
		_check(not back.visible, "Tarot card back stayed visible after the flip revealed the face", failures)


## 卡下功能文字：必须存在、非空、且**正向可读**（不随卡面图案倒置）。
func _check_tarot_caption_upright(button: Button, failures: Array[String]) -> void:
	var caption := button.get_parent().find_child("FateFunctionCaption", false, false) as Label
	_check(caption != null, "Fate card is missing its function caption", failures)
	if caption == null:
		return
	_check(not caption.text.strip_edges().is_empty(), "Fate card function caption is empty", failures)
	_check(absf(caption.get_global_transform().get_rotation()) < 0.01, "Fate function caption is not upright: %s" % caption.text, failures)


func _check_tarot_text_upright(button: Button, failures: Array[String]) -> void:
	# 注意：get_meta 的默认值若为 null，Godot 仍会打错误日志，故用 has_meta 守卫。
	var face := (button.get_meta("tarot_face_node") if button.has_meta("tarot_face_node") else null) as Control
	_check(face != null and face.visible, "Tarot readable text layer is missing", failures)
	if face == null:
		return
	_check(absf(face.get_global_transform().get_rotation()) < 0.01, "Tarot face text layer is upside down", failures)
	_check(face.pivot_offset.is_equal_approx(face.size * 0.5), "Tarot text pivot does not follow layout size", failures)
	var labels := face.find_children("*", "Label", true, false)
	if face is Label:
		labels.append(face)
	for node in labels:
		var label := node as Label
		# 中央天体与朝向三角是图案，不是需要旋回的说明文字。
		var ornament := face.find_child("TarotOrientationOrnament", true, false)
		if ornament != null and ornament.is_ancestor_of(label):
			continue
		_check(absf(label.get_global_transform().get_rotation()) < 0.01, "Tarot label is upside down: %s" % label.text, failures)
	_check(not button.disabled, "Tarot card stayed disabled", failures)


func _check_simple_tarot_entries(failures: Array[String]) -> void:
	var workbench := WorkbenchPanel.new()
	var divination := DivinationMenu.new()
	var reversed_card := FateCardPresets.fate_reinforce()
	reversed_card.set_orientation(FateCard.Orientation.REVERSED, 0.8)
	for reduce_motion in [false, true]:
		ProjectSettings.set_setting("accessibility/reduce_motion", reduce_motion)
		for entry in [workbench, divination]:
			var button := Button.new()
			button.text = "星币·王牌\n逆位\n" + reversed_card.short_description
			button.size = Vector2(240, 120)
			add_child(button)
			entry.call("_play_workbench_tarot_flip" if entry == workbench else "_play_card_flip", button, reversed_card, 0)
			_check(button.disabled, "Simple tarot entry allows clicks before reveal", failures)
			await get_tree().create_timer(0.55).timeout
			_check_tarot_text_upright(button, failures)
			_check(absf(absf(button.rotation) - PI) < 0.01, "Simple tarot entry lost reversed frame", failures)
			button.size = Vector2(300, 140)
			await get_tree().process_frame
			_check_tarot_text_upright(button, failures)
			button.free()
	workbench.free()
	divination.free()


func _capture(file_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var image := get_viewport().get_texture().get_image()
	return image != null and image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK


func _collect_label_text(root: Node) -> String:
	var result := ""
	for label_node in root.find_children("*", "Label", true, false):
		result += "\n" + (label_node as Label).text
	return result


func _check(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
