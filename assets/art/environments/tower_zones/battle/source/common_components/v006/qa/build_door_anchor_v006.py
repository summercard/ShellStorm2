"""Blender 4.5: collection-anchor correction and independent door art. No runtime writes."""
import bpy,bmesh,json,math,hashlib,shutil,random,ast,runpy,sys
from pathlib import Path
from mathutils import Vector,Matrix
BASE=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle/source/common_components')
SOURCE=BASE/'v005/战局区块_通用组件库_v005.blend'
DEST=BASE/'v006'; OUT=Path('I:/工作项目/shellstrom2/outputs/door_anchor_v006')
BLEND=DEST/'战局区块_通用组件库_v006.blend'
PALETTE=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png')
RENDER=DEST/'renders'
for p in [RENDER,OUT,DEST/'qa']:p.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));master=bpy.context.scene;bpy.context.view_layer.update()
ROLES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[bpy.data.materials[n] for n in ROLES]
# Defaults on imported functions are evaluated immediately.
G0=(10,1);G1=(10,2);G2=(10,3);G3=(10,4);G4=(10,5);G5=(10,6);G6=(10,7)
# Reuse geometry and signature functions only; never execute v005 builder.
code=ast.parse((BASE/'v005/qa/build_wall08_v005.py').read_text(encoding='utf-8'))
for node in code.body:
 if isinstance(node,ast.FunctionDef) and node.name in ['digest','q','rna_props','signature','palette_uv','make_mesh','mesh','box','plate','cylinder','bolt','label','flat']:
  exec(compile(ast.Module(body=[node],type_ignores=[]),'v005_helpers','exec'))
raw_signature=signature
def signature(o):
 d=raw_signature(o)['details']
 if 'data' in d:d['data'].pop('session_uid',None)
 return {'sha256':digest(d),'details':d}
G0=(10,1);G1=(10,2);G2=(10,3);G3=(10,4);G4=(10,5);G5=(10,6);G6=(10,7)
# Match warm/cool accent cells by actual shared-palette RGB rather than assume locations.
image=next(i for i in bpy.data.images if Path(bpy.path.abspath(i.filepath)).resolve()==PALETTE.resolve())
pix=list(image.pixels);w,h=image.size
cells={}
for row in range(1,11):
 for col in range(1,11):
  x=int((col-.5)*w/10);y=int((10-row+.5)*h/10);idx=(y*w+x)*4
  cells[(col,row)]=pix[idx:idx+3]
def color_cell(target):return min(cells,key=lambda c:sum((cells[c][i]-target[i])**2 for i in range(3)))
AMBER=color_cell((.80,.47,.12));CYAN=color_cell((.1,.65,.7))
roots={s:bpy.data.objects['ROOT_'+s+'_通用组件'] for s in ['wall_door_5m','door_5m']}
packs={s:bpy.data.collections[s+'_通用包'] for s in roots}
old_offsets={s:list(c.instance_offset) for s,c in packs.items()}
current='door_5m';editable=bpy.data.collections['door_5m_制作源']
modified=set(editable.all_objects)|{o for o in packs[current].objects if o.type=='MESH'}
instances=[o for o in bpy.data.objects if o.instance_type=='COLLECTION' and o.instance_collection in packs.values()]
locked={o.name:signature(o) for o in bpy.data.objects if o not in modified and o not in instances}
source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
(DEST/'qa/locked_before.json').write_text(json.dumps(locked,ensure_ascii=False,indent=2),encoding='utf-8')
# Fix COLLECTION placement anchor only. Preserve root and mesh geometry, including full master layout.
instance_corrections=[]
for ob in instances:
 s=next(s for s,c in packs.items() if c==ob.instance_collection)
 assert ob.parent is None and not ob.constraints,ob.name
 # Other scenes may have unevaluated matrix_world on reopen. These instances are unparented.
 delta=roots[s].matrix_world.translation-Vector(old_offsets[s]);before=ob.matrix_basis.copy()
 after=before @ Matrix.Translation(delta)
 ob.matrix_world=after
 assert max(abs(a-b) for row_a,row_b in zip(before@Matrix.Translation(-Vector(old_offsets[s])),after@Matrix.Translation(-roots[s].matrix_world.translation)) for a,b in zip(row_a,row_b))<1e-4
 instance_corrections.append({'name':ob.name,'before':q(before),'after':q(after),'rendered_geometry_unchanged':True})
