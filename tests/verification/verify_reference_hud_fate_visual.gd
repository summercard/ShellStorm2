extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")


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
	# —— 2026-10-15 玩家主界面血条延迟白段（与 Boss 屏条、小怪头顶条同一口径）——
	# 白段是纯视觉层：真实 HP 立刻落到 `hp_bar.value`，白条随后按统一速度追赶。
	# 第 18 行已 `set_process(false)` 停掉自动 tick，所以这里全部用固定 delta 手动步进 ——
	# 靠 `await process_frame` 取样会随机器帧时间浮动，把这条断言变成飘忽用例。
	var player_hp_bar := hud.find_child("HPBar", true, false) as ProgressBar
	var delayed_layer := hud.find_child("PlayerHealthBarDelayed", true, false) as ProgressBar
	_check(player_hp_bar != null, "Player HP bar is missing", failures)
	_check(delayed_layer != null, "Player HP delayed white layer is missing", failures)
	if player_hp_bar != null and delayed_layer != null:
		var full_hp := int(maxf(1.0, player_hp_bar.max_value))
		_check(
			delayed_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and not delayed_layer.show_percentage,
			"Player delayed HP layer is not a passive overlay",
			failures,
		)
		# 受伤：红条立刻到新血量，白段必须停在此击之前的满血位置。
		dungeon.call("_on_player_hp_changed", int(round(full_hp * 0.6)), full_hp)
		var hurt := dungeon.get_player_vitals_bar_snapshot()
		_check(
			absf(float(hurt.get("actual_ratio", -1.0)) - 0.6) <= 0.02,
			"Player HP bar did not drop to the damaged ratio",
			failures,
		)
		_check(
			float(hurt.get("delayed_ratio", 0.0)) >= 0.99,
			"Player damage leaves no visible delayed white segment",
			failures,
		)
		# 追赶：只朝真实血量收，且不得越过（越过会在红条左侧露出白）。
		dungeon.call("_tick_player_health_bar_delay", 0.05)
		var chasing := float(dungeon.get_player_vitals_bar_snapshot().get("delayed_ratio", 1.0))
		_check(
			chasing < float(hurt.get("delayed_ratio", 1.0)) and chasing >= 0.6,
			"Player delayed white segment does not catch up toward real HP: %.4f" % chasing,
			failures,
		)
		# 治疗/回满：立即对齐，不留假白段。
		dungeon.call("_on_player_hp_changed", full_hp, full_hp)
		_check(
			is_equal_approx(
				float(dungeon.get_player_vitals_bar_snapshot().get("delayed_ratio", 0.0)), 1.0
			),
			"Player healing left a stale white segment",
			failures,
		)
		# 留一次可见白段给截图：这一帧之后不再步进，截图里能直接看到白段。
		dungeon.call("_on_player_hp_changed", int(round(full_hp * 0.72)), full_hp)
		await get_tree().process_frame
		_check(
			delayed_layer.get_global_rect().size.is_equal_approx(
				player_hp_bar.get_global_rect().size
			),
			"Player delayed HP layer is not exactly stacked on the real bar",
			failures,
		)
	_check(_capture("reference_combat_hud.png"), "Could not capture reference combat HUD", failures)
	# —— 2026-10-15：换弹环迁到角色投影右下侧，武器图标仍保留弹跳 ——
	# 独立钉住外径 25 canvas px、角色脚底投影右 34 / 下 10 px，不从实现常量取期望值。
	# 冻结场景内只手动步进换弹反馈；移动角色与切换相机后完整复位，不推进世界。
	# 世界空间那一版环的退役由 `verify_3d_reload_state_flow` 的反向钉子管，两边不重叠。
	var reload_ring := hud.find_child("HudReloadRing", true, false) as HudReloadRing
	var weapon_icon := hud.find_child("CurrentWeaponModelIcon3D", true, false) as Control
	_check(reload_ring != null, "HUD reload ring is missing", failures)
	_check(weapon_icon != null, "HUD weapon icon is missing", failures)
	if reload_ring != null:
		var ring_snapshot := reload_ring.get_snapshot()
		_check(
			reload_ring.size.is_equal_approx(Vector2(25.0, 25.0))
			and is_equal_approx(float(ring_snapshot.get("outer_diameter_px", 0.0)), 25.0),
			"HUD 换弹环外径不是 25 canvas px：%s" % ring_snapshot.get("outer_diameter_px"),
			failures
		)
		_check(not reload_ring.visible, "HUD reload ring shows while nothing is reloading", failures)
		# 外径缩到 25 px 后仍沿用 0.13 线宽比和 1.8 发光倍数：主干 1.625、发光 2.925 px。
		# 两条均用严格数值断言，防止只缩主干却保留旧的宽发光。
		var ring_thickness := float(ring_snapshot.get("thickness_px", 0.0))
		_check(
			is_equal_approx(ring_thickness, 1.625),
			"HUD 换弹环主干不是 1.625 px：%.3f" % ring_thickness,
			failures
		)
		var ring_glow_width := float(ring_snapshot.get("glow_width_px", 999.0))
		_check(
			is_equal_approx(ring_glow_width, 2.925),
			"HUD 换弹环发光宽度不是 2.925 px：%.3f" % ring_glow_width,
			failures
		)
		_check(
			float((ring_snapshot.get("glow_color") as Color).a) <= 0.45,
			"HUD reload ring glow is too opaque to read as a thin ring (alpha %.3f)"
			% (ring_snapshot.get("glow_color") as Color).a,
			failures
		)
		# 独立从当前视口相机投影角色，再转到环父控件局部坐标；不使用武器图标作为锚点。
		var ring_camera := dungeon.get_viewport().get_camera_3d()
		_check(ring_camera != null, "角色侧换弹环缺少当前视口相机", failures)
		dungeon.call("_tick_hud_reload_feedback", 0.0)
		_check(not reload_ring.visible, "未换弹时手动 tick 意外显示了 HUD 换弹环", failures)
		if ring_camera != null:
			_check_hud_reload_ring_projection(reload_ring, dungeon.player, ring_camera, "初始定位", failures)
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
		var weapon_was_processing := hud_weapon.is_processing()
		var hud_inventory := dungeon.get("_inventory") as InventoryModule
		if hud_inventory != null:
			hud_inventory.add_item(ItemRegistry.get_instance().get_item("item_ammo_pack"), 6)
		hud_weapon.current_ammo = maxi(0, hud_weapon.magazine_size - 3)
		# 故意留下过期位置，确保真实开始事件当场重新定位，而非等下一次 tick 才碰巧正确。
		reload_ring.position = Vector2(-1000.0, -1000.0)
		if not dungeon.player.request_reload():
			_check(false, "Cannot start a reload to exercise the HUD reload ring", failures)
		else:
			# request_reload 会唤醒武器 process；冻结真实计时器，后续只按固定 delta 手动推进。
			hud_weapon.set_process(false)
			var hud_reload_duration := float(dungeon.player.get_reload_snapshot().get("duration", hud_weapon.reload_time))
			_check(reload_ring.visible, "HUD reload ring did not appear when the reload started", failures)
			if ring_camera != null:
				_check_hud_reload_ring_projection(reload_ring, dungeon.player, ring_camera, "真实换弹开始立即定位", failures)
			_check(
				is_equal_approx(reload_ring.progress, 0.0),
				"HUD reload ring did not start as an empty ring: %.3f" % reload_ring.progress,
				failures
			)
			if ring_camera != null:
				# 相机是玩家子节点时也固定其世界姿态，确保这次移动真的改变屏幕投影。
				# 以下操作无 await、无世界 tick，结束时恢复完整 global_transform。
				var player_transform := dungeon.player.global_transform
				var camera_transform := ring_camera.global_transform
				var initial_ring_center := reload_ring.position + reload_ring.size * 0.5
				dungeon.player.global_position += camera_transform.basis.x.normalized() * 2.0
				ring_camera.global_transform = camera_transform
				dungeon.call("_tick_hud_reload_feedback", 0.0)
				_check(reload_ring.visible, "角色移动后正在换弹的环被隐藏", failures)
				_check_hud_reload_ring_projection(reload_ring, dungeon.player, ring_camera, "角色移动跟随", failures)
				_check(
					(reload_ring.position + reload_ring.size * 0.5).distance_to(initial_ring_center) > 1.0,
					"角色移动后换弹环仍留在原位置",
					failures
				)
				dungeon.player.global_transform = player_transform
				ring_camera.global_transform = camera_transform
				dungeon.call("_tick_hud_reload_feedback", 0.0)
				_check_hud_reload_ring_projection(reload_ring, dungeon.player, ring_camera, "角色移动复位", failures)
				# 改变当前相机位置：环必须使用新的投影，而非缓存旧相机姿态。
				ring_camera.global_position += camera_transform.basis.x.normalized() * 2.0
				dungeon.call("_tick_hud_reload_feedback", 0.0)
				_check(reload_ring.visible, "相机移动后正在换弹的环被隐藏", failures)
				_check_hud_reload_ring_projection(reload_ring, dungeon.player, ring_camera, "相机移动跟随", failures)
				_check(
					(reload_ring.position + reload_ring.size * 0.5).distance_to(initial_ring_center) > 1.0,
					"相机移动后换弹环仍使用旧投影",
					failures
				)
				ring_camera.global_transform = camera_transform
				# 临时新相机不挂在玩家下，位置与原相机不同，防止硬编码 player.camera 蒙混过关。
				var alternate_camera := Camera3D.new()
				alternate_camera.projection = ring_camera.projection
				alternate_camera.keep_aspect = ring_camera.keep_aspect
				alternate_camera.size = ring_camera.size
				alternate_camera.fov = ring_camera.fov
				alternate_camera.near = ring_camera.near
				alternate_camera.far = ring_camera.far
				dungeon.add_child(alternate_camera)
				alternate_camera.global_transform = camera_transform
				alternate_camera.global_position -= camera_transform.basis.x.normalized() * 3.0
				alternate_camera.make_current()
				_check(dungeon.get_viewport().get_camera_3d() == alternate_camera, "临时相机未成为当前视口相机", failures)
				dungeon.call("_tick_hud_reload_feedback", 0.0)
				_check(reload_ring.visible, "切换相机后正在换弹的环被隐藏", failures)
				_check_hud_reload_ring_projection(reload_ring, dungeon.player, alternate_camera, "当前相机切换跟随", failures)
				_check(
					(reload_ring.position + reload_ring.size * 0.5).distance_to(initial_ring_center) > 1.0,
					"切换相机后换弹环仍使用原相机投影",
					failures
				)
				ring_camera.make_current()
				alternate_camera.free()
				ring_camera.global_transform = camera_transform
				dungeon.call("_tick_hud_reload_feedback", 0.0)
				_check(dungeon.get_viewport().get_camera_3d() == ring_camera, "临时相机测试后未恢复原当前相机", failures)
				_check_hud_reload_ring_projection(reload_ring, dungeon.player, ring_camera, "相机切换复位", failures)
				# 相机 +Z 是身后；移动玩家后再次固定子相机世界姿态，避免相机一起跟过去。
				dungeon.player.global_position = camera_transform.origin + camera_transform.basis.z.normalized() * 2.0
				ring_camera.global_transform = camera_transform
				_check(ring_camera.is_position_behind(dungeon.player.global_position), "身后隐藏测试未把角色移到相机后方", failures)
				dungeon.call("_tick_hud_reload_feedback", 0.0)
				_check(not reload_ring.visible, "角色在相机身后时换弹环仍可见", failures)
				_check(hud_weapon.is_reloading(), "角色移到相机身后意外取消了真实换弹", failures)
				dungeon.player.global_transform = player_transform
				ring_camera.global_transform = camera_transform
				dungeon.call("_tick_hud_reload_feedback", 0.0)
				_check(reload_ring.visible, "角色返回相机前方后换弹环未恢复", failures)
				_check_hud_reload_ring_projection(reload_ring, dungeon.player, ring_camera, "身后返回恢复", failures)
				_check(is_equal_approx(reload_ring.progress, 0.0), "投影测试推进了真实换弹进度", failures)
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
			# 第二轮走真实取消 API，不直接伪造 HUD 的结束事件；随后恢复完成换弹时的弹量。
			var completed_reload_ammo := hud_weapon.current_ammo
			hud_weapon.current_ammo = maxi(0, hud_weapon.magazine_size - 3)
			if not dungeon.player.request_reload():
				_check(false, "无法开始第二轮换弹以验证取消隐藏", failures)
			else:
				hud_weapon.set_process(false)
				_check(reload_ring.visible and hud_weapon.is_reloading(), "取消测试没有进入可见的真实换弹状态", failures)
				hud_weapon.call("_process", hud_reload_duration * 0.25)
				_check(reload_ring.visible and reload_ring.progress > 0.0, "取消前未产生可见的换弹进度", failures)
				_check(hud_weapon.cancel_reload(), "真实 weapon.cancel_reload 未取消换弹", failures)
				_check(not hud_weapon.is_reloading(), "取消后真实武器仍在换弹", failures)
				_check(not reload_ring.visible, "真实取消换弹后 HUD 环未立即隐藏", failures)
				_check(is_equal_approx(reload_ring.progress, 0.0), "真实取消换弹后 HUD 环未清空进度", failures)
				dungeon.call("_tick_hud_reload_feedback", Dungeon3D.HUD_WEAPON_ICON_POP_DURATION)
				_check(not reload_ring.visible, "取消后的反馈 tick 重新显示了 HUD 换弹环", failures)
			hud_weapon.current_ammo = completed_reload_ammo
			hud_weapon.set_process(weapon_was_processing)
	dungeon.call("_toggle_full_map")
	for _frame in 3:
		await get_tree().process_frame
	var full_map := dungeon.get("_full_map_control") as DungeonMinimap3D
	_check(full_map != null and bool(full_map.get_snapshot().get("full_map_mode", false)), "M full-floor map overlay is missing", failures)
	_check(_capture("full_floor_explored_map.png"), "Could not capture full-floor map", failures)
	dungeon.call("_close_full_map")

	var initial_reduce_motion: Variant = ProjectSettings.get_setting("accessibility/reduce_motion", false)
	ProjectSettings.set_setting("accessibility/reduce_motion", false)
	# 购卡制下单卡点击要有钱可花，否则按下会被前置校验拦下、拿不到反馈锁定态。
	GameManager.add_currency(9999)
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
		# 顶部协议提示、底部信息条、标题与顶部本局金币余额行按最新视觉需求全部移除。
		# 标题与余额行都用**反向钉子**：金币的唯一读数是右下角的 RunLootReadout，
		# 弹窗内谁把它们加回来这条即红（2026-10-14 / 2026-10-15 主人要求）。
		_check("购 买 》" not in all_text and "命 运 卡 ·" not in all_text, "Fate purchase overlay reintroduced its removed title", failures)
		_check("当前信息" not in all_text, "Fate overlay still contains the removed bottom information bar", failures)
		_check("FATE PROTOCOL / SELECT ONE" not in all_text, "Fate overlay still contains the removed top protocol label", failures)
		# 购买制的可见契约（2026-10-15 修订）：卡下价格行、屏幕下方正中的退出按钮。
		_check(
			"本局金币 ◈" not in all_text,
			"Fate purchase overlay still contains the removed top balance line",
			failures
		)
		_check(
			overlay.find_child("FateCurrencyBalance", true, false) == null,
			"Fate purchase overlay still has a balance label node",
			failures
		)
		var loot_readout := dungeon.find_child("RunLootReadout", true, false) as Label
		_check(
			loot_readout != null and "金币" in loot_readout.text,
			"Bottom-right run-currency readout is missing from the HUD",
			failures
		)
		var exit_button := overlay.find_child("FateExitButton", true, false) as Button
		_check(exit_button != null, "Fate purchase overlay is missing its exit button", failures)
		if exit_button != null:
			_check(
				is_equal_approx(exit_button.anchor_left, 0.5)
				and is_equal_approx(exit_button.anchor_right, 0.5)
				and is_equal_approx(exit_button.anchor_bottom, 1.0),
				"Fate exit button is not anchored to the bottom centre of the screen",
				failures
			)
		for card in cards:
			var card_control := card as Control
			var card_button := card_control as Button
			_check(bool(card_control.get_meta("tarot_face_ready", false)), "Tarot face did not finish flipping", failures)
			# 卡下价格行是购买制的唯一价格口径，必须存在且带上金币价。
			var price_label := (card_button.get_meta("tarot_price_label") if card_button.has_meta("tarot_price_label") else null) as Label
			_check(price_label != null and price_label.text.begins_with("◈ "), "Fate card is missing its price line under the card", failures)
			_check(int(card_button.get_meta("tarot_price", -1)) > 0, "Fate card has no positive purchase price", failures)
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
			# 🔴 这里不写固定 `await timer(0.1 / 0.2)`：缩放是 tween，机器被占满时
			# 同样的真实时间里只跑得出两三帧，固定时长会把「机器慢」误判成
			# 「tween 有残余」（2026-10-15 实测踩到：同一份代码上一轮通过、本轮红，
			# 整轮耗时从 2m49s 涨到 12m40s）。改成按真实时间轮询到收敛 ——
			# 若 tween 真的坏了，轮询会超时，判据强度不变。
			var hover_enlarged := await _wait_card_scale(card_view, 1.0, "above", 0.6)
			_check(hover_enlarged, "Fate card hover did not enlarge the card", failures)
			if card_button.name == "FateChoiceCard_0":
				await RenderingServer.frame_post_draw
				_check(_capture("fate_feedback_hover.png"), "Could not capture fate feedback hover", failures)
			dungeon.call("_on_reference_fate_card_hover", card_button, false)
			dungeon.call("_on_reference_fate_card_hover", card_button, true)
			dungeon.call("_on_reference_fate_card_hover", card_button, false)
			var hover_recovered := await _wait_card_scale(card_view, 1.0, "equal", 1.2)
			_check(hover_recovered, "Fate card hover tween did not recover after rapid enter/exit", failures)
			_check(card_control.size.x >= 250.0 and card_control.size.y >= 420.0, "Fate cards are too small to dominate the choice screen", failures)
			_check(card_control.size.x <= 300.0 and card_control.size.y <= 500.0, "Fate card exceeds its 80%-scaled layout budget", failures)
			_check_fate_card_art(card as Button, failures)
		var reversed_cards := cards.filter(func(value: Node) -> bool: return str(value.get_meta("tarot_orientation", "")) == "逆位")
		_check(reversed_cards.size() == 1, "Deterministic visual offer does not contain exactly one reversed card", failures)
		if reversed_cards.size() == 1:
			# 图卡模式的新契约：**只把卡面图案相对卡本身倒置 180°**，按钮与卡下功能文字都不旋转。
			# 不能比对「绝对 PI」：门后三张卡各自常驻一条轻微漂浮/透视旋转 tween（作用在列容器上），
			# 卡面会跟着列被带动最多 ±0.9°，绝对角度阈值 0.01 rad 会随采样时刻翻面。
			# 这里比对**卡面相对它自己那张卡**的夹角，与漂浮相位无关。
			var reversed_card := reversed_cards[0] as Control
			var reversed_face := reversed_card.find_child("TarotArtFace", true, false) as Control
			var reversed_card_rotation := reversed_card.get_global_transform().get_rotation()
			var reversed_face_rotation := (
				reversed_face.get_global_transform().get_rotation() if reversed_face != null else 0.0
			)
			_check(
				reversed_face != null
				and absf(absf(angle_difference(reversed_card_rotation, reversed_face_rotation)) - PI) < 0.01,
				"Reversed card art layer is no longer inverted relative to its own card",
				failures
			)
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

	# —— 买下之后翻回背面 + 悬停不再放大（2026-10-14 主人要求）——
	# 这是本轮唯一的视觉变更，必须有图可看：真买一张并截出「背面朝上」的形态。
	dungeon.call("_close_door_fate_overlay")
	_check(dungeon.show_reference_fate_overlay_for_test(), "Could not reopen the offer for the purchased-card screenshot", failures)
	await get_tree().create_timer(0.7).timeout
	var purchase_overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	if purchase_overlay != null:
		GameManager.add_currency(99999)
		dungeon.call("_refresh_door_fate_prices")
		var purchase_button := purchase_overlay.find_child("FateChoiceCard_0", true, false) as Button
		if purchase_button == null:
			_check(false, "Purchased-card screenshot could not find the first fate card", failures)
		else:
			await dungeon.call("_on_door_fate_selected", 0)
			await get_tree().create_timer(0.7).timeout
			var purchase_face := (purchase_button.get_meta("tarot_face_node") if purchase_button.has_meta("tarot_face_node") else null) as Control
			var purchase_back := (purchase_button.get_meta("tarot_back_node") if purchase_button.has_meta("tarot_back_node") else null) as Control
			_check(purchase_face != null and not purchase_face.visible, "Purchased card kept showing its face", failures)
			_check(purchase_back != null and purchase_back.visible, "Purchased card did not flip to its back", failures)
			_check(not purchase_button.disabled, "Purchased card became unfocusable after flipping back", failures)
			# 已购卡三件套：灰阶材质 + 压暗 + 缩到 70%（业主 2026-10-14 要求）。
			_check(
				purchase_back != null and (purchase_back as CanvasItem).material is ShaderMaterial,
				"Purchased card back has no greyscale material",
				failures
			)
			var purchase_view := purchase_button.get_meta("fate_feedback_view") as Control
			_check(
				purchase_view != null and purchase_view.modulate.r < 0.75,
				"Purchased card column is not dimmed",
				failures
			)
			# 绝对上限：主人连提两次要更暗（0.62 → 0.40），只跟常量比拦不住把常量改回亮档。
			_check(
				purchase_view != null and purchase_view.modulate.r <= 0.50,
				"Purchased card column is not dark enough (modulate %.2f, ceiling 0.50)"
				% [purchase_view.modulate.r if purchase_view != null else 1.0],
				failures
			)
			_check(
				purchase_view != null
				and is_equal_approx(purchase_view.scale.x, Dungeon3D.FATE_PURCHASED_CARD_SCALE),
				"Purchased card is not scaled to %.2f" % Dungeon3D.FATE_PURCHASED_CARD_SCALE,
				failures
			)
			# 卡背**半透明**、卡下文字**不跟着淡**（业主 2026-10-15：翻过去的卡做半透明，更淡一些）。
			# 两条一起钉：只淡卡牌本身，文字仍是这张卡唯一被读到的事实。
			var purchase_back_canvas := purchase_back as CanvasItem
			_check(
				purchase_back_canvas != null
				and purchase_back_canvas.modulate.a < 1.0
				and is_equal_approx(purchase_back_canvas.modulate.a, Dungeon3D.FATE_PURCHASED_CARD_ALPHA),
				"Purchased card back is not translucent (alpha %s)"
				% [purchase_back_canvas.modulate.a if purchase_back_canvas != null else 1.0],
				failures
			)
			var purchase_caption := (
				purchase_button.get_meta("tarot_caption_label")
				if purchase_button.has_meta("tarot_caption_label")
				else null
			) as Label
			_check(
				purchase_caption != null and is_equal_approx(purchase_caption.modulate.a, 1.0),
				"Purchased card caption went translucent together with the card",
				failures
			)
			# 悬停在一张已购买的卡上：不得离开它的 70% 基准缩放。
			dungeon.call("_on_reference_fate_card_hover", purchase_button, true)
			await get_tree().create_timer(0.28).timeout
			_check(
				purchase_view != null
				and is_equal_approx(purchase_view.scale.x, Dungeon3D.FATE_PURCHASED_CARD_SCALE),
				"Purchased card zoomed away from its 70% base scale when hovered",
				failures
			)
			await RenderingServer.frame_post_draw
			_check(_capture("fate_purchased_card_back.png"), "Could not capture the flipped-back purchased card", failures)
			# 金币不足时的完整表现证据：余额行闪红 + 卡片抖动 + 卡下价格行（2026-10-19 起只写价格，
			# 不再写「还差 M」）+ 右下金币读数保持常色不被暗化层压暗。
			# 四件事在同一帧里拍到，评审一眼就能看出反馈落在哪几个位置。
			GameManager.spend_currency(GameManager.currency)
			dungeon.call("_refresh_door_fate_prices")
			var reject_index := -1
			for slot in range(3):
				if str(dungeon.call("_fate_card_block_reason", slot)) == "insufficient":
					reject_index = slot
					break
			_check(reject_index >= 0, "No unaffordable card available to capture the rejection feedback", failures)
			if reject_index >= 0:
				var reject_button := purchase_overlay.find_child("FateChoiceCard_%d" % reject_index, true, false) as Button
				if reject_button != null:
					dungeon.call("_on_reference_fate_card_pressed", reject_button, reject_index)
					await get_tree().create_timer(0.09).timeout
					await RenderingServer.frame_post_draw
					_check(
						_capture("fate_reject_feedback.png"),
						"Could not capture the fate rejection feedback",
						failures
					)
					_check(
						dungeon.get("_fate_balance_warn_tween") != null,
						"Rejection feedback did not warn the run-currency balance line",
						failures
					)
	await _check_fate_exit_visual(dungeon, failures)

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
		print("REFERENCE_HUD_FATE_VISUAL_OK: 逆位框与装饰保持倒置、文字正向；常规/减少动效与三入口已验证；换弹环外径 25 canvas px、主干 1.625 px、发光 2.925 px，角色投影右 34/下 10 px，开始立即定位、角色移动与当前相机变化/切换跟随、身后隐藏及返回恢复、真实进度 0→0.5→完成隐藏和取消隐藏、武器图标弹跳已验证")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 期望值由测试独立计算：当前相机投影 → 父控件局部坐标 → 固定右 34 / 下 10 canvas px。
