extends Node
## 宝箱档位 + 命运卡真模型真实渲染取证。
## 仅接受工程外的 CHEST_FATE_RENDER_DIR；不得回写 res://outputs。

const VIEW_W := 1400
const VIEW_H := 720
const ORTHO_SIZE := 5.8
const CAM_POSITION := Vector3(0.0, 5.2, 10.8)
const CAM_TARGET := Vector3(0.0, 0.72, 0.0)
const WARMUP_FRAMES := 15
const CARD_ROTATION_SPEED := 0.55
const LINEUP := [
	{"label": "普通\n未开", "quality": "common", "chest_tier": "normal", "opened": false, "position": Vector3(-3.25, 0.0, -0.80)},
	{"label": "普通\n已开", "quality": "common", "chest_tier": "normal", "opened": true, "position": Vector3(-1.08, 0.0, -0.80)},
		{"label": "高级\n未开", "quality": "rare", "chest_tier": "advanced", "opened": false, "position": Vector3(1.08, 0.0, -0.80)},
		{"label": "高级\n已开", "quality": "rare", "chest_tier": "advanced", "opened": true, "position": Vector3(3.25, 0.0, -0.80)},
]

var _vp: SubViewport
var _camera: Camera3D
var _chests: Array[TreasureChest3D] = []
var _cards: Array[FateCardDropPickup3D] = []
var _frames := 0
var _output_dir := ""
var _first_image: Image


func _process(_delta: float) -> void:
	_hide_runtime_labels_except_captions()


func _ready() -> void:
	# 在正式交互控制器之后执行，避免它每帧重新打开 InteractionDot3D。
	process_priority = 100000
	_output_dir = _read_output_dir()
	if _output_dir.is_empty():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output_dir)
	print("CHEST_FATE_RENDER_DIR=%s" % _output_dir)
	_build_view()
	_build_chest_lineup()
	_build_fate_card_lineup()
	_hide_runtime_labels_except_captions()
	_run_capture_sequence()


func _read_output_dir() -> String:
	var path := OS.get_environment("CHEST_FATE_RENDER_DIR").strip_edges()
	if path.is_empty():
		push_error("CHEST_FATE_RENDER_DIR 必填；拒绝写入工程内默认出口")
		return ""
	if not path.is_absolute_path():
		push_error("CHEST_FATE_RENDER_DIR 必须是绝对路径：%s" % path)
		return ""
	return path.trim_suffix("/").trim_suffix("\\")


func _build_view() -> void:
	_vp = SubViewport.new()
	_vp.name = "ChestFateEvidenceViewport"
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.035, 0.060)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.54, 0.62, 0.82)
	environment.ambient_light_energy = 1.15
	env.environment = environment
	_vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.45
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.62
	fill.rotation_degrees = Vector3(-18.0, 142.0, 0.0)
	_vp.add_child(fill)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(12.5, 5.6)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.075, 0.095, 0.14)
	ground_material.roughness = 0.92
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.name = "EvidenceGround"
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.01, 0.0)
	_vp.add_child(ground)

	_camera = Camera3D.new()
	_camera.name = "EvidenceCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ORTHO_SIZE
	_vp.add_child(_camera)
	_camera.look_at_from_position(CAM_POSITION, CAM_TARGET, Vector3.UP)
	_camera.current = true


func _build_chest_lineup() -> void:
	for item_index in range(LINEUP.size()):
		var item := LINEUP[item_index] as Dictionary
		var chest := TreasureChest3D.new()
		chest.name = "Chest_%02d_%s" % [item_index, str(item["chest_tier"])]
		chest.configure({
			"id": "render_%02d" % item_index,
			"quality": item["quality"],
			"chest_tier": item["chest_tier"],
		})
		chest.position = item["position"]
		_vp.add_child(chest)
		# 取证场景不放玩家，不需要正式交互点；移除 provider 组避免运行时 UI 圆点遮挡模型。
		chest.remove_from_group("interaction_provider_3d")
		chest.remove_from_group("interaction_providers_3d")
		if bool(item["opened"]):
			chest.restore_opened_state(true)
		for label_node in chest.find_children("*", "Label3D", true, false):
			(label_node as Label3D).visible = false
		_chests.append(chest)
		_add_caption(str(item["label"]), chest.position + Vector3(0.0, 1.38, 0.48), Color(0.92, 0.94, 1.0))


