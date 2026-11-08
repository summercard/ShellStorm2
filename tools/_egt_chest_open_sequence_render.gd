extends Node
## 宝箱开箱动画序列真实渲染取证。
## 六只真实 TreasureChest3D 同帧错峰启动，在同一真实窗口帧分别处于：
## 抖动一、抖动二、蓄力、爆点、余韵、终态；所有产物写入 CHEST_FATE_RENDER_DIR。

const VIEW_W := 1800
const VIEW_H := 500
const PANEL_W := 300
const CAM_POSITION := Vector3(0.0, 2.9, 8.4)
const CAM_TARGET := Vector3(0.0, 0.72, 0.0)
const CAM_ORTHO_SIZE := 4.0
const WARMUP_FRAMES := 15
const CAPTURE_AT_SECONDS := 2.0
const SHOT_TIMES := [0.09, 0.20, 0.52, 0.64, 0.82, 1.20]
const PHASE_LABELS := ["抖动一", "抖动二", "蓄力", "爆点", "余韵", "终态"]

var _vp: SubViewport
var _chests: Array[TreasureChest3D] = []
var _output_dir := ""


func _process(_delta: float) -> void:
	_hide_runtime_labels_except_captions()


func _ready() -> void:
	# 在正式交互控制器之后执行，避免它每帧重新打开 InteractionDot3D。
	process_priority = 100000
	_output_dir = OS.get_environment("CHEST_FATE_RENDER_DIR").strip_edges()
	if _output_dir.is_empty() or not _output_dir.is_absolute_path():
		push_error("CHEST_FATE_RENDER_DIR 必填且必须为绝对路径；拒绝写入工程内默认出口")
		get_tree().quit(2)
		return
	_output_dir = _output_dir.trim_suffix("/").trim_suffix("\\")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	print("CHEST_FATE_RENDER_DIR=%s" % _output_dir)
	_build_view()
	_build_chests()
	_hide_runtime_labels_except_captions()
	_run()


func _build_view() -> void:
	_vp = SubViewport.new()
	_vp.name = "ChestOpenSequenceViewport"
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.045, 0.070)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.70, 0.76, 0.90)
	environment.ambient_light_energy = 1.05
	env.environment = environment
	_vp.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 34.0, 0.0)
	sun.light_energy = 1.40
	sun.shadow_enabled = true
	_vp.add_child(sun)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(15.0, 5.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.14, 0.16, 0.21)
	ground_material.roughness = 0.95
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.name = "SequenceGround"
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.01, 0.0)
	_vp.add_child(ground)

	var camera := Camera3D.new()
	camera.name = "SequenceCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAM_ORTHO_SIZE
	_vp.add_child(camera)
	camera.look_at_from_position(CAM_POSITION, CAM_TARGET, Vector3.UP)
	camera.current = true


func _build_chests() -> void:
	var start_x := -2.5 * 2.1
	for index in range(SHOT_TIMES.size()):
		var chest := TreasureChest3D.new()
		chest.name = "SequenceChest_%02d" % index
		chest.configure({"id": "sequence_%02d" % index, "quality": "common", "chest_tier": "advanced"})
		chest.position = Vector3(start_x + float(index) * 2.1, 0.0, 0.0)
		_vp.add_child(chest)
		chest.remove_from_group("interaction_provider_3d")
		chest.remove_from_group("interaction_providers_3d")
		for label_node in chest.find_children("*", "Label3D", true, false):
			(label_node as Label3D).visible = false
		_chests.append(chest)
		_add_caption(PHASE_LABELS[index], chest.position + Vector3(0.0, 1.68, 0.34))


func _hide_runtime_labels_except_captions() -> void:
	_hide_runtime_node(_vp)


func _hide_runtime_node(node: Node) -> void:
	if node is Label3D and not node.is_in_group("chest_open_sequence_caption"):
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


func _add_caption(text: String, position: Vector3) -> void:
	var label := Label3D.new()
	label.add_to_group("chest_open_sequence_caption")
	label.text = text
	label.font_size = 28
	label.pixel_size = 0.009
	label.outline_size = 6
	label.modulate = Color(0.88, 0.93, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position
	_vp.add_child(label)


## 采用绝对时钟，先把六只箱子错峰启动，再只截一帧。
## 这样保存图片不会把后续样本推迟，六格不会全部落在同一动画阶段。
func _run() -> void:
	for _frame in WARMUP_FRAMES:
		await get_tree().process_frame
	var start_ms := Time.get_ticks_msec()
	# 目标启动时间从晚到早；每个箱子 commit 后都独立运行，
	# 到统一 capture_ms 时，箱龄正好分别是 SHOT_TIMES[index]。
	for index in range(SHOT_TIMES.size() - 1, -1, -1):
		var target_ms := start_ms + int(round((CAPTURE_AT_SECONDS - float(SHOT_TIMES[index])) * 1000.0))
		while Time.get_ticks_msec() < target_ms:
			await get_tree().process_frame
		_chests[index].commit_opened()
	var capture_ms := start_ms + int(round(CAPTURE_AT_SECONDS * 1000.0))
	while Time.get_ticks_msec() < capture_ms:
		await get_tree().process_frame
	_capture_sequence()
	get_tree().quit(0)


func _capture_sequence() -> void:
	var image := _vp.get_texture().get_image()
	if image == null:
		push_error("viewport texture 为空，开箱序列拍照失败")
		get_tree().quit(1)
		return
	var sheet_path := "%s/egt_chest_open_sequence.png" % _output_dir
	var sheet_error := image.save_png(sheet_path)
	if sheet_error != OK:
		push_error("保存开箱序列拼图失败 err=%d path=%s" % [sheet_error, sheet_path])
		get_tree().quit(1)
		return
	for index in range(_chests.size()):
		var region := image.get_region(Rect2i(index * PANEL_W, 0, PANEL_W, VIEW_H))
		var single_path := "%s/egt_chest_open_sequence_%02d.png" % [_output_dir, index]
		var error := region.save_png(single_path)
		if error != OK:
			push_error("保存开箱单帧失败 err=%d path=%s" % [error, single_path])
			get_tree().quit(1)
			return
		_print_shot(index, single_path)
	print("IMAGE egt_chest_open_sequence size=%dx%d non_empty=true path=%s" % [image.get_width(), image.get_height(), sheet_path])
	print("EGT_CHEST_OPEN_SEQUENCE_RENDER_OK %s" % sheet_path)


func _print_shot(index: int, path: String) -> void:
	var chest := _chests[index]
	var snapshot := chest.get_chest_snapshot()
	print(
		"SHOT %d plan=%.2fs phase=%s lid=%.1f° rot_z=%.2f° pos_y=%.3f scale_y=%.3f path=%s"
		% [
			index, float(SHOT_TIMES[index]), snapshot.get("open_phase_name", "?"),
			rad_to_deg(chest._lid_pivot.rotation.x) if chest._lid_pivot != null else 0.0,
			rad_to_deg(chest._visual_root.rotation.z) if chest._visual_root != null else 0.0,
			chest._visual_root.position.y if chest._visual_root != null else 0.0,
			chest._visual_root.scale.y if chest._visual_root != null else 0.0,
			path,
		]
	)
