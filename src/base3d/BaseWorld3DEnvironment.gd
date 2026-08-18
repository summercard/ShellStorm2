class_name BaseWorld3DEnvironment
extends Node3D
## 首张 3D 基地—荒野地图的模块化程序占位套件。
## 只负责视觉、静态碰撞和灯光；设施、入口、存档与场景切换由 BaseWorld3D 持有。

const WORLD_SIZE := Vector3(94.0, 0.4, 32.0)
const WORLD_CENTER := Vector3(29.0, -0.2, 0.0)
const ROAD_COLOR := Color(0.16, 0.17, 0.17)
const SOIL_COLOR := Color(0.105, 0.13, 0.105)
const BASE_COLOR := Color(0.075, 0.105, 0.13)
const RUST_COLOR := Color(0.29, 0.13, 0.055)

var _module_count := 0
var _ruin_count := 0
var _barrier_count := 0
var _light_count := 0
var _world_environment: WorldEnvironment
var _key_light: DirectionalLight3D


func _ready() -> void:
	_build_environment()
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.register_atmosphere(self)
	_build_ground_kit()
	_build_road_damage()
	_build_ruins_and_barriers()
	_build_navigation_lights()
	_build_boundaries()


func get_environment_snapshot() -> Dictionary:
	return {
		"module_count": _module_count,
		"ruin_count": _ruin_count,
		"barrier_count": _barrier_count,
		"light_count": _light_count,
		"world_size": WORLD_SIZE,
		"is_3d": true,
	}


func _build_environment() -> void:
	_world_environment = WorldEnvironment.new()
	_world_environment.name = "UniversalAtmosphere"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = TowerAtmosphere3D.BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = TowerAtmosphere3D.AMBIENT_COLOR
	environment.ambient_light_energy = TowerAtmosphere3D.AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = TowerAtmosphere3D.FOG_LIGHT_COLOR
	environment.fog_density = TowerAtmosphere3D.FOG_DENSITY
	environment.fog_height = 0.0
	environment.fog_height_density = 0.0  # 纯距离雾，关闭高度差异
	_world_environment.environment = environment
	add_child(_world_environment)
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.register_environment(environment)

	_key_light = DirectionalLight3D.new()
	_key_light.name = "UniversalKeyLight"
	_key_light.rotation_degrees = Vector3(-60.0, 32.0, 0.0)
	_key_light.light_color = TowerAtmosphere3D.SUN_COLOR
	_key_light.light_energy = TowerAtmosphere3D.SUN_ENERGY
	_key_light.shadow_enabled = true
	_key_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	_key_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	_key_light.directional_shadow_max_distance = 90.0
	add_child(_key_light)
	_key_light.add_to_group(EnemyIllumination3D.SUN_GROUP)
	_key_light.set_meta("gameplay_light_kind", "sun")


func apply_performance_quality(profile: String) -> void:
	if _world_environment != null and _world_environment.environment != null:
		_world_environment.environment.fog_enabled = (
			profile != "low"
			and (GraphicsSettingsManager == null or GraphicsSettingsManager.is_enabled("distance_fog"))
		)
	if _key_light != null:
		_key_light.shadow_enabled = true
		_key_light.directional_shadow_max_distance = 120.0 if profile == "high" else 72.0 if profile == "balanced" else 42.0


