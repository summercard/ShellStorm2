"""Create the formal Base99 5 m mezzanine/stair asset revision.

Input is the clean v001 asset pack. The script preserves tread/deck/railing
thickness where practical, shortens structural spans, and creates a true 4 m
exterior stair by extending the authored 2 m module with a second flight.
"""

import bpy
import json
from pathlib import Path
from mathutils import Vector


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
ASSET_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d"
SOURCE_PATH = ASSET_ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v001.blend"
OUTPUT_PATH = ASSET_ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v002.blend"
MANIFEST_PATH = ASSET_ROOT / "source/env_base99_modular_room/env_base99_height5_assets_v002_manifest.json"
PREVIEW_PATH = ASSET_ROOT / "source/env_base99_modular_room/previews/env_base99_height5_assets_v002_overview.png"

HEIGHT_RATIO = 5.0 / 7.0

REVISIONS = {
    "ENV-BASE99-MEZZANINE-20X10-Z7": {
        "asset_id": "ENV-BASE99-MEZZANINE-20X10-Z5",
        "logic_id": "base99_mezzanine_20x10_z5",
        "mode": "mezzanine",
        "replacements": [("Z7", "Z5"), ("z7", "z5"), ("7米", "5米")],
    },
    "ENV-BASE99-STAIR-L-Z7": {
        "asset_id": "ENV-BASE99-STAIR-L-Z5",
        "logic_id": "base99_stair_l_z5",
        "mode": "l_stair",
        "replacements": [("Z7", "Z5"), ("z7", "z5"), ("7米", "5米")],
    },
    "ENV-BASE99-STAIR-EXTERIOR-H2": {
        "asset_id": "ENV-BASE99-STAIR-EXTERIOR-H4",
        "logic_id": "base99_stair_exterior_h4",
        "mode": "exterior_h4",
        "replacements": [("H2", "H4"), ("h2", "h4"), ("高差2米", "高差4米"), ("8级", "16级")],
    },
}


def descendants(root):
    result = []
    pending = list(root.children)
    while pending:
        child = pending.pop()
        result.append(child)
        pending.extend(child.children)
    return result


def mesh_descendants(root):
    return [obj for obj in descendants(root) if obj.type == "MESH"]


def connected_vertex_components(mesh):
    adjacency = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)
    remaining = set(range(len(mesh.vertices)))
    components = []
    while remaining:
        seed = remaining.pop()
        stack = [seed]
        component = [seed]
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
                    component.append(neighbor)
        components.append(component)
    return components


def transform_mezzanine_mesh(mesh):
    for component in connected_vertex_components(mesh):
        z_values = [mesh.vertices[index].co.z for index in component]
        minimum = min(z_values)
        maximum = max(z_values)
        if minimum >= 6.35:
            for index in component:
                mesh.vertices[index].co.z -= 2.0
        elif maximum <= 0.55:
            continue
        else:
            for index in component:
                mesh.vertices[index].co.z *= HEIGHT_RATIO
    mesh.update()


def transform_l_stair_mesh(mesh):
    for component in connected_vertex_components(mesh):
        z_values = [mesh.vertices[index].co.z for index in component]
        minimum = min(z_values)
        maximum = max(z_values)
        height = maximum - minimum
        if height <= 0.45:
            old_center = (minimum + maximum) * 0.5
            target_center = old_center * HEIGHT_RATIO
            shift = target_center - old_center
            for index in component:
                mesh.vertices[index].co.z += shift
        elif height <= 1.10:
            target_base = minimum * HEIGHT_RATIO
            shift = target_base - minimum
            for index in component:
                mesh.vertices[index].co.z += shift
        else:
            for index in component:
                mesh.vertices[index].co.z *= HEIGHT_RATIO
    mesh.update()


def extend_exterior_stair(root):
    originals = mesh_descendants(root)
    if not originals:
        raise RuntimeError(f"No exterior stair meshes below {root.name}")
    for original in originals:
        original.location.x -= 2.0
        duplicate = original.copy()
        duplicate.data = original.data.copy()
        duplicate.name = original.name.replace("8级", "16级") + "_上半段"
        duplicate.parent = original.parent
        for collection in original.users_collection:
            collection.objects.link(duplicate)
        duplicate.location.x += 4.0
        duplicate.location.z += 2.0


def replace_name(value, replacements):
    result = value
    for old, new in replacements:
        result = result.replace(old, new)
    return result


