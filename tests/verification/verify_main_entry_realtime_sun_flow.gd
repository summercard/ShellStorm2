extends Node
## 开场鼠标朝向与单一实时太阳专项；不依赖基地设施摆放或作者缩放。

const TimeDomain = preload("res://src/core/WorldTimeDomain.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	await _verify_realtime_sun(failures)
	await _verify_entry_mouse_aim(failures)
	if failures.is_empty():
		print("MAIN_ENTRY_REALTIME_SUN_OK: mouse-driven avatar aim and one realtime sun color/energy/rotation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MAIN_ENTRY_REALTIME_SUN_FAIL: %s" % failure)
	get_tree().quit(1)


func _verify_realtime_sun(failures: Array[String]) -> void:
	var environment := Environment.new()
	var sun := DirectionalLight3D.new()
	sun.name = "RealtimeSunProbe"
	add_child(sun)
	var atmosphere := TowerAtmosphere3D.new()
	atmosphere.name = "RealtimeAtmosphereProbe"
	atmosphere.configure(environment, sun)
	add_child(atmosphere)
	await get_tree().process_frame

	var noon := TimeDomain.get_snapshot(_elapsed_from_start_hour(12.0))
	var dusk_17 := TimeDomain.get_snapshot(_elapsed_from_start_hour(17.0))
	var dusk_18 := TimeDomain.get_snapshot(_elapsed_from_start_hour(18.0))
	var night := TimeDomain.get_snapshot(_elapsed_from_start_hour(20.0))
	atmosphere.call("_on_world_time_advanced", 0.0, noon)
	var noon_rotation := sun.rotation_degrees
	var noon_color := sun.light_color
	_expect(is_equal_approx(sun.light_energy, 1.0), "12:00太阳峰值不是1", failures)
	atmosphere.call("_on_world_time_advanced", 0.0, dusk_17)
	var dusk_17_rotation := sun.rotation_degrees
	var dusk_17_color := sun.light_color
	_expect(sun.light_energy >= 0.60, "17:00太阳能量过低", failures)
	_expect(not dusk_17_rotation.is_equal_approx(noon_rotation), "12:00到17:00太阳角度没有变化", failures)
	_expect(not dusk_17_color.is_equal_approx(noon_color), "12:00到17:00太阳颜色没有变化", failures)
	atmosphere.call("_on_world_time_advanced", 0.0, dusk_18)
	_expect(sun.light_energy > 0.40, "18:00太阳被提前关闭", failures)
	_expect(not sun.rotation_degrees.is_equal_approx(dusk_17_rotation), "17:00到18:00太阳角度没有连续变化", failures)
	_expect(not sun.light_color.is_equal_approx(dusk_17_color), "17:00到18:00太阳颜色没有连续变化", failures)
	atmosphere.call("_on_world_time_advanced", 0.0, night)
	_expect(is_zero_approx(sun.light_energy), "20:00后太阳仍有直射能量", failures)
	atmosphere.queue_free()
	sun.queue_free()
	await get_tree().process_frame


func _verify_entry_mouse_aim(failures: Array[String]) -> void:
	var player_scene := load("res://scenes/Player3D.tscn") as PackedScene
	var player := player_scene.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	var entry_scene := load("res://scenes/ui/MainEntryScreen3D.tscn") as PackedScene
	var entry := entry_scene.instantiate() as MainEntryScreen3D
	entry.auto_present_when_player_found = false
	add_child(entry)
	await get_tree().process_frame
	_expect(entry.present(player), "开场页不能绑定真实玩家与相机", failures)
	var requested_yaw := player.aim_yaw + 0.73
	player.aim_yaw = requested_yaw
	entry.call("_process", 0.0)
	var snapshot := entry.get_entry_snapshot()
	_expect(bool(snapshot.get("avatar_follows_mouse", false)), "开场页没有声明鼠标朝向合同", failures)
	_expect(is_equal_approx(player.aim_yaw, requested_yaw), "开场页仍覆盖鼠标产生的aim_yaw", failures)
	_expect(player.input_locked, "开场页没有继续锁定移动与战斗输入", failures)
	entry.skip_to_gameplay()
	entry.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _elapsed_from_start_hour(hour: float) -> float:
	return fposmod(hour - 17.0, 24.0) * 3600.0


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
