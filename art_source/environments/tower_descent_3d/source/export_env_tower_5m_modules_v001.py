from pathlib import Path

import bpy


SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

EXPORTS = {
    "10A_MOD_FLOOR_TILE_5M_U01": "env_tower_floor_tile_5m_top3d_v001.glb",
    "10B_MOD_WALL_SOLID_5M_U01": "env_tower_wall_solid_5m_top3d_v002.glb",
    "10C_MOD_WALL_PARAPET_5M_U01": "env_tower_wall_parapet_5m_top3d_v001.glb",
    "10D_MOD_WALL_DOOR_5M_U01": "env_tower_wall_door_5m_top3d_v001.glb",
}


def export_collection(collection_name: str, filename: str) -> None:
    collection = bpy.data.collections.get(collection_name)
    if collection is None:
        raise RuntimeError(f"Missing module collection: {collection_name}")

    bpy.ops.object.select_all(action="DESELECT")
    def collect_objects(source_collection):
        result = list(source_collection.objects)
        for child_collection in source_collection.children:
            result.extend(collect_objects(child_collection))
        return result

    selected = []
    for obj in collect_objects(collection):
        if obj.type not in {"MESH", "EMPTY"}:
            continue
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
        selected.append(obj)

    if not any(obj.type == "MESH" for obj in selected):
        raise RuntimeError(f"Module collection has no mesh: {collection_name}")

    output_path = OUTPUT_DIR / filename
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    print(f"EXPORTED {collection_name} -> {output_path}")


for module_collection, module_filename in EXPORTS.items():
    export_collection(module_collection, module_filename)

print(f"EXPORT_OK count={len(EXPORTS)} output={OUTPUT_DIR}")
