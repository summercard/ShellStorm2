import bpy
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DERIVATIVE = ROOT / "source/art/blender/base_facility_layout/export/v024/base_facility_runtime_layout_hq-v024-corner_l_5m.blend"
OUTPUT = ROOT / "assets/art/environments/base_facility_3d/components/env_base99_corner_l_5m/env_base99_corner_l_5m_visual_top3d_v001.glb"
OBJECT_NAME = "env_base99_corner_l_5m_visual_top3d_v001"


def main():
    if not DERIVATIVE.exists():
        raise RuntimeError(f"Derivative must be created before export: {DERIVATIVE}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(DERIVATIVE))
    visual = bpy.data.objects.get(OBJECT_NAME)
    if visual is None or visual.type != "MESH":
        raise RuntimeError(f"Derivative visual missing: {OBJECT_NAME}")
    bpy.ops.object.select_all(action="DESELECT")
    visual.select_set(True)
    bpy.context.view_layer.objects.active = visual
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_lights=False,
        export_cameras=False,
        export_materials="EXPORT",
        export_image_format="NONE",
    )
    print("BASE99_CORNER_GLB_EXPORT=" + json.dumps({
        "derivative": str(DERIVATIVE),
        "glb": str(OUTPUT),
        "triangles": len(visual.data.polygons),
        "uv_layers": [layer.name for layer in visual.data.uv_layers],
        "materials": [material.name for material in visual.data.materials if material],
    }, ensure_ascii=False))


main()
