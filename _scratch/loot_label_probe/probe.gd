extends Node3D
## 实拍：GroundLootPickup3D 名牌策略（货币不挂名牌）。
## 左 = 货币（__currency__ / 魂）—— 应无名牌
## 右 = 普通物品（item_health_potion）—— 应仍有名牌
## 用真实 ItemRegistry 数据与真实组件，不用手搓 Label。

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
	cam.position = Vector3(0.0, 3.6, 2.4)
	cam.look_at(Vector3(0.0, 0.7, 0.0), Vector3.UP)
	cam.fov = 45.0
	cam.make_current()

	var currency := _spawn(_currency_data(), Vector3(-0.95, 0.0, 0.0))
	var potion_data := ItemRegistry.get_instance().get_item("item_health_potion")
	if potion_data.is_empty():
		push_error("PROBE: 找不到 item_health_potion")
		get_tree().quit(1)
		return
	var potion := _spawn(potion_data, Vector3(0.95, 0.0, 0.0))

	for _i in range(8):
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout

	var currency_snapshot := currency.get_model_snapshot()
	var potion_snapshot := potion.get_model_snapshot()
	print("CURRENCY  name=%s  is_currency=%s  label_shown=%s  label_text=%s" % [
		str(currency.item_data.get("name", "")),
		str(currency_snapshot.get("is_currency", "")),
		str(currency_snapshot.get("label_shown", "")),
		str(currency_snapshot.get("label_text", "")),
	])
	print("POTION    name=%s  is_currency=%s  label_shown=%s  label_text=%s" % [
		str(potion.item_data.get("name", "")),
		str(potion_snapshot.get("is_currency", "")),
		str(potion_snapshot.get("label_shown", "")),
		str(potion_snapshot.get("label_text", "")),
	])
	print("POLICY    LABEL_DISPLAY_POLICY=%s" % GroundLootPickup3D.LABEL_DISPLAY_POLICY)
	print("NODE_COUNT currency_labels=%d potion_labels=%d" % [
		_count_labels(currency), _count_labels(potion),
	])

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_scratch/loot_label_probe/probe_out.png")
	print("PROBE_SAVED")
	get_tree().quit()


## 复刻 RewardSink 造货币的字段（id __currency__ + name 魂 + is_currency）。
func _currency_data() -> Dictionary:
	return {
		"id": "__currency__",
		"name": "魂",
		"type": "currency",
		"count": 15,
		"is_currency": true,
	}


func _spawn(data: Dictionary, pos: Vector3) -> GroundLootPickup3D:
	var pickup := GroundLootPickup3D.new()
	pickup.position = pos
	add_child(pickup)
	pickup.configure(data, Color(0.38, 0.88, 0.72))
	return pickup


func _count_labels(node: Node) -> int:
	var total := 0
	for child in node.find_children("*", "Label3D", true, false):
		total += 1
	return total
