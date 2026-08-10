extends Node

const FACILITY_OUTPUT := "res://outputs/verification/formal_facility_asset_gallery.png"
const WEAPON_OUTPUT := "res://outputs/verification/formal_weapon_asset_gallery.png"

const FACILITIES := [
	["储物站（待开放）", "res://assets/art/props/base_world_3d/runtime/locker_station/prp_base_locker_station_root_top3d_v001.tscn"],
	["枪械工坊", "res://assets/art/props/base_world_3d/runtime/weapon_workshop/prp_base_weapon_workshop_root_top3d_v001.tscn"],
	["电视站（待开放）", "res://assets/art/props/base_world_3d/runtime/retro_tv_station/prp_base_retro_tv_station_root_top3d_v001.tscn"],
	["远征情报终端", "res://assets/art/props/base_world_3d/runtime/mission_operations/prp_base_mission_operations_root_top3d_v001.tscn"],
	["自动贩卖机", "res://assets/art/props/base_world_3d/runtime/vending_machine/prp_base_vending_machine_root_top3d_v002.tscn"],
]

const WEAPONS := [
	["水箱爆能枪", "water_tank_blaster"], ["扩音器加农炮", "megaphone_cannon"],
	["吉他爆能枪", "guitar_blaster"], ["锅铲步枪", "spatula_rifle"],
	["平底锅加农炮", "frying_pan_cannon"], ["烤面包机发射器", "toaster_launcher"],
	["瞄准镜加农炮", "scope_cannon"], ["爆米花爆能枪", "popcorn_blaster"],
	["口香糖机加农炮", "gumball_cannon"], ["双管炮", "double_barrel_cannon"],
	["饮料管爆能枪", "soda_straw_blaster"], ["鳄鱼加农炮", "crocodile_cannon"],
	["糖果狙击枪", "candy_sniper"], ["相机爆能枪", "camera_blaster"],
	["纸巾盒加农炮", "tissue_box_cannon"], ["扫帚步枪", "broom_rifle"],
	["风扇爆能枪", "fan_blaster"], ["吹风机", "hair_dryer"],
]


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var stage := _create_stage()
	add_child(stage)
	var camera := stage.get_node("Camera3D") as Camera3D
	_build_facility_gallery(stage)
	camera.position = Vector3(0.0, 9.0, -20.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 2.0, 0.0), Vector3.UP)
	camera.fov = 38.0
	await _settle()
	_save_view(FACILITY_OUTPUT, "设施资产验收图保存失败", failures)

	_clear_assets(stage)
	_build_weapon_gallery(stage)
	camera.position = Vector3(0.0, 5.8, -15.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, 2.4, 0.0), Vector3.UP)
	camera.fov = 37.0
	await _settle()
	_save_view(WEAPON_OUTPUT, "枪械资产验收图保存失败", failures)
	if failures.is_empty():
		print("FORMAL_3D_ASSET_GALLERY_VISUAL_OK: 设施朝向/人物比例与18枪侧视比例验收图已生成")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _create_stage() -> Node3D:
	var stage := Node3D.new()
	stage.name = "Stage"
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17152b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8298c8")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(18.0, 8.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("242341")
	floor_material.metallic = 0.18
	floor_material.roughness = 0.68
	plane.material = floor_material
	floor.mesh = plane
	stage.add_child(floor)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key.light_color = Color("c8dcff")
	key.light_energy = 1.05
	stage.add_child(key)
	var warm := OmniLight3D.new()
	warm.position = Vector3(-5.5, 5.2, -4.5)
	warm.light_color = Color("ff72c7")
	warm.light_energy = 5.0
	warm.omni_range = 15.0
	stage.add_child(warm)
	var cool := OmniLight3D.new()
	cool.position = Vector3(5.5, 4.0, -2.0)
	cool.light_color = Color("55e8ff")
	cool.light_energy = 4.0
	cool.omni_range = 15.0
	stage.add_child(cool)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	stage.add_child(camera)
	var assets := Node3D.new()
	assets.name = "Assets"
	stage.add_child(assets)
	return stage


func _build_facility_gallery(stage: Node3D) -> void:
	var assets := stage.get_node("Assets") as Node3D
	for index in FACILITIES.size():
		var record: Array = FACILITIES[index]
		var scene := load(str(record[1])) as PackedScene
		var asset := scene.instantiate() as Node3D
		asset.position = Vector3((float(index) - 2.0) * 5.15, 0.0, 0.0)
		assets.add_child(asset)
		_hide_runtime_labels(asset)
		_add_label(assets, str(record[0]), asset.position + Vector3(0.0, 4.9, 0.0), 34)
	_add_height_reference(assets, Vector3(-13.0, 0.0, 0.0), 1.0, "1米")
	_add_height_reference(assets, Vector3(13.0, 0.0, 0.0), 2.0, "2米")


func _build_weapon_gallery(stage: Node3D) -> void:
	var assets := stage.get_node("Assets") as Node3D
	for index in WEAPONS.size():
		var record: Array = WEAPONS[index]
		var slug := str(record[1])
		var path := "res://assets/art/weapons/weapon_3d/runtime/%s/wpn_%s_root_top3d_v001.tscn" % [slug, slug]
		var asset := (load(path) as PackedScene).instantiate() as Node3D
		var column := index % 6
		var row := index / 6
		asset.position = Vector3((float(column) - 2.5) * 2.65, 4.9 - float(row) * 2.05, 0.0)
		asset.rotation.y = PI * 0.5
		assets.add_child(asset)
		_add_label(assets, str(record[0]), asset.position + Vector3(0.0, -0.78, 0.0), 24)
	_add_height_reference(assets, Vector3(-8.25, 0.0, 0.0), 1.0, "1米参照")


func _add_height_reference(parent: Node3D, position: Vector3, height: float, text: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, height, 0.12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffd84a")
	material.emission_enabled = true
	material.emission = Color("8a5d08")
	material.emission_energy_multiplier = 0.45
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = position + Vector3(0.0, height * 0.5, 0.0)
	parent.add_child(mesh_instance)
	_add_label(parent, text, position + Vector3(0.0, height + 0.18, 0.0), 26)


func _add_label(parent: Node3D, text: String, position: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.font_size = font_size
	label.outline_size = 8
	label.modulate = Color("d7f6ff")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


func _hide_runtime_labels(root: Node) -> void:
	for node_name in ["NameLabel", "PromptLabel"]:
		var label := root.get_node_or_null(node_name) as Label3D
		if label != null:
			label.visible = false


func _clear_assets(stage: Node3D) -> void:
	var old_assets := stage.get_node("Assets")
	old_assets.free()
	var assets := Node3D.new()
	assets.name = "Assets"
	stage.add_child(assets)


func _settle() -> void:
	for _frame in 6:
		await get_tree().process_frame


func _save_view(path: String, message: String, failures: Array[String]) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append(message)
