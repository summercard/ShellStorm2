"""Actual low geometry tower + courtyard, preserving independent spatial packages."""
import bpy,bmesh,sys,json,math,hashlib,random,shutil
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent));import tower04_court_common as H
R=H.R;OUT=R/'assets/art/environments/open_world/source/tower_04/v010'
COURT=R/'assets/art/environments/open_world/source/tower_04_2/v002';BLEND=OUT/'塔4与塔4-2_远景优化合景_v010.blend'
if BLEND.exists():
 prior=json.loads((OUT/'far_catalog.json').read_text(encoding='utf8'));assert hashlib.sha256(BLEND.read_bytes()).hexdigest()==prior['source_sha256']
 backup=R.parent/'_scratch/tower04_v010/far_first_draft.blend';assert not backup.exists();shutil.copy2(BLEND,backup)
meta=json.loads((OUT/'catalog.json').read_text(encoding='utf8'));court=json.loads((COURT/'far_catalog.json').read_text(encoding='utf8'))
bpy.ops.wm.open_mainfile(filepath=str(R/meta['source_blend']));sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;H.setup_materials()
keep={n for p in meta['packages'] for n in p['objects']}
for s in list(bpy.data.scenes):
 if s!=sc:bpy.data.scenes.remove(s)
for o in list(bpy.data.objects):
 if o.name not in keep:bpy.data.objects.remove(o,do_unlink=True)
for c in list(bpy.data.collections):
 if not c.objects and not c.children:bpy.data.collections.remove(c)
root=H.coll('塔4_远景优化_独立组件',sc.collection)
records=[]
def cell(o):
 uv=o.data.uv_layers.active
 if not uv or not o.data.polygons:return H.TILE
 p=max(o.data.polygons,key=lambda p:p.area);u=sum(uv.data[i].uv.x for i in p.loop_indices)/p.loop_total;v=sum(uv.data[i].uv.y for i in p.loop_indices)/p.loop_total
 return (min(9,int(u*10)),min(9,int((1-v)*10)))
def lobe(p,center,size,color):
 x,y,z=center;sx,sy,sz=size;n=7
 verts=[(x+sx*math.sin(j*math.pi/4)*math.cos(i*math.tau/n),y+sy*math.sin(j*math.pi/4)*math.sin(i*math.tau/n),z+sz*math.cos(j*math.pi/4)) for j in range(1,4) for i in range(n)]
 verts.extend([(x,y,z+sz),(x,y,z-sz)]);f=[]
 for j in range(2):
  for i in range(n):f.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
 for i in range(n):f.extend([(21,i,(i+1)%n),(22,14+(i+1)%n,14+i)])
 p.poly(verts,f,color,1)
