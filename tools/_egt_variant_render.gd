extends Node

## 开发期真实渲染：把 12 只远征03 复刻怪按族拍成四行，供人工目视核对族内区分度。
##   godot --path <project> --scene res://tools/_egt_variant_render.tscn
## ⚠ 必须 `--scene` 而非 `--script`：要实例化 Enemy3D，它依赖 autoload（MonsterAIManager 等），
##   而 `--script` 模式**不加载 autoload**，会直接 `Identifier not found` 编译失败。
##
## 输出：outputs/verification/egt_variant_lineup.png（四族各一行，由 Python 拼合）
##      中间产物：outputs/verification/_egt_row_<族名>.png
##
## ⚠ 本工具**不做断言**。断言在 `_egt_variant_visual_probe`（数据层）里。
## 这里只回答一个数据答不了的问题：**摆在一起，人眼能不能一眼分开？**
## 因为「体型 0.86 与 0.94 在数据上是"不同"的，但在屏幕上可能看不出差别」——
## 那正是需要出图才能发现的问题。
##
## ## 为什么一族一图、再拼起来（而不是一张图里排四行）
## 试过两次都在布局上翻车（2026-10-29 实测）：
##   ① 透视相机 + 沿 Z 排四行 → 后排被透视压缩，几乎与前排重叠，完全看不懂；
##   ② 正交相机 + 沿 Z 排四行 → 行距拉开后，**前排的标签仍压在后排怪身上**。
## 根因是「多行 + 单一相机」必然产生遮挡。一族一图后：
##   相机永远正对单行、正交投影、无倾斜 ⇒ 完全没有遮挡，且每只怪都能拍得足够大。
## 拼合交给 Python（PIL），比在引擎里堆 4 套布局简单得多。
##
## ## 文字为什么不用 Label3D，而交给 Python 画
## 试过 Label3D，两种摆法都不行（2026-10-29 实测）：
##   ① 放怪脚下（y≈0）→ 直接压在怪身上，挡住脚和附肢；
##   ② 放地面以下（y=-0.75）→ 正交视锥外，被裁掉，图上一个字都没有。
## 根因：正交相机的可见范围是死区间，3D 文字要么进画面就压怪、要么出画面就消失。
## 交给 Python 后文字在 2D 画布上排，位置完全可控，且中文字体渲染比 Label3D 稳定。

const OUT_DIR := "res://outputs/verification"

const LAYOUT := [
	{
		"family": "远程族",
		"rule": "体型阶梯 + 染色 = 弹色",
		"members": [
			"egt_bullet_kin", "egt_bandana_kin", "egt_veteran_kin",
			"egt_red_shotgun", "egt_blue_shotgun",
		],
	},
	{
		"family": "分裂族",
		"rule": "纯体型阶梯（刻意同色）",
		"members": ["egt_blobulin", "egt_blobuloid", "egt_blobulon"],
	},
	{
		"family": "爆炸族",
		"rule": "体型 + 色温",
		"members": ["egt_bullat", "egt_nitra", "egt_pinhead"],
	},
	{
		"family": "辅助族",
		"rule": "放大 + 高亮",
		"members": ["egt_gunsinger"],
	},
]

const COL_GAP := 2.55
## 纵向世界尺寸。第一版给 4.6，结果上下各留一大片黑、怪只占中间一小块（2026-10-29 出图）。
## 收紧到 3.2：刚好容下最高的 gunsinger(约 2.3m) + 头顶血条(约 1.95m) + 地面标签。
const ORTHO_SIZE := 3.5
const VIEW_W := 1500
const VIEW_H := 430
const CAM_Y := 1.15

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
## 当前正在显示（即将被拍）的行号。**必须从 0 起** —— 初版写成 -1 想靠"自增后再取"，
## 结果 GDScript 的负索引把 `LAYOUT[-1]` 解析成**最后一族**，辅助族被拍两次、顺序全乱
## （2026-10-29 实测：日志顺序 辅助→远程→分裂→爆炸→辅助，count=5）。
var _row := 0
var _frames := 0
var _saved: Array[String] = []
## 每行成员的**世界 x**（构建时记下）与**屏幕 x**（拍照帧算出），都按行号索引。
##
## 为什么必须实测、且必须在拍照帧算（2026-10-29 出图连踩两次）：
##   ① 让拼合脚本按"画布宽 ÷ 成员数"硬算 → 每行图注横向偏移最多近 200px，文字跑到两只怪中间。
##      根因是正交相机横向可见宽 = ORTHO_SIZE × 宽高比，与世界坐标均分不是同一套换算。
##   ② 改成在 `_build_row()` 里调 `unproject_position()` → 全部图注挤在 x≈0。
##      根因是新建节点当帧相机矩阵尚未解析，`unproject_position` 返回零值。
## 现在：构建只记世界 x；拍照那一帧（相机早已解析）再投影。屏幕坐标只有一个真源 —— 相机本身。
var _row_world_x: Array[float] = []
var _row_kinds: Array[String] = []
var _row_screen_x: Dictionary = {}     # row_index -> { kind: screen_x_px }


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
	e.ambient_light_color = Color(0.58, 0.62, 0.72)
	e.ambient_light_energy = 1.05
	env.environment = e
	_vp.add_child(env)

	# 两盏方向光：单光会让模块化外壳与 GLB 的体积感消失
	var key := DirectionalLight3D.new()
	key.light_energy = 1.35
	key.rotation_degrees = Vector3(-38, -32, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-15, 150, 0)
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ORTHO_SIZE
	# 正对、无倾斜：这是"无遮挡"的前提，见文件头说明
	_cam.position = Vector3(0.0, CAM_Y, 12.0)
	_cam.rotation_degrees = Vector3.ZERO
	_vp.add_child(_cam)
	_cam.current = true

	_build_row(0)


