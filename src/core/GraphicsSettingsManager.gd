extends Node
## 全局画面设置与持久化。所有正式 WorldEnvironment 注册后共享同一套玩家设置。

signal settings_changed(settings: Dictionary)

const SAVE_PATH := "user://graphics_settings.cfg"
const SECTION := "graphics"
const DEFAULT_SETTINGS := {
	"anti_aliasing": "taa",
	"bloom": true,
	"ssao": true,
	"ssil": true,
	"ssr": true,
	"indirect_diffuse_quality": "high",
	"volumetric_fog": true,
	"distance_fog": true,
	"shadow_quality": "high",
	"color_grading": true,
}
const AA_MODES := ["off", "fxaa", "msaa_2x", "msaa_4x", "msaa_8x", "taa"]
const SHADOW_QUALITY_MODES := ["low", "medium", "high"]
const INDIRECT_DIFFUSE_QUALITY_MODES := ["low", "medium", "high"]
const INDIRECT_DIFFUSE_PROFILES := {
	"low": {
		"cascades": 2,
		"max_distance": 90.0,
		"bounce_feedback": 0.24,
		"energy": 0.72,
	},
	"medium": {
		"cascades": 3,
		"max_distance": 140.0,
		"bounce_feedback": 0.36,
		"energy": 0.82,
	},
	"high": {
		# Godot原始高档基线：4级联、204.8米、自动得出0.2米最小体素。
		"cascades": 4,
		"max_distance": 204.8,
		"bounce_feedback": 0.46,
		"energy": 0.88,
	},
}
const SHADOW_ATLAS_SIZES := {
	"low": 1024,
	"medium": 2048,
	"high": 4096,
}
const SHADOW_FILTER_QUALITIES := {
	"low": RenderingServer.SHADOW_QUALITY_HARD,
	"medium": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	# 保留改造前项目默认的 Soft Low（2），最高档画面与开销不变。
	"high": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
}

var _settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var _environments: Array[WeakRef] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	call_deferred("_apply_all")


func get_settings_snapshot() -> Dictionary:
	return _settings.duplicate(true)


func get_value(key: String, fallback: Variant = null) -> Variant:
	return _settings.get(key, fallback)


func is_enabled(key: String) -> bool:
	# 动态阴影承载太阳、手电和房间灯的玩法信息，不存在关闭档。
	# SDFGI 旧调用同样保持兼容：新三级档均开启太阳/天空间接漫反射。
	if key == "shadows" or key == "sdfgi":
		return true
	return bool(_settings.get(key, false))


func get_shadow_quality() -> String:
	return str(_settings.get("shadow_quality", "high"))


func get_indirect_diffuse_quality() -> String:
	return str(_settings.get("indirect_diffuse_quality", "high"))


func get_shadow_atlas_size() -> int:
	return int(SHADOW_ATLAS_SIZES.get(get_shadow_quality(), 4096))


func set_value(key: String, value: Variant, save := true) -> bool:
	if not DEFAULT_SETTINGS.has(key):
		return false
	var sanitized: Variant = _sanitize_value(key, value)
	if _settings.get(key) == sanitized:
		return true
	_settings[key] = sanitized
	_apply_all()
	if save:
		_save_settings()
	settings_changed.emit(get_settings_snapshot())
	return true


func apply_high_quality_defaults() -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	_apply_all()
	_save_settings()
	settings_changed.emit(get_settings_snapshot())


func register_environment(environment: Environment) -> void:
	if environment == null:
		return
	_prune_environments()
	for reference in _environments:
		if reference.get_ref() == environment:
			_apply_environment(environment)
			return
	_environments.append(weakref(environment))
	_apply_environment(environment)


func apply_to_environment(environment: Environment) -> void:
	_apply_environment(environment)


