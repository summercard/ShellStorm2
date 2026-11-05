extends Node
## 宝箱开箱**动画序列**实拍（2026-11-05）。
##
## 数据探针能证明"掉落要等砰"，证明不了**看起来是不是那个过程**：
## 抖两下够不够明显、蓄力有没有"按住"的对比、砰那一下有没有劲。
## 这张 6 格图就是给业主那句「点击之后宝箱会抖两下，然后箱子砰的一下打开」做目视取证。
##
## 出图：`outputs/verification/egt_chest_open_sequence.png`（横向 6 格，按时间从左到右）
## 单帧同时留在同目录 `egt_chest_open_sequence_0N.png`，便于放大看某一段。
##
## 采样点是动画时间轴的关键帧（与 `TreasureChest3D` 的常量同源）：
##   ① 抖动第一下  ② 抖动第二下反向  ③ 蓄力下压  ④ 砰（盖子过冲）  ⑤ 余韵  ⑥ 终态
##
## ⚠ **必须不加 `--headless`**：headless 下 SubViewport 没有可读的渲染目标，
## `get_texture().get_image()` 返回 null。正确命令：
## `godot --path . --scene res://tools/_egt_chest_open_sequence_render.tscn`
## 因此它不进 CI 门禁，只是需要人眼确认时的取证工具（同 `_egt_chest_render`）。

const OUT_DIR := "res://outputs/verification"
const VIEW_W := 760
const VIEW_H := 560
## 相机俯角 24°：正对只能看到箱体正面投影，盖子上翻与箱口透光全被自己挡住。
## `size` / `target` 是按**开盖后**的包围盒定的：盖子上翻 104° 后顶端到 y≈1.55m，
## 而箱子关着时只占 0~1.02m —— 按关着的箱子取景，第 4 格起盖子就会被裁掉（2026-11-05 首版就这样）。
const CAM_POSITION := Vector3(0.0, 2.6, 5.4)
const CAM_TARGET := Vector3(0.0, 0.66, 0.0)
const CAM_ORTHO_SIZE := 2.75

## 稳定帧数：材质与灯光要几帧才收敛（同 `_egt_chest_render` 的口径）。
const WARMUP_FRAMES := 12

var _vp: SubViewport
var _chest: TreasureChest3D
var _shots: Array[Image] = []

## 采样时刻（秒，相对按下 E）。取在每段**中段**，不是段边界 —— 边界处姿态还没走出来，
## 拍到的会是"上一段的尾巴"（实测按边界取样时，0.48s 那张还在抖动、0.62s 才进蓄力）。
##
## 抖动半周期 0.105s，峰值在 0.105（+）/ 0.210（−）/ 0.315（+）/ 0.420（−）：
## 取 0.09 与 0.20 各拍一次反向峰值 —— 这张图要证明的就是"抖了**两下**"，只拍一下证明不了。
## 蓄力 0.42~0.54（EASE_OUT，后半段姿态最满）⇒ 取 0.52；砰 0.59~0.73（含过冲）⇒ 取 0.64；
## 余韵到 0.95 ⇒ 取 0.82；终态取 1.20。
## 「砰」的时刻取自 `TreasureChest3D.OPEN_BURST_DELAY_SECONDS`（= 0.42 + 0.05 + 0.12），
## 不手写 —— 手写过一次，漏了回正的 0.05s，拍出来的"砰"其实是蓄力最后一帧。
const SHOT_TIMES := [0.09, 0.20, 0.52, 0.64, 0.82, 1.20]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_vp = SubViewport.new()
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.062, 0.075)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.78, 0.9)
	e.ambient_light_energy = 0.95
	env.environment = e
	_vp.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	_vp.add_child(sun)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(6.0, 6.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.16, 0.17, 0.19)
	ground_mat.roughness = 0.95
	ground_mesh.material = ground_mat
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.01, 0.0)
	_vp.add_child(ground)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_ORTHO_SIZE
	# ⚠ 必须先入树再 `look_at`：不在树里的 Node3D 没有全局变换，
	# 会报 `Node not inside tree. Use look_at_from_position() instead.` 且朝向不生效。
	_vp.add_child(cam)
	cam.position = CAM_POSITION
	cam.look_at(CAM_TARGET, Vector3.UP)
	cam.current = true

	_chest = TreasureChest3D.new()
	_chest.configure({"id": "sequence", "quality": "rare"})
	_vp.add_child(_chest)
	# 提示牌在近距取景下会盖住箱体本身；这张图回答的是"箱子怎么开的"。
	_chest.get_node("ChestPrompt").visible = false

	_run()


## 采样走协程 + **绝对时钟**（`Time.get_ticks_msec()`）。
## 不用 `_process` 里累加 delta：`_capture()` 的 `get_image()` 是同步阻塞，
## 每截一张就把后续采样点整体往后推（实测漂移 0.14s，蓄力段被拍成了抖动段）。
func _run() -> void:
	for _frame in range(WARMUP_FRAMES):
		await get_tree().process_frame
	var start_ms := Time.get_ticks_msec()
	_chest.commit_opened()
	for index in range(SHOT_TIMES.size()):
		var target_ms := start_ms + int(round(float(SHOT_TIMES[index]) * 1000.0))
		while Time.get_ticks_msec() < target_ms:
			await get_tree().process_frame
		_capture(index)
	_finish()


func _capture(shot_index: int) -> void:
	var img := _vp.get_texture().get_image()
	if img == null:
		push_error("viewport texture 为空，拍照失败")
		get_tree().quit(1)
		return
	var single := ProjectSettings.globalize_path(
		"%s/egt_chest_open_sequence_%02d.png" % [OUT_DIR, shot_index]
	)
	img.save_png(single)
	_shots.append(img)
	# 顺带把这一刻的实际变换打出来：出图是给人看的，数值是给下次改动画时对的。
	print(
		"SHOT %d plan=%.2fs phase=%s lid=%.1f° rot_z=%.2f° pos_y=%.3f scale_y=%.3f"
		% [
			shot_index, float(SHOT_TIMES[shot_index]),
			_chest.get_chest_snapshot().get("open_phase_name", "?"),
			rad_to_deg(_chest._lid_pivot.rotation.x) if _chest._lid_pivot != null else 0.0,
			rad_to_deg(_chest._visual_root.rotation.z) if _chest._visual_root != null else 0.0,
			_chest._visual_root.position.y if _chest._visual_root != null else 0.0,
			_chest._visual_root.scale.y if _chest._visual_root != null else 0.0,
		]
	)


## 六格横向拼成一张。`blit_rect` 要求同格式，所以整图按第一格格式建。
func _finish() -> void:
	if _shots.size() != SHOT_TIMES.size():
		push_error("采样帧数不足：%d/%d" % [_shots.size(), SHOT_TIMES.size()])
		get_tree().quit(1)
		return
	var first := _shots[0]
	var sheet := Image.create_empty(
		VIEW_W * _shots.size(), VIEW_H, false, first.get_format()
	)
	for index in range(_shots.size()):
		sheet.blit_rect(_shots[index], Rect2i(0, 0, VIEW_W, VIEW_H), Vector2i(VIEW_W * index, 0))
	var out := ProjectSettings.globalize_path("%s/egt_chest_open_sequence.png" % OUT_DIR)
	var err := sheet.save_png(out)
	if err != OK:
		push_error("保存拼图失败 err=%d path=%s" % [err, out])
		get_tree().quit(1)
		return
	print("EGT_CHEST_OPEN_SEQUENCE_RENDER_OK %s" % out)
	get_tree().quit(0)
