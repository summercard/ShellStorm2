# Run in Blender's scripting workspace, or with blender --background --python rebuild.py.
from pathlib import Path
folder=Path(__file__).resolve().parent
namespace={'__name__':'pink_room_rebuild'}
for fn in ['01_room.py','02_details.py','03_render.py','04_refine.py','05_finish.py','06_layout_clearance.py','07_wall_joint.py']:
 exec(compile((folder/fn).read_text(),str(folder/fn),'exec'),namespace)

import bpy
ref=folder.parent/"reference"/"设计稿.png"
if ref.exists():
 im=bpy.data.images.load(str(ref),check_existing=True);im.name="用户原始设计稿_仅参考";im.pack()
notes=folder.parent/"交付说明.md"
if notes.exists():
 t=bpy.data.texts.get("交付说明") or bpy.data.texts.new("交付说明");t.clear();t.write(notes.read_text())
bpy.ops.wm.save_as_mainfile(filepath=namespace["OUT"]+"/粉色电竞卧室_高还原_v001.blend")
