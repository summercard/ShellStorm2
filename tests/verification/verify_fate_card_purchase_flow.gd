extends Node

## 既有购卡回归：仅将旧表现契约迁到正式全息板，交易与输入断言保持严格。
## test_mode fixture 验稀有度表；生产入口另验开门不弹卡、命运凭据主动交互。
const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const TRANSITION := preload("res://src/ui/weapon_build/WeaponHologramTransition.gd")


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
		_expect(false, "玩家没有武器实例", failures)
		_finish(failures)
		return
	var extraction_before := BaseManager.get_extraction_points()

	# 1) 金币不足：保留精确报价、唯一余额、提权及拒绝反馈契约。
	_set_run_currency(0)
	instance.fate_upgrades.clear()
	_expect(dungeon.show_reference_fate_overlay_for_test(), "无法打开购卡fixture", failures)
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	_expect(overlay != null, "购卡层缺失", failures)
	if overlay == null:
		_finish(failures)
		return
	await _wait_fate_cards_flipped(overlay)
	var choices := (dungeon.get("_door_fate_choices") as Array).duplicate()
	_expect(choices.size() == 3, "没有同时提供三张卡", failures)
	for index in choices.size():
		var card := choices[index] as FateCard
		var button := overlay.find_child("FateChoiceCard_%d" % index, true, false) as Button
		_expect(button != null, "卡位 %d 缺失" % index, failures)
		if button == null:
			continue
		var price_label := button.get_meta("tarot_price_label") as Label
		var purchase := button.get_meta("tarot_purchase_button") as Button
		var price := int(Dungeon3D.FATE_PRICE_BY_RARITY[int(card.card_rarity)])
		_expect(price_label != null and price_label.text == "购买  %d" % price, "购买按钮没有精确显示报价", failures)
		_expect(price_label != null and "还差" not in price_label.text and "区间" not in price_label.text, "已移除的差额/区间文案回流", failures)
		_expect(purchase != null and purchase.is_ancestor_of(price_label) and purchase.is_visible_in_tree(), "报价未落在真实购买按钮上", failures)
		_expect(int(button.get_meta("tarot_price", -1)) == price, "fixture报价不等于稀有度表", failures)
		_expect(str(dungeon.call("_fate_card_block_reason", index)) == "insufficient", "空钱包未拒绝卡位 %d" % index, failures)
	_expect(overlay.find_child("FateCurrencyBalance", true, false) == null, "恢复了重复的顶部余额行", failures)
	_expect("购 买" not in _collect_label_text(overlay), "恢复了已移除标题", failures)
	var loot_readout := dungeon.find_child("RunLootReadout", true, false) as Label
	_expect(loot_readout != null and loot_readout.text.contains("金币 0"), "右下唯一读数没有显示空钱包", failures)
	if loot_readout != null:
		var loot_effective_z := loot_readout.z_index
		var loot_parent := loot_readout.get_parent() as Control
		if loot_parent != null:
			loot_effective_z += loot_parent.z_index
		_expect(loot_effective_z > overlay.z_index, "唯一金币读数仍被遮罩压暗", failures)
	var first_button := overlay.find_child("FateChoiceCard_0", true, false) as Button
	dungeon.call("_on_reference_fate_card_pressed", first_button, 0)
	_expect(not bool(dungeon.get("_fate_feedback_locked")) and not bool(dungeon.get("_fate_purchase_busy")), "买不起仍锁定事务", failures)
	_expect(bool(dungeon.get("_door_fate_active")) and GameManager.currency == 0, "买不起仍扣款或关闭弹层", failures)
	_expect(dungeon.get("_fate_confirm") == null, "买不起仍进入不可逆确认", failures)
	_expect(not (dungeon.get("_fate_shake_tweens") as Dictionary).is_empty(), "拒绝没有抖动卡列", failures)
	_expect(dungeon.get("_fate_balance_warn_tween") != null, "拒绝没有警示金币读数", failures)
	_expect(loot_readout != null and loot_readout.get_theme_color("font_color").is_equal_approx(Dungeon3D.FATE_BALANCE_SHORTAGE_COLOR), "金币读数未转警示色", failures)
	await get_tree().create_timer(0.05).timeout
	var reject_price := first_button.get_meta("tarot_price_label") as Label
	_expect(reject_price != null and reject_price.modulate.r > 1.0, "拒绝没有提亮价格行", failures)

	# 2) 武器卡先确认默认否，再确认是；确认之前不扣款、不刻槽。
	var first_card := choices[0] as FateCard
	var first_price := int(Dungeon3D.FATE_PRICE_BY_RARITY[int(first_card.card_rarity)])
	_set_run_currency(first_price + 5)
	dungeon.call("_refresh_door_fate_prices")
	var before_buy := GameManager.currency
	var before_item := dungeon.player.get_equipped_weapon_item().duplicate(true)
	var original_size := first_button.size
	dungeon.call("_on_reference_fate_card_pressed", first_button, 0)
	_expect(dungeon.get("_fate_confirm") != null, "武器卡点击未弹确认", failures)
	var focus := get_viewport().gui_get_focus_owner() as Button
	_expect(focus != null and focus.text == "否", "不可逆确认未默认聚焦否", failures)
	_expect(GameManager.currency == before_buy and before_item == dungeon.player.get_equipped_weapon_item(), "确认前已扣款或修改枪", failures)
	_expect(bool(dungeon.get("_fate_purchase_busy")), "确认期间没有事务忙锁", failures)
	_answer(dungeon, false, failures)
	await _wait_idle(dungeon, failures)
	_expect(GameManager.currency == before_buy and before_item == dungeon.player.get_equipped_weapon_item(), "否取消仍改变金币或枪", failures)
	_expect(not bool(first_button.get_meta("tarot_purchased", true)), "否取消仍标记已购", failures)
	dungeon.call("_on_reference_fate_card_pressed", first_button, 0)
	_answer(dungeon, true, failures)
	var board := dungeon.get("_fate_board") as Control
	var pending := _board_snapshot(dungeon)
	_expect(int(pending.get("pending_slot", -1)) == 1, "成功提交未进入第一槽pending", failures)
	var pending_cards := pending.get("cards", []) as Array
	_expect(not pending_cards.is_empty(), "pending板没有卡巢", failures)
	if not pending_cards.is_empty():
		var entry := pending_cards[0] as Dictionary
		_expect(bool(entry.get("pending", false)) and bool(entry.get("shows_back", false)) and not bool(entry.get("occupied", true)), "在途卡提前显示为已占用牌面", failures)
	var deducted := GameManager.currency
	dungeon.call("_on_door_fate_selected", 0)
	dungeon.call("_cancel_door_fate_selection")
	_expect(GameManager.currency == deducted and bool(dungeon.get("_door_fate_active")) and not bool(dungeon.get("_fate_overlay_closing")), "提交期间重复购卡或退出穿透忙锁", failures)
	var spend_popup := overlay.find_child("FateCurrencySpendPopup", true, false) as Label
	_expect(spend_popup != null and spend_popup.text.contains(str(first_price)), "扣款没有精确金额飘字", failures)
	await _wait_idle(dungeon, failures)
	var bought := bool(first_button.get_meta("tarot_purchased", false))
	_expect(bought, "确认是后未完成购买", failures)
	_expect(before_buy - GameManager.currency == first_price, "成功购买未恰好扣报价", failures)
	_expect(bool(dungeon.get("_door_fate_active")), "购买后提前关闭弹层", failures)
	var price_after := first_button.get_meta("tarot_price_label") as Label
	_expect(price_after != null and price_after.text == "已购买", "购买按钮没有已购文案", failures)
	# 旧70%灰背已退役：原位同尺寸占位，真实牌面落到board的永久巢。
	var face := first_button.get_meta("tarot_face_node") as Control
	var back := first_button.get_meta("tarot_back_node") as Control
	var first_view := first_button.get_meta("fate_feedback_view") as Control
	_expect(face != null and not face.visible and back != null and not back.visible, "已购位仍展示可买牌面或旧灰背", failures)
	_expect(str(first_button.get_meta("tarot_face_side", "")) == "purchased" and first_button.text == "已购买\n01", "已购占位身份错误", failures)
	_expect(not first_button.disabled and bool(first_button.get_meta("tarot_face_ready", false)), "已购卡切断焦点链", failures)
	_expect(first_button.size.is_equal_approx(original_size) and first_button.scale.is_equal_approx(Vector2.ONE), "已购占位尺寸发生变化", failures)
	_expect(first_view != null and first_view.scale.is_equal_approx(Vector2.ONE) and first_view.modulate.is_equal_approx(Color.WHITE), "已购位恢复了旧缩小/压暗表现", failures)
	var caption := first_button.get_meta("tarot_caption_label") as Label
	_expect(caption != null and is_equal_approx(caption.modulate.a, 1.0) and price_after != null and is_equal_approx(price_after.modulate.a, 1.0), "已购功能文字或购买状态变为半透明", failures)
	var settled := _board_snapshot(dungeon)
	_expect(board != null and board.is_visible_in_tree() and int(settled.get("used", -1)) == 1 and int(settled.get("committed_used", -1)) == 1 and int(settled.get("pending_slot", 0)) == -1, "永久卡没有完成真实落巢", failures)
	for entry: Dictionary in settled.get("cards", []):
		var occupied := int(entry.get("slot_index", 0)) == 1
		_expect(bool(entry.get("occupied", false)) == occupied and bool(entry.get("shows_back", false)) == not occupied and not bool(entry.get("pending", true)), "稳定态牌面/空卡背/pending错误", failures)
	dungeon.call("_on_reference_fate_card_hover", first_button, true)
	await get_tree().create_timer(0.28).timeout
	_expect(first_view.scale.is_equal_approx(Vector2.ONE), "已购占位悬停后放大", failures)
	var other_button := overlay.find_child("FateChoiceCard_1", true, false) as Button
	_set_run_currency(9999)
	dungeon.call("_refresh_door_fate_prices")
	dungeon.call("_on_reference_fate_card_hover", other_button, true)
	await get_tree().create_timer(0.28).timeout
	var other_view := other_button.get_meta("fate_feedback_view") as Control
	_expect(other_view != null and other_view.scale.x > 1.0, "未购卡丢失悬停放大对照", failures)
	dungeon.call("_on_reference_fate_card_hover", other_button, false)
	dungeon.call("_on_reference_fate_card_hover", first_button, false)
	var before_second := GameManager.currency
	await dungeon.call("_on_door_fate_selected", 0)
	_expect(GameManager.currency == before_second and str(dungeon.call("_fate_card_block_reason", 0)) == "purchased", "已购卡重复扣款或未拒绝", failures)
	_expect(dungeon.get("_fate_confirm") == null, "已购位再次弹确认", failures)
	var fate_state := dungeon.build_runtime_save_snapshot().get("fate_run_state", {}) as Dictionary
	var door_state := fate_state.get("door", {}) as Dictionary
	_expect(int(door_state.get("offer_id", 0)) > 0, "快照未保存offer_id", failures)
	var saved_cards := door_state.get("cards", []) as Array
	_expect(saved_cards.size() == choices.size(), "快照未保存全部候选", failures)
	_expect(not (door_state.get("quotes", {}) as Dictionary).is_empty(), "快照未保存冻结报价", failures)
	_expect(not saved_cards.is_empty() and bool((saved_cards[0] as Dictionary).get("purchased", false)), "快照未保存已购位", failures)

	# 3) 其余作用域仍按准确报价交易，不占武器槽；失败必须原额退款。
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
			_expect(before_attempt - GameManager.currency == price, "作用域卡扣费不等于报价", failures)
		else:
			_expect(GameManager.currency == before_attempt, "作用域卡失败未原额退款", failures)
		print("FATE_SCOPE_ATTEMPT index=%d id=%s purchased=%s before=%d after=%d status=%s" % [index, card.get_stable_card_id(), did_buy, before_attempt, GameManager.currency, dungeon.status_label.text])
		_expect(dungeon.player.get_equipped_weapon_instance().fate_upgrades.size() == 1, "世界/角色卡占用枪槽", failures)
		_expect(bool(dungeon.get("_door_fate_active")), "作用域卡尝试提前关层", failures)

	# 3b) 来源取消走真实预扣款/失败退款，而非只验证余额不足的零扣款。
	dungeon.call("_close_door_fate_overlay")
	_expect(dungeon.show_reference_fate_overlay_for_test(), "无法打开退款fixture", failures)
	var refund_choices := dungeon.get("_door_fate_choices") as Array
	refund_choices[0] = FateCardPresets.gun_on_gun()
	var refund_quotes := dungeon.get("_fate_door_quote") as Dictionary
	refund_quotes[refund_choices[0].get_stable_card_id()] = int(Dungeon3D.FATE_PRICE_BY_RARITY[int(refund_choices[0].card_rarity)])
	dungeon.call("_build_door_fate_overlay")
	overlay = dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	await _wait_fate_cards_flipped(overlay)
	_set_run_currency(9999)
	dungeon.call("_refresh_door_fate_prices")
	var refund_before := GameManager.currency
	var refund_item := dungeon.player.get_equipped_weapon_item().duplicate(true)
	dungeon.call("_on_door_fate_selected", 0)
	_answer(dungeon, true, failures)
	var source_deadline := Time.get_ticks_msec() + 6000
	while FateCardGameBridge.get_node_or_null("FateSourceSelectionPanel") == null and bool(dungeon.get("_fate_purchase_busy")) and Time.get_ticks_msec() < source_deadline:
		await get_tree().process_frame
	var source := FateCardGameBridge.get_node_or_null("FateSourceSelectionPanel")
	_expect(source != null, "真实来源选择窗口未出现", failures)
	if source != null:
		_expect(refund_before - GameManager.currency == int(dungeon.call("_fate_price", refund_choices[0])), "来源选择前未精确预扣款", failures)
		source.call("cancel")
	await _wait_idle(dungeon, failures)
	_expect(GameManager.currency == refund_before and dungeon.player.get_equipped_weapon_item() == refund_item, "来源取消没有全额退款或修改了枪", failures)
	_expect(not bool((dungeon.get("_door_fate_purchased") as Array)[0]) and int(_board_snapshot(dungeon).get("pending_slot", 0)) == -1, "失败仍标已购或残留pending", failures)

	# 4) 满槽拒绝：原因可见，不扣款、不确认、不关闭。
	dungeon.call("_close_door_fate_overlay")
	instance = dungeon.player.get_equipped_weapon_instance()
	instance.fate_upgrades.clear()
	for slot_index in instance.fate_slot_capacity:
		instance.fate_upgrades.append({"slot_index": slot_index + 1, "stable_card_id": "verify_purchase_full_%02d" % slot_index, "effect_version": 1})
	_set_run_currency(9999)
	_expect(dungeon.show_reference_fate_overlay_for_test(), "无法打开满槽fixture", failures)
	overlay = dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	await _wait_fate_cards_flipped(overlay)
	var full_index := _find_blocked_card(dungeon, "slot_full")
	_expect(full_index >= 0, "满槽武器卡没有被模型拒绝", failures)
	if full_index >= 0:
		var before_full := GameManager.currency
		await dungeon.call("_on_door_fate_selected", full_index)
		_expect(GameManager.currency == before_full and dungeon.get("_fate_confirm") == null, "满槽尝试仍扣款或弹确认", failures)
		var full_button := overlay.find_child("FateChoiceCard_%d" % full_index, true, false) as Button
		var full_label := full_button.get_meta("tarot_price_label") as Label
		_expect(full_label != null and full_label.text == "命运槽已满", "满槽原因未显示", failures)

	# 5) 卡→购买按钮→退出→卡焦点闭环；退场仍持有输入锁，不可重复交易。
	var exit_button := overlay.find_child("FateExitButton", true, false) as Button
	_expect(exit_button != null, "缺少退出按钮", failures)
	if exit_button != null:
		_expect(is_equal_approx(exit_button.anchor_left, 0.5) and is_equal_approx(exit_button.anchor_right, 0.5) and is_equal_approx(exit_button.anchor_bottom, 1.0), "退出按钮未锚定底部正中", failures)
		var viewport_centre := Vector2(dungeon.get_viewport().get_visible_rect().size) * 0.5
		_expect(absf(exit_button.get_global_rect().get_center().x - viewport_centre.x) <= 2.0, "退出按钮未水平居中", failures)
		for index in choices.size():
			var card_button := overlay.find_child("FateChoiceCard_%d" % index, true, false) as Button
			var purchase := card_button.get_meta("tarot_purchase_button") as Button
			_expect(purchase != null and card_button.focus_neighbor_bottom == card_button.get_path_to(purchase), "卡焦点无法下移到购买按钮", failures)
			if purchase != null:
				_expect(purchase.focus_neighbor_top == purchase.get_path_to(card_button) and purchase.focus_neighbor_bottom == purchase.get_path_to(exit_button), "购买按钮焦点未连接卡和退出", failures)
		var first := overlay.find_child("FateChoiceCard_0", true, false) as Button
		_expect(first != null and exit_button.focus_neighbor_top == exit_button.get_path_to(first), "退出焦点无法回卡列", failures)
		var exit_currency := GameManager.currency
		var presentation := dungeon.get("_fate_presentation") as Control
		board = dungeon.get("_fate_board") as Control
		exit_button.pressed.emit()
		_expect(bool(dungeon.get("_fate_overlay_closing")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == overlay, "退出硬切而非动画退场", failures)
		_expect(bool(dungeon.get("_door_fate_active")) and dungeon.player.input_locked and exit_button.disabled, "退场提前释放模态输入", failures)
		var exit_tween: Tween = board.get_meta(TRANSITION.TWEEN_KEY) as Tween
		exit_tween.pause()
		exit_tween.custom_step(0.10)
		_expect(not (presentation.get("row") as Control).visible and board.visible and board.scale.x < 1.0 and board.modulate.a < 1.0, "退场未隐藏候选并收起全息板", failures)
		dungeon.call("_cancel_door_fate_selection")
		_expect(board.get_meta(TRANSITION.TWEEN_KEY) == exit_tween, "重复退出创建第二条退场", failures)
		await dungeon.call("_on_door_fate_selected", 0)
		_expect(GameManager.currency == exit_currency, "退场仍接受购买", failures)
		exit_tween.play()
		await _wait_overlay_closed(dungeon)
		_expect(not bool(dungeon.get("_door_fate_active")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null, "退出未清理弹层", failures)
		_expect(not dungeon.player.input_locked, "退场完成仍锁玩家", failures)
		var readout_after := dungeon.find_child("RunLootReadout", true, false) as Label
		_expect(readout_after == null or readout_after.z_index == 0, "关闭后余额读数未恢复层级", failures)

	# 6) 生产路径：门仅通行，凭据通过正式构造口和主动交互创建同一购卡事务。
	await _check_real_pickup_purchase_entry(dungeon, failures)
	_expect(BaseManager.get_extraction_points() == extraction_before, "纯局内交易改变基地抽取点：%d -> %d" % [extraction_before, BaseManager.get_extraction_points()], failures)
	dungeon.queue_free()
	_finish(failures)


func _check_real_pickup_purchase_entry(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var first_room_id := ""
	for record: Dictionary in dungeon.get("_records"):
		if str(record.get("parent", "")) == "start":
			first_room_id = str(record.get("id", ""))
			break
	var room := (dungeon.get("_room_by_id") as Dictionary).get(str(dungeon.get("_current_room_id"))) as DungeonRoom3D
	_expect(not first_room_id.is_empty() and room != null, "无法定位真实过门fixture", failures)
	if first_room_id.is_empty() or room == null:
		return
	dungeon.set("_room_key_count", 5)
	room.cleared = true
	_set_run_currency(9999)
	var entry_currency := GameManager.currency
	var offer_before := int(dungeon.get("_fate_door_offer_id"))
	_expect(dungeon.try_open_room_door(first_room_id), "清房有钥匙仍无法开门", failures)
	await get_tree().create_timer(0.30).timeout
	_expect(not bool(dungeon.get("_door_fate_active")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null and int(dungeon.get("_fate_door_offer_id")) == offer_before, "开门仍创建购卡事务", failures)
	_expect(GameManager.currency == entry_currency, "开门消耗了购卡金币", failures)
	var item := ItemRegistry.get_instance().get_item("item_fate_card_drop").duplicate(true)
	var pickup_id := "verification:purchase:room:credential"
	item.merge({"type": "fate_pickup", "id": "item_fate_card_drop", "fate_pickup_id": pickup_id, "fate_source": "verification", "source_room_id": room.room_id}, true)
	var pickup := dungeon.call("_create_ground_pickup", item) as FateCardDropPickup3D
	_expect(pickup != null, "正式构造口未生成命运凭据", failures)
	if pickup == null:
		return
	room.add_child(pickup)
	pickup.global_position = dungeon.player.global_position
	var candidate := pickup.get_interaction_candidate(dungeon.player)
	_expect(not candidate.is_empty() and pickup.perform_interaction(dungeon.player, candidate), "合法凭据主动交互未进入购卡", failures)
	_expect(bool(dungeon.get("_door_fate_active")) and str(dungeon.get("_fate_offer_source")) == "pickup" and str(dungeon.get("_fate_offer_pickup_id")) == pickup_id, "购卡事务未绑定凭据来源", failures)
	_expect(int(dungeon.get("_fate_door_offer_id")) == offer_before + 1 and GameManager.currency == entry_currency, "凭据创建事务不幂等或提前扣款", failures)
	var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	_expect(overlay != null, "凭据购卡弹层缺失", failures)
	if overlay != null:
		await _wait_fate_cards_flipped(overlay)
		var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
		_expect(cards.size() == 3 and dungeon.get("_fate_board") != null, "生产凭据未进入同一三卡/board UI", failures)
		for node in cards:
			var button := node as Button
			_expect(button.has_meta("tarot_price_label") and int(button.get_meta("tarot_price", 0)) > 0, "生产候选没有真实报价", failures)
		_expect(overlay.find_child("FateExitButton", true, false) != null, "生产购卡缺少退出", failures)
	if is_instance_valid(pickup):
		_expect(not pickup.perform_interaction(dungeon.player, candidate), "同一凭据重复创建事务", failures)
	dungeon.call("_cancel_door_fate_selection")
	await _wait_overlay_closed(dungeon)
	_expect(not bool(dungeon.get("_door_fate_active")) and GameManager.currency == entry_currency, "生产购卡退出未清理或无购买却扣款", failures)


func _answer(dungeon: Dungeon3D, accepted: bool, failures: Array[String]) -> void:
	var confirm := dungeon.get("_fate_confirm") as Control
	_expect(confirm != null, "不可逆确认控件缺失", failures)
	if confirm == null:
		return
	for node in confirm.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == ("是" if accepted else "否"):
			button.pressed.emit()
			return
	_expect(false, "真实确认按钮缺失", failures)


func _board_snapshot(dungeon: Dungeon3D) -> Dictionary:
	var board := dungeon.get("_fate_board") as Control
	return board.call("get_presentation_snapshot") as Dictionary if board != null else {}


func _find_blocked_card(dungeon: Dungeon3D, reason: String) -> int:
	for index in (dungeon.get("_door_fate_choices") as Array).size():
		if str(dungeon.call("_fate_card_block_reason", index)) == reason:
			return index
	return -1


func _set_run_currency(target: int) -> void:
	var delta := maxi(0, target) - GameManager.currency
	if delta > 0:
		GameManager.add_currency(delta)
	elif delta < 0:
		GameManager.spend_currency(-delta)


func _wait_idle(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while bool(dungeon.get("_fate_purchase_busy")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not bool(dungeon.get("_fate_purchase_busy")) and not bool(dungeon.get("_fate_feedback_locked")), "事务未在6000ms内解锁", failures)


func _wait_overlay_closed(dungeon: Dungeon3D) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		if not bool(dungeon.get("_door_fate_active")) and dungeon.get_node_or_null("HUD/DoorFateOverlay3D") == null:
			return
		await get_tree().create_timer(0.05).timeout


func _wait_fate_cards_flipped(overlay: Control) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		var ready := true
		var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
		if cards.size() != 3:
			ready = false
		for node in cards:
			var button := node as Button
			if button.disabled or not bool(button.get_meta("tarot_face_ready", false)) or not button.is_visible_in_tree():
				ready = false
		if ready:
			return
		await get_tree().create_timer(0.05).timeout


func _collect_label_text(root: Node) -> String:
	var result := ""
	for node in root.find_children("*", "Label", true, false):
		result += "\n" + (node as Label).text
	return result


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FATE_CARD_PURCHASE_FLOW_OK: 精确报价/守恒、默认否再是、真实pending落巢、已购幂等、作用域、失败退款、满槽拒绝、焦点闭环、退场输入锁、门不弹卡及生产凭据入口；基地抽取点不变")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