func _check_hud_reload_ring_projection(
	ring: HudReloadRing,
	player: Node3D,
	camera: Camera3D,
	stage: String,
	failures: Array[String],
) -> void:
	var parent := ring.get_parent() as Control
	_check(parent != null, "%s：HUD 换弹环父节点不是 Control" % stage, failures)
	if parent == null:
		return
	_check(not camera.is_position_behind(player.global_position), "%s：角色不在相机前方" % stage, failures)
	var projected_position := camera.unproject_position(player.global_position)
	var expected_center := (
		parent.get_global_transform_with_canvas().affine_inverse() * projected_position
		+ Vector2(34.0, 10.0)
	)
	var actual_center := ring.position + ring.size * 0.5
	_check(
		actual_center.distance_to(expected_center) <= 0.01,
		"%s：换弹环未对齐角色投影右 34 / 下 10 canvas px（实际 %s，期望 %s）"
		% [stage, actual_center, expected_center],
		failures
	)


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


## 卡下功能文字：必须存在、非空、且**不随卡面图案倒置**（正向可读），并与所属卡列同向。
## 注意门后三张卡常驻一条轻微漂浮/透视旋转 tween，所以这里不能比对「绝对 0 度」。
func _check_tarot_caption_upright(button: Button, failures: Array[String]) -> void:
	var caption := button.get_parent().find_child("FateFunctionCaption", false, false) as Label
	_check(caption != null, "Fate card is missing its function caption", failures)
	if caption == null:
		return
	_check(not caption.text.strip_edges().is_empty(), "Fate card function caption is empty", failures)
	# 契约是「正向可读」= **不随卡面图案倒置**，不是「绝对 0 度」：门后三张卡本身带
	# 轻微错相漂浮 + 透视旋转（设计契约，见 `14_技术施工_命运塔罗牌组 §3.2`），列容器一直
	# 挂在这条 tween 上，卡下文字跟着列一起轻微倾斜属正常表现。用 0.01 rad 当阈值会把
	# ±0.9° 的漂浮直接判红，而且结果随采样时刻抖动（同一份代码换个帧序就翻面）。
	# 这里改钉两条**与漂浮相位无关**的判据：
	#   ① 文字没有翻转（|rot| < 90°）—— 这才是「倒置」这个 bug 的形态；
	#   ② 文字没有做反向补偿（与所属卡列同向）—— 反向补偿会让正位卡的文字歪在卡面上。
	var caption_rotation := caption.get_global_transform().get_rotation()
	_check(
		absf(caption_rotation) < PI * 0.5,
		"Fate function caption is inverted (%.4f rad): %s" % [caption_rotation, caption.text],
		failures
	)
	var caption_host := caption.get_parent() as Control
	if caption_host != null:
		var host_rotation := caption_host.get_global_transform().get_rotation()
		_check(
			absf(angle_difference(caption_rotation, host_rotation)) < 0.01,
			"Fate function caption does not follow its card column (caption %.4f vs column %.4f): %s"
			% [caption_rotation, host_rotation, caption.text],
			failures
		)


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
	# 2026-10-18：武器改造台改为 6×6 炼金盘，塔罗三选一入口已移除，
	# 「简单塔罗入口」只剩占卜屋一条。逆位翻卡的可读性判据不变，只减一个入口。
	var divination := DivinationMenu.new()
	var reversed_card := FateCardPresets.fate_reinforce()
	reversed_card.set_orientation(FateCard.Orientation.REVERSED, 0.8)
	for reduce_motion in [false, true]:
		ProjectSettings.set_setting("accessibility/reduce_motion", reduce_motion)
		var button := Button.new()
		button.text = "星币·王牌\n逆位\n" + reversed_card.short_description
		button.size = Vector2(240, 120)
		add_child(button)
		divination.call("_play_card_flip", button, reversed_card, 0)
		_check(button.disabled, "Simple tarot entry allows clicks before reveal", failures)
		await get_tree().create_timer(0.55).timeout
		_check_tarot_text_upright(button, failures)
		_check(absf(absf(button.rotation) - PI) < 0.01, "Simple tarot entry lost reversed frame", failures)
		button.size = Vector2(300, 140)
		await get_tree().process_frame
		_check_tarot_text_upright(button, failures)
		button.free()
	divination.free()


