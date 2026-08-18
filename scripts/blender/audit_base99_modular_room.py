import bpy
import json
from pathlib import Path
from mathutils import Vector


OUTPUT_PATH = Path(
    "/Users/summercards/ShellStorm2/assets/art/environments/base_facility_3d/"
    "source/env_base99_modular_room/env_base99_modular_room_audit_v001.json"
)

bpy.context.view_layer.update()


def vector(values):
    return [round(float(value), 5) for value in values]


def world_bounds(obj):
    if obj.type != "MESH" or not obj.bound_box:
        return None
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    maximum = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return {
        "min": vector(minimum),
        "max": vector(maximum),
        "size": vector(maximum - minimum),
        "center": vector((minimum + maximum) * 0.5),
    }


def collection_tree(collection):
    return {
        "name": collection.name,
        "hide_viewport": collection.hide_viewport,
        "hide_render": collection.hide_render,
        "objects": [obj.name for obj in collection.objects],
        "children": [collection_tree(child) for child in collection.children],
    }


objects = []
for obj in sorted(bpy.data.objects, key=lambda item: item.name):
    data = {
        "name": obj.name,
        "type": obj.type,
        "collections": sorted(collection.name for collection in obj.users_collection),
        "location": vector(obj.location),
        "rotation_euler": vector(obj.rotation_euler),
        "scale": vector(obj.scale),
        "dimensions": vector(obj.dimensions),
        "world_bounds": world_bounds(obj),
        "hide_viewport": obj.hide_viewport,
        "hide_render": obj.hide_render,
        "parent": obj.parent.name if obj.parent else None,
        "modifiers": [modifier.type for modifier in obj.modifiers],
    }
    if obj.type == "MESH":
        data.update(
            {
                "vertices": len(obj.data.vertices),
                "edges": len(obj.data.edges),
                "polygons": len(obj.data.polygons),
                "materials": [slot.material.name if slot.material else None for slot in obj.material_slots],
                "uv_layers": [layer.name for layer in obj.data.uv_layers],
                "active_uv": obj.data.uv_layers.active.name if obj.data.uv_layers.active else None,
                "active_render_uv": next(
                    (layer.name for layer in obj.data.uv_layers if layer.active_render), None
                ),
            }
        )
    objects.append(data)

materials = []
for material in sorted(bpy.data.materials, key=lambda item: item.name):
    entry = {"name": material.name, "users": material.users, "use_nodes": material.use_nodes}
    if material.use_nodes and material.node_tree:
        principled = next(
            (node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None
        )
        if principled:
            entry["metallic"] = round(float(principled.inputs["Metallic"].default_value), 5)
            entry["roughness"] = round(float(principled.inputs["Roughness"].default_value), 5)
            entry["emission_strength"] = round(
                float(principled.inputs["Emission Strength"].default_value), 5
            )
    materials.append(entry)

report = {
    "blend_file": bpy.data.filepath,
    "blender_version": bpy.app.version_string,
    "is_dirty": bpy.data.is_dirty,
    "unit_system": bpy.context.scene.unit_settings.system,
    "unit_scale": bpy.context.scene.unit_settings.scale_length,
    "object_count": len(bpy.data.objects),
    "mesh_count": sum(obj.type == "MESH" for obj in bpy.data.objects),
    "material_count": len(bpy.data.materials),
    "collections": [collection_tree(collection) for collection in bpy.context.scene.collection.children],
    "objects": objects,
    "materials": materials,
}

OUTPUT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"BASE99_AUDIT_WRITTEN:{OUTPUT_PATH}")
