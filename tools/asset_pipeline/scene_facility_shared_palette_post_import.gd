@tool
extends EditorScenePostImport
## Rebind palette-based environment/facility materials to one project texture and
## collapse legacy material copies onto the four canonical scene roles.

const SHARED_PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const ROLE_PREFIXES := {
	"01_精工金属": &"01_精工金属_紫色骨架",
	"02_细腻哑光": &"02_细腻哑光_青绿大面",
	"03_清漆反光": &"03_清漆反光_紫粉点缀",
	"04_柔和自发光": &"04_柔和自发光_UI灯光",
}


func _post_import(scene: Node) -> Object:
	var palette := load(SHARED_PALETTE_PATH) as Texture2D
	if palette == null:
		push_error("SCENE_FACILITY_SHARED_PALETTE_MISSING: %s" % SHARED_PALETTE_PATH)
		return scene
	_apply_palette(scene, palette, {})
	return scene


func _canonical_role(material_name: StringName) -> StringName:
	var text := String(material_name)
	for prefix in ROLE_PREFIXES.keys():
		var prefix_text := String(prefix)
		if text.begins_with(prefix_text):
			return StringName(ROLE_PREFIXES[prefix])
	return material_name


func _apply_palette(root: Node, palette: Texture2D, canonical_materials: Dictionary) -> void:
	if root is MeshInstance3D:
		_apply_to_mesh_instance(root as MeshInstance3D, palette, canonical_materials)
	for child in root.get_children():
		_apply_palette(child, palette, canonical_materials)


func _apply_to_mesh_instance(mesh_instance: MeshInstance3D, palette: Texture2D, canonical_materials: Dictionary) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var original := mesh.surface_get_material(surface_index) as BaseMaterial3D
		if original == null:
			continue
		var role := _canonical_role(original.resource_name)
		var material: BaseMaterial3D = canonical_materials.get(role) as BaseMaterial3D
		if material == null:
			material = original
			material.resource_name = role
			canonical_materials[role] = material
		_configure_material(material, palette)
		if material != original:
			mesh.surface_set_material(surface_index, material)


func _configure_material(material: BaseMaterial3D, palette: Texture2D) -> void:
	material.albedo_texture = palette
	material.emission_texture = palette
	# glTF's white emissive factor multiplies the palette. Godot's default ADD
	# operator instead adds white and washes out every cell.
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.texture_repeat = false