func get_renderer_summary() -> String:
	var method := RenderingServer.get_current_rendering_method()
	var device := RenderingServer.get_current_rendering_driver_name()
	return "%s / %s" % [method, device]


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for key in DEFAULT_SETTINGS.keys():
		if config.has_section_key(SECTION, key):
			_settings[key] = _sanitize_value(key, config.get_value(SECTION, key))
	# 旧版 shadows=false 不再迁移为关闭；玩法阴影统一进入当前高档基线。
	if not config.has_section_key(SECTION, "shadow_quality"):
		_settings["shadow_quality"] = "high"
	# 旧版只有SDFGI开关：开启迁移为完整高档，关闭迁移为仍保留漫反射的低档。
	if not config.has_section_key(SECTION, "indirect_diffuse_quality"):
		_settings["indirect_diffuse_quality"] = (
			"high" if bool(config.get_value(SECTION, "sdfgi", true)) else "low"
		)


func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in DEFAULT_SETTINGS.keys():
		config.set_value(SECTION, key, _settings[key])
	config.save(SAVE_PATH)


func _sanitize_value(key: String, value: Variant) -> Variant:
	if key == "anti_aliasing":
		var mode := str(value)
		return mode if mode in AA_MODES else DEFAULT_SETTINGS[key]
	if key == "shadow_quality":
		var mode := str(value)
		return mode if mode in SHADOW_QUALITY_MODES else DEFAULT_SETTINGS[key]
	if key == "indirect_diffuse_quality":
		var mode := str(value)
		return mode if mode in INDIRECT_DIFFUSE_QUALITY_MODES else DEFAULT_SETTINGS[key]
	return bool(value)


func _apply_all() -> void:
	_apply_viewport_antialiasing()
	_apply_shadow_quality()
	_prune_environments()
	for reference in _environments:
		var environment := reference.get_ref() as Environment
		if environment != null:
			_apply_environment(environment)
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.refresh_registered_quality()


func _apply_viewport_antialiasing() -> void:
	var viewport := get_tree().root
	if viewport == null:
		return
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	match str(_settings.get("anti_aliasing", "taa")):
		"fxaa":
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"msaa_2x":
			viewport.msaa_3d = Viewport.MSAA_2X
		"msaa_4x":
			viewport.msaa_3d = Viewport.MSAA_4X
		"msaa_8x":
			viewport.msaa_3d = Viewport.MSAA_8X
		"taa":
			viewport.use_taa = true
	viewport.scaling_3d_scale = 1.0


func _apply_shadow_quality() -> void:
	var viewport := get_tree().root
	if viewport == null:
		return
	var mode := get_shadow_quality()
	var atlas_size := int(SHADOW_ATLAS_SIZES.get(mode, 4096))
	var filter_quality := int(
		SHADOW_FILTER_QUALITIES.get(mode, RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	)
	var directional_16_bits := bool(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/16_bits", true
	))
	var positional_16_bits := bool(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/positional_shadow/atlas_16_bits", true
	))
	RenderingServer.directional_shadow_atlas_set_size(atlas_size, directional_16_bits)
	RenderingServer.viewport_set_positional_shadow_atlas_size(
		viewport.get_viewport_rid(), atlas_size, positional_16_bits
	)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter_quality)


