extends Node
## 单块地砖近景：看「一块 5m 砖内部到底长什么样」。
##
## 用途：业主报「砖块密度太细」时，区分两种成因 ——
##   · 摆放间距错（应该 5m 一块，实际更密）→ 改 `ManorShellPlan.floor_plan()`
##   · 砖内贴图太碎（一张 5m 的面上跨了多格色盘）→ 改资产 UV
## 本工具拍单块砖、正交俯视、按尺寸满帧，砖内纹理的格数可直接数出来。
##
## 必须真实渲染：`godot --path . --scene res://tools/_exp03_floor_closeup.tscn`

const OUT_DIR := "res://outputs/expedition03_floor_closeup"
const FLOORS := {
	"stone": "res://assets/art/environments/tower_zones/expedition/runtime/common_components/manor_floor_stone/env_manor_floor_stone_root_top3d.tscn",
	"wood": "res://assets/art/environments/tower_zones/expedition/runtime/common_components/manor_floor_wood/env_manor_floor_wood_root_top3d.tscn",
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for key in FLOORS.keys():
		await _shoot(str(key), str(FLOORS[key]))
	# 再拍一张 2×2 拼接，看接缝与整体节奏
	await _shoot_tiled("stone_tiled2x2",
		str(FLOORS["stone"]), 2, 2)
	print("FLOORCLOSEUP_DONE")
	get_tree().quit(0)


func _shoot(label: String, prefab: String) -> void:
	var stage := Node3D.new()
	add_child(stage)
	var root := (load(prefab) as PackedScene).instantiate() as Node3D
	stage.add_child(root)
	_setup(stage)
	var cam := Camera3D.new()
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.6 * 1.4
	cam.position = Vector3(4.2, 5.0, 4.2)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	stage.add_child(cam)
	await _capture("%s_single.png" % label)
	print("CLOSEUP %-16s 单块 5m，正交满帧" % label)
	stage.queue_free()
	for _f in 3:
		await get_tree().process_frame


func _shoot_tiled(label: String, prefab: String, cols: int, rows: int) -> void:
	var stage := Node3D.new()
	add_child(stage)
	for r in range(rows):
		for c in range(cols):
			var root := (load(prefab) as PackedScene).instantiate() as Node3D
			root.position = Vector3((c - (cols - 1) * 0.5) * 5.0, 0.0, (r - (rows - 1) * 0.5) * 5.0)
			stage.add_child(root)
	_setup(stage)
	var cam := Camera3D.new()
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.0 * cols * 1.5
	# **斜视，不用纯顶视**：正交相机垂直向下拍水平面时实测整帧只有背景色
	# （mesh 在树里、AABB 正确、相机也对着，但一个像素都不出）。
	# 换成与 `_exp03_manor_shell_shots.gd` 同款的 45° 斜视就正常 —— 那套已验证。
	cam.position = Vector3(5.0 * cols * 0.55, 5.0 * cols * 0.7, 5.0 * rows * 0.55)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	stage.add_child(cam)
	# 诊断：确认实例真的进了树、有网格、且相机确实看着它。
	var mesh_count := 0
	var aabb := AABB()
	var first := true
	for node in stage.find_children("*", "MeshInstance3D", true, false):
		mesh_count += 1
		var mi := node as MeshInstance3D
		print("    mesh %-24s visible=%s in_tree=%s ovr=%s"
			% [str(mi.name), str(mi.visible), str(mi.is_visible_in_tree()),
				str(mi.material_override)])
		if mi.mesh != null:
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
	print("  DIAG stage=%s 子=%d mesh=%d aabb=(%s size=%s) cam_pos=%s far=%.0f"
		% [str(stage.name), stage.get_child_count(), mesh_count,
			str(aabb.position), str(aabb.size), str(cam.global_position), cam.far])
	await _capture("%s_tiled.png" % label)
	print("CLOSEUP %-16s %dx%d 拼接" % [label, cols, rows])
	stage.queue_free()
	for _f in 3:
		await get_tree().process_frame


func _setup(stage: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	# 背景故意用中性灰蓝：地板若没渲出来，一眼能看出是"空画面"而不是"很暗的砖"。
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.92, 0.94, 1.0)
	# 环境光给到 2.2：石材 albedo 实测很暗（p50≈16/255），按常规能量拍出来近乎全黑，
	# 分不清"没渲染"和"砖很暗"。这里只要看清色块边界，不追求画面氛围。
	e.ambient_light_energy = 2.2
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	# 与 `_exp03_manor_shell_shots.gd` 同一组角度（那套已验证能出图）。
	sun.rotation_degrees = Vector3(-58.0, -34.0, 0.0)
	sun.light_energy = 1.6
	stage.add_child(sun)


func _capture(file_name: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUT_DIR.path_join(file_name))
	if error != OK:
		push_error("保存失败 %s" % file_name)