func _build_ground_kit() -> void:
	_add_box("WorldGround", WORLD_CENTER, WORLD_SIZE, SOIL_COLOR, 0.0, 1.0)
	_add_box("BaseDistrict", Vector3(-5.5, 0.03, 0.0), Vector3(22.0, 0.12, 19.0), BASE_COLOR, 0.12, 0.86)
	_add_box("BaseRoadHorizontal", Vector3(-5.5, 0.11, 0.0), Vector3(20.0, 0.08, 2.1), Color(0.14, 0.17, 0.20), 0.18, 0.82)
	_add_box("BaseRoadVertical", Vector3(-10.0, 0.12, 0.0), Vector3(2.1, 0.08, 16.0), Color(0.14, 0.17, 0.20), 0.18, 0.82)
	_add_box("BasePlaza", Vector3(-10.0, 0.14, 0.0), Vector3(6.8, 0.10, 5.1), Color(0.18, 0.22, 0.25), 0.22, 0.76)
	_add_box("WildRoad", Vector3(37.75, 0.12, 0.0), Vector3(66.5, 0.10, 2.6), ROAD_COLOR, 0.16, 0.91)

	for branch in [
		["WildRoadNorth01", Vector3(14.7, 0.12, -3.75), Vector3(2.4, 0.10, 4.9)],
		["WildRoadSouth02", Vector3(29.7, 0.12, 3.9), Vector3(2.4, 0.10, 5.2)],
		["WildRoadNorth03", Vector3(45.7, 0.12, -3.9), Vector3(2.4, 0.10, 5.2)],
		["WildRoadSouth04", Vector3(61.7, 0.12, 4.1), Vector3(2.4, 0.10, 5.6)],
	]:
		_add_box(branch[0], branch[1], branch[2], ROAD_COLOR, 0.16, 0.91)

	var fields := [
		["NorthField01", Vector3(14.5, 0.02, -8.35), Vector3(17.0, 0.07, 12.3), Color(0.085, 0.14, 0.09)],
		["SouthField02", Vector3(29.5, 0.02, 8.35), Vector3(17.0, 0.07, 12.3), Color(0.15, 0.10, 0.065)],
		["NorthField03", Vector3(46.0, 0.02, -8.35), Vector3(16.0, 0.07, 12.3), Color(0.075, 0.105, 0.13)],
		["SouthField04", Vector3(63.25, 0.02, 8.35), Vector3(18.5, 0.07, 12.3), Color(0.13, 0.07, 0.13)],
	]
	for field in fields:
		_add_box(field[0], field[1], field[2], field[3], 0.0, 1.0)

	for x in range(7, 70, 4):
		if x in [15, 31, 47, 63]:
			continue
		_add_box("LaneMark_%02d" % x, Vector3(float(x), 0.19, 0.0), Vector3(1.65, 0.035, 0.11), Color(0.58, 0.52, 0.31), 0.0, 0.94)


func _build_road_damage() -> void:
	var patches := [
		[Vector3(8.5, 0.19, -0.45), Vector3(2.2, 0.035, 0.85)],
		[Vector3(20.0, 0.19, 0.35), Vector3(1.4, 0.035, 0.65)],
		[Vector3(34.0, 0.19, -0.30), Vector3(2.8, 0.035, 0.55)],
		[Vector3(51.0, 0.19, 0.42), Vector3(1.8, 0.035, 0.70)],
		[Vector3(67.0, 0.19, -0.35), Vector3(2.4, 0.035, 0.58)],
	]
	for index in range(patches.size()):
		_add_box("RoadPatch_%02d" % index, patches[index][0], patches[index][1], Color(0.075, 0.08, 0.08), 0.1, 0.96)

	for index in range(18):
		var x := 6.5 + float(index) * 3.6
		var z := -0.82 + float(index % 4) * 0.52
		var debris := _add_box(
			"RoadDebris_%02d" % index,
			Vector3(x, 0.28, z),
			Vector3(0.22 + float(index % 3) * 0.08, 0.22, 0.16 + float(index % 2) * 0.09),
			RUST_COLOR if index % 4 == 0 else Color(0.16, 0.17, 0.16),
			0.42,
			0.75
		)
		debris.rotation_degrees.y = float(index * 37 % 180)


func _build_ruins_and_barriers() -> void:
	var ruin_specs := [
		[Vector3(10.0, 0.0, -11.3), Vector3(4.3, 0.0, 2.6), Color(0.14, 0.22, 0.24)],
		[Vector3(18.9, 0.0, -5.0), Vector3(3.6, 0.0, 2.5), Color(0.27, 0.14, 0.07)],
		[Vector3(25.8, 0.0, 9.1), Vector3(4.5, 0.0, 3.0), Color(0.12, 0.23, 0.14)],
		[Vector3(34.8, 0.0, 5.4), Vector3(3.3, 0.0, 2.3), Color(0.20, 0.10, 0.20)],
		[Vector3(41.3, 0.0, -11.0), Vector3(4.7, 0.0, 2.8), Color(0.14, 0.22, 0.24)],
		[Vector3(50.5, 0.0, -4.8), Vector3(3.6, 0.0, 2.3), Color(0.27, 0.14, 0.07)],
		[Vector3(58.7, 0.0, 9.2), Vector3(4.3, 0.0, 3.0), Color(0.12, 0.23, 0.14)],
		[Vector3(68.2, 0.0, 6.0), Vector3(3.9, 0.0, 2.6), Color(0.20, 0.10, 0.20)],
	]
	for index in range(ruin_specs.size()):
		var spec = ruin_specs[index]
		var center: Vector3 = spec[0]
		var size: Vector3 = spec[1]
		var tint: Color = spec[2]
		_add_box("RuinFloor_%02d" % index, center + Vector3(0, 0.11, 0), Vector3(size.x, 0.18, size.z), tint.darkened(0.38), 0.28, 0.88)
		_add_box("RuinWallA_%02d" % index, center + Vector3(0, 0.72, -size.z * 0.46), Vector3(size.x, 1.3, 0.24), tint, 0.38, 0.73)
		_add_box("RuinWallB_%02d" % index, center + Vector3(-size.x * 0.46, 0.48, 0), Vector3(0.24, 0.85, size.z), tint.darkened(0.12), 0.38, 0.73)
		_ruin_count += 1

	var barriers := [
		Vector3(12.0, 0.42, 1.7), Vector3(23.0, 0.42, -1.8),
		Vector3(37.0, 0.42, 1.75), Vector3(55.0, 0.42, -1.75),
		Vector3(70.0, 0.42, 1.7), Vector3(-15.0, 0.42, -7.8),
	]
	for index in range(barriers.size()):
		var barrier := _add_box("Barrier_%02d" % index, barriers[index], Vector3(1.8, 0.62, 0.34), Color(0.23, 0.19, 0.10), 0.46, 0.66)
		barrier.rotation_degrees.y = -18.0 if index % 2 == 0 else 17.0
		_barrier_count += 1


