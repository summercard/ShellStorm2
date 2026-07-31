class_name TowerAtmosphere3D
extends Node3D
## PH42 全塔统一自然光控制器。太阳与环境参数不随楼层变化；
## 室内明暗由楼板、墙、门的真实阴影以及局部灯具决定。
## 光照只负责表现，不参与 PlayerVision3D 的目标显隐判定。

## 太阳与天空补光只照环境层（Layer 1）。角色在 Layer 2，只吃 AvatarFrontFill，
## 这样第三盏角色补光的表现不会随楼层的自然光强弱而漂移。
const ENVIRONMENT_RENDER_LAYER := 1
const SUN_ENERGY := 0.85
const SUN_COLOR := Color(1.0, 0.84, 0.62)
const BACKGROUND_COLOR := Color(0.58, 0.62, 0.64)
const AMBIENT_COLOR := Color(0.45, 0.52, 0.60)
const AMBIENT_ENERGY := 0.42
const FOG_LIGHT_COLOR := Color(0.40, 0.48, 0.55)
const FOG_DENSITY := 0.0050

var _environment: Environment
var _sun: DirectionalLight3D
var _city_root: Node3D
var _rooftop_sky_bounce: OmniLight3D
var _current_floor_number := 100


func configure(environment: Environment, sun: DirectionalLight3D) -> void:
	_environment = environment
	_sun = sun
	_apply_fixed_lighting()


func _ready() -> void:
	_build_city_silhouette()
	_build_rooftop_sky_bounce()
	set_floor_number(100)


func set_floor_number(floor_number: int) -> void:
	_current_floor_number = floor_number
	var rooftop := floor_number >= 100
	if _city_root != null:
		_city_root.visible = rooftop
	if _rooftop_sky_bounce != null:
		# PH49：补光属于全塔固定环境的一部分，不能随玩家所在楼层闪断。
		_rooftop_sky_bounce.visible = true
	_apply_fixed_lighting()


func _apply_fixed_lighting() -> void:
	if _sun != null:
		_sun.light_energy = SUN_ENERGY
		_sun.light_color = SUN_COLOR
		_sun.shadow_enabled = true
		_sun.light_cull_mask = ENVIRONMENT_RENDER_LAYER
	if _environment != null:
		_environment.background_color = BACKGROUND_COLOR
		_environment.ambient_light_color = AMBIENT_COLOR
		_environment.ambient_light_energy = AMBIENT_ENERGY
		_environment.fog_enabled = true
		_environment.fog_light_color = FOG_LIGHT_COLOR
		_environment.fog_density = FOG_DENSITY


func get_snapshot() -> Dictionary:
	return {
		"floor_number": _current_floor_number,
		"rooftop_daylight": _current_floor_number >= 100,
		"city_visible": _city_root != null and _city_root.visible,
		"lighting_mode": "global_fixed_environment",
		"floor_dependent_lighting": false,
		"lighting_visibility_follows_player": false,
		"simulated_window_lighting": false,
		"rooftop_sky_bounce": (
			_rooftop_sky_bounce != null and _rooftop_sky_bounce.visible
		),
		"sun_energy": _sun.light_energy if _sun != null else 0.0,
		"sun_color": _sun.light_color if _sun != null else Color.BLACK,
		"sun_shadow_enabled": _sun != null and _sun.shadow_enabled,
		"sun_cull_mask": _sun.light_cull_mask if _sun != null else 0,
		"sky_bounce_cull_mask": (
			_rooftop_sky_bounce.light_cull_mask if _rooftop_sky_bounce != null else 0
		),
		"world_lights_affect_avatar": false,
		"ambient_energy": _environment.ambient_light_energy if _environment != null else 0.0,
		"ambient_color": (
			_environment.ambient_light_color if _environment != null else Color.BLACK
		),
		"fog_density": _environment.fog_density if _environment != null else 0.0,
	}


func _build_city_silhouette() -> void:
	_city_root = Node3D.new()
	_city_root.name = "RooftopCityBelow"
	add_child(_city_root)
	var building_mesh := BoxMesh.new()
	building_mesh.size = Vector3(1.0, 1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.025, 0.040, 0.052)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.metallic = 0.36
	material.roughness = 0.82
	material.emission_enabled = true
	material.emission = Color(0.04, 0.12, 0.17)
	material.emission_energy_multiplier = 0.22
	building_mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = building_mesh
	var transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 990095
	for ring in range(2):
		# 第一圈紧邻250m楼体之外，玩家靠近围栏即可俯瞰；建筑最高点
		# 始终低于楼顶20m，不会与可玩屋面穿插。
		var radius := 145.0 + float(ring) * 58.0
		var count := 40 + ring * 16
		for index in range(count):
			var angle := TAU * float(index) / float(count) + rng.randf_range(-0.035, 0.035)
			var width := rng.randf_range(12.0, 28.0)
			var depth := rng.randf_range(12.0, 28.0)
			var height := rng.randf_range(45.0, 150.0)
			var position := Vector3(cos(angle) * radius, -20.0 - height * 0.5, sin(angle) * radius)
			var basis := Basis.IDENTITY.scaled(Vector3(width, height, depth))
			transforms.append(Transform3D(basis, position))
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var city := MultiMeshInstance3D.new()
	city.name = "CityBuildingSilhouettes"
	city.multimesh = multimesh
	city.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	city.visibility_range_end = 520.0
	_city_root.add_child(city)


func _build_rooftop_sky_bounce() -> void:
	# Compatibility 渲染器没有实时天空 GI；太阳背面的特殊楼梯墙会因此
	# 压成纯黑。单个带阴影局部光放在特殊墙顶以上，只模拟楼顶开阔
	# 天空的漫反射；太阳、环境参数和室内灯体系保持不变，楼板与墙仍
	# 会阻止它泄漏到室内。
	_rooftop_sky_bounce = OmniLight3D.new()
	_rooftop_sky_bounce.name = "RooftopSkyBounce"
	_rooftop_sky_bounce.position = Vector3(-34.0, 16.0, 0.0)
	_rooftop_sky_bounce.light_color = Color(0.42, 0.66, 0.82)
	_rooftop_sky_bounce.light_energy = 0.92
	_rooftop_sky_bounce.omni_range = 52.0
	_rooftop_sky_bounce.omni_attenuation = 1.35
	_rooftop_sky_bounce.shadow_enabled = false
	_rooftop_sky_bounce.light_cull_mask = ENVIRONMENT_RENDER_LAYER
	add_child(_rooftop_sky_bounce)
