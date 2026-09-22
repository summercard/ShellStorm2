extends Node
## 保底武装配套弹药验收。
## 白送手枪来自 `Player3D.start_with_weapon`，只给枪不给弹；配套备弹由
## `Dungeon3D._setup_run_modules()` 在入场时补一份 `item_ammo_pack`。
## 本场景用「隔离存档 + test_mode=false」跑真实发放路径，证明四件事：
##   1. 真实入场确实拿到 GUARANTEED_LOADOUT_AMMO_ROUNDS 发通用备弹；
##   2. 备弹数在 HUD 真串里出现（运行时拼串，必须驱动真事件再读）；
##   3. 这份备弹能被换弹按缺口真实消耗，不是只写了个数字；
##   4. 存档快照恢复整格覆盖背包，入场发放不会叠加到存档备弹上。
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

	var expected_rounds := tower.get_guaranteed_loadout_ammo_rounds()
	if expected_rounds != 300:
		failures.append("保底备弹发数变成 %d，与设计输入 300 不一致" % expected_rounds)

	var weapon := tower.player.weapon
	if weapon == null:
		failures.append("入场没有装配 WeaponModel3D，保底武装不成立")
		tower.queue_free()
		_probe_completed = true
		return
	# 前提：保底武装本身必须在手，否则「配套」没有对象可配。
	if tower.player.get_equipped_weapon_item_for_slot(0).is_empty():
		failures.append("入场没有拿到保底武装，无法判定配套备弹")

	var backpack := tower.get_inventory_module()
	if backpack == null:
		failures.append("入场没有创建主背包模块")
		tower.queue_free()
		_probe_completed = true
		return

	var staged := backpack.get_item_count("item_ammo_pack")
	if staged != expected_rounds:
		failures.append("真实入场主背包备弹 %d 发，期望 %d 发" % [staged, expected_rounds])
	var reserve := int(tower.call("_get_reserve_ammo_count"))
	if reserve != expected_rounds:
		failures.append("换弹备弹口径 %d 与保底发数 %d 不一致" % [reserve, expected_rounds])

	# HUD 备弹是运行时拼串，必须驱动真实弹量事件再读真串。
	weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	await get_tree().process_frame
	if tower.ammo_label == null:
		failures.append("没有找到弹药 HUD 标签，无法校验运行时备弹串")
	elif not tower.ammo_label.text.contains("%d备弹" % expected_rounds):
		failures.append("HUD 弹药串没有带出保底备弹：%s" % tower.ammo_label.text)

	# 备弹必须真能装进弹匣：留 10 发缺口，只应消耗 10 发。
	var gap := 10
	weapon.current_ammo = maxi(0, weapon.magazine_size - gap)
	weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	if not tower.player.request_reload():
		failures.append("有保底备弹时换弹被拒绝")
	else:
		weapon.call("_process", weapon.reload_time + 0.01)
		if weapon.current_ammo != weapon.magazine_size:
			failures.append(
				"保底备弹没有按缺口装填：%d/%d" % [weapon.current_ammo, weapon.magazine_size]
			)
		var after_reload := backpack.get_item_count("item_ammo_pack")
		if after_reload != expected_rounds - gap:
			failures.append(
				"换弹没有按缺口精确扣除保底备弹：剩余 %d，期望 %d"
				% [after_reload, expected_rounds - gap]
			)

	# 存档恢复走 restore_slots_snapshot：整格覆盖，不得把入场发放叠加到存档备弹上。
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
		print("GUARANTEED_LOADOUT_AMMO_OK: 真实入场发放保底备弹、HUD 真串带出备弹数、换弹按缺口精确扣除，且存档恢复整格覆盖不会叠加")
		get_tree().quit(0)
		return
	for failure in output:
		push_error(failure)
	get_tree().quit(1)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
