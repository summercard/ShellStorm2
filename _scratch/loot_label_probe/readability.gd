extends Node3D
## 去掉「框框」后的实拍 + 可读性代价验证。
## 用真实 GroundLootPickup3D 与真实 ItemRegistry 物品色。
## A 组：正常地面（灰）—— 看是不是真的没有框了
## B 组：浅色强光地面 —— 看无描边时对比度还够不够（这是去掉描边的代价）

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.05, 1.45)
	cam.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	cam.fov = 40.0
	cam.make_current()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	# A 组：正常灰地面
	await _shoot(0.42, "loot_outline0_normal_floor.png")
	# B 组：浅色强光地面（最坏情况）
	await _shoot(0.86, "loot_outline0_bright_floor.png")

	print("PROBE_DONE")
	get_tree().quit()


func _shoot(gray: float, file: String) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(gray, gray, gray + 0.02)
	env.environment = e
	add_child(env)

	var registry := ItemRegistry.get_instance()
	var ids := ["item_health_potion", "weapon_pistol", "mod_bullet_piercing"]
	var made: Array[Node] = []
	for i in range(ids.size()):
		var data := registry.get_item(ids[i])
		if data.is_empty():
			continue
		var pickup := GroundLootPickup3D.new()
		pickup.position = Vector3((float(i) - 1.0) * 1.05, 0.0, 0.0)
		add_child(pickup)
		pickup.configure(data, ItemModelFactory3D.get_item_color(data))
		made.append(pickup)

	for _i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_scratch/loot_label_probe/" + file)
	print(
		"SHOT %s floor_gray=%.2f outline=%d" % [
			file, gray, GroundLootPickup3D.LABEL_OUTLINE_SIZE,
		]
	)
	for node in made:
		node.queue_free()
	env.queue_free()
	await get_tree().process_frame