func _build_row(index: int) -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	_world = Node3D.new()
	_vp.add_child(_world)

	var members: Array = LAYOUT[index]["members"]
	_row_world_x.clear()
	_row_kinds.clear()

	# 地面：给每只怪一个可见落脚点，否则读不出体型相对什么
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 14)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.10, 0.12, 0.16)
	gm.roughness = 1.0
	ground.material_override = gm
	_world.add_child(ground)

	for i in range(members.size()):
		var kind := str(members[i])
		var x := (float(i) - (float(members.size()) - 1.0) * 0.5) * COL_GAP
		var enemy := Enemy3D.new()
		var avatar := EnemyAvatar3D.new()
		avatar.name = "Avatar"
		enemy.add_child(avatar)
		_world.add_child(enemy)
		enemy.apply_profile(kind)
		enemy.position = Vector3(x, 0.0, 0.0)
		# 稍侧一个角度：露出钳子 / 轨道球这些附肢，正面拍会看不出形状
		enemy.rotation_degrees = Vector3(0, 20, 0)
		# 冻结 AI：本工具只拍照，不需要它走动或攻击
		enemy.set_physics_process(false)
		enemy.set_process(false)
		_hide_overhead_bar(enemy)
		# 只记世界 x；屏幕 x 留到拍照帧算（见 `_row_screen_x` 注释）
		_row_world_x.append(x)
		_row_kinds.append(kind)
		# 不建 Label3D：文字交给 Python 拼合时画（见文件头「为什么」）


## 隐藏头顶血条。
##
## ## 为什么必须隐藏（这是第一版出图才发现的）
## 血条是**世界尺寸**的 billboard（`_position_overhead_health_bar()` 里显式
## `scale = Vector3.ONE`，刻意不随怪体缩放），且条上带一个光照状态小图标。
## 在正交近景对照图里，它的视觉权重会盖过怪本身：
##   ① 比怪体还宽还高，直接挡住脸和附肢 —— 而这图要看的就是轮廓；
##   ② 那个图标在这点像素下糊成一串看不懂的字形，反而成了噪声。
## 血条宽度这一维由 Python 在拼合时写进图注，不需要靠画面表达。
func _hide_overhead_bar(enemy: Enemy3D) -> void:
	var bar := enemy.get_node_or_null("OverheadHealthBar") as Node3D
	if bar != null:
		bar.visible = false


func _process(_delta: float) -> void:
	_frames += 1
	# 每行给 8 帧稳定（材质、灯光、GLB 导入缓存）
	if _frames % 8 != 0:
		return
	if _row >= LAYOUT.size():
		return

	# 先按**当前行号**取族名与文件，再决定下一步 —— 顺序反了就会拍错行。
	var family := str(LAYOUT[_row]["family"])
	var img := _vp.get_texture().get_image()
	if img == null:
		push_error("viewport texture 为空，拍照失败")
		get_tree().quit(1)
		return
	var path := ProjectSettings.globalize_path("%s/_egt_row_%s.png" % [OUT_DIR, family])
	var err := img.save_png(path)
	if err != OK:
		push_error("保存 PNG 失败 err=%d path=%s" % [err, path])
		get_tree().quit(1)
		return
	_saved.append(path)
	# 在**这一帧**投影：相机矩阵此时已解析
	var screen_map := {}
	for i in range(_row_kinds.size()):
		var p := _cam.unproject_position(Vector3(_row_world_x[i], 1.2, 0.0))
		screen_map[_row_kinds[i]] = p.x
	_row_screen_x[_row] = screen_map
	print("EGT_ROW_SAVED %s %s" % [family, path])

	_row += 1
	if _row >= LAYOUT.size():
		_finish()
		return
	_build_row(_row)


