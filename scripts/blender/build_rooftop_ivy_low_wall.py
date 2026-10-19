"""Author the rooftop broken wall and derive foliage from the existing rooftop ivy.
Run Blender --background --python this_file. Source and optimized files are distinct.
"""
import bpy,bmesh,math,random,json,re,sys,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
P=Path(__file__).resolve().parents[2];sys.path.insert(0,str(P/'scripts'))
from workspace_paths import work_path
O=work_path('sessions/2026-10-19_rooftop_ivy_revision/build.json').parent
S=P/'art_source/environments/tower_zones/rooftop/source/ivy_broken_low_wall'
S.mkdir(parents=True,exist_ok=True)
SOURCE=S/'rooftop_ivy_broken_low_wall_v002.blend'
OPT=S/'export/v002/rooftop_ivy_broken_low_wall_optimized_v002.blend';OPT.parent.mkdir(parents=True,exist_ok=True)
PAL=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
R=random.Random(1807)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.unit_settings.system='METRIC'
def coll(n,p):
 c=bpy.data.collections.new(n);p.children.link(c);return c
root=coll('天台藤蔓破损矮墙_中文资产管理',scene.collection)
src=coll('01_制作组件_按资产拆分',root);out=coll('02_游戏输出_独立资产包_v002',root)
src.hide_render=True;src.hide_viewport=True
image=bpy.data.images.load(str(PAL));image.filepath=str(PAL)
mats=[]
for i,n in enumerate(['01_精工金属_紫色骨架','02_细腻哑光_青绿大面']):
 m=bpy.data.materials.new(n);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 p.inputs['Metallic'].default_value=[.86,.025][i];p.inputs['Roughness'].default_value=[.29,.72][i]
 p.inputs['Coat Weight'].default_value=[.16,0][i]
 uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
 tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']);m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color']);mats.append(m)

class Geo:
 def __init__(self):self.v=[];self.f=[];self.style=[]
 def add(self,v,f,cell,role=1,transform=None):
  off=len(self.v);self.v.extend([tuple(transform@Vector(x)) if transform else tuple(x) for x in v])
  self.f.extend([tuple(off+i for i in face) for face in f]);self.style.extend([(cell,role)]*len(f))
g=None
def box(c,d,cell=(9,6),role=1,bev=.04,rot=0,transform=None,jitter=0):
 bm=bmesh.new();bmesh.ops.create_cube(bm,size=1)
 for v in bm.verts:v.co=Vector((v.co.x*d[0],v.co.y*d[1],v.co.z*d[2]))
 if bev:bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bev,min(d)*.24),segments=1,affect='EDGES')
 bm.verts.ensure_lookup_table();bm.verts.index_update()
 mat=Matrix.Translation(Vector(c))@Matrix.Rotation(rot,4,'Z')
 if transform:mat=transform@mat
 verts=[mat@(v.co+Vector((R.uniform(-jitter,jitter),R.uniform(-jitter,jitter),R.uniform(-jitter,jitter)))) for v in bm.verts]
 g.add(verts,[tuple(v.index for v in f.verts) for f in bm.faces],cell,role);bm.free()
def rod(a,b,r,cell=(9,4),role=0,n=6):
 a,b=Vector(a),Vector(b);q=(b-a).to_track_quat('Z','Y')
 v=[p+q@Vector((r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),0)) for p in (a,b) for i in range(n)]
 f=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 g.add(v,f,cell,role)
