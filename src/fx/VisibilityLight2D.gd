class_name VisibilityLight2D
extends PointLight2D
## A rendered Godot light that also supplies its visibility footprint to gameplay logic.

enum LightShape { RADIAL, FLASHLIGHT }

const TEXTURE_SIZE := 512
const LIGHT_MASK := 1
const CONE_EDGE_SOFTNESS := PI * 3.0 / 180.0
const RANGE_EDGE_SOFTNESS := 18.0
const WORLD_Z_MIN := -4096
const WORLD_Z_MAX := 4096

@export var light_shape: LightShape = LightShape.RADIAL
@export_range(16.0, 1200.0, 1.0) var light_radius: float = 180.0
@export_range(0.0, 360.0, 1.0) var cone_angle_degrees: float = 100.0
@export_range(0.0, 256.0, 1.0) var near_radius: float = 0.0
@export_range(0.25, 4.0, 0.05) var radial_falloff_power: float = 2.0
@export var contributes_to_visibility: bool = true


func _ready() -> void:
	refresh_light()


func configure_flashlight(radius: float, cone_angle_radians: float, p_near_radius: float) -> void:
	light_shape = LightShape.FLASHLIGHT
	light_radius = radius
	cone_angle_degrees = rad_to_deg(cone_angle_radians)
	near_radius = p_near_radius
	if is_inside_tree():
		refresh_light()


func refresh_light() -> void:
	texture = _make_light_texture()
	texture_scale = light_radius / (TEXTURE_SIZE * 0.5)
	shadow_enabled = true
	shadow_item_cull_mask = LIGHT_MASK
	range_z_min = WORLD_Z_MIN
	range_z_max = WORLD_Z_MAX


func get_visibility_descriptor() -> Dictionary:
	if not enabled or not contributes_to_visibility:
		return {}
	return {
		"position": global_position,
		"radius": light_radius,
		"shape": "flashlight" if light_shape == LightShape.FLASHLIGHT else "radial",
		"direction": Vector2.RIGHT.rotated(global_rotation),
		"cone_angle": deg_to_rad(cone_angle_degrees),
		"near_radius": near_radius,
	}


func _make_light_texture() -> ImageTexture:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEXTURE_SIZE * 0.5, TEXTURE_SIZE * 0.5)
	var texture_radius := TEXTURE_SIZE * 0.5
	var cone_half_angle := deg_to_rad(cone_angle_degrees) * 0.5
	var near_texture_radius := texture_radius * near_radius / maxf(light_radius, 1.0)
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var offset := Vector2(float(x), float(y)) - center
			var distance := offset.length()
			var strength := _radial_falloff(distance, texture_radius)
			if light_shape == LightShape.FLASHLIGHT:
				strength = _flashlight_strength(offset, distance, texture_radius, cone_half_angle, near_texture_radius)
			image.set_pixel(x, y, Color(strength, strength, strength, strength))
	return ImageTexture.create_from_image(image)


func _flashlight_strength(
	offset: Vector2, distance: float, radius: float, half_angle: float, near_texture_radius: float
) -> float:
	var cone_intensity := 0.0
	var angle := absf(offset.angle()) if distance > 0.001 else 0.0
	if distance <= radius and angle <= half_angle:
		var edge_alpha := clampf((half_angle - angle) / CONE_EDGE_SOFTNESS, 0.0, 1.0)
		var range_alpha := clampf((radius - distance) / RANGE_EDGE_SOFTNESS, 0.0, 1.0)
		cone_intensity = minf(edge_alpha, range_alpha)
	var near_intensity := clampf((near_texture_radius - distance) / RANGE_EDGE_SOFTNESS, 0.0, 1.0)
	return maxf(cone_intensity, near_intensity)


func _radial_falloff(distance: float, radius: float) -> float:
	if radius <= 0.0 or distance > radius:
		return 0.0
	var normalized := clampf(1.0 - distance / radius, 0.0, 1.0)
	return pow(normalized, radial_falloff_power)
