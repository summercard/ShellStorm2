extends Node
## 开场弹药口径验收（2026-11-09 语义已反转，文件名保留）。
##
## **旧行为**：入场白送 300 发 `item_ammo_pack`，本用例证明「真的发了、HUD 带出来、换弹按缺口扣」。
## **现行行为**（业主同日两项要求）：
##   1. 开场**不发**任何保底备弹 —— 入场背包只有基地带上来的东西；
##   2. 豌豆手枪**备弹无限**（业主最终原话：「弹夹保持 10 发，打完后备弹无限」）——
##      弹匣 10 发照常打空、照常换弹 1.4 s，但换弹**不扣备弹** ⇒ 每轮都白拿满匣。
##
## 本场景用「隔离存档 + test_mode=false」跑真实入场路径，证明四件事：
##   A 入场备弹为 0（主背包与换弹口径两个通道都为 0），且显式调用发放函数也不会加东西；
##   B 出厂手枪 `infinite_reserve_ammo == true`，弹匣 **10** 发；
##   C 弹匣**照常消耗**：开火扣 1、空匣开火被拒并自动起换弹（不是「开火不扣弹」）；
##   D 无备弹时换弹成功且**不消耗备弹**，可无限重复（每轮都白拿满匣）；HUD 当前弹数真实、备弹段 `∞`。
## 存档恢复整格覆盖那条旧断言保留：它验的是「入场发放不会叠加到存档备弹上」，
## 现在入场发放恒为 0，更需要它挡的是「别有人偷偷加回来」。
## _probe_completed 是防假绿哨兵：中途脚本错误会静默中断本函数并留下空失败表。

const TEST_PATH := "user://guaranteed_loadout_ammo_probe.json"

var _probe_completed := false


func _ready() -> void:
	var failures: Array[String] = []
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	_cleanup()
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true

	await _verify_real_spawn_grant(failures)

	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()
	call_deferred("_report_and_quit", failures.duplicate())


