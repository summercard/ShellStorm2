"""Cut the old terrace guard at the new stair entrance, preserving all other objects."""
import bpy,bmesh,json,sys,hashlib,shutil,math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent));import tower04_court_common as H
from tower04_lower_structure_common import object_signature
R=H.R;F=R/'assets/art/environments/open_world/source/tower_04/v010';cat=json.loads((F/'catalog.json').read_text(encoding='utf8'));path=R/cat['source_blend']
assert hashlib.sha256(path.read_bytes()).hexdigest()==cat['source_sha256'];backup=R.parent/'_scratch/tower04_v010/roof_before_portal.blend';assert not backup.exists();shutil.copy2(path,backup)
bpy.ops.wm.open_mainfile(filepath=str(path));H.setup_materials();sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
slugs={'terrace_rail_x01_y03','terrace_rail_x02_y03'};changed=[]
def cut(o):
 part=H.Part('portal','旋梯入口栏杆切口','support');old=o.data
 for x,normal in [(-58.52,(-1,0,0)),(-54.52,(1,0,0))]:
  bm=bmesh.new();bm.from_mesh(old);bm.transform(o.matrix_world)
  bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=(x,0,0),plane_no=normal,clear_inner=True)
  uv=bm.loops.layers.uv.active
  for f in bm.faces:
   q=sum((l[uv].uv for l in f.loops),Vector((0,0)))/len(f.loops);color=(max(0,min(9,int(q.x*10))),max(0,min(9,int((1-q.y)*10))))
   part.poly([v.co[:] for v in f.verts],[tuple(range(len(f.verts)))],color,f.material_index)
  bm.free()
 m,origin,dims=H.mesh_of(part);inv=o.matrix_world.inverted()
 for v in m.vertices:v.co=inv@(v.co+origin)
 o.data=m
 if old.users==0:bpy.data.meshes.remove(old)
 changed.append(o.name)
for p in cat['packages']:
 if p['slug'] in slugs:
  for key in ('collection','source_collection'):
   for o in bpy.data.collections[p[key]].objects:cut(o)
  p['component_revision']='v010';p['stair_portal_clear_x']=[-58.52,-54.52]
  q=F/'component_packages'/p['category']/p['slug']/'asset_manifest.json';q.write_text(json.dumps(p,ensure_ascii=False,indent=2),encoding='utf8')
locked=json.loads((F/'qa/locked_before.json').read_text(encoding='utf8'));assert all(object_signature(bpy.data.objects[n])==v for n,v in locked.items() if n not in changed)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(path));cat['source_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();(F/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf8')
report=dict(passed=True,source_sha256=cat['source_sha256'],changed_objects=changed,reason='新增旋梯接口需要切开原连廊护栏',clear_width=4.,locked_match=True,locked_objects=len(locked)-len(changed));(F/'qa/stair_portal.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
H.render(sc,bpy.data.objects['CAM_旋梯接口'],F/'previews/旋梯与升层.png');H.render(sc,bpy.data.objects['CAM_参考全景'],F/'previews/参考全景.png',(1600,1000))
# The same two original rail objects exist in the far representation; keep the portal consistent.
far=json.loads((F/'far_catalog.json').read_text(encoding='utf8'));path=R/far['source_blend'];assert hashlib.sha256(path.read_bytes()).hexdigest()==far['source_sha256'];shutil.copy2(path,R.parent/'_scratch/tower04_v010/far_before_portal.blend')
bpy.ops.wm.open_mainfile(filepath=str(path));H.setup_materials()
for o in list(bpy.data.objects):
 if o.get('source_package','').split('/')[-1] in slugs:cut(o)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(path));far['source_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();far['parent_sha256']=cat['source_sha256'];far['visible_triangles']=H.tri_count(bpy.context.scene.objects);far['tower_after_triangles']=far['visible_triangles']-far['court_triangles'];(F/'far_catalog.json').write_text(json.dumps(far,ensure_ascii=False,indent=2),encoding='utf8')
H.render(bpy.context.scene,bpy.context.scene.camera,F/'previews/塔4与塔4-2_远景合景.png',(1800,1100),48)
