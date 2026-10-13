"""Whole-face low-poly shell, isolated pillar lamps, noncoplanar tower tops, bridge thresholds and supports."""
import bpy,bmesh,ast,math,json,sys,shutil,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_fixes_v026/state.json').parent;W.mkdir(parents=True,exist_ok=True)
OLD=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v025';D=OLD.parent/'v026';B=D/'Boss房B_整面外壳与桥门修复_v026.blend'
assert not B.exists();assert 'v025' in bpy.data.filepath
bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_live.blend'),copy=True)
scene=bpy.context.scene;scene.frame_set(1);bpy.context.view_layer.update();source=bpy.data.collections['01_制作组件_母版与可编辑零件'];out=bpy.data.collections['02_游戏输出_组件实例布局'];show=bpy.data.collections['90_展示与验收_灯光相机']
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
for n in ast.parse((ROOT/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in ('signature','tris'):exec(compile(ast.Module(body=[n],type_ignores=[]),'<helper>','exec'))
catalog=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'))
retired=['enclosure_wall_5m','enclosure_slab_5m','enclosure_doorwall_5m'];towers=['compute_tower_tall','compute_tower_stepped','compute_tower_compact','suspended_server_5m','door_support_pier'];mutable=set()
for slug in retired+towers:
 info=next(r for r in catalog if r['slug']==slug);mutable.update(o.name for o in bpy.data.collections['组件_'+info['name_zh']].all_objects)
 if slug in retired:mutable.update(o.name for o in scene.objects if o.instance_collection and o.instance_collection.name=='输出资产包_'+slug)
eastleaves=[o for o in scene.objects if o.instance_collection and o.instance_collection.name in ('输出资产包_exit_leaf_a','输出资产包_exit_leaf_b') and 32<o.location.x<35];mutable.update(o.name for o in eastleaves)
locked={o.name:signature(o) for o in scene.objects if o.name not in mutable};poses={n:[list(r) for r in bpy.data.objects[n].matrix_world] for n in ('草稿巨屏_246','草稿巨屏_247','草稿巨屏_248')}
shell_before=sum(tris(o.instance_collection) for o in scene.objects if o.instance_collection and o.instance_collection.name in ['输出资产包_'+s for s in retired]);shell_before_count=sum(bool(o.instance_collection and o.instance_collection.name in ['输出资产包_'+s for s in retired]) for o in scene.objects)
defs=[('shell_wall_solid_80m','整面封闭装甲墙','shell_wall'),('shell_wall_gate_80m','整面高位入口墙','shell_wall'),('shell_wall_gate_100m','整面侧门长墙','shell_wall'),('shell_horizontal_80x100m','整面顶底围护板','shell_horizontal'),('stair_pillar_light','独立栏杆竖向灯','pillar_light'),('bridge_threshold','桥门衔接平台','threshold'),('bridge_belly_5m','桥下设备与曲管托架','bridge_belly'),('door_undersupport','门下层叠承力机座','door_support_base')]
plan['components']=[r for r in plan['components'] if r['slug'] not in retired];catalog=[r for r in catalog if r['slug'] not in retired]
for slug,name,family in defs:
 rec={'slug':slug,'name_zh':name,'component_id':'ENV-EXPEDITION-BOSS-B-'+slug.upper().replace('_','-'),'component_family':family,'category':'facilities' if slug=='stair_pillar_light' else 'architecture','scope':'room_type_local','front_axis':'-Y','serves_room_types':['BOSS_ROOM']};plan['components'].append(rec);catalog.append(rec.copy())
plan.update(version='v026',component_budget={'limit':50,'planned':len(catalog),'remaining':50-len(catalog)},refinement={'shell':'User overrides tiled enclosure: exactly 6 whole-face instances, 4 definitions; one body output mesh each','tower_top':'Remove coincident main-box/shoulder horizontal surfaces by 0.08m offset','doors':'Close east inner leaf pair; preserve side bridge dimensions; thresholds cover measured 0.95m break','lamps':'80 independent vertical post lamps paired to existing 100 step activation sequence','supports':'Layered bridge belly trays, curved conduits and door bearing blocks'})
D.mkdir(parents=True,exist_ok=True)
for p in OLD.glob('*.json'):shutil.copy2(p,D/p.name)
for p in OLD.glob('reference*.png'):shutil.copy2(p,D/p.name)
shutil.copytree(OLD/'textures',D/'textures',dirs_exist_ok=True);write(D/'component_plan.json',plan)
masters={r['slug']:bpy.data.collections[r['collection']] for r in catalog if r.get('collection')};parts=[];current=None;cache={};edits={};meta={}
DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8);roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'];mats=[bpy.data.materials[n] for n in roles]
for n in ast.parse((ROOT/'scripts/blender/build_boss_room_B_structure_v022.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in {'collection','uv','geom_box','part','box','bar','begin','object_from','finish','aim'}:
  if n.name=='geom_box':
   for k in ast.walk(n):
    if isinstance(k,ast.keyword) and k.arg=='segments':k.value=ast.Constant(value=1)
   ast.fix_missing_locations(n)
  exec(compile(ast.Module(body=[n],type_ignores=[]),'<helper>','exec'))
for n in ast.parse((ROOT/'scripts/blender/complete_boss_room_B_v025.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in ('bezier','tube'):exec(compile(ast.Module(body=[n],type_ignores=[]),'<cable_helper>','exec'))
for slug in retired:
 oldrec=next(r for r in json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'] if r['slug']==slug);parent=bpy.data.collections['组件_'+oldrec['name_zh']]
 for o in list(scene.objects):
  if o.instance_collection and o.instance_collection.name=='输出资产包_'+slug:bpy.data.objects.remove(o,do_unlink=True)
 for child in list(parent.children):
  for o in list(child.objects):bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.collections.remove(child)
 bpy.data.collections.remove(parent)
# Rebuild tower outputs from their editable source, preserving material roles and UV cells.
top_report=[]
for slug in towers:
 rec=next(r for r in catalog if r['slug']==slug);edit=bpy.data.collections['制作零件_'+slug];core=next(o for o in edit.objects if o.get('semantic_part')=='大型方形主壳');top=max(v.co.z for v in core.data.vertices);shifted=[]
 for o in edit.objects:
  center=sum(v.co.z for v in o.data.vertices)/len(o.data.vertices)
  if center>top*.87 and o.get('semantic_part') in ('外凸方形肩座','肩座前端装甲块','宽扣耳','顶部横向压条'):
   for v in o.data.vertices:v.co.z+=.08
   shifted.append(o.name)
 final=masters[slug];names={any(m==mats[3] for m in o.data.materials):o.name for o in final.objects}
 for o in list(final.objects):bpy.data.objects.remove(o,do_unlink=True)
 for emission in (False,True):
  vs=[];fs=[];rr=[];cc=[]
  for o in edit.objects:
   if o.type!='MESH' or any(m==mats[3] for m in o.data.materials)!=emission:continue
   start=len(vs);vs.extend(tuple(v.co) for v in o.data.vertices)
   for p in o.data.polygons:
    fs.append(tuple(start+i for i in p.vertices));rr.append(roles.index(o.data.materials[p.material_index].name));co=o.data.uv_layers['PaletteUV'].data[p.loop_start].uv;cc.append((int(co.x*10),int(co.y*10)))
  if fs:object_from(names[emission],vs,fs,rr,cc,final)
 top_report.append({'slug':slug,'core_top':top,'collar_top':top+.08,'shifted_parts':shifted})
def inst(slug,loc=(0,0,0),rz=0,matrix=None,name=None):
 o=bpy.data.objects.new(name or next(r['name_zh'] for r in catalog if r['slug']==slug)+f'_{len(out.objects):04}',None);out.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=masters[slug];o.location=loc;o.rotation_euler.z=math.radians(rz)
 if matrix is not None:o.matrix_world=matrix
 return o
def wall(length,opening=None):
 # One welded closed extrusion, with an actual door aperture. No stacked wall tiles.
 xs=[-length/2,length/2];zs=[0,72]
 if opening:cx,z0=opening;xs=[-length/2,cx-2.5,cx+2.5,length/2];zs=sorted(set([0,z0,z0+6,72]))
 verts=[];faces=[];lookup={}
 def vi(x,y,z):
  key=(x,y,z)
  if key not in lookup:lookup[key]=len(verts);verts.append(key)
  return lookup[key]
 cells=[]
 for i in range(len(xs)-1):
  for j in range(len(zs)-1):
   if opening and i==1 and zs[j]==opening[1]:continue
   cells.append((i,j));a,b=xs[i:i+2];lo,hi=zs[j:j+2]
   faces.append(tuple(vi(x,-.30,z) for x,z in [(a,lo),(b,lo),(b,hi),(a,hi)]));faces.append(tuple(vi(x,.30,z) for x,z in [(a,hi),(b,hi),(b,lo),(a,lo)]))
 for i,j in cells:
  a,b=xs[i:i+2];lo,hi=zs[j:j+2]
  for adjacent,edge in [((i-1,j),[(a,lo),(a,hi)]),((i+1,j),[(b,hi),(b,lo)]),((i,j-1),[(b,lo),(a,lo)]),((i,j+1),[(a,hi),(b,hi)])]:
   if adjacent not in cells:
    (x1,z1),(x2,z2)=edge;faces.append((vi(x1,-.3,z1),vi(x2,-.3,z2),vi(x2,.3,z2),vi(x1,.3,z1)))
 part('整面带厚度围护',verts,faces,role=1,cell=DARK)
 # Sparse structural bands only; all are merged into the same single output mesh.
 for z in (12,24,48,60):
  for side in (-1,1):
   if opening and opening[1]-.15<z<opening[1]+6.15:continue
   box('整面横向加强带',(length,.12,.18),(0,side*.34,z),0,DARK,b=0)
for slug,length,opening in [('shell_wall_solid_80m',80,None),('shell_wall_gate_80m',80,(0,48)),('shell_wall_gate_100m',100,(22.5,36))]:begin(slug);wall(length,opening);finish()
begin('shell_horizontal_80x100m');box('整面顶底板',(80,100,.4),(0,0,.2),1,DARK,b=0);finish()
shell=[]
for slug,loc,rz,n in [('shell_wall_solid_80m',(0,27.5,-36),0,'外壳_后墙'),('shell_wall_gate_80m',(0,-72.5,-36),0,'外壳_入口墙'),('shell_wall_gate_100m',(-40,-22.5,-36),90,'外壳_西墙'),('shell_wall_gate_100m',(40,-22.5,-36),90,'外壳_东墙'),('shell_horizontal_80x100m',(0,-22.5,-36.4),0,'外壳_底面'),('shell_horizontal_80x100m',(0,-22.5,36),0,'外壳_顶面')]:shell.append(inst(slug,loc,rz,name=n).name)
begin('stair_pillar_light');box('竖灯黑色背壳',(.15,.075,.86),(0,0,.43),0,DARK,b=.01);box('竖向红色灯条',(.078,.025,.76),(0,-.05,.43),3,RED,b=.008);finish()
pillar_lamps=[]
for j in range(10):
 for yy in (-2.25,-.75,.75,2.25):
  seq=99-(j*10+round((2.25-yy)/.5))
  for side in (-1,1):
   o=inst('stair_pillar_light',(side*2.395,-15-j*5+yy,j*1.2+.6-yy*.24+.15),-90*side);o['sequence_index']=seq;o['activation_group']='stair_descent';pillar_lamps.append({'instance_id':o.name,'sequence_index':seq,'position_m':list(o.location)})
begin('bridge_threshold');box('连续门槛承重板',(5,1.5,.22),(0,0,.11),0,DARK,b=.018)
for yy in (-.6,-.3,0,.3,.6):box('门槛防滑压条',(4.85,.055,.015),(0,yy,.224),0,MID,b=.004)
for x in (-2.40,2.40):box('门槛侧压边',(.17,1.5,.07),(x,0,.23),0,EDGE,b=.01)
finish()
portals=[o for o in scene.objects if o.instance_collection==masters['exit_portal']];east=next(o for o in portals if 32<o.location.x<35)
for o in eastleaves:
 xx=-1.235 if o.instance_collection==masters['exit_leaf_a'] else 1.235;o.matrix_world=east.matrix_world@Matrix.Translation((xx,-.03,.02));o['door_state']='closed'
thresholds=[]
for door in portals:
 # Plate covers both the bridge-to-inner-door gap and the vestibule-to-outer-door gap.
 if abs(door.location.x)>30:thresholds.append(inst('bridge_threshold',matrix=door.matrix_world@Matrix.Translation((0,-.25,-.23))@Matrix.Translation(Vector(meta['bridge_threshold']['anchor']))).name)
begin('bridge_belly_5m')
for x in (-2.35,0,2.35):box('桥底宽横梁',(.24,4.60,.38),(x,0,-.25),0,DARK,b=.03)
box('中部电力桥架',(4.90,1.6,.60),(0,0,-.72),0,DARK,b=.035)
for x in (-1.65,0,1.65):
 box('桥下设备箱',(1.10,1.95,.70),(x,0,-1.35),1,DARK,b=.055)
 for y in (-1.01,1.01):box('检修面板',(.80,.06,.35),(x,y,-1.35),0,MID,b=.02)
for side in (-1,1):
 for x in (-1.7,1.7):bar('斜向托架',(x,side*2.1,-.25),(x,side*.85,-1.45),.16,.23,0,EDGE)
 pts=bezier([Vector((-2.48,side*1.5,-.5)),Vector((-1.5,side*1.75,-2.1)),Vector((1.5,side*1.75,-2.1)),Vector((2.48,side*1.5,-.5))],28);tube('桥下弧形输送管',pts,.10,0,DARK,8)
finish()
for side in (-1,1):
 for x in (15,20,25,30):inst('bridge_belly_5m',matrix=Matrix.Translation((side*x,0,-.48))@Matrix.Translation(Vector(meta['bridge_belly_5m']['anchor'])))
begin('door_undersupport')
box('门底上承台',(6.4,3.0,.60),(0,0,-.30),0,DARK,b=.07)
box('下挂机械箱',(4.9,2.0,1.8),(0,.30,-1.45),1,DARK,b=.065)
box('二级承力台',(5.5,2.55,.42),(0,.15,-2.25),0,EDGE,b=.035)
for x in (-2.2,2.2):
 box('墙侧深锚板',(.65,.55,5),(x,1,-2.5),0,DARK,b=.04)
 bar('门下粗斜撑',(x,1,-4.65),(x,-1.20,-.55),.40,.44,0,MID)
 for z in (-.85,-3.0):box('锚固搭接块',(.95,.82,.40),(x,.88,z),0,DARK,b=.04)
 pts=bezier([Vector((x*.55,-1.05,-.48)),Vector((x*.55,-1.6,-3.4)),Vector((x*.8,.15,-3.4)),Vector((x,1,-1.8))],32);tube('门下弯曲管线',pts,.14,0,DARK,8)
for x in (-1.5,0,1.5):box('下挂机箱检修盖',(1.1,.15,.86),(x,-.78,-1.43),0,MID,b=.035)
finish()
for door in portals:inst('door_undersupport',matrix=door.matrix_world@Matrix.Translation((0,0,-.27))@Matrix.Translation(Vector(meta['door_undersupport']['anchor'])))
for name,loc,target,lens in [('验收_桥门衔接',(24,-10,4),(33,0,-.8),40),('验收_桥门下方',(27,-12,-5),(33,0,-2),40),('验收_竖灯楼梯',(4,-31,8),(0,-44,9),38),('验收_顶盖修复',(24,-25,0),(19,-14,-5),50)]:
 cd=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,cd);show.objects.link(o);o.location=loc;aim(o,target);cd.lens=lens;cd.clip_end=300
for im in bpy.data.images:
 if im.source=='FILE' and 'screen_' in Path(bpy.path.abspath(im.filepath)).name:im.filepath=str(D/'textures'/Path(bpy.path.abspath(im.filepath)).name)
bpy.context.view_layer.update();changed=[n for n,h in locked.items() if n not in bpy.data.objects or signature(bpy.data.objects[n])!=h];assert not changed,changed
write(W/'scope_lock.json',{'before':locked,'screen_poses':poses,'changed':changed,'authorized':retired+towers+eastleaves[0].name.split()})
instances=[]
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 slug=next(s for s,c in masters.items() if c==o.instance_collection);r=next(r for r in catalog if r['slug']==slug);instances.append({'instance_id':o.name,'component_id':r['component_id'],'slug':slug,'position_m':list(o.location),'matrix_room_local':[list(row) for row in o.matrix_world],'rotation_euler_xyz_deg':[math.degrees(v) for v in o.rotation_euler],'scale':list(o.scale),'draft':False})
write(D/'component_instances.json',{'schema_version':2,'version':'v026','instances':instances})
text=(ROOT/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8');chunk=text[text.index('for rec in catalog:\n'):text.index("write(D/'component_catalog.json'")];exec(compile(chunk.replace("version='v024'","version='v026'"),'<export>','exec'));write(D/'component_catalog.json',{'component_count':len(catalog),'components':catalog})
light=json.loads((D/'stair_light_contract.json').read_text(encoding='utf-8'));light['pillar_lamps']=pillar_lamps;light['pillar_component']=str(D/'component_packages/stair_pillar_light/stair_pillar_light.blend');write(D/'stair_light_contract.json',light)
enc=json.loads((D/'enclosure_contract.json').read_text(encoding='utf-8'));enc['shell_instances']=shell;enc['geometry']='six whole-face low-poly meshes';write(D/'enclosure_contract.json',enc)
manifest=json.loads((D/'room_type_manifest.json').read_text(encoding='utf-8'));manifest.update(version='v026',source_blend=str(B),component_budget=plan['component_budget']);write(D/'room_type_manifest.json',manifest)
write(W/'fix_contract.json',{'shell_before_instances':shell_before_count,'shell_after_instances':6,'shell_before_expanded_triangles':shell_before,'shell_after_expanded_triangles':sum(tris(bpy.data.objects[n].instance_collection) for n in shell),'top_fixes':top_report,'thresholds':thresholds,'east_leaf_names':[o.name for o in eastleaves],'pillar_lamp_count':len(pillar_lamps)})
(D/'component_tree.txt').write_text('\n'.join(f'{r["slug"]} | {r["name_zh"]} | {r["instance_count"]}' for r in catalog),encoding='utf-8');scene.name='Boss房B_整面外壳桥门修复_v026';bpy.data.collections['Boss房B_中文资产管理_v025'].name='Boss房B_中文资产管理_v026';bpy.ops.wm.save_as_mainfile(filepath=str(B));print('SAVED_V026',len(catalog),len(instances),shell_before,sum(tris(bpy.data.objects[n].instance_collection) for n in shell))
