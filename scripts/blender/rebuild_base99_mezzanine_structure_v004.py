"""Export a deck-free mezzanine structure that reuses the V020 loft floor."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bmesh
import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
ROOT = PROJECT / "assets/art/environments/base_facility_3d"
INPUT = ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v005.blend"
OUTPUT = ROOT / "source/env_base99_modular_room/env_base99_modular_room_assets_clean_v006.blend"
GLB = ROOT / "components/env_base99_mezzanine_20x10_z5/env_base99_mezzanine_20x10_z5_visual_top3d_v004.glb"
MANIFEST = ROOT / "source/env_base99_modular_room/env_base99_mezzanine_20x10_z5_v004_manifest.json"
ASSET_ID = "ENV-BASE99-MEZZANINE-20X10-Z5"


def descendants(root):
    items, queue = [], list(root.children)
    while queue:
        node = queue.pop()
        items.append(node)
        queue.extend(node.children)
    return items


def duplicate(source, parent, collection):
    node = source.copy()
    node.data = source.data.copy()
    node.parent = parent
    node.matrix_local = source.matrix_local.copy()
    collection.objects.link(node)
    return node


def join(nodes, name):
    bpy.ops.object.select_all(action="DESELECT")
    for node in nodes:
        node.select_set(True)
    bpy.context.view_layer.objects.active = nodes[0]
    bpy.ops.object.join()
    output = bpy.context.active_object
    output.name = name
    output["palette_uv_contract"] = "PaletteUV"
    return output


def triangulate(mesh):
    data = bmesh.new()
    data.from_mesh(mesh)
    bmesh.ops.triangulate(data, faces=list(data.faces))
    data.to_mesh(mesh)
    data.free()
    mesh.update()


def triangles(mesh):
    return sum(max(0, len(face.vertices) - 2) for face in mesh.polygons)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


if Path(bpy.data.filepath).resolve() != INPUT.resolve():
    raise RuntimeError("Open %s" % INPUT)
source = next(node for node in bpy.data.objects if node.get("asset_id") == ASSET_ID and node.get("asset_version") == "v003" and "制作根节点" in node.name)
if any(node.get("asset_id") == ASSET_ID and node.get("asset_version") == "v004" for node in bpy.data.objects):
    raise RuntimeError("v004 already exists; versioned assets are never overwritten")

source_collection = bpy.data.collections.new("01_制作组件_阁楼结构_v004")
output_collection = bpy.data.collections.new("02_游戏输出_阁楼结构_v004")
bpy.context.scene.collection.children.link(source_collection)
bpy.context.scene.collection.children.link(output_collection)
source_root = bpy.data.objects.new("%s_制作根节点_v004" % ASSET_ID, None)
output_root = bpy.data.objects.new("%s_输出根节点_v004" % ASSET_ID, None)
source_collection.objects.link(source_root)
output_collection.objects.link(output_root)
for root in (source_root, output_root):
    root.matrix_world = source.matrix_world.copy()
    root["asset_id"] = ASSET_ID
    root["asset_version"] = "v004"
    root["visual_deck_policy"] = "reuse_ENV-BASE99-LOFT-FLOOR-FINISH-V017_v002"
source_root.hide_set(True)
output_root["geometry_contract"] = "structure_and_guardrails_only; V020 owns visible deck finish"
output_root["collision_contract"] = "Godot wrapper owns continuous deck and real guard blockers"

body, emissive = [], []
removed = 0
for child in source.children:
    if child.type != "MESH":
        continue
    floor_surface = child.get("semantic_component") == "inset_deck_skin" or "阁楼地砖_" in child.name
    if floor_surface:
        removed += 1
        continue
    editable = duplicate(child, source_root, source_collection)
    editable.hide_set(True)
    visual = duplicate(child, output_root, output_collection)
    if any(material and "自发光" in material.name for material in visual.data.materials):
        emissive.append(visual)
    else:
        body.append(visual)

body_mesh = join(body, "二层楼板_结构护栏_主体_金属哑光反光")
emissive_mesh = join(emissive, "二层楼板_结构护栏_UI灯光_柔和自发光")
body_mesh.parent = output_root
emissive_mesh.parent = output_root
for node in descendants(output_root):
    if node.type == "MESH":
        triangulate(node.data)
meshes = [node for node in descendants(output_root) if node.type == "MESH"]
inverse = output_root.matrix_world.inverted()
points = [inverse @ node.matrix_world @ vertex.co for node in meshes for vertex in node.data.vertices]
minimum = [min(point[index] for point in points) for index in range(3)]
maximum = [max(point[index] for point in points) for index in range(3)]
output_root["removed_legacy_floor_mesh_count"] = removed
output_root["triangle_count"] = sum(triangles(node.data) for node in meshes)
output_root["local_bounds_min"] = minimum
output_root["local_bounds_max"] = maximum

bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
output_root.select_set(True)
for node in descendants(output_root):
    node.select_set(True)
bpy.context.view_layer.objects.active = output_root
GLB.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_texcoords=True, export_normals=True, export_tangents=True, export_materials="EXPORT", export_image_format="NONE", export_extras=True, export_cameras=False, export_lights=False, export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
manifest = {
    "asset_id": ASSET_ID, "version": "v004", "input_blend": str(INPUT.relative_to(PROJECT)),
    "source": str(OUTPUT.relative_to(PROJECT)), "glb": str(GLB.relative_to(PROJECT)),
    "visual_deck_policy": "reuse ENV-BASE99-LOFT-FLOOR-FINISH-V017 v002; no duplicate deck visual",
    "removed_legacy_floor_mesh_count": removed, "triangles": output_root["triangle_count"],
    "bounds_min": [round(value, 5) for value in minimum], "bounds_max": [round(value, 5) for value in maximum],
    "materials": sorted({material.name for node in meshes for material in node.data.materials if material}),
    "collision": "PackedScene owns continuous deck and real guard blockers", "source_sha256": digest(OUTPUT), "glb_sha256": digest(GLB),
}
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("BASE99_MEZZANINE_V004_WRITTEN:triangles=%d:removed_floor_meshes=%d" % (output_root["triangle_count"], removed))
