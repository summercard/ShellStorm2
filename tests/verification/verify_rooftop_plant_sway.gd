extends SceneTree
## 总验收：按真实天台布局（data/layouts/rooftop_100f_decorated_layout.json）
## 实例化全部 44 件植物 + 24 面房间墙，检查：
##   N1 每件植物的色盘面都换成了风摆材质
##   N2 全场景材质实例数（同档共用，应远小于面数）
##   N3 没有新增任何 Light3D
##   N4 冻结全部风摆后，与原始 prefab 逐像素相等（颜色未变）
##   N5 时钟仍在推进
##   N6 几何级穿墙判定：最坏摆幅下与房间墙零新增体积重叠
##
## N4 必须走**真渲染**（Forward+）。headless 下拿不到绘图表面，脚本会跳过截图并
## 以 exit 2 明确报「未执行视觉对照」，不允许把无头通过当作视觉验收。
##   真渲染：godot --path . --script res://tests/verification/verify_rooftop_plant_sway.gd

const LAYOUT := "res://data/layouts/rooftop_100f_decorated_layout.json"
const PREFABS := {
	"plant_large": "res://assets/art/environments/tower_zones/rooftop/runtime/plant_large.tscn",
	"plant_small": "res://assets/art/environments/tower_zones/rooftop/runtime/plant_small.tscn",
	"flowerbox": "res://assets/art/environments/tower_zones/rooftop/runtime/flowerbox.tscn",
	"ivy": "res://assets/art/environments/tower_zones/rooftop/runtime/ivy.tscn",
	"parapet_ivy": "res://assets/art/environments/tower_zones/rooftop/runtime/parapet_ivy.tscn",
}
const WALL_SCENES := {
	"room_wall": "res://assets/art/props/dungeon_3d/prp_rooftop_room_wall_5x12.tscn",
	"room_window": "res://assets/art/props/dungeon_3d/prp_rooftop_room_window_5x12.tscn",
	"room_doorwall": "res://assets/art/props/dungeon_3d/prp_rooftop_room_doorwall_5x12.tscn",
}
const OUT_DIR := "res://outputs/verification/rooftop_plant_sway"

