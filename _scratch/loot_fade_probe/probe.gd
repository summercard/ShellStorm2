extends Node3D
## 真实组件实拍：GroundLootPickup3D 名牌在「拾取瞬间」的旧/新写法对照。
## 左 = 旧写法（只把 modulate.a 归零）：正文没了，黑色描边原地留下
## 右 = 新写法（transparency = 1.0）：正文与描边一起走干净
## 使用真实 ItemRegistry 物品数据（weapon_pistol / 豌豆手枪）与真实名牌参数。

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.47, 0.53)
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 3.4, 2.6)
	cam.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	cam.fov = 45.0
	cam.make_current()

	var data := _find_item("weapon_pistol")
	if data.is_empty():
		push_error("PROBE: 找不到 weapon_pistol")
		get_tree().quit(1)
		return

	var left := _spawn(data, Vector3(-1.0, 0.0, 0.0))
	var right := _spawn(data, Vector3(1.0, 0.0, 0.0))

	for _i in range(6):
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	await _capture("res://_scratch/loot_fade_probe/shot_1_before.png")

	# 定格「拾取瞬间」：左走旧写法，右走新写法。
	(left.get_node("LootLabel") as Label3D).modulate.a = 0.0
	(right.get_node("LootLabel") as Label3D).transparency = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("res://_scratch/loot_fade_probe/shot_2_after.png")

	print("PROBE_DONE")
	get_tree().quit()


func _find_item(item_id: String) -> Dictionary:
	var registry := ItemRegistry.get_instance()
	for item in registry.get_all_items():
		if str(item.get("id", "")) == item_id:
			return item
	return {}


func _spawn(data: Dictionary, pos: Vector3) -> GroundLootPickup3D:
	var pickup := GroundLootPickup3D.new()
	pickup.position = pos
	add_child(pickup)
	pickup.configure(data, Color(0.38, 0.88, 0.72))
	return pickup


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_SHOT ", path)
