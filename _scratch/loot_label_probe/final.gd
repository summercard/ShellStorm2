extends Node3D
## 最终实拍：所有地上掉落物（普通物品 / 货币「魂」/ 房间钥匙）**一律没有文字**。
## 用真实组件 + 真实 ItemRegistry 数据，俯视视角模拟游戏内观感。

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.34, 0.42)
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -28.0, 0.0)
	sun.light_energy = 1.0
	add_child(sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 3.9, 3.0)
	cam.look_at(Vector3(0.0, 0.35, 0.0), Vector3.UP)
	cam.fov = 42.0
	cam.make_current()

	var registry := ItemRegistry.get_instance()
	var nodes: Array[Node] = []

	# 第一行：普通物品
	var row0 := ["item_health_potion", "weapon_pistol", "mod_bullet_piercing", "bp_pistol"]
	for i in range(row0.size()):
		var data := registry.get_item(row0[i])
		if data.is_empty():
			print("MISSING_ITEM ", row0[i])
			continue
		nodes.append(_loot(data, Vector3((float(i) - 1.5) * 1.0, 0.0, -0.62)))

	# 第二行：货币「魂」 + 其它实物
	var currency := {
		"id": "__currency__", "name": "魂", "type": "currency",
		"count": 15, "is_currency": true,
	}
	nodes.append(_loot(currency, Vector3(-1.5, 0.0, 0.62)))
	var row1 := ["mod_bullet_bounce", "item_flashlight_module", "item_health_potion"]
	for i in range(row1.size()):
		var data := registry.get_item(row1[i])
		if data.is_empty():
			print("MISSING_ITEM ", row1[i])
			continue
		nodes.append(_loot(data, Vector3((float(i) - 0.5) * 1.0, 0.0, 0.62)))

	# 房间钥匙
	var key := RoomKeyPickup3D.new()
	key.configure("room_probe")
	key.position = Vector3(1.75, 0.0, 0.62)
	add_child(key)
	nodes.append(key)

	for _i in range(10):
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

	# 逐件报告：地上必须一个 Label3D 都没有
	var total_labels := 0
	for node in nodes:
		var labels := node.find_children("*", "Label3D", true, false)
		total_labels += labels.size()
		var shown := false
		if node is GroundLootPickup3D:
			shown = bool((node as GroundLootPickup3D).get_model_snapshot().get("label_shown", false))
		elif node is RoomKeyPickup3D:
			shown = bool((node as RoomKeyPickup3D).get_pickup_snapshot().get("label_shown", false))
		var name := ""
		if node is GroundLootPickup3D:
			name = str((node as GroundLootPickup3D).item_data.get("name", ""))
		else:
			name = "房间钥匙"
		print("LOOT %-14s label_shown=%s Label3D_count=%d" % [name, str(shown), labels.size()])
	print("TOTAL_Label3D=%d  POLICY=%s  KEY_LABEL=%s" % [
		total_labels,
		GroundLootPickup3D.LABEL_DISPLAY_POLICY,
		str(RoomKeyPickup3D.SHOW_NAME_LABEL),
	])

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_scratch/loot_label_probe/final_no_text.png")
	print("PROBE_SAVED")
	get_tree().quit()


func _loot(data: Dictionary, pos: Vector3) -> GroundLootPickup3D:
	var pickup := GroundLootPickup3D.new()
	pickup.position = pos
	add_child(pickup)
	pickup.configure(data, ItemModelFactory3D.get_item_color(data))
	return pickup
