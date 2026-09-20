extends Node
## 探针（只读）：直接加载 h12 上层围护 tscn，实测「东西南三面 17 块 v002 房间标准墙
## + 36 格 v002 房顶模块」到底装配成什么，并渲染两张验收图。
## 跑法：不带 --headless（要出图）。
##   Godot_console.exe --path . res://_scratch/task_house/probe_h12_house.tscn

const SCENE := "res://assets/art/environments/base_facility_3d/runtime/env_base100_upper_shell_30x30_h12/env_base100_upper_shell_30x30_h12_root_top3d.tscn"
const OUT_TOP := "res://outputs/verification/h12_house_roof_topdown.png"
const OUT_SIDE := "res://outputs/verification/h12_house_south_wall.png"
const OUT_ISO := "res://outputs/verification/h12_house_iso.png"
const PALETTE := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

## 期望：asset_id -> [件数, 声明包络]
const EXPECT := {
	"ENV-ROOFTOP-REF-ROOM-WALL": [17, Vector3(5, 11.9, 0.3)],
	"ENV-ROOFTOP-REF-ROOF-CORNER": [4, Vector3(5, 0.3, 5)],
	"ENV-ROOFTOP-REF-ROOF-EDGE": [16, Vector3(5, 0.3, 5)],
	"ENV-ROOFTOP-REF-ROOF-FULL": [16, Vector3(5, 0.3, 5)],
}

var _counts := {}
var _rots := {}
var _aabb_fail: Array[String] = []
var _palette_ok := 0
var _palette_bad := 0
var _palette_none := 0
var _first_world_min := {}
var _first_world_max := {}


func _ready() -> void:
	VerificationOutput.prepare()
	var packed := load(SCENE) as PackedScene
	if packed == null:
		print("H12_PROBE_FAIL: 场景加载失败 %s" % SCENE)
		get_tree().quit(1)
		return
	var shell := packed.instantiate() as Node3D
	add_child(shell)
	for _i in range(4):
		await get_tree().process_frame

	var wall_group := shell.get_node_or_null("100层围护墙_可移动旋转") as Node3D
	var roof_group := shell.get_node_or_null("24米封顶_6x6地砖") as Node3D
	print("H12_PROBE_SENTINEL wall_children=%d roof_children=%d" % [
		wall_group.get_child_count() if wall_group != null else -1,
		roof_group.get_child_count() if roof_group != null else -1,
	])
	if wall_group == null or roof_group == null:
		print("H12_PROBE_FAIL: 缺少 100层围护墙_可移动旋转 / 24米封顶_6x6地砖")
		get_tree().quit(1)
		return

	_scan(shell)

	print("\n=== 逐 AssetID 计数（期望） ===")
	var keys := _counts.keys()
	keys.sort()
	for k in keys:
		var want := int((EXPECT.get(k, [0, Vector3.ZERO]) as Array)[0])
		var flag := "OK " if int(_counts[k]) == want else "!! "
		print("  %s%-34s %d  (期望 %d)" % [flag, k, _counts[k], want])

	print("\n=== 逐 AssetID 出现的 rotation_y（去重，度） ===")
	for k in keys:
		var degs: Array = []
		for rad in (_rots[k] as Dictionary).keys():
			degs.append(snappedf(rad_to_deg(rad), 0.01))
		degs.sort()
		print("  %-34s %s" % [k, str(degs)])

	print("\n=== 首个实例的世界包络（核对原点契约与层位） ===")
	for k in keys:
		print("  %-34s min=%s max=%s" % [k, str(_first_world_min[k]), str(_first_world_max[k])])

	print("\n=== 色盘 ===")
	print("  palette_bound=%d  palette_wrong=%d  no_material=%d" % [
		_palette_ok, _palette_bad, _palette_none,
	])

	print("\n=== 包络不符项 ===")
	if _aabb_fail.is_empty():
		print("  (无)")
	for line in _aabb_fail:
		print("  %s" % line)

	# ---- 渲染 ----
	var dir := DirectionalLight3D.new()
	dir.light_energy = 2.0
	dir.light_color = Color("ffffff")
	dir.rotation_degrees = Vector3(-62.0, -28.0, 0.0)
	add_child(dir)
	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202428")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dfe8f0")
	environment.ambient_light_energy = 1.5
	environment.fog_enabled = false
	world_env.environment = environment
	add_child(world_env)

	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.current = true
	add_child(camera)

	# 1) 正上方俯视：房顶 6×6 网格（角板/边板/完整板）应铺满 30×30。
	camera.global_position = Vector3(0.0, 44.0, 0.001)
	camera.look_at(Vector3(0.0, 24.0, 0.0), Vector3.UP)
	for _f in range(10):
		await get_tree().process_frame
	_save(OUT_TOP)

	# 2) 南墙外侧正立面：v002 房间标准墙的装饰面应朝外。
	camera.global_position = Vector3(0.0, 12.0, 42.0)
	camera.look_at(Vector3(0.0, 11.0, 15.0), Vector3.UP)
	for _f in range(10):
		await get_tree().process_frame
	_save(OUT_SIDE)

	# 3) 东南上方等轴：同时看南墙、东墙（含门洞槽）与封顶收口。
	camera.global_position = Vector3(46.0, 34.0, 46.0)
	camera.look_at(Vector3(0.0, 14.0, 0.0), Vector3.UP)
	for _f in range(10):
		await get_tree().process_frame
	_save(OUT_ISO)

	print("\nH12_HOUSE_PROBE_OK")
	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		print("H12_PROBE_WARN: 截图失败 %s" % path)
	else:
		print("  saved %s" % path)


func _scan(node: Node) -> void:
	for child in node.get_children():
		_scan(child)
	var asset_id := str(node.get_meta("asset_id", ""))
	if not EXPECT.has(asset_id):
		return
	_counts[asset_id] = int(_counts.get(asset_id, 0)) + 1
	var node_3d := node as Node3D
	if node_3d == null:
		return
	var by_rot: Dictionary = _rots.get(asset_id, {})
	by_rot[snappedf(node_3d.rotation.y, 1e-5)] = true
	_rots[asset_id] = by_rot

	for mesh_value in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			if material == null:
				_palette_none += 1
			elif (
				material.albedo_texture != null
				and str(material.albedo_texture.resource_path) == PALETTE
			):
				_palette_ok += 1
			else:
				_palette_bad += 1
		# 用「轴对齐局部包络」核对声明尺寸（不做旋转展开，故只用于单面墙/单块板）
		var local_aabb := mesh_instance.mesh.get_aabb()
		var want_size: Vector3 = (EXPECT[asset_id] as Array)[1]
		var got := local_aabb.size
		if (
			not is_equal_approx(got.x, want_size.x)
			or not is_equal_approx(got.y, want_size.y)
			or not is_equal_approx(got.z, want_size.z)
		):
			# 旋转 90° 的墙/边板会把 XZ 互换，两向都接受
			var swapped := Vector3(want_size.z, want_size.y, want_size.x)
			if (
				not is_equal_approx(got.x, swapped.x)
				or not is_equal_approx(got.y, swapped.y)
				or not is_equal_approx(got.z, swapped.z)
			):
				_aabb_fail.append("%s %s 实测=%s 声明=%s" % [
					asset_id, node_3d.name, str(got), str(want_size),
				])
		if not _first_world_min.has(asset_id):
			var xform := mesh_instance.global_transform
			_first_world_min[asset_id] = xform * local_aabb.position
			_first_world_max[asset_id] = xform * local_aabb.end
