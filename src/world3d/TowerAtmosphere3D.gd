class_name TowerAtmosphere3D
extends Node3D
## v0.1 全塔统一自然光控制器。太阳与环境参数不随楼层变化；
## 室内明暗由楼板、墙、门的真实阴影以及局部灯具决定。
## 光照只负责表现，不参与 PlayerVision3D 的目标显隐判定。

const TimeDomain = preload("res://src/core/WorldTimeDomain.gd")

const SUN_ENERGY := 3.0
const SUN_COLOR := Color(1.0, 0.84, 0.62)
const BACKGROUND_COLOR := Color(0.58, 0.62, 0.64)
const AMBIENT_COLOR := Color(0.45, 0.52, 0.60)
const AMBIENT_ENERGY := 0.01
const FOG_LIGHT_COLOR := Color(0.40, 0.48, 0.55)
const FOG_DENSITY := 0.040

var _environment: Environment
var _sun: DirectionalLight3D
var _city_root: Node3D
var _rooftop_sky_bounce: OmniLight3D
var _current_floor_number := 100
var _time_source: Node
var _last_time_snapshot: Dictionary = {}

## 仅在没有全局 GameTimeManager 的孤立验收场景里使用。
@export_range(0.0, 24.0, 0.1) var time_of_day := 17.0
@export_range(0.0, 360.0, 0.1) var time_scale := 0.0


func configure(environment: Environment, sun: DirectionalLight3D) -> void:
	_environment = environment
	_sun = sun
	if GraphicsSettingsManager != null and _environment != null:
		GraphicsSettingsManager.register_environment(_environment)
	if _sun != null:
		_sun.add_to_group(EnemyIllumination3D.SUN_GROUP)
		_sun.set_meta("gameplay_light_kind", "sun")
		if GameplaySpatialRegistry3D != null:
			GameplaySpatialRegistry3D.register_node(_sun, GameplaySpatialRegistry3D.KIND_SUN)
		if not _sun.tree_exiting.is_connected(_unregister_sun):
			_sun.tree_exiting.connect(_unregister_sun)
	# configure() 在 TowerDescent3D.add_child() 之前调用；绝对 /root 查询必须
	# 等节点进入场景树后由 _ready() 执行，避免正式启动时产生树外访问错误。
	_apply_fixed_lighting()


func _ready() -> void:
	_build_city_silhouette()
	_build_rooftop_sky_bounce()
	set_floor_number(100)
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.register_atmosphere(self)
	add_to_group("time_system")
	_bind_global_time_source()
	set_process(_time_source == null and time_scale > 0.0)


func set_floor_number(floor_number: int) -> void:
	_current_floor_number = floor_number
	var rooftop := floor_number >= 100
	if _city_root != null:
		_city_root.visible = rooftop
	if _rooftop_sky_bounce != null:
		# v0.1：补光属于全塔固定环境的一部分，不能随玩家所在楼层闪断。
		_rooftop_sky_bounce.visible = true
	_apply_fixed_lighting()


func _apply_fixed_lighting() -> void:
	if _sun != null:
		_sun.light_color = SUN_COLOR
		_sun.shadow_enabled = true
		_sun.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
		_sun.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	if _environment != null:
		_environment.fog_enabled = GraphicsSettingsManager == null or GraphicsSettingsManager.is_enabled("distance_fog")
		_environment.fog_light_color = FOG_LIGHT_COLOR
		_environment.fog_density = FOG_DENSITY
	_apply_time_of_day()
	set_process(_time_source == null and time_scale > 0.0)


func _apply_time_of_day() -> void:
	if _sun == null:
		return
	var solar := TimeDomain.get_solar_snapshot(time_of_day)
	if not _last_time_snapshot.is_empty():
		solar = (_last_time_snapshot.get("solar", solar) as Dictionary).duplicate(true)
	_apply_solar_snapshot(solar)


func _compute_sun_pitch(hour: float) -> float:
	return (TimeDomain.get_solar_snapshot(hour).get("rotation_degrees", Vector3.ZERO) as Vector3).x


