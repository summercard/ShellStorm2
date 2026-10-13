"""Fixed before/after contact sheets; render outside the repository."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_room02_import/fidelity.json').parent
D=R/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v027'
m=json.loads((D/'import_manifest.json').read_text('utf8'));bpy.ops.wm.read_factory_settings(use_empty=True)
s=bpy.context.scene;before=bpy.data.collections.new('Before');after=bpy.data.collections.new('After');s.collection.children.link(before);s.collection.children.link(after);checks=[]
for j,d in enumerate(m['components']):
 cols=[]
 for path in [d['source_path'],d['optimized_path']]:
  with bpy.data.libraries.load(str(R/path),link=False) as (a,z):z.collections=[d['collection']]
  cols.append(z.collections[0])
 points=[[o.matrix_basis@v.co for o in c.objects for v in o.data.vertices] for c in cols]
 delta=max(abs(fn(v[i] for v in points[0])-fn(v[i] for v in points[1])) for i in range(3) for fn in [min,max]);assert delta<1e-5
 checks.append({'slug':d['slug'],'bbox_delta':delta,'optimized_reopened':True})
 for dest,c in zip([before,after],cols):
  o=bpy.data.objects.new(d['slug'],None);o.instance_type='COLLECTION';o.instance_collection=c;o.scale=(3/max(d['bounds_size_m']),)*3;o.location=((j%8)*4,(j//8)*4,0);dest.objects.link(o)
world=bpy.data.worlds.new('Neutral');s.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.22,.24,.28,1);world.node_tree.nodes['Background'].inputs[1].default_value=.7
ld=bpy.data.lights.new('Softbox','AREA');ld.energy=5000;ld.size=24;o=bpy.data.objects.new('Softbox',ld);s.collection.objects.link(o);o.location=(12,8,22)
cd=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',cd);s.collection.objects.link(cam);s.camera=cam;cd.type='ORTHO';cd.ortho_scale=39
s.render.engine='CYCLES';s.cycles.samples=12;s.cycles.use_denoising=True;s.cycles.seed=41
try:
 p=bpy.context.preferences.addons['cycles'].preferences;p.compute_device_type='OPTIX';p.get_devices()
 for device in p.devices:device.use=device.type!='CPU'
 s.cycles.device='GPU'
except Exception:pass
s.render.resolution_x=1600;s.render.resolution_y=1000;s.render.resolution_percentage=100
target=Vector((14,10,1))
for view,offset in [('front',(0,-40,15)),('back',(0,40,15)),('side',(40,0,15)),('game',(22,-35,38))]:
 cam.location=target+Vector(offset);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
 for label in ['before','after']:
  before.hide_render=label!='before';after.hide_render=label!='after';s.render.filepath=str(W/('fidelity_'+view+'_'+label+'.png'));bpy.ops.render.render(write_still=True)
(W/'fidelity_geometry.json').write_text(json.dumps({'components':checks,'views':['front','back','side','game']},indent=2),encoding='utf8')
