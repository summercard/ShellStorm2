@tool
extends EditorScenePostImport
## Four independent item-owned resources; scene materials are never reused.
const ITEM_MATERIALS := [
    preload("res://assets/art/items_weapons/shared/materials/itm_metal.tres"),
    preload("res://assets/art/items_weapons/shared/materials/itm_matte.tres"),
    preload("res://assets/art/items_weapons/shared/materials/itm_clearcoat.tres"),
    preload("res://assets/art/items_weapons/shared/materials/itm_emissive.tres"),
]
func _post_import(scene: Node) -> Object:
    _apply_materials(scene)
    return scene
func _apply_materials(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh := (node as MeshInstance3D).mesh
        if mesh != null:
            for surface in mesh.get_surface_count():
                var original := mesh.surface_get_material(surface)
                if original == null:
                    push_error("ITEM_MATERIAL_ROLE_MISSING: %s" % node.name)
                    continue
                var index := int(String(original.resource_name).left(2)) - 1
                if index < 0 or index >= ITEM_MATERIALS.size():
                    push_error("ITEM_MATERIAL_ROLE_UNKNOWN: %s" % original.resource_name)
                    continue
                mesh.surface_set_material(surface, ITEM_MATERIALS[index])
    for child in node.get_children():
        _apply_materials(child)
