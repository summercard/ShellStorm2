"""Reference stairs, smooth cable arcs, modular chase lights, debris and closed shell."""
import bpy,bmesh,ast,math,json,sys,hashlib,shutil
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_enclosure_v025/state.json').parent;W.mkdir(parents=True,exist_ok=True)
OLD=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v024';D=OLD.parent/'v025';B=D/'Boss房B_楼梯弧缆与完整围护_v025.blend'
assert not B.exists();assert 'v024' in bpy.data.filepath
bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_live.blend'),copy=True)
scene=bpy.context.scene;scene.frame_set(1);bpy.context.view_layer.update()
source=bpy.data.collections['01_制作组件_母版与可编辑零件'];out=bpy.data.collections['02_游戏输出_组件实例布局'];show=bpy.data.collections['90_展示与验收_灯光相机']
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
for n in ast.parse((ROOT/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in ('signature','tris'):exec(compile(ast.Module(body=[n],type_ignores=[]),'<helper>','exec'))
catalog=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'))
retired=['draft_stair_5m','draft_wall_5m'];rebuild=['cables_swept','cables_mirrored','cables_crown'];mutable=set()
for slug in retired+rebuild:
 info=next(r for r in catalog if r['slug']==slug);col=bpy.data.collections['组件_'+info['name_zh']];mutable.update(o.name for o in col.all_objects)
 mutable.update(o.name for o in scene.objects if o.instance_collection and o.instance_collection.name=='输出资产包_'+slug)
locked={o.name:signature(o) for o in scene.objects if o.name not in mutable}
screens=[bpy.data.objects[n] for n in ('草稿巨屏_246','草稿巨屏_247','草稿巨屏_248')];poses={o.name:[list(r) for r in o.matrix_world] for o in screens}
defs=[('stair_flight_5m','精工格栅楼梯节段','stair','architecture'),('stair_chase_light','逐级感应灯组件','step_light','facilities'),('stair_landing_5m','入口钢格栅平台','landing','architecture'),('hanging_power_bundle','悬垂交错动力电缆','hanging_cable','support'),('damaged_cabinet_open','破损敞口机箱','debris','facilities'),('damaged_cabinet_crushed','凹陷破损机箱','debris','facilities'),('enclosure_wall_5m','双面井室装甲墙','enclosure_wall','architecture'),('enclosure_slab_5m','密封顶底装甲板','enclosure_slab','architecture'),('enclosure_doorwall_5m','贯通密封门墙','enclosure_doorwall','architecture')]
plan['components']=[r for r in plan['components'] if r['slug'] not in retired];catalog=[r for r in catalog if r['slug'] not in retired]
for slug,name,fam,cat in defs:
 rec={'slug':slug,'name_zh':name,'component_id':'ENV-EXPEDITION-BOSS-B-'+slug.upper().replace('_','-'),'component_family':fam,'category':cat,'scope':'room_type_local','front_axis':'-Y','serves_room_types':['BOSS_ROOM'],'variant_axis':'damage_state' if fam=='debris' else None};plan['components'].append(rec);catalog.append(rec.copy())
plan.update(version='v025',status='frozen_before_geometry',component_budget={'limit':50,'planned':len(plan['components']),'remaining':50-len(plan['components'])},refinement={'stairs':'5m wide, 50m run, 12m rise, 100 steps; 10 identical flights','lights':'100 independent paired step lamps, entrance-to-platform sequence indices 0..99','cables':'Analytic cubic Bezier curves with transported cross sections and smooth tube normals','enclosure':'x +/-40, y -72.5..27.5, z -36..36; existing side connections retained; back entrance z12','inference':'Unseen surfaces inferred from existing industrial armour; source art only'})
D.mkdir(parents=True,exist_ok=True)
for p in OLD.glob('*.json'):shutil.copy2(p,D/p.name)
shutil.copytree(OLD/'textures',D/'textures',dirs_exist_ok=True);write(D/'component_plan.json',plan)
shutil.copy2(r'C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-a1d685b8-ee9b-4e1a-9901-bc5962b1fc18.png',D/'reference_stairs.png')
masters={r['slug']:bpy.data.collections[r['collection']] for r in catalog if r.get('collection')};meta={};edits={};parts=[];current=None;cache={}
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'];mats=[bpy.data.materials[n] for n in roles]
DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8)
for n in ast.parse((ROOT/'scripts/blender/build_boss_room_B_structure_v022.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in {'collection','uv','geom_box','part','box','bar','plate','begin','object_from','finish','aim'}:
  if n.name=='geom_box':
   for k in ast.walk(n):
    if isinstance(k,ast.keyword) and k.arg=='segments':k.value=ast.Constant(value=1)
   ast.fix_missing_locations(n)
  exec(compile(ast.Module(body=[n],type_ignores=[]),'<helpers>','exec'))
def remove_master(slug):
 info=next(r for r in json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'] if r['slug']==slug);c=bpy.data.collections['组件_'+info['name_zh']]
 for o in list(scene.objects):
  if o.instance_collection and o.instance_collection.name=='输出资产包_'+slug:bpy.data.objects.remove(o,do_unlink=True)
 for child in list(c.children):
  for o in list(child.objects):bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.collections.remove(child)
 bpy.data.collections.remove(c)
for slug in retired+rebuild:remove_master(slug)
def inst(slug,loc=(0,0,0),rz=0,matrix=None,name=None):
 o=bpy.data.objects.new(name or next(r['name_zh'] for r in plan['components'] if r['slug']==slug)+f'_{len(out.objects):04}',None);out.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=masters[slug];o.location=loc;o.rotation_euler.z=math.radians(rz)
 if matrix is not None:o.matrix_world=matrix
 o['component_id']=masters[slug].get('component_id','');return o
def bezier(control,n=64):
 a,b,c,d=[Vector(v) for v in control];return [(1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t*t*c+t**3*d for t in [k/n for k in range(n+1)]]
def tube(name,pts,r=.16,role=1,cell=BLACK,sides=10):
 vs=[];fs=[];old_t=None;a=None
 for i,p in enumerate(pts):
  t=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
  if a is None:a=t.cross(Vector((0,1,0))).normalized()
  else:a=old_t.rotation_difference(t)@a;a=(a-t*a.dot(t)).normalized()
  b=t.cross(a).normalized();old_t=t
  vs.extend(tuple(p+r*(a*math.cos(k*math.tau/sides)+b*math.sin(k*math.tau/sides))) for k in range(sides))
 for i in range(len(pts)-1):
  for k in range(sides):fs.append((i*sides+k,i*sides+(k+1)%sides,(i+1)*sides+(k+1)%sides,(i+1)*sides+k))
 fs.extend([tuple(reversed(range(sides))),tuple(range((len(pts)-1)*sides,len(pts)*sides))]);part(name,vs,fs,role=role,cell=cell)
def finish_cable(paths):
 finish()
 for o in masters[current].objects:
  for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
 for o in edits[current].objects:
  for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
 # Editable spline guides remain in hidden authoring collection, excluded from packages.
 for j,pts in enumerate(paths):
  cu=bpy.data.curves.new('可编辑弧线','CURVE');cu.dimensions='3D';sp=cu.splines.new('POLY');sp.points.add(len(pts)-1)
  for p,co in zip(sp.points,pts):p.co=tuple(co-Vector(meta[current]['anchor']))+(1,)
  ob=bpy.data.objects.new('弧线导向_'+str(j),cu);edits[current].objects.link(ob);ob.hide_render=True
for slug,screen in zip(('cables_swept','cables_crown','cables_mirrored'),screens):
 begin(slug);paths=[]
 for side in (-1,1):
  for k in range(4):
   start=Vector((side*(3.65+k*.26),.92,.73));end=screen.matrix_world.inverted()@Vector((screen.location.x+side*(8+k*.55),15+k*.30,35.7))
   control=[start,start+Vector((side*1.5,1,-7-k*.4)),Vector((end.x+side*2,2.3+k*.28,-6-k*.8)),end]
   pts=bezier(control,80);paths.append(pts);tube('圆滑下垂供电缆',pts,.11+.025*(k%3))
   for q in (2,38,70):tube('弧缆接箍',pts[q:q+3],.16+.025*(k%3),0,DARK)
  for k in range(2):
   start=Vector((side*(3.5+k*.35),.95,5.85));end=screen.matrix_world.inverted()@Vector((screen.location.x-side*(1+k*.7),16.5+k*.3,35.7));pts=bezier([start,start+Vector((side*2,1,6)),end-Vector((side*2,0,7)),end]);paths.append(pts);tube('交叉上悬缆',pts,.12)
 finish_cable(paths);inst(slug,matrix=screen.matrix_world@Matrix.Translation(Vector(meta[slug]['anchor'])))
# Flight interfaces: front (-Y) high, rear (+Y) low. 10 x (0.5 run / 0.12 rise).
begin('stair_flight_5m')
for k in range(10):
 y=2.25-k*.5;z=(k+1)*.12
 box('踏步承托',(5,.50,.12),(0,y,z-.06),0,DARK,b=.015)
 box('踏步前缘',(5,.06,.055),(0,y-.22,z+.005),0,EDGE,b=.009)
 box('格栅暗底',(4.42,.35,.018),(0,y,z+.008),1,BLACK,b=0)
 for x in [-2.10+j*.14 for j in range(31)]:box('纵向防滑格条',(.024,.35,.022),(x,y,z+.023),0,MID,b=0)
 for off in (-.11,0,.11):box('横向钢格条',(4.40,.025,.024),(0,y+off,z+.024),0,DARK,b=0)
for x in (-2.52,2.52):
 bar('外侧连续箱梁',(x,-2.5,1.0),(x,2.5,-.20),.25,.34,0,DARK)
 bar('上沿扶手',(x,-2.5,2.32),(x,2.5,1.12),.14,.12,0,MID)
 bar('下沿防护横梁',(x,-2.5,1.56),(x,2.5,.36),.08,.09,0,DARK)
 for y in (-2.25,-.75,.75,2.25):
  zz=.6-y*.24;box('方形护栏立柱',(.20,.23,1.17),(x,y,zz+.58),0,DARK,b=.025);box('护栏侧板',(.05,.65,.50),(x,y+.35,zz+.50),1,DARK,b=.014)
finish()
begin('stair_chase_light')
for x in (-2.34,2.34):
 box('独立灯槽壳',(.21,.33,.055),(x,0,.0275),0,DARK,b=.015)
 box('独立红灯透镜',(.13,.26,.025),(x,0,.063),3,RED,b=.01)
finish()
begin('stair_landing_5m');box('平台底板',(5,5,.22),(0,0,.11),0,DARK,b=.025)
for k in range(31):box('平台钢格条',(4.9,.06,.035),(0,-2.4+k*.16,.2375),0,MID,b=0)
for x in (-2.48,2.48):
 box('平台侧箱梁',(.14,5,.30),(x,0,.17),0,DARK,b=.02)
 for y in (-2.25,0,2.25):box('平台栏杆柱',(.18,.18,1.1),(x,y,.79),0,DARK,b=.02)
 box('平台扶手',(.12,5,.12),(x,0,1.35),0,MID,b=.015)
finish()
lamp_records=[]
for j in range(10):
 # Compensate bbox anchor to preserve tread and connection coordinates.
 inst('stair_flight_5m',matrix=Matrix.Translation((0,-15-5*j,1.2*j))@Matrix.Translation(Vector(meta['stair_flight_5m']['anchor'])))
 for k in range(10):
  seq=99-(j*10+k);pos=(0,-12.75-j*5-k*.5,(j*10+k+1)*.12+.035)
  o=inst('stair_chase_light',pos,name=f'逐级灯_{seq:03}');o['sequence_index']=seq;o['activation_distance_m']=.7;o['initial_state']='off_in_game';o['preview_state']='all_on'
  lamp_records.append({'instance_id':o.name,'sequence_index':seq,'position_m':list(pos),'trigger_owner':'room_runtime','per_instance_emission_required':True})
for y in (-65,-70):inst('stair_landing_5m',matrix=Matrix.Translation((0,y,11.745))@Matrix.Translation(Vector(meta['stair_landing_5m']['anchor'])))
begin('hanging_power_bundle');paths=[]
for k in range(5):
 left=Vector((-4+k*.26,-.35+k*.5,35.7));bottom=Vector((-.2+k*.15,.3+k*.28,1.0+k*.65));right=Vector((4.7-k*.25,1.3-k*.38,35.7))
 pts=bezier([left,left+Vector((-.6,1,-25)),bottom-Vector((4.7,0,0)),bottom],48)+bezier([bottom,bottom+Vector((4.7,0,0)),right+Vector((.6,-1,-25)),right],48)[1:];paths.append(pts);tube('大型悬垂弧线电缆',pts,.20+.025*(k%3))
 for q in (7,29,64,84):tube('重缆卡环',pts[q:q+3],.26+.025*(k%3),0,DARK)
finish_cable(paths)
for side in (-1,1):
 for y in (-42,-18):inst('hanging_power_bundle',matrix=Matrix.Translation((side*(11 if y==-42 else 17),y,0))@Matrix.Rotation(math.radians(12*side),4,'Z')@Matrix.Translation(Vector(meta['hanging_power_bundle']['anchor'])))
# Open shells, exposed trays and tilted torn armour, not solid decorative boxes.
for slug,crush in [('damaged_cabinet_open',False),('damaged_cabinet_crushed',True)]:
 begin(slug);box('机箱底壳',(1.1,1.9,.12),(0,0,.06),0,DARK,b=.025)
 for x in (-.53,.53):box('破损侧壁',(.09,1.9,.72),(x,0,.40),0,DARK,b=.02,rot=Matrix.Rotation(.13 if crush and x>0 else 0,3,'Y'))
 box('背部残板',(1.05,.10,.72),(0,.90,.4),1,DARK,b=.02)
 for y in (-.6,-.15,.3):box('暴露硬盘托盘',(.82,.30,.15),(0,y,.19),0,MID,b=.025)
 box('掀起破损顶板',(1.0,1.0,.055),(.26,.39,.82),0,DARK,b=.015,rot=Matrix.Rotation(.55 if crush else .9,3,'Y'))
 for k in range(4):box('断裂散热片',(.7,.028,.10),(0,-.92,.20+k*.14),0,EDGE,b=.005)
 finish()
for slug,x,y,rot,roll in [('damaged_cabinet_open',-8,-3,24,1.35),('damaged_cabinet_crushed',8.2,4,-35,1.7),('damaged_cabinet_open',-7,7,112,1.48),('damaged_cabinet_crushed',6.9,-6,70,1.3),('damaged_cabinet_open',-9,-4.5,-10,.35)]:
 col=masters[slug];mat=Matrix.Rotation(math.radians(rot),4,'Z')@Matrix.Rotation(roll,4,'Y');zmin=min((mat@v.co).z for o in col.objects for v in o.data.vertices);o=inst(slug,matrix=Matrix.Translation((x,y,-zmin+.015))@mat);o['debris']=True
# Closed double-sided envelope. Continuous backing spans 12m; visible armour 11.9m.
begin('enclosure_wall_5m');box('连续密封背板',(5,.6,12),(0,0,6),1,DARK,b=0)
for side in (-1,1):
 box('双面装甲大面',(4.68,.10,11.9),(0,side*.35,5.95),1,DARK,b=.03)
 for x in (-2.36,2.36):box('竖向接缝梁',(.20,.25,12),(x,side*.39,6),0,DARK,b=.018)
 for z in (.2,5.95,11.7):box('分段加强梁',(4.9,.22,.22),(0,side*.40,z),0,MID,b=.018)
finish()
begin('enclosure_slab_5m');box('密封板',(5,5,.40),(0,0,.20),1,DARK,b=0)
for z in (.02,.43):
 for x in (-2.38,2.38):box('装甲板筋',(.18,5,.10),(x,0,z),0,DARK,b=.01)
finish()
begin('enclosure_doorwall_5m');box('门洞上方密封墙',(5,.6,6),(0,0,9),1,DARK,b=0)
for side in (-1,1):
 box('门楣厚甲',(5,.30,.45),(0,side*.4,6.22),0,MID,b=.035)
 for z in (8.5,11.7):box('门墙加强梁',(5,.20,.2),(0,side*.38,z),0,DARK,b=.02)
finish()
shell=[]
for y,rz in [(-72.5,0),(27.5,180)]:
 # odd centers align x=0 door, end half-panels resolved by corner backing overlap.
 for x in range(-40,41,5):
  for z in range(-36,36,12):
   slug='enclosure_doorwall_5m' if y<0 and x==0 and z==12 else 'enclosure_wall_5m';o=inst(slug,(x,y,z+(6 if slug=='enclosure_doorwall_5m' else 0)),rz);shell.append(o.name)
for x,rz in [(-40,90),(40,270)]:
 for y in range(-70,26,5):
  for z in range(-36,36,12):
   slug='enclosure_doorwall_5m' if y==0 and z==0 else 'enclosure_wall_5m';o=inst(slug,(x,y,z+(6 if slug=='enclosure_doorwall_5m' else 0)),rz);shell.append(o.name)
for x in range(-40,41,5):
 for y in range(-70,26,5):
  for z in (-36.40,36):o=inst('enclosure_slab_5m',(x,y,z));shell.append(o.name)
# Additional closed outer doors cap the side vestibules and the unseen entrance.
doors=[((0,-72.5,12),180),((-40,0,0),90),((40,0,0),270)]
for index,(pos,rz) in enumerate(doors):
 mat=Matrix.Translation(pos)@Matrix.Rotation(math.radians(rz),4,'Z');inst('exit_portal',matrix=mat,name=f'外壳门框_{index}')
 for slug,xx in [('exit_leaf_a',-1.245),('exit_leaf_b',1.245)]:inst(slug,matrix=mat@Matrix.Translation((xx,0,0)),name=f'外壳门扇_{index}_{slug}')
# Camera and lighting for unseen-surface inspection, all remain display-only.
for name,pos,target,lens in [('验收_楼梯弧缆',(0,-64,17),(0,-8,3),27),('验收_背面入口',(14,-42,20),(0,-72,16),28),('验收_破损机箱',(-12,-10,7),(-7,-2,0),40)]:
 cd=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,cd);show.objects.link(o);o.location=pos;aim(o,target);cd.lens=lens;cd.clip_end=300
for side in (-1,1):
 ld=bpy.data.lights.new('楼梯缆束侧光','AREA');ld.energy=3500;ld.size=12;ld.color=(.65,.72,.85);o=bpy.data.objects.new('楼梯缆束侧光',ld);show.objects.link(o);o.location=(side*15,-43,20);aim(o,(side*8,-32,12))
ld=bpy.data.lights.new('入口门墙柔光','AREA');ld.energy=2600;ld.size=8;o=bpy.data.objects.new('入口门墙柔光',ld);show.objects.link(o);o.location=(0,-62,20);aim(o,(0,-72,16))
for im in bpy.data.images:
 if im.source=='FILE' and 'screen_' in Path(bpy.path.abspath(im.filepath)).name:im.filepath=str(D/'textures'/Path(bpy.path.abspath(im.filepath)).name)
bpy.context.view_layer.update();changed=[n for n,h in locked.items() if n not in bpy.data.objects or signature(bpy.data.objects[n])!=h];assert not changed,changed
write(W/'scope_lock.json',{'before':locked,'changed':changed,'screen_poses':poses,'authorized_geometry':retired+rebuild+[d[0] for d in defs]})
instances=[]
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 slug=next(s for s,c in masters.items() if c==o.instance_collection);rec=next(r for r in catalog if r['slug']==slug)
 instances.append({'instance_id':o.name,'component_id':rec['component_id'],'slug':slug,'position_m':list(o.location),'rotation_euler_xyz_deg':[math.degrees(v) for v in o.rotation_euler],'matrix_room_local':[list(r) for r in o.matrix_world],'scale':list(o.scale),'draft':False,'user_pose_locked':o.name in poses})
write(D/'component_instances.json',{'schema_version':2,'version':'v025','instances':instances})
# Same independent-package writer used in the accepted v024 pipeline.
text=(ROOT/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8');chunk=text[text.index('for rec in catalog:\n'):text.index("write(D/'component_catalog.json'")];chunk=chunk.replace("version='v024'","version='v025'");exec(compile(chunk,'<package_export>','exec'))
write(D/'component_catalog.json',{'component_count':len(catalog),'components':catalog})
write(D/'stair_light_contract.json',{'schema':'boss.step_lights.v1','asset_id':next(r['component_id'] for r in catalog if r['slug']=='stair_chase_light'),'component_source':str(D/'component_packages/stair_chase_light/stair_chase_light.blend'),'independent_instances':sorted(lamp_records,key=lambda r:r['sequence_index']),'default_game_state':'off','preview_state':'all_on','activation':'Room owner projects player onto stair descent path; activate reached sequence indices in order; per-instance material override, never mutate shared emission material','trigger_collision':'Not authored; wrapper owns trigger and walking ramp','animation_status':'contract only; no Godot gameplay integration'})
write(D/'enclosure_contract.json',{'bounds_m':{'x':[-40,40],'y':[-72.5,27.5],'z':[-36,36]},'shell_instances':shell,'closed_outer_doors':[{'position':p,'rotation_z_deg':r} for p,r in doors],'side_inner_doors':'preserved user scene; outer vestibule door seals enclosure','stairs':{'width':5,'run':50,'rise':12,'step_run':.5,'step_rise':.12,'count':100,'low_end':[0,-12.5,0],'high_end':[0,-62.5,12]},'runtime_collision':'pending'})
manifest=json.loads((D/'room_type_manifest.json').read_text(encoding='utf-8'));manifest.update(version='v025',source_blend=str(B),component_budget=plan['component_budget'],runtime_connected=False);write(D/'room_type_manifest.json',manifest)
(D/'component_tree.txt').write_text('\n'.join(f'{r["slug"]} | {r["name_zh"]} | {r["instance_count"]}' for r in catalog),encoding='utf-8')
scene.name='Boss房B_楼梯弧缆与完整围护_v025';bpy.data.collections['Boss房B_中文资产管理_v024'].name='Boss房B_中文资产管理_v025';scene.camera=bpy.data.objects['参考镜头_全景'];scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B));print('V025_SAVED',len(catalog),len(instances))
