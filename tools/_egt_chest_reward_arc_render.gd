extends Node
## 宝箱奖励「箱口 -> 外围」空间弧线真实渲染取证。
## 使用正式 GroundLootPickup3D / FateCardDropPickup3D 和 begin_spawn_animation(chest_arc)，
## 只把固定合法落点用于画面构图；生产落点合法性仍由 Dungeon3D 专项验收负责。
## 所有产物写入工程外 CHEST_FATE_RENDER_DIR，不写入 res://outputs。

const VIEW_W := 1280
const VIEW_H := 720
const ORTHO_SIZE := 8.2
const CAM_POSITION := Vector3(0.0, 7.0, 11.5)
const CAM_TARGET := Vector3(0.0, 0.95, 0.0)
const WARMUP_FRAMES := 18
const CAPTION_COLOR := Color(0.82, 0.90, 1.0)

const DROP_LAYOUT := [
	{"id": "item_health_potion", "label": "治疗剂", "position": Vector3(-2.65, 0.0, 0.35), "color": Color(0.30, 0.92, 0.52)},
	{"id": "item_room_key", "label": "房间钥匙", "position": Vector3(-1.35, 0.0, 2.45), "color": Color(1.0, 0.72, 0.16)},
	{"id": "item_battery_l", "label": "大电池", "position": Vector3(1.35, 0.0, 2.35), "color": Color(0.30, 0.72, 1.0)},
	{"id": "item_fate_card_drop", "label": "命运卡", "position": Vector3(2.72, 0.0, 0.18), "color": Color(0.72, 0.34, 1.0), "fate": true},
	{"id": "__currency__", "label": "金币", "position": Vector3(0.45, 0.0, -2.72), "color": Color(1.0, 0.72, 0.12), "currency": true},
]

var _vp: SubViewport
var _camera: Camera3D
var _output_dir := ""
var _chest: TreasureChest3D
var _pickups: Array[GroundLootPickup3D] = []
var _caption: Label3D


func _ready() -> void:
	process_priority = 100000
	_output_dir = OS.get_environment("CHEST_FATE_RENDER_DIR").strip_edges()
	if _output_dir.is_empty() or not _output_dir.is_absolute_path():
		push_error("CHEST_FATE_RENDER_DIR 必填且必须是绝对路径")
		get_tree().quit(2)
		return
	_output_dir = _output_dir.trim_suffix("/").trim_suffix("\\")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	print("CHEST_REWARD_ARC_RENDER_DIR=%s" % _output_dir)
	_build_view()
	_build_chest()
	_build_reward_pickups()
	_hide_runtime_labels()
	_run_capture()


func _build_view() -> void:
	_vp = SubViewport.new()
	_vp.name = "ChestRewardArcEvidenceViewport"
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.025, 0.048)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.64, 0.88)
	environment.ambient_light_energy = 1.20
	environment.glow_enabled = true
	environment.glow_intensity = 1.0
	environment.glow_strength = 1.15
	environment.glow_bloom = 0.12
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_hdr_threshold = 0.85
	environment_node.environment = environment
	_vp.add_child(environment_node)

	var key := DirectionalLight3D.new()
	key.name = "ArcEvidenceKeyLight"
	key.light_energy = 1.55
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "ArcEvidenceFillLight"
	fill.light_energy = 0.70
	fill.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	_vp.add_child(fill)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(13.0, 13.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.075, 0.095, 0.14)
	ground_material.roughness = 0.92
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.name = "ArcEvidenceGround"
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.01, 0.0)
	_vp.add_child(ground)

	_camera = Camera3D.new()
	_camera.name = "ArcEvidenceCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ORTHO_SIZE
	_vp.add_child(_camera)
	_camera.look_at_from_position(CAM_POSITION, CAM_TARGET, Vector3.UP)
	_camera.current = true

	_caption = Label3D.new()
	_caption.name = "ArcEvidenceCaption"
	_caption.text = "宝箱奖励：箱口 → 外围弧线 · 2.5m 峰值 · 1.35s"
	_caption.font_size = 30
	_caption.pixel_size = 0.009
	_caption.outline_size = 6
	_caption.modulate = CAPTION_COLOR
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.position = Vector3(0.0, 4.0, 0.0)
	_vp.add_child(_caption)


