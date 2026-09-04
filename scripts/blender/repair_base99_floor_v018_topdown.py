"""Create a v018 Base99 Blender source with floor z-fighting and unseen faces removed.

Input:  base_facility_runtime_layout_hq_v017.blend
Output: base_facility_runtime_layout_hq_v018.blend

The source v017 file is never saved or overwritten.  The repair targets only
the Blender-authored floor detail overlays and the separate loft floor finish;
the reused load-bearing base slabs remain untouched.
"""

from __future__ import annotations

import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_BLEND = (
    PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v018.blend"
)
REPORT_OUTPUT = PROJECT_ROOT / "outputs/verification/base99_floor_v018_repair_report.json"
FLOOR_COLLECTION_SUFFIX = "_原砖与深化内容_资产包"
LOFT_COLLECTION_NAME = "116_二楼地板色彩深化_资产包"
REUSED_BASE_MARKERS = ("保留地板", "普通地板_主体", "带铆钉地板_主体", "输出根节点")
INNER_SHADOW_MARKER = "内阴影条"
COPLANAR_LIFT_M = 0.002
BOTTOM_NORMAL_MAX_Z = -0.95


def is_reused_base_object(obj: bpy.types.Object) -> bool:
    return any(marker in obj.name for marker in REUSED_BASE_MARKERS)


def floor_collections() -> list[bpy.types.Collection]:
    collections = sorted(
        [
            collection
            for collection in bpy.data.collections
            if collection.name.startswith("地砖_R")
            and collection.name.endswith(FLOOR_COLLECTION_SUFFIX)
        ],
        key=lambda collection: collection.name,
    )
    if len(collections) != 36:
        raise RuntimeError(f"Expected 36 floor packages, got {len(collections)}")
    return collections


def package_is_rivet(collection: bpy.types.Collection) -> bool:
    return any("带铆钉地板_主体" in obj.name for obj in collection.objects)


def lift_rivet_inner_shadow_strips(collections: list[bpy.types.Collection]) -> list[str]:
    lifted: list[str] = []
    world_lift = Matrix.Translation((0.0, 0.0, COPLANAR_LIFT_M))
    for collection in collections:
        if not package_is_rivet(collection):
            continue
        for obj in collection.objects:
            if obj.type != "MESH" or INNER_SHADOW_MARKER not in obj.name:
                continue
            obj.matrix_world = world_lift @ obj.matrix_world
            lifted.append(obj.name)
    if len(lifted) != 72:
        raise RuntimeError(f"Expected to lift 72 rivet inner shadow strips, got {len(lifted)}")
    return lifted


def detail_meshes(collections: list[bpy.types.Collection]) -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
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
    if len(result) != len(set(result)):
        raise RuntimeError("A repair mesh is present in multiple selected packages")
    return result


def remove_downward_faces(objects: list[bpy.types.Object]) -> tuple[int, dict[str, int]]:
    total_removed = 0
    removed_by_object: dict[str, int] = {}
    for obj in objects:
        if obj.modifiers:
            raise RuntimeError(f"Refusing to destructively edit a modified detail mesh: {obj.name}")
        mesh = obj.data
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        bm = bmesh.new()
        try:
            bm.from_mesh(mesh)
            bm.normal_update()
            downward_faces = [
                face
                for face in bm.faces
                if (normal_matrix @ face.normal).normalized().z < BOTTOM_NORMAL_MAX_Z
            ]
            if not downward_faces:
                continue
            count = len(downward_faces)
            bmesh.ops.delete(bm, geom=downward_faces, context="FACES")
            bm.to_mesh(mesh)
            mesh.update()
            total_removed += count
            removed_by_object[obj.name] = count
        finally:
            bm.free()
    return total_removed, removed_by_object


def main() -> None:
    if Path(bpy.data.filepath).name != "base_facility_runtime_layout_hq_v017.blend":
        raise RuntimeError(f"Expected v017 input, got {bpy.data.filepath}")
    collections = floor_collections()
    lifted = lift_rivet_inner_shadow_strips(collections)
    removal_scope = detail_meshes(collections)
    removed_count, removed_by_object = remove_downward_faces(removal_scope)
    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
    report = {
        "input_blend": "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend",
        "output_blend": str(OUTPUT_BLEND.relative_to(PROJECT_ROOT)),
        "version": "v018",
        "repair_scope": "Blender-authored ground detail overlays and loft floor finish only; reused base slabs excluded",
        "coplanar_fix": {
            "lift_m": COPLANAR_LIFT_M,
            "lifted_rivet_inner_shadow_strip_count": len(lifted),
            "lifted_objects": lifted,
        },
        "topdown_optimization": {
            "normal_z_threshold": BOTTOM_NORMAL_MAX_Z,
            "removed_downward_facing_triangle_count": removed_count,
            "removed_by_object": removed_by_object,
        },
    }
    REPORT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    REPORT_OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE99_FLOOR_V018_BLEND_WRITTEN:{OUTPUT_BLEND}")
    print(f"BASE99_FLOOR_V018_REPAIR_REPORT:{REPORT_OUTPUT}")
    print(f"LIFTED_RIVET_INNER_SHADOW_STRIPS:{len(lifted)}")
    print(f"REMOVED_DOWNWARD_TRIANGLES:{removed_count}")


if __name__ == "__main__":
    main()
