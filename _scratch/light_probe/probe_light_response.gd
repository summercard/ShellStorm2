extends Node
## 实拍 A/B：证明办公室/桥房房型组件是否响应灯光，并验证材质修正后的效果。
##
## 场景只有一盏平行光，环境光为 0。逐对象在 3 档光强下各拍一张，
## 对比「原材质」与「把金属度降到通用件水平」两种状态。
## 背景纯黑 ⇒ 图像平均亮度 ≈ 该物件对灯光的响应。

const OUT_DIR := "I:/ss2_iso/light_probe"
const ENERGIES := [0.0, 1.0, 3.0]

const CASES := [
	{
		"tag": "01_办公室墙_原材质",
		"path": "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/office_room/wall_t615_5m/wall_t615_5m_root_top3d.tscn",
		"metallic": -1.0,
	},
	{
		"tag": "02_办公室墙_金属度改0.03",
		"path": "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/office_room/wall_t615_5m/wall_t615_5m_root_top3d.tscn",
		"metallic": 0.03,
	},
	{
		"tag": "03_通用实墙_参照",
		"path": "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn",
		"metallic": -1.0,
	},
]

var _camera: Camera3D
var _sun: DirectionalLight3D
var _holder: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup()
	for case_value in CASES:
		var spec := case_value as Dictionary
		await _shoot_case(spec)
	print("PROBE_LIGHT_RESPONSE_DONE")
	get_tree().quit(0)


func _setup() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.name = "ProbeWorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "ProbeSun"
	# 固定斜射：灯不正对墙面。金属（低粗糙度）此时只剩一小块高光、大面积无漫反射，
	# 哑光面则整面受光 —— 这才是房间里真实灯具的入射条件。
	_sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	_sun.light_energy = 0.0
	_sun.shadow_enabled = false
	add_child(_sun)

	_camera = Camera3D.new()
	_camera.name = "ProbeCamera"
	_camera.fov = 45.0
	_camera.near = 0.05
	_camera.far = 400.0
	add_child(_camera)

	_holder = Node3D.new()
	_holder.name = "ProbeHolder"
	add_child(_holder)


func _shoot_case(spec: Dictionary) -> void:
	var tag := str(spec["tag"])
	var path := str(spec["path"])
	var metallic := float(spec["metallic"])
	var packed := load(path) as PackedScene
	if packed == null:
		print("!! %s 加载失败" % tag)
		return
	var instance := packed.instantiate() as Node3D
	_holder.add_child(instance)
	await get_tree().process_frame

	var aabb := _world_aabb(instance)
	var center := aabb.get_center()
	var size := aabb.size
	var min_axis := 0
	if size.y < size[min_axis]:
		min_axis = 1
	if size.z < size[min_axis]:
		min_axis = 2
	var normal_dir := Vector3.ZERO
	normal_dir[min_axis] = 1.0
	var dist := maxf(maxf(size.x, size.y), size.z) * 1.7

	print("-- %s aabb=%s 薄轴=%d 相机距=%.1f" % [
		tag, str(size), min_axis, dist,
	])
	_camera.position = center + normal_dir * dist
	_camera.look_at(center, Vector3.UP)

	if metallic >= 0.0:
		var touched := _force_metallic(instance, metallic)
		print("   已改写金属度 %.2f（影响 %d 个网格）" % [metallic, touched])
	_report_normals(instance)

	for energy_value in ENERGIES:
		_sun.light_energy = float(energy_value)
		await _capture("%s_光强%.0f" % [tag, float(energy_value)])

	_holder.remove_child(instance)
	instance.free()


## 把整棵子树的材质复制一份并把金属度压到目标值（不改资产，只改本实例）。
func _force_metallic(root: Node, metallic: float) -> int:
	var touched := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var source := mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var copy := source.duplicate() as BaseMaterial3D
			copy.metallic = metallic
			copy.metallic_specular = 0.5
			mesh_instance.set_surface_override_material(surface, copy)
			touched += 1
	return touched


## 法线朝向自检：薄轴方向上，法线应与「从中心指向顶点」同号（朝外）。
func _report_normals(root: Node) -> void:
	var total := 0
	var outward := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			if normals.is_empty():
				continue
			var box := _local_aabb(vertices)
			var local_center := box.get_center()
			for index in range(0, vertices.size(), maxi(1, vertices.size() / 200)):
				var radial := (vertices[index] - local_center)
				if radial.length() < 0.05:
					continue
				total += 1
				if radial.normalized().dot(normals[index].normalized()) > 0.0:
					outward += 1
	print("   法线朝外比例=%.3f（%d/%d）" % [
		float(outward) / float(maxi(total, 1)), outward, total,
	])


func _local_aabb(vertices: PackedVector3Array) -> AABB:
	if vertices.is_empty():
		return AABB()
	var box := AABB(vertices[0], Vector3.ZERO)
	for index in range(1, vertices.size()):
		box = box.expand(vertices[index])
	return box


func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local := mesh_instance.mesh.get_aabb()
		var world := mesh_instance.global_transform * local
		box = world if first else box.merge(world)
		first = false
	return box


func _capture(label: String) -> void:
	_camera.make_current()
	for _i in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("   !! %s 截图失败" % label)
		return
	var path := "%s/%s.png" % [OUT_DIR, label]
	image.save_png(path)
	print("   截图 %s" % path)
