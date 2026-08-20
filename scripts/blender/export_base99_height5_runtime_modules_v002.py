"""Export the three Base99 v002 height-corrected runtime modules."""

import bpy
import bmesh
from pathlib import Path


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
EXPORTS = {
    "ENV-BASE99-MEZZANINE-20X10-Z5": PROJECT_ROOT
    / "assets/art/environments/base_facility_3d/components/env_base99_mezzanine_20x10_z5"
    / "env_base99_mezzanine_20x10_z5_visual_top3d_v002.glb",
    "ENV-BASE99-STAIR-L-Z5": PROJECT_ROOT
    / "assets/art/environments/base_facility_3d/components/env_base99_stair_l_z5"
    / "env_base99_stair_l_z5_visual_top3d_v002.glb",
    "ENV-BASE99-STAIR-EXTERIOR-H4": PROJECT_ROOT
    / "assets/art/environments/base_facility_3d/components/env_base99_stair_exterior_h4"
    / "env_base99_stair_exterior_h4_visual_top3d_v002.glb",
}


def descendants(root):
    result = []
    pending = list(root.children)
    while pending:
        child = pending.pop()
        result.append(child)
        pending.extend(child.children)
    return result


def output_root(asset_id):
    matches = [
        obj for obj in bpy.data.objects
        if obj.get("asset_id") == asset_id and "输出根节点" in obj.name
    ]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one output root for {asset_id}, found {len(matches)}")
    return matches[0]


def triangulate(mesh_object):
    bm = bmesh.new()
    bm.from_mesh(mesh_object.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(mesh_object.data)
    bm.free()
    mesh_object.data.update()


def export_asset(asset_id, output_path):
    root = output_root(asset_id)
    children = descendants(root)
    meshes = [obj for obj in children if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"No meshes below {root.name}")
    original_location = root.location.copy()
    try:
        for mesh in meshes:
            triangulate(mesh)
        root.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        root.select_set(True)
        for child in children:
            child.select_set(True)
        bpy.context.view_layer.objects.active = root
        output_path.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=str(output_path),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
            export_texcoords=True,
            export_normals=True,
            export_tangents=True,
            export_materials="EXPORT",
            export_extras=True,
            export_cameras=False,
            export_lights=False,
            export_animations=False,
        )
    finally:
        root.location = original_location
        bpy.context.view_layer.update()
    print(f"BASE99_HEIGHT5_GLB_WRITTEN:{asset_id}:{output_path}")


for asset_id, output_path in EXPORTS.items():
    export_asset(asset_id, output_path)
