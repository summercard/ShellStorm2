"""Author eight rooftop scene-interaction assets; never regenerates the room layout.
Run Blender --background --python this_file. Source and optimized files are distinct.
"""
import bpy,bmesh,math,random,json,re,sys,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
P=Path(__file__).resolve().parents[2];sys.path.insert(0,str(P/'scripts'))
from workspace_paths import work_path
O=work_path('sessions/2026-10-18_rooftop_formal/build.json').parent
S=P/'art_source/environments/tower_zones/rooftop/source/interactive_clutter'
S.mkdir(parents=True,exist_ok=True)
SOURCE=S/'rooftop_interactive_clutter_v001.blend'
OPT=S/'export/v001/rooftop_interactive_clutter_optimized_v001.blend';OPT.parent.mkdir(parents=True,exist_ok=True)
PAL=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
R=random.Random(1807)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.unit_settings.system='METRIC'
def coll(n,p):
 c=bpy.data.collections.new(n);p.children.link(c);return c
root=coll('天台交互杂物_中文资产管理',scene.collection)
src=coll('01_制作组件_按资产拆分',root);out=coll('02_游戏输出_独立资产包_v001',root)
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
def begin(slug,aid,name,version='v001'):
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

# Preserve the authored five-piece and three-piece collision geometry exactly.
for slug in ['rubble_pile_a','rubble_pile_b','rubble_pile_c','timber_pile']:
 a=begin(slug,'ENV-ROOFTOP-'+slug.upper().replace('_','-'),'水泥碎块'+slug[-1].upper() if slug.startswith('rubble') else '旧木料堆','v002')
 text=(P/('assets/art/environments/tower_zones/rooftop/runtime/guidance/env_rooftop_'+slug+'_root_top3d.tscn')).read_text(encoding='utf-8')
 sizes=re.findall(r'\[sub_resource type="BoxShape3D" id="shape\d+"\]\nsize = Vector3\(([^)]+)\)',text)
 transforms=re.findall(r'\[node name="Piece\d+"[^\n]*\]\ntransform = Transform3D\(([^)]+)\)',text)
 C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
 for j,(sz,tr) in enumerate(zip(sizes,transforms)):
  sz=list(map(float,sz.split(',')));t=list(map(float,tr.split(',')))
  G=Matrix(((t[0],t[3],t[6],t[9]),(t[1],t[4],t[7],t[10]),(t[2],t[5],t[8],t[11]),(0,0,0,1)));T=C@G@C.inverted()
  d=(sz[0],sz[2],sz[1]);a['collision'].append({'size':sz,'transform':t})
  if slug.startswith('rubble'):
   box((0,0,0),d,(9,5+j%3),bev=.16,transform=T,jitter=.045)
   # Fragmented facing and exposed rusty reinforcement, kept within original block envelope.
   for k in range(3):
    x=R.uniform(-.3,.3)*d[0];y=R.uniform(-.3,.3)*d[1]
    box((x,y,d[2]*.5+.012),(.18,.10,.025),(9,3+j%3),bev=.008,transform=T)
   aa=T@Vector((-.35*d[0],-.22*d[1],d[2]*.5));bb=T@Vector((.22*d[0],-.17*d[1],d[2]*.5+.06));rod(aa,bb,.027,(4,2))
  else:
   box((0,0,0),d,(6+j%3,2),bev=.045,transform=T)
   for k in range(4):
    box((R.uniform(-.1,.1),(-.32+k*.21)*d[1],d[2]*.5+.006),(d[0]*R.uniform(.45,.85),.015,.008),(3+j%2,2),bev=0,transform=T)
 finish(a)

