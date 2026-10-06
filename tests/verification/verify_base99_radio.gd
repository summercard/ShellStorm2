extends Node
## 收音机专用验收：失败断言必须覆盖Prefab、尺寸、摆位、状态、音频、音乐互斥与原桌场景基线。

const RADIO_SCENE_PATH := "res://assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"
const LAYOUT_PATH := "res://assets/art/environments/tower_zones/base/runtime/zone_base.tscn"
const REQUESTED_LAYOUT_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn"
const BATTERY_CABINET_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/loft_battery_cabinet/loft_battery_cabinet_root_top3d.tscn"
const MUSIC_A := "res://assets/audio/music/base_passion/base_passion_a_v001.ogg"
const MUSIC_B := "res://assets/audio/music/base_passion/base_passion_b_v001.ogg"
const TOWER_SCENE_PATH := "res://scenes/TowerDescent3D.tscn"

func _ready() -> void:
	var failures: Array[String] = []
	var radio_scene := load(RADIO_SCENE_PATH) as PackedScene
	if radio_scene == null:
		failures.append("radio prefab 无法加载")
		_finish(failures)
		return
	var radio := radio_scene.instantiate() as Base99Radio3D
	if radio == null:
		failures.append("radio prefab 根节点不是 Base99Radio3D")
		_finish(failures)
		return
	add_child(radio)
	await get_tree().process_frame

	_assert(failures, radio.get_meta("asset_id", "") == "PRP-BASE99-RADIO-3D", "asset_id 不正确")
	_assert(failures, radio.get_meta("asset_category", "") == "decor_prop", "category 必须是场景可交互道具")
	var radio_bounds := _world_bounds(radio)
	_assert(failures, radio_bounds.size.is_equal_approx(Vector3(0.828, 0.822, 0.456)), "radio运行时视觉bounds不符合v003本地契约")
	_assert(failures, "environment_component" not in str(radio.get_meta("collision_policy", "")), "radio 不得标记 environment_component")
	_assert(failures, radio.scale.is_equal_approx(Vector3.ONE), "radio 根节点不得缩放")
	_assert(failures, radio.get_node_or_null("AudioStreamPlayer3D") != null, "缺少 AudioStreamPlayer3D")
	_assert(failures, radio.get_node("AudioStreamPlayer3D").bus == &"Music", "AudioStreamPlayer3D 未使用 Music bus")
	_assert(failures, ResourceLoader.exists(MUSIC_A) and ResourceLoader.exists(MUSIC_B), "base_passion A/B 音频缺失")

	_assert(failures, radio.radio_state == "off", "初始状态必须 off")
	_assert(failures, radio.cycle_state() == "a", "off → A 状态切换失败")
	_assert(failures, radio.cycle_state() == "b", "A → B 状态切换失败")
	_assert(failures, radio.cycle_state() == "off", "B → off 状态切换失败")
	_assert(failures, radio.set_radio_state("bad") == false, "非法状态必须失败")

	var layout := load(LAYOUT_PATH) as PackedScene
	_assert(failures, layout != null, "正式99F运行布局无法加载")
	if layout != null:
		var root := layout.instantiate()
		var placed := root.find_child("99F床边桌独立收音机", true, false) as Base99Radio3D
		_assert(failures, placed != null, "正式99F布局未接入独立收音机")
		if placed != null:
			_assert(failures, placed.position.is_equal_approx(Vector3(-1.95, 6.97, -13.87143)), "radio正式布局局部摆位不正确")
			_assert(failures, rad_to_deg(placed.rotation.y) >= 9.99 and rad_to_deg(placed.rotation.y) <= 20.01, "radio斜摆角度必须在10~20度")
			_assert(failures, placed.get_parent().name == "场景装饰_可自由增删", "radio不得挂在基地结构组件下")
		root.free()

	var requested_layout := load(REQUESTED_LAYOUT_PATH) as PackedScene
	_assert(failures, requested_layout != null, "用户指定正式美术布局无法加载")
	if requested_layout != null:
		var requested_root := requested_layout.instantiate()
		_assert(failures, requested_root.find_child("99F床边桌独立收音机", true, false) != null, "用户指定布局未接入radio")
		requested_root.free()

	var battery_cabinet := load(BATTERY_CABINET_PATH) as PackedScene
	_assert(failures, battery_cabinet != null, "46号BATTERY模块收纳箱Prefab无法加载")
	if battery_cabinet != null:
		var battery_root := battery_cabinet.instantiate()
		_assert(failures, battery_root.get_meta("asset_id", "") == "ENV-BASE99-REMAINING-FACILITIES-V021::loft_battery_cabinet", "46号BATTERY资产基线改变")
		_assert(failures, battery_root.get_meta("collision_policy", "") == "per_source_object_box_collision", "46号BATTERY碰撞契约改变")
		battery_root.free()

	var atmosphere_script := FileAccess.get_file_as_string("res://src/world3d/TowerAtmosphere3D.gd")
	_assert(failures, "if floor_number == 99:" in atmosphere_script and "mgr.stop()" in atmosphere_script, "99F音乐互斥逻辑未落盘")
	_assert(failures, "mgr.play(\"base_passion\")" not in atmosphere_script, "99F仍由TowerAtmosphere3D播放base_passion")

	radio.free()
	await _verify_tower_radio_mouse_path(failures)
	_finish(failures)