## 把每一行的族名、规则、成员及其视觉参数写成 JSON。
##
## 为什么由 GDScript 出这份数据、而不是 Python 自己再写一遍：
## 体型 / 颜色 / 血条宽度的**唯一真源**在 `Enemy3D` 与 `EnemyAvatar3D` 的常量表里。
## 让 Python 复制一份等于制造第二个真源，改了一边就会对不上 ——
## 那时图注会写着旧数字，而游戏里已经是新的，且没有任何东西会报错。
func _write_manifest() -> String:
	var rows: Array = []
	for row_index in range(LAYOUT.size()):
		var entry: Dictionary = LAYOUT[row_index]
		var screen_map: Dictionary = _row_screen_x.get(row_index, {})
		var members: Array = []
		for kind in entry["members"]:
			var k := str(kind)
			var asset_kind := EnemyAvatar3D.resolve_asset_kind(k)
			var uses_formal := EnemyAvatar3D.FORMAL_NORMAL_SCENES.has(asset_kind)
			var tint: Color = EnemyAvatar3D.FORMAL_MODEL_TINT.get(k, Color.WHITE)
			# 外壳色必须**回退到借用基类**，不能回退成白色。
			# `COLORS` 里只登记了"与基类不同色"的那几只；pinhead 刻意沿用 `exploder` 的橙。
			# 第一版写 `COLORS.get(k, Color(1,1,1))`，出图后 pinhead 的图注显示 #FFFFFF ——
			# 与玩家实际看到的橙色不符，图注直接变成假数据（2026-10-29 踩过）。
			var shell: Color = EnemyAvatar3D.COLORS.get(
				k, EnemyAvatar3D.COLORS.get(asset_kind, Color.WHITE)
			)
			var visible := tint if uses_formal else shell
			members.append({
				"kind": k,
				"screen_x": float(screen_map.get(k, 0.0)),
				"body_scale": float(Enemy3D.BODY_SCALE_BY_KIND[k]),
				"world_scale": float(Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER) * float(Enemy3D.BODY_SCALE_BY_KIND[k]),
				# 世界高（米）—— 与玩家 1.8m 可直接比。图注用它而不是 `world_scale`：
				# `world_scale` 是"根节点缩放"（0.7~1.9），写成「世界 0.75」会被读成 0.75 **米**，
				# 而那只怪实际 1.22m。2026-10-30 出图时这个标注就有歧义。
				"world_height": float(
					EnemyAvatar3D.get_footprint_profile(k).get("height", 1.2)
				) * (float(Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER) * float(Enemy3D.BODY_SCALE_BY_KIND[k])),
				"hp": int(Enemy3D.PROFILES[k]["hp"]),
				"bar_width": (Enemy3D.HEALTH_BAR_SIZE_BY_KIND.get(k, Vector2.ZERO) as Vector2).x,
				"uses_formal": uses_formal,
				"tinted": EnemyAvatar3D.FORMAL_MODEL_TINT.has(k),
				"color": _color_hex(visible),
			})
		rows.append({"family": str(entry["family"]), "rule": str(entry["rule"]), "members": members})

	var path := ProjectSettings.globalize_path("%s/_egt_variant_rows.json" % OUT_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("写清单失败: %s" % path)
		return ""
	f.store_string(JSON.stringify({"rows": rows}, "  "))
	f.close()
	return path


static func _color_hex(c: Color) -> String:
	return "#%02X%02X%02X" % [
		int(round(clampf(c.r, 0.0, 1.0) * 255.0)),
		int(round(clampf(c.g, 0.0, 1.0) * 255.0)),
		int(round(clampf(c.b, 0.0, 1.0) * 255.0)),
	]


func _finish() -> void:
	print("EGT_VARIANT_ROWS_DONE count=%d" % _saved.size())
	var manifest := _write_manifest()
	if not manifest.is_empty():
		print("EGT_VARIANT_MANIFEST %s" % manifest)
	print("EGT_VARIANT_ROWS_DIR %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)