a=begin('sandbag_barrier','ENV-ROOFTOP-SANDBAG-BARRIER','防洪沙袋堆','v002')
for layer in range(2):
 for j in range(4 if layer==0 else 3):
  x=(j-(1.5 if layer==0 else 1))*1.42;z=.29+layer*.49;y=R.uniform(-.14,.14);ang=R.uniform(-.13,.13)
  pillow((x,y,z),(1.65,1.42,.58),ang,(7+(j+layer)%2,3))
  co,si=math.cos(ang),math.sin(ang)
  a['collision'].append({'size':[1.56,.55,1.30],'transform':[co,0,-si,0,1,0,si,0,co,x,z,-y]})
finish(a)

a=begin('broken_crate_a','ENV-ROOFTOP-BROKEN-CRATE-A','大型旧木箱','v002')
for z in [.16,2.84]:box((0,0,z),(4,3,.28),(5,2),bev=.05)
for j in range(7):
 x=-1.74+j*.58
 box((x,0,2.99),(.55,2.82,.12),(6+j%3,2),bev=.025)
 for side in [-1,1]:box((x,side*1.43,1.5),(.55,.15,2.5),(6+j%3,2),bev=.025)
for side in [-1,1]:
 for j in range(5):box((side*1.91,-1.12+j*.56,1.5),(.18,.53,2.5),(6+j%3,2),bev=.025)
 for x in [-1.72,1.72]:
  box((x,side*1.52,1.5),(.22,.16,2.84),(4,2),bev=.035)
  for z in [.3,2.7]:box((x,side*1.615,z),(.13,.035,.13),(9,5),0,bev=.02)
 # Diagonal bracing boards on both sides, independently readable silhouette.
 rod((-1.7,side*1.58,.4),(1.7,side*1.58,2.6),.13,(5,2),1,n=4)
box((.4,-1.54,1.7),(.65,.025,.38),(9,8),bev=.01)
for x in [.2,.38,.56]:box((x,-1.559,1.7),(.04,.015,.21),(9,3),bev=0)
a['collision']=[{'size':[4,3.05,3.2],'position':[0,1.525,0]}];finish(a)

a=begin('covered_cargo','ENV-ROOFTOP-COVERED-CARGO','篷布大货包')
for x in [-1.6,0,1.6]:box((x,0,.13),(.32,3,.26),(4,2),bev=.04)
for j in range(7):box((-1.98+j*.66,0,.33),(.60,3,.15),(6,2),bev=.025)
box((0,0,1.55),(4.4,2.9,2.35),(4,5),bev=.22)
for j in range(10):
 x=-2+j*.44
 # Broad cloth folds on the front and back catch light at the game camera distance.
 for side in [-1,1]:box((x,side*(1.43+R.uniform(0,.07)),1.6),(.12,.08,R.uniform(1.8,2.1)),(3+j%3,5),bev=.025)
for x in [-1.35,1.3]:
 box((x,0,2.745),(.12,2.6,.035),(8,3),bev=.01)
 for side in [-1,1]:box((x,side*1.49,1.56),(.12,.04,2.22),(8,3),bev=.01)
 for side in [-1,1]:box((x,side*1.52,1.3),(.23,.08,.27),(9,5),0,bev=.025)
a['collision']=[{'size':[4.4,2.8,3.1],'position':[0,1.4,0]}];finish(a)

a=begin('grass_patch','ENV-ROOFTOP-GRASS-PATCH','地缝风摆杂草')
for tuft in range(12):
 cx=R.uniform(-1,.95);cy=R.uniform(-.65,.65)
 for k in range(R.randint(5,8)):
  ang=R.random()*math.tau;h=R.uniform(.25,.72);w=R.uniform(.035,.065);lean=R.uniform(.10,.33)
  side=Vector((math.cos(ang)*w,math.sin(ang)*w,0));base=Vector((cx,cy,0));mid=base+Vector((-math.sin(ang)*lean*.4,math.cos(ang)*lean*.4,h*.52));tip=base+Vector((-math.sin(ang)*lean,math.cos(ang)*lean,h))
  vv=[base-side,base+side,mid+side*.55,mid-side*.55,tip]
  # Closed 3mm blades avoid glTF removal of coplanar opposite faces.
  normal=(vv[1]-vv[0]).cross(vv[3]-vv[0]).normalized()*.003
  vv += [p-normal for p in vv[:]]
  faces=[(0,1,2),(0,2,3),(3,2,4),(7,6,5),(8,7,5),(9,7,8)]
  for x,y in [(0,1),(1,2),(2,4),(4,3),(3,0)]:faces.extend([(x,y,y+5),(x,y+5,x+5)])
  g.add(vv,faces,(3+k%4,4))
