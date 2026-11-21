extends RefCounted

const POWERBOX_SHADER := preload("library_powerbox.gdshader")
const UNLIT_SOURCE := "Archanor VFX/Epic Toon FX/ETFX_PowerboxUnlit"
const ASSET_DIR := "res://assets/art/vfx/library/UnityVFXLibrary/Assets"
static var _metal_shaders: Dictionary = {}


static func supports(settings: Dictionary) -> bool:
	var shader_name := str(settings.get("shader", ""))
	return shader_name == UNLIT_SOURCE or (shader_name == "Standard" and (
		str(settings.get("name", "")).begins_with("power_metal_") or
		str(settings.get("source_path", settings.get("path", ""))).contains("/Powerbox/Metal/")))


# 返回 ShaderMaterial：可直接接入现有绘制器的 geometry_mode 和 per-draw uniforms。
# 辅助贴图以 Unity 属性名入参；若未传入，则按源引用查找现有共享资源。
static func make(settings: Dictionary, texture: Texture2D, auxiliary: Dictionary) -> Material:
	if not supports(settings):
		return null
	var material := ShaderMaterial.new()
	var missing: Array[String] = []
	var limitations: Array[String] = []
	if settings.get("shader") == UNLIT_SOURCE:
		material.shader = POWERBOX_SHADER
		_bind(material, "icon_texture", settings, auxiliary, "_Icon", missing)
		_bind(material, "background_texture", settings, auxiliary, "_Background", missing)
		material.set_shader_parameter("background_tint", _color(settings.get("_BackgroundTint"), Color(1.0, 0.0, 0.05511808, 0.0)))
		material.set_shader_parameter("icon_tint", _color(settings.get("_IconTint"), Color(0.0, 0.0, 0.0, 0.0)))
		material.set_shader_parameter("background_brightness", float(settings.get("_BackgroundBrightness", 1.0)))
		material.set_shader_parameter("background_contrast", float(settings.get("_BackgroundContrast", 1.0)))
		material.set_shader_parameter("icon_brightness", float(settings.get("_IconBrightness", 1.0)))
		material.set_shader_parameter("icon_contrast", float(settings.get("_IconContrast", 1.0)))
		var mesh_uv := _texture_transform(settings, "_texcoord")
		var background_uv := _texture_transform(settings, "_Background")
		var background_scale := Vector2(background_uv.x, background_uv.y)
		var background_offset := Vector2(mesh_uv.z, mesh_uv.w) * background_scale + Vector2(background_uv.z, background_uv.w)
		background_scale *= Vector2(mesh_uv.x, mesh_uv.y)
		material.set_shader_parameter("background_scale", background_scale)
		material.set_shader_parameter("background_offset", _flip_offset(background_scale, background_offset))
		var icon_scale := float(settings.get("_IconScale", 2.0))
		var icon_scale_2d := Vector2(mesh_uv.x, mesh_uv.y) * icon_scale
		var icon_offset := Vector2(mesh_uv.z, mesh_uv.w) * icon_scale + _vec2(settings.get("_IconOffset"), Vector2(0.0, -1.0))
		material.set_shader_parameter("icon_scale", icon_scale_2d)
		material.set_shader_parameter("icon_offset", _flip_offset(icon_scale_2d, icon_offset))
	else:
		var alpha_mode := clampi(int(settings.get("_Mode", 0)), 0, 3)
		var depth_write := float(settings.get("_ZWrite", 1.0 if alpha_mode < 2 else 0.0)) > 0.5
		var specular := float(settings.get("_SpecularHighlights", 1.0)) > 0.5 and not _has_keyword(settings, "_SPECULARHIGHLIGHTS_OFF")
		material.shader = _metal_shader(alpha_mode, depth_write, specular)
		_bind(material, "main_texture", settings, auxiliary, "_MainTex", missing, texture)
		var gloss_map := _bind(material, "metallic_gloss_texture", settings, auxiliary, "_MetallicGlossMap", missing)
		var bump_map := _bind(material, "bump_texture", settings, auxiliary, "_BumpMap", missing)
		_bind(material, "emission_texture", settings, auxiliary, "_EmissionMap", missing)
		var keywords_exported := settings.has("keywords")
		material.set_shader_parameter("use_metallic_gloss", gloss_map != null and (not keywords_exported or _has_keyword(settings, "_METALLICGLOSSMAP")))
		material.set_shader_parameter("use_bump", bump_map != null and (not keywords_exported or _has_keyword(settings, "_NORMALMAP")))
		var emission_color := _color(settings.get("_EmissionColor"), Color.BLACK)
		material.set_shader_parameter("use_emission", _has_keyword(settings, "_EMISSION") if keywords_exported else maxf(emission_color.r, maxf(emission_color.g, emission_color.b)) > 0.0)
		material.set_shader_parameter("emission_tint", emission_color)
		material.set_shader_parameter("tint", _color(settings.get("_Color"), Color.WHITE))
		material.set_shader_parameter("metallic", float(settings.get("_Metallic", 0.0)))
		material.set_shader_parameter("roughness", 1.0 - clampf(float(settings.get("_Glossiness", 0.5)), 0.0, 1.0))
		material.set_shader_parameter("gloss_map_scale", float(settings.get("_GlossMapScale", 1.0)))
		material.set_shader_parameter("smoothness_albedo_alpha", int(settings.get("_SmoothnessTextureChannel", 0)) == 1 or _has_keyword(settings, "_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A"))
		material.set_shader_parameter("bump_scale", float(settings.get("_BumpScale", 1.0)))
		material.set_shader_parameter("cutoff", float(settings.get("_Cutoff", 0.5)))
		var main_uv := _texture_transform(settings, "_MainTex")
		var main_scale := Vector2(main_uv.x, main_uv.y)
		material.set_shader_parameter("main_scale", main_scale)
		material.set_shader_parameter("main_offset", _flip_offset(main_scale, Vector2(main_uv.z, main_uv.w)))
		limitations.append("unity_standard_vs_godot_brdf_and_light_environment")
		if float(settings.get("_GlossyReflections", 1.0)) < 0.5 or _has_keyword(settings, "_GLOSSYREFLECTIONS_OFF"):
			limitations.append("unity_indirect_gloss_toggle_not_matched_by_godot_pbr")
	material.set_meta("powerbox_missing_textures", missing)
	material.set_meta("powerbox_limitations", limitations)
	return material