func _build_fate_card_lineup() -> void:
	var card_data := [
		{"id": "render_card_a", "position": Vector3(-1.28, 0.0, 1.28), "label": "FateCardDropPickup3D\n扫描流光"},
		{"id": "render_card_b", "position": Vector3(1.28, 0.0, 1.28), "label": "悬浮 · 慢转\n0.55 rad/s"},
	]
	for data in card_data:
		var card := FateCardDropPickup3D.new()
		card.name = str(data["id"])
		card.configure({
			"type": "fate_pickup",
			"id": "item_fate_card_drop",
			"fate_pickup_id": data["id"],
			"card_source": "chest_render_evidence",
		})
		card.position = data["position"]
		card.scale = Vector3.ONE * 1.55
		_vp.add_child(card)
		card.remove_from_group("interaction_provider_3d")
		card.remove_from_group("interaction_providers_3d")
		for label_node in card.find_children("*", "Label3D", true, false):
			(label_node as Label3D).visible = false
		_cards.append(card)
		_add_caption(str(data["label"]), card.position + Vector3(0.0, 1.22, 0.50), Color(0.55, 0.86, 1.0))


func _hide_runtime_labels_except_captions() -> void:
	_hide_runtime_node(_vp)


func _hide_runtime_node(node: Node) -> void:
	if node is Label3D and not node.is_in_group("chest_fate_render_caption"):
		(node as Label3D).visible = false
	if node is Node3D:
		var node3d := node as Node3D
		var node_name := str(node.name).to_lower()
		var script := node.get_script() as Script
		var is_interaction_dot := script != null and script.resource_path == "res://src/ui/InteractionDot3D.gd"
		if is_interaction_dot:
			node3d.process_mode = Node.PROCESS_MODE_DISABLED
			node3d.visible = false
		elif node_name in ["chestprompt", "lootlabel", "keyhint", "interactiondot3d"] \
			or node_name.begins_with("questionmark"):
			node3d.visible = false
	for child in node.get_children():
		_hide_runtime_node(child)


