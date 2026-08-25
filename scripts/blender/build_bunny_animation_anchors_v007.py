"""Create Bunny v007 with hand-ring and ear-root animation anchors."""

from pathlib import Path

import bpy
from mathutils import Matrix, Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"
OUTPUT_BLEND = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v007.blend"
ACCESSORY_BLEND = PROJECT_ROOT / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/accessories/head/chibi_anime_head_v001/source/chr_player_bunny01_head_chibi_anime_source_v001.blend"
ACCESSORY_COLLECTION = "二次元头部配件_中文管理"


def _world_vertices(name: str) -> list[Vector]:
    obj = bpy.data.objects[name]
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


def _center(name: str) -> Vector:
    vertices = _world_vertices(name)
    return sum(vertices, Vector()) / len(vertices)


def _ear_root(name: str) -> Vector:
    vertices = _world_vertices(name)
    minimum_z = min(vertex.z for vertex in vertices)
    maximum_z = max(vertex.z for vertex in vertices)
    threshold = minimum_z + max(0.01, (maximum_z - minimum_z) * 0.06)
    base = [vertex for vertex in vertices if vertex.z <= threshold]
    center = sum(base, Vector()) / len(base)
    center.z = minimum_z
    return center


def _bind_preserving_world(child_name: str, pivot_name: str) -> None:
    child = bpy.data.objects[child_name]
    pivot = bpy.data.objects[pivot_name]
    world_matrix = child.matrix_world.copy()
    child.parent = pivot
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.matrix_basis = pivot.matrix_world.inverted() @ world_matrix


def _merge_accessory_collection() -> None:
    existing = bpy.data.collections.get(ACCESSORY_COLLECTION)
    if existing is not None:
        return
    with bpy.data.libraries.load(str(ACCESSORY_BLEND), link=False) as (source, destination):
        if ACCESSORY_COLLECTION not in source.collections:
            raise RuntimeError(f"Accessory collection missing: {ACCESSORY_COLLECTION}")
        destination.collections = [ACCESSORY_COLLECTION]
    imported = destination.collections[0]
    if imported is None:
        raise RuntimeError("Accessory collection failed to load")
    bpy.context.scene.collection.children.link(imported)


def main() -> None:
    if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError(f"Expected source Blend {SOURCE_BLEND}, got {bpy.data.filepath}")

    hand_l = _center("SRC_Hand_Cuff_L")
    hand_r = _center("SRC_Hand_Cuff_R")
    ear_l = _ear_root("SRC_Ear_L_Mirror")
    ear_r = _ear_root("SRC_Ear_R")
    targets = {
        "PIVOT_HAND_L": hand_l,
        "PIVOT_HAND_R": hand_r,
        "PIVOT_EAR_L": ear_l,
        "PIVOT_EAR_R": ear_r,
    }
    for pivot_name, location in targets.items():
        pivot = bpy.data.objects[pivot_name]
        pivot.location = location
        pivot["animation_anchor_contract"] = (
            "hand_ring_center" if "HAND" in pivot_name else "ear_base_contact_center"
        )
    bpy.context.view_layer.update()

    for child_name in ("SRC_Hand_Main_L", "SRC_Hand_Cuff_L"):
        _bind_preserving_world(child_name, "PIVOT_HAND_L")
    for child_name in ("SRC_Hand_Main_R", "SRC_Hand_Cuff_R"):
        _bind_preserving_world(child_name, "PIVOT_HAND_R")
    _bind_preserving_world("SRC_Ear_L_Mirror", "PIVOT_EAR_L")
    _bind_preserving_world("SRC_Ear_R", "PIVOT_EAR_R")

    _merge_accessory_collection()
    bpy.context.scene["character_anchor_version"] = "v007"
    bpy.context.scene["character_anchor_contract"] = (
        "Hands rotate at cuff-ring centers; ears rotate at bottom contact centers; static mesh world matrices preserved."
    )
    bpy.context.scene["character_accessory_maintenance_source"] = str(
        ACCESSORY_BLEND.relative_to(PROJECT_ROOT)
    ).replace("\\", "/")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(
        "BUNNY_ANCHORS_V007="
        f"hand_l={tuple(hand_l)} hand_r={tuple(hand_r)} "
        f"ear_l={tuple(ear_l)} ear_r={tuple(ear_r)} output={OUTPUT_BLEND}"
    )


if __name__ == "__main__":
    main()
