@tool
extends "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
## Warm linen shades and candle flames; shared geometry and PaletteUV stay intact.

func _configure_material(material: BaseMaterial3D, palette: Texture2D) -> void:
	super._configure_material(material, palette)
	if not String(material.resource_name).begins_with("04_柔和自发光"):
		return
	material.albedo_color = Color(1.0, 0.72, 0.38, 1.0)
	material.emission = Color(1.0, 0.65, 0.28, 1.0)
	material.emission_energy_multiplier = 0.8
	material.metallic = 0.0
	material.roughness = 0.72