def rename_revision_tree(root, revision):
    replacements = revision["replacements"]
    root.name = replace_name(root.name, replacements)
    for obj in descendants(root):
        obj.name = replace_name(obj.name, replacements)
        if obj.type == "MESH":
            obj.data.name = replace_name(obj.data.name, replacements)
    for collection in root.users_collection:
        collection.name = replace_name(collection.name, replacements)


def apply_revision(old_asset_id, revision):
    roots = [obj for obj in bpy.data.objects if obj.get("asset_id") == old_asset_id]
    if len(roots) != 2:
        raise RuntimeError(f"Expected source/output roots for {old_asset_id}, found {len(roots)}")
    for root in roots:
        mode = revision["mode"]
        if mode == "mezzanine":
            for obj in mesh_descendants(root):
                transform_mezzanine_mesh(obj.data)
        elif mode == "l_stair":
            for obj in mesh_descendants(root):
                transform_l_stair_mesh(obj.data)
        elif mode == "exterior_h4":
            extend_exterior_stair(root)
        root["asset_id"] = revision["asset_id"]
        root["logic_id"] = revision["logic_id"]
        root["unit"] = "meter"
        root["blender_forward"] = "-Y"
        root["godot_forward"] = "-Z"
        root["module_local_origin"] = "xy_center_bottom_z0"
        root["revision_reason"] = "platform_height_5m_and_connected_stairs"
        if mode == "mezzanine":
            root["deck_height_m"] = 5.0
        elif mode == "l_stair":
            root["start_height_m"] = 0.0
            root["landing_height_m"] = 2.5
            root["end_height_m"] = 5.0
        else:
            root["start_height_m"] = 5.0
            root["end_height_m"] = 9.0
            root["height_delta_m"] = 4.0
            root["step_count"] = 16
        rename_revision_tree(root, revision)
    return roots


def local_bounds(root):
    points = []
    inverse = root.matrix_world.inverted()
    for obj in mesh_descendants(root):
        for vertex in obj.data.vertices:
            points.append(inverse @ obj.matrix_world @ vertex.co)
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


def output_root(asset_id):
    matches = [
        obj for obj in bpy.data.objects
        if obj.get("asset_id") == asset_id and "输出根节点" in obj.name
    ]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one output root for {asset_id}, found {len(matches)}")
    return matches[0]


if Path(bpy.data.filepath).resolve() != SOURCE_PATH.resolve():
    raise RuntimeError(f"Open the clean v001 pack first: {SOURCE_PATH}")

for old_id, revision in REVISIONS.items():
    apply_revision(old_id, revision)

bpy.context.view_layer.update()
bpy.context.evaluated_depsgraph_get().update()

manifest_modules = []
for revision in REVISIONS.values():
    root = output_root(revision["asset_id"])
    minimum, maximum = local_bounds(root)
    root["local_bounds_min"] = list(minimum)
    root["local_bounds_max"] = list(maximum)
    root["local_dimensions"] = list(maximum - minimum)
    manifest_modules.append({
        "asset_id": revision["asset_id"],
        "logic_id": revision["logic_id"],
        "mode": revision["mode"],
        "local_bounds_min": [round(value, 5) for value in minimum],
        "local_bounds_max": [round(value, 5) for value in maximum],
        "local_dimensions": [round(value, 5) for value in maximum - minimum],
        "mesh_count": len(mesh_descendants(root)),
        "forward": "Blender -Y / Godot -Z",
        "origin": "xy_center_bottom_z0",
    })

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene["asset_pack"] = "ENV-BASE99-MODULAR-ROOM"
scene["asset_pack_version"] = "v002"
scene["height_contract"] = "99F floor 0m; mezzanine 5m; 100F floor 9m"
scene["collision_contract"] = "Godot wrapper owns smooth ramps, rail blockers and camera slabs"

manifest = {
    "asset_pack": "ENV-BASE99-MODULAR-ROOM",
    "version": "v002",
    "source": str(SOURCE_PATH),
    "output_blend": str(OUTPUT_PATH),
    "height_contract": {"floor_99_m": 0.0, "mezzanine_m": 5.0, "floor_100_m": 9.0},
    "modules": manifest_modules,
}
MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_PATH), compress=True)
scene.render.filepath = str(PREVIEW_PATH)
bpy.ops.render.render(write_still=True)
print(f"BASE99_HEIGHT5_BLEND_WRITTEN:{OUTPUT_PATH}")
print(f"BASE99_HEIGHT5_MANIFEST_WRITTEN:{MANIFEST_PATH}")
print(f"BASE99_HEIGHT5_PREVIEW_WRITTEN:{PREVIEW_PATH}")