for s,c in packs.items():c.instance_offset=roots[s].matrix_world.translation
bpy.context.view_layer.update()
# Root authoring locations remain locked; collection anchor is its explicit offset.

def review(name,which='door'):
 sc=bpy.data.scenes.new(name);sc.render.engine='CYCLES';sc.cycles.samples=40;sc.cycles.use_denoising=True
 sc.render.resolution_x=1400;sc.render.resolution_y=1400;sc.render.resolution_percentage=100
 sc.view_settings.view_transform='AgX';sc.view_settings.look='AgX - Medium High Contrast';sc.view_settings.exposure=.6
 world=bpy.data.worlds.new(name+'_环境');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.10,.14,.19,1);world.node_tree.nodes['Background'].inputs[1].default_value=.55;sc.world=world
 for s in (['door_5m'] if which=='door' else ['wall_door_5m','door_5m']):
  ob=bpy.data.objects.new(name+'_'+s,None);sc.collection.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=packs[s];ob.location=(0,0,0)
 cam=bpy.data.objects.new(name+'_固定相机',bpy.data.cameras.new(name+'_固定相机'));sc.collection.objects.link(cam);cam.data.type='ORTHO';cam.data.ortho_scale=3.6
 target=Vector((0,0,1.24));cam.location=(3.7,11,4.8);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();sc.camera=cam
 for name_,loc,energy,size,color in [('主',(-3,5,6),500,5,(.80,.9,1)),('填',(4,3,3),260,4,(.68,.82,1)),('轮廓',(1,-4,5),600,4,(.8,.86,1))]:
  data=bpy.data.lights.new(name+name_,'AREA');data.energy=energy;data.shape='DISK';data.size=size;data.color=color
  light=bpy.data.objects.new(name+name_,data);sc.collection.objects.link(light);light.location=loc;light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
 return sc

def render(sc,filename):
 sc.render.filepath=str(RENDER/filename);bpy.ops.render.render(scene=sc.name,write_still=True);shutil.copy2(RENDER/filename,OUT/filename)

door_scene=review('98_独立门扇_同机位前后');render(door_scene,'01_door_before.png')
# Dispose authorized old door only; all wall meshes remain byte-for-byte unchanged.
for c in [editable,packs[current]]:
 for o in list(c.objects):
  if o.type=='MESH':bpy.data.objects.remove(o,do_unlink=True)
# The leaf outline is unchanged: 2.2 x .18 x 2.5m. Relief on BOTH sides stays inside +/- .09m.
box('整体门芯',0,0,1.25,2.2,.06,2.5,0,G1,.008)
# Make front components in .03.. .09. Mirror later for a finished back, symmetrical anchor and no extra clearance.
front_start=set(editable.objects)
for sign in [-1,1]:
 x=sign*1.04
 box('周边金属锁边',x,.055,1.25,.115,.070,2.46,0,G3,.006)
 box('侧边橡胶密封槽',sign*.971,.062,1.25,.021,.017,2.31,1,G0,.002)
 for z in [.18,.62,1.87,2.33]:bolt(x,z,.072,.63)
for z in [.065,2.435]:box('顶底收边梁',0,.055,z,2.12,.07,.115,0,G3,.006)
for sign in [-1,1]:
 x0,x1=(-.944,-.04) if sign<0 else (.04,.944)
 plate('上部斜切装甲',x0,x1,1.37,2.35,y=.053,depth=.041,cut=.07,cell=G3 if sign<0 else G2)
 plate('下部斜切装甲',x0,x1,.20,1.13,y=.053,depth=.041,cut=.07,cell=G2 if sign<0 else G3)
 # Nested edge notches and sub-panel stripes avoid a flat colored rectangle.
 box('侧装甲压痕',sign*.79,.075,1.79,.012,.003,.86,1,G1,.001)
 box('底部防撞贴片',sign*.49,.075,.27,.69,.013,.14,0,G2,.004)
 for xx in [x0+.075,x1-.075]:
  for zz in [.28,1.04,1.46,2.26]:bolt(xx,zz,.075,.48)
