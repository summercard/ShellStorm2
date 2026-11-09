extends Node3D

const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const ACTIVATION_DURATION := 6.4
const RELEASE_WINDOW := 5.4

var failures: Array[String] = []
var checks := 0

class DummyPlayer extends Node3D:
	var current_hp := 100000
	var hits: Array[int] = []

	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO) -> void:
		hits.append(amount)
		current_hp -= amount


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _ready() -> void:
	var player := DummyPlayer.new()
	player.add_to_group("player_3d")
	add_child(player)
	var injector := MonsterInjector.new()
	var config: Dictionary = injector._generate_boss(1, 0, {"boss_content_id": "boss_monitor002", "floor_number": 0})
	var monitor := ENEMY.instantiate() as Enemy3D
	add_child(monitor)
	monitor.configure_from_enemy_data(config)
	monitor.set_physics_process(false)
	monitor.set_process(false)
	monitor._target = player
	await get_tree().physics_frame
	player.global_position = monitor.global_position + Vector3(0.5, 0.0, 0.0)
	monitor.set_runtime_active(true)
	monitor.set_physics_process(false)
	monitor.set_process(false)

	# 剧情 hold：近身也不得自动激活、位移、攻击或受伤。
	monitor.set_story_activation_hold(true)
	var held_position := monitor.global_position
	var held_hp := monitor.current_hp
	monitor._physics_process(1.0)
	monitor.take_damage(999999)
	monitor.take_projectile_damage(999999)
	var held := monitor.get_story_activation_snapshot()
	expect(bool(held["held"]) and not bool(held["started"]) and not bool(held["completed"]), "hold 近身不激活")
	expect(float(held["elapsed"]) == 0.0 and monitor.global_position == held_position, "hold 不推进激活、不位移")
	expect(monitor.current_hp == held_hp and monitor.ai_state not in ["telegraph", "attack"], "hold 期间正式伤害入口均被保护")

	# 显式 request：不依赖 10m 距离，窗口与总时长走同一条生产激活时序。
	player.global_position = Vector3(100.0, 0.0, 0.0)
	var started_events := 0
	var release_events := 0
	var completed_events := 0
	monitor.boss_activation_started.connect(func(_enemy: Enemy3D) -> void: started_events += 1)
	monitor.boss_activation_release_window.connect(func(_enemy: Enemy3D) -> void: release_events += 1)
	monitor.boss_activation_completed.connect(func(_enemy: Enemy3D) -> void: completed_events += 1)
	expect(monitor.request_story_activation(), "monitor request 成功")
	var requested := monitor.get_story_activation_snapshot()
	expect(not bool(requested["held"]) and bool(requested["started"]) and float(requested["elapsed"]) == 0.0, "request 解除 hold 并从零开始")
	expect(started_events == 1, "激活开始信号只发一次")
	monitor._physics_process(5.39)
	expect(release_events == 0 and not bool(monitor.get_story_activation_snapshot()["completed"]), "5.4 秒前无释放窗口且未完成")
	var activation_hp := monitor.current_hp
	monitor.take_damage(999999)
	expect(monitor.current_hp == activation_hp, "剧情激活未完成前仍不可受伤")
	monitor._physics_process(0.02)
	var release_elapsed := float(monitor.get_story_activation_snapshot()["elapsed"])
	expect(release_events == 1 and release_elapsed >= RELEASE_WINDOW and release_elapsed < RELEASE_WINDOW + 0.02, "elapsed 穿越 5.4 秒发一次释放窗口")
	var retry_before := monitor.get_story_activation_snapshot()
	expect(monitor.request_story_activation(), "已 started 的重复 request 幂等成功")
	var retry_after := monitor.get_story_activation_snapshot()
	expect(float(retry_after["elapsed"]) == float(retry_before["elapsed"]) and started_events == 1, "重复 request 不重置且不重复开始")
	monitor._physics_process(1.0)
	expect(bool(monitor.get_story_activation_snapshot()["completed"]) and completed_events == 1, "6.4 秒完成且 completed 只发一次")
	expect(monitor.request_story_activation() and completed_events == 1, "completed request 幂等成功")

	# 完成后才允许伤害；不擅自重置已完成的 Boss。
	var completed_hp := monitor.current_hp
	monitor.take_damage(1)
	expect(monitor.current_hp == completed_hp - 1, "激活完成后恢复正常受伤")
	var saved := monitor.export_runtime_state()
	saved.erase("monitor_story_activation_hold")
	saved.erase("monitor_story_activation_requested")
	expect(monitor.import_runtime_state(saved), "旧存档可恢复")
	expect(bool(monitor.get_story_activation_snapshot()["completed"]), "旧字段缺省不重置已完成 Boss")

	# 默认未配置剧情 hold 的显示器仍保留 10m 自动激活。
	var automatic := ENEMY.instantiate() as Enemy3D
	add_child(automatic)
	automatic.configure_from_enemy_data(config)
	automatic.set_physics_process(false)
	automatic.set_process(false)
	var automatic_player := DummyPlayer.new()
	automatic_player.add_to_group("player_3d")
	add_child(automatic_player)
	automatic_player.global_position = automatic.global_position + Vector3(10.0, 0.0, 0.0)
	automatic.set_runtime_active(true)
	automatic.set_physics_process(false)
	automatic.set_process(false)
	automatic._physics_process(0.1)
	expect(bool(automatic.get_story_activation_snapshot()["started"]), "默认显示器仍按 10m 自动激活")

	# 非显示器 Boss 没有剧情接口能力；死亡和卸载不得留下迟发推进。
	var other_config: Dictionary = injector._generate_boss(1, 0, {"boss_content_id": "boss_hollow_choir_85", "floor_number": 0})
	var other := ENEMY.instantiate() as Enemy3D
	add_child(other)
	other.configure_from_enemy_data(other_config)
	expect(not other.request_story_activation(), "其他 Boss 返回 false")
	var cancel_probe := ENEMY.instantiate() as Enemy3D
	add_child(cancel_probe)
	cancel_probe.configure_from_enemy_data(config)
	cancel_probe.set_physics_process(false)
	cancel_probe.set_process(false)
	cancel_probe.set_story_activation_hold(true)
	cancel_probe.request_story_activation()
	cancel_probe._physics_process(0.2)
	cancel_probe._die()
	var dead_snapshot := cancel_probe.get_story_activation_snapshot()
	cancel_probe._physics_process(10.0)
	expect(not bool(dead_snapshot["started"]) and float(cancel_probe.get_story_activation_snapshot()["elapsed"]) == 0.0, "死亡取消剧情激活且无迟发")
	cancel_probe.queue_free()
	monitor.queue_free()
	await get_tree().process_frame
	expect(not is_instance_valid(monitor) and not is_instance_valid(cancel_probe), "场景卸载完成")
	finish()


func finish() -> void:
	var report := {"checks": checks, "failures": failures, "exit_code": 0 if failures.is_empty() else 1, "not_executed": ["Godot execution deferred to主agent隔离运行"]}
	var file := FileAccess.open("res://tests/verification/verify_main_story_boss_gate.report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAIN_STORY_BOSS_GATE_OK checks=", checks)
	get_tree().quit(0 if failures.is_empty() else 1)
