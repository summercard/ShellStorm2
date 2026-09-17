import bpy, sys
from pathlib import Path
O=Path(__file__).resolve().parents[1]
s=bpy.data.scenes['天台_参考拼装展示']
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
names=['01_参考镜头全景','02_俯视结构','03_房间设备近景','04_外墙接口']
if 'draft' in args:names=names[:1];s.render.resolution_percentage=55;s.cycles.samples=12
for name in names:
    s.camera=bpy.data.objects[name];s.render.filepath=str(O/'renders'/((name+'_draft' if 'draft' in args else name)+'.png'))
    bpy.ops.render.render(write_still=True,scene=s.name)
