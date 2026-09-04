"""Export the v017 Base99 floor visual overlays without modifying the source blend.

The 6x6 floor's load-bearing 5m slabs are deliberately *not* exported here:
they are the existing ENV-BASE99-FLOOR-PLAIN-5M and
ENV-BASE99-FLOOR-RIVET-5M runtime modules.  This exporter emits only the
Blender-authored surface treatment and the separate second-floor finish.

Run from the repository root:
  /Applications/Blender.app/Contents/MacOS/Blender --background \\
    source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend \\
    --python scripts/blender/export_base_facility_v017_floor_visuals.py
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bmesh
import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT_ROOT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
COMPONENT_ROOT = PROJECT_ROOT / "assets/art/environments/base_facility_3d/components"
GROUND_OUTPUT = (
    COMPONENT_ROOT
    / "env_base99_floor_details_v017"
    / "env_base99_floor_details_v017_visual_top3d_v001.glb"
)
LOFT_OUTPUT = (
    COMPONENT_ROOT
    / "env_base99_loft_floor_finish_v017"
    / "env_base99_loft_floor_finish_v017_visual_top3d_v001.glb"
)
MANIFEST_OUTPUT = (
    COMPONENT_ROOT
    / "env_base99_floor_details_v017"
    / "env_base99_floor_details_v017_runtime_manifest_v001.json"
)

FLOOR_COLLECTION_SUFFIX = "_原砖与深化内容_资产包"
LOFT_COLLECTION_NAME = "116_二楼地板色彩深化_资产包"
REUSED_BASE_MARKERS = (
    "保留地板",
    "普通地板_主体",
    "带铆钉地板_主体",
    "输出根节点",
)


def floor_collections() -> list[bpy.types.Collection]:
    collections = [
        collection
        for collection in bpy.data.collections
        if collection.name.startswith("地砖_R")
        and collection.name.endswith(FLOOR_COLLECTION_SUFFIX)
    ]
    collections.sort(key=lambda collection: collection.name)
    if len(collections) != 36:
        raise RuntimeError(f"Expected 36 Base99 floor packages, found {len(collections)}")
    return collections


def is_reused_base_object(obj: bpy.types.Object) -> bool:
    return any(marker in obj.name for marker in REUSED_BASE_MARKERS)


def ground_detail_objects(
    collections: list[bpy.types.Collection],
) -> tuple[list[bpy.types.Object], list[dict[str, object]]]:
    details: list[bpy.types.Object] = []
    package_rows: list[dict[str, object]] = []
    for collection in collections:
        objects = list(collection.objects)
        reused = [obj for obj in objects if is_reused_base_object(obj)]
        detail = [obj for obj in objects if obj.type == "MESH" and obj not in reused]
        base_kind = "rivet" if any("带铆钉地板_主体" in obj.name for obj in reused) else "plain"
        if not detail:
            raise RuntimeError(f"Floor package has no detail meshes: {collection.name}")
        details.extend(detail)
        package_rows.append(
            {
                "package_collection": collection.name,
                "runtime_role": "detail_overlay_only",
                "reused_base_asset_id": (
                    "ENV-BASE99-FLOOR-RIVET-5M"
                    if base_kind == "rivet"
                    else "ENV-BASE99-FLOOR-PLAIN-5M"
                ),
                "detail_object_count": len(detail),
                "detail_objects": [obj.name for obj in detail],
            }
        )
    if len({obj.name for obj in details}) != len(details):
        raise RuntimeError("A floor detail mesh belongs to more than one selected package")
    return details, package_rows


def triangulate(mesh_object: bpy.types.Object) -> None:
    """Triangulate an export-only mesh so tangent generation is deterministic."""
    mesh = mesh_object.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def _temporary_joined_meshes(
    objects: list[bpy.types.Object], label: str
) -> tuple[bpy.types.Collection, list[bpy.types.Object]]:
    """Copy source meshes, then combine body and emissive geometry for runtime.

    The Blender master keeps over one thousand individually editable floor-detail
    meshes.  The runtime representation has the same geometry but uses one
    mesh for the three non-emissive shared roles and one mesh for the emissive
    role.  No source object or mesh datablock is changed.
    """
    temporary = bpy.data.collections.new(f"__EXPORT_{label}")
    bpy.context.scene.collection.children.link(temporary)
    groups: dict[str, list[bpy.types.Object]] = {"body": [], "emission": []}
    for source in objects:
        copy = source.copy()
        copy.data = source.data.copy()
        copy.animation_data_clear()
        temporary.objects.link(copy)
        material_names = {
            slot.material.name for slot in copy.material_slots if slot.material is not None
        }
        role = "emission" if material_names == {"04_柔和自发光_UI灯光"} else "body"
        groups[role].append(copy)

    joined: list[bpy.types.Object] = []
    for role, copies in groups.items():
        if not copies:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for copy in copies:
            copy.select_set(True)
        bpy.context.view_layer.objects.active = copies[0]
        bpy.ops.object.join()
        combined = bpy.context.view_layer.objects.active
        combined.name = f"{label}_{'UI灯光' if role == 'emission' else '主体'}"
        triangulate(combined)
        joined.append(combined)
    return temporary, joined


def _delete_temporary_meshes(
    collection: bpy.types.Collection, objects: list[bpy.types.Object]
) -> None:
    for obj in objects:
        mesh = obj.data if obj.type == "MESH" else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    bpy.data.collections.remove(collection)


def export_glb(objects: list[bpy.types.Object], output_path: Path, label: str) -> None:
    if not objects:
        raise RuntimeError(f"No mesh objects supplied for {output_path.name}")
    temporary, export_meshes = _temporary_joined_meshes(objects, label)
    try:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in export_meshes:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = export_meshes[0]
        bpy.context.view_layer.update()
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
            export_image_format="NONE",
            export_extras=True,
            export_cameras=False,
            export_lights=False,
            export_animations=False,
        )
    finally:
        _delete_temporary_meshes(temporary, export_meshes)


def material_names(objects: list[bpy.types.Object]) -> list[str]:
    return sorted(
        {
            slot.material.name
            for obj in objects
            for slot in obj.material_slots
            if slot.material is not None
        }
    )


def build_manifest(
    floor_rows: list[dict[str, object]],
    ground_details: list[bpy.types.Object],
    loft_details: list[bpy.types.Object],
) -> dict[str, object]:
    plain_count = sum(
        row["reused_base_asset_id"] == "ENV-BASE99-FLOOR-PLAIN-5M"
        for row in floor_rows
    )
    rivet_count = len(floor_rows) - plain_count
    return {
        "schema": "shellstorm2.base99.floor_visual_runtime.v1",
        "source_blend": str(SOURCE_BLEND.relative_to(PROJECT_ROOT)),
        "source_blend_sha256": hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest(),
        "version": "v017",
        "coordinate_contract": {
            "blender": "X east, Y north, Z up",
            "godot": "X east, Y up, -Z north",
            "conversion": "GLB export_yup handles Blender Z-up; layout root stays at identity",
        },
        "ground_floor": {
            "asset_id": "ENV-BASE99-FLOOR-DETAILS-V017",
            "visual_glb": str(GROUND_OUTPUT.relative_to(PROJECT_ROOT)),
            "role": "visual_overlay_only",
            "collision_policy": "reuse TowerFloorStage3D shared flat support; no collider in GLB",
            "reused_base_assets": {
                "ENV-BASE99-FLOOR-PLAIN-5M": plain_count,
                "ENV-BASE99-FLOOR-RIVET-5M": rivet_count,
            },
            "detail_mesh_count": len(ground_details),
            "shared_material_roles": material_names(ground_details),
            "packages": floor_rows,
        },
        "loft_floor_finish": {
            "asset_id": "ENV-BASE99-LOFT-FLOOR-FINISH-V017",
            "visual_glb": str(LOFT_OUTPUT.relative_to(PROJECT_ROOT)),
            "role": "visual_overlay_only",
            "collision_policy": "reuse ENV-BASE99-MEZZANINE-20X10-Z5 walkable deck and guard collisions",
            "placement_anchor": "Blender deck top Z=6.0m maps to the existing Godot deck top Y=5.0m",
            "detail_mesh_count": len(loft_details),
            "shared_material_roles": material_names(loft_details),
        },
    }


def main() -> None:
    collections = floor_collections()
    ground_details, floor_rows = ground_detail_objects(collections)
    loft_collection = bpy.data.collections.get(LOFT_COLLECTION_NAME)
    if loft_collection is None:
        raise RuntimeError(f"Missing collection: {LOFT_COLLECTION_NAME}")
    loft_details = [obj for obj in loft_collection.objects if obj.type == "MESH"]
    if not loft_details:
        raise RuntimeError("Second-floor finish collection contains no mesh objects")

    export_glb(ground_details, GROUND_OUTPUT, "Base99FloorDetailsV017")
    export_glb(loft_details, LOFT_OUTPUT, "Base99LoftFloorFinishV017")
    manifest = build_manifest(floor_rows, ground_details, loft_details)
    MANIFEST_OUTPUT.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"BASE99_FLOOR_DETAILS_GLB_WRITTEN:{GROUND_OUTPUT}")
    print(f"BASE99_LOFT_FLOOR_FINISH_GLB_WRITTEN:{LOFT_OUTPUT}")
    print(f"BASE99_FLOOR_RUNTIME_MANIFEST_WRITTEN:{MANIFEST_OUTPUT}")


if __name__ == "__main__":
    main()