func _add_caption(text: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.add_to_group("chest_fate_render_caption")
	label.text = text
	label.font_size = 25
	label.pixel_size = 0.008
	label.outline_size = 6
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position
	_vp.add_child(label)


func _run_capture_sequence() -> void:
	for _frame in WARMUP_FRAMES:
		await get_tree().process_frame
	_print_projection_evidence("warmup")
	var first := _capture("egt_chest_fate_render_00")
	_first_image = first
	await _wait_seconds(1.10)
	_capture("egt_chest_fate_render_01_card_scan_later")
	await _wait_seconds(0.70)
	var third := _capture("egt_chest_fate_render_02_card_scan_latest")
	if _first_image != null and third != null:
		print("CARD_RENDER_DIFF first_latest=%.5f (shader TIME + 0.55 rad/s rotation evidence)" % _image_difference(_first_image, third))
	_print_runtime_evidence()
	print("EGT_CHEST_FATE_RENDER_OK output_dir=%s renderer=Godot 4.7.2 real-window" % _output_dir)
	get_tree().quit(0)


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _capture(stem: String) -> Image:
	var image := _vp.get_texture().get_image()
	if image == null:
		push_error("viewport texture 为空，拍照失败 stem=%s" % stem)
		get_tree().quit(1)
		return null
	var path := "%s/%s.png" % [_output_dir, stem]
	var error := image.save_png(path)
	if error != OK:
		push_error("保存 PNG 失败 err=%d path=%s" % [error, path])
		get_tree().quit(1)
		return null
	var stats := _image_stats(image)
	print("IMAGE %s size=%dx%d non_background=%d mean=%.4f range=%.4f..%.4f path=%s" % [
		stem, image.get_width(), image.get_height(), stats["active"], stats["mean"], stats["min"], stats["max"], path,
	])
	return image


func _image_stats(image: Image) -> Dictionary:
	var min_luma := 10.0
	var max_luma := -10.0
	var sum := 0.0
	var active := 0
	var samples := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var color := image.get_pixel(x, y)
			var luma := (color.r + color.g + color.b) / 3.0
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
			sum += luma
			samples += 1
			if luma > 0.12:
				active += 1
	return {
		"min": min_luma,
		"max": max_luma,
		"mean": sum / float(maxi(samples, 1)),
		"active": active,
	}


func _image_difference(first: Image, second: Image) -> float:
	var total := 0.0
	var samples := 0
	for y in range(0, mini(first.get_height(), second.get_height()), 12):
		for x in range(0, mini(first.get_width(), second.get_width()), 12):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 1
	return total / float(maxi(samples * 3, 1))


func _print_projection_evidence(stage: String) -> void:
	for index in range(_chests.size()):
		_print_projection_bounds("chest_%d" % index, _chests[index], stage)
	for index in range(_cards.size()):
		_print_projection_bounds("fate_card_%d" % index, _cards[index], stage)


func _print_projection_bounds(label: String, root: Node3D, stage: String) -> void:
	var bounds := Rect2()
	var found := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_aabb := mesh_instance.mesh.get_aabb()
		for corner in range(8):
			var world_point := mesh_instance.global_transform * local_aabb.get_endpoint(corner)
			if _camera.is_position_behind(world_point):
				continue
			var screen_point := _camera.unproject_position(world_point)
			if not is_finite(screen_point.x) or not is_finite(screen_point.y):
				continue
			if not found:
				bounds = Rect2(screen_point, Vector2.ZERO)
				found = true
			else:
				bounds = bounds.expand(screen_point)
	if not found or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		print("PROJECTION %s stage=%s unavailable in_frame=false" % [label, stage])
		return
	var normalized := Rect2(bounds.position / Vector2(VIEW_W, VIEW_H), bounds.size / Vector2(VIEW_W, VIEW_H))
	var inside := normalized.position.x >= 0.05 and normalized.position.y >= 0.05 \
		and normalized.end.x <= 0.95 and normalized.end.y <= 0.95
	print("PROJECTION %s stage=%s bounds=(%.3f,%.3f)-(%.3f,%.3f) in_frame=%s" % [
		label, stage, normalized.position.x, normalized.position.y, normalized.end.x, normalized.end.y, str(inside),
	])


func _print_runtime_evidence() -> void:
	for index in range(_cards.size()):
		var card := _cards[index]
		var visual := card._visual
		var rotation := visual.rotation.y if visual != null else 0.0
		var hover_y := visual.position.y if visual != null else 0.0
		print("FATE_CARD_RUNTIME index=%d class=%s hover_y=%.4f rotation_y=%.4f speed_target=%.2f rad/s manual=%s shader=scan_TIME" % [
			index, card.get_class(), hover_y, rotation, CARD_ROTATION_SPEED, str(card.requires_manual_interaction()),
		])
	for index in range(_chests.size()):
		var chest := _chests[index]
		var prompt := chest.get_node_or_null("ChestPrompt") as Label3D
		print("CHEST_RUNTIME index=%d tier=%s quality=%s opened=%s phase=%s prompt_visible=%s prompt_text=%s" % [
			index, chest.chest_tier, chest.quality, str(chest.is_opened()), chest.get_chest_snapshot().get("open_phase_name", "?"),
			str(prompt != null and prompt.visible), prompt.text if prompt != null else "<none>",
		])
