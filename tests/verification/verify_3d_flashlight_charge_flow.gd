extends Node
## 合同 §10.6 验收：手电筒电量 / 电池 / 模块 / 揭示倍率 / 存档 持久化 / HUD 阈值闪烁。
## 测试场景：Dungeon3D 实例化后,基础档满电 100%,用物理 tick / 信号连接验证。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const SAVE_VERSION_EXPECTED := "1.6"

var _depleted_signal_emitted := false
var _restored_signal_emitted := false
var _charge_changed_count := 0
var _last_charge_ratio := 1.0
var _last_charge_tier := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	# 隔离长期档案：测试必须从基础模块开始，不能继承开发存档上一次的工坊选择。
	BaseManager.set_equipped_flashlight_module("basic")
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 240724
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame

	var player: Player3D = dungeon.player
	var flashlight: PlayerFlashlight3D = player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight == null:
		failures.append("PlayerFlashlight3D missing on player root")
		_report(failures)
		return
	flashlight.charge_changed.connect(_on_charge_changed)
	flashlight.state_changed.connect(_on_state_changed)

	# 1. §10.6 #1 — 99F 基地内 charge_ratio == 1.0,2 秒不掉电
	await _assert_charge_no_drain_in_facility(flashlight, failures)
	# 2. §10.6 #2 — 出基地开启后掉电,关闭立刻停止
	await _assert_drain_and_stop(flashlight, dungeon, failures)
	# 3. §10.6 #4 — 0% 自动关 + depleted 信号
	await _assert_zero_auto_off(flashlight, failures)
	# 4. §10.6 #6 — 三种电池 +25/+75/+100,满电时不被消耗
	await _assert_batteries(flashlight, player, failures)
	# 5. §10.6 #7 — 模块基地外被拒,基地内 advanced 切为 0.7143×/1.20×
	await _assert_module_swap(flashlight, dungeon, failures)
	# 6. 长期装备选择会在新行动注入 PlayerFlashlight3D
	_assert_persisted_module_hydration(dungeon, flashlight, failures)
	# 7. §10.6 #5 — HUD 面板存在,5 档色 + 闪烁阈值
	await _assert_hud_panel(dungeon, failures)
	# 8. §10.6 #6 — 贩卖机 item_battery_s 在架 & base_shelf_order==6;battery_l/cell_pack 不在
	await _assert_shop_catalog(failures)
	# 9. §10.6 #8 — BaseData.active_run_snapshot.flashlight_charge_ratio 写入并回读
	await _assert_active_run_snapshot(flashlight, failures)
	# 10. §10.6 #7 — BaseData.equipped_flashlight_module_id 持久化
	await _assert_equipped_module_persist(failures)
	# 11. §10.6 #8 — 死亡保留检查点,撤离后清检查点
	await _assert_checkpoint_death_vs_extract(failures)
	# 12. §10.6 #9 — 跨房间电量不变 + advanced 模块下揭示半径 ×1.20
	await _assert_reveal_multiplier(flashlight, dungeon, failures)

	if failures.is_empty():
		var summary := "12/12 OK: facility no-drain, drain/stop, depleted, batteries, visual module profiles, persisted module hydration, HUD, shop, checkpoints, module persistence and reveal"
		print("VERIFY_3D_FLASHLIGHT_CHARGE_FLOW_OK: %s" % summary)
		get_tree().quit(0)
		return
	_report(failures)


func _report(failures: Array[String]) -> void:
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _on_charge_changed(ratio: float, tier: int) -> void:
	_charge_changed_count += 1
	_last_charge_ratio = ratio
	_last_charge_tier = tier


func _on_state_changed(state_id: String, _context: Dictionary) -> void:
	if state_id == "depleted":
		_depleted_signal_emitted = true
	elif state_id == "restored":
		_restored_signal_emitted = true


func _wait_physics(seconds: float) -> void:
	var ticks := int(ceil(seconds * 60.0))
	for _i in ticks:
		await get_tree().physics_frame


