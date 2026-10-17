extends Node

## 门后命运卡「局内购卡」验收（2026-10-14 主人改版）。
##
## 改版要点：三张卡**全部出现**，不再是「三选一」；每张卡按稀有度标价，用**本局金币**
## （`GameManager.currency`）购买；可以全买，也可以一张不买；弹窗只在点「退出」
## （或 ESC / 手柄 B）时才关闭；星星卡在目标枪命运槽已满时置灰不可购买。
##
## 本用例盯死四条不会被别的用例覆盖的契约：
## 1. 价格只来自 `FATE_PRICE_BY_RARITY`，且与稀有度一一对应；
## 2. 每一次购买尝试都满足**货币守恒**：买成 = 恰好扣掉该卡价格；买不成 = 金币分文不少；
## 3. 局外总货币池 `BaseManager.get_extraction_points()` 全程一动不动；
## 4. 买完弹窗保持打开，只有退出按钮才关闭。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 515151
	add_child(dungeon)
	for _frame in 8:
		await get_tree().process_frame

	var instance := dungeon.player.get_equipped_weapon_instance()
	if instance == null:
		_expect(false, "Player has no equipped weapon instance", failures)
		_finish(failures)
		return

	# 局外总池基线：整段测试结束时必须逐整数相等。
	var extraction_before := BaseManager.get_extraction_points()

	# —— 1) 金币不足：三张卡都按稀有度标价，但一张也买不了 ——
	_set_run_currency(0)
	instance.fate_upgrades.clear()
	_expect(dungeon.show_reference_fate_overlay_for_test(), "Cannot open the fate purchase overlay", failures)
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	_expect(overlay != null, "Fate purchase overlay node is missing", failures)
	if overlay == null:
		_finish(failures)
		return
	await _wait_fate_cards_flipped(overlay)
	var choices := dungeon.get("_door_fate_choices") as Array
	_expect(choices.size() == 3, "Fate purchase overlay does not offer three cards", failures)
	for index in range(choices.size()):
		var card := choices[index] as FateCard
		var button := overlay.find_child("FateChoiceCard_%d" % index, true, false) as Button
		_expect(button != null, "Fate choice card %d is missing" % index, failures)
		if button == null:
			continue
		var price_label := (button.get_meta("tarot_price_label") if button.has_meta("tarot_price_label") else null) as Label
		_expect(price_label != null and not price_label.text.strip_edges().is_empty(), "Fate card %d has no price line under the card" % index, failures)
		# 「金币不足」只说了状态；卡下必须同时写出**还差多少**，玩家才能一眼知道下一步要攒多少。
		_expect(
			price_label != null and "还差" in price_label.text,
			"Unaffordable card %d price line does not spell out the shortfall: %s"
			% [index, price_label.text if price_label != null else "<null>"],
			failures
		)
		var expected_price := int(Dungeon3D.FATE_PRICE_BY_RARITY[int(card.card_rarity)])
		_expect(int(button.get_meta("tarot_price", -1)) == expected_price, "Fate card %d price does not come from the rarity table" % index, failures)
		_expect(
			str(dungeon.call("_fate_card_block_reason", index)) == "insufficient",
			"Card %d (%s, %d soul) is not reported as unaffordable with an empty wallet" % [index, card.card_name, expected_price],
			failures
		)
	# 顶部「本局金币」余额行已按主人 2026-10-15 要求移除（反向钉子，防误恢复）：
	# 金币的唯一读数是右下角的 `RunLootReadout`，弹窗内不允许再出现第二个金币口径。
	_expect(
		overlay.find_child("FateCurrencyBalance", true, false) == null,
		"Fate purchase overlay still contains the removed top balance line",
		failures
	)
	# 顶部标题已移除（反向钉子，防误恢复）。
	_expect(
		"购 买" not in _collect_label_text(overlay),
		"Fate purchase overlay still prints its removed title",
		failures
	)
	var loot_readout := dungeon.find_child("RunLootReadout", true, false) as Label
	_expect(
		loot_readout != null and loot_readout.text.contains("金币 0"),
		"Bottom-right run-currency readout does not show the empty run wallet",
		failures
	)
	# 真实点击一张买不起的卡：不能扣金币、不能进反馈锁定态、也不能关弹窗。
	var first_button := overlay.find_child("FateChoiceCard_0", true, false) as Button
	dungeon.call("_on_reference_fate_card_pressed", first_button, 0)
	_expect(not bool(dungeon.get("_fate_feedback_locked")), "Unaffordable card still entered the locked press feedback", failures)
	_expect(bool(dungeon.get("_door_fate_active")), "Unaffordable card press closed the overlay", failures)
	_expect(GameManager.currency == 0, "Unaffordable card press spent run currency", failures)

	# —— 1b) 卡上 / 金币读数上的拒绝反馈（业主 2026-10-15：反馈要更容易被看到）——
	# 状态栏在屏幕左上角，玩家的视线在三张卡上；所以「买不起」必须同时落在**卡**和
	# **右下金币读数**上（2026-10-15 余额行移除后读数是唯一金币口径）。
	# 三条各钉一个可见证据：卡片抖动 · 价格行闪亮 · 金币读数转警示色。
	_expect(
		not (dungeon.get("_fate_shake_tweens") as Dictionary).is_empty(),
		"Card rejection feedback did not shake the card column",
		failures
	)
	_expect(
		dungeon.get("_fate_balance_warn_tween") != null,
		"Unaffordable purchase did not warn the run-currency readout",
		failures
	)
	_expect(
		loot_readout != null
		and loot_readout.get_theme_color("font_color").is_equal_approx(Dungeon3D.FATE_BALANCE_SHORTAGE_COLOR),
		"Run-currency readout did not turn into its shortage colour",
		failures
	)
	# 价格行闪烁是 tween：点击当帧还没开始推进，等 50 ms 再读乘性提亮（>1 才算「亮过」）。
	await get_tree().create_timer(0.05).timeout
	var reject_price_label := first_button.get_meta("tarot_price_label") as Label
	_expect(
		reject_price_label != null and reject_price_label.modulate.r > 1.0,
		"Card rejection feedback did not flash the price line (modulate %s)"
		% [reject_price_label.modulate if reject_price_label != null else "null"],
		failures
	)

	# —— 2) 买得起的卡：按下即扣金币、卡位标记已购买、弹窗保持打开 ——
	var first_card := choices[0] as FateCard
	var first_price := int(Dungeon3D.FATE_PRICE_BY_RARITY[int(first_card.card_rarity)])
	_set_run_currency(first_price + 5)
	dungeon.call("_refresh_door_fate_prices")
	var before_buy := GameManager.currency
	dungeon.call("_on_reference_fate_card_pressed", first_button, 0)
	await _wait_purchased(overlay, 0)
	# 扣款反馈：右下金币读数上方浮出「-N 金币」飘字，把这次花掉多少写明白。
	# 断言紧贴购买完成 —— 飘字只活 0.9 秒，等翻牌动画收束后再读就可能已经自毁了。
	var spend_popup := overlay.find_child("FateCurrencySpendPopup", true, false) as Label
	_expect(
		spend_popup != null and spend_popup.text.contains(str(first_price)),
		"Purchase did not spell out the spent amount next to the currency readout",
		failures
	)
	await _wait_fate_cards_flipped(overlay)
	var bought := bool(first_button.get_meta("tarot_purchased", false))
	_expect(bought, "Affordable card press did not buy the card", failures)
	if bought:
		_expect(before_buy - GameManager.currency == first_price, "Purchase spent a different amount than the card price", failures)
		_expect(bool(dungeon.get("_door_fate_active")), "Buying a card closed the overlay instead of keeping it open", failures)
		var price_label_after := first_button.get_meta("tarot_price_label") as Label
		_expect(price_label_after != null and price_label_after.text == "已购买", "Bought card does not show its purchased state", failures)
		# 买下的卡必须**翻回背面**：卡位用掉了，还露着牌面会被当成「还能再买一次」。
		# 等动画收束再断言 —— `tarot_purchased` 是事务里同步打的，翻背要 0.36 秒。
		var flipped_back := await _wait_card_back(overlay, 0)
		var face_after := (first_button.get_meta("tarot_face_node") if first_button.has_meta("tarot_face_node") else null) as Control
		var back_after := (first_button.get_meta("tarot_back_node") if first_button.has_meta("tarot_back_node") else null) as Control
		_expect(flipped_back, "Bought card did not flip back to its back face within the animation budget", failures)
		_expect(
			face_after != null and not face_after.visible,
			"Bought card still shows its face instead of flipping to the back",
			failures
		)
		_expect(
			back_after != null and back_after.visible,
			"Bought card did not flip to its back",
			failures
		)
		_expect(
			str(first_button.get_meta("tarot_face_side", "")) == "back",
			"Bought card does not report its back side",
			failures
		)
		# 翻回背面**不能**把卡变成不可聚焦：购买制下焦点链要经过卡列回退出按钮。
		_expect(
			not first_button.disabled and bool(first_button.get_meta("tarot_face_ready", false)),
			"Bought card became unfocusable after flipping back",
			failures
		)
		# —— 已购卡的三件套：灰阶 + 压暗 + 缩到 70%（业主 2026-10-14 要求）——
		# ① 去色必须真的挂上灰度材质。只用 `modulate` 压暗是**去不掉色相**的
		#    —— 卡背是亮青绿线稿，压完只会变成「暗绿」，这一条正是那个 bug 的反向钉子。
		_expect(
			back_after != null and (back_after as CanvasItem).material is ShaderMaterial
			and ((back_after as CanvasItem).material as ShaderMaterial).shader != null,
			"Bought card back has no greyscale shader material",
			failures
		)
		if back_after != null and (back_after as CanvasItem).material is ShaderMaterial:
			var grey_code := (((back_after as CanvasItem).material as ShaderMaterial).shader).code
			_expect(
				"luminance" in grey_code and "COLOR = vec4(vec3(luminance)" in grey_code,
				"Bought card greyscale shader does not desaturate by luminance",
				failures
			)
		# ② 压暗：整列 modulate 必须是已购档，而不是未购的白。
		# 除了「和常量一致」，另钉一条**绝对上限 0.50** —— 主人 2026-10-14 连提两次要暗
		# （0.62 → 0.40），只跟常量比的话，谁把常量改回亮档这条也照样绿，拦不住回退。
		var first_view := first_button.get_meta("fate_feedback_view") as Control
		_expect(
			first_view != null
			and first_view.modulate.r < 0.75 and first_view.modulate.g < 0.75 and first_view.modulate.b < 0.75,
			"Bought card column is not dimmed (modulate %s)" % [first_view.modulate if first_view != null else "null"],
			failures
		)
		_expect(
			first_view != null and is_equal_approx(first_view.modulate.r, Dungeon3D.FATE_PURCHASED_DIM_COLOR.r),
			"Bought card column dim does not match FATE_PURCHASED_DIM_COLOR (actual %s)"
			% [first_view.modulate if first_view != null else "null"],
			failures
		)
		_expect(
			first_view != null and first_view.modulate.r <= 0.50,
			"Bought card column is not dark enough (modulate %.2f, ceiling 0.50)"
			% [first_view.modulate.r if first_view != null else 1.0],
			failures
		)
		# ③ 缩小到 70%。这是**基准缩放**：后续任何悬停/复位都不得把它弹回 100%。
		_expect(
			first_view != null
			and is_equal_approx(first_view.scale.x, Dungeon3D.FATE_PURCHASED_CARD_SCALE)
			and is_equal_approx(first_view.scale.y, Dungeon3D.FATE_PURCHASED_CARD_SCALE),
			"Bought card is not scaled to %.2f (actual %s)" % [
				Dungeon3D.FATE_PURCHASED_CARD_SCALE, first_view.scale if first_view != null else Vector2.ZERO,
			],
			failures
		)
		# ③b 卡背**半透明**（业主 2026-10-15 要求「翻过去的命运卡做半透明，更淡一些」）。
		# 只淡卡背贴图层，不淡整列 —— 理由见下一条 ④b 的反向钉子。
		var back_canvas := back_after as CanvasItem
		_expect(
			back_canvas != null
			and back_canvas.modulate.a < 1.0
			and is_equal_approx(back_canvas.modulate.a, Dungeon3D.FATE_PURCHASED_CARD_ALPHA),
			"Bought card back is not translucent (alpha %s)"
			% [back_canvas.modulate.a if back_canvas != null else 1.0],
			failures
		)
		# ④ 卡下说明也要去色：它原本按作用域着色（紫/金/浅蓝），留着会和灰阶卡面打架。
		var caption_after := (first_button.get_meta("tarot_caption_label") if first_button.has_meta("tarot_caption_label") else null) as Label
		_expect(caption_after != null, "Bought card is missing its caption label reference", failures)
		if caption_after != null:
			var caption_color := caption_after.get_theme_color("font_color")
			_expect(
				is_equal_approx(caption_color.r, caption_color.g)
				and is_equal_approx(caption_color.g, caption_color.b),
				"Bought card caption kept a coloured scope tint: %s" % caption_color,
				failures
			)
		# ④b 文字**不跟着半透明**。这是「淡卡不淡字」这条设计的反向钉子：
		# 整列调 alpha 会把「已购买」压到 0.72 × 0.40 × α ≈ 0.13 的有效亮度，直接读不出来 ——
		# 而这行字是这张卡唯一还需要被读到的事实（它证明这张卡买过了）。
		_expect(
			caption_after != null and is_equal_approx(caption_after.modulate.a, 1.0),
			"Bought card caption went translucent together with the card (alpha %s)"
			% [caption_after.modulate.a if caption_after != null else 1.0],
			failures
		)
		_expect(
			price_label_after != null and is_equal_approx(price_label_after.modulate.a, 1.0),
			"Bought card price line went translucent together with the card (alpha %s)"
			% [price_label_after.modulate.a if price_label_after != null else 1.0],
			failures
		)
		# 已购买的卡：鼠标悬停不再放大（主人 2026-10-14 要求）。
		dungeon.call("_on_reference_fate_card_hover", first_button, true)
		await get_tree().create_timer(0.28).timeout
		_expect(
			first_view != null
			and is_equal_approx(first_view.scale.x, Dungeon3D.FATE_PURCHASED_CARD_SCALE),
			"Bought card zoomed away from its 70%% base scale when hovered (actual %s)"
			% [first_view.scale if first_view != null else Vector2.ZERO],
			failures
		)
		# 反向对照：同一时刻按住另一张**未购买**的卡，必须仍然放大 ——
		# 否则「不再放大」可能只是悬停反馈整体坏了，而不是按购买状态生效。
		var other_index := 1 if choices.size() > 1 else -1
		if other_index >= 0:
			var other_button := overlay.find_child("FateChoiceCard_%d" % other_index, true, false) as Button
			var other_view := (
				other_button.get_meta("fate_feedback_view") as Control if other_button != null else null
			)
			if other_button != null and not bool(other_button.get_meta("tarot_purchased", true)):
				_set_run_currency(9999)
				dungeon.call("_refresh_door_fate_prices")
				dungeon.call("_on_reference_fate_card_hover", other_button, true)
				await get_tree().create_timer(0.28).timeout
				_expect(
					other_view != null and other_view.scale.x > 1.0,
					"Unpurchased card lost its hover zoom while the bought card gained no zoom",
					failures
				)
				dungeon.call("_on_reference_fate_card_hover", other_button, false)
		dungeon.call("_on_reference_fate_card_hover", first_button, false)
		# 同一张卡不能买第二次：既不再扣金币，也不关弹窗。
		var before_second := GameManager.currency
		await dungeon.call("_on_door_fate_selected", 0)
		_expect(GameManager.currency == before_second, "Repeat purchase of the same card spent run currency again", failures)
		_expect(str(dungeon.call("_fate_card_block_reason", 0)) == "purchased", "Repeat purchase of the same card was not rejected", failures)
		# 门后事务必须随正式运行时快照保留：offer_id、候选、冻结报价和已购位不能只存在内存。
		var fate_save := dungeon.build_runtime_save_snapshot()
		var fate_state := fate_save.get("fate_run_state", {}) as Dictionary
		var door_state := fate_state.get("door", {}) as Dictionary
		_expect(int(door_state.get("offer_id", 0)) > 0, "门后快照没有保存 offer_id", failures)
		_expect((door_state.get("cards", []) as Array).size() == choices.size(), "门后快照没有保存全部候选卡", failures)
		_expect(not (door_state.get("quotes", {}) as Dictionary).is_empty(), "门后快照没有保存冻结报价", failures)
		_expect(bool(((door_state.get("cards", []) as Array)[0] as Dictionary).get("purchased", false)), "门后快照没有保存已购卡位", failures)

	# —— 3) 货币守恒：所有剩余卡的购买尝试，要么恰好扣价、要么原额保留 ——
	for index in range(1, choices.size()):
		var card := choices[index] as FateCard
		var price := int(Dungeon3D.FATE_PRICE_BY_RARITY[int(card.card_rarity)])
		_set_run_currency(price + 40)
		dungeon.call("_refresh_door_fate_prices")
		var before_attempt := GameManager.currency
		await dungeon.call("_on_door_fate_selected", index)
		var button := overlay.find_child("FateChoiceCard_%d" % index, true, false) as Button
		var did_buy := button != null and bool(button.get_meta("tarot_purchased", false))
		if did_buy:
			_expect(before_attempt - GameManager.currency == price, "Card %d bought for a wrong price" % index, failures)
		else:
			_expect(GameManager.currency == before_attempt, "Card %d failed to apply but did not refund its soul cost" % index, failures)
		_expect(bool(dungeon.get("_door_fate_active")), "Card %d attempt closed the overlay early" % index, failures)

	# —— 4) 星星卡满槽：置灰不可购买，且绝不扣金币 ——
	dungeon.call("_close_door_fate_overlay")
	instance.fate_upgrades.clear()
	for slot_index in range(instance.fate_slot_capacity):
		instance.fate_upgrades.append({
			"slot_index": slot_index + 1,
			"stable_card_id": "verify_purchase_full_%02d" % slot_index,
			"effect_version": 1,
		})
	_set_run_currency(9999)
	_expect(dungeon.show_reference_fate_overlay_for_test(), "Cannot reopen the fate purchase overlay for the full-slot contract", failures)
	overlay = dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	if overlay != null:
		var full_index := _find_blocked_card(dungeon, "slot_full")
		_expect(full_index >= 0, "A weapon card with a full target gun is not blocked in the purchase model", failures)
		if full_index >= 0:
			var before_full := GameManager.currency
			await dungeon.call("_on_door_fate_selected", full_index)
			_expect(GameManager.currency == before_full, "Full-slot weapon card purchase spent run currency", failures)
			var full_button := overlay.find_child("FateChoiceCard_%d" % full_index, true, false) as Button
			if full_button != null:
				var full_label := full_button.get_meta("tarot_price_label") as Label
				_expect(full_label != null and full_label.text == "命运槽已满", "Full-slot card does not surface its blocked reason under the card", failures)

	# —— 5) 退出按钮：屏幕下方正中、手柄可达、点一次即关闭弹窗 ——
	if overlay != null:
		var exit_button := overlay.find_child("FateExitButton", true, false) as Button
		_expect(exit_button != null, "Fate purchase overlay has no exit button", failures)
		if exit_button != null:
			_expect(
				is_equal_approx(exit_button.anchor_left, 0.5)
				and is_equal_approx(exit_button.anchor_right, 0.5)
				and is_equal_approx(exit_button.anchor_bottom, 1.0),
				"Fate exit button is not anchored to the bottom centre of the screen",
				failures
			)
			var viewport_centre := Vector2(dungeon.get_viewport().get_visible_rect().size) * 0.5
			_expect(
				absf(exit_button.get_global_rect().get_center().x - viewport_centre.x) <= 2.0,
				"Fate exit button is not horizontally centred on the screen",
				failures
			)
			# 手柄可达性：购买制下这张弹窗只有退出按钮一个出口，若焦点链走不到它，
			# 手柄玩家就被永久困在购卡界面。这里逐路径核对「卡 → 下 → 退出 → 上 → 卡」的闭环。
			for index in range(choices.size()):
				var card_button := overlay.find_child("FateChoiceCard_%d" % index, true, false) as Button
				if card_button == null:
					continue
				_expect(
					not card_button.focus_neighbor_bottom.is_empty()
					and card_button.focus_neighbor_bottom == card_button.get_path_to(exit_button),
					"Fate card %d bottom focus neighbour does not lead to the exit button" % index,
					failures
				)
			var first_card_button := overlay.find_child("FateChoiceCard_0", true, false) as Button
			_expect(
				first_card_button != null
				and not exit_button.focus_neighbor_top.is_empty()
				and exit_button.focus_neighbor_top == exit_button.get_path_to(first_card_button),
				"Fate exit button has no focus neighbour back up into the card row",
				failures
			)
			var exit_currency := GameManager.currency
			var exit_cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
			exit_button.emit_signal("pressed")
			# 退出不是硬切：同步检查覆盖层还在，重复退出不会创建第二条退场。
			_expect(bool(dungeon.get("_fate_overlay_closing")), "Fate exit did not enter the animated closing state", failures)
			_expect(dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == overlay, "Fate overlay was hard-cut before exit animation", failures)
			_expect(bool(dungeon.get("_door_fate_active")) and exit_button.disabled, "Fate exit released modal input before the animation finished", failures)
			dungeon.call("_cancel_door_fate_selection")
			var exit_deadline := Time.get_ticks_msec() + 6000
			while is_instance_valid(overlay) and float(overlay.get_meta("fate_exit_progress", 0.0)) <= 0.40 and Time.get_ticks_msec() < exit_deadline:
				await get_tree().process_frame
			_expect(is_instance_valid(overlay), "Fate exit did not expose an intermediate animation frame", failures)
			if is_instance_valid(overlay):
				for exit_card_node in exit_cards:
					var exit_card := exit_card_node as Button
					var exit_view := exit_card.get_meta("fate_feedback_view") as Control
					_expect(exit_card.disabled and exit_view.scale.x < 1.0 and exit_view.modulate.a < 1.0, "A fate card did not shrink and fade during exit", failures)
					_expect(str(exit_card.get_meta("tarot_face_side", "")) == "back", "A fate card did not flip to its back during exit", failures)
			await dungeon.call("_on_door_fate_selected", 0)
			_expect(GameManager.currency == exit_currency, "A closing fate overlay accepted another purchase", failures)
			# 等退场动画完成，再验证状态和节点都收干净。
			await _wait_overlay_closed(dungeon)
			_expect(not bool(dungeon.get("_door_fate_active")), "Fate exit button did not close the purchase overlay", failures)
			_expect(dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null, "Fate purchase overlay was not torn down", failures)

	# —— 6) 真实过门路径落到同一套购买 UI，且同样只花本局金币 ——
	await _check_real_door_purchase_entry(dungeon, failures)

	# 局外总池收尾校验：门后买卡是纯局内交易，基地抽取点一个子儿都不能动。
	_expect(
		BaseManager.get_extraction_points() == extraction_before,
		"Fate purchase touched the out-of-run extraction point pool (%d -> %d)" % [
			extraction_before, BaseManager.get_extraction_points(),
		],
		failures
	)

	dungeon.queue_free()
	_finish(failures)


