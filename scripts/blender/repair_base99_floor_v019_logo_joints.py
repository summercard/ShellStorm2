"""Create the final v019 floor source by removing residual logo-joint z-fighting.

Input:  base_facility_runtime_layout_hq_v018.blend
Output: base_facility_runtime_layout_hq_v019.blend
"""

from __future__ import annotations

import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_BLEND = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v019.blend"
REPORT_OUTPUT = PROJECT_ROOT / "outputs/verification/base99_floor_v019_repair_report.json"
FLOOR_COLLECTION_SUFFIX = "_原砖与深化内容_资产包"
LOFT_COLLECTION_NAME = "116_二楼地板色彩深化_资产包"
REUSED_BASE_MARKERS = ("保留地板", "普通地板_主体", "带铆钉地板_主体", "输出根节点")
BOTTOM_NORMAL_MAX_Z = -0.95
LOGO_LIFTS_M = {
    "BASE门前_三角Logo边_2": 0.001,
    "BASE门前_三角Logo边_3": 0.002,
}


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


def lift_logo_joint_meshes() -> list[str]:
    lifted: list[str] = []
    for name, lift in LOGO_LIFTS_M.items():
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError(f"Missing expected logo-joint mesh: {name}")
        obj.matrix_world = Matrix.Translation((0.0, 0.0, lift)) @ obj.matrix_world
        lifted.append(name)
    return lifted


def remove_residual_downward_faces(objects: list[bpy.types.Object]) -> int:
    total = 0
    for obj in objects:
        if obj.modifiers:
            raise RuntimeError(f"Refusing to edit a modified detail mesh: {obj.name}")
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        bm = bmesh.new()
        try:
            bm.from_mesh(obj.data)
            bm.normal_update()
            faces = [
                face
                for face in bm.faces
                if (normal_matrix @ face.normal).normalized().z < BOTTOM_NORMAL_MAX_Z
            ]
            if faces:
                total += len(faces)
                bmesh.ops.delete(bm, geom=faces, context="FACES")
                bm.to_mesh(obj.data)
                obj.data.update()
        finally:
            bm.free()
    return total


def main() -> None:
    if Path(bpy.data.filepath).name != "base_facility_runtime_layout_hq_v018.blend":
        raise RuntimeError(f"Expected v018 input, got {bpy.data.filepath}")
    lifted = lift_logo_joint_meshes()
    removed = remove_residual_downward_faces(selected_detail_objects())
    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
    REPORT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    REPORT_OUTPUT.write_text(
        json.dumps(
            {
                "input_blend": "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v018.blend",
                "output_blend": str(OUTPUT_BLEND.relative_to(PROJECT_ROOT)),
                "version": "v019",
                "lifted_logo_joint_meshes": lifted,
                "logo_joint_lifts_m": LOGO_LIFTS_M,
                "removed_residual_downward_faces": removed,
            },
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )
    print(f"BASE99_FLOOR_V019_BLEND_WRITTEN:{OUTPUT_BLEND}")
    print(f"LIFTED_LOGO_JOINT_MESHES:{len(lifted)}")
    print(f"REMOVED_RESIDUAL_DOWNWARD_FACES:{removed}")


if __name__ == "__main__":
    main()