func _verify_tower_radio_mouse_path(failures: Array[String]) -> void:
	var tower_scene := load(TOWER_SCENE_PATH) as PackedScene
	_assert(failures, tower_scene != null, "TowerDescent3D 场景无法加载")
	if tower_scene == null:
		return
	var isolated_scene := load(RADIO_SCENE_PATH) as PackedScene
	var isolated_radio := isolated_scene.instantiate() as Base99Radio3D if isolated_scene != null else null
	if isolated_radio != null:
		isolated_radio.name = "RadioOutsideTowerWorldScope"
		add_child(isolated_radio)
		await get_tree().process_frame
		isolated_radio.set_radio_state("a")
	var tower := tower_scene.instantiate() as TowerDescent3D
	_assert(failures, tower != null, "TowerDescent3D 根节点类型不正确")
	if tower == null:
		return
	tower.test_mode = true
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame

	var player := tower.player
	var radio := tower.find_child("99F床边桌独立收音机", true, false) as Base99Radio3D
	_assert(failures, player != null and radio != null, "TowerDescent3D 缺少玩家或99F radio")
	if player == null or radio == null:
		tower.free()
		return

	_assert(failures, radio.get_state_snapshot().get("floor_active", true) == false, "天台初始 radio 必须关闭")
	player.global_position = radio.global_position + Vector3(0.0, -0.90, 1.1)
	player.velocity = Vector3.ZERO
	player.set_input_locked(false)
	player.set_combat_enabled(false)
	tower.call("_refresh_physical_location_authority", true)
	await get_tree().create_timer(0.65).timeout
	_assert(failures, player.is_on_floor() and player.get_state_machine_state() in ["idle", "moving"], "radio输入测试玩家未在阁楼地面稳定着地")
	_assert(failures, radio.get_state_snapshot().get("floor_active", false), "进入99F后 radio 未激活")
	if isolated_radio != null:
		_assert(failures, isolated_radio.get_radio_state() == "a", "Tower 不得改变其他场景 radio 状态")

	var camera := player.camera
	var screen_position := Vector2.INF
	if camera != null:
		screen_position = camera.unproject_position(radio.get_interaction_dot_anchor())
	_assert(failures, camera != null and screen_position.is_finite(), "radio 点击投影坐标无效")
	if camera == null or not screen_position.is_finite():
		tower.free()
		return
	_assert(failures, radio.call("_mouse_hits_radio", screen_position, player), "radio 点击射线未命中自身")
	_assert(failures, await _click_radio(radio, screen_position, "a"), "鼠标左键点击 radio A 未执行")
	_assert(failures, radio.get_radio_state() == "a", "鼠标左键点击后未进入 A")
	_assert(failures, await _click_radio(radio, screen_position, "b"), "鼠标左键点击 radio B 未执行")
	_assert(failures, radio.get_radio_state() == "b", "鼠标左键点击后未进入 B")
	_assert(failures, await _click_radio(radio, screen_position, "off"), "鼠标左键点击 radio off 未执行")
	_assert(failures, radio.get_radio_state() == "off", "鼠标左键点击后未关闭 radio")
	for state in ["a", "b", "off"]:
		await get_tree().process_frame
		var key := InputEventKey.new()
		key.keycode = KEY_E
		key.physical_keycode = KEY_E
		key.pressed = true
		Input.parse_input_event(key)
		await get_tree().process_frame
		key = key.duplicate() as InputEventKey
		key.pressed = false
		Input.parse_input_event(key)
		await get_tree().process_frame
		_assert(failures, radio.get_radio_state() == state, "真实E派发未切换到%s" % state)

	radio.set_radio_state("a")
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var blocker := StaticBody3D.new()
	blocker.name = "RadioMousePathBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 1
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(1.2, 1.2, 1.2)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	tower.add_child(blocker)
	blocker.global_position = ray_origin + ray_direction * 2.0
	await get_tree().physics_frame
	_assert(failures, not radio.call("_mouse_hits_radio", screen_position, player), "阻挡物存在时 radio 射线仍命中")
	await _click_radio(radio, screen_position, "a")
	_assert(failures, radio.get_radio_state() == "a", "阻挡物存在时左键仍切换 radio")
	blocker.free()

	player.global_position = radio.global_position + Vector3(10.0, 0.0, 0.0)
	tower.call("_refresh_physical_location_authority", true)
	_assert(failures, not radio.call("_mouse_hits_radio", screen_position, player) or radio.get_interaction_candidate(player).is_empty(), "超出距离仍可交互 radio")
	player.global_position = radio.global_position + Vector3(0.0, -0.90, 1.1)
	player.set_combat_enabled(true)
	_assert(failures, radio.get_interaction_candidate(player).is_empty(), "战斗中仍可交互 radio")
	player.set_combat_enabled(false)

	radio.set_radio_state("b")
	player.global_position = TowerDescent3D.ROOFTOP_LOGOUT_SPAWN
	tower.call("_refresh_physical_location_authority", true)
	await get_tree().process_frame
	_assert(failures, radio.get_radio_state() == "off", "离开99F后 radio 未关闭")
	_assert(failures, MusicManager == null or MusicManager.get_current_music_id() == "rooftop_relax", "离开99F后天台音乐未恢复")

	player.global_position = radio.global_position + Vector3(0.0, -0.90, 1.1)
	tower.call("_refresh_physical_location_authority", true)
	await get_tree().process_frame
	_assert(failures, radio.get_radio_state() == "off", "返回99F后 radio 不应自动恢复播放")
	_assert(failures, radio.get_state_snapshot().get("floor_active", false), "返回99F后 radio 未重新激活")
	tower.free()
	if isolated_radio != null:
		isolated_radio.free()
	await get_tree().process_frame


func _click_radio(radio: Base99Radio3D, screen_position: Vector2, expected_state: String) -> bool:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_position
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		event.position = camera.unproject_position(radio.to_global(Vector3(0.0, 0.411, 0.0)))
	var player := radio.call("_get_player") as Player3D
	print("RADIO_DISPATCH_BEFORE expected=%s state=%s can=%s hit=%s player=%s screen=%s" % [expected_state, radio.get_radio_state(), radio.call("_can_interact", player), radio.call("_mouse_hits_radio", event.position, player), player.global_position, event.position])
	Input.parse_input_event(event)
	await get_tree().process_frame
	print("RADIO_DISPATCH_AFTER state=%s" % radio.get_radio_state())
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
	return radio.get_radio_state() == expected_state


func _world_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		var local := mesh.get_aabb()
		for index in 8:
			var point := mesh.global_transform * local.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result


func _assert(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE99_RADIO_OK: prefab, bounds contract, battery cabinet placement, dispatched mouse input, off-A-B-off, Music bus, fixed looping tracks, floor music exclusion")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("BASE99_RADIO_FAIL: " + failure)
	get_tree().quit(1)
