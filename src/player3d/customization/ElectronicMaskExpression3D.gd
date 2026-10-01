extends Node3D
## Cosmetic channels sampled by the Blender-authored AnimationLibrary.
## Each instance owns its material; this adapter has no gameplay/state authority.

var blink_amount := 0.0:
	set(value):
		blink_amount = clampf(value, 0.0, 1.0)
		var pixels := get_node_or_null("Visual/ExpressionPixels") as MeshInstance3D
		if pixels != null:
			pixels.set_blend_shape_value(0, blink_amount if _blink_enabled else 0.0)

var pixel_brightness := 1.0:
	set(value):
		pixel_brightness = clampf(value, 0.0, 1.0)
		if _pixel_material != null:
			_pixel_material.emission_energy_multiplier = _full_emission * pixel_brightness

var _pixel_material: StandardMaterial3D
var _full_emission := 1.0
var _blink_enabled := true
var current_expression := "neutral"
var _system: Node
var _mesh_cache: Dictionary = {}

func _ready() -> void:
	var pixels := get_node("Visual/ExpressionPixels") as MeshInstance3D
	_pixel_material = pixels.get_active_material(0).duplicate() as StandardMaterial3D
	_full_emission = _pixel_material.emission_energy_multiplier
	pixels.material_override = _pixel_material
	blink_amount = blink_amount
	pixel_brightness = pixel_brightness

func bind_expression_system(system: Node) -> void:
	if is_instance_valid(_system) and _system.is_connected("expression_changed", apply_expression):
		_system.disconnect("expression_changed", apply_expression)
	_system = system
	_system.connect("expression_changed", apply_expression)
	apply_expression(str(_system.call("get_snapshot")["expression_id"]))

func apply_expression(expression_id: String) -> bool:
	var definition := CharacterExpressionCatalog.get_definition(expression_id)
	if definition.is_empty():
		return false
	if not _mesh_cache.has(expression_id):
		var visual := (definition["scene"] as PackedScene).instantiate()
		var meshes := visual.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() != 1:
			visual.free()
			return false
		_mesh_cache[expression_id] = (meshes[0] as MeshInstance3D).mesh
		visual.free()
	var mesh := _mesh_cache[expression_id] as Mesh
	var material := mesh.surface_get_material(0) as StandardMaterial3D
	if material == null or mesh.get_blend_shape_count() != 1:
		return false
	var pixels := get_node("Visual/ExpressionPixels") as MeshInstance3D
	pixels.mesh = mesh
	_pixel_material = material.duplicate() as StandardMaterial3D
	_full_emission = _pixel_material.emission_energy_multiplier
	pixels.material_override = _pixel_material
	_blink_enabled = bool(definition["blink_enabled"])
	current_expression = expression_id
	blink_amount = blink_amount
	pixel_brightness = pixel_brightness
	return true
