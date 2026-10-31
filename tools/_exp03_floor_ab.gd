extends Node
## 地板贴图密度 A/B/C 对照：证明「细格子」来自 UV 跨度，不是摆放间距。
##
## 三组用**同一块** 5m 地砖、同一机位：
##   A 原样           —— 现状（业主截图里那种密集细纹）
##   B UV 归一        —— 把 UV 跨度拉到约 1 个色盘格，看「一格铺满 5m」是什么样
##   C 线性过滤       —— 不改 UV，只把 Nearest 换成 Linear，看锯齿是不是主因
##
## 必须真实渲染：`godot --path . --scene res://tools/_exp03_floor_ab.tscn`

const OUT_DIR := "res://outputs/expedition03_floor_ab"
const STONE := "res://assets/art/environments/tower_zones/expedition/runtime/common_components/manor_floor_stone/env_manor_floor_stone_root_top3d.tscn"
const WOOD := "res://assets/art/environments/tower_zones/expedition/runtime/common_components/manor_floor_wood/env_manor_floor_wood_root_top3d.tscn"

## 实测 UV 跨度（`_exp03_floor_texel_probe` 量得）：
##   石 u=0.7442 v=0.2442   ⇒ 一格 5m 面跨 7.4×2.4 个色盘格
##   木 u=0.1455 v=0.1477   ⇒ 只跨 0.15×0.15 格（把极小一片色盘放大铺满 5m）
const UV_SPAN := {
	"stone": Vector2(0.7442, 0.2442),
	"wood": Vector2(0.1455, 0.1477),
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for key in ["stone", "wood"]:
		var prefab := STONE if key == "stone" else WOOD
		await _variant(str(key), prefab, "A_origin", 1.0, BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		await _variant(str(key), prefab, "B_uv_norm", _norm_scale(str(key)), BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		await _variant(str(key), prefab, "C_linear", 1.0, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	print("FLOOR_AB_DONE")
	get_tree().quit(0)


func _norm_scale(key: String) -> float:
	# 让 UV 跨度等于 1 格：scale = 1.0 / 当前最大跨度。
	var span: Vector2 = UV_SPAN[key]
	return 1.0 / maxf(span.x, span.y)


func _variant(key: String, prefab: String, tag: String, uv_scale: float, filter: int) -> void:
	var stage := Node3D.new()
	add_child(stage)
	# 铺 3x3 = 15m，能看出砖与砖之间的接缝节奏
	for r in range(3):
		for c in range(3):
			var root := (load(prefab) as PackedScene).instantiate() as Node3D
			root.position = Vector3((c - 1) * 5.0, 0.0, (r - 1) * 5.0)
			stage.add_child(root)
			for node in root.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				if mi.mesh == null:
					continue
				for s in range(mi.mesh.get_surface_count()):
					var base := mi.mesh.surface_get_material(s) as BaseMaterial3D
					if base == null:
						continue
					var copy := base.duplicate() as BaseMaterial3D
					copy.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
					copy.texture_filter = filter
					mi.set_surface_override_material(s, copy)
	_setup(stage)
	var cam := Camera3D.new()
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# **必须先 add_child 再设 position/look_at**。
	# 不在树里调 `look_at()` 时基向量算不出正交基（相机正对 +UP 的退化方向），
	# 结果整帧只有背景色 —— 实测踩过两次：mesh 在树里、AABB 正确、相机参数看起来
	# 也对，但一个像素都不出。`_exp03_manor_shell_shots.gd` 是先加后设，所以它正常。
	stage.add_child(cam)
	cam.size = 17.0
	cam.position = Vector3(9.0, 12.4, 9.0)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	await _capture("%s_%s.png" % [key, tag])
	print("AB %-6s %-12s uv1_scale=%.3f filter=%d" % [key, tag, uv_scale, filter])
	stage.queue_free()
	for _f in 3:
		await get_tree().process_frame


func _setup(stage: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.15, 0.19)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.95, 0.96, 1.0)
	# 地表 albedo 很暗（石 p50≈16/255），环境光要给足才看得清图案。
	e.ambient_light_energy = 2.6
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -34.0, 0.0)
	sun.light_energy = 1.4
	stage.add_child(sun)


func _capture(file_name: String) -> void:
	for _i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.save_png(OUT_DIR.path_join(file_name)) != OK:
		push_error("保存失败 %s" % file_name)