static func _metal_shader(alpha_mode: int, depth_write: bool, specular: bool) -> Shader:
	var key := Vector3i(alpha_mode, int(depth_write), int(specular))
	if not _metal_shaders.has(key):
		var shader := Shader.new()
		var depth := "depth_draw_never"
		if depth_write:
			depth = "depth_draw_opaque" if alpha_mode < 2 else "depth_draw_always"
		var blend := "blend_premul_alpha" if alpha_mode == 3 else "blend_mix"
		var highlight := "specular_schlick_ggx" if specular else "specular_disabled"
		shader.code = POWERBOX_SHADER.code.replace(
			"unshaded, cull_back, depth_draw_opaque, fog_disabled", "cull_back, %s, %s, %s" % [depth, blend, highlight]
		).replace("#define POWERBOX_PBR 0", "#define POWERBOX_PBR 1").replace(
			"#define POWERBOX_ALPHA_MODE 0", "#define POWERBOX_ALPHA_MODE %d" % alpha_mode
		)
		_metal_shaders[key] = shader
	return _metal_shaders[key]


static func _bind(material: ShaderMaterial, parameter: String, settings: Dictionary, auxiliary: Dictionary, property: String, missing: Array[String], primary: Texture2D = null) -> Texture2D:
	var texture := auxiliary.get(property) as Texture2D
	if texture == null:
		texture = primary
	var tex_props: Dictionary = settings.get("texture_properties", {})
	var spec: Dictionary = tex_props.get(property, {})
	var source: Variant = spec.get("texture_ref", settings.get(property))
	if texture == null and source is Texture2D:
		texture = source
	if texture == null and source is Dictionary:
		var asset_key := str(source.get("asset_key", ""))
		if not asset_key.is_empty():
			var path := "%s/tex_%s.res" % [ASSET_DIR, asset_key.replace(":", "_")]
			if ResourceLoader.exists(path, "Texture2D"):
				texture = load(path) as Texture2D
	if texture == null and (source != null or property in ["_Icon", "_Background"]):
		missing.append(property)
	if texture != null:
		material.set_shader_parameter(parameter, texture)
	return texture


static func _texture_transform(settings: Dictionary, property: String) -> Vector4:
	var tex_props: Dictionary = settings.get("texture_properties", {})
	var spec: Dictionary = tex_props.get(property, {})
	var scale := _vec2(spec.get("scale", settings.get("texture_scale") if property == "_MainTex" else null), Vector2.ONE)
	var offset := _vec2(spec.get("offset", settings.get("texture_offset") if property == "_MainTex" else null), Vector2.ZERO)
	return Vector4(scale.x, scale.y, offset.x, offset.y)


static func _flip_offset(scale: Vector2, offset: Vector2) -> Vector2:
	return Vector2(offset.x, 1.0 - scale.y - offset.y)


static func _has_keyword(settings: Dictionary, keyword: String) -> bool:
	return keyword in settings.get("keywords", [])


static func _color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Array and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)
	return fallback


static func _vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2 or value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
