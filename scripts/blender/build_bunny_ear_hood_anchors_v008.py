"""Create Bunny v008 with ear pivots centered on the hood contact bands."""

from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v007.blend"
OUTPUT_BLEND = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v008.blend"


def _world_vertices(obj: bpy.types.Object) -> list[Vector]:
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


def _head_bvh() -> BVHTree:
    head = bpy.data.objects["SRC_Head"]
    return BVHTree.FromPolygons(
        _world_vertices(head),
        [[index for index in polygon.vertices] for polygon in head.data.polygons],
    )


def _contact_center(ear_name: str, head_bvh: BVHTree) -> Vector:
    points: list[Vector] = []
    for vertex in _world_vertices(bpy.data.objects[ear_name]):
        nearest = head_bvh.find_nearest(vertex)
        if nearest is not None and nearest[3] <= 0.025 and vertex.z <= 1.10:
            points.append(vertex)
    if not points:
        raise RuntimeError(f"No hood contact band found for {ear_name}")
    return sum(points, Vector()) / len(points)


def _move_pivot_preserving_child_world(
    pivot_name: str,
    child_name: str,
    target: Vector,
) -> None:
    pivot = bpy.data.objects[pivot_name]
    child = bpy.data.objects[child_name]
    child_world = child.matrix_world.copy()
    pivot.location = target
    pivot["animation_anchor_contract"] = "ear_hood_contact_center"
    bpy.context.view_layer.update()
    child.parent = pivot
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.matrix_basis = pivot.matrix_world.inverted() @ child_world


def main() -> None:
    if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError(f"Expected source Blend {SOURCE_BLEND}, got {bpy.data.filepath}")
    head_bvh = _head_bvh()
    raw_l = _contact_center("SRC_Ear_L_Mirror", head_bvh)
    raw_r = _contact_center("SRC_Ear_R", head_bvh)
    half_x = (abs(raw_l.x) + abs(raw_r.x)) * 0.5
    shared_y = (raw_l.y + raw_r.y) * 0.5
    shared_z = (raw_l.z + raw_r.z) * 0.5
    ear_l = Vector((-half_x, shared_y, shared_z))
    ear_r = Vector((half_x, shared_y, shared_z))
    _move_pivot_preserving_child_world("PIVOT_EAR_L", "SRC_Ear_L_Mirror", ear_l)
    _move_pivot_preserving_child_world("PIVOT_EAR_R", "SRC_Ear_R", ear_r)
    bpy.context.scene["character_anchor_version"] = "v008"
    bpy.context.scene["ear_anchor_contract"] = (
        "Ear pivots use mirrored hood-contact-band centers; static ear mesh world matrices are preserved."
    )
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"BUNNY_EAR_ANCHORS_V008=ear_l={tuple(ear_l)} ear_r={tuple(ear_r)} output={OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