# Central structural spine and readable service belt; a single moving leaf, not simulated bifold doors.
box('中央锁闭脊',0,.053,1.24,.060,.060,2.18,0,G1,.005)
box('中央细金属芯',0,.086,1.24,.012,.006,1.95,0,G5,.001)
plate('中部横向锁机装甲',-.945,.945,1.17,1.34,y=.052,depth=.066,cut=.035,role=0,cell=G2)
for sign in [-1,1]:
 box('锁机连接端',sign*.88,.075,1.255,.085,.021,.14,0,G4,.003)
 # Captive fasteners on lock belt.
 bolt(sign*.70,1.255,.075,.6)
# Flush recessed handle, not a second wall-mounted reader.
plate('内嵌把手金属座',-.60,-.30,.84,1.11,y=.065,depth=.026,cut=.035,role=0,cell=G4)
box('把手黑色内凹',-.45,.082,.975,.206,.007,.175,1,G0,.01)
box('把手内握梁',-.45,.087,.977,.038,.006,.125,0,G5,.002)
# Small service access hatch and grille.
plate('维护检修盖',.18,.74,.52,.94,y=.063,depth=.028,cut=.036,role=0,cell=G2)
box('检修百叶暗底',.46,.079,.715,.41,.006,.21,1,G0,.002)
for j in range(5):box('检修百叶',.46,.084,.634+j*.040,.34,.008,.013,0,G4,.002)
for x in [.23,.69]:
 for z in [.57,.89]:bolt(x,z,.075,.45)
# Single small status jewel + segmented top indicator.
box('状态玻璃窗',.45,.078,1.60,.24,.014,.105,2,G0,.005)
for i in range(3):box('状态UI灯光',.38+i*.067,.087,1.60,.035,.004,.044,3,CYAN,.001)
plate('上部灯条槽',-.35,.35,2.145,2.26,y=.066,depth=.030,cut=.025,role=0,cell=G0)
for i in range(6):box('琥珀UI灯光',-.235+i*.094,.086,2.20,.065,.006,.03,3,AMBER,.001)
# Painted typography and hazard marks reside on panel face; explicit matrix avoids depsgraph text drift.
label('03',-.43,1.78,.27,.0755,G6)
label('ARCHIVE',.43,1.89,.095,.0755,G5)
label('SECURE ACCESS',.43,1.77,.048,.0755,G4)
label('MECHANICAL / LOCK',0,1.215,.035,.086,G5)
label('SERVICE',.45,.96,.045,.0755,G4)
label('SS / B1',-.43,.58,.055,.0755,G4)
for i in range(4):
 x=-.69+i*.115
 flat('下部警示斜纹',[(x,.35),(x+.04,.35),(x+.085,.47),(x+.045,.47)],.0755,AMBER)
# Sparse wear placed on the panel, small enough not to read as arbitrary triangles.
rng=random.Random(180906)
for j in range(32):
 x=rng.choice([-.86,-.14,.14,.86])+rng.uniform(-.015,.015);z=rng.uniform(.32,2.28)
 if 1.1<z<1.4:continue
 width=rng.uniform(.003,.009);height=rng.uniform(.015,.048)
 flat('边缘漆面擦伤',[(x,z),(x+width,z+.002),(x+width*.7,z+height),(x+.001,z+height*.85)],.075,G1)
# Mirror front geometry around Y=0 for an equally finished back; reverse winding to preserve normals.
front=[o for o in editable.objects if o not in front_start]
for o in front:
 dup=o.copy();dup.data=o.data.copy();dup.name=o.name+'_背面';editable.objects.link(dup)
 bm=bmesh.new();bm.from_mesh(dup.data)
 for v in bm.verts:v.co.x=-v.co.x;v.co.y=-v.co.y
 # 180 degree Z rotation has positive determinant; winding remains valid.
 bm.to_mesh(dup.data);bm.free()