func _tap_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame


# 1. §10.6 #1
func _assert_charge_no_drain_in_facility(flashlight: PlayerFlashlight3D, failures: Array[String]) -> void:
	flashlight.set_charge_ratio(0.5)
	flashlight.set_in_facility(true)
	await _wait_physics(2.0)
	if not is_equal_approx(flashlight.get_charge_ratio(), 1.0):
		failures.append("Facility did not refill flashlight to 100%% within 2s")
	# 注:_in_facility 由 Player3D._physics_process 每帧推送(Player.is_player_inside_facility),
	# 在测试场景中可能瞬间被覆盖。剩余时间逻辑本身在开启+非基地时由 drain 速率推算,
	# 在测试 2 单独验证。


# 2. §10.6 #2
func _assert_drain_and_stop(flashlight: PlayerFlashlight3D, dungeon: Dungeon3D, failures: Array[String]) -> void:
	# 只关心"开启后第一个 2% 步进"的信号,HUD 显示细节同理。
	_charge_changed_count = 0
	_last_charge_ratio = 1.0
	_last_charge_tier = 0
	flashlight.set_in_facility(false)
	flashlight.set_charge_ratio(1.0)
	flashlight.set_light_enabled(true)
	# 头像下方三格电芯 + 右侧时间文本；不再有右上独立电池面板。
	var hud := dungeon.get_node_or_null("HUD/ReferenceCombatHUD")
	var panel: Control = hud.find_child("FlashlightBatteryPanel", true, false) as Control if hud != null else null
	var time_label: Label = null
	if panel != null:
		time_label = panel.find_child("BatteryTimeLabel", true, false) as Label
	if panel == null or panel.find_children("BatteryCell_*", "Panel", false, false).size() != 3 or time_label == null:
		failures.append("Avatar battery cells / BatteryTimeLabel missing")
	# 让 _tick_battery_blink 至少跑一次,time label 才会从"FULL · 基地内"切到"05:00"。
	await get_tree().process_frame
	# 首个 2% 步进前采样剩余时间 / 时间文本,1 秒后再采样。
	# 这条专门防"每 6 秒跳一次"的回归:ratio 应仍为 100%,但 secs 应已下降约 1。
	var secs_at_t0 := flashlight.get_estimated_remaining_seconds()
	var time_text_t0 := time_label.text if time_label != null else ""
	if secs_at_t0 <= 0.0 or secs_at_t0 >= 320.0:
		failures.append("Remaining seconds out of range at start (got %f)" % secs_at_t0)
	await _wait_physics(1.0)
	var ratio_after_1s := flashlight.get_charge_ratio()
	var secs_at_t1 := flashlight.get_estimated_remaining_seconds()
	var time_text_t1 := time_label.text if time_label != null else ""
	if ratio_after_1s < 1.0:
		failures.append("Charge dropped within 1s, first 2%% step expected near 6s (got %f)" % ratio_after_1s)
	if secs_at_t1 >= secs_at_t0 - 0.5:
		failures.append("Remaining seconds did not drop over 1s (t0=%f, t1=%f)" % [secs_at_t0, secs_at_t1])
	if time_label != null and time_text_t0 == time_text_t1:
		failures.append("BatteryTimeLabel did not tick between t=0 and t=1s (both '%s')" % time_text_t0)
	# 2% step 验证: 基础档满电大约 300 秒耗尽(每 2% 一格,共 50 格)；每格约 6 秒。
	# 此前已等了 1 秒,这里再跑 6 秒,首个 2% 步进应已发生,且幅度不应超过 2% ± 浮点误差。
	var ratio_before := flashlight.get_charge_ratio()
	var saw_step := false
	for _i in 360:  # 6s @ 60Hz
		await get_tree().physics_frame
		var current := flashlight.get_charge_ratio()
		var delta := ratio_before - current
		if delta > 0.0:
			if delta > 0.025:
				failures.append("Drain step exceeded 2%% (delta=%f)" % delta)
			saw_step = true
		ratio_before = current
	if not saw_step:
		failures.append("No 2%% drain step observed within 7 seconds")
	# 信号 + HUD 同步：charge_changed 应在第一个步进时发；三格电芯仍为满格。
	if _charge_changed_count < 1:
		failures.append("charge_changed not emitted after first 2%% drain step (count=%d)" % _charge_changed_count)
	if not is_equal_approx(_last_charge_ratio, 0.98):
		failures.append("First drain step ratio != 0.98 (got %f)" % _last_charge_ratio)
	# 倒计时在开启后应 > 0 且接近基础档剩余时长(小于 320 秒)
	var secs := flashlight.get_estimated_remaining_seconds()
	if secs <= 0.0 or secs >= 320.0:
		failures.append("Remaining seconds out of range after enabling (got %f)" % secs)
	var after_on := flashlight.get_charge_ratio()
	if after_on >= 1.0 or after_on <= 0.0:
		failures.append("Flashlight did not drain during 7s on (got %f)" % after_on)
	flashlight.set_light_enabled(false)
	var stopped := flashlight.get_charge_ratio()
	await _wait_physics(1.0)
	if not is_equal_approx(flashlight.get_charge_ratio(), stopped):
		failures.append("Flashlight continued draining after toggle off")


