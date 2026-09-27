extends Node
## 真实远征场景内「开灯 / 关灯」实拍对照。
##
## 目的：直接回答「灯打上去有没有效果」。
## 做法：进入房间后，在相机前方放一盏点光源，能量 0 / 8 各拍一张，
## 比较同一机位下画面平均亮度变化。办公室（精工金属结构）与
## 其它房间（通用哑光结构）在同一口径下对照。

const OUT_DIR := "I:/ss2_iso/room_light_probe"
const RUN_SEED := 77001199
const ENERGIES := [0.0, 8.0]
## room_03 = 办公室房型；room_02 = 通用壳体房（对照）
const ROOMS := ["room_02", "room_03", "room_05"]

var _camera: Camera3D
var _lamp: OmniLight3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var scene := load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene
	if scene == null:
		print("!! 远征场景加载失败")
		get_tree().quit(1)
		return
	var level := scene.instantiate()
	level.set("test_mode", true)
	level.set("run_seed_override", RUN_SEED)
	add_child(level)
	for _i in range(10):
		await get_tree().process_frame
		await get_tree().physics_frame
	var hud := level.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false

	_setup_light()

	var rooms := get_tree().get_nodes_in_group("dungeon_room_3d")
	for room_id in ROOMS:
		var room := _find_room(rooms, str(room_id))
		if room == null:
			print("!! 未找到 %s" % room_id)
			continue
		await _shoot_room(str(room_id), room)
	print("PROBE_ROOM_LIGHT_DONE")
	get_tree().quit(0)


## 环境光压到很低，突出「点光源本身」的贡献；世界背景保留一点冷灰便于看清轮廓。
func _setup_light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.22)
	env.ambient_light_energy = 0.10
	var world_env := WorldEnvironment.new()
	world_env.name = "ProbeWorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	_camera = Camera3D.new()
	_camera.name = "ProbeCamera"
	_camera.fov = 80.0
	_camera.near = 0.05
	_camera.far = 300.0
	add_child(_camera)

	_lamp = OmniLight3D.new()
	_lamp.name = "ProbeLamp"
	_lamp.omni_range = 60.0
	_lamp.shadow_enabled = false
	_lamp.light_energy = 0.0
	add_child(_lamp)


func _find_room(rooms: Array, room_id: String) -> DungeonRoom3D:
	for value in rooms:
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_room_id == room_id:
			return room
	return null


func _shoot_room(room_id: String, room: DungeonRoom3D) -> void:
	var tiles: Array[Node3D] = []
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var node3d := node as Node3D
		if node3d == null:
			continue
		if node3d.has_meta("walk_plane_snap_y"):
			tiles.append(node3d)
	if tiles.is_empty():
		print("!! %s 无地砖" % room_id)
		return
	var centroid := Vector3.ZERO
	for tile in tiles:
		centroid += tile.global_position
	centroid /= float(tiles.size())
	var wall_role := _dominant_wall_role(room)
	print("-- %s 地砖=%d 形心=(%.1f,%.1f) 墙主材质=%s" % [
		room_id, tiles.size(), centroid.x, centroid.z, wall_role,
	])
	var forward := Vector3(0.0, 0.0, -1.0)
	_camera.position = Vector3(centroid.x, 1.7, centroid.z)
	_camera.look_at(_camera.position + forward, Vector3.UP)
	_lamp.position = Vector3(centroid.x, 3.2, centroid.z) + forward * 4.0
	for energy_value in ENERGIES:
		_lamp.light_energy = float(energy_value)
		await _capture("%s_点光%.0f_结构%s" % [room_id, float(energy_value), wall_role])


## 房间里最大那面墙件的材质角色（判断它是不是精工金属）。
func _dominant_wall_role(room: DungeonRoom3D) -> String:
	var best := ""
	var best_verts := -1
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if str(node.get_meta("tower_wall_direction", "")).is_empty():
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			var count: int = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
			if count > best_verts:
				best_verts = count
				best = "%s(m=%.2f)" % [material.resource_name, material.metallic]
	return best


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
