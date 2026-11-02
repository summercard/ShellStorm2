extends Node
## 开火反馈观感探针（2026-11-02）。
##
## 为什么需要它：业主两次反馈「没有看到变化」「是不是太快了」。这类问题 headless
## 断言抓不到 —— `punch` 数值确实变了，但枪在屏幕上只有十几像素，形变又只持续几十毫秒。
## 只有真渲染能量出「到底变了几像素、持续几帧」。
##
## 输出两段：
##   ① [实战相机] 客观数字：枪身屏幕长度、峰值缩短量、压扁持续帧数。不产图。
##   ② [近景相机] 6 帧拼图 `weapon_fire_feedback_preview.png`，供人眼复核形变**形状**。
##      ⚠ 近景是放大观察用的镜头，不代表实战尺度 —— 尺度一律看 ① 的数字。
##
## 运行：godot --path . --resolution 1920x1080 --scene res://tools/probe_weapon_fire_feedback.tscn

const PLAYER := preload("res://scenes/Player3D.tscn")

## 与 `scenes/Player3D.tscn` 的 Camera3D 逐字一致：位置、俯角、fov。
## 换相机就必须同步这里，否则探针看到的比例与实战不符 —— 那正是前面翻车的原因。
const GAME_CAMERA_POSITION := Vector3(0.0, 17.5, 13.0)
const GAME_CAMERA_PITCH := -0.907571
const GAME_CAMERA_FOV := 43.0

## 采样时刻（秒，相对开火）。手枪 punch_hz = 3.4 ⇒ 半周期 147 ms：
## 0.000 最扁 → 0.074 回正 → 0.147 拉长到顶 → 之后回正。
const SAMPLE_TIMES := [0.0, 0.03, 0.06, 0.09, 0.13, 0.20]

var _weapon: WeaponModel3D
var _camera: Camera3D
var _muzzle: Node3D


func _ready() -> void:
	VerificationOutput.prepare()
	var stage := Node3D.new()
	add_child(stage)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("141d22")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cfdfe6")
	environment.ambient_light_energy = 1.35
	world_environment.environment = environment
	stage.add_child(world_environment)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("3a5058")
	floor_material.roughness = 0.9
	plane.material = floor_material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -34, 0)
	key.light_energy = 1.7
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.2, 2.6, -1.6)
	fill.omni_range = 10.0
	fill.light_energy = 5.0
	fill.light_color = Color("ffe3c0")
	stage.add_child(fill)

	var player := PLAYER.instantiate() as Player3D
	stage.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.get_node("Camera3D").current = false
	await get_tree().process_frame
	await get_tree().process_frame
	player.aim_direction = Vector3(0, 0, -1)
	player.aim_yaw = 0.0
	player.avatar.visual_root.rotation.y = 0.0
	player.get_node("AimCursor").visible = false
	if not player.equip_weapon("bp_pistol", "mod_bullet_standard"):
		push_error("无法装备手枪，探针无法继续")
		get_tree().quit(1)
		return
	_weapon = player.weapon
	await get_tree().process_frame
	for _index in range(3):
		player.avatar.call("_process", 0.10)

	_muzzle = _weapon.find_child("MuzzleSocket", true, false) as Node3D
	if _muzzle == null:
		push_error("找不到 MuzzleSocket，无法度量枪身长度")
		get_tree().quit(1)
		return

	_camera = Camera3D.new()
	_camera.position = GAME_CAMERA_POSITION
	_camera.rotation = Vector3(GAME_CAMERA_PITCH, 0.0, 0.0)
	_camera.fov = GAME_CAMERA_FOV
	_camera.current = true
	stage.add_child(_camera)
	for node in get_tree().root.find_children("*", "Control", true, false):
		(node as Control).visible = false
	await get_tree().process_frame
	await get_tree().process_frame

	await _measure_under_game_camera()
	await _capture_closeup_sequence()
	get_tree().quit(0)


## 枪口 → 枪根 在屏幕上的像素距离。
func _barrel_pixels() -> float:
	return _camera.unproject_position(_muzzle.global_position).distance_to(
		_camera.unproject_position(_weapon.global_position)
	)


