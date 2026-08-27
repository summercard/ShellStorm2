"""Validate source structure and visible bounds for the first elite asset."""

import bpy
from mathutils import Vector


EXPECTED_ASSET_ID = "ENM-ELITE-RIFT-BOAR-ARMED-3D"
EXPECTED_COLLECTION = "游戏输出_背枪的裂口爬虫"


def main():
    failures = []
    collection = bpy.data.collections.get(EXPECTED_COLLECTION)
    if collection is None:
        failures.append("missing output collection")
        collection_objects = []
    else:
        collection_objects = list(collection.all_objects)
    root = bpy.data.objects.get("精英根_背枪的裂口爬虫")
    if root is None or root.get("asset_id") != EXPECTED_ASSET_ID:
        failures.append("missing stable asset metadata")
    meshes = [obj for obj in collection_objects if obj.type == "MESH"]
    materials = {slot.material.name for obj in meshes for slot in obj.material_slots if slot.material}
    semantics = {str(obj.get("semantic_component", "")) for obj in meshes}
    required = {"core", "shell", "appendages", "weapon_attachment", "state_vfx"}
    if not required.issubset(semantics):
        failures.append(f"missing semantic components: {sorted(required - semantics)}")
    if len(materials) != 4:
        failures.append(f"material budget is {len(materials)}, expected 4")
    if len(meshes) != 18:
        failures.append(f"mesh count is {len(meshes)}, expected 18")
    corners = []
    for obj in meshes:
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if corners:
        minimum = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
        maximum = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
        size = maximum - minimum
        if minimum.z < -0.001 or size.x > 2.05 or size.y > 2.35 or size.z > 2.15:
            failures.append(f"invalid bounds min={tuple(minimum)} size={tuple(size)}")
        print(f"BOUNDS_MIN={tuple(round(v, 4) for v in minimum)} BOUNDS_SIZE={tuple(round(v, 4) for v in size)}")
    if any(obj for obj in collection_objects if obj.type in {"CAMERA", "LIGHT"}):
        failures.append("output collection contains review camera/light")
    if failures:
        raise RuntimeError("; ".join(failures))
    print(f"ELITE_RIFT_BOAR_ASSET_OK: meshes={len(meshes)} materials={sorted(materials)} semantics={sorted(semantics)}")


main()