# Editable source nodes all share the package bottom center; they have their parent/collection hidden by the existing source branch.
for o in editable.objects:o['host_asset']='door_5m';o['component_role']='editable_source'
for emit in [False,True]:
 verts=[];faces=[];indices=[];uvs=[]
 for o in editable.objects:
  role=mats.index(o.data.materials[0])
  if (role==3)!=emit:continue
  offset=len(verts);verts.extend(tuple(v.co) for v in o.data.vertices)
  for f in o.data.polygons:
   faces.append(tuple(offset+i for i in f.vertices));indices.append(0 if emit else role);uvs.append([tuple(o.data.uv_layers['PaletteUV'].data[li].uv) for li in f.loop_indices])
 name='door_5m_'+('UI灯光_柔和自发光' if emit else '门扇_输出')
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 for m in ([mats[3]] if emit else mats[:3]):me.materials.append(m)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;me.uv_layers.active=uv
 for f,idx,coords in zip(me.polygons,indices,uvs):
  f.material_index=idx
  for li,co in zip(f.loop_indices,coords):uv.data[li].uv=co
 ob=bpy.data.objects.new(name,me);packs[current].objects.link(ob);ob.parent=roots[current];ob.matrix_parent_inverse=Matrix.Identity(4);ob.matrix_basis=Matrix.Identity(4)
 ob['visual_only']=True;ob['asset_version']='v006';ob['origin_contract']='bottom_center'
bpy.context.view_layer.update();render(door_scene,'02_door_after.png')
assembly=review('99_门墙接口_装配近景','assembly');assembly.camera.data.ortho_scale=5.8;assembly.camera.location=(4,14,5);assembly.camera.rotation_euler=(Vector((0,0,1.8))-assembly.camera.location).to_track_quat('-Z','Y').to_euler();render(assembly,'03_assembly.png')
full=review('100_门墙装配_完整全景','assembly');full.camera.data.ortho_scale=13.8;full.camera.location=(8,24,15);full.camera.rotation_euler=(Vector((0,0,5.8))-full.camera.location).to_track_quat('-Z','Y').to_euler();render(full,'04_full_wall.png')
front_scene=review('101_门扇正立面_底部中心');front_scene.camera.location=(0,12,1.25);front_scene.camera.rotation_euler=(Vector((0,0,1.25))-front_scene.camera.location).to_track_quat('-Z','Y').to_euler();front_scene.camera.data.ortho_scale=2.95;render(front_scene,'05_door_front.png')
# Exact orthographic top view for centered thickness and assembled alignment.
top=review('102_门墙俯视接口','assembly');top.camera.location=(0,0,20);top.camera.rotation_euler=(0,0,0);top.camera.data.ortho_scale=5.5;top.render.resolution_y=450;render(top,'06_top.png')
# Actual evaluated collection instances at four rotations, not just transforming an arbitrary zero vector.
probe=bpy.data.scenes.new('103_锚点四向实例核验');anchor_tests=[]
bpy.context.window.scene=probe
for s,c in packs.items():
 for angle in [0,90,180,270]:
  inst=bpy.data.objects.new('锚点实测_'+s+'_'+str(angle),None);probe.collection.objects.link(inst);inst.instance_type='COLLECTION';inst.instance_collection=c;inst.location=(17,-8,2);inst.rotation_euler.z=math.radians(angle)
  bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();pts=[];count=0
  inv=inst.matrix_world.inverted()
  for item in deps.object_instances:
   if item.is_instance and item.parent and item.parent.original==inst and item.object.type=='MESH':
    count+=1;pts.extend(inv@(item.matrix_world@v.co) for v in item.object.data.vertices)
  assert pts,(s,angle,'no evaluated meshes')
  lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
  err=max(abs((lo[0]+hi[0])/2),abs(lo[2]))
  # wall Y anchor is structure midplane, not asymmetric decorative protrusion midpoint.
  if s=='door_5m':err=max(err,abs((lo[1]+hi[1])/2))
  assert err<.0001,(s,angle,lo,hi)
  width=5 if s=='wall_door_5m' else 2.2;height=11.9 if s=='wall_door_5m' else 2.5
  assert abs(hi[0]-lo[0]-width)<.0001 and abs(hi[2]-height)<.0001
  if s=='door_5m':assert lo[1]>=-.0901 and hi[1]<=.0901,(lo,hi)
  anchor_tests.append({'asset':s,'angle':angle,'evaluated_mesh_count':count,'local_bounds_lo':q(lo),'local_bounds_hi':q(hi),'bottom_center_error_m':err,'passed':True})
  bpy.data.objects.remove(inst,do_unlink=True)