## 等一张卡的缩放满足条件 —— **按真实时间轮询**，而不是 `await timer(固定秒数)`。
##
## 为什么要这样：缩放是 tween，机器被占满时同样长的真实时间里只跑得出两三帧，
## 固定时长会把「机器慢」误判成「tween 有残余」。轮询到收敛不放松判据 ——
## tween 若真的坏了就永远等不到，照样超时报红。
##
## `mode`：`"equal"` 等收敛到 `target`；`"above"` 等超过 `target`。
func _wait_card_scale(view: Control, target: float, mode := "equal", timeout := 1.2) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if view == null or not is_instance_valid(view):
			return false
		if _card_scale_matches(view, target, mode):
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return view != null and is_instance_valid(view) and _card_scale_matches(view, target, mode)


func _card_scale_matches(view: Control, target: float, mode: String) -> bool:
	if mode == "above":
		return view.scale.x > target and view.scale.y > target
	return is_equal_approx(view.scale.x, target) and is_equal_approx(view.scale.y, target)


## 暂停同一条真实退场 tween 并逐段推进，保证截图不会错过 0.42 秒动画的中间态。
## 图片来自游戏 viewport，不是示意图；结束仍由 tween 的 finished 时间轴回收弹窗。
func _check_fate_exit_visual(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	if overlay == null:
		_check(false, "Exit animation visual overlay is missing", failures)
		return
	var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
	await RenderingServer.frame_post_draw
	_check(_capture("fate_exit_before.png"), "Could not capture fate exit before", failures)
	var exit_button := overlay.find_child("FateExitButton", true, false) as Button
	exit_button.pressed.emit()
	_check(bool(dungeon.get("_door_fate_active")) and bool(dungeon.get("_fate_overlay_closing")), "Exit hard-cut the overlay instead of retaining its modal lock", failures)
	var exit_tween := overlay.get_meta("fate_exit_tween") as Tween
	exit_tween.pause()
	exit_tween.custom_step(Dungeon3D.FATE_OVERLAY_EXIT_DURATION * 0.30)
	for card_node in cards:
		var button := card_node as Button
		var view := button.get_meta("fate_feedback_view") as Control
		_check(button.disabled and button.scale.x < 0.6 and view.modulate.a < 1.0, "A card did not fold and fade in the first exit phase", failures)
	await RenderingServer.frame_post_draw
	_check(_capture("fate_exit_fold.png"), "Could not capture fate exit folding", failures)
	exit_tween.custom_step(Dungeon3D.FATE_OVERLAY_EXIT_DURATION * 0.25)
	for card_node in cards:
		var button := card_node as Button
		_check(str(button.get_meta("tarot_face_side", "")) == "back", "A card did not turn to the back on exit", failures)
	await RenderingServer.frame_post_draw
	_check(_capture("fate_exit_back_shrink.png"), "Could not capture fate exit back shrink", failures)
	exit_tween.custom_step(Dungeon3D.FATE_OVERLAY_EXIT_DURATION * 0.25)
	await RenderingServer.frame_post_draw
	_check(_capture("fate_exit_fade.png"), "Could not capture fate exit fade", failures)
	exit_tween.custom_step(Dungeon3D.FATE_OVERLAY_EXIT_DURATION)
	_check(not bool(dungeon.get("_door_fate_active")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null, "Exit animation finished without cleaning up its overlay", failures)
	await RenderingServer.frame_post_draw
	_check(_capture("fate_exit_after.png"), "Could not capture fate exit after", failures)
	# 减少动效分支仍能退出，不留下 locked/closing 或旧节点。
	ProjectSettings.set_setting("accessibility/reduce_motion", true)
	_check(dungeon.show_reference_fate_overlay_for_test(), "Cannot reopen reduced-motion exit offer", failures)
	dungeon.call("_cancel_door_fate_selection")
	_check(not bool(dungeon.get("_fate_overlay_closing")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null, "Reduced-motion exit left an overlay behind", failures)
	ProjectSettings.set_setting("accessibility/reduce_motion", false)


func _capture(file_name: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	return image != null and image.save_png(VerificationOutput.path(file_name)) == OK


func _collect_label_text(root: Node) -> String:
	var result := ""
	for label_node in root.find_children("*", "Label", true, false):
		result += "\n" + (label_node as Label).text
	return result


func _check(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