func _compute_sun_energy(hour: float) -> float:
	return float(TimeDomain.get_solar_snapshot(hour).get("energy", 0.0))


func get_clock_string() -> String:
	if not _last_time_snapshot.is_empty():
		return str(_last_time_snapshot.get("clock_text", "17:00"))
	var hour := int(floor(time_of_day)) % 24
	var minute := int(floor(fmod(time_of_day, 1.0) * 60.0))
	return "%02d:%02d" % [hour, minute]


func _process(delta: float) -> void:
	if _time_source != null or time_scale <= 0.0:
		return
	# 孤立预览兼容：time_scale 表示一个游戏小时使用的真实秒数。
	time_of_day = fposmod(time_of_day + delta / maxf(0.001, time_scale), 24.0)
	_apply_time_of_day()


func bind_time_source(source: Node) -> bool:
	if source == null or not source.has_signal("time_advanced"):
		return false
	if _time_source == source:
		return true
	_time_source = source
	if not _time_source.time_advanced.is_connected(_on_world_time_advanced):
		_time_source.time_advanced.connect(_on_world_time_advanced)
	if _time_source.has_method("get_time_snapshot"):
		_last_time_snapshot = _time_source.call("get_time_snapshot") as Dictionary
		time_of_day = float(_last_time_snapshot.get("hour_float", time_of_day))
	set_process(false)
	_apply_time_of_day()
	return true


func _bind_global_time_source() -> void:
	var source := get_node_or_null("/root/GameTimeManager")
	if source != null:
		bind_time_source(source)


func _on_world_time_advanced(_delta_game_seconds: float, snapshot: Dictionary) -> void:
	_last_time_snapshot = snapshot.duplicate(true)
	time_of_day = float(snapshot.get("hour_float", time_of_day))
	_apply_time_of_day()


func _apply_solar_snapshot(solar: Dictionary) -> void:
	if _sun != null:
		_sun.rotation_degrees = solar.get("rotation_degrees", Vector3(-60.0, 32.0, 0.0)) as Vector3
		_sun.light_energy = float(solar.get("energy", 0.0))
		_sun.light_color = solar.get("sun_color", SUN_COLOR) as Color
	if _environment != null:
		_environment.background_color = solar.get("background_color", BACKGROUND_COLOR) as Color
		_environment.ambient_light_color = solar.get("ambient_color", AMBIENT_COLOR) as Color
		_environment.ambient_light_energy = float(solar.get("ambient_energy", AMBIENT_ENERGY))
	if _rooftop_sky_bounce != null:
		_rooftop_sky_bounce.light_energy = lerpf(
			0.06, 0.92, float(solar.get("daylight_factor", 0.0))
		)


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
		"sun_peak_energy": SUN_ENERGY,
		"time_source": "GameTimeManager" if _time_source != null else "isolated_preview",
		"time": _last_time_snapshot.duplicate(true),
		"sun_color": _sun.light_color if _sun != null else Color.BLACK,
		"sun_shadow_enabled": _sun != null and _sun.shadow_enabled,
		"ambient_energy": _environment.ambient_light_energy if _environment != null else 0.0,
		"ambient_color": (
			_environment.ambient_light_color if _environment != null else Color.BLACK
		),
		"fog_density": _environment.fog_density if _environment != null else 0.0,
	}


func apply_performance_quality(profile: String) -> void:
	if _environment != null:
		_environment.fog_enabled = (
			profile != "low"
			and (GraphicsSettingsManager == null or GraphicsSettingsManager.is_enabled("distance_fog"))
		)
		_environment.fog_density = FOG_DENSITY if profile == "high" else FOG_DENSITY * 0.72
	if _sun != null:
		_sun.shadow_enabled = true
		_sun.directional_shadow_max_distance = 120.0 if profile == "high" else 72.0 if profile == "balanced" else 42.0


func _unregister_sun() -> void:
	if GameplaySpatialRegistry3D != null and _sun != null:
		GameplaySpatialRegistry3D.unregister_node(_sun)


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
	city.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	add_child(_rooftop_sky_bounce)