## 真实过门：清房 + 钥匙后开门必须弹出同一套购卡界面（三张卡 + 卡下价格行 + 底部退出按钮）。
func _check_real_door_purchase_entry(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var first_room_id := ""
	for record in (dungeon.get("_records") as Array):
		if str((record as Dictionary).get("parent", "")) == "start":
			first_room_id = str((record as Dictionary).get("id", ""))
			break
	if first_room_id.is_empty():
		_expect(false, "Could not find a room adjacent to the start room for the real door contract", failures)
		return
	dungeon.set("_room_key_count", 5)
	var start_room := (dungeon.get("_room_by_id") as Dictionary).get(str(dungeon.get("_current_room_id"))) as DungeonRoom3D
	if start_room == null:
		_expect(false, "Could not resolve the current room for the real door contract", failures)
		return
	start_room.cleared = true
	_set_run_currency(9999)
	if not dungeon.try_open_room_door(first_room_id):
		_expect(false, "Real door did not open for the purchase-entry contract", failures)
		return
	await get_tree().process_frame
	_expect(bool(dungeon.get("_door_fate_active")), "Real door did not open the fate purchase overlay", failures)
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	if overlay == null:
		_expect(false, "Real door fate purchase overlay node is missing", failures)
		return
	var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
	_expect(cards.size() == 3, "Real door purchase overlay does not show three cards", failures)
	for card_node in cards:
		var button := card_node as Button
		var price_label := (button.get_meta("tarot_price_label") if button.has_meta("tarot_price_label") else null) as Label
		_expect(price_label != null, "Real door purchase card has no price line", failures)
	_expect(overlay.find_child("FateExitButton", true, false) != null, "Real door purchase overlay has no exit button", failures)
	dungeon.call("_cancel_door_fate_selection")
	await _wait_overlay_closed(dungeon)
	_expect(not bool(dungeon.get("_door_fate_active")), "Real door purchase overlay did not close on exit", failures)


func _find_blocked_card(dungeon: Dungeon3D, reason: String) -> int:
	var choices := dungeon.get("_door_fate_choices") as Array
	for index in range(choices.size()):
		if str(dungeon.call("_fate_card_block_reason", index)) == reason:
			return index
	return -1


## 把本局金币精确设成目标值：走 `add_currency` / `spend_currency` 以便同步 `_run_value` 与自动存档。
func _set_run_currency(target: int) -> void:
	var delta := maxi(0, target) - GameManager.currency
	if delta > 0:
		GameManager.add_currency(delta)
	elif delta < 0:
		GameManager.spend_currency(-delta)


func _wait_purchased(overlay: Control, index: int) -> void:
	var deadline_ms := 6000
	var elapsed_ms := 0
	while elapsed_ms < deadline_ms:
		var button := overlay.find_child("FateChoiceCard_%d" % index, true, false) as Button
		if button != null and bool(button.get_meta("tarot_purchased", false)):
			return
		await get_tree().create_timer(0.05).timeout
		elapsed_ms += 50


## 三张卡是否都已翻面并解除「翻牌期间禁点」（与 `_finish_reference_tarot_flip` 等价）。
func _fate_cards_flipped(overlay: Control) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
	if cards.size() != 3:
		return false
	for card_node in cards:
		var card := card_node as Button
		if card.disabled or not bool(card.get_meta("tarot_face_ready", false)):
			return false
	return true


## 等某张卡**真的翻回背面**：`tarot_purchased` 是在购买事务里同步打上的，
## 而翻背是 0.36 秒的 tween（同样的 90° 薄边换面手法）。买完立刻断言会必然踩空 ——
## 这里按真实时间轮询到卡面隐藏、卡背显示为止。
func _wait_card_back(overlay: Control, index: int) -> bool:
	var deadline_ms := 6000
	var elapsed_ms := 0
	while elapsed_ms < deadline_ms:
		var button := overlay.find_child("FateChoiceCard_%d" % index, true, false) as Button
		if button != null:
			var face := (button.get_meta("tarot_face_node") if button.has_meta("tarot_face_node") else null) as Control
			var back := (button.get_meta("tarot_back_node") if button.has_meta("tarot_back_node") else null) as Control
			if (
				face != null and not face.visible
				and back != null and back.visible
				and str(button.get_meta("tarot_face_side", "")) == "back"
			):
				return true
		await get_tree().create_timer(0.05).timeout
		elapsed_ms += 50
	return false


## 等退出退场动画真正完成；不能用固定等待，否则慢机器会把已完成的动画误判成未关闭。
func _wait_overlay_closed(dungeon: Dungeon3D) -> void:
	var deadline_ms := 6000
	var elapsed_ms := 0
	while elapsed_ms < deadline_ms:
		if not bool(dungeon.get("_door_fate_active")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null:
			return
		await get_tree().create_timer(0.05).timeout
		elapsed_ms += 50


## 弹窗里所有 Label 的文字拼一起，用于「标题已移除」这类反向断言。
func _collect_label_text(root: Node) -> String:
	var result := ""
	for label_node in root.find_children("*", "Label", true, false):
		result += "\n" + (label_node as Label).text
	return result


## 按**真实时间**轮询：headless 下 process 帧不做垂直同步，固定帧数可能只累积极短的真实 delta。
func _wait_fate_cards_flipped(overlay: Control) -> void:
	var deadline_ms := 6000
	var elapsed_ms := 0
	while elapsed_ms < deadline_ms:
		if _fate_cards_flipped(overlay):
			return
		await get_tree().create_timer(0.05).timeout
		elapsed_ms += 50


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FATE_CARD_PURCHASE_FLOW_OK: three cards are all offered with rarity prices, souls are only ever spent in exact card-price amounts, a full-slot star card is unbuyable without spending, the bottom-centre exit button closes the overlay, and the out-of-run extraction pool stays untouched")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