func _verify_real_spawn_grant(failures: Array[String]) -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	tower.run_seed_override = 991217
	add_child(tower)
	for _frame in 3:
		await get_tree().process_frame

	# ---------- A 组：开场不发备弹 ----------
	var expected_rounds := tower.get_guaranteed_loadout_ammo_rounds()
	if expected_rounds != 0:
		failures.append("保底备弹设计值应为 0（2026-11-09 已取消），实际 %d" % expected_rounds)

	var weapon := tower.player.weapon
	if weapon == null:
		failures.append("入场没有装配 WeaponModel3D，无限弹匣无从验证")
		tower.queue_free()
		_probe_completed = true
		return
	# 前提：出厂手枪必须在手，否则验的不是这把枪的口径。
	if tower.player.get_equipped_weapon_item_for_slot(0).is_empty():
		failures.append("入场没有拿到出厂手枪，无限弹匣无从验证")

	var backpack := tower.get_inventory_module()
	if backpack == null:
		failures.append("入场没有创建主背包模块")
		tower.queue_free()
		_probe_completed = true
		return

	var staged := backpack.get_item_count("item_ammo_pack")
	if staged != 0:
		failures.append("真实入场主背包备弹 %d 发，期望 0 发（保底备弹已取消）" % staged)
	var reserve := int(tower.call("_get_reserve_ammo_count"))
	if reserve != 0:
		failures.append("换弹备弹口径 %d，期望 0" % reserve)

	# 显式调发放函数也不许加东西 —— 挡「有人把功能加回来但没改门禁」。
	var granted := int(tower.call("_grant_guaranteed_loadout_ammo"))
	if granted != 0:
		failures.append("显式调用保底备弹发放返回 %d 发，应为 0" % granted)
	if int(tower.call("_get_reserve_ammo_count")) != 0:
		failures.append("显式调用后背包里出现了备弹")

	# ---------- B 组：出厂手枪声明了「备弹无限」----------
	if not bool(weapon.get("infinite_reserve_ammo")):
		failures.append(
			"出场手枪的 WeaponModel3D.infinite_reserve_ammo 不是 true（内容侧声明没走到运行时）"
		)
	if weapon.magazine_size != 10:
		failures.append("手枪弹匣容量应为 10，实际 %d" % weapon.magazine_size)

	# ---------- C 组：弹匣照常消耗（不是「开火不扣弹」）----------
	weapon.call("cancel_reload")
	weapon.set("_reload_remaining", 0.0)
	weapon.set("_cooldown", 0.0)
	weapon.current_ammo = 3
	var before_fire := weapon.current_ammo
	weapon.try_fire(Vector3.FORWARD, tower.player)
	if weapon.current_ammo != before_fire - 1:
		failures.append(
			"开火后弹数 %d，期望 %d —— 弹匣必须照常消耗（业主口径是「备弹无限」不是「弹匣无限」）"
			% [weapon.current_ammo, before_fire - 1]
		)

	# 打空后不能开火，且会自动起换弹。
	weapon.current_ammo = 0
	weapon.set("_cooldown", 0.0)
	weapon.call("cancel_reload")
	weapon.set("_reload_remaining", 0.0)
	var empty_fired: bool = weapon.try_fire(Vector3.FORWARD, tower.player)
	if empty_fired:
		failures.append("空匣仍然开火了 —— 弹匣必须真的会空")
	if not weapon.is_reloading():
		failures.append("空匣开火没有自动起换弹（玩家会卡在 0 发）")

	# ---------- D 组：无备弹也能换弹，且换弹不消耗备弹 → 每次白拿满匣 ----------
	weapon.call("cancel_reload")
	weapon.set("_reload_remaining", 0.0)
	weapon.set("_cooldown", 0.0)
	weapon.current_ammo = 1
	if not weapon.request_reload():
		failures.append("无备弹时换弹被拒绝，无限备弹没有豁免备弹检查")
	else:
		weapon.call("_process", weapon.reload_time + 0.01)
		if weapon.current_ammo != weapon.magazine_size:
			failures.append(
				"无限备弹换弹后没有补满：%d/%d" % [weapon.current_ammo, weapon.magazine_size]
			)
		if backpack.get_item_count("item_ammo_pack") != 0:
			failures.append(
				"无限备弹换弹凭空生成了备弹：%d" % backpack.get_item_count("item_ammo_pack")
			)
	# 连打两轮空匣：证明「备弹」是耗不完的，而不是只白送一次。
	for round_index in range(2):
		weapon.current_ammo = 0
		weapon.call("cancel_reload")
		weapon.set("_reload_remaining", 0.0)
		if not weapon.request_reload():
			failures.append("第 %d 轮空匣换弹被拒绝" % (round_index + 1))
			break
		weapon.call("_process", weapon.reload_time + 0.01)
		if weapon.current_ammo != weapon.magazine_size:
			failures.append(
				"第 %d 轮换弹没补满：%d/%d"
				% [round_index + 1, weapon.current_ammo, weapon.magazine_size]
			)

	# HUD：当前弹数照常显示真实值，**备弹段**显示 `∞`。
	weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	await get_tree().process_frame
	if tower.ammo_label == null:
		failures.append("没有找到弹药 HUD 标签，无法校验无限备弹显示")
	else:
		var hud_text := tower.ammo_label.text
		if not hud_text.begins_with("%d" % weapon.current_ammo):
			failures.append("HUD 当前弹数不是真实值：%s" % hud_text)
		if not hud_text.contains("∞备弹"):
			failures.append("HUD 备弹段没有显示 ∞：%s" % hud_text)

	# 存档恢复走 restore_slots_snapshot：整格覆盖，入场发放（现为 0）不得叠加到存档备弹上。
	var saved_rounds := 3
	backpack.restore_slots_snapshot([{
		"item": ItemRegistry.get_instance().get_item("item_ammo_pack"),
		"count": saved_rounds,
	}])
	var after_restore := int(tower.call("_get_reserve_ammo_count"))
	if after_restore != saved_rounds:
		failures.append(
			"存档快照恢复后备弹为 %d，期望 %d；入场发放叠加到了存档备弹上"
			% [after_restore, saved_rounds]
		)

	tower.queue_free()
	await get_tree().process_frame
	_probe_completed = true


func _report_and_quit(failures: Array[String]) -> void:
	var output := failures.duplicate()
	if not _probe_completed:
		output.append("验收流程中途中断（脚本错误或提前返回），结果不可信")
	if output.is_empty():
		print("GUARANTEED_LOADOUT_AMMO_OK: 开场不再发放保底备弹；出厂手枪 10 发弹匣照常打空、无备弹可无限换弹（换弹不扣备弹）、HUD 备弹显示 ∞；存档恢复整格覆盖不叠加")
		get_tree().quit(0)
		return
	for failure in output:
		push_error(failure)
	get_tree().quit(1)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
