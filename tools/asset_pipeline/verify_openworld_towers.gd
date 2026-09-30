extends SceneTree
## Run with isolated APPDATA, real renderer (not --headless), --script this file.
const BASE := "res://assets/art/environments/open_world/"
const PALETTE := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
var checks: int = 0
var failures: Array[String] = []
var stage: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func mesh_bounds(node: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(node, meshes)
	var result := AABB()
	var first := true
	for mesh in meshes:
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result

func collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		collect_meshes(child, result)

func verify_materials(node: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(node, meshes)
	check(not meshes.is_empty(), "empty imported asset")
	for mesh in meshes:
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "shadow disabled")
		for i in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(i)
			check(material is BaseMaterial3D, "invalid PBR material")
			if material is BaseMaterial3D:
				check(material.albedo_texture != null and material.albedo_texture.resource_path == PALETTE, "missing shared palette: " + material.resource_name)
				check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "palette filter not nearest")

func run() -> void:
	root.size = Vector2i(1280, 960)
	stage = Node3D.new()
	root.add_child(stage)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("519fe5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5ddff")
	env.ambient_light_energy = 0.65
	env_node.environment = env
	stage.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1000
	stage.add_child(camera)
	camera.current = true
	var report: Dictionary = {"towers": []}
	for pair in [["tower_02", "v003"], ["tower_03", "v001"]]:
		var slug: String = pair[0]
		var version: String = pair[1]
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "source/" + slug + "/export/" + version + "/export_manifest.json"))
		for record in manifest.records:
			var scene: PackedScene = load("res://" + record.prefab)
			check(scene != null, "component cannot load: " + record.slug)
			if scene == null:
				continue
			var component: Node3D = scene.instantiate()
			stage.add_child(component)
			verify_materials(component)
			component.position = Vector3(record.position_godot[0], record.position_godot[1], record.position_godot[2])
			var actual := mesh_bounds(component)
			var low: Array = record.bounds_blender[0]
			var high: Array = record.bounds_blender[1]
			var expected := AABB(Vector3(low[0],low[2],-high[1]),Vector3(high[0]-low[0],high[2]-low[2],high[1]-low[1]))
			check(actual.position.distance_to(expected.position) < 0.01 and actual.size.distance_to(expected.size) < 0.01, "world bounds mismatch: " + record.slug)
			component.free()
		var tower_scene: PackedScene = load(BASE + "runtime/" + slug + "/env_" + slug + "_root_top3d.tscn")
		check(tower_scene != null, "tower cannot load")
		var tower: Node3D = tower_scene.instantiate()
		stage.add_child(tower)
		check(tower.scale == Vector3.ONE, "root scale changed")
		check(not tower.find_children("*", "CollisionObject3D", true, false).size(), "unexpected collision/logic")
		if slug == "tower_02":
			check(tower.get_node("cranes").get_child_count() == 3, "three independent cranes missing")
			for i in range(3):
				var crane_path := BASE + "runtime/tower_02/cranes/crane_%02d/env_tower_02_crane_%02d_root_top3d.tscn" % [i,i]
				var crane_scene: PackedScene = load(crane_path)
				check(crane_scene != null, "independent crane cannot load")
				var crane: Node3D = crane_scene.instantiate()
				stage.add_child(crane)
				var parts: Array[MeshInstance3D] = []
				collect_meshes(crane, parts)
				check(parts.size() == 7, "crane parts mismatch")
				crane.free()
		var bounds := mesh_bounds(tower)
		report.towers.append({"slug":slug,"component_count":manifest.records.size(),"bounds_position":[bounds.position.x,bounds.position.y,bounds.position.z],"bounds_size":[bounds.size.x,bounds.size.y,bounds.size.z]})
		for view in ["whole", "roof"]:
			var center: Vector3 = bounds.get_center()
			if view == "roof":
				center = Vector3(0, 85 if slug == "tower_02" else 43, 0)
				camera.size = 94 if slug == "tower_02" else 83
			else:
				camera.size = 180 if slug == "tower_02" else 108
			camera.position = center + Vector3(140, 135, 165)
			camera.look_at(center, Vector3.UP)
			for frame in range(12):
				await process_frame
			root.msaa_3d = Viewport.MSAA_4X
			await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			check(not image.is_empty(), "real renderer image empty")
			var output: String = BASE + "runtime/" + slug + "/qa/" + view + ".png"
			DirAccess.make_dir_recursive_absolute(output.get_base_dir())
			check(image.save_png(output) == OK, "screenshot save failed")
		tower.free()
	report["checks"] = checks
	report["failures"] = failures
	report["renderer"] = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open(BASE + "runtime/import_acceptance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("OPENWORLD_TOWERS_VERIFY_OK" if failures.is_empty() else "OPENWORLD_TOWERS_VERIFY_FAILED", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
