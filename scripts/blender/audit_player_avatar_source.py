"""Print the authored player source contract without changing the .blend file."""

import bpy
import json
from mathutils import Vector


def visible_mesh_bounds():
    points = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.hide_render:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        for corner in evaluated.bound_box:
            points.append(evaluated.matrix_world @ Vector(corner))
    if not points:
        return {}
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return {
        "minimum": list(minimum),
        "maximum": list(maximum),
        "dimensions": list(maximum - minimum),
    }


payload = {
    "blender_version": bpy.app.version_string,
    "unit_system": bpy.context.scene.unit_settings.system,
    "scale_length": bpy.context.scene.unit_settings.scale_length,
    "visible_mesh_bounds": visible_mesh_bounds(),
    "collections": [collection.name for collection in bpy.data.collections],
    "objects": [
        {
            "name": obj.name,
            "type": obj.type,
            "parent": obj.parent.name if obj.parent else "",
            "location": list(obj.location),
            "rotation_euler": list(obj.rotation_euler),
            "scale": list(obj.scale),
            "hidden_viewport": obj.hide_viewport,
            "hidden_render": obj.hide_render,
        }
        for obj in bpy.context.scene.objects
    ],
}
print("PLAYER_AVATAR_SOURCE_AUDIT=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
