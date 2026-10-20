"""Author a standalone rooftop generator with an attached loose ground cable.
Run Blender --background --python this_file. Source and optimized files are distinct.
"""
import bpy,bmesh,math,random,json,re,sys,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
P=Path(__file__).resolve().parents[2];sys.path.insert(0,str(P/'scripts'))
from workspace_paths import work_path
O=work_path('sessions/2026-10-20_generator_cables/build.json').parent
S=P/'art_source/environments/tower_zones/rooftop/source/generator'
S.mkdir(parents=True,exist_ok=True)
SOURCE=S/'rooftop_generator_v002.blend'
OPT=S/'export/v002/rooftop_generator_optimized_v002.blend';OPT.parent.mkdir(parents=True,exist_ok=True)
PAL=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
R=random.Random(1807)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.unit_settings.system='METRIC'
def coll(n,p):
 c=bpy.data.collections.new(n);p.children.link(c);return c
root=coll('天台发电机_中文资产管理',scene.collection)
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
aid='ENV-ROOFTOP-GENERATOR';slug='generator'
output=coll('发电机_资产包',out);sourcecol=coll('发电机_制作组件',src)
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
# 1.5 x 2.0m skid-mounted diesel set; integral rails and four isolator feet.
for x in [-.62,.62]:
 for y in [-.83,.83]:box((x,y,.065),(.24,.28,.13),(9,1),1,bev=.025)
 box((x,0,.19),(.16,2.0,.17),(0,4),0,bev=.025)
for y in [-.86,.86]:box((0,y,.29),(1.5,.12,.14),(0,4),0,bev=.02)
box((0,0,.78),(1.28,1.73,.94),(3,5),1,bev=.09)
box((0,-.16,1.29),(1.28,1.43,.14),(3,6),1,bev=.06)
# Protective corner cage and lift handles.
for x in [-.70,.70]:
 for y in [-.89,.89]:rod((x,y,.24),(x,y,1.31),.045,(0,4),0,n=8)
 rod((x,-.89,1.31),(x,.89,1.31),.045,(0,4),0,n=8)
for y in [-.68,.47]:
 for x in [-.23,.23]:rod((x,y,1.36),(x,y,1.44),.025,(9,4),0,n=8)
 rod((-.23,y,1.44),(.23,y,1.44),.025,(9,4),0,n=8)
# Fuel filler and exhaust silencer.
rod((.35,-.48,1.34),(.35,-.48,1.39),.10,(9,3),0,n=12)
rod((-.38,-.58,1.35),(-.38,-.58,1.43),.065,(9,3),0,n=10)
box((-.38,-.60,1.43),(.20,.26,.08),(9,4),0,bev=.03)
# Long side radiator slats and a hinged maintenance door.
for side in [-1,1]:
 box((side*.649,-.33,.82),(.025,.92,.57),(9,1),1,bev=.01)
 for y in range(11):box((side*.67,-.73+y*.08,.82),(.035,.032,.53),(9,4),0,bev=.006)
 box((side*.65,.47,.78),(.025,.55,.72),(3,4),1,bev=.025)
 box((side*.68,.58,.83),(.045,.16,.045),(9,2),0,bev=.009)
 for z in [.54,1.02]:box((side*.67,.23,z),(.035,.055,.09),(9,5),0,bev=.008)
# End control panel facing +Y in Blender / -Z in Godot.
box((0,.884,.90),(1.03,.045,.57),(9,2),0,bev=.035)
box((-.23,.917,1.02),(.36,.028,.17),(9,0),1,bev=.012)
for x in [-.33,-.25,-.17]:box((x,.935,1.02),(.045,.012,.07),(3,7),1,bev=.004)
for x in [.14,.34]:
 rod((x,.91,1.03),(x,.95,1.03),.065,(9,6),0,n=12)
 rod((x,.951,1.03),(x,.96,1.03),.043,(9,1),1,n=12)
rod((.34,.91,.78),(.34,.99,.78),.065,(7,5),1,n=10)
for x in [-.32,-.06]:
 rod((x,.91,.76),(x,.97,.76),.085,(9,0),1,n=12)
 for dx in [-.026,.026]:box((x+dx,.975,.76),(.018,.012,.035),(9,5),0,bev=0)
# Warning band, fasteners, and a raised lightning badge.
box((0,-.883,.91),(.47,.025,.34),(7,6),1,bev=.016)
g.add([(-.04,-.901,1.05),(.12,-.901,1.05),(.015,-.901,.92),(.11,-.901,.92),(-.12,-.901,.75),(-.035,-.901,.91),(-.13,-.901,.91)],[(0,1,2,3,4,5,6)],(9,1),1)
for x in [-.53,.53]:
 for z in [.43,1.16]:rod((x,.88,z),(x,.916,z),.026,(9,6),0,n=6)
