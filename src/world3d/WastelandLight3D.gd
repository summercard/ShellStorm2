class_name WastelandLight3D
extends Node3D
## 可复用废土灯具：支持室外路灯与室内中央顶灯两种装配。

@export var light_color := Color(0.34, 0.75, 1.0)
@export_range(0.2, 48.0, 0.1) var energy := 4.6
@export_range(2.0, 64.0, 0.5) var light_range := 12.0
@export var failing := true
@export var flicker_seed := 1
@export var cast_shadow := false
@export_flags_3d_render var light_cull_mask := 3
@export_enum("street", "ceiling") var fixture_style := "street"
@export var light_enabled := true

var _light: OmniLight3D
var _lens_material: StandardMaterial3D
var _pool_material: StandardMaterial3D
var _elapsed := 0.0
var _built := false
var _runtime_active := true
var _runtime_flicker := true
var _runtime_shadow_allowed := true


func configure(
	color: Color,
	p_energy: float,
	p_range: float,
	seed: int,
	shadow := false,
	is_failing := true,
	p_fixture_style := "street"
) -> void:
	light_color = color
	energy = p_energy
	light_range = p_range
	flicker_seed = seed
	cast_shadow = shadow
	failing = is_failing
	fixture_style = p_fixture_style if p_fixture_style in ["street", "ceiling"] else "street"
	if _built:
		_apply_configuration()


func _ready() -> void:
	_build_fixture()
	_apply_configuration()
	_built = true


func _process(delta: float) -> void:
	if not _runtime_active:
		return
	_elapsed += delta
	if _light == null:
		return
	if not light_enabled:
		_light.visible = false
		return
	var slow_wave := sin(_elapsed * (1.15 + float(flicker_seed % 5) * 0.08) + float(flicker_seed)) * 0.07
	var micro_wave := sin(_elapsed * 7.3 + float(flicker_seed) * 1.71) * 0.025
	var factor := 1.0 + slow_wave + micro_wave
	if failing:
		var cycle := fmod(_elapsed + float(flicker_seed) * 0.73, 7.6 + float(flicker_seed % 4) * 0.9)
		if cycle > 7.15 and cycle < 7.42:
			factor = 0.10
	_light.light_energy = energy * factor
	if _pool_material != null:
		_pool_material.albedo_color.a = 0.12 + clampf(factor, 0.0, 1.2) * 0.07


func set_runtime_active(active: bool, allow_shadow := false, allow_flicker := true) -> void:
	_runtime_active = active
	_runtime_flicker = allow_flicker
	_runtime_shadow_allowed = allow_shadow
	set_process(active and allow_flicker)
	visible = active
	if _light != null:
		_light.visible = active and light_enabled
		_light.shadow_enabled = active and light_enabled and allow_shadow and cast_shadow
		if active and light_enabled and not allow_flicker:
			_light.light_energy = energy
	_update_lens_state()


func set_light_enabled(enabled: bool) -> void:
	light_enabled = enabled
	set_process(_runtime_active and _runtime_flicker and light_enabled)
	if _light != null:
		_light.visible = _runtime_active and light_enabled
		_light.shadow_enabled = (
			_runtime_active
			and light_enabled
			and _runtime_shadow_allowed
			and cast_shadow
		)
	_update_lens_state()


func is_light_enabled() -> bool:
	return light_enabled


func get_snapshot() -> Dictionary:
	return {
		"color": light_color,
		"energy": energy,
		"range": light_range,
		"failing": failing,
		"has_fixture": get_node_or_null("Fixture") != null,
		"has_light_pool": get_node_or_null("LightPool") != null,
		"fixture_style": fixture_style,
		"light_enabled": light_enabled,
		"illumination_active": _runtime_active and light_enabled,
		"runtime_active": _runtime_active,
		"runtime_flicker": _runtime_flicker,
		"runtime_shadow_allowed": _runtime_shadow_allowed,
		"shadow_capable": cast_shadow,
		"shadow_enabled": _light != null and _light.shadow_enabled,
		"light_cull_mask": light_cull_mask,
		"is_3d": true,
	}


func _build_fixture() -> void:
	var metal := _material(Color(0.07, 0.085, 0.09), 0.72, 0.42)
	_lens_material = _material(light_color, 0.08, 0.24, true)
	_light = OmniLight3D.new()
	_light.name = "LampLight"
	if fixture_style == "ceiling":
		_add_box("CeilingMount", Vector3(0, 2.72, 0), Vector3(1.35, 0.12, 0.72), metal)
		_add_box("Fixture", Vector3(0, 2.61, 0), Vector3(1.08, 0.20, 0.54), metal)
		_add_box("Lens", Vector3(0, 2.49, 0), Vector3(0.88, 0.045, 0.40), _lens_material)
		_light.position = Vector3(0, 2.34, 0)
	else:
		_add_box("Pole", Vector3(0, 1.25, 0), Vector3(0.13, 2.5, 0.13), metal)
		_add_box("Arm", Vector3(0.30, 2.40, 0), Vector3(0.72, 0.10, 0.10), metal)
		_add_box("Fixture", Vector3(0.62, 2.31, 0), Vector3(0.52, 0.20, 0.34), metal)
		_add_box("Lens", Vector3(0.62, 2.18, 0), Vector3(0.40, 0.045, 0.25), _lens_material)
		_light.position = Vector3(0.62, 2.12, 0)
		_build_light_pool()
	add_child(_light)


func _build_light_pool() -> void:
	var pool_mesh := CylinderMesh.new()
	pool_mesh.top_radius = 2.7
	pool_mesh.bottom_radius = 3.2
	pool_mesh.height = 0.018
	pool_mesh.radial_segments = 32
	_pool_material = _material(Color(light_color.r, light_color.g, light_color.b, 0.18), 0.0, 1.0, true, true)
	_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_mesh.material = _pool_material
	var pool := MeshInstance3D.new()
	pool.name = "LightPool"
	pool.position = Vector3(0.62, 0.025, 0)
	pool.mesh = pool_mesh
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)


func _apply_configuration() -> void:
	if _light != null:
		_light.light_color = light_color
		_light.light_energy = energy
		_light.omni_range = light_range
		_light.shadow_enabled = (
			_runtime_active
			and light_enabled
			and _runtime_shadow_allowed
			and cast_shadow
		)
		_light.light_cull_mask = light_cull_mask
	if _lens_material != null:
		_lens_material.albedo_color = light_color
		_lens_material.emission = light_color
	if _pool_material != null:
		_pool_material.albedo_color = Color(light_color.r, light_color.g, light_color.b, 0.18)
		_pool_material.emission = light_color.darkened(0.22)
	_update_lens_state()


func _update_lens_state() -> void:
	if _lens_material == null:
		return
	_lens_material.emission_enabled = light_enabled and _runtime_active
	_lens_material.albedo_color = light_color if light_enabled and _runtime_active else Color(0.10, 0.12, 0.12)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	add_child(instance)
	return instance


func _material(color: Color, metallic: float, roughness: float, emission := false, unshaded := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b, 1.0)
		# 灯罩只负责可读性，不再用高发光值把附近地砖推成过曝色块。
		material.emission_energy_multiplier = 0.72
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
