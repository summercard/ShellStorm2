"""Create the v025 Base99 door-wall source and palette-correct runtime export.

Only the large matte panel's PaletteUV is moved to the plain wall's runtime cell
(1, 6). Blender's V axis is inverted by the Godot GLB export, so its authoring
cell is (1, 3).
The UV islands retain their size and shape; frame/accent materials and geometry stay intact.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[2]
SOURCE_OUTPUT = ROOT / "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v025.blend"
DERIVED_OUTPUT = ROOT / "source/art/blender/base_facility_layout/export/v025/base_facility_runtime_layout_hq-v025-door_wall_palette.blend"
GLB_OUTPUT = ROOT / "assets/art/environments/base_facility_3d/components/env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v003.glb"
MANIFEST_OUTPUT = ROOT / "source/art/blender/base_facility_layout/export/v025/door_wall_palette_export_manifest.json"

PANEL_MATERIAL = "02_细腻哑光_青绿大面"
# GLB runtime target is (1, 6); Blender source uses the vertically flipped (1, 3).
TARGET_CELL = (1, 3)
ALLOWED_SOURCE_CELLS = {(9, 2), (9, 3)}
MASTER_OBJECTS = (
    "西墙带门墙体_主体_金属哑光反光",
    "西墙带门墙体_主体_金属哑光反光__源",
)
EXPORT_OBJECT = "西墙带门墙体_主体_金属哑光反光__源"


def palette_cell(uv: tuple[float, float]) -> tuple[int, int]:
    return (max(0, min(9, int(uv[0] * 10))), max(0, min(9, int(uv[1] * 10))))


def remap_panel_uv(obj: bpy.types.Object) -> tuple[int, int]:
    mesh = obj.data
    uv_layer = mesh.uv_layers.get("PaletteUV")
    if uv_layer is None:
        raise RuntimeError(f"{obj.name} is missing PaletteUV")
    mesh.uv_layers.active = uv_layer
    uv_layer.active_render = True
    material_index = next((i for i, m in enumerate(mesh.materials) if m and m.name == PANEL_MATERIAL), None)
    if material_index is None:
        raise RuntimeError(f"{obj.name} is missing {PANEL_MATERIAL}")
    changed_faces = 0
    changed_loops = 0
    for polygon in mesh.polygons:
        if polygon.material_index != material_index:
            continue
        cells = {palette_cell(tuple(uv_layer.data[index].uv)) for index in polygon.loop_indices}
        if len(cells) != 1 or not cells <= ALLOWED_SOURCE_CELLS:
            raise RuntimeError(f"{obj.name} polygon {polygon.index} has unexpected panel UV cells: {cells}")
        source_cell = cells.pop()
        delta_u = (TARGET_CELL[0] - source_cell[0]) / 10.0
        delta_v = (TARGET_CELL[1] - source_cell[1]) / 10.0
        for index in polygon.loop_indices:
            uv_layer.data[index].uv.x += delta_u
            uv_layer.data[index].uv.y += delta_v
            changed_loops += 1
        changed_faces += 1
    if changed_faces == 0:
        raise RuntimeError(f"{obj.name} has no large-panel faces to remap")
    return changed_faces, changed_loops


def keep_only_export_object() -> tuple[int, int]:
    source = bpy.data.objects.get(EXPORT_OBJECT)
    if source is None or source.type != "MESH":
        raise RuntimeError(f"Missing export object: {EXPORT_OBJECT}")
    for obj in list(bpy.data.objects):
        if obj != source:
            bpy.data.objects.remove(obj, do_unlink=True)
    # The source mesh lived in a nested authoring collection. Give the derived
    # file an explicit scene-level export collection so the glTF exporter sees it.
    export_collection = bpy.data.collections.get("wall_door_02_游戏输出_整合模型")
    if export_collection is None:
        export_collection = bpy.data.collections.new("wall_door_02_游戏输出_整合模型")
        bpy.context.scene.collection.children.link(export_collection)
    if export_collection.objects.get(source.name) is None:
        export_collection.objects.link(source)
    source.hide_viewport = False
    source.hide_render = False
    source.name = "wall_door_西墙带门墙体_主体_金属哑光反光"
    source.data.name = "wall_door_西墙带门墙体_主体_金属哑光反光_网格"
    bpy.context.view_layer.objects.active = source
    source.select_set(True)
    mesh = source.data
    before = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[face for face in bm.faces if face.normal.z < -0.5], context="FACES")
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    after = len(mesh.polygons)
    return before, after


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    change_summary = {}
    for name in MASTER_OBJECTS:
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError(f"Missing master object: {name}")
        change_summary[name] = dict(zip(("faces", "loops"), remap_panel_uv(obj)))
    SOURCE_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene["palette_revision"] = "base99_door_wall_panel_matches_plain_wall_v025"
    bpy.context.scene["palette_revision_note"] = "Only matte main-panel PaletteUV moved to cell (1, 6); frame/accent UVs unchanged."
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_OUTPUT), compress=True)

    triangles_before, triangles_after = keep_only_export_object()
    DERIVED_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED_OUTPUT), compress=True)
    GLB_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # Saving a .blend may clear the transient selection; restore the one export root.
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    export_root = bpy.data.objects["wall_door_西墙带门墙体_主体_金属哑光反光"]
    export_root.select_set(True)
    bpy.context.view_layer.objects.active = export_root
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_image_format="NONE",
        export_lights=False,
        export_cameras=False,
        export_materials="EXPORT",
    )
    MANIFEST_OUTPUT.write_text(json.dumps({
        "version": "v025",
        "source_blend": str(SOURCE_OUTPUT.relative_to(ROOT)),
        "source_blend_sha256": sha256(SOURCE_OUTPUT),
        "derived_blend": str(DERIVED_OUTPUT.relative_to(ROOT)),
        "asset_id": "ENV-BASE99-WALL-DOOR-5X9",
        "palette_uv_change": {
            "material": PANEL_MATERIAL,
            "target_cell": list(TARGET_CELL),
            "source_cells": [list(cell) for cell in sorted(ALLOWED_SOURCE_CELLS)],
            "master_objects": change_summary,
            "unchanged": ["geometry", "door opening", "metal frame UV", "accent UV", "collision ownership"],
        },
        "triangles_before": triangles_before,
        "triangles_after": triangles_after,
        "downward_triangles_removed": triangles_before - triangles_after,
        "visual_glb": str(GLB_OUTPUT.relative_to(ROOT)),
        "visual_glb_sha256": sha256(GLB_OUTPUT),
        "forward_axis": "Godot -Z",
        "collision_policy": "DungeonRoom3D + RoomDoor3D unchanged",
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE99_DOOR_WALL_V025_EXPORTED faces={change_summary} tris={triangles_after}")


if __name__ == "__main__":
    main()
