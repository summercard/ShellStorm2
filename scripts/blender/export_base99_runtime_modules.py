"""Export selected Base99 game-output modules from the clean Blender pack.

Run with Blender, for example:
  blender -b <clean.blend> -P scripts/blender/export_base99_runtime_modules.py -- \
    ENV-BASE99-WALL-PLAIN-5X9

Each AssetID is mapped to one stable GLB path. The source Empty is moved to the
origin only for export and is restored before the Blender process exits.
"""

import bpy
import sys
from pathlib import Path


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
EXPORTS = {
    "ENV-BASE99-WALL-PLAIN-5X9": PROJECT_ROOT
    / "assets/art/environments/base_facility_3d/components/env_base99_wall_plain_5x9"
    / "env_base99_wall_plain_5x9_visual_top3d_v001.glb",
    "ENV-BASE99-WALL-DOOR-5X9": PROJECT_ROOT
    / "assets/art/environments/base_facility_3d/components/env_base99_wall_door_5x9"
    / "env_base99_wall_door_5x9_visual_top3d_v001.glb",
}


def descendants(root):
    result = []
    pending = list(root.children)
    while pending:
        child = pending.pop()
        result.append(child)
        pending.extend(child.children)
    return result


def find_output_root(asset_id):
    candidates = [
        obj
        for obj in bpy.data.objects
        if obj.get("asset_id") == asset_id and "输出根节点" in obj.name
    ]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one output root for {asset_id}, found {len(candidates)}")
    return candidates[0]


def export_asset(asset_id, output_path):
    root = find_output_root(asset_id)
    meshes = [obj for obj in descendants(root) if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"No output mesh below {root.name}")
    original_location = root.location.copy()
    try:
        root.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        root.select_set(True)
        for obj in descendants(root):
            obj.select_set(True)
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
    print(f"BASE99_RUNTIME_GLB_WRITTEN:{asset_id}:{output_path}")


requested = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
asset_ids = requested or sorted(EXPORTS)
unknown = [asset_id for asset_id in asset_ids if asset_id not in EXPORTS]
if unknown:
    raise RuntimeError(f"Unknown Base99 AssetID(s): {unknown}")
for requested_asset_id in asset_ids:
    export_asset(requested_asset_id, EXPORTS[requested_asset_id])