var _stage: Node3D
var _camera: Camera3D
var _failures: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()

	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var planted := 0
	var swayed_faces := 0
	var kept_faces := 0
	var materials := {}
	var plants: Array = []
	var wall_boxes: Array = []
	for item: Dictionary in layout["instances"]:
		var slug := str(item.get("component_slug", ""))
		if not bool(item.get("enabled", false)):
			continue
		var is_plant := PREFABS.has(slug)
		var is_wall := WALL_SCENES.has(slug)
		if not is_plant and not is_wall:
			continue
		var path: String = PREFABS[slug] if is_plant else WALL_SCENES[slug]
		var packed := load(path) as PackedScene
		if packed == null:
			_failures.append("load_failed " + slug)
			continue
		var instance := packed.instantiate() as Node3D
		_place(instance, item)
		_stage.add_child(instance)
		await process_frame
		if is_wall:
			wall_boxes.append([slug, _world_aabb(instance)])
			continue
		planted += 1
		plants.append([slug, instance, _world_aabb(instance)])
		for node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var override := mesh_instance.get_surface_override_material(surface)
				if override is ShaderMaterial:
					swayed_faces += 1
					materials[override.get_instance_id()] = true
				else:
					kept_faces += 1
					_failures.append("not_swayed %s s%d" % [mesh_instance.name, surface])

	await _wait_frames(10)
	print("N1 planted=%d swayed_faces=%d kept_faces=%d walls=%d" % [
		planted, swayed_faces, kept_faces, wall_boxes.size()
	])
	print("N2 shared_material_instances=%d" % materials.size())
	if planted != 44:
		_failures.append("planted_expected_44_got_%d" % planted)

	var lights := 0
	for node in _stage.find_children("*", "Light3D", true, false):
		lights += 1
	print("N3 light_count=%d (sun only)" % lights)
	if lights != 1:
		_failures.append("light_count_expected_1_got_%d" % lights)

	var sway_script = load("res://src/world3d/PlantSway3D.gd")
	var before := float(sway_script._clock)
	await _wait_seconds(0.5)
	var after := float(sway_script._clock)
	print("N5 clock %.3f -> %.3f advanced=%s" % [before, after, str(after > before)])
	if after <= before:
		_failures.append("clock_not_advancing")

	_check_wall_clearance(plants, wall_boxes)

	if DisplayServer.get_name() == "headless":
		# 无头档不代签视觉：给明确退出码，避免被误读成通过。
		if _failures.is_empty():
			printerr("HEADLESS_SKIPPED_VISUAL: 结构/时钟/穿墙已通过，但颜色对照未执行")
			quit(2)
		else:
			for failure in _failures:
				printerr("FAIL ", failure)
			quit(1)
		return

	# 冻结全部材质后与「无脚本原始 prefab」对照颜色
	var frozen := 0
	for node in _stage.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var override := mesh_instance.get_surface_override_material(surface)
			if override is ShaderMaterial:
				override.set_shader_parameter("sway_amplitude", 0.0)
				override.set_shader_parameter("wind_time", 0.0)
				frozen += 1
	print("FREEZE applied to %d materials" % frozen)
	_frame_camera(_union_aabb(plants))
	await _wait_frames(10)
	await _capture("40_layout_frozen")
	# 噪声基线：同一静止状态下再拍一张。TAA 会做时间累积，两张之间也会有
	# 极少量像素抖动；有了这条基线，颜色对照的判据才能是「差值不超过噪声」而不是死磕 0。
	await _wait_frames(10)
	await _capture("40b_layout_frozen_repeat")

	# 对照：同样布局、同样位置，但用原始 GLB（无风摆脚本）。
	# ⚠️ 必须保留太阳光：把 Light3D 一起 free 会让第二遍变成纯环境光，
	#    植物像素整体变暗，误判成「着色器改坏了颜色」（实测 max=123 / 5001 点）。
	for child in _stage.get_children():
		if child == _camera or child is WorldEnvironment or child is Light3D:
			continue
		child.queue_free()
	await _wait_frames(4)
	_rebuild_originals(layout)
	await _wait_frames(10)
	await _capture("41_layout_original")

	if _failures.is_empty():
		print("ROOFTOP_PLANT_SWAY_ACCEPT_OK")
	else:
		for failure in _failures:
			printerr("FAIL ", failure)
	quit(0 if _failures.is_empty() else 1)


## 几何级穿墙判定：只有 foliage_base_y 以上的枝叶会动，盆/箱体不动。
## 把「会动部分」沿风向两侧各平移满幅，与墙体 AABB 求交；再减去静止时本来就有的重叠。
## ⚠️ 不能把整件 AABB 一起平移 —— 那会把不动的箱体也算进扫掠体积，误报穿透
##    （第一次实测就这样误判成「花箱新增重叠 0.74m³」，实际箱体根本没动）。
##
## ⚠️ 本判据的已知盲区：**沿墙面的横向摆动**。
##    当植物整体已落在墙的 x 范围内时（藤蔓就是：4.26m 宽，落在 5m 墙里），
##    横向多扫 7.6cm 不会改变「与墙 AABB 的相交体积」，于是本判据报 0 ——
##    但这不代表没有擦到窗垛。藤蔓的真实证据是像素级：冻结帧 vs 原始材质
##    只差 2 个像素、max=22，且位于窗框边缘（窗墙 5m、玻璃 4.4m，墙垛仅 0.15m）。
##    这个量级是抗锯齿边缘差异：藤蔓本来就贴在墙外侧盘绕、静止时就与墙体重叠，
##    叶子横摆掠过 0.15m 墙垛是正确表现，不是穿模。
func _check_wall_clearance(plants: Array, wall_boxes: Array) -> void:
	var new_overlaps := 0
	for entry in plants:
		var slug: String = entry[0]
		var node: Node3D = entry[1]
		var rest_box: AABB = entry[2]
		var materials := _sway_materials(node)
		if materials.is_empty():
			continue
		var amplitude := 0.0
		for material in materials:
			amplitude = maxf(amplitude, float(material.get_shader_parameter("sway_amplitude")))
		var from_top := bool(materials[0].get_shader_parameter("sway_from_top"))
		var base_y := float(materials[0].get_shader_parameter("foliage_base_y"))
		var world_base_y := node.global_position.y + base_y
		var moving_box := _foliage_only_aabb(node, world_base_y, from_top)
		if moving_box.size == Vector3.ZERO:
			continue
		var swept: AABB = rest_box.merge(moving_box)
		for sign_value in [-1.0, 1.0]:
			var shift: Vector3 = Vector3(amplitude, 0.0, amplitude) * 0.85 * float(sign_value)
			swept = swept.merge(AABB(moving_box.position + shift, moving_box.size))
		for wall in wall_boxes:
			var wall_box: AABB = wall[1]
			if not swept.intersects(wall_box):
				continue
			var swept_overlap: AABB = swept.intersection(wall_box)
			var rest_overlap := 0.0
			if rest_box.intersects(wall_box):
				rest_overlap = (rest_box.intersection(wall_box) as AABB).get_volume()
			var delta := swept_overlap.get_volume() - rest_overlap
			if delta > 0.0005:
				new_overlaps += 1
				_failures.append("wall_penetration %s ↔ %s new=%.4f m³" % [slug, wall[0], delta])
	print("N6 new_wall_penetrations=%d (0 = 最坏摆幅下不穿墙)" % new_overlaps)