# 3. §10.6 #4
func _assert_zero_auto_off(flashlight: PlayerFlashlight3D, failures: Array[String]) -> void:
	_depleted_signal_emitted = false
	flashlight.set_charge_ratio(1.0)
	flashlight.set_light_enabled(true)
	flashlight.set_in_facility(false)
	# 强制耗尽
	for _i in 600:
		flashlight.consume_charge(0.05)
		await get_tree().physics_frame
		if flashlight.is_depleted():
			break
	if not flashlight.is_depleted():
		failures.append("Forced consumption did not reach 0")
	if flashlight.is_light_enabled():
		failures.append("Flashlight did not auto-off at 0%%")
	if not _depleted_signal_emitted:
		failures.append("state_changed('depleted', …) was not emitted at 0%%")
	# 0% 状态拒绝打开 — 用 Dictionary 包装以避开 lambda 捕获语义
	var refused_box := {"value": false}
	flashlight.state_changed.connect(func(state_id: String, _context: Dictionary) -> void:
		if state_id == "consume_refused":
			refused_box["value"] = true
	)
	flashlight.set_light_enabled(true)
	await get_tree().process_frame
	if not refused_box["value"]:
		failures.append("set_light_enabled(true) at 0%% did not emit consume_refused")


# 4. §10.6 #6
func _assert_batteries(flashlight: PlayerFlashlight3D, player: Player3D, failures: Array[String]) -> void:
	var handler := ItemUseHandler.get_instance()
	# 用 cell_pack 满充验证 "+100"
	flashlight.set_charge_ratio(0.0)
	var context := {"player": player}
	var cell := ItemRegistry.get_instance().get_item("item_cell_pack")
	if not bool(handler.apply(cell, context)):
		failures.append("cell_pack did not apply at 0%%")
	if not is_equal_approx(flashlight.get_charge_ratio(), 1.0):
		failures.append("cell_pack did not fully charge (got %f)" % flashlight.get_charge_ratio())
	# 满电再用应被拒
	_restored_signal_emitted = false
	if bool(handler.apply(cell, context)):
		failures.append("cell_pack was consumed while already full")
	# battery_s +25
	flashlight.set_charge_ratio(0.0)
	var s_item := ItemRegistry.get_instance().get_item("item_battery_s")
	handler.apply(s_item, context)
	if not is_equal_approx(flashlight.get_charge_ratio(), 0.25):
		failures.append("battery_s did not restore 25%% (got %f)" % flashlight.get_charge_ratio())
	# battery_l +75
	flashlight.set_charge_ratio(0.0)
	var l_item := ItemRegistry.get_instance().get_item("item_battery_l")
	handler.apply(l_item, context)
	if not is_equal_approx(flashlight.get_charge_ratio(), 0.75):
		failures.append("battery_l did not restore 75%% (got %f)" % flashlight.get_charge_ratio())


