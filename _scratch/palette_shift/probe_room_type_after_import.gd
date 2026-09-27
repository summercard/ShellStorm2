extends Node
## 导入拼装后的运行时取证：实例化**真实 PackedScene**，读运行时材质参数并渲染，
## 证明「UV 提亮 + 材质亚光化」已随资产重导进入运行时。
##
## 输出：每个组件一张 PNG + 逐表面的 metallic/roughness/贴图 文本报告。

const OUT_DIR := "I:/ss2_iso/room_type_after_import"

const RUNTIME := "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components"

const CASES := [
	# 转哑光的大面（本次改动的正对象）
	{"tag": "1_office_work_cluster", "room": "office_room", "slug": "work_cluster"},
	{"tag": "2_office_wall_t615_5m", "room": "office_room", "slug": "wall_t615_5m"},
	{"tag": "3_bridge_tile_upper", "room": "bridge_room", "slug": "tile_upper"},
	{"tag": "4_bridge_pit_side", "room": "bridge_room", "slug": "pit_side"},
	{"tag": "5_boss_server_rack", "room": "boss_room", "slug": "server_rack"},
	{"tag": "6_boss_heavy_conduits", "room": "boss_room", "slug": "heavy_conduits"},
	{"tag": "7_boss_wall_solid_5m", "room": "boss_room", "slug": "wall_solid_5m"},
	# 按判据保留金属的小件（对照：仍应见高金属）
	{"tag": "8_boss_workstation_a", "room": "boss_room", "slug": "workstation_a"},
	{"tag": "9_office_floor_tile_5m", "room": "office_room", "slug": "floor_tile_5m"},
]

var _camera: Camera3D
var _sun: DirectionalLight3D
var _holder: Node3D
var _report: FileAccess


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_report = FileAccess.open("%s/probe_report.txt" % OUT_DIR, FileAccess.WRITE)
	_setup()
	for case_value in CASES:
		await _shoot_case(case_value as Dictionary)
	_report.close()
	print("PROBE_ROOM_TYPE_AFTER_IMPORT_DONE")
	get_tree().quit(0)


## 同时写 stdout 与报告文件，保证验收日志可归档。
func _emit(line: String) -> void:
	print(line)
	if _report != null:
		_report.store_line(line)


func _setup() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.88)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.name = "ProbeWorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "ProbeSun"
	# 俯射主光：与房间顶灯入射角一致，哑光整面受光、金属只剩小块高光。
	_sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	_sun.light_energy = 2.2
	_sun.shadow_enabled = false
	add_child(_sun)

	var fill := DirectionalLight3D.new()
	fill.name = "ProbeFill"
	fill.rotation_degrees = Vector3(-24.0, -140.0, 0.0)
	fill.light_energy = 0.9
	fill.shadow_enabled = false
	add_child(fill)

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
	var slug := str(spec["slug"])
	var path := "%s/%s/%s/%s_root_top3d.tscn" % [RUNTIME, spec["room"], slug, slug]
	var packed := load(path) as PackedScene
	if packed == null:
		_emit("!! %s 加载失败：%s" % [tag, path])
		return
	var instance := packed.instantiate() as Node3D
	_holder.add_child(instance)
	await get_tree().process_frame

	var aabb := _world_aabb(instance)
	var center := aabb.get_center()
	var size := aabb.size
	var dist := maxf(maxf(size.x, size.y), size.z) * 1.9
	_camera.position = center + Vector3(0.86, 0.82, 0.62).normalized() * dist
	_camera.look_at(center, Vector3.UP)

	_emit("== %s (%s) aabb=%s" % [tag, slug, str(size)])
	_report_materials(instance)

	await _capture(tag)
	_holder.remove_child(instance)
	instance.free()


## 逐表面打印运行时实际材质参数（这是「导入拼装」是否生效的硬证据）。
func _report_materials(root: Node) -> void:
	var surfaces := 0
	var metals := 0
	var mattes := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			surfaces += 1
			var material := mesh_instance.get_surface_override_material(surface)
			if material == null:
				material = mesh.surface_get_material(surface)
			var std := material as StandardMaterial3D
			if std == null:
				_emit("   surface%d 材质非 StandardMaterial3D：%s" % [surface, material])
				continue
			var texture_path := "<无>"
			if std.albedo_texture != null:
				texture_path = std.albedo_texture.resource_path
			_emit("   surface%d metallic=%.3f roughness=%.3f albedo_tex=%s" % [
				surface, std.metallic, std.roughness, texture_path,
			])
			if std.metallic >= 0.5:
				metals += 1
			else:
				mattes += 1
	_emit("   >> 表面 %d：高金属(>=0.5) %d，低金属(<0.5) %d" % [surfaces, metals, mattes])


func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return box


func _capture(label: String) -> void:
	_camera.make_current()
	for _i in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		_emit("   !! %s 截图失败" % label)
		return
	var path := "%s/%s.png" % [OUT_DIR, label]
	image.save_png(path)
	_emit("   截图 %s" % path)
