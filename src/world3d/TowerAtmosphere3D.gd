class_name TowerAtmosphere3D
extends Node3D
## v0.1 全塔统一自然光控制器。太阳与环境参数不随楼层变化；
## 室内明暗由楼板、墙、门的真实阴影以及局部灯具决定。
## 光照只负责表现，不参与 PlayerVision3D 的目标显隐判定。

const SUN_ENERGY := 0.58
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

## 游戏内时间系统（小时，0..24）。time_scale = 0 时不推进（默认），
## time_scale = 1.0 = 1 真实秒 = 1 游戏秒 = 1 小时 / 3600 秒。
## 当 time_scale > 0 时 _process 会按 delta 自增 time_of_day；
## time_of_day 走过 24 点后折返到 0 点（不存日期）。
@export_range(0.0, 24.0, 0.1) var time_of_day := 12.0
@export_range(0.0, 360.0, 0.1) var time_scale := 0.0
## 太阳方位角（yaw）— 与之前一致，主人手调过的值；时间系统只改 pitch（高度）
## 与 light_energy，yaw 始终保持太阳方位不变。
@export_range(-180.0, 180.0, 0.5) var sun_yaw := 32.0


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
	_apply_fixed_lighting()


func _ready() -> void:
	_build_city_silhouette()
	_build_rooftop_sky_bounce()
	set_floor_number(100)
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.register_atmosphere(self)
	add_to_group("time_system")
	set_process(time_scale > 0.0)


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
		_environment.background_color = BACKGROUND_COLOR
		_environment.ambient_light_color = AMBIENT_COLOR
		_environment.ambient_light_energy = AMBIENT_ENERGY
		_environment.fog_enabled = GraphicsSettingsManager == null or GraphicsSettingsManager.is_enabled("distance_fog")
		_environment.fog_light_color = FOG_LIGHT_COLOR
		_environment.fog_density = FOG_DENSITY
	_apply_time_of_day()
	set_process(time_scale > 0.0)


## 根据 time_of_day 重写太阳的仰角与能量。
## 约定：6 点日出、12 点正午、18 点日落。太阳轨迹在半天空（从地平线以下
## 升至顶 + 落回地平线以下）。夜裡能量 = 0，白天能量峰值 = SUN_ENERGY。
func _apply_time_of_day() -> void:
	if _sun == null:
		return
	# ——1. 仰角：0 点 = -90（地平线以下），6 点 = -90（升起点），12 点 = 0（正顶），18 点 = -90（落下），24 点 = -90
	var sun_pitch := _compute_sun_pitch(time_of_day)
	_sun.rotation_degrees = Vector3(sun_pitch, sun_yaw, 0.0)
	# ——2. 能量：仅在白天太阳位于地平线上方时按仰角查表，夜里/日出日落附近=0
	_sun.light_energy = _compute_sun_energy(time_of_day)


func _compute_sun_pitch(hour: float) -> float:
	# 以 6 点为中心（-180°）扫到 18 点（180°），保证12 点=0（正顶，仰角90°）
	# 这里返回的是 Godot 的 pitch：负值表示光朝地面射（正值表示仰起来）
	# 设计：6 点 / 18 点 时太阳刚好在地平线，pitch = -90°（光水平射），正午 pitch = -90° 时太阳在头顶
	# 实际上希望正午太阳在“上方斜下60°”即目前 -60°，那么推 pitch = -（90 - elevation_deg）
	var elevation_deg := ((hour - 12.0) / 12.0) * -90.0 # 6点=+90，12点=0，18点=-90
	var pitch := -(90.0 - elevation_deg) # 6点 = -180（半夜），12 点 = -90（太阳头顶），18 点 = 0（水平）
	# 上面公式会有 0 点 = pitch = -45（、太阳从侧面过来），不符合“夜裡太阳应在下方”。
	# 重新推：设 6 点 = -90°（日出，太阳刚好地平线）、12 点 = -60°（正顶斜下 60°，即主人原定值）、18 点 = -90°（日落）
	# 中间用余弦曲线从 -90 平滑到 -60 再回到 -90
	# hour 0..6 与 18..24 都是 -90（夜晚太阳在地平线以下）
	if hour < 6.0 or hour > 18.0:
		return -90.0
	var phase := (hour - 6.0) / 12.0 # 6点=0，12点=0.5，18点=1
	var dip := cos(phase * PI) # 6点/18点=cos(0)=1，12点=cos(PI/2)=0 → 太阳从“-90°水平”上升到“-60°深低”再回到“-90°水平”
	return lerpf(-90.0, -60.0, 1.0 - dip) # 6点/18点=-90，12点=-60


func _compute_sun_energy(hour: float) -> float:
	# 仅 6 点到 18 点有太阳能量，值为 0 到 1，中间凸起为二次曲线。
	if hour < 6.0 or hour > 18.0:
		return 0.0
	var phase := (hour - 6.0) / 12.0 # 0..1
	# 6/18点=0，12点=1。能量按 sin(phase * PI) 曲线，正午最高。
	var factor := sin(phase * PI)
	return SUN_ENERGY * factor


func get_clock_string() -> String:
	# 格式 HH:MM（0 点 = 00:00）。供 HUD 计时器区显示。
	var hour := int(floor(time_of_day)) % 24
	var minute := int(floor(fmod(time_of_day, 1.0) * 60.0))
	return "%02d:%02d" % [hour, minute]


func _process(delta: float) -> void:
	if time_scale <= 0.0:
		return
	# time_scale 定义为“1 游戏小时 = 多少 真实秒”。
	# 例如 time_scale = 60.0 表示 60 真实秒走 1 游戏小时。
	# 那么 1 真实秒推进 1 / time_scale / 3600 游戏小时。
	time_of_day = fmod(time_of_day + delta / 3600.0 / maxf(0.001, time_scale), 24.0)
	_apply_time_of_day()


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
