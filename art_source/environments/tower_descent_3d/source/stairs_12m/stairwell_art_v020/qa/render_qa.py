import bpy, json, os
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
s=bpy.context.scene
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_percentage=100
s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=0;s.view_settings.gamma=1
def camera(name,pos,target,scale):
    o=bpy.data.objects.get(name)
    if not o:
        o=bpy.data.objects.new(name,bpy.data.cameras.new(name));bpy.data.collections['90_展示与验收_沿用v016镜头'].objects.link(o)
    o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();o.data.type='ORTHO';o.data.ortho_scale=scale;return o
views=[
 ('wall_focus',bpy.data.objects['验收摄像机_v018_主墙与开口'],1200,1050),
 ('overview',camera('验收摄像机_v020_参考总览',(22,49,36),(40,11,-8),42),1100,1350),
 ('top',camera('验收摄像机_v020_顶视',(40,12,45),(40,12,-10),36),850,1350),
 ('floor_close',camera('验收摄像机_v020_楼板表面',(37,9,0),(40,.5,-9),17),1200,950),
 ('railing_opening',bpy.data.objects['验收摄像机_v019_对面删墙纠正'],1100,1050),
]
records=[]
for name,cam,w,h in views:
    s.camera=cam;s.render.resolution_x=w;s.render.resolution_y=h;s.render.filepath=str(ROOT/'renders'/f'{name}.png')
    bpy.ops.render.render(write_still=True)
    records.append({'name':name,'camera':cam.name,'position':list(cam.location),'rotation':list(cam.rotation_euler),'type':cam.data.type,'lens':cam.data.lens,'ortho_scale':cam.data.ortho_scale,'resolution':[w,h]})
s.camera=views[0][1];s.render.resolution_x=1200;s.render.resolution_y=1050
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.overlay.show_overlays=False
(ROOT/'qa'/'camera_records.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('RENDER_QA_DONE',len(views))
