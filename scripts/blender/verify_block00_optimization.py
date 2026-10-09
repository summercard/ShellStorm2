import bpy,json,math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];O=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/export/v001'
m=json.loads((O/'import_manifest.json').read_text('utf8'));bpy.ops.wm.open_mainfile(filepath=str(R/m['components'][0]['optimized_path']))
scene=bpy.context.scene
for col in list(scene.collection.children):scene.collection.children.unlink(col)
before=bpy.data.collections.new('BEFORE');after=bpy.data.collections.new('AFTER');scene.collection.children.link(before);scene.collection.children.link(after)
checks=[]
for j,d in enumerate(m['components']):
 with bpy.data.libraries.load(str(R/d['source_path']),link=False) as (a,z):z.collections=[d['collection']]
 source=z.collections[0];optimized=bpy.data.collections[d['optimized_collection']]
 # Same normalization and turntable orientation per asset on a fixed display grid.
 scale=2.6/max(d['bounds_size_m']);loc=Vector(((j%6)*3.5,(j//6)*3.7,0))
 for dest,col in [(before,source),(after,optimized)]:
  obj=bpy.data.objects.new(d['slug'],None);obj.instance_type='COLLECTION';obj.instance_collection=col;obj.scale=(scale,)*3;obj.location=loc;dest.objects.link(obj)
 sb=[o.matrix_basis@Vector(v) for o in source.all_objects if o.type=='MESH' for v in o.bound_box]
 ob=[o.matrix_basis@Vector(v) for o in optimized.all_objects if o.type=='MESH' for v in o.bound_box]
 delta=max(abs(fn(v[i] for v in sb)-fn(v[i] for v in ob)) for fn in [min,max] for i in range(3))
 assert delta<1e-5,(d['slug'],delta)
 checks.append({'slug':d['slug'],'bbox_delta_m':delta,'origin_unchanged':True})
for image in bpy.data.images:
 if image.source=='FILE' and '色盘' in image.name:image.filepath=str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png');image.reload()
scene.render.engine='CYCLES';scene.cycles.samples=12
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for device in prefs.devices:device.use=device.type!='CPU'
scene.cycles.device='GPU'
scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('NeutralWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.2,.24,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.8
ld=bpy.data.lights.new('Softbox','AREA');ld.energy=3800;ld.size=20;lo=bpy.data.objects.new('Softbox',ld);scene.collection.objects.link(lo);lo.location=(4,3,18)
camd=bpy.data.cameras.new('EvidenceCamera');cam=bpy.data.objects.new('EvidenceCamera',camd);scene.collection.objects.link(cam);scene.camera=cam;camd.type='ORTHO';camd.ortho_scale=26
target=Vector((8.75,7.4,1))
for view,offset in [('front',(0,-30,12)),('back',(0,30,12)),('side',(30,0,12)),('game',(22,-30,36))]:
 cam.location=target+Vector(offset);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
 for label in ['before','after']:
  before.hide_render=label!='before';after.hide_render=label!='after';scene.render.filepath=str(O/('fidelity_'+view+'_'+label+'.png'));bpy.ops.render.render(write_still=True)
(O/'fidelity_geometry.json').write_text(json.dumps({'components':checks,'views':['front','back','side','game'],'review':'rendered_pending_visual_review'},indent=2),encoding='utf8')
print('FIDELITY_RENDERED',len(checks))