before=H.tri_count([bpy.data.objects[n] for n in keep])
for index,item in enumerate(meta['packages']):
 for name in item['objects']:
  o=bpy.data.objects.get(name)
  if not o or o.type!='MESH':continue
  p=None;d=item['component_definition'];mn=Vector(item['bounds_min']);mx=Vector(item['bounds_max']);center=(mn+mx)*.5;dims=mx-mn
  if any(s in d for s in ('growth','overgrown','planting','garden','vine')):
   p=H.Part(item['slug'],item['display_name'],'garden')
   mesh=o.data;faces=mesh.polygons;uv=mesh.uv_layers.active;i=0;leafid=0
   while i<len(faces):
    f=faces[i];fan=len(f.vertices)==3 and i+9<len(faces) and all(len(faces[i+j].vertices)==3 and faces[i+j].vertices[-1]==f.vertices[-1] for j in range(10))
    if fan:
     if leafid%5==0:
      ids=[faces[i+j].vertices[0] for j in (0,2,5,7)]+[f.vertices[-1]]
      vv=[o.matrix_world@mesh.vertices[k].co for k in ids];mid=vv[4];vv=[mid+(v-mid)*1.65 for v in vv]
      q=uv.data[f.loop_start].uv;c=(min(9,int(q.x*10)),min(9,int((1-q.y)*10)))
      p.poly(vv,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],c,1)
     leafid+=1;i+=10
    else:i+=1
   if not p.f:p=None
  elif d=='roof_paver_3x1p5':
   p=H.Part(item['slug'],item['display_name'],'floor');p.box(tuple(center),tuple(dims),cell(o),1)
  if p:
   old=o.data;o.data,origin,dim=H.mesh_of(p);o.location=origin;o.rotation_euler=(0,0,0);o.scale=(1,1,1)
  elif len(o.data.polygons)>240:
   # Geometry-preserving reduction for structural silhouettes; reset each face's palette island.
   bpy.context.view_layer.objects.active=o;o.select_set(True)
   mod=o.modifiers.new('远景轮廓简化','DECIMATE');mod.ratio=max(.08,min(.7,180/len(o.data.polygons)));mod.use_collapse_triangulate=True
   bpy.ops.object.modifier_apply(modifier=mod.name);o.select_set(False)
   if o.data.uv_layers:
    uv=o.data.uv_layers.active;colors=[];mi=[]
    for f in o.data.polygons:
     u=sum(uv.data[i].uv.x for i in f.loop_indices)/f.loop_total;v=sum(uv.data[i].uv.y for i in f.loop_indices)/f.loop_total
     colors.append((max(0,min(9,int(u*10))),max(0,min(9,int((1-v)*10)))));mi.append(f.material_index)
    slots=list(o.data.materials)
    for uv in list(o.data.uv_layers):o.data.uv_layers.remove(uv)
    o.data.materials.clear();H.uv_mesh(o.data,colors,mi,slots)
  o['lod']='far';o['source_package']=item['package_id'];bpy.context.view_layer.update()
  # Split legacy wide pieces into true spatial cells, not a single large mesh.
  world=[o.matrix_world@Vector(v) for v in o.bound_box];lo=[min(v[j] for v in world) for j in range(3)];hi=[max(v[j] for v in world) for j in range(3)]
  outputs=[o]
  if max(hi[0]-lo[0],hi[1]-lo[1])>10.02:
   outputs=[]
   for ix in range(math.floor(lo[0]/8),math.ceil(hi[0]/8)):
    for iy in range(math.floor(lo[1]/8),math.ceil(hi[1]/8)):
     bm=bmesh.new();bm.from_mesh(o.data);bm.transform(o.matrix_world)
     for point,normal in [((ix*8,0,0),(1,0,0)),(((ix+1)*8,0,0),(-1,0,0)),((0,iy*8,0),(0,1,0)),((0,(iy+1)*8,0),(0,-1,0))]:
      bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.00001,plane_co=point,plane_no=normal,clear_inner=True)
     if bm.faces:
      mesh=bpy.data.meshes.new(o.name+f'_{ix}_{iy}');bm.to_mesh(mesh)
      for mat in o.data.materials:mesh.materials.append(mat)
      no=bpy.data.objects.new(mesh.name,mesh);root.objects.link(no);no['source_package']=item['package_id'];no['lod']='far';outputs.append(no)
     bm.free()
   bpy.data.objects.remove(o,do_unlink=True)
  for out in outputs:records.append(dict(object=out.name,source_package=item['package_id'],triangles=H.tri_count([out])))
 if index%300==0:print('FAR_TOWER_PROGRESS',index,flush=True)

# Append only the visible courtyard layout, not its high-resolution definitions or lights.
with bpy.data.libraries.load(str(R/court['source_blend']),link=False) as (a,b):b.collections=['02_游戏输出_分区实例']
court_collection=b.collections[0];court_collection.name='塔4-2_远景庭院_分区';sc.collection.children.link(court_collection)
for o in court_collection.all_objects:
 if o.type=='MESH':
  for i,m in enumerate(o.data.materials):
   base=m.name.split('.')[0]
   if base in H.NAMES:o.data.materials[i]=bpy.data.materials[base]
for mesh in list(bpy.data.meshes):
 if mesh.users==0:bpy.data.meshes.remove(mesh)
for mat in list(bpy.data.materials):
 if mat.users==0 and mat.name not in H.NAMES:bpy.data.materials.remove(mat)
display=H.coll('90_远景验收',sc.collection)
world=bpy.data.worlds.new('远景黄昏天空');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.45,.55,.72,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45;sc.world=world
ld=bpy.data.lights.new('黄昏暖阳','SUN');ld.energy=2.7;ld.color=(1,.74,.43);ld.angle=.12;sun=bpy.data.objects.new(ld.name,ld);display.objects.link(sun);sun.rotation_euler=(.62,-.6,-.72)
cam=H.camera(sc,'CAM_远景合景',(160,-215,150),(-3,-15,12),204,display);sc.camera=cam
sc['asset_id']='ENV-OPENWORLD-TOWER04-FAR';sc['version']='v010';sc['lod']='far';sc['contains_hidden_high_meshes']=False
bpy.context.view_layer.update();tris=H.tri_count(sc.objects)
report=dict(asset_id='ENV-OPENWORLD-TOWER04-FAR',version='v010',source_blend=BLEND.relative_to(R).as_posix(),parent=meta['source_blend'],court_source=court['source_blend'],tower_before_triangles=before,tower_after_triangles=sum(p['triangles'] for p in records),court_triangles=court['visible_triangles'],visible_triangles=tris,geometry_budget=600000,budget_passed=tris<=600000,packages=records,hidden_high_meshes=False,material_count=len(bpy.data.materials),runtime_verified=False)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(BLEND));report['source_sha256']=hashlib.sha256(BLEND.read_bytes()).hexdigest();(OUT/'far_catalog.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('FAR_SAVED',tris,flush=True);H.render(sc,cam,OUT/'previews/塔4与塔4-2_远景合景.png',(1800,1100),48)