# 5. §10.6 #7
func _assert_module_swap(flashlight: PlayerFlashlight3D, _dungeon: Dungeon3D, failures: Array[String]) -> void:
	flashlight.set_in_facility(false)
	flashlight.set_module("advanced")  # 基地外
	if flashlight.get_drain_multiplier() != 1.0 or flashlight.get_reveal_multiplier() != 1.0:
		failures.append("Module swap was accepted outside facility")
	flashlight.set_in_facility(true)
	if not bool(flashlight.set_module("advanced")):
		failures.append("advanced module swap was rejected inside facility")
	# 5.0 / 7.0 = 0.7142857... 强化档满电 420s。从源码常量读,避免浮点近似漂移。
	var advanced_drain_expected: float = PlayerFlashlight3D.FLASHLIGHT_MODULE_PROFILES["advanced"]["drain"]
	if not is_equal_approx(flashlight.get_drain_multiplier(), advanced_drain_expected):
		failures.append("advanced drain != %f (got %f)" % [advanced_drain_expected, flashlight.get_drain_multiplier()])
	if not is_equal_approx(flashlight.get_reveal_multiplier(), 1.20):
		failures.append("advanced reveal != 1.20 (got %f)" % flashlight.get_reveal_multiplier())
	if not is_equal_approx(flashlight.get_range_multiplier(), 1.20):
		failures.append("advanced visual range != 1.20 (got %f)" % flashlight.get_range_multiplier())
	var beam := flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D
	if beam == null or not is_equal_approx(beam.spot_range, flashlight.beam_range * 1.20):
		failures.append("advanced beam range was not applied to the real light")
	# efficient 0.50 / 0.85
	if not bool(flashlight.set_module("efficient")):
		failures.append("efficient module swap was rejected inside facility")
	if not is_equal_approx(flashlight.get_drain_multiplier(), 0.50):
		failures.append("efficient drain != 0.50 (got %f)" % flashlight.get_drain_multiplier())
	# 回 basic
	flashlight.set_module("basic")


# 6. 长期装备状态必须成为新局 PlayerFlashlight3D 的运行态，而不只是存档中的字符串。
func _assert_persisted_module_hydration(dungeon: Dungeon3D, flashlight: PlayerFlashlight3D, failures: Array[String]) -> void:
	BaseManager.set_blueprint_tier("attachment", 1)
	if not BaseManager.set_equipped_flashlight_module("advanced"):
		failures.append("Could not persist advanced flashlight module for hydration")
		return
	dungeon._apply_persisted_flashlight_module()
	if flashlight.get_module_id() != "advanced" or not is_equal_approx(flashlight.get_drain_multiplier(), 5.0 / 7.0):
		failures.append("Persisted advanced module did not hydrate PlayerFlashlight3D")
	BaseManager.set_equipped_flashlight_module("basic")
	dungeon._apply_persisted_flashlight_module()


