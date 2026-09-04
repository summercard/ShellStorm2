"""Create v020 by deleting the final triangulated, downward-facing sliver faces.

Input:  base_facility_runtime_layout_hq_v019.blend
Output: base_facility_runtime_layout_hq_v020.blend

The source mesh can contain non-planar n-gons whose generated render triangles have
an inverted, near-zero-area sliver even though the n-gon normal is upward.  This
script triangulates only the editable floor-detail meshes, then deletes those
individual downward triangles.  Reused base-floor meshes remain untouched.
"""

from __future__ import annotations

import json
from pathlib import Path

import bmesh
import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_BLEND = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v020.blend"
REPORT_OUTPUT = PROJECT_ROOT / "outputs/verification/base99_floor_v020_repair_report.json"
FLOOR_COLLECTION_SUFFIX = "_原砖与深化内容_资产包"
LOFT_COLLECTION_NAME = "116_二楼地板色彩深化_资产包"
REUSED_BASE_MARKERS = ("保留地板", "普通地板_主体", "带铆钉地板_主体", "输出根节点")
BOTTOM_NORMAL_MAX_Z = -0.95


def is_reused_base_object(obj: bpy.types.Object) -> bool:
    return any(marker in obj.name for marker in REUSED_BASE_MARKERS)


def selected_detail_objects() -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
    collections = [
        collection
        for collection in bpy.data.collections
        if collection.name.startswith("地砖_R")
        and collection.name.endswith(FLOOR_COLLECTION_SUFFIX)
    ]
    if len(collections) != 36:
        raise RuntimeError(f"Expected 36 floor packages, got {len(collections)}")
    for collection in collections:
        result.extend(
            obj
            for obj in collection.objects
            if obj.type == "MESH" and not is_reused_base_object(obj)
        )
    loft = bpy.data.collections.get(LOFT_COLLECTION_NAME)
    if loft is None:
        raise RuntimeError(f"Missing loft collection: {LOFT_COLLECTION_NAME}")
    result.extend(obj for obj in loft.objects if obj.type == "MESH")
    return result


def triangulate_and_delete_bottom_slivers(objects: list[bpy.types.Object]) -> tuple[int, int]:
    triangulated = 0
    removed = 0
    for obj in objects:
        if obj.modifiers:
            raise RuntimeError(f"Refusing to edit a modified detail mesh: {obj.name}")
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        bm = bmesh.new()
        try:
            bm.from_mesh(obj.data)
            ngons = [face for face in bm.faces if len(face.verts) > 3]
            if ngons:
                bmesh.ops.triangulate(bm, faces=ngons, quad_method="FIXED", ngon_method="EAR_CLIP")
                triangulated += len(ngons)
            bm.normal_update()
            downward = [
                face
                for face in bm.faces
                if (normal_matrix @ face.normal).normalized().z < BOTTOM_NORMAL_MAX_Z
            ]
            if downward:
                removed += len(downward)
                bmesh.ops.delete(bm, geom=downward, context="FACES")
            if ngons or downward:
                bm.to_mesh(obj.data)
                obj.data.update()
        finally:
            bm.free()
    return triangulated, removed


def main() -> None:
    if Path(bpy.data.filepath).name != "base_facility_runtime_layout_hq_v019.blend":
        raise RuntimeError(f"Expected v019 input, got {bpy.data.filepath}")
    triangulated, removed = triangulate_and_delete_bottom_slivers(selected_detail_objects())
    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
    REPORT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    REPORT_OUTPUT.write_text(
        json.dumps(
            {
                "input_blend": "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v019.blend",
                "output_blend": str(OUTPUT_BLEND.relative_to(PROJECT_ROOT)),
                "version": "v020",
                "triangulated_editable_ngons": triangulated,
                "removed_downward_triangles": removed,
            },
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )
    print(f"BASE99_FLOOR_V020_BLEND_WRITTEN:{OUTPUT_BLEND}")
    print(f"TRIANGULATED_EDITABLE_NGONS:{triangulated}")
    print(f"REMOVED_DOWNWARD_TRIANGLES:{removed}")


if __name__ == "__main__":
    main()