finish(a)

for a in assets:
 ap=S/'component_packages'/a['slug'];ap.mkdir(parents=True,exist_ok=True)
 a['manifest']=str((ap/'asset_manifest.json').relative_to(P));a['scene_design_docs']=['docs/v0.1/design/rooftop_first_visit_guidance.md'];a['runtime_integrated']=False
 (ap/'asset_manifest.json').write_text(json.dumps(a,ensure_ascii=False,indent=2),encoding='utf-8')
(S/'catalog.json').write_text(json.dumps(assets,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE));sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()

# Real cleanup on a separately saved optimization file; preserve UV seams and double-sided foliage.
bpy.ops.wm.save_as_mainfile(filepath=str(OPT))
for c in list(src.children):
 for ob in list(c.objects):bpy.data.objects.remove(ob,do_unlink=True)
 bpy.data.collections.remove(c)
for a in assets:
 ob=bpy.data.objects[a['object']];bm=bmesh.new();bm.from_mesh(ob.data)
 isolated=[v for v in bm.verts if not v.link_faces];bmesh.ops.delete(bm,geom=isolated,context='VERTS')
 zero=[f for f in bm.faces if f.calc_area()<1e-10];bmesh.ops.delete(bm,geom=zero,context='FACES')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)) if a['slug']!='grass_patch' else None
 bm.to_mesh(ob.data);bm.free();ob.data.update()
 a['optimization']={'isolated_vertices_removed':len(isolated),'zero_area_faces_removed':len(zero),'merge_distance':0,'reason':'Preserve UV islands, silhouette, seams, bottom/back faces and explicit double-sided grass; no arbitrary decimation','budget':None,'budget_source':'No project per-component triangle budget supplied'}
 # Triangulation is explicit in persistent optimized mesh.
 bpy.context.view_layer.objects.active=ob;ob.select_set(True)
 mod=ob.modifiers.new('ExportTriangulation','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)
 a['triangles_after']=len(ob.data.polygons);a['reduction_ratio']=(a['triangles_before']-a['triangles_after'])/a['triangles_before']
bpy.ops.wm.save_as_mainfile(filepath=str(OPT));bpy.ops.wm.open_mainfile(filepath=str(OPT))
for a in assets:
 bpy.ops.object.select_all(action='DESELECT');ob=bpy.data.objects[a['object']];ob.select_set(True);bpy.context.view_layer.objects.active=ob
 dest=O/(a['slug']+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_image_format='NONE',export_yup=True,export_animations=False,export_cameras=False,export_lights=False,export_extras=True)
 a['source_sha256_before']=sha;a['source_sha256_after']=hashlib.sha256(SOURCE.read_bytes()).hexdigest();assert a['source_sha256_after']==sha
 a['optimized_sha256']=hashlib.sha256(OPT.read_bytes()).hexdigest();a['glb_sha256']=hashlib.sha256(dest.read_bytes()).hexdigest()
 a['staged_glb']=str(dest)
 (P/a['manifest']).write_text(json.dumps(a,ensure_ascii=False,indent=2),encoding='utf-8')
(S/'export/v001/import_manifest.json').write_text(json.dumps(assets,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'build.json').write_text(json.dumps(assets,ensure_ascii=False,indent=2),encoding='utf-8')
print('ROOFTOP_AUTHORING_OK',[(a['slug'],a['triangles_after']) for a in assets])