func _apply_environment(environment: Environment) -> void:
	# 高档默认以“清晰、层次、克制”为目标：辉光不吞字，AO不压死暗部，
	# 体积雾只建立纵深，不覆盖顶视角战斗轮廓。
	_set_property(environment, "glow_enabled", is_enabled("bloom"))
	_set_property(environment, "glow_intensity", 0.72)
	_set_property(environment, "glow_strength", 0.92)
	_set_property(environment, "glow_bloom", 0.08)
	_set_property(environment, "glow_hdr_threshold", 1.08)
	_set_property(environment, "glow_hdr_scale", 1.65)
	_set_property(environment, "glow_normalized", true)

	_set_property(environment, "ssao_enabled", is_enabled("ssao"))
	_set_property(environment, "ssao_radius", 1.25)
	_set_property(environment, "ssao_intensity", 1.65)
	_set_property(environment, "ssao_power", 1.28)
	_set_property(environment, "ssao_detail", 0.72)
	_set_property(environment, "ssao_horizon", 0.06)

	_set_property(environment, "ssil_enabled", is_enabled("ssil"))
	_set_property(environment, "ssil_radius", 3.2)
	_set_property(environment, "ssil_intensity", 0.92)
	_set_property(environment, "ssil_sharpness", 0.88)
	_set_property(environment, "ssil_normal_rejection", 1.0)

	_set_property(environment, "ssr_enabled", is_enabled("ssr"))
	_set_property(environment, "ssr_max_steps", 96)
	_set_property(environment, "ssr_fade_in", 0.18)
	_set_property(environment, "ssr_fade_out", 2.4)
	_set_property(environment, "ssr_depth_tolerance", 0.16)

	# 三档都保持太阳与天空的动态漫反射；档位只收缩体素覆盖和精度，
	# 不再提供会使场景突然失去反弹光的关闭入口。
	var indirect_profile: Dictionary = INDIRECT_DIFFUSE_PROFILES.get(
		get_indirect_diffuse_quality(), INDIRECT_DIFFUSE_PROFILES["high"]
	)
	_set_property(environment, "sdfgi_enabled", true)
	_set_property(environment, "sdfgi_use_occlusion", true)
	_set_property(environment, "sdfgi_read_sky_light", true)
	_set_property(environment, "sdfgi_cascades", int(indirect_profile["cascades"]))
	# max_distance会按级联数量自动重算min_cell_size，不能把两者作为独立值连写。
	_set_property(environment, "sdfgi_max_distance", float(indirect_profile["max_distance"]))
	_set_property(environment, "sdfgi_bounce_feedback", float(indirect_profile["bounce_feedback"]))
	_set_property(environment, "sdfgi_energy", float(indirect_profile["energy"]))
	_set_property(environment, "sdfgi_normal_bias", 1.1)
	_set_property(environment, "sdfgi_probe_bias", 1.1)

	_set_property(environment, "volumetric_fog_enabled", is_enabled("volumetric_fog"))
	_set_property(environment, "volumetric_fog_density", float(environment.get_meta("presentation_volumetric_fog_density", 0.018)))
	_set_property(environment, "volumetric_fog_albedo", Color(0.72, 0.80, 0.86))
	_set_property(environment, "volumetric_fog_emission", Color(0.015, 0.022, 0.030))
	_set_property(environment, "volumetric_fog_emission_energy", 0.22)
	_set_property(environment, "volumetric_fog_length", 56.0)
	_set_property(environment, "volumetric_fog_detail_spread", 1.6)
	_set_property(environment, "volumetric_fog_ambient_inject", 0.58)
	_set_property(environment, "volumetric_fog_temporal_reprojection_enabled", true)
	_set_property(environment, "volumetric_fog_temporal_reprojection_amount", 0.90)

	_set_property(environment, "fog_enabled", is_enabled("distance_fog"))
	_set_property(environment, "adjustment_enabled", is_enabled("color_grading"))
	_set_property(environment, "adjustment_brightness", 1.01)
	_set_property(environment, "adjustment_contrast", 1.07)
	_set_property(environment, "adjustment_saturation", 1.04)
	_set_property(environment, "tonemap_mode", Environment.TONE_MAPPER_FILMIC)
	_set_property(environment, "tonemap_exposure", 1.12)
	_set_property(environment, "tonemap_white", 1.18)


func _set_property(object: Object, property_name: String, value: Variant) -> void:
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			object.set(property_name, value)
			return


func _prune_environments() -> void:
	for index in range(_environments.size() - 1, -1, -1):
		if _environments[index].get_ref() == null:
			_environments.remove_at(index)