def pillow(c,d,angle,cell):
 # Puffy sack silhouette, compressed corners, pinched tied ends and an equatorial seam.
 rings=[(-.5,.28,.28),(-.42,.79,.73),(-.25,1,1),(.25,1,1),(.42,.79,.73),(.5,.28,.28)]
 v=[];n=10;mat=Matrix.Translation(Vector(c))@Matrix.Rotation(angle,4,'Z')
 for x,w,h in rings:
  for k in range(n):
   a=k*math.tau/n;v.append(mat@Vector((x*d[0],math.cos(a)*d[1]*.5*w,math.sin(a)*d[2]*.5*h)))
 f=[tuple(reversed(range(n))),tuple(range(5*n,6*n))]
 for j in range(5):
  for k in range(n):f.append((j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k))
 g.add(v,f,cell)
 for side in [-1,1]:
  a=mat@Vector((-.43*d[0],side*d[1]*.37,0));b=mat@Vector((.43*d[0],side*d[1]*.37,0));rod(a,b,.012,(5,3),1)

assets=[]
def begin(slug,aid,name,version='v002'):
 global g
 g=Geo();return {'slug':slug,'asset_id':aid,'name':name,'version':version,'collision':[]}
def finish(a):
 lo=Vector(tuple(min(v[i] for v in g.v) for i in range(3)));hi=Vector(tuple(max(v[i] for v in g.v) for i in range(3)))
 shift=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z));g.v=[tuple(Vector(v)+shift) for v in g.v]
 a['origin_shift_blender']=list(shift);a['bounds_blender']=list(hi-lo)
 me=bpy.data.meshes.new(a['slug']);me.from_pydata(g.v,[],g.f);me.update()
 for m in mats:me.materials.append(m)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
 for poly,(cell,role) in zip(me.polygons,g.style):
  poly.material_index=role;n=len(poly.loop_indices);cx=(cell[0]+.5)/10;cy=1-(cell[1]+.5)/10
  for j,li in enumerate(poly.loop_indices):uv.data[li].uv=(cx+.026*math.cos(j*math.tau/n),cy+.026*math.sin(j*math.tau/n))
 sc=coll(a['name']+'_制作组件',src);oc=coll(a['name']+'_资产包',out)
 ob=bpy.data.objects.new(a['name']+'_主体',me);oc.objects.link(ob);ob['asset_id']=a['asset_id'];ob['block_id']='rooftop'
 sob=ob.copy();sob.data=me.copy();sc.objects.link(sob)
 a['collection']=oc.name;a['object']=ob.name;a['source_blend']=str(SOURCE.relative_to(P));a['optimized_blend']=str(OPT.relative_to(P))
 a['glb']='assets/art/environments/tower_zones/rooftop/components/guidance/env_rooftop_'+a['slug']+'_visual_top3d.glb'
 a['prefab']='assets/art/environments/tower_zones/rooftop/runtime/guidance/env_rooftop_'+a['slug']+'_root_top3d.tscn'
 a['block_id']='rooftop';a['floor_range']='100F';a['category']='scene_interactive_content';a['source']=ob.name
 a['triangles_before']=sum(len(p.vertices)-2 for p in me.polygons);assets.append(a)

# One independent component, wall and foliage remain separate output meshes.
aid='ENV-ROOFTOP-IVY-BROKEN-LOW-WALL';slug='ivy_broken_low_wall'
output=coll('藤蔓破损矮墙_资产包',out);sourcecol=coll('藤蔓破损矮墙_制作组件',src)
heights=[1.20,1.75,2.35,2.95,3.25,3.70,4.80,5.05]
def mesh_object(name,geo):
 me=bpy.data.meshes.new(name);me.from_pydata(geo.v,[],geo.f);me.update()
 for m in mats:me.materials.append(m)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
 for p,(cell,role) in zip(me.polygons,geo.style):
  p.material_index=role;n=len(p.loop_indices)
  for k,li in enumerate(p.loop_indices):uv.data[li].uv=((cell[0]+.5)/10+.026*math.cos(k*math.tau/n),1-(cell[1]+.5)/10+.026*math.sin(k*math.tau/n))
 ob=bpy.data.objects.new(name,me);output.objects.link(ob);ob['asset_id']=aid
 copy=ob.copy();copy.data=me.copy();sourcecol.objects.link(copy)
 return ob