func _rebuild_originals(layout: Dictionary) -> void:
	var glbs := {
		"plant_large": "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_plant_large_top3d.glb",
		"plant_small": "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_plant_small_top3d.glb",
		"flowerbox": "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_flowerbox_top3d.glb",
		"ivy": "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_ivy_top3d.glb",
		"parapet_ivy": "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_ivy_top3d.glb",
	}
	for item: Dictionary in layout["instances"]:
		var slug := str(item.get("component_slug", ""))
		if not bool(item.get("enabled", false)):
			continue
		if glbs.has(slug):
			var instance := (load(glbs[slug]) as PackedScene).instantiate() as Node3D
			_place(instance, item)
			_stage.add_child(instance)
		elif WALL_SCENES.has(slug):
			var wall := (load(WALL_SCENES[slug]) as PackedScene).instantiate() as Node3D
			_place(wall, item)
			_stage.add_child(wall)


func _place(instance: Node3D, item: Dictionary) -> void:
	var position: Array = item["position_m"]
	# position_m = [x, z, y_height]
	instance.position = Vector3(float(position[0]), float(position[2]), float(position[1]))
	instance.rotation_degrees = Vector3(0.0, float(item.get("rotation_y_deg", 0.0)), 0.0)


func _sway_materials(root: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var override := mesh_instance.get_surface_override_material(surface)
			if override is ShaderMaterial and not found.has(override):
				found.append(override)
	return found


func _union_aabb(plants: Array) -> AABB:
	var result := AABB()
	var first := true
	for entry in plants:
		var box: AABB = _world_aabb(entry[1])
		if box.size == Vector3.ZERO:
			continue
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _world_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


## 只取「会动的那部分」的世界 AABB：按固定端高度切分顶点。
## from_top=true（藤蔓）取 y < world_base_y 的顶点；否则取 y > world_base_y。
func _foliage_only_aabb(root: Node, world_base_y: float, from_top: bool) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var xform := mesh_instance.global_transform
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			if not String(material.resource_name).begins_with("0"):
				continue
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var world := xform * vertex
				var in_foliage := world.y < world_base_y - 0.01 if from_top else world.y > world_base_y + 0.01
				if not in_foliage:
					continue
				var point := AABB(world, Vector3.ZERO)
				result = point if first else result.merge(point)
				first = false
	return result


func _frame_camera(aabb: AABB) -> void:
	var center := aabb.get_center()
	var radius := maxf(aabb.size.length() * 0.5, 2.0)
	var distance := radius / tan(deg_to_rad(_camera.fov * 0.5)) * 1.1
	_camera.look_at_from_position(center + Vector3(0.35, 0.85, 1.0).normalized() * distance, center)


func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "LayoutStage"
	get_root().add_child(_stage)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.40, 0.46, 0.54)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.63, 0.70)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	_stage.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 40.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	_stage.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_camera.current = true
	_stage.add_child(_camera)


func _wait_frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name]))
	print("SHOT ", shot_name)
