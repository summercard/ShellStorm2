import sys
from pathlib import Path

import bpy


if "--" not in sys.argv:
    raise RuntimeError("Expected output path and Chinese asset name after --")

arguments = sys.argv[sys.argv.index("--") + 1 :]
output_path = Path(arguments[0])
asset_name = arguments[1]

root_name = f"{asset_name}_中文资产管理"
source_name = "01_原始组件_制作过程"
game_name = "02_游戏输出_整合模型"

root = bpy.data.collections.get(root_name) or bpy.data.collections.new(root_name)
if root.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(root)

source = bpy.data.collections.get(source_name) or bpy.data.collections.new(source_name)
game = bpy.data.collections.get(game_name) or bpy.data.collections.new(game_name)
if source.name not in root.children:
    root.children.link(source)
if game.name not in root.children:
    root.children.link(game)
source.hide_viewport = True
source.hide_render = True

meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
for obj in meshes:
    if "PaletteUV" not in obj.data.uv_layers and obj.data.uv_layers.active is not None:
        obj.data.uv_layers.active.name = "PaletteUV"
    if obj.name == "Body":
        obj.name = f"{asset_name}_主体_金属哑光反光"
    elif obj.name == "Emissive":
        obj.name = f"{asset_name}_UI灯光_柔和自发光"
    if obj.name not in game.objects:
        game.objects.link(obj)
    for collection in list(obj.users_collection):
        if collection != game:
            collection.objects.unlink(obj)

bpy.context.scene["asset_name_cn"] = asset_name
bpy.context.scene["asset_structure"] = "中文资产管理/01_原始组件_制作过程/02_游戏输出_整合模型"
bpy.ops.wm.save_as_mainfile(filepath=str(output_path), compress=True)
print(f"NORMALIZED_BLEND {asset_name} -> {output_path}")