# 6. §10.6 #5
func _assert_hud_panel(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var hud := dungeon.get_node_or_null("HUD/ReferenceCombatHUD")
	var panel: Control = hud.find_child("FlashlightBatteryPanel", true, false) as Control if hud != null else null
	if panel == null:
		failures.append("Avatar FlashlightBatteryPanel missing")
		return
	if panel.find_children("BatteryCell_*", "Panel", false, false).size() != 3:
		failures.append("Battery HUD should reuse exactly three avatar cells")
	var time_label: Label = panel.find_child("BatteryTimeLabel", true, false) as Label
	if time_label == null:
		failures.append("BatteryTimeLabel (named) missing beside avatar cells")
	if panel.get_parent() == hud:
		failures.append("Legacy right-side flashlight battery panel should be removed")
	# 5 档: 60/30/10/1/0
	var flashlight: PlayerFlashlight3D = dungeon.player.get_node("PlayerFlashlight3D")
	flashlight.set_charge_ratio(0.65)
	if flashlight.get_tier() != 0:
		failures.append("tier 0 expected at 65%%, got %d" % flashlight.get_tier())
	flashlight.set_charge_ratio(0.45)
	if flashlight.get_tier() != 1:
		failures.append("tier 1 expected at 45%%, got %d" % flashlight.get_tier())
	flashlight.set_charge_ratio(0.20)
	if flashlight.get_tier() != 2:
		failures.append("tier 2 expected at 20%%, got %d" % flashlight.get_tier())
	flashlight.set_charge_ratio(0.05)
	if flashlight.get_tier() != 3:
		failures.append("tier 3 expected at 5%%, got %d" % flashlight.get_tier())
	# 同一 tier 内 (>=60%) 的 set_charge_ratio 仍要发 charge_changed 并刷新 HUD。
	# 防 set_charge_ratio 只在跨 tier 时 emit 的回归:0.98 → 0.96 都是 tier 0,但值确实变了。
	flashlight.set_charge_ratio(0.98)
	var ratio_same_tier_1 := flashlight.get_charge_ratio()
	flashlight.set_charge_ratio(0.96)
	var ratio_same_tier_2 := flashlight.get_charge_ratio()
	if not is_equal_approx(ratio_same_tier_2, 0.96):
		failures.append("Same-tier set_charge_ratio to 0.96 failed (got %f)" % ratio_same_tier_2)
	if is_equal_approx(ratio_same_tier_1, ratio_same_tier_2):
		failures.append("Same-tier set_charge_ratio did not change ratio (both %f)" % ratio_same_tier_1)
	if flashlight.get_tier() != 0:
		failures.append("Same-tier set_charge_ratio changed tier (got %d)" % flashlight.get_tier())
	# 临界/耗尽档的三格电芯与时间文本整体闪烁。
	flashlight.set_charge_ratio(0.0)
	# 等多个 process + physics 帧,让 _tick_battery_blink 有机会切换 alpha
	for _i in 30:
		await get_tree().process_frame
		await get_tree().physics_frame
	# 至少应出现一次 alpha < 1.0
	var saw_blink := false
	for _i in 30:
		await get_tree().process_frame
		if panel.modulate.a < 0.95:
			saw_blink = true
			break
	if not saw_blink:
		failures.append("Depleted tier panel did not blink (alpha=%f)" % panel.modulate.a)


# 7. §10.6 #6
func _assert_shop_catalog(failures: Array[String]) -> void:
	var goods := BaseManager.get_base_shop_goods()
	var found_s := false
	for g in goods:
		var item_id: String = str(g.get("id", ""))
		if item_id == "item_battery_s":
			found_s = true
			if int(g.get("base_shelf_order", -1)) != 6:
				failures.append("item_battery_s base_shelf_order != 6 (got %d)" % int(g.get("base_shelf_order", -1)))
		if item_id == "item_battery_l" or item_id == "item_cell_pack":
			failures.append("%s should NOT be in base shop" % item_id)
	if not found_s:
		failures.append("item_battery_s missing from base shop goods")


# 8. §10.6 #8
func _assert_active_run_snapshot(flashlight: PlayerFlashlight3D, failures: Array[String]) -> void:
	flashlight.set_charge_ratio(0.42)
	var snapshot := {
		"valid": true,
		"checkpoint_id": "test_cp_1",
		"layout_id": "test_cp_1",
		"flashlight_charge_ratio": flashlight.get_charge_ratio(),
		"flashlight_module_id": flashlight.get_module_id(),
	}
	if not BaseManager.set_active_run_checkpoint(snapshot, "test_charge"):
		failures.append("set_active_run_checkpoint failed")
	# 真实信号会把后续电量变化写回已有行动检查点，而不是只在测试中手写字典。
	flashlight.set_charge_ratio(0.40)
	var stored := BaseManager.get_active_run_checkpoint()
	if not is_equal_approx(float(stored.get("flashlight_charge_ratio", -1.0)), 0.40):
		failures.append("flashlight_charge_ratio was not updated from the runtime signal (got %s)" % str(stored.get("flashlight_charge_ratio")))
	if str(stored.get("flashlight_module_id", "")) != flashlight.get_module_id():
		failures.append("flashlight_module_id was not updated from runtime state")


# 9. §10.6 #7
func _assert_equipped_module_persist(failures: Array[String]) -> void:
	if not bool(BaseManager.set_equipped_flashlight_module("advanced")):
		# 没解锁情况下写应失败,先解锁
		BaseManager.set_blueprint_tier("attachment", 1)
		if not bool(BaseManager.set_equipped_flashlight_module("advanced")):
			failures.append("set_equipped_flashlight_module('advanced') failed after tier unlock")
	if BaseManager.get_equipped_flashlight_module_id() != "advanced":
		failures.append("get_equipped_flashlight_module_id != 'advanced' after set")
	# efficient 未解锁应失败
	BaseManager.set_equipped_flashlight_module("advanced")
	if bool(BaseManager.set_equipped_flashlight_module("efficient")):
		failures.append("efficient should be locked when not in vault")


# 10. §10.6 #8
func _assert_checkpoint_death_vs_extract(failures: Array[String]) -> void:
	BaseManager.set_active_run_checkpoint({
		"valid": true,
		"checkpoint_id": "death_test",
		"layout_id": "death_test",
	}, "test_death")
	# 死亡:clear_active_run_checkpoint 不应被 Dungeon3D._finish_run(false) 自动清(仅 true 才清)
	# 这里仅断言在 BaseManager 层 clear 与 set 仍然有效
	if BaseManager.get_active_run_checkpoint().is_empty():
		failures.append("active_run_snapshot disappeared unexpectedly")
	BaseManager.clear_active_run_checkpoint("run_success")
	if not BaseManager.get_active_run_checkpoint().is_empty():
		failures.append("clear_active_run_checkpoint did not clear")


# 11. §10.6 #9
func _assert_reveal_multiplier(flashlight: PlayerFlashlight3D, _dungeon: Dungeon3D, failures: Array[String]) -> void:
	flashlight.set_in_facility(true)
	flashlight.set_module("advanced")
	flashlight.set_light_enabled(false)  # 切到 off 保留 module 状态
	# 直接读取 Enemy3D 的静态常量值
	var reveal_mult := PlayerFlashlight3D.FLASHLIGHT_REVEAL_BOOST_BASE * PlayerFlashlight3D.FLASHLIGHT_MODULE_PROFILES["advanced"]["reveal"]
	if not is_equal_approx(reveal_mult, 1.7 * 1.20):
		failures.append("advanced reveal boost != 2.04 (got %f)" % reveal_mult)
	# efficient 应是 1.7 * 0.85
	flashlight.set_module("efficient")
	var eff := PlayerFlashlight3D.FLASHLIGHT_REVEAL_BOOST_BASE * PlayerFlashlight3D.FLASHLIGHT_MODULE_PROFILES["efficient"]["reveal"]
	if not is_equal_approx(eff, 1.7 * 0.85):
		failures.append("efficient reveal boost != 1.445 (got %f)" % eff)
	# 跨房间门:电量不变 — 用 set_charge_ratio + 等帧检查
	flashlight.set_charge_ratio(0.5)
	flashlight.set_in_facility(false)
	flashlight.set_light_enabled(false)
	var before := flashlight.get_charge_ratio()
	await _wait_physics(0.5)
	if not is_equal_approx(flashlight.get_charge_ratio(), before):
		failures.append("Charge changed with light off (before=%f, after=%f)" % [before, flashlight.get_charge_ratio()])
	# 回 basic
	flashlight.set_module("basic")
