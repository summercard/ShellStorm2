import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
current=ROOT/'env_tower_stairwell_art_source_v020.blend'
bpy.ops.wm.open_mainfile(filepath=str(current))
light_names=[o.name for o in bpy.context.scene.objects if o.type=='LIGHT']
world_name=bpy.context.scene.world.name
bpy.ops.wm.open_mainfile(filepath=str(ROOT.parent/'stairwell_art_v019/env_tower_stairwell_art_source_v019.blend'))
for o in list(bpy.context.scene.objects):
    if o.type=='LIGHT':bpy.data.objects.remove(o,do_unlink=True)
with bpy.data.libraries.load(str(current),link=True) as (a,b):b.objects=light_names;b.worlds=[world_name]
for o in b.objects:bpy.context.scene.collection.objects.link(o)
s=bpy.context.scene;s.world=b.worlds[0]
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_percentage=100
s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=0;s.view_settings.gamma=1
records=json.loads((ROOT/'qa/camera_records.json').read_text())
for rec in records[:2]:
    cam=bpy.data.objects.new('Before_'+rec['name'],bpy.data.cameras.new('Before_'+rec['name']));s.collection.objects.link(cam)
    cam.location=rec['position'];cam.rotation_euler=rec['rotation'];cam.data.type=rec['type'];cam.data.lens=rec['lens'];cam.data.ortho_scale=rec['ortho_scale']
    s.camera=cam;s.render.resolution_x,s.render.resolution_y=rec['resolution'];s.render.filepath=str(ROOT/'renders'/('before_'+rec['name']+'.png'))
    bpy.ops.render.render(write_still=True)
print('BEFORE_RENDER_DONE_SAME_V020_LIGHTING')