## ① 实战相机下的客观度量。只输出数字，不产图 —— 不受裁切坐标影响。
func _measure_under_game_camera() -> void:
	print("[实战相机] 位置=%s fov=%.0f 分辨率=%s" % [
		GAME_CAMERA_POSITION, GAME_CAMERA_FOV, str(get_viewport().get_visible_rect().size)
	])
	var rest_length := _barrel_pixels()
	_weapon.call("_apply_fire_feedback")
	_weapon.call("_process", 1.0 / 240.0)
	var peak := float(_weapon.get("_punch"))
	var peak_length := _barrel_pixels()
	print("  静息枪身屏幕长度 = %.1f px" % rest_length)
	print(
		"  压扁峰值 punch=%+.3f ⇒ %.1f px（变短 %.1f px = %.0f%%）"
		% [peak, peak_length, rest_length - peak_length, (peak_length / maxf(0.01, rest_length) - 1.0) * 100.0]
	)
	# 60 fps 下压扁阶段能占几帧：从峰值衰减到 10% 峰值所需时间。
	var frames_at_60 := 0
	var elapsed := 0.0
	var threshold := peak * 0.1
	while float(_weapon.get("_punch")) > threshold and elapsed < 1.0:
		_weapon.call("_process", 1.0 / 60.0)
		elapsed += 1.0 / 60.0
		frames_at_60 += 1
	print("  压扁衰减到峰值的 10%% 耗时 %.0f ms ≈ %d 帧 @60fps" % [elapsed * 1000.0, frames_at_60])
	_weapon.call("_reset_fire_feedback")


## ② 近景 6 帧。⚠ 放大观察用，不代表实战尺度。
func _capture_closeup_sequence() -> void:
	var gun_center := (_muzzle.global_position + _weapon.global_position) * 0.5
	_camera.position = gun_center + Vector3(0.30, 0.52, -0.92)
	_camera.look_at_from_position(_camera.position, gun_center, Vector3.UP)
	_camera.fov = 32.0
	_camera.current = true
	await get_tree().process_frame
	await get_tree().process_frame

	var frames: Array[Image] = []
	# 先推一帧再开火：`_visual_root.scale` 只在 `_process` 里写，不推的话 t=0 那一帧
	# 取到的是上一发残留的缩放，画面与报出来的 `punch` 对不上。
	_weapon.call("_process", 1.0 / 240.0)
	_weapon.call("_apply_fire_feedback")
	_weapon.call("_process", 1.0 / 240.0)
	var elapsed := 1.0 / 240.0
	for index in range(SAMPLE_TIMES.size()):
		var target: float = SAMPLE_TIMES[index]
		while elapsed < target - 0.0001:
			var step := minf(1.0 / 120.0, target - elapsed)
			_weapon.call("_process", step)
			elapsed += step
		await get_tree().process_frame
		await get_tree().process_frame
		var frame := _grab_full_downscaled()
		if frame == null:
			push_error("第 %d 帧取图失败" % index)
			return
		var visual_scale: Vector3 = _weapon.get("_visual_root").scale
		print("  [近景] t=%.3fs punch=%+.3f scale=(%.2f, %.2f, %.2f)" % [
			target, float(_weapon.get("_punch")), visual_scale.x, visual_scale.y, visual_scale.z
		])
		frames.append(frame)

	var sheet := _compose_sheet(frames)
	var output := VerificationOutput.path("weapon_fire_feedback_preview.png")
	if sheet.save_png(output) != OK:
		push_error("无法保存观感探针拼图：%s" % output)
		return
	print("FIRE_FEEDBACK_PREVIEW_OK: %s" % output)


## 取整帧再缩一半：不依赖任何投影坐标，杜绝裁切错位。
func _grab_full_downscaled() -> Image:
	var viewport_image := get_viewport().get_texture().get_image()
	if viewport_image == null or viewport_image.is_empty():
		return null
	var image := viewport_image.duplicate() as Image
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


## 3 列拼图。单元格尺寸直接取第一帧的实际尺寸，不写死。
func _compose_sheet(frames: Array[Image]) -> Image:
	if frames.is_empty():
		return Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var columns := 3
	var rows := int(ceil(float(frames.size()) / float(columns)))
	var cell := Vector2i(frames[0].get_width(), frames[0].get_height())
	var sheet := Image.create(cell.x * columns, cell.y * rows, false, Image.FORMAT_RGBA8)
	for index in range(frames.size()):
		var origin := Vector2i((index % columns) * cell.x, int(index / columns) * cell.y)
		sheet.blit_rect(frames[index], Rect2i(Vector2i.ZERO, cell), origin)
	return sheet
