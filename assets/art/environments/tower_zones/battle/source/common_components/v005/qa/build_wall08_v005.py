"""Wall08 reference-driven art refinement. Blender 4.5 --background --factory-startup --python this_file.
Only the two wall packages and their editable sources change. Runtime files are never written.
"""
import bpy, bmesh, math, json, hashlib, random, shutil
from pathlib import Path
from mathutils import Vector, Matrix

PROJECT = Path('I:/工作项目/shellstrom2/ShellStorm2')
BASE = PROJECT / 'assets/art/environments/tower_zones/battle/source/common_components'
SOURCE = BASE / 'v004/战局区块_通用组件库_v004.blend'
DEST = BASE / 'v005'
OUT = Path('I:/工作项目/shellstrom2/outputs/wall08_v005')
PALETTE = PROJECT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
SLUGS = ['wall_standard_5m', 'wall_door_5m']
ROLES = ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
BLEND = DEST / '战局区块_通用组件库_v005.blend'
TARGET_FILE = OUT / '08_两墙独立审阅_v005.blend'
RENDER = DEST / 'renders'
for p in [DEST/'qa',OUT,RENDER]: p.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
bpy.context.view_layer.update()
master = bpy.context.scene
mats = [bpy.data.materials[n] for n in ROLES]
roots = {s:bpy.data.objects['ROOT_'+s+'_通用组件'] for s in SLUGS}
packages = {s:bpy.data.collections[s+'_通用包'] for s in SLUGS}
sources = {s:bpy.data.collections[s+'_制作源'] for s in SLUGS}
modified_names = set(o.name for s in SLUGS for c in [packages[s],sources[s]] for o in c.all_objects if o != roots[s])

def digest(v): return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def q(v):
 if isinstance(v,float): return round(v,6)
 if isinstance(v,(str,int,bool)) or v is None: return v
 try: return [q(x) for x in v]
 except TypeError: return str(v)
def rna_props(item):
 result={}
 for p in item.bl_rna.properties:
  if p.identifier=='rna_type' or p.type=='COLLECTION': continue
  try:
   value=getattr(item,p.identifier)
   result[p.identifier]=value.name if p.type=='POINTER' and value else q(value)
  except (AttributeError,TypeError): pass
 return result

def signature(o):
 d={'name':o.name,'type':o.type,'parent':o.parent.name if o.parent else None,
    'matrix_world':q(o.matrix_world),'matrix_basis':q(o.matrix_basis),'dimensions':q(o.dimensions),
    'collections':sorted(c.name for c in o.users_collection),'hide_render':o.hide_render,'hide_viewport':o.hide_viewport,
    'modifiers':[rna_props(m) for m in o.modifiers],'constraints':[rna_props(m) for m in o.constraints]}
 if o.type=='MESH':
  me=o.data
  d['mesh']=digest({'v':[q(v.co) for v in me.vertices],'e':[list(e.vertices) for e in me.edges],
   'p':[(list(p.vertices),p.material_index,p.use_smooth) for p in me.polygons],
   'uv':[(uv.name,uv.active_render,[q(l.uv) for l in uv.data]) for uv in me.uv_layers]})
  d['materials']=[m.name if m else None for m in me.materials]
 if o.type in ['CAMERA','LIGHT','FONT']: d['data']=rna_props(o.data)
 a=o.animation_data
 d['animation']=None if not a else {'action':a.action.name if a.action else None,
  'curves':[(f.data_path,f.array_index,[(q(k.co),k.interpolation,q(k.handle_left),q(k.handle_right)) for k in f.keyframe_points]) for f in a.action.fcurves] if a.action else [],
  'drivers':[(f.data_path,f.array_index,f.driver.expression) for f in a.drivers],
  'nla':[(t.name,[(s.name,s.action.name if s.action else None,s.frame_start,s.frame_end) for s in t.strips]) for t in a.nla_tracks]}
 return {'sha256':digest(d),'details':d}
