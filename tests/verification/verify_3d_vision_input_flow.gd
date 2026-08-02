extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 240724
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame

	await _verify_inventory_shortcuts(dungeon, failures)
	await _verify_pause_priority(dungeon, failures)
	await _verify_true_vision(dungeon, failures)

	if failures.is_empty():
		print("3D_VISION_INPUT_FLOW_OK: 360 occlusion vision, manual F flashlight, I/Tab inventory lock and recoverable pause pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_inventory_shortcuts(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var inventory_ui := dungeon.get_node_or_null("HUD/InventoryUI3D") as InventoryUI
	if inventory_ui == null:
		failures.append("3D inventory UI is missing")
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if inventory_ui.size.x < viewport_size.x - 2.0 or inventory_ui.size.y < viewport_size.y - 2.0:
		failures.append("Inventory root does not fill the viewport, so right-anchored panels can render off-screen")
	await _tap_action("ui_inventory")
	if not inventory_ui.is_inventory_open() or not dungeon.player.input_locked:
		failures.append("ui_inventory / I action did not open the inventory and lock player input")
	await _tap_action("ui_inventory")
	if inventory_ui.is_inventory_open() or dungeon.player.input_locked:
		failures.append("ui_inventory / I action did not close the inventory and restore input")
	await _tap_key(KEY_I)
	if not inventory_ui.is_inventory_open() or not dungeon.player.input_locked:
		failures.append("Physical I key did not open the 3D inventory")
	await _tap_key(KEY_I)
	if inventory_ui.is_inventory_open() or dungeon.player.input_locked:
		failures.append("Physical I key did not close the 3D inventory")
	await _tap_action("ui_tab")
	if not inventory_ui.is_inventory_open():
		failures.append("3D compatibility Tab shortcut did not open the inventory")
	await _tap_action("ui_tab")
	if inventory_ui.is_inventory_open():
		failures.append("3D compatibility Tab shortcut did not close the inventory")
	var control_hint := dungeon.get_node_or_null("HUD/ControlHint") as Label
	if control_hint == null or "I / Tab 背包" not in control_hint.text:
		failures.append("HUD does not teach the inventory shortcut")
	if control_hint == null or "F 探照灯" not in control_hint.text:
		failures.append("HUD does not teach the manual flashlight shortcut")


func _verify_pause_priority(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var inventory_ui := dungeon.get_node_or_null("HUD/InventoryUI3D") as InventoryUI
	var pause_overlay := dungeon.get_node_or_null("HUD/PauseOverlay") as PauseMenu3D
	if inventory_ui == null or pause_overlay == null:
		failures.append("Inventory or pause overlay missing from 3D HUD")
		return
	await _tap_action("ui_inventory")
	await _tap_action("pause")
	if inventory_ui.is_inventory_open():
		failures.append("Esc did not close inventory first")
	if get_tree().paused or pause_overlay.is_pause_open():
		failures.append("Closing inventory with Esc also opened pause")
	await _tap_action("pause")
	if not get_tree().paused or not pause_overlay.is_pause_open():
		failures.append("Esc did not open a visible, real pause state")
	await _tap_action("pause")
	if get_tree().paused or pause_overlay.is_pause_open():
		failures.append("Second Esc did not resume the paused 3D run")


func _verify_true_vision(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var vision := dungeon.player.get_node_or_null("PlayerVision3D") as PlayerVision3D
	if vision == null:
		failures.append("PlayerVision3D is missing")
		return
	dungeon.player.global_position = Vector3(0, 0.05, 0)
	dungeon.player.aim_direction = Vector3(0, 0, -1)
	dungeon.player.aim_yaw = 0.0
	var blocker := StaticBody3D.new()
	blocker.name = "VisionAcceptanceWall"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	blocker.position = Vector3(0, 1.0, -4.0)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.2, 2.0, 0.5)
	shape_node.shape = shape
	blocker.add_child(shape_node)
	dungeon.add_child(blocker)
	await get_tree().physics_frame
	vision.force_refresh()
	if not vision.is_position_visible(Vector3(0, 0.7, -2.0)):
		failures.append("Clear point inside the presentation cone is not visible")
	if vision.is_position_visible(Vector3(0, 0.7, -8.0)):
		failures.append("Physical wall does not block gameplay vision")
	if not vision.is_position_visible(Vector3(0, 0.7, 3.0)):
		failures.append("Clear point behind the player is hidden by presentation direction")
	var snapshot := vision.get_snapshot()
	if (
		not is_equal_approx(float(snapshot.get("gameplay_angle_degrees", 0.0)), 360.0)
		or not is_equal_approx(float(snapshot.get("presentation_angle_degrees", 0.0)), 96.0)
		or not bool(snapshot.get("gameplay_omnidirectional", false))
	):
		failures.append("Vision snapshot does not separate 360-degree gameplay from 96-degree presentation")
	if str(snapshot.get("visibility_mode", "")) != "omnidirectional_range_with_physical_occlusion":
		failures.append("Vision snapshot does not declare the occlusion-only omnidirectional contract")
	if bool(snapshot.get("gameplay_light_dependent", true)):
		failures.append("Gameplay visibility still depends on lighting")
	if str(snapshot.get("visual_mode", "")) != "soft_raycast_field_with_real_flashlight_rig":
		failures.append("Vision range has no soft raycast visualization")
	if not bool(snapshot.get("soft_edge", false)) or bool(snapshot.get("hard_outline", true)):
		failures.append("Vision GUI still uses a hard outline instead of a feathered edge")
	if not bool(snapshot.get("surface_no_depth_test", false)):
		failures.append("Vision GUI can still be depth-sorted below room floors")
	if (
		int(snapshot.get("presentation_light_count", 0)) != 3
		or int(snapshot.get("spotlight_count", 0)) != 2
		or int(snapshot.get("spill_light_count", 0)) != 1
		or int(snapshot.get("front_fill_light_count", 0)) != 1
		or int(snapshot.get("shadow_light_count", 0)) != 1
	):
		failures.append("Real flashlight must contain one shadowing environment beam plus non-shadow spill/front fill")
	var flashlight := dungeon.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight == null:
		failures.append("Independent PlayerFlashlight3D rig is missing")
	else:
		flashlight.force_sync()
		var flashlight_snapshot := flashlight.get_snapshot()
		var beam := flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D
		var spill := flashlight.get_node_or_null("FlashlightKit/EnvironmentSpill") as OmniLight3D
		var front_fill := flashlight.get_node_or_null("FlashlightKit/AvatarFrontFill") as SpotLight3D
		if flashlight.is_light_enabled() or bool(flashlight_snapshot.get("start_enabled", true)):
			failures.append("探照灯没有以手动关闭状态进入战局")
		if (
			not bool(flashlight_snapshot.get("manual_toggle", false))
			or str(flashlight_snapshot.get("toggle_action", "")) != "toggle_flashlight"
			or not InputMap.has_action("toggle_flashlight")
		):
			failures.append("探照灯没有登记独立手动输入动作")
		await _tap_action("toggle_flashlight")
		if not flashlight.is_light_enabled():
			failures.append("toggle_flashlight动作没有打开探照灯")
		await _tap_key(KEY_F)
		if flashlight.is_light_enabled():
			failures.append("物理F键没有关闭探照灯")
		# 输入事件会跨过若干处理帧；重新固定本专项的正北测试朝向，
		# 避免无窗口鼠标位置改变扇形采样方向。
		dungeon.player.aim_direction = Vector3(0, 0, -1)
		dungeon.player.aim_yaw = 0.0
		flashlight.force_sync()
		vision.force_refresh()
		# 关灯时 light_energy 会被归零，所以重新打开才能校验 export 值与 cull_mask。
		flashlight.set_light_enabled(true)
		beam = flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D
		spill = flashlight.get_node_or_null("FlashlightKit/EnvironmentSpill") as OmniLight3D
		front_fill = flashlight.get_node_or_null("FlashlightKit/AvatarFrontFill") as SpotLight3D
		if flashlight.mount_height > 1.5 or flashlight.mount_height < 1.0:
			failures.append("1.5m角色探照灯安装点没有落在胸口/武器高度")
		if flashlight.front_fill_height > 1.5 or flashlight.avatar_target_height > 1.2:
			failures.append("角色补光仍沿用高于1.5m角色的旧坐标")
		if beam == null or not beam.shadow_enabled or beam.light_energy < 12.0 or beam.spot_range < 20.0:
			failures.append("Forward flashlight is not a sufficiently bright real environment SpotLight3D")
		if spill == null or spill.shadow_enabled or spill.light_energy < 1.5 or spill.omni_range < 4.0:
			failures.append("Environment spill light is missing or incorrectly configured")
		# 完成后立刻关灯，保证后续视觉测试回到关灯基线。
		flashlight.set_light_enabled(false)
		if (
			front_fill == null
			or front_fill.shadow_enabled
			or front_fill.light_energy > 1.2
			or front_fill.light_cull_mask != 2
			or beam.light_cull_mask != 1
			or spill.light_cull_mask != 1
		):
			failures.append("Avatar front fill is not a subtle layer-2-only light, or environment lights leak onto the avatar")
		if not bool(flashlight_snapshot.get("shadow_light_disabled_for_avatar", false)):
			failures.append("Flashlight snapshot must report shadow_light_disabled_for_avatar=true")
		if bool(flashlight_snapshot.get("environment_spill_affects_avatar", true)) or not bool(flashlight_snapshot.get("front_fill_affects_avatar", false)):
			failures.append("Flashlight snapshot does not preserve environment/avatar light isolation")
		if float(flashlight_snapshot.get("aim_alignment", 0.0)) < 0.99:
			failures.append("Real flashlight beam does not follow the player's aim direction")
		if not bool(flashlight_snapshot.get("configurable", false)):
			failures.append("Real flashlight parameters are not exposed for tuning")
	if vision.get_node_or_null("VisionFieldSurface") == null or vision.get_node_or_null("VisionProximitySurface") == null:
		failures.append("Cone/proximity vision surfaces are missing")
	var cone_points := vision.get_cone_points_for_test()
	if cone_points.size() != vision.cone_ray_count:
		failures.append("Rendered cone does not use the configured ray sample count")
	else:
		var center_distance := cone_points[cone_points.size() / 2].length()
		if center_distance >= 4.0 or center_distance <= 3.0:
			failures.append("Rendered cone boundary is not clipped to the physical wall (distance=%.2f)" % center_distance)
	var hidden_target := Node3D.new()
	hidden_target.name = "LightIndependenceTarget"
	hidden_target.add_to_group("ground_loot_3d")
	hidden_target.position = Vector3(0, 0.2, -8.0)
	dungeon.add_child(hidden_target)
	var decorative_light := OmniLight3D.new()
	decorative_light.omni_range = 8.0
	decorative_light.light_energy = 12.0
	hidden_target.add_child(decorative_light)
	vision.force_refresh()
	if hidden_target.visible:
		failures.append("A bright scene light revealed a logically occluded target")
	hidden_target.position = Vector3(0, 0.2, -2.0)
	vision.force_refresh()
	if not hidden_target.visible:
		failures.append("A target inside clear gameplay vision remained hidden")
	hidden_target.position = Vector3(0, 0.2, 3.0)
	vision.force_refresh()
	if not hidden_target.visible:
		failures.append("A real ground-loot target behind the player is hidden without an occluder")
	var rear_blocker := StaticBody3D.new()
	rear_blocker.name = "RearVisionAcceptanceWall"
	rear_blocker.collision_layer = 1
	rear_blocker.collision_mask = 0
	rear_blocker.position = Vector3(0, 1.0, 4.0)
	var rear_shape_node := CollisionShape3D.new()
	var rear_shape := BoxShape3D.new()
	rear_shape.size = Vector3(3.2, 2.0, 0.5)
	rear_shape_node.shape = rear_shape
	rear_blocker.add_child(rear_shape_node)
	dungeon.add_child(rear_blocker)
	await get_tree().physics_frame
	if vision.is_position_visible(Vector3(0, 0.7, 8.0)):
		failures.append("Physical wall behind the player does not block 360-degree gameplay vision")
	hidden_target.position = Vector3(0, 0.2, 8.0)
	vision.force_refresh()
	if hidden_target.visible:
		failures.append("A real ground-loot target behind a rear wall remains visible")


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


func _tap_key(keycode: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventKey.new()
	released.keycode = keycode
	released.physical_keycode = keycode
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame
