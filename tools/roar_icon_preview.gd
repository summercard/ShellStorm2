extends SceneTree
## 一次性工具：把 FX01-16 头顶吼叫图标按各怪物真实体型渲染成对比图，然后退出。
## 用法：godot --headless --path . -s tools/roar_icon_preview.gd -- <out.png>
##
## 目的：图标尺寸是**按体型算出来的**（MonsterStartupProfile.icon_edge_m），
##       光看代码常量看不出「小怪头上会不会太大」。这张图把 6 种体型并排渲染，
##       用游戏真实的近俯视机位看一遍。

const ROAR_SCENE: PackedScene = preload(
	"res://assets/art/vfx/combat_3d/vfx_monster_roar_icon_root_top3d.tscn"
)

## 用头顶血条宽度代表体型（= MonsterStartupProfile 的尺寸输入）。
const ROWS := [
	{"label": "exploder 1.15", "bar_w": 1.15, "bar_h": 0.14},
	{"label": "melee_chaser 1.38", "bar_w": 1.38, "bar_h": 0.15},
	{"label": "shielded 1.55", "bar_w": 1.55, "bar_h": 0.17},
	{"label": "fat_zombie03 1.80", "bar_w": 1.80, "bar_h": 0.18},
	{"label": "elite 2.05", "bar_w": 2.05, "bar_h": 0.20},
	{"label": "boss 2.65", "bar_w": 2.65, "bar_h": 0.24},
]

const COL_SPACING := 2.3
## 机位要同时框住「血条」和它上方的「图标」：相机再靠近一点，图标就被顶出画面外了
## （实测 CAM_HEIGHT 5.4 时整排图标全部出框）。这组值是有下界的，改前先看渲染结果。
const CAM_HEIGHT := 9.0
const CAM_BACK := 7.2
## 血条槽根离地高度。与 Enemy3D._position_overhead_health_bar 的口径一致
## （world_height + 0.58，因表现基准缩放为 1.0 故此处恒 0.58）。
## 图标偏移 icon_offset_y_m 是**相对槽根**量的，不是相对地面 —— 两者必须同源，
## 否则对照图会把图标画到血条里，看不出「图标坐在血条上方」。
const BAR_SLOT_ROOT_Y := 0.58


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "res://outputs/monster_roar_icon_preview.png"
	if args.size() >= 1:
		out_path = args[0]

	var world := Node3D.new()
	world.name = "PreviewWorld"
	root.add_child(world)
	# 必须等一帧：SceneTree 脚本里 add_child 之后节点尚未真正进树，
	# 此时写 global_position / activate() 会报 !is_inside_tree() 并把位置丢成原点。
	await process_frame

	# 地板：给图标一个可对照的尺度参照（1m 网格）
	_add_floor(world)

	var cam := Camera3D.new()
	cam.name = "PreviewCamera"
	# 游戏是「几乎俯视」的塔内机位，这里用相近的俯角
	cam.position = Vector3(0.0, CAM_HEIGHT, CAM_BACK)
	cam.rotation_degrees = Vector3(-52.0, 0.0, 0.0)
	cam.fov = 46.0
	cam.current = true
	world.add_child(cam)

	var key := DirectionalLight3D.new()
	key.name = "PreviewKey"
	key.rotation_degrees = Vector3(-58.0, -38.0, 0.0)
	key.light_energy = 1.35
	world.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "PreviewFill"
	fill.rotation_degrees = Vector3(-30.0, 150.0, 0.0)
	fill.light_energy = 0.55
	world.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.045, 0.05, 0.07, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.34, 0.40, 1.0)
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)

	var effects: Array[Node3D] = []
	var x0 := -float(ROWS.size() - 1) * 0.5 * COL_SPACING
	for i in range(ROWS.size()):
		var row: Dictionary = ROWS[i]
		var bar_w := float(row["bar_w"])
		var bar_h := float(row["bar_h"])
		var edge := MonsterStartupProfile.icon_edge_m(bar_w)
		var offset := MonsterStartupProfile.icon_offset_y_m(bar_w, bar_h)

		var origin := Vector3(x0 + float(i) * COL_SPACING, 0.0, 0.0)
		# 血条中心 = 槽根（图标偏移的基准点）
		_add_health_bar(world, origin + Vector3.UP * BAR_SLOT_ROOT_Y, bar_w, bar_h)

		var effect := ROAR_SCENE.instantiate() as Node3D
		world.add_child(effect)
		# 图标 = 槽根 + 偏移（与 MonsterStartupProfile.icon_offset_y_m 同一参考系）
		effect.global_position = origin + Vector3.UP * (BAR_SLOT_ROOT_Y + offset)
		# hold 必须给得极大：本工具用「等若干帧」来等渲染就绪，而帧数对应的真实耗时
		# 不可预测（headless 下可能几秒）。若 hold 只有几秒，特效会在截图前被基类的
		# _process 判到 lifetime 到期而 _retire() 隐藏 —— 表现为「有时有图标、有时没有」
		# 的间歇性空图。给足 hold 才能让「保持段、scale=1.0、不透明」这件事确定成立。
		effect.activate(
			effect.global_position,
			Color.WHITE,
			edge,
			{"hold_seconds": 600.0, "fade_seconds": 0.0}
		)
		effect._on_tick(0.30, effect.lifetime)
		effects.append(effect)
		var sp := effect.get_node_or_null("RoarIconSprite") as Sprite3D
		var screen_pos := Vector2(-1.0, -1.0)
		if sp != null:
			screen_pos = cam.unproject_position(sp.global_position)
		print(			"[roar_preview] %-22s edge=%.3fm offset=%.3fm sprite=%s tex=%s vis=%s scale=%.3f gpos=%s screen=%s"
			% [
				String(row["label"]), edge, offset,
				"yes" if sp != null else "NO",
				"yes" if (sp != null and sp.texture != null) else "NO",
				"yes" if (sp != null and sp.is_visible_in_tree()) else "NO",
				sp.scale.x if sp != null else -1.0,
				str(sp.global_position) if sp != null else "n/a",
				str(screen_pos),
			]
		)

	for i in range(90):
		await process_frame

	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		printerr("[roar_preview] no image")
		quit(2)
		return
	var resolved := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(resolved)
	if err != OK:
		printerr("[roar_preview] save_png err=%d -> %s" % [err, resolved])
		quit(3)
		return
	print("[roar_preview] saved -> %s" % resolved)
	quit(0)


## 头顶血条：只为对照图标「坐得比血条高、不遮血条」，与 Enemy3D 的同名表现同口径。
## `bar_center` 是血条中心的世界坐标（= 槽根），不是地面点。
func _add_health_bar(world: Node3D, bar_center: Vector3, bar_w: float, bar_h: float) -> void:
	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(bar_w, bar_h)
	bar.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.93, 0.055, 0.12, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar.material_override = mat
	bar.position = bar_center
	world.add_child(bar)


func _add_floor(world: Node3D) -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(26.0, 14.0)
	var floor_node := MeshInstance3D.new()
	floor_node.name = "PreviewFloor"
	floor_node.mesh = floor_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.20, 1.0)
	mat.roughness = 0.95
	floor_node.material_override = mat
	world.add_child(floor_node)