g=Geo()
# A continuous fractured slab, rather than a row of tall pillars.
profile=[(-2.3,1.10),(-1.92,1.32),(-1.68,1.86),(-1.40,1.70),(-1.17,2.28),(-.82,2.55),(-.50,2.88),(-.13,3.08),(.22,3.16),(.54,3.66),(.91,3.90),(1.10,4.65),(1.42,4.82),(1.83,5.05),(2.3,5.12)]
outline=[(-2.3,0),(2.3,0)]+list(reversed(profile));n=len(outline)
v=[(x,y,z) for y in [-.15,.15] for x,z in outline]
f=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
g.add(v,f,(9,6))
# Shallow weathered mortar and short cracks do not split the wall silhouette.
for side in [-1,1]:
 for i,h in enumerate(heights):
  x=-2.0125+i*.575
  for z in [.45,.92,1.42,1.94,2.45,2.96,3.48,4.02,4.52]:
   if z<h-.23:box((x,side*.153,z),(.56,.008,.018),(9,4),bev=0)
 for x,z in [(-1.4,1.5),(-.4,2.5),(.8,3.45),(1.65,4.4)]:
  rod((x,side*.16,z),(x+.14,side*.16,z-.30),.012,(9,3),1,n=4)
wall=mesh_object('Wall',g)
# Derive the actual rooftop ivy mesh; retain original palette UV and leaf topology.
ivy_source=P/'art_source/environments/tower_zones/rooftop/source/reference_components/v002/天台区块_参考组件库_v002.blend'
ivy_source_sha=hashlib.sha256(ivy_source.read_bytes()).hexdigest()
with bpy.data.libraries.load(str(ivy_source),link=False) as (library,loaded):
 loaded.objects=['墙面攀爬藤蔓_主体']
original=loaded.objects[0]
parts=[]
def crest(x):
 t=max(0,min(7,(x+2.0125)/.575));i=min(6,int(t));return heights[i]*(1-(t-i))+heights[i+1]*(t-i)
for side,hanging in [(1,False),(-1,False),(1,True)]:
 ob=bpy.data.objects.new('DerivedIvy',original.data.copy());output.objects.link(ob)
 # Connected leaf islands move rigidly, retaining the reference leaf silhouette.
 mesh=ob.data;adj=[[] for v in mesh.vertices]
 for edge in mesh.edges:
  a,b=edge.vertices;adj[a].append(b);adj[b].append(a)
 seen=set()
 for index in range(len(mesh.vertices)):
  if index in seen:continue
  stack=[index];seen.add(index);ids=[]
  while stack:
   k=stack.pop();ids.append(k)
   for neighbor in adj[k]:
    if neighbor not in seen:seen.add(neighbor);stack.append(neighbor)
  center=sum((mesh.vertices[k].co for k in ids),Vector())/len(ids)
  x=center.x*1.02
  if hanging:
   # Long tendrils next to the exit, shorter towards the rubble; overlap at roof lip.
   bottom=-1.0-3.3*((x+2.2)/4.4)+.38*math.sin(x*3.1)
   z=.15+(center.z/3.802195-1)*(-bottom+.15)
  else:z=.15+center.z/3.802195*(crest(x)-.20)
  for k in ids:
   v=mesh.vertices[k];delta=v.co-center
   # Thin depth follows the adjacent 0.30m enclosure, with leaves outside either face.
   v.co=Vector((x+delta.x,side*((.40+min(1,max(0,-z/.5))*.97 if hanging else .40)+(center.y+delta.y)*.52),z+delta.z))
 for i,m in enumerate(list(mesh.materials)):
  mesh.materials[i]=mats[0] if m.name.startswith('01_') else mats[1]
 parts.append(ob)
