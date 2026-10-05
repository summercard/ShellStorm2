import bpy
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
BLEND = PROJECT / "assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v001.blend"
GLB = PROJECT / "assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb"
OUT_DIR = PROJECT / "outputs/base99_radio_v001"
ROLE_CELLS = {
    "01_精工金属_紫色骨架": (2, 2),
    "02_细腻哑光_青绿大面": (1, 4),
    "03_清漆反光_紫粉点缀": (3, 1),
    "04_柔和自发光_UI灯光": (7, 4),
}

def apply_role_uv(obj):
    if obj.type != 'MESH' or not obj.data.uv_layers.get('PaletteUV'):
        return
    uv = obj.data.uv_layers.get('PaletteUV')
    mats = list(obj.data.materials)
    for poly in obj.data.polygons:
        role = mats[poly.material_index].name if poly.material_index < len(mats) else "02_细腻哑光_青绿大面"
        col, row = ROLE_CELLS.get(role, ROLE_CELLS["02_细腻哑光_青绿大面"])
        center = ((col + 0.5) / 10.0, (row + 0.5) / 10.0)
        n = len(poly.loop_indices)
        for i, loop_index in enumerate(poly.loop_indices):
            angle = 2.0 * 3.141592653589793 * i / max(3, n) + 0.20
            uv.data[loop_index].uv = (center[0] + 0.020 * __import__('math').cos(angle), center[1] + 0.020 * __import__('math').sin(angle))
    obj.data.uv_layers.active = uv
    uv.active_render = True

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
source = bpy.data.collections.get("01_制作组件_已统一材质")
output = bpy.data.collections.get("02_游戏输出_独立资产包_v001")
source_light = next((obj for obj in source.all_objects if obj.type == 'MESH' and obj.get("runtime_override_node")), None) if source else None
output_light = next((obj for obj in output.all_objects if obj.type == 'MESH' and obj.get("runtime_override_node")), None) if output else None
if source_light:
    source_light.name = "StatusLight_UI灯光_柔和自发光_Source"
    source_light["runtime_interface_name"] = "StatusLight"
if output_light:
    output_light.name = "StatusLight_UI灯光_柔和自发光"
    output_light["runtime_interface_name"] = "StatusLight"

for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    uv = obj.data.uv_layers.get("PaletteUV")
    for layer in list(obj.data.uv_layers):
        if layer.name != "PaletteUV":
            obj.data.uv_layers.remove(layer)
    if uv:
        obj.data.uv_layers.active = obj.data.uv_layers.get("PaletteUV")
        obj.data.uv_layers.get("PaletteUV").active_render = True

# Keep the descriptive Blender name; the export-only rename below preserves the exact GLB runtime node.

for mat in list(bpy.data.materials):
    if mat.name == "Material" and mat.users == 0:
        bpy.data.materials.remove(mat)

for obj in bpy.data.objects:
    apply_role_uv(obj)

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print("fixed source names without touching GLB", BLEND, GLB)
