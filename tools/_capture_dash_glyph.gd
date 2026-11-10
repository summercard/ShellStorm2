extends Node
## 抓「兔子翻滚」某一帧的白色剪影（一次性工具，2026-11-10）。
##
## 目的：主人要求把翻滚冷却环的图形换成「兔子翻滚的其中一帧的白色剪影」。
## 剪影必须来自**真实角色在真实 dashing 姿态下的那一帧**，不能用通用人形图标代替。
##
## ## 做法
## 1. 起真实 `Dungeon3D`（`test_mode`），让玩家真的开始一次冲刺；
## 2. 逐物理帧读 `avatar._dash_animation_progress`，到目标相位就地停住角色的 `_process`
##    —— 停的是**表现层**，玩法状态机已经不再被这个脚本推进，所以姿态会定格；
## 3. 只把 avatar 子树的 `layers` 抬到第 2 层、相机 `cull_mask = 2` ⇒ 场景其它几何全不被画；
## 4. `WorldEnvironment.environment = null` + 默认清屏色改黑 ⇒ 背景纯黑，非黑像素就是角色；
## 5. 所有网格换白色 unshaded `material_override` ⇒ 不管原材质是彩色还是带 shader，出来都是纯白；
## 6. 等 `frame_post_draw` 截图，裁到内容包围盒，按内容高度归一化到 96 px。
##
## ## 为什么不用 SubViewport
## 角色挂在 `player` 下，reparent 进 SubViewport 会破坏物理与状态机引用。
## 改 `cull_mask` + 清屏色是**不搬节点**就能拿到纯背景的唯一办法。
##
## 输出（工程内 `outputs/verification/`，只作人工比对，不进游戏资源）：
##   `dash_glyph_p<NN>.png` —— 各相位的黑底白剪影
##   `dash_glyph_mask_p<NN>.txt` —— 同一张的 96×96 掩码（`#` = 有角色），
##                                供下一步转成 GDScript 多边形常量

const SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const OUT_DIR := "res://outputs/verification"
## 要试的相位。dashing 时 `visual_root.rotation.x = smoothstep(0,1,p) * TAU`，
## 所以 p ≈ 0.25 是转了 90°（侧翻）、p ≈ 0.5 是一半（基本翻完一圈的上半段）。
const PHASES: Array[float] = [
	0.02, 0.06, 0.10, 0.14, 0.18, 0.22, 0.26, 0.30,
	0.34, 0.38, 0.42, 0.46, 0.50, 0.54, 0.58, 0.62, 0.66, 0.70,
]
## 剪影归一化到的高度（像素）。HUD 上实际显示约 42 px；96 是给轮廓提取留的余量 ——
## 描边工具会先 3× 放大再二值化，所以原图分辨率越高，矢量化后的拐点越贴真实边缘。
const MASK_SIZE := 128
## 相机正交高度（米）。角色约 1.5 m，翻滚时横向最宽约 1.4 m。
## 取 1.9 ⇒ 剪影占到画面绝大部分，边缘像素更多。
const CAMERA_SIZE := 1.9


func _ready() -> void:
	var dungeon := SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 10:
		await get_tree().process_frame
	dungeon.force_enter_room_for_test("main_01")
	for _frame in 4:
		await get_tree().process_frame

	var player := dungeon.player
	var avatar := player.avatar
	# 换个开阔点：房间中央，避免角色贴着墙导致正交相机的 near plane 切到几何。
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.rotation = Vector3.ZERO
	for _frame in 2:
		await get_tree().process_frame

	# —— 只留角色可被渲染 ——
	var layer_mask := 1 << 1  # 第 2 位
	var avatar_meshes: Array[MeshInstance3D] = []
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		# 手上的枪不属于"兔子剪影"：带枪的轮廓读不出翻滚。
		if str(mesh.name).to_lower().contains("weapon"):
			mesh.layers = 0
			continue
		mesh.layers = layer_mask
		avatar_meshes.append(mesh)
	print("CAPTURE_DASH_GLYPH_MESHES count=%d" % avatar_meshes.size())

	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	white.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mesh in avatar_meshes:
		mesh.material_override = white

	# 背景压成纯黑：去掉环境（天空/雾/环境光）+ 清屏色改黑，非黑像素 = 角色。
	dungeon.world_environment.environment = null
	RenderingServer.set_default_clear_color(Color.BLACK)
	# HUD 与所有覆盖层一起关掉，否则血条/小地图会被当成"角色像素"。
	for child in dungeon.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.cull_mask = layer_mask
	camera.current = true
	dungeon.add_child(camera)
	# 从 +X 侧看：角色默认朝 -Z，`visual_root.rotation.x` 的翻滚在 YZ 平面内，
	# 沿 -X 看能把"翻跟头"完整看全。
	camera.global_position = Vector3(6.0, 0.9, 0.0)
	camera.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)

	# 只停表现层：姿态由本脚本按相位直接钉住，玩法状态机不参与。
	avatar.set_process(false)
	for phase in PHASES:
		await _capture_phase(dungeon, player, avatar, phase)
	get_tree().quit(0)