bpy.data.objects.remove(original,do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();ivy=bpy.context.object;ivy.name='Ivy';ivy['asset_id']=aid
copy=ivy.copy();copy.data=ivy.data.copy();sourcecol.objects.link(copy)
assert hashlib.sha256(ivy_source.read_bytes()).hexdigest()==ivy_source_sha
fol=bpy.data.objects.new('Foliage',None);output.objects.link(fol);ivy.parent=fol
# The rooftop layout parent turns the authored instance by 180 degrees.
# Bake the matching orientation into this component; preserve the stable instance transform.
for collection in [output,sourcecol]:
 for ob in collection.objects:
  if ob.type=='MESH':
   for v in ob.data.vertices:v.co.x=-v.co.x;v.co.y=-v.co.y
heights=list(reversed(heights))
names=['Wall','Ivy'];counts={n:sum(len(p.vertices)-2 for p in bpy.data.objects[n].data.polygons) for n in names}
for unused in list(bpy.data.materials):
 if unused not in mats:bpy.data.materials.remove(unused,do_unlink=True)
scene.name='天台藤蔓破损矮墙_v002';bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE));sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.save_as_mainfile(filepath=str(OPT))
for ob in list(sourcecol.objects):bpy.data.objects.remove(ob,do_unlink=True)
for name in names:
 ob=bpy.data.objects[name];bm=bmesh.new();bm.from_mesh(ob.data)
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
 bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_area()<1e-10],context='FACES')
 bm.to_mesh(ob.data);bm.free()
 bpy.context.view_layer.objects.active=ob;ob.select_set(True);mod=ob.modifiers.new('Triangulate','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(OPT));bpy.ops.wm.open_mainfile(filepath=str(OPT))
bpy.ops.object.select_all(action='DESELECT')
for n in names+['Foliage']:bpy.data.objects[n].select_set(True)
dest=O/'ivy_broken_low_wall.glb';bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_image_format='NONE',export_yup=True,export_animations=False,export_extras=True)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==sha
a={'asset_id':aid,'name':'藤蔓覆盖破损矮墙','slug':slug,'version':'v002','block_id':'rooftop','floor_range':'100F','design_scope':'西侧井口出口平台南端沿井口东边','scene_design_docs':['docs/v0.1/design/rooftop_first_visit_guidance.md','docs/v0.1/05.1_关卡区块设计.md','docs/v0.1/05.2_关卡版图白盒与生成规范.md'],'source_blend':str(SOURCE.relative_to(P)),'optimized_blend':str(OPT.relative_to(P)),'source_sha256_before':sha,'source_sha256_after':sha,'optimized_sha256':hashlib.sha256(OPT.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'glb':'assets/art/environments/tower_zones/rooftop/components/guidance/env_rooftop_ivy_broken_low_wall_visual_top3d.glb','prefab':'assets/art/environments/tower_zones/rooftop/runtime/guidance/env_rooftop_ivy_broken_low_wall_root_top3d.tscn','triangles_before':counts,'triangles_after':{n:len(bpy.data.objects[n].data.polygons) for n in names},'optimization':{'operations':['remove isolated vertices','remove zero area faces','explicit triangulation'],'budget':None,'reduction':'0; preserve masonry break silhouette, mortar, leaf backs and vine segments'},'collision_heights':heights,'wall_thickness':.30,'ivy_parent_asset':'ENV-ROOFTOP-REF-IVY','ivy_source_sha256':ivy_source_sha,'hanging_envelope_godot_y':[-4.8,5.4],'collection':output.name if False else '藤蔓破损矮墙_资产包','objects':['Wall','Foliage','Ivy'],'origin':'bottom center; Blender Z-up to Godot Y-up','runtime_integrated':False}
(O/'build.json').write_text(json.dumps(a,ensure_ascii=False,indent=2),encoding='utf-8')
(S/'asset_manifest.json').write_text(json.dumps(a,ensure_ascii=False,indent=2),encoding='utf-8')
print('IVY_WALL_BUILD_OK',counts)

