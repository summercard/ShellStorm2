"""Restore tree crown mass in far LOD and remove repetitive large puddle decals."""
import bpy,sys,json,math,hashlib,shutil
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent));import tower04_court_common as H
R=H.R;C=R/'assets/art/environments/open_world/source/tower_04_2/v002';T=R/'assets/art/environments/open_world/source/tower_04/v010'
cat=json.loads((C/'far_catalog.json').read_text(encoding='utf8'));p=R/cat['source_blend']
assert hashlib.sha256(p.read_bytes()).hexdigest()==cat['source_sha256'];backup=R.parent/'_scratch/tower04_v010/far_court_before_crowns.blend';assert not backup.exists();shutil.copy2(p,backup)
bpy.ops.wm.open_mainfile(filepath=str(p));H.setup_materials()
def crown(p,pos,radius,height,seed,low=False):
 x,y,z=pos;n=8;v=[]
 for j in range(1,4):
  for i in range(n):
   t=i*math.tau/n;v.append((x+radius*math.sin(j*math.pi/4)*math.cos(t),y+radius*math.sin(j*math.pi/4)*math.sin(t),z+height*.5+height*.65*math.cos(j*math.pi/4)))
 v.extend([(x,y,z+height*1.15),(x,y,z-height*.15)]);f=[]
 for j in range(2):
  for i in range(n):f.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
 for i in range(n):f.extend([(24,i,(i+1)%n),(25,16+(i+1)%n,16+i)])
 p.poly(v,f,[(3,4),(4,4),(5,4)][seed%3],1)
H.foliage=crown
for d in cat['definitions']:
 if d['family']!='tree' and d['slug']!='paving_2':continue
 part=H.Part(d['slug'],d['display_name'],'court')
 if d['family']=='tree':H.tree(part,int(d['slug'][-1]),True)
 else:part.box((0,0,-.12),(6,6,.24),H.LIGHT,1)
 old=bpy.data.meshes[d['mesh']];new,origin,dims=H.mesh_of(part);oldorigin=Vector(d['origin'])
 # Keep exact placement and local origin contract used by the shared instance list.
 for v in new.vertices:v.co+=origin-oldorigin
 for o in bpy.data.objects:
  if o.type=='MESH' and o.data==old:o.data=new
 bpy.data.meshes.remove(old);new.name=d['mesh'];d['triangles']=sum(len(f.vertices)-2 for f in new.polygons);d['dimensions']=dims
 f=C/'component_packages'/d['slug']/'far_manifest.json';m=json.loads(f.read_text(encoding='utf8'));m.update(triangles=d['triangles'],dimensions=dims);f.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf8')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p));cat['visible_triangles']=H.tri_count(bpy.data.collections['02_游戏输出_分区实例'].all_objects);cat['source_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();(C/'far_catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf8')
print('COURT_CROWNS',cat['visible_triangles'],flush=True)
far=json.loads((T/'far_catalog.json').read_text(encoding='utf8'));path=R/far['source_blend'];assert hashlib.sha256(path.read_bytes()).hexdigest()==far['source_sha256'];shutil.copy2(path,R.parent/'_scratch/tower04_v010/far_before_crown_sync.blend')
bpy.ops.wm.open_mainfile(filepath=str(path));sc=bpy.context.scene;H.setup_materials()
c=bpy.data.collections['塔4-2_远景庭院_分区']
for o in list(c.all_objects):bpy.data.objects.remove(o,do_unlink=True)
for child in list(c.children_recursive):bpy.data.collections.remove(child)
bpy.data.collections.remove(c)
with bpy.data.libraries.load(str(p),link=False) as (a,b):b.collections=['02_游戏输出_分区实例']
c=b.collections[0];c.name='塔4-2_远景庭院_分区';sc.collection.children.link(c)
for o in c.all_objects:
 if o.type=='MESH':
  for i,m in enumerate(o.data.materials):
   base=m.name.split('.')[0]
   if base in H.NAMES:o.data.materials[i]=bpy.data.materials[base]
for m in list(bpy.data.meshes):
 if m.users==0:bpy.data.meshes.remove(m)
for m in list(bpy.data.materials):
 if m.users==0 and m.name not in H.NAMES:bpy.data.materials.remove(m)
# Reset islands after clipping legacy oversized pieces; palette colours remain the same.
for mesh in bpy.data.meshes:
 if not mesh.uv_layers:continue
 uv=mesh.uv_layers.active
 for f in mesh.polygons:
  u=sum(uv.data[i].uv.x for i in f.loop_indices)/f.loop_total;v=sum(uv.data[i].uv.y for i in f.loop_indices)/f.loop_total
  cx=(max(0,min(9,int(u*10)))+.5)/10;cy=(max(0,min(9,int(v*10)))+.5)/10
  for j,k in enumerate(f.loop_indices):uv.data[k].uv=(cx+.028*math.cos(j*math.tau/f.loop_total),cy+.028*math.sin(j*math.tau/f.loop_total))
 uv.active_render=True;mesh.uv_layers.active=uv
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(path));far['court_triangles']=cat['visible_triangles'];far['visible_triangles']=H.tri_count(sc.objects);far['source_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();far['budget_passed']=far['visible_triangles']<=600000;far['court_source_sha256']=cat['source_sha256'];(T/'far_catalog.json').write_text(json.dumps(far,ensure_ascii=False,indent=2),encoding='utf8')
H.render(sc,sc.camera,T/'previews/塔4与塔4-2_远景合景.png',(1800,1100),48)