## 让角色摆出 `target_phase` 那一帧的翻滚姿态，然后出图。
##
## ⚠️ **不能靠"真冲刺一次再冻住"**：冲刺只有 0.204 s，而动画周期是 0.265 s，
## 状态机在 progress ≈ 0.77 就退回 idle —— `rotation.x` 被 `_update_state_motion`
## 末尾那句 `else 0.0` 清掉，而 `_dash_animation_progress` 还停在旧值。
## 于是"冻在 0.37"截出来的是**一只站着的兔子**（首版就是这么错的）。
## 这里直接把表现态钉成 dashing，再按皮肤姿态函数收敛，最后按生产代码同一条公式写旋转。
func _capture_phase(dungeon: Dungeon3D, player: Player3D, avatar: Node, target_phase: float) -> void:
	avatar.set("_state", "dashing")
	avatar.set("_dash_animation_progress", target_phase)
	# 收敛姿态：每轮先把进度压回目标相位，再让 `_update_state_motion` 里的 lerp 走一步。
	# 不重置的话那个函数自己会把进度往前推，收敛完就偏了。
	for _step in 40:
		avatar.set("_dash_animation_progress", target_phase)
		avatar.call("_update_state_motion", 0.05)
	# 旋转按生产代码**同一条公式**写（`smoothstep(0,1,p) * TAU`）：不再调一次姿态函数，
	# 否则它会把进度又推一格。
	var visual_root := avatar.get("visual_root") as Node3D
	visual_root.rotation.x = smoothstep(0.0, 1.0, target_phase) * TAU
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("CAPTURE_DASH_GLYPH_FAIL null_image p=%.2f" % target_phase)
		return
	image.convert(Image.FORMAT_RGBA8)
	var cropped := _crop_to_content(image)
	if cropped == null:
		print("CAPTURE_DASH_GLYPH_FAIL empty p=%.2f" % target_phase)
		return
	var normalized := _normalize(cropped, MASK_SIZE)
	var tag := int(round(target_phase * 100.0))
	var png_path := "%s/dash_glyph_p%02d.png" % [OUT_DIR, tag]
	normalized.save_png(png_path)
	var mask_path := "%s/dash_glyph_mask_p%02d.txt" % [OUT_DIR, tag]
	_write_mask(normalized, mask_path)
	print(
		"CAPTURE_DASH_GLYPH_SHOT p=%.3f tag=%d crop=%dx%d roll_deg=%.1f"
		% [
			target_phase, tag, cropped.get_width(), cropped.get_height(),
			rad_to_deg(visual_root.rotation.x),
		]
	)


## 裁到"非黑像素"的包围盒。阈值取 8/255：抗锯齿边缘与 TAA 抖动都低于它。
func _crop_to_content(image: Image) -> Image:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) * 255.0 > 8.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return null
	return image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))


## 等比缩放到高 `target`、居中放进 `target × target` 的正方形画布（黑底）。
func _normalize(image: Image, target: int) -> Image:
	var scale := float(target) / float(maxi(1, image.get_height()))
	var width := maxi(1, int(round(float(image.get_width()) * scale)))
	var resized := image.duplicate() as Image
	resized.resize(width, target, Image.INTERPOLATE_BILINEAR)
	var canvas := Image.create(target, target, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.BLACK)
	var offset_x := maxi(0, (target - width) / 2)
	if width > target:
		# 宽于画布：按宽再缩一次，避免裁掉耳朵。
		var fit := float(target) / float(width)
		resized.resize(target, maxi(1, int(round(float(target) * fit))), Image.INTERPOLATE_BILINEAR)
		canvas.fill(Color.BLACK)
		canvas.blit_rect(resized, Rect2i(0, 0, resized.get_width(), resized.get_height()), Vector2i(0, maxi(0, (target - resized.get_height()) / 2)))
		return canvas
	canvas.blit_rect(resized, Rect2i(0, 0, width, target), Vector2i(offset_x, 0))
	return canvas


func _write_mask(image: Image, path: String) -> void:
	var lines := PackedStringArray()
	for y in image.get_height():
		var row := ""
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			row += "#" if maxf(color.r, maxf(color.g, color.b)) > 0.35 else "."
		lines.append(row)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