bpy.data.scenes.remove(probe)
bpy.context.window.scene=master;bpy.context.view_layer.update()
locked_after={n:signature(bpy.data.objects[n]) for n in locked}
assert all(locked[n]['sha256']==locked_after[n]['sha256'] for n in locked),[n for n in locked if locked[n]['sha256']!=locked_after[n]['sha256']]
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash
(DEST/'qa/locked_after.json').write_text(json.dumps(locked_after,ensure_ascii=False,indent=2),encoding='utf-8')
# Full collection/disk mirror, preserving stable IDs of all existing packages.
catalog=json.loads((BASE/'v005/component_catalog.json').read_text(encoding='utf-8'))
for entry in catalog:
 s=entry['slug'];c=bpy.data.collections[entry['blender_collection']];r=bpy.data.objects[entry['root_object']]
 entry['source_blend']=str(BLEND)
 if s in packs:
  entry['version']='v006';entry['exported']=False;entry['collection_instance_offset']=q(c.instance_offset)
  entry['anchor_contract']='root and mesh origins at structural bottom center; collection instance offset equals authored root world translation'
  entry['objects']=[o.name for o in c.objects if o.type=='MESH'];entry['object_count']=len(entry['objects'])
  entry['editable_collection']=s+'_制作源'
  if s=='door_5m':entry['attachments']='Independent single rigid moving door leaf; no fixed wall trim welded into leaf';entry['material_roles']=ROLES;entry['emissive_objects']=['door_5m_UI灯光_柔和自发光']
  meshes=[o for o in c.objects if o.type=='MESH'];inv=r.matrix_world.inverted();pts=[inv@(o.matrix_world@v.co) for o in meshes for v in o.data.vertices]
  lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
  entry['bounds_lo']=q(lo);entry['bounds_hi']=q(hi);entry['bounds_size']=q([hi[i]-lo[i] for i in range(3)])
 folder=DEST/'component_packages_v006'/entry['category'][:2]/s;folder.mkdir(parents=True,exist_ok=True);(folder/'asset_manifest.json').write_text(json.dumps(entry,ensure_ascii=False,indent=2),encoding='utf-8')
(DEST/'component_catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
(DEST/'component_tree.txt').write_text('\n'.join(e['category'][:2]+'/'+e['slug']+'/asset_manifest.json' for e in catalog),encoding='utf-8')
report={'source':str(SOURCE),'source_sha256':source_hash,'result':str(BLEND),'locked_match':True,'locked_count':len(locked),'wall_geometry_unchanged':True,'root_positions_unchanged':True,'collection_offsets_before':old_offsets,'collection_offsets_after':{s:q(c.instance_offset) for s,c in packs.items()},'review_instance_corrections':instance_corrections,'actual_evaluated_anchor_tests':anchor_tests,'door_dimensions':[2.2,.18,2.5],'material_count':len(bpy.data.materials),'palette_external':True,'source_preserved':True,'runtime_imported':False,'door_motion':'single rigid leaf, no new animation','package_count':len(catalog)}
(DEST/'qa/anchor_and_door_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.context.window.scene=master
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=False)
print('DOOR_ANCHOR_BUILD_OK',flush=True)
