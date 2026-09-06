extends Node3D
## Turns the Blender-authored palette emission into readable HDR glow.
## Strong fixtures also receive small environment-only light pools. This remains
## presentation-only and never participates in PlayerVision3D visibility.

const PALETTE := preload("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
const SOFT_EMISSION_TARGET := 2.35
const FIXTURE_PROFILES := [
	{"name": "BASE_CAMP霓虹标识", "offset": Vector3(0, 0, 0.32), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "二楼GOOD_VIBES霓虹", "offset": Vector3(0, 0, 0.32), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "楼梯墙STAY_CURIOUS标识", "offset": Vector3(0.32, 0, 0), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "33_暖橙床头灯_资产包", "offset": Vector3.ZERO, "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "梯下壁灯生活点缀", "offset": Vector3(0, 0, 0.20), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "84_东面圆形工业吊灯_资产包", "offset": Vector3(0, -0.35, 0), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "61_仓库防爆吊灯组_资产包", "offset": Vector3(0, -0.35, 0), "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "62_主通道应急灯组_资产包", "offset": Vector3.ZERO, "cool": false, "spill": true, "target": 2.35, "energy": 2.40, "range": 3.8},
	{"name": "50_二楼分层照明支持_资产包", "offset": Vector3.ZERO, "cool": false, "spill": false, "target": 2.35},
	{"name": "14_西北贴墙L型楼梯_资产包", "offset": Vector3.ZERO, "cool": false, "spill": false, "target": 2.40},
]

var _enhanced_surfaces := 0
var _strong_fixtures := 0
var _spill_lights := 0
var _processed_surfaces := {}


func _ready() -> void:
	var palette_image := PALETTE.get_image()
	if palette_image.is_compressed():
		palette_image.decompress()
	for profile in FIXTURE_PROFILES:
		var fixture := find_child(str(profile.name), true, false) as Node3D
		if fixture == null:
			push_error("BASE_GLOW_FIXTURE_MISSING: %s" % profile.name)
			continue
		_strong_fixtures += 1
		_enhance_fixture(fixture, palette_image, profile)
	# Screens, status strips and utility emitters share the same HDR target. Their
	# authored palette cells stay unchanged and they do not create extra lights.
	for node in find_children("*", "MeshInstance3D", true, false):
		_enhance_mesh(node as MeshInstance3D, palette_image, SOFT_EMISSION_TARGET, false)


func get_presentation_snapshot() -> Dictionary:
	return {
		"strong_fixtures": _strong_fixtures,
		"enhanced_surfaces": _enhanced_surfaces,
		"spill_lights": _spill_lights,
	}


func _enhance_fixture(fixture: Node3D, palette_image: Image, profile: Dictionary) -> void:
	var bounds := AABB()
	var has_bounds := false
	var tint := Color.BLACK
	var sample_count := 0
	for node in fixture.find_children("*", "MeshInstance3D", true, false):
		var result := _enhance_mesh(
			node as MeshInstance3D, palette_image, float(profile.target), true
		)
		if int(result.get("sample_count", 0)) == 0:
			continue
		tint += result.tint
		sample_count += int(result.sample_count)
		var visual_bounds: AABB = result.bounds
		if not has_bounds:
			bounds = visual_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(visual_bounds)
	if not bool(profile.spill) or not has_bounds or sample_count == 0:
		return
	tint /= float(sample_count)
	var maximum := maxf(tint.r, maxf(tint.g, tint.b))
	tint = Color(tint.r / maximum, tint.g / maximum, tint.b / maximum)
	if bool(profile.cool):
		# A less saturated blue-white reads as light after filmic tonemapping.
		tint = tint.lerp(Color.WHITE, 0.34)
	_add_light_spill(
		fixture,
		bounds.get_center() + profile.offset,
		tint,
		float(profile.energy),
		float(profile.range)
	)


func _enhance_mesh(
	visual: MeshInstance3D,
	palette_image: Image,
	target: float,
	collect_samples: bool
) -> Dictionary:
	var result := {"tint": Color.BLACK, "sample_count": 0, "bounds": AABB()}
	if visual == null or visual.mesh == null:
		return result
	var has_bounds := false
	for surface in range(visual.mesh.get_surface_count()):
		var uses_instance_override := visual.material_override != null
		if uses_instance_override and surface > 0:
			continue
		var key := (
			"%d:override" % visual.get_instance_id()
			if uses_instance_override
			else "%d:%d" % [visual.get_instance_id(), surface]
		)
		if _processed_surfaces.has(key):
			continue
		var original := visual.get_active_material(surface) as BaseMaterial3D
		if original == null or not original.emission_enabled:
			continue
		var arrays := visual.mesh.surface_get_arrays(surface)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var peak := 0.0
		for index in range(uvs.size()):
			var uv := uvs[index]
			var color := palette_image.get_pixel(
				clampi(int(uv.x * palette_image.get_width()), 0, palette_image.get_width() - 1),
				clampi(int(uv.y * palette_image.get_height()), 0, palette_image.get_height() - 1)
			)
			var linear := color.srgb_to_linear()
			peak = maxf(peak, maxf(linear.r, maxf(linear.g, linear.b)))
			if collect_samples:
				result.tint += color
				result.sample_count += 1
				var point := to_local(visual.to_global(vertices[index]))
				if not has_bounds:
					result.bounds = AABB(point, Vector3.ZERO)
					has_bounds = true
				else:
					result.bounds = result.bounds.expand(point)
		var material := original.duplicate() as BaseMaterial3D
		material.resource_name = original.resource_name + (
			"_基地灯具HDR" if collect_samples else "_基地微光HDR"
		)
		material.emission = Color.WHITE
		material.emission_texture = PALETTE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = maxf(
			original.emission_energy_multiplier,
			clampf(target / maxf(peak, 0.001), target, 128.0)
		)
		if uses_instance_override:
			visual.material_override = material
		else:
			visual.set_surface_override_material(surface, material)
		_processed_surfaces[key] = true
		_enhanced_surfaces += 1
	return result


func _add_light_spill(
	fixture: Node3D,
	world_position: Vector3,
	tint: Color,
	energy: float,
	range_meters: float
) -> void:
	var light := OmniLight3D.new()
	light.name = "PaletteLightSpill"
	fixture.add_child(light)
	light.global_position = to_global(world_position)
	light.light_color = tint
	light.light_energy = energy
	light.light_specular = 0.15
	light.omni_range = range_meters
	light.omni_attenuation = 1.4
	light.light_cull_mask = 1
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.18
	light.distance_fade_enabled = true
	light.distance_fade_begin = 20.0
	light.distance_fade_length = 6.0
	_spill_lights += 1
