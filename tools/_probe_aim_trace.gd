extends Node
## 临时探针：量「准星 vs 弹道」在屏幕上的偏差（像素），覆盖正前 / 斜向 / 近距。
## 运行：godot --headless --path . --scene res://tools/_probe_aim_trace.tscn

const PLAYER := preload("res://scenes/Player3D.tscn")
const MOUSE_POINTS := [
	Vector2(960.0, 620.0),
	Vector2(1500.0, 700.0),
	Vector2(960.0, 860.0),
	Vector2(400.0, 700.0),
]


func _ready() -> void:
	get_viewport().size = Vector2i(1920, 1080)
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	var body := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	ground_shape.shape = box
	ground_shape.position = Vector3(0, -0.1, 0)
	body.add_child(ground_shape)
	stage.add_child(body)

	var player := PLAYER.instantiate() as Player3D
	stage.add_child(player)
	player.set_process(false)
	for i in range(60):
		await get_tree().physics_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)

	print("EQUIP=", player.equip_weapon("bp_pistol", "mod_bullet_standard"))
	for i in range(4):
		await get_tree().process_frame

	var weapon: WeaponModel3D = player.weapon
	var camera := player.get_node("Camera3D") as Camera3D
	camera.current = true
	await get_tree().process_frame

	var muzzle := weapon.muzzle_global_position()
	print("PLAYER_POS=", player.global_position)
	print("MUZZLE=", muzzle, " ABOVE_FEET=", muzzle.y - player.global_position.y)
	print("AIM_TARGET_HEIGHT=", player.AIM_TARGET_HEIGHT)

	var cursor := player.get_node("AimCursor") as Node3D
	for mouse in MOUSE_POINTS:
		var ray_origin := camera.project_ray_origin(mouse)
		var ray_dir := camera.project_ray_normal(mouse)
		var plane_hit: Variant = Plane(
			Vector3.UP, player.global_position.y + player.AIM_TARGET_HEIGHT
		).intersects_ray(ray_origin, ray_dir)
		if not plane_hit is Vector3:
			print("MOUSE=", mouse, " NO_PLANE_HIT")
			continue
		var cursor_pos: Vector3 = plane_hit as Vector3
		cursor.global_position = cursor_pos
		var flat := cursor_pos - player.global_position
		flat.y = 0.0
		var aim_dir := flat.normalized()
		var shot_dir: Vector3 = player._ballistic_direction(aim_dir, cursor_pos)

		weapon.set("_cooldown", 0.0)
		weapon.current_ammo = 12
		var spawned: Array = []
		var cb := func(p: Projectile3D) -> void: spawned.append(p)
		weapon.projectile_spawned.connect(cb)
		weapon.call("_fire_now", shot_dir, player, 1.0)
		weapon.projectile_spawned.disconnect(cb)
		if spawned.is_empty():
			print("MOUSE=", mouse, " NO_PROJECTILE")
			continue
		var projectile := spawned[0] as Projectile3D
		var start := projectile.global_position
		var dir := projectile.direction
		var t := (cursor_pos - start).dot(dir)
		var bullet_at := start + dir * t

		var cursor_screen := camera.unproject_position(cursor_pos)
		var bullet_screen := camera.unproject_position(bullet_at)
		print("MOUSE=", mouse, " DIST_H=", flat.length(), " SHOT_ANGLE_DEG=", rad_to_deg(aim_dir.angle_to(dir)))
		print("  CURSOR_SCREEN=", cursor_screen, " MOUSE_DELTA=", cursor_screen - mouse)
		print("  BULLET_SCREEN=", bullet_screen)
		print("  SCREEN_DELTA_PX=", bullet_screen - cursor_screen)
		print("  WORLD_DELTA_M=", bullet_at - cursor_pos)
		projectile.free()

	get_tree().quit(0)
