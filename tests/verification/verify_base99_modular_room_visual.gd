extends Node
## 基地99层九件模块整体布置的明亮验收视图；只用于可视回归，不参与玩法。

const OUTPUT := "res://outputs/verification/base99_modular_room_integration.png"
const UPPER_SHELL_OUTPUT := "res://outputs/verification/base100_upper_shell_roof_integration.png"
const MEZZANINE_EDGE_OUTPUT := "res://outputs/verification/base99_mezzanine_v003_edge_closeup.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null:
		push_error("BASE99_VISUAL_FAIL: facility missing")
		get_tree().quit(1)
		return
	facility.ensure_detail_built()
	for canvas_value in tower.find_children("*", "CanvasLayer", true, false):
		(canvas_value as CanvasLayer).visible = false

	var fill := DirectionalLight3D.new()
	fill.name = "Base99AcceptanceFill"
	fill.light_energy = 2.2
	fill.light_color = Color("d9efff")
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	add_child(fill)

	var camera := Camera3D.new()
	camera.name = "Base99AcceptanceCamera"
	camera.current = true
	camera.fov = 68.0
	add_child(camera)
	# 从房间南侧内部朝北拍摄，正面覆盖L梯、7米楼板和外门小楼梯。
	camera.global_position = facility.global_position + Vector3(-8.0, 5.2, 12.5)
	camera.look_at(facility.global_position + Vector3(2.0, 4.0, -8.0), Vector3.UP)
	for _frame in range(12):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(OUTPUT) != OK:
		push_error("BASE99_VISUAL_FAIL: cannot save preview")
		get_tree().quit(1)
		return
	# 从南侧近距离同时验收平台外缘和下方横向门板；机位覆盖原闪面发生区域。
	camera.global_position = facility.global_position + Vector3(1.5, 7.4, 2.0)
	camera.look_at(facility.global_position + Vector3(5.0, 4.0, -6.8), Vector3.UP)
	for _frame in range(8):
		await get_tree().process_frame
	var mezzanine_edge_image := get_viewport().get_texture().get_image()
	if (
		mezzanine_edge_image == null
		or mezzanine_edge_image.is_empty()
		or mezzanine_edge_image.save_png(MEZZANINE_EDGE_OUTPUT) != OK
	):
		push_error("BASE99_VISUAL_FAIL: cannot save mezzanine edge closeup")
		get_tree().quit(1)
		return
	# 从东南上方验证18米封顶和两层围护；这是独立验收图，不改变玩法相机。
	camera.global_position = facility.global_position + Vector3(0.0, 25.0, -32.0)
	camera.look_at(facility.global_position + Vector3(0.0, 10.0, 0.0), Vector3.UP)
	for _frame in range(8):
		await get_tree().process_frame
	var upper_shell_image := get_viewport().get_texture().get_image()
	if (
		upper_shell_image == null
		or upper_shell_image.is_empty()
		or upper_shell_image.save_png(UPPER_SHELL_OUTPUT) != OK
	):
		push_error("BASE100_VISUAL_FAIL: cannot save upper shell/roof preview")
		get_tree().quit(1)
		return
	print("BASE99_MODULAR_ROOM_VISUAL_OK: interior, mezzanine v003 edge and upper-shell roof previews saved")
	get_tree().quit(0)