locked_names=sorted(o.name for o in bpy.data.objects if o.name not in modified_names)
locked_before={n:signature(bpy.data.objects[n]) for n in locked_names}
material_before={m.name:digest({'nodes':[(n.name,n.type,[(i.name,q(i.default_value)) for i in n.inputs if hasattr(i,'default_value')]) for n in m.node_tree.nodes],'links':[(l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in m.node_tree.links]}) for m in mats}
source_sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
(DEST/'qa/scope_lock_before.json').write_text(json.dumps(locked_before,ensure_ascii=False,indent=2),encoding='utf-8')

# All new geometry uses only the preexisting shared materials; not a single shared shader is changed.
# Palette cells use 1-based top-down rows/columns. Cold grey is column 10.
G0=(10,1); G1=(10,2); G2=(10,3); G3=(10,4); G4=(10,5); G5=(10,6); G6=(10,7); G7=(10,8)
AMBER=(8,4); CYAN=(8,6)

def palette_uv(me,cell):
 for uv in list(me.uv_layers): me.uv_layers.remove(uv)
 uv=me.uv_layers.new(name='PaletteUV')
 u=(cell[0]-.5)/10; v=1-(cell[1]-.5)/10
 for face in me.polygons:
  n=len(face.loop_indices)
  for j,li in enumerate(face.loop_indices):
   a=2*math.pi*j/n
   uv.data[li].uv=(u+.028*math.cos(a),v+.028*math.sin(a))
 me.uv_layers.active=uv; uv.active_render=True

def make_mesh(name,verts,faces,role,cell,coll,root=None,bevel=0):
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
 if bevel:
  bm=bmesh.new(); bm.from_mesh(me)
  bmesh.ops.bevel(bm,geom=list(bm.edges),offset=bevel,segments=1,affect='EDGES')
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(me); bm.free(); me.update()
 me.materials.append(mats[role]); palette_uv(me,cell)
 o=bpy.data.objects.new(name,me); coll.objects.link(o)
 if root: o.parent=root; o.matrix_parent_inverse=Matrix.Identity(4)
 return o

current=None; editable=None

def mesh(name,verts,faces,role=1,cell=G2,bevel=0):
 return make_mesh(current+'_'+name,verts,faces,role,cell,editable,roots[current],bevel)

def box(name,x,y,z,w,d,h,role=1,cell=G2,bevel=.008):
 pts=[(x+sx*w/2,y+sy*d/2,z+sz*h/2) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 return mesh(name,pts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],role,cell,min(bevel,min(w,d,h)*.24) if bevel else 0)

def plate(name,x0,x1,z0,z1,y=.181,depth=.046,cut=.045,role=1,cell=G2):
 c=min(cut,(x1-x0)/4,(z1-z0)/4)
 outline=[(x0+c,z0),(x1-c,z0),(x1,z0+c),(x1,z1-c),(x1-c,z1),(x0+c,z1),(x0,z1-c),(x0,z0+c)]
 verts=[(x,yy,z) for yy in [y-depth/2,y+depth/2] for x,z in outline]
 faces=[tuple(range(7,-1,-1)),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
 return mesh(name,verts,faces,role,cell,.005)

def cylinder(name,a,b,r,role=0,cell=G2,n=10):
 a,b=Vector(a),Vector(b); axis=(b-a).normalized(); v=axis.cross(Vector((0,1,0)))
 if v.length<.1:v=axis.cross(Vector((1,0,0)))
 v.normalize(); w=axis.cross(v)
 pts=[tuple(c+r*(math.cos(i*2*math.pi/n)*v+math.sin(i*2*math.pi/n)*w)) for c in [a,b] for i in range(n)]
 return mesh(name,pts,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],role,cell)

def bolt(x,z,y=.224,scale=1):
 cylinder('沉头紧固件',(x,y-.01,z),(x,y+.012,z),.027*scale,0,G5,8)
 box('螺钉一字槽',x,y+.013,z,.026*scale,.002,.004*scale,1,G0,0)

def label(text,x,z,size=.16,y=.212,cell=G5):
 cu=bpy.data.curves.new(current+'_标识_'+text,'FONT'); cu.body=text; cu.align_x='CENTER'; cu.size=size; cu.space_character=1.15; cu.extrude=0; cu.resolution_u=3
 ob=bpy.data.objects.new(current+'_标识_'+text,cu); editable.objects.link(ob)
 ob.location=(x,y,z); ob.rotation_euler=(math.pi/2,0,math.pi)
 bpy.context.view_layer.update()
 me=bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
 transform=Matrix.Translation(Vector((x,y,z))) @ Matrix.Rotation(math.pi,4,'Z') @ Matrix.Rotation(math.pi/2,4,'X')
 me.transform(transform); bpy.data.objects.remove(ob,do_unlink=True); bpy.data.curves.remove(cu)
 me.materials.clear(); me.materials.append(mats[1]); palette_uv(me,cell)
 o=bpy.data.objects.new(current+'_标识_'+text,me); editable.objects.link(o); o.parent=roots[current]
 return o

def flat(name,pts,y,cell=G1):
 return mesh(name,[(x,y,z) for x,z in pts],[tuple(range(len(pts)))],1,cell)

def warning(x,z,w=.4):
 flat('安全警示三角',[(x-w/2,z),(x+w/2,z),(x,z+w*.86)],.234,AMBER)
 flat('警示三角内底',[(x-w*.31,z+w*.12),(x+w*.31,z+w*.12),(x,z+w*.67)],.235,G1)
 box('警示感叹线',x,.237,z+w*.40,w*.06,.003,w*.21,1,AMBER,0)
 box('警示感叹点',x,.237,z+w*.20,w*.06,.003,w*.055,1,AMBER,0)

# Render-only scene uses collection instances: master placements and all locked items are unchanged.
def review_scene(name,offsets):
 sc=bpy.data.scenes.new(name)
 sc.render.engine='CYCLES'; sc.cycles.samples=32; sc.cycles.use_denoising=True
 sc.render.resolution_x=1600; sc.render.resolution_y=1400; sc.render.resolution_percentage=100
 sc.render.image_settings.file_format='PNG'; sc.render.film_transparent=False
 sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.view_settings.exposure=.8
 world=bpy.data.worlds.new(name+'_环境'); world.use_nodes=True
 world.node_tree.nodes.get('Background').inputs[0].default_value=(.10,.14,.20,1)
 world.node_tree.nodes.get('Background').inputs[1].default_value=.55; sc.world=world
 for s,x in offsets.items():
  o=bpy.data.objects.new(name+'_'+s+'_仅展示实例',None); sc.collection.objects.link(o)
  o.instance_type='COLLECTION'; o.instance_collection=packages[s]
  o.location=Vector((x,0,0))-roots[s].matrix_world.translation
 def light(n,loc,power,size,color):
  data=bpy.data.lights.new(name+n,'AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=color
  ob=bpy.data.objects.new(name+n,data); sc.collection.objects.link(ob); ob.location=loc; ob.rotation_euler=(Vector((0,0,5))-ob.location).to_track_quat('-Z','Y').to_euler()
 light('_主柔光',(-6,10,15),2400,9,(.74,.85,1))
 light('_面填光',(8,6,9),1600,8,(.55,.72,1))
 light('_顶部轮廓',(0,-4,14),2800,7,(.65,.82,1))
 data=bpy.data.cameras.new(name+'_固定参考相机'); cam=bpy.data.objects.new(name+'_固定参考相机',data); sc.collection.objects.link(cam)
 cam.location=(13,34,20); target=Vector((0,0,5.8)); cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler(); data.type='ORTHO'; data.ortho_scale=16.4; sc.camera=cam
 return sc

def render(sc,name):
 sc.render.filepath=str(RENDER/name); bpy.ops.render.render(scene=sc.name,write_still=True)
 shutil.copy2(RENDER/name,OUT/name)

pair=review_scene('91_08两墙固定参考审阅',{'wall_standard_5m':3.0,'wall_door_5m':-3.0})
render(pair,'01_before.png')

for current in SLUGS:
 editable=sources[current]
 for c in [packages[current],editable]:
  for o in list(c.objects):
   if o!=roots[current]: bpy.data.objects.remove(o,do_unlink=True)
 door=current=='wall_door_5m'
 # Retain the exact structural contract; only surface art occupies the front relief band.
 if door:
  box('结构_左门垛',-1.8,0,5.95,1.4,.30,11.9,1,G1,0)
  box('结构_右门垛',1.8,0,5.95,1.4,.30,11.9,1,G1,0)
  box('结构_门楣',0,0,7.2,2.2,.30,9.4,1,G1,0)
 else: box('结构_整墙',0,0,5.95,5,.30,11.9,1,G1,0)
 # Fine edge rails rather than oversized sci-fi mechanical framing.
 for x in [-2.445,2.445]:
  box('侧边拼装压条',x,.187,5.95,.095,.08,11.84,0,G2,.012)
  box('侧边高光线',x-.028,.231,5.95,.012,.006,11.65,0,G4,.001)
  for z in [.18,3.24,7.77,11.70]: bolt(x,z,.235,.85)
 box('顶沿收口',0,.190,11.80,4.95,.11,.16,0,G2,.018)
 box('顶沿装配线',0,.250,11.75,4.77,.006,.025,0,G5,.001)
 # Tall quiet vertical panels, reference-sized horizontal tier seams.
 rectangles=[]
 for i,(x0,x1) in enumerate([(-2.37,-.025),(.025,2.37)]):
  for j,(z0,z1) in enumerate([(3.31,7.735),(7.805,11.66)]):
   cell=G2 if (i+j)%2==0 else G3
   plate('主装甲_%d_%d'%(i,j),x0,x1,z0,z1,cell=cell)
   rectangles.append((x0,x1,z0,z1,.210,cell))
   for x in [x0+.11,x1-.11]:
    for z in [z0+.115,z1-.115]:bolt(x,z,.213,.75)
 # Recessed vertical service seams and modest inset panel returns.
 for x in [-.045,.045]:box('中线密封条',x,.210,7.5,.018,.014,8.2,1,G0,.002)
 for x in [-1.32,1.36]:
  for z0,z1 in [(3.50,7.50),(8.04,11.38)]:
   box('面板浅竖向压痕',x,.208,(z0+z1)/2,.014,.005,z1-z0,1,G1,.001)
   box('压痕金属回边',x+.018,.211,(z0+z1)/2,.009,.005,z1-z0,0,G4,.001)
 for z in [3.245,7.77]:
  box('分层嵌入式横缝',0,.166,z,4.77,.025,.065,1,G0,.006)
  box('横缝上沿细金属',0,.214,z+.025,4.72,.009,.016,0,G4,.002)
 if door:
  for x0,x1 in [(-2.37,-1.34),(1.34,2.37)]:
   plate('下部门垛装甲',x0,x1,.10,3.19,cell=G2)
   rectangles.append((x0,x1,.1,3.19,.210,G2))
  plate('门楣面板',-1.32,1.32,2.71,3.19,cell=G3)
  for x in [-1.205,1.205]:
   box('分段门框立柱',x,.19,1.28,.20,.19,2.56,0,G3,.018)
   box('门框外缘封条',x+(-.118 if x<0 else .118),.236,1.3,.035,.028,2.52,1,G0,.003)
   for z in [.23,.67,1.96,2.36]:bolt(x,z,.290,.85)
   box('门框内侧光导_柔和自发光',x,.296,1.86,.024,.012,.63,3,CYAN,.002)
   box('门框护脚',x,.250,.25,.20,.13,.49,0,G2,.012)
  box('门洞顶梁',0,.19,2.595,2.6,.19,.19,0,G3,.014)
  box('门楣状态灯遮光壳',0,.251,2.89,.95,.135,.155,0,G0,.012)
  box('门楣琥珀状态灯_柔和自发光',0,.324,2.881,.77,.014,.074,3,AMBER,.005)
  for x in [-.38,-.19,0,.19,.38]:box('灯具保护筋',x,.337,2.881,.009,.009,.086,0,G2,.002)
  # Reader sits in front of the wall, never behind it or in the door passage.
  box('门禁读卡器背座',-1.62,.229,1.47,.34,.14,.69,0,G2,.020)
  box('门禁读卡器前面',-1.62,.306,1.48,.29,.038,.61,1,G1,.012)
  box('读卡器玻璃',-1.62,.330,1.58,.22,.014,.22,2,G0,.009)
  for z,w in [(1.62,.14),(1.57,.11),(1.53,.07)]:box('读卡器UI灯光',-1.62,.339,z,w,.004,.010,3,CYAN,.001)
  for x in [-1.70,-1.62,-1.54]:box('门禁按钮',x,.330,1.34,.039,.01,.026,0,G5,.003)
  label('ACCESS',-1.62,1.76,.055,.335,G6)
  label('03',.86,2.88,.19,.215,G6)
  label('SECURE / ARCHIVE',0,3.02,.091,.214,G5)
  warning(1.85,1.76,.34)
 else:
  for x0,x1 in [(-2.37,-.025),(.025,2.37)]:
   plate('下部防撞装甲',x0,x1,.11,3.19,cell=G2)
   rectangles.append((x0,x1,.11,3.19,.210,G2))
  box('下沿踢脚防撞条',0,.220,.22,4.80,.11,.29,0,G2,.018)
  box('下沿回折边',0,.277,.11,4.73,.012,.025,0,G4,.002)
  warning(-.7,.52,.30)
  label('SERVICE',.69,2.51,.14,.216,G5)
  label('08 / 5M',.69,2.29,.09,.216,G5)
 # Integrated maintenance grille; no unrelated freestanding facility is added.
 vx=1.86 if door else .86; vz=.85 if door else 1.16; vw=.69 if door else 1.18
 plate('检修格栅座',vx-vw/2,vx+vw/2,vz-.33,vz+.33,y=.225,depth=.045,cut=.035,role=0,cell=G3)
 box('检修格栅暗腔',vx,.252,vz,vw-.12,.016,.48,1,G0,.005)
 for i in range(7):box('通风百叶',vx,.267,vz-.195+i*.065,vw-.18,.035,.020,0,G3,.003)
 for x in [vx-vw/2+.06,vx+vw/2-.06]:
  for z in [vz-.265,vz+.265]:bolt(x,z,.253,.65)
 label('FILTER / 04',vx,vz+.40,.060,.213,G5)
 # Attached conduit within the 5 m footprint. Does not cross an independent asset boundary.
 for k,x in enumerate([-2.15,-2.02]):
  lo=.55 if not door else 3.53
  cylinder('竖向供能管',(x,.266,lo),(x,.266,11.55),.026 if k else .038,0,G2)
  for z in [3.7,5.70,7.60,9.65,11.3]:
   if z<lo:continue
   cylinder('管线接头',(x,.266,z-.045),(x,.266,z+.045),.037 if k else .049,0,G4)
  for z in [4.45,8.55,10.80]:box('双管束带',-2.086,.295,z,.25,.045,.045,0,G3,.006)
 # Small junction boxes and warning hardware; large panel fields remain uncluttered.
 plate('上部接线盖',-2.29,-1.85,9.12,9.58,y=.245,depth=.09,role=0,cell=G2)
 for x in [-2.23,-1.91]:
  for z in [9.18,9.52]:bolt(x,z,.294,.65)
 label('PWR',-2.07,9.32,.068,.296,G6)
 for i in range(3):box('接线盒琥珀刻线',-2.06+i*.05,.297,9.23,.017,.004,.024,1,AMBER,.001)
 # Restrained markings, matching the reference's archive sector typography.
 label('B1',.75,8.88,.72,.211,G5)
 label('ARCHIVE',.75,8.56,.175,.211,G5)
 label('SECTOR',.75,8.34,.153,.211,G5)
 label('DATA / 01',.65,6.93,.12,.211,G4)
 label('AUTHORIZED PERSONNEL',.65,6.73,.067,.211,G4)
 label('STEEL RAIN',.52,10.88,.15,.211,G5)
 for x in [.08,.35,.62,.89]:box('顶部刻度',x,.215,10.64,.16,.005,.014,1,G4,.001)
 # A tiny locator light rather than a neon frame.
 box('微型灯座',1.92,.236,3.64,.27,.12,.145,0,G1,.010)
 box('琥珀维护灯_柔和自发光',1.92,.303,3.64,.17,.010,.066,3,AMBER,.004)
 # Scratches, grime runs and chipped edges are mesh decals, using only the shared palette.
 rng=random.Random(801 if not door else 802)
 wear_verts=[];wear_faces=[];wear_cells=[]
 def wear(poly,y,cell):
  i=len(wear_verts); wear_verts.extend((x,y,z) for x,z in poly); wear_faces.append(tuple(range(i,i+len(poly)))); wear_cells.append(cell)
 for x0,x1,z0,z1,y,cell in rectangles:
  for _ in range(38):
   edge=rng.choice([0,1,2]); z=rng.uniform(z0+.045,z1-.045)
   x=rng.uniform(x0+.07,x1-.07) if edge==0 else (x0+.05 if edge==1 else x1-.05)+rng.uniform(-.018,.04)
   w=rng.uniform(.003,.016); h=rng.uniform(.012,.085)
   h=min(h,(z1-z)*.8)
   if door and z<2.6 and abs(x)<1.36:continue
   wear([(x-w,z),(x+w*.7,z+.008),(x+w*.35,z+h*.4),(x+w*.2,z+h),(x-w*.2,z+h*.78)],.20435,G1 if rng.random()<.86 else G3)
  # Thin, irregular paint abrasion, within 0.35 mm of the real panel surface.
  for _ in range(4):
   x=rng.uniform(x0+.15,x1-.15); z=z1-rng.uniform(.11,.38); h=rng.uniform(.10,.42); w=rng.uniform(.008,.024)
   wear([(x-w,z),(x+w,z+.012),(x+w*.8,z-h*.25),(x+w*.45,z-h*.30),(x+w*.25,z-h),(x-w*.10,z-h*.97),(x-w*.3,z-h*.40),(x-w*.85,z-h*.35)],.20425,G2 if cell==G3 else G1)
 wear_obj=mesh('局部磨损_边缘擦伤与雨痕',wear_verts,wear_faces,1,G2)
 uv=wear_obj.data.uv_layers.active
 for face,cell in zip(wear_obj.data.polygons,wear_cells):
  u=(cell[0]-.5)/10;v=1-(cell[1]-.5)/10
  for j,li in enumerate(face.loop_indices):
   a=2*math.pi*j/len(face.loop_indices);uv.data[li].uv=(u+.028*math.cos(a),v+.028*math.sin(a))
 # Flat construction decals; keep warning strips tiny and off the threshold.
 wx=1.88 if door else -1.07
 for i in range(3):
  x=wx+(i-1)*.13
  flat('下部磨旧警示斜纹',[(x-.05,.33),(x+.02,.33),(x+.09,.57),(x+.02,.57)],.213,AMBER)
 # Convert the editable components to two integrated output meshes without operators/context dependencies.
 for emitting in [False,True]:
  vertices=[];faces=[];face_roles=[];uvs=[]
  for o in list(editable.objects):
   if o.type!='MESH':continue
   role=mats.index(o.data.materials[0])
   if (role==3)!=emitting:continue
   offset=len(vertices);vertices.extend(tuple(v.co) for v in o.data.vertices)
   for f in o.data.polygons:
    faces.append(tuple(offset+i for i in f.vertices));face_roles.append(0 if emitting else role)
    uvs.append([tuple(o.data.uv_layers['PaletteUV'].data[li].uv) for li in f.loop_indices])
  name=current+('_UI灯光_柔和自发光' if emitting else '_主体_输出')
  me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces);me.update()
  for m in ([mats[3]] if emitting else mats[:3]):me.materials.append(m)
  uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;me.uv_layers.active=uv
  for face,role,coords in zip(me.polygons,face_roles,uvs):
   face.material_index=role
   for li,co in zip(face.loop_indices,coords):uv.data[li].uv=co
  ob=bpy.data.objects.new(name,me);packages[current].objects.link(ob);ob.parent=roots[current]
  ob['asset_version']='v005';ob['visual_only']=True;ob['front_axis_blender']='+Y'
 for o in editable.objects:
  if o.type=='MESH':o['component_role']='editable_source';o['host_asset']=current

bpy.context.view_layer.update()
locked_after={n:signature(bpy.data.objects[n]) for n in locked_names}
changed=[n for n in locked_names if locked_before[n]['sha256']!=locked_after[n]['sha256']]
assert not changed, 'LOCKED OBJECTS CHANGED: '+str(changed)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_sha
assert len(bpy.data.materials)==4

# Mirror all existing output packages into manifests, not just the modified walls.
output_collection=bpy.data.collections['02_游戏输出_独立资产包_v003']
catalog=[];bounds={};tree=[]
for category in output_collection.children:
 tree.append(category.name)
 for c in category.children:
  objs=[o for o in c.objects if o.type=='MESH'];root=next((o for o in c.objects if o.type=='EMPTY'),None)
  assert objs and root,c.name
  slug=c.name.removesuffix('_通用包')
  inv=root.matrix_world.inverted(); pts=[inv@(o.matrix_world@v.co) for o in objs for v in o.data.vertices]
  lo=[round(min(v[i] for v in pts),6) for i in range(3)];hi=[round(max(v[i] for v in pts),6) for i in range(3)]
  entry={'package_id':'ENV-BATTLE-COMMON-'+slug.upper().replace('_','-'),'slug':slug,'name_zh':c.name,
   'category':category.name,'version':'v005' if slug in SLUGS else 'unchanged_from_v004','source_blend':str(BLEND),
   'blender_collection':c.name,'root_object':root.name,'objects':[o.name for o in objs],
   'object_count':len(objs),'world_position':q(root.matrix_world.translation),'local_origin':[0,0,0],
   'blender_forward_axis':'+Y','blender_up_axis':'+Z','bounds_lo':lo,'bounds_hi':hi,
   'bounds_size':[round(b-a,6) for a,b in zip(lo,hi)],
   'material_roles':sorted({m.name for o in objs for m in o.data.materials}),
   'editable_collection':sources[slug].name if slug in SLUGS else slug+'_制作源',
   'emissive_objects':[o.name for o in objs if any(m==mats[3] for m in o.data.materials)],
   'collision':'visual_only; existing Godot collision untouched','exported':False if slug in SLUGS else 'not_reexported',
   'expected_export':slug+'_visual_top3d.glb','dependencies':[str(PALETTE)],'animation':'none',
   'attachments':'Only directly attached hardware; no independent props or moving door leaf'}
  folder=DEST/'component_packages_v005'/category.name[:2]/slug;folder.mkdir(parents=True,exist_ok=True)
  (folder/'asset_manifest.json').write_text(json.dumps(entry,ensure_ascii=False,indent=2),encoding='utf-8')
  catalog.append(entry);tree.append('  '+slug+'/asset_manifest.json')
  if slug in SLUGS:bounds[slug]=entry
(DEST/'component_catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
(DEST/'component_tree.txt').write_text('\n'.join(tree),encoding='utf-8')
for s in SLUGS:
 assert bounds[s]['bounds_lo'][0]>=-2.50001 and bounds[s]['bounds_hi'][0]<=2.50001
 assert abs(bounds[s]['bounds_lo'][2])<.00001 and abs(bounds[s]['bounds_hi'][2]-11.9)<.00001
 # No new front attachment may enter the door's original clear aperture.
 if s=='wall_door_5m':
  for o in sources[s].objects:
   for v in o.data.vertices:
    x,y,z=v.co
    assert not (-1.09999<x<1.09999 and .00001<z<2.49999), (o.name,tuple(v.co))

report={'source':str(SOURCE),'source_sha256':source_sha,'result':str(BLEND),'scope':['08/wall_standard_5m','08/wall_door_5m'],
 'locked_object_count':len(locked_names),'locked_match':not changed,'locked_changed':changed,
 'locked_before_sha256':digest(locked_before),'locked_after_sha256':digest(locked_after),'source_unchanged':True,
 'materials_unchanged':material_before,'material_count':len(bpy.data.materials),'package_count':len(catalog),
 'category_count':len(output_collection.children),'empty_packages':[],'multiple_package_membership':[],
 'walls':bounds,'door_clear_aperture':[2.2,2.5],'logical_wall_height':12,'visual_wall_height':11.9,
 'interface_notes':['Roots and 5m span unchanged. Front relief is now at most +0.341m local Y; previous +0.153/+0.215m.',
 'Review instances are separated 6m for visibility; library original root placements are unchanged.',
 'Independent moving door in category 10 is locked. No Godot import or collision edit.',
 'Old downstream object-name enumerators for v004 must not be reused to export v005; enumerate package meshes instead.'],
 'editable_mesh_count':sum(len(sources[s].objects) for s in SLUGS),'output_wall_mesh_count':4,
 'removed_display_geometry':[],'game_runtime_integrated':False}
(DEST/'qa/scope_lock_after.json').write_text(json.dumps(locked_after,ensure_ascii=False,indent=2),encoding='utf-8')
(DEST/'qa/task_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
# Save the original master scene with all non-target collections, settings and cameras intact.
# The added preview scene provides a non-overlapping review without changing asset transforms.
bpy.context.window.scene=master
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=False)
print('WALL08_BUILD_SAVED',str(BLEND),flush=True)
# Standalone asset library retains local originals, hidden editable sources and a convenient instance preview.
standalone=bpy.data.scenes.new('08_两墙独立审阅_制作与输出')
standalone.render.engine=pair.render.engine
standalone.world=pair.world;standalone.camera=pair.camera
for c in packages.values():standalone.collection.children.link(c)
edit_parent=bpy.data.collections.new('01_制作组件_两墙_默认隐藏');edit_parent.hide_render=True;edit_parent.hide_viewport=True
standalone.collection.children.link(edit_parent)
for c in sources.values():edit_parent.children.link(c)
for o in pair.objects:
 if o.type in ['CAMERA','LIGHT']:standalone.collection.objects.link(o)
bpy.data.libraries.write(str(TARGET_FILE),{standalone,pair},path_remap='ABSOLUTE',fake_user=True,compress=True)
render(pair,'02_after.png')
# Dedicated fixed close-ups preserve the same camera definition before/after in later render pass.
for s,label_name in [('wall_standard_5m','03_standard_detail.png'),('wall_door_5m','04_door_detail.png')]:
 sc=review_scene('92_'+s+'_近景',{s:0})
 sc.camera.location=(3.8,17,6.5);sc.camera.rotation_euler=(Vector((0,0,2.0))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=5.6
 sc.render.resolution_x=1500;sc.render.resolution_y=1500
 render(sc,label_name)
# Front elevation checks literal dimensions without perspective foreshortening.
front=review_scene('93_08正立面接口核验',{'wall_standard_5m':3,'wall_door_5m':-3})
front.camera.location=(0,30,5.95);front.camera.rotation_euler=(Vector((0,0,5.95))-front.camera.location).to_track_quat('-Z','Y').to_euler();front.camera.data.ortho_scale=14
front.render.resolution_x=1500;front.render.resolution_y=1500
render(front,'05_front.png')
# High angled view reveals panel relief and unchanged open threshold, more legible than a 0.5m-thick line.
top=review_scene('94_08俯视结构核验',{'wall_standard_5m':3,'wall_door_5m':-3})
top.camera.location=(0,19,31);top.camera.rotation_euler=(Vector((0,0,5.5))-top.camera.location).to_track_quat('-Z','Y').to_euler();top.camera.data.ortho_scale=13
render(top,'06_top.png')
bpy.context.window.scene=master
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=False)
print('WALL08_ALL_RENDERS_SAVED',flush=True)
