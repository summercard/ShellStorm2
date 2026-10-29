extends Node
## 宝箱外观实拍（2026-10-29）。
##
## 数据探针只能证明"箱子建出来、开了给东西"，证明不了**它看起来像不像宝箱、
## 品质读不读得出来**。这一张图就是给"玩家在门口能不能分辨值不值得花钥匙"做目视取证。
##
## 出图：outputs/verification/egt_treasure_chest.png
##
## ⚠ **必须不加 `--headless`**：headless 下 SubViewport 没有可读的渲染目标，
## `get_texture().get_image()` 返回 null，脚本会打 "viewport texture 为空" 后退出 1。
## 正确命令：`godot --path . --scene res://tools/_egt_chest_render.tscn`
## （同 `_egt_variant_render` / `_minimap_render`，凡是真渲染的探针都不能 headless。）
## 因此它**不进 CI 门禁**，只是需要人眼确认时的取证工具。

const OUT_DIR := "res://outputs/verification"
## 正交相机**纵向**可见高。横向可见宽 = `ORTHO_SIZE × 宽高比`，
## 所以排布宽度要靠这两个常量一起算 —— 第一版取 1.65（只想着"装下一个 1.02m 高的箱子"），
## 横向只覆盖 6.8m，而 6 只箱子占 9.75m，直接裁掉了两边各一只（2026-10-29 出图）。
## 现取 2.9：横向 2.9 × (1400/380) ≈ 10.7m，刚好容下排布 9.75m + 余量。
const ORTHO_SIZE := 2.9
const VIEW_W := 1400
const VIEW_H := 300
## 相机从**前上方俯视 26°**。第一版是正对（rotation 全 0），结果只看到箱子的正面投影 ——
## 盖子、箱口、内部发光面全被箱体自己挡住，"开了没开"在图上完全读不出来。
## 开箱必须能看见"盖子上翻 + 箱口透光"，所以必须有一个俯角。
## ⚠ 用 `look_at` 对准箱子中心，**不能用固定俯角**：
## 相机在 (0, 3.0, 9) 时若只写 `rotation_degrees.x = -26`，视线在 z=0 处已经落到 y≈-1.4，
## 而箱子在 y≈0.5 —— 正交相机的纵向半高只有 1.5m，于是整幅图全黑（2026-10-29 第二次出图）。
## 俯角必须由「相机点 − 目标点」算出来，不能凭感觉填。
const CAM_POSITION := Vector3(0.0, 3.0, 9.0)
const CAM_TARGET := Vector3(0.0, 0.52, 0.0)
const SPACING := 1.95

## 一列一个箱子：品质 × 开/未开。开箱状态是这张图要回答的一半问题，
## 所以 common 出现两次（关 / 开）—— 只看"开过的箱子"无法判断开箱动画是否做对了终态。
const LINEUP := [
	{"quality": "common", "opened": false},
	{"quality": "common", "opened": true},
	{"quality": "uncommon", "opened": false},
	{"quality": "rare", "opened": false},
	{"quality": "epic", "opened": false},
	{"quality": "epic", "opened": true},
]

var _vp: SubViewport
var _frames := 0
var _saved := ""


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
	e.background_color = Color(0.045, 0.055, 0.075)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.64, 0.74)
	e.ambient_light_energy = 1.10
	env.environment = e
	_vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.30
	key.rotation_degrees = Vector3(-36, -30, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.50
	fill.rotation_degrees = Vector3(-14, 148, 0)
	_vp.add_child(fill)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ORTHO_SIZE
	# `look_at()` 要求节点已在树内，所以先 add_child 再对准。
	# （`look_at_from_position()` 可以在树外用，但那样还得自己算 up —— 没必要。）
	_vp.add_child(cam)
	cam.look_at_from_position(CAM_POSITION, CAM_TARGET, Vector3.UP)
	cam.current = true

	# 地面：没有它箱子会"浮"在暗背景里，看不出贴地关系。
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(13.0, 2.6)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.10, 0.11, 0.13)
	ground_material.roughness = 0.95
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.01, 0.0)
	_vp.add_child(ground)

	var start_x := -SPACING * float(LINEUP.size() - 1) * 0.5
	for index in range(LINEUP.size()):
		var item := LINEUP[index] as Dictionary
		var chest := TreasureChest3D.new()
		chest.configure({"id": "lineup_%02d" % index, "quality": item["quality"]})
		chest.position = Vector3(start_x + SPACING * float(index), 0.0, 0.0)
		_vp.add_child(chest)
		# `_ready()` 在 add_child 时同步跑完（会建视觉），所以可以直接落终态。
		if bool(item["opened"]):
			chest.restore_opened_state(true)
		# 提示牌是交互态表现（32 号字的 [E] 文案），在近距取景下会盖住箱体本身。
		# 这张图要回答的是"箱子长什么样、开没开"，所以把它藏掉。
		chest.get_node("ChestPrompt").visible = false

	# 品质标签：图注只是为了人眼对照，不参与任何运行时判定。
	for index in range(LINEUP.size()):
		var item := LINEUP[index] as Dictionary
		var label := Label3D.new()
		# 分两行：一行写品质、一行写开合状态。挤在一行会被相邻标签吃掉
		# （第一版就是 "common · 已开" 和右边那格的文字撞在一起）。
		label.text = "%s\n%s" % [
			str(item["quality"]), "已开" if bool(item["opened"]) else "未开",
		]
		label.font_size = 26
		label.pixel_size = 0.0072
		label.outline_size = 0
		label.modulate = Color(0.86, 0.90, 0.96)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# 摆在箱前一格（z 更大 = 更靠近相机），俯视下自然落在箱子下方。
		label.position = Vector3(start_x + SPACING * float(index), 0.30, 1.35)
		_vp.add_child(label)

	# 内部发光面在开箱后才可见 —— 关着的箱子不该透光。这里靠 `restore_opened_state()`
	# 打开 `_glow`，所以"common 已开"那一格应该能看到箱口的暖光。


func _process(_delta: float) -> void:
	_frames += 1
	# 给 10 帧稳定：材质与灯光需要几帧才收敛（同 `_egt_variant_render` 的口径）。
	if _frames != 10:
		return
	var img := _vp.get_texture().get_image()
	if img == null:
		push_error("viewport texture 为空，拍照失败")
		get_tree().quit(1)
		return
	_saved = ProjectSettings.globalize_path("%s/egt_treasure_chest.png" % OUT_DIR)
	var err := img.save_png(_saved)
	if err != OK:
		push_error("保存 PNG 失败 err=%d path=%s" % [err, _saved])
		get_tree().quit(1)
		return
	print("EGT_CHEST_RENDER_OK %s" % _saved)
	get_tree().quit(0)
