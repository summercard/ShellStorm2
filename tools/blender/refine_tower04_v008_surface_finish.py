"""Finish the unregistered v008 draft, with a checksum guard and recoverable backup."""
import bpy,json,hashlib,math,random,shutil,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
F=R/'assets/art/environments/open_world/source/tower_04/v008'
B=next(F.glob('*.blend'))
EXPECTED='7fce8cd7f3777c047f42242f74759953e86f43037d2f302590b768ebef2eee67'
assert hashlib.sha256(B.read_bytes()).hexdigest()==EXPECTED,'Draft changed; do not overwrite'
backup=R.parent/'_scratch/tower04_v008_before_surface_finish.blend'
assert not backup.exists(),'Do not replay this draft transaction'
shutil.copy2(B,backup)
lock=json.loads((F/'qa/locked_before.json').read_text(encoding='utf8'))
# Read the real parent metadata; never assume all historical packages had one version.
bpy.ops.wm.open_mainfile(filepath=str(next((F.parent/'v006').glob('*.blend'))))
versions={n:bpy.data.objects[n].get('version') for n in lock['objects']}
(F/'qa/locked_baseline_versions.json').write_text(json.dumps(versions,ensure_ascii=False,indent=2),encoding='utf8')
bpy.ops.wm.open_mainfile(filepath=str(B))
cat=json.loads((F/'catalog.json').read_text(encoding='utf8'));mats=cat['material_roles'];changed={}
for o in bpy.data.objects:
 if o.type!='MESH':continue
 slug=o.get('package_id','').split('/')[-1]
 if not slug.startswith(('tile_r','leaf_canopy_x','glass_pavilion_x')):continue
 uv=o.data.uv_layers['PaletteUV'];n=0
 rng=random.Random(slug+'aged8');tile=rng.choice([(9,7),(9,8),(9,8),(9,8)])
 for face in o.data.polygons:
  inds=face.loop_indices
  c=(int(sum(uv.data[i].uv.x for i in inds)/len(inds)*10),int((1-sum(uv.data[i].uv.y for i in inds)/len(inds))*10))
  mi=mats.index(o.data.materials[face.material_index].name)
  target=None
  if slug.startswith('tile_r') and c in ((9,9),(9,8)) and face.area>.16:target=tile
  elif not slug.startswith('tile_r') and mi==0 and c[0]==9:
   target=rng.choice([(6,2),(6,2),(7,2),(9,5),(9,6),(9,7)])
  if target is not None:
   for i in inds:uv.data[i].uv.x+=(target[0]-c[0])*.1;uv.data[i].uv.y-=(target[1]-c[1])*.1
   n+=1
 if n:changed[o.name]=n
mood=bpy.data.scenes['塔4_黄昏末世氛围'];mood.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.18
sun=bpy.data.objects['末世夕阳'];sun.data.energy=4.0;sun.data.color=(1.0,.72,.43)
mood.view_settings.exposure=-.15
cam=bpy.data.objects['CAM_末世_平台总览'];cam.rotation_euler=(Vector((0,2,12))-cam.location).to_track_quat('-Z','Y').to_euler()
assert hashlib.sha256(B.read_bytes()).hexdigest()==EXPECTED
bpy.context.window.scene=bpy.data.scenes['Scene']
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(B))
digest=hashlib.sha256(B.read_bytes()).hexdigest()
report={'passed':True,'backup':str(backup),'prior_sha256':EXPECTED,'source_sha256':digest,'changed_surface_objects':changed,'geometry_changed':False,'material_nodes_changed':False,'scope':'Existing editable paving and canopy/frame palette faces; mood lighting and overview framing'}
(F/'qa/surface_finish.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
build=json.loads((F/'qa/overgrowth_build.json').read_text(encoding='utf8'));build['source_sha256']=digest;build['surface_finish']='qa/surface_finish.json'
(F/'qa/overgrowth_build.json').write_text(json.dumps(build,ensure_ascii=False,indent=2),encoding='utf8')
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for d in prefs.devices:d.use=d.type!='CPU'
bpy.context.window.scene=mood;mood.cycles.device='GPU';mood.cycles.samples=48
for name in ['CAM_末世_平台总览','CAM_末世_棚下主街','CAM_末世_营地设施近景']:
 mood.camera=bpy.data.objects[name];mood.render.resolution_x=1600;mood.render.resolution_y=1000;mood.render.resolution_percentage=100
 mood.render.filepath=str(F/'mood'/(name[4:]+'.png'));bpy.ops.render.render(write_still=True,scene=mood.name)
print('FINISHED',digest,len(changed),flush=True)