func _build_chest() -> void:
	_chest = TreasureChest3D.new()
	_chest.name = "ArcEvidenceChest"
	_chest.configure({
		"id": "arc_evidence_chest",
		"quality": "rare",
		"chest_tier": "advanced",
	})
	_chest.position = Vector3.ZERO
	_vp.add_child(_chest)
	_chest.remove_from_group("interaction_provider_3d")
	_chest.remove_from_group("interaction_providers_3d")
	_chest.commit_opened()
	for child in _chest.find_children("*", "", true, false):
		if child is MeshInstance3D and str(child.name).to_lower().begins_with("questionmark"):
			(child as MeshInstance3D).visible = false
	for label_node in _chest.find_children("*", "Label3D", true, false):
		(label_node as Label3D).visible = false


func _build_reward_pickups() -> void:
	var burst_origin := Vector3(0.0, 0.40, 0.0)
	for index in range(DROP_LAYOUT.size()):
		var layout := DROP_LAYOUT[index] as Dictionary
		var item_id := str(layout["id"])
		var item: Dictionary
		if bool(layout.get("fate", false)):
			item = {
				"type": "fate_pickup",
				"id": "item_fate_card_drop",
				"fate_pickup_id": "arc_render_fate_%d" % index,
				"card_source": "chest_arc_render_evidence",
			}
		elif bool(layout.get("currency", false)):
			item = {"id": "__currency__", "name": "金币", "is_currency": true, "count": 30}
		else:
			item = (ItemRegistry.get_instance().get_item(item_id) as Dictionary).duplicate(true)
		var pickup: GroundLootPickup3D
		if bool(layout.get("fate", false)):
			pickup = FateCardDropPickup3D.new()
		else:
			pickup = GroundLootPickup3D.new()
		pickup.name = "ArcReward_%02d_%s" % [index, item_id]
		pickup.configure(item, layout["color"] as Color)
		pickup.position = layout["position"] as Vector3
		_vp.add_child(pickup)
		for label_node in pickup.find_children("*", "Label3D", true, false):
			(label_node as Label3D).visible = false
		pickup.begin_spawn_animation({
			"mode": "chest_arc",
			"origin": burst_origin,
			"roll_vector": Vector3(1.10 + float(index) * 0.08, 0.56, 0.70 + float(index) * 0.05),
		})
		_pickups.append(pickup)


func _hide_runtime_labels() -> void:
	_hide_runtime_node(_vp)
	if _caption != null:
		_caption.visible = true


func _hide_runtime_node(node: Node) -> void:
	if node is Label3D and node != _caption:
		(node as Label3D).visible = false
	for child in node.get_children():
		_hide_runtime_node(child)


func _run_capture() -> void:
	for _frame in range(WARMUP_FRAMES):
		await get_tree().process_frame
	_capture("egt_chest_reward_arc_launch")
	await get_tree().create_timer(GroundLootPickup3D.CHEST_SPAWN_DURATION_S * 0.44, false).timeout
	await get_tree().process_frame
	_capture("egt_chest_reward_arc_apex")
	await get_tree().create_timer(GroundLootPickup3D.CHEST_SPAWN_DURATION_S * 0.60, false).timeout
	await get_tree().process_frame
	_capture("egt_chest_reward_arc_settled")
	_print_runtime_evidence()
	print("EGT_CHEST_REWARD_ARC_RENDER_OK output_dir=%s renderer=Godot 4.7.2 real-window" % _output_dir)
	get_tree().quit(0)


func _capture(stem: String) -> void:
	var image := _vp.get_texture().get_image()
	if image == null:
		push_error("宝箱奖励弧线 viewport 为空：%s" % stem)
		get_tree().quit(1)
		return
	var path := "%s/%s.png" % [_output_dir, stem]
	var error := image.save_png(path)
	if error != OK:
		push_error("保存宝箱奖励弧线 PNG 失败 err=%d path=%s" % [error, path])
		get_tree().quit(1)
		return
	print("IMAGE %s size=%dx%d path=%s" % [stem, image.get_width(), image.get_height(), path])


func _print_runtime_evidence() -> void:
	for index in range(_pickups.size()):
		var pickup := _pickups[index]
		var snapshot := pickup.get_model_snapshot()
		var visual_position := snapshot.get("visual_world_position", Vector3.ZERO) as Vector3
		print("ARC_REWARD index=%d item=%s root=(%.2f,%.2f,%.2f) visual=(%.2f,%.2f,%.2f) spawn_mode=%s animating=%s unlocked=%s" % [
			index,
			str(snapshot.get("item_id", "")),
			pickup.global_position.x, pickup.global_position.y, pickup.global_position.z,
			visual_position.x, visual_position.y, visual_position.z,
			str(snapshot.get("spawn_mode", "")),
			str(snapshot.get("spawn_animating", false)),
			str(snapshot.get("pickup_unlocked", false)),
		])
