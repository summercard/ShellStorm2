import bpy,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];s=bpy.context.scene
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_percentage=100
s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast'
display=bpy.data.collections['90_展示与验收_沿用v016镜头']
def cam(name,pos,target,scale):
    o=bpy.data.objects.get(name) or bpy.data.objects.new(name,bpy.data.cameras.new(name))
    if not o.users_collection:display.objects.link(o)
    o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();o.data.type='ORTHO';o.data.ortho_scale=scale;return o
views=[
 ('dual_overview',cam('验收摄像机_v021_双楼梯总览',(20,-78,64),(0,0,-5),112),1500,1050),
 ('dual_top',cam('验收摄像机_v021_双楼梯定位顶视',(0,0,120),(0,0,-5),112),1500,850),
 ('stair_a_100_99',cam('验收摄像机_v021_楼梯A',(0,-50,32),(-40,-12,-1),43),1100,1250),
 ('stair_b_99_98',cam('验收摄像机_v021_楼梯B',(18,49,36),(40,11,-8),43),1100,1250),
]
records=[]
for name,c,w,h in views:
    s.camera=c;s.render.resolution_x=w;s.render.resolution_y=h;s.render.filepath=str(ROOT/'renders'/f'{name}.png');bpy.ops.render.render(write_still=True)
    records.append({'name':name,'camera':c.name,'position':list(c.location),'rotation':list(c.rotation_euler),'ortho_scale':c.data.ortho_scale,'resolution':[w,h]})
s.camera=views[1][1]
(ROOT/'qa'/'camera_records.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('V021_RENDERS_OK',len(views))