body=mesh_object('GeneratorBody',g)
g=Geo()
# Attached lead drops from the output gland, then makes a loose irregular ground loop.
points=[(.64,.57,.56),(.82,.61,.44),(.91,.66,.22),(1.04,.74,.042),(1.35,.98,.042),(1.79,1.10,.042),(2.12,.86,.042),(2.23,.39,.042),(2.06,-.10,.042),(1.70,-.30,.042),(1.37,-.12,.042),(1.37,.22,.042),(1.67,.46,.042),(2.08,.36,.042),(2.51,.04,.042),(2.69,-.38,.042)]
def cable_tube(points,radius=.035,cell=(9,1)):
 curve=[]
 for i in range(len(points)-1):
  p0=Vector(points[max(0,i-1)]);p1=Vector(points[i]);p2=Vector(points[i+1]);p3=Vector(points[min(len(points)-1,i+2)])
  for k in range(6):
   t=k/6;v=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t);v.z=max(.042,v.z);curve.append(v)
 curve.append(Vector(points[-1]));verts=[];n=8
 for i,p in enumerate(curve):
  tangent=curve[min(len(curve)-1,i+1)]-curve[max(0,i-1)];q=tangent.to_track_quat('Z','Y')
  for k in range(n):verts.append(p+q@Vector((radius*math.cos(k*math.tau/n),radius*math.sin(k*math.tau/n),0)))
 faces=[tuple(reversed(range(n))),tuple(range((len(curve)-1)*n,len(curve)*n))]
 for i in range(len(curve)-1):
  for k in range(n):faces.append((i*n+k,i*n+(k+1)%n,(i+1)*n+(k+1)%n,(i+1)*n+k))
 g.add(verts,faces,cell,1)
cable_tube(points)
rod(points[0],(.59,.55,.60),.065,(9,2),0,n=10)
end=Vector(points[-1]);end.z=.066;tip=end+Vector((.05,-.20,0));rod(end,tip,.065,(7,5),1,n=10);rod(tip,tip+Vector((.025,-.06,0)),.035,(9,5),0,n=8)
# Three extra installed leads: asymmetric slack routes terminate inside the 0.30m wall.
# Layout origin world X=18; wall occupies X=14.85..15.15. End center X=15.00.
installed_routes=[
 [(-.65,-.55,.55),(-.91,-.70,.30),(-1.02,-.95,.045),(-.92,-1.60,.045),(.20,-2.10,.045),(-.05,-3.25,.045),(-1.10,-3.65,.045),(-1.35,-4.70,.045),(-2.35,-4.75,.045),(-2.72,-4.42,.08),(-3.0,-4.30,.18)],
 [(.34,.98,.76),(.42,1.16,.40),(.20,1.50,.042),(-.80,1.82,.042),(-1.55,1.34,.042),(-2.02,.83,.042),(-2.52,1.02,.07),(-3.0,1.20,.18)],
 [(.30,-.88,.40),(.45,-1.20,.16),(.10,-1.72,.042),(-.90,-2.30,.042),(-1.95,-2.02,.042),(-2.40,-2.64,.06),(-3.0,-2.90,.16)]
]
for route,radius,cell in zip(installed_routes,[.038,.032,.026],[(9,1),(9,2),(9,0)]):
 cable_tube(route,radius,cell)
 # Dark rubber glands at the machine; wall ends are capped inside masonry, no protruding plug.
 p0=Vector(route[0]);direction=(Vector(route[1])-p0).normalized();rod(p0-direction*.04,p0+direction*.05,radius*1.6,(9,2),1,n=8)
cable=mesh_object('GroundCable',g)
names=['GeneratorBody','GroundCable'];counts={n:sum(len(p.vertices)-2 for p in bpy.data.objects[n].data.polygons) for n in names}
scene.name='天台发电机_v002';bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE));sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.save_as_mainfile(filepath=str(OPT))
for ob in list(sourcecol.objects):bpy.data.objects.remove(ob,do_unlink=True)
for name in names:
 ob=bpy.data.objects[name];bm=bmesh.new();bm.from_mesh(ob.data)
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
 bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_area()<1e-10],context='FACES')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
 bpy.context.view_layer.objects.active=ob;ob.select_set(True);mod=ob.modifiers.new('Triangulate','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(OPT));bpy.ops.wm.open_mainfile(filepath=str(OPT))
bpy.ops.object.select_all(action='DESELECT')
for n in names:bpy.data.objects[n].select_set(True)
dest=O/'generator.glb';bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_image_format='NONE',export_yup=True,export_animations=False,export_extras=True)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==sha
a={'asset_id':aid,'name':'天台带电缆发电机','slug':slug,'version':'v002','block_id':'rooftop','floor_range':'100F','design_scope':'中央房屋东侧门南边','scene_design_docs':['docs/v0.1/design/rooftop_first_visit_guidance.md','docs/v0.1/05.1_关卡区块设计.md','docs/v0.1/05.2_关卡版图白盒与生成规范.md'],'source_blend':SOURCE.relative_to(P).as_posix(),'optimized_blend':OPT.relative_to(P).as_posix(),'source_sha256_before':sha,'source_sha256_after':sha,'optimized_sha256':hashlib.sha256(OPT.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'glb':'assets/art/environments/tower_zones/rooftop/components/generator/env_rooftop_generator_visual_top3d.glb','prefab':'assets/art/environments/tower_zones/rooftop/runtime/generator/env_rooftop_generator_root_top3d.tscn','triangles_before':counts,'triangles_after':{n:len(bpy.data.objects[n].data.polygons) for n in names},'reduction_ratio':0,'optimization':{'operations':['remove isolated vertices','remove zero area faces','recalculate normals','explicit triangulation'],'budget':None,'retained_faces':'back and underside needed for independent object views; single bevel segment and 8-sided cable preserve silhouette'},'cable_count':4,'wall_entry_endpoints_blender':[list(p[-1]) for p in installed_routes],'wall_interval_world_x':[14.85,15.15],'body_footprint':[1.5,2.0],'height':1.47,'objects':names,'collection':'发电机_资产包','origin':'generator body bottom center; cable is attached nonblocking visual extension','interaction_status':'planned_locked','runtime_integrated':False}
(O/'build.json').write_text(json.dumps(a,ensure_ascii=False,indent=2),encoding='utf-8');(S/'asset_manifest.json').write_text(json.dumps(a,ensure_ascii=False,indent=2),encoding='utf-8');print('GENERATOR_BUILD_OK',counts)
