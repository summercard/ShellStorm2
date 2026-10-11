"""Export the v0.1 2.2 m x 2.5 m tower door module from v007."""

from pathlib import Path

import bpy


SOURCE_DIR = Path(__file__).resolve().parent
SOURCE_BLEND = SOURCE_DIR / "env_tower_descent_kit_top3d_v007.blend"
OUTPUT = (
    SOURCE_DIR.parent
    / "components/env_tower_wall_door_5m_top3d_v002.glb"
)
COLLECTION_NAME = "10D_MOD_WALL_DOOR_5M_U01"

if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))

collection = bpy.data.collections.get(COLLECTION_NAME)
if collection is None:
    raise RuntimeError(f"Missing door collection: {COLLECTION_NAME}")

bpy.ops.object.select_all(action="DESELECT")
selected = []


def collect_objects(source_collection):
    result = list(source_collection.objects)
    for child_collection in source_collection.children:
        result.extend(collect_objects(child_collection))
    return result


for obj in collect_objects(collection):
    if obj.type not in {"MESH", "EMPTY"}:
        continue
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.hide_render = False
    obj.select_set(True)
    selected.append(obj)

if not any(obj.type == "MESH" for obj in selected):
    raise RuntimeError("Door collection contains no meshes")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_extras=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_animations=False,
)
print(f"EXPORT_DOOR_V002_OK output={OUTPUT} selected={len(selected)}")