func _build_navigation_lights() -> void:
	var lights := [
		[Vector3(-14.6, 3.0, -6.1), Color(0.40, 0.78, 1.0)],
		[Vector3(-10.1, 3.2, -0.8), Color(0.44, 0.82, 1.0)],
		[Vector3(-5.8, 2.8, 5.2), Color(0.38, 0.68, 0.92)],
		[Vector3(1.2, 2.6, 0.0), Color(0.38, 0.62, 0.72)],
		[Vector3(9.8, 2.6, 0.0), Color(0.72, 0.58, 0.30)],
		[Vector3(14.7, 3.3, -6.5), Color(0.30, 0.64, 1.0)],
		[Vector3(23.7, 2.8, 0.1), Color(0.92, 0.44, 0.12)],
		[Vector3(29.7, 3.3, 6.8), Color(1.0, 0.34, 0.08)],
		[Vector3(37.7, 2.7, -0.2), Color(0.42, 0.72, 0.28)],
		[Vector3(45.7, 3.3, -6.8), Color(0.32, 0.92, 0.38)],
		[Vector3(53.5, 2.7, 0.2), Color(0.72, 0.22, 0.36)],
		[Vector3(61.7, 3.3, 7.2), Color(0.92, 0.20, 0.70)],
		[Vector3(70.0, 2.6, -0.1), Color(0.42, 0.55, 0.68)],
	]
	for index in range(lights.size()):
		var spec = lights[index]
		_add_box("LightPole_%02d" % index, Vector3(spec[0].x, 1.35, spec[0].z), Vector3(0.13, 2.7, 0.13), Color(0.09, 0.10, 0.11), 0.75, 0.45)
		var light := OmniLight3D.new()
		light.name = "NavigationLight_%02d" % index
		light.position = spec[0]
		light.light_color = spec[1]
		light.light_energy = 2.2 if index in [5, 7, 9, 11] else 1.25
		light.omni_range = 6.8 if index in [5, 7, 9, 11] else 4.6
		light.shadow_enabled = false
		add_child(light)
		light.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		light.set_meta("gameplay_light_kind", "omni")
		_light_count += 1


func _build_boundaries() -> void:
	var boundary := StaticBody3D.new()
	boundary.name = "WorldBoundary"
	boundary.collision_layer = 1
	boundary.collision_mask = 0
	add_child(boundary)
	for spec in [
		["North", Vector3(29.0, 1.0, -16.4), Vector3(94.8, 2.0, 0.8)],
		["South", Vector3(29.0, 1.0, 16.4), Vector3(94.8, 2.0, 0.8)],
		["West", Vector3(-18.4, 1.0, 0.0), Vector3(0.8, 2.0, 32.8)],
		["East", Vector3(76.4, 1.0, 0.0), Vector3(0.8, 2.0, 32.8)],
	]:
		var shape := BoxShape3D.new()
		shape.size = spec[2]
		var collision := CollisionShape3D.new()
		collision.name = spec[0]
		collision.position = spec[1]
		collision.shape = shape
		boundary.add_child(collision)

	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundCollision"
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	add_child(ground_body)
	var ground_shape := BoxShape3D.new()
	ground_shape.size = WORLD_SIZE
	var ground_collision := CollisionShape3D.new()
	ground_collision.position = WORLD_CENTER
	ground_collision.shape = ground_shape
	ground_body.add_child(ground_collision)


func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	color: Color,
	metallic: float,
	roughness: float
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	_module_count += 1
	return instance
