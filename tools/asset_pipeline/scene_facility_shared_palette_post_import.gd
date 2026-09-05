@tool
extends EditorScenePostImport
## Rebind palette-based environment/facility materials to one project texture.

const SHARED_PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


func _post_import(scene: Node) -> Object:
	var palette := load(SHARED_PALETTE_PATH) as Texture2D
	if palette == null:
		push_error("SCENE_FACILITY_SHARED_PALETTE_MISSING: %s" % SHARED_PALETTE_PATH)
		return scene
	_apply_palette(scene, palette)
	return scene


func _apply_palette(root: Node, palette: Texture2D) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
				if material == null:
					continue
				material.albedo_texture = palette
				material.emission_texture = palette
				# glTF's white emissive factor multiplies the palette. Godot's
				# default ADD operator instead adds white and washes out every cell.
				material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				material.texture_repeat = false
	for child in root.get_children():
		_apply_palette(child, palette)
