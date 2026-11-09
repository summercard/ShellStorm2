extends Node
## 临时探针：billboard 准星 + 敌方子弹图标的朝向/尺寸/可见性实测。
## 运行：godot --headless --path . --scene res://tools/_probe_billboard_icons.tscn

const PLAYER := preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	get_viewport().size = Vector2i(1920, 1080)
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80, 0.2, 80)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0, -0.1, 0)
	ground.add_child(ground_shape)
	stage.add_child(ground)

	var player := PLAYER.instantiate() as Player3D
	stage.add_child(player)
	player.set_process(false)
	for i in range(40):
		await get_tree().physics_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.equip_weapon("bp_pistol", "mod_bullet_standard")
	var camera := player.get_node("Camera3D") as Camera3D
	camera.current = true
	await get_tree().process_frame

	# ── 准星：摇杆分支定位，然后读朝向与尺寸 ──
	player._mobile_input_available = true
	player._mobile_face_active = true
	player._mobile_face_direction = Vector2(0.0, -1.0)
	player.call("_update_aim_from_mouse")
	await get_tree().process_frame

	var cursor := player.get_node("AimCursor") as Node3D
	var icon := cursor.get_node("Icon") as Node3D
	print("CURSOR_POS=", cursor.global_position)
	print("CURSOR_SCALE=", cursor.scale)
	print("CURSOR_BASIS_Z=", cursor.global_transform.basis.z.normalized())
	print("CAMERA_BASIS_Z=", camera.global_transform.basis.z.normalized())
	print("CURSOR_ALIGN=", cursor.global_transform.basis.z.normalized().dot(camera.global_transform.basis.z.normalized()))
	print("ICON_VISIBLE=", icon.visible)
	print("CURSOR_CHILD_COUNT=", cursor.get_child_count())
	for child in cursor.get_children():
		print("  CHILD=", child.name, " type=", child.get_class())
	# 屏幕尺寸：投影片面上的两点
	var half := cursor.scale.x * 0.5
	var right := cursor.global_transform.basis.x.normalized() * half
	var p0 := camera.unproject_position(cursor.global_position - right)
	var p1 := camera.unproject_position(cursor.global_position + right)
	print("VIEWPORT_SIZE=", get_viewport().get_visible_rect().size)
	print("CAMERA_POS=", camera.global_position)
	print("CAMERA_TO_CURSOR=", camera.global_position.distance_to(cursor.global_position))
	var dist := camera.global_position.distance_to(cursor.global_position)
	var vph := get_viewport().get_visible_rect().size.y
	print("WORLD_PER_PX=", 2.0 * dist * tan(deg_to_rad(camera.fov) * 0.5) / vph)
	print("TARGET_WORLD_FOR_48PX=", 48.0 * 2.0 * dist * tan(deg_to_rad(camera.fov) * 0.5) / vph)
	print("CURSOR_SCREEN_PX=", p0.distance_to(p1))

	# ── 敌方子弹：hostile 应走 billboard ──
	var hostile := Projectile3D.new()
	stage.add_child(hostile)
	hostile.activate({
		"direction": Vector3(0, 0, -1), "speed": 12.0, "damage": 5, "hostile": true,
		"target_group": "player_3d", "projectile_collision_mask": 1,
		"visual_scale": 2.0, "shooter": player,
	}, Vector3(2.0, 0.75, -3.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var hsnap: Dictionary = hostile.get_orientation_snapshot()
	print("HOSTILE_BILLBOARD=", hsnap.get("billboard"))
	print("HOSTILE_ICON_VISIBLE=", hsnap.get("icon_visible"))
	print("HOSTILE_ICON_SIDE=", hsnap.get("icon_world_side"))
	print("HOSTILE_ICON_CORE_DIAM=", hsnap.get("icon_core_diameter"))
	print("HOSTILE_COLLISION_RADIUS=", hsnap.get("collision_radius"))
	print("HOSTILE_ICON_ALIGN=", hsnap.get("icon_camera_alignment"))
	print("HOSTILE_TRAIL_VISIBLE=", hsnap.get("trail_visible"))
	print("HOSTILE_BODY_VISIBLE=", hsnap.get("body_visible"))
	print("HOSTILE_VISUAL_BODY_SCALE=", hsnap.get("visual_body_scale"))

	# ── 玩家子弹：应保持 3D 弹体 ──
	var friendly := Projectile3D.new()
	stage.add_child(friendly)
	friendly.activate({
		"direction": Vector3(0, 0, -1), "speed": 15.0, "damage": 25, "hostile": false,
		"target_group": "enemy_3d", "projectile_collision_mask": 5, "shooter": player,
	}, Vector3(-2.0, 0.75, -3.0))
	await get_tree().process_frame
	var fsnap: Dictionary = friendly.get_orientation_snapshot()
	print("FRIENDLY_BILLBOARD=", fsnap.get("billboard"))
	print("FRIENDLY_ICON_VISIBLE=", fsnap.get("icon_visible"))
	print("FRIENDLY_TRAIL_VISIBLE=", fsnap.get("trail_visible"))
	print("FRIENDLY_VISUAL_BODY_SCALE=", fsnap.get("visual_body_scale"))

	get_tree().quit(0)
