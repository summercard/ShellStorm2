"""Deepen the user's live screen placement without replacing the v022 deck/bridges."""
import bpy,bmesh,math,json,hashlib,sys,ast,shutil
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
WORK=work_path('outputs/boss_detail_v023/session.json').parent
OLD=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v022'
DEST=OLD.parent/'v023';DEST.mkdir(parents=True,exist_ok=True)
BLEND=DEST/'Boss房B_显示器电缆与矩阵深化_v023.blend'
baseline=json.loads((WORK/'live_snapshot.json').read_text(encoding='utf-8'))
if Path(bpy.data.filepath)==BLEND:
 bpy.ops.wm.open_mainfile(filepath=baseline['backup'])
else:
 for s in baseline['screens']:
  o=bpy.data.objects[s['name']]
  assert max(abs(o.matrix_world[i][j]-s['matrix'][i][j]) for i in range(4) for j in range(4))<1e-6,'Screen changed since snapshot; refresh baseline rather than overwrite'
scene=bpy.context.scene;scene.name='Boss房B_显示器与矩阵深化_v023';scene.frame_set(1)
root=bpy.data.collections['Boss房B_中文资产管理_v022'];root.name='Boss房B_中文资产管理_v023'
source=bpy.data.collections['01_制作组件_母版与可编辑零件'];out=bpy.data.collections['02_游戏输出_组件实例布局'];draft=bpy.data.collections['80_草稿_入口巨屏井壁'];show=bpy.data.collections['90_展示与验收_灯光相机']
retired={'draft_screen','draft_tower','draft_portal'}
oldcat=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components']
oldplan=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'))
additions=[('monitor_chassis','大型悬挂显示器机壳','monitor','facilities'),('screen_left','诊断遥测屏幕','screen_content','facilities'),('screen_center','数据核心屏幕','screen_content','facilities'),('screen_right','波形监测屏幕','screen_content','facilities'),('cables_swept','侧翼下垂重缆束','cable_bundle','support'),('cables_mirrored','侧翼反向重缆束','cable_bundle','support'),('cables_crown','中央供电与数据缆束','cable_bundle','support'),('compute_tower_tall','高层计算机塔','compute_tower','architecture'),('compute_tower_stepped','阶梯计算机塔','compute_tower','architecture'),('compute_tower_compact','短层计算机塔','compute_tower','architecture'),('exit_portal','出口装甲门框','portal','architecture'),('exit_leaf_a','装甲门扇A','door_leaf','architecture'),('exit_leaf_b','装甲门扇B','door_leaf','architecture'),('exit_passage','出口内廊','passage','architecture'),('matrix_bay_5m','后方矩阵模块','matrix','architecture'),('matrix_bus_5m','矩阵横向连接桥架','matrix_bus','support')]
plan={**oldplan,'version':'v023','status':'frozen_before_geometry','reference_image':'reference_detail.png','based_on_user_snapshot':str(WORK/'user_adjusted_before.blend'),'components':[d for d in oldplan['components'] if d['slug'] not in retired]}
for s,n,f,cat in additions:plan['components'].append({'slug':s,'component_id':'ENV-EXPEDITION-BOSS-B-'+s.upper().replace('_','-'),'name_zh':n,'component_family':f,'category':cat,'scope':'room_type_local','serves_room_types':['BOSS_ROOM'],'front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270],'variant_axis':'structure_state','variant_value':s,'variant_reason':'Reference silhouette / content or cable routing variation'})
plan['component_budget']={'limit':50,'planned':len(plan['components']),'remaining':50-len(plan['components'])}
plan['texture_exception']={'authorized_by':'user explicitly permits image-2 screen texture','surfaces':['screen_left','screen_center','screen_right'],'uv':'ScreenUV','material_roles':'3 screen emission materials in addition to 4 shared palette roles','animation':'independent screen surface + scan phase / line contrast / signal pulse; no game logic baked'}
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
write(DEST/'component_plan.json',plan)
shutil.copyfile(r'C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-62baada4-00f5-45f6-8f6b-cb9bc7d252c9.png',DEST/'reference_detail.png')
print('PLAN_FROZEN',len(plan['components']),flush=True)

# Reuse the audited geometry helpers, never execute the old room constructor.
DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8);WHITE=(9,0)
tree=ast.parse((ROOT/'scripts/blender/build_boss_room_B_structure_v022.py').read_text(encoding='utf-8'))
needed={'collection','uv','geom_box','part','box','bar','plate','bolt','begin','object_from','finish','aim'}
for node in tree.body:
 if isinstance(node,ast.FunctionDef) and node.name in needed:exec(compile(ast.Module(body=[node],type_ignores=[]),'<audited_v022_helpers>','exec'))
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'];mats=[bpy.data.materials[n] for n in roles]
DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8);WHITE=(9,0)
cache={};parts=[];current=None
masters={c['slug']:bpy.data.collections[c['collection']] for c in oldcat if c['slug'] not in retired}
meta={c['slug']:{'definition':next(d for d in plan['components'] if d['slug']==c['slug']),'bounds_size_m':c['bounds_size_m'],'part_count':c.get('editable_part_count',0),'anchor':[0,0,0]} for c in oldcat if c['slug'] not in retired};edits={}
def sig(o):
 d={'type':o.type,'matrix':[list(r) for r in o.matrix_world],'parent':o.parent.name if o.parent else None,'instance':o.instance_collection.name if o.instance_collection else None}
 if o.type=='MESH':d['geometry']=hashlib.sha256(str(([tuple(v.co) for v in o.data.vertices],[tuple(p.vertices) for p in o.data.polygons],[p.material_index for p in o.data.polygons],[m.name for m in o.data.materials])).encode()).hexdigest()
 if o.type=='LIGHT':d['light']=[o.data.energy,list(o.data.color),o.data.type]
 if o.type=='CAMERA':d['camera']=[o.data.lens,o.data.type,o.data.ortho_scale]
 return hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()
retire_cols=set()
for slug in retired:
 c=bpy.data.collections['组件_'+next(c['name_zh'] for c in oldcat if c['slug']==slug)];retire_cols.add(c);retire_cols.update(c.children_recursive)
mutable_names={o.name for o in bpy.data.objects if any(c in retire_cols for c in o.users_collection)}
mutable_names.update(o.name for o in bpy.context.scene.objects if o.instance_type=='COLLECTION' and o.instance_collection.name in ['输出资产包_'+s for s in retired|{'suspended_server_5m'}])
locked={o.name:sig(o) for o in bpy.data.objects if o.name not in mutable_names}
screen_objects=[bpy.data.objects[s['name']] for s in baseline['screens']]
old_server_instances=[o for o in out.objects if o.instance_type=='COLLECTION' and o.instance_collection==masters['suspended_server_5m']]
old_portals=[o for o in draft.objects if o.instance_type=='COLLECTION' and o.instance_collection.name=='输出资产包_draft_portal']
portal_matrices=[o.matrix_world.copy() for o in old_portals]
old_towers=[o for o in draft.objects if o.instance_type=='COLLECTION' and o.instance_collection.name=='输出资产包_draft_tower']
for o in old_server_instances+old_portals+old_towers:bpy.data.objects.remove(o,do_unlink=True)
write(WORK/'scope_lock_before.json',{'locked':locked,'screen_matrices':baseline['screens'],'mutable':sorted(mutable_names),'snapshot_sha256':hashlib.sha256((WORK/'user_adjusted_before.blend').read_bytes()).hexdigest()})

def tube(name,pts,r=.12,role=0,cell=BLACK,sides=10):
 vs=[];fs=[]
 for i,p in enumerate(pts):
  p=Vector(p);t=Vector(pts[min(i+1,len(pts)-1)])-Vector(pts[max(i-1,0)]);t.normalize();a=t.cross(Vector((0,1,0)))
  if a.length<.1:a=t.cross(Vector((1,0,0)))
  a.normalize();b=t.cross(a).normalized()
  for k in range(sides):vs.append(tuple(p+r*(a*math.cos(k*math.tau/sides)+b*math.sin(k*math.tau/sides))))
 for i in range(len(pts)-1):
  for k in range(sides):fs.append((i*sides+k,i*sides+(k+1)%sides,(i+1)*sides+(k+1)%sides,(i+1)*sides+k))
 fs.extend([tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+k for k in range(sides))]);part(name,vs,fs,role=role,cell=cell)
def curved(name,controls,r=.12,role=0,cell=BLACK):
 pts=[];controls=[Vector(p) for p in controls]
 for i in range(len(controls)-1):
  a=controls[max(0,i-1)];b=controls[i];c=controls[i+1];d=controls[min(i+2,len(controls)-1)]
  for j in range(12):
   t=j/12;pts.append(tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)))
 pts.append(tuple(controls[-1]));tube(name,pts,r,role,cell)
def cylinder(name,r,h,loc,role=0,cell=MID,n=24,axis='Z'):
 vs=[(r*math.cos(k*math.tau/n),r*math.sin(k*math.tau/n),z) for z in (-h/2,h/2) for k in range(n)];fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(k,(k+1)%n,(k+1)%n+n,k+n) for k in range(n)]
 rot=Matrix.Rotation(math.pi/2,3,'X') if axis=='Y' else None;part(name,vs,fs,loc,role,cell,rot)

begin('monitor_chassis')
plate('后部装甲壳',11, .68,7,.12,(0,.12,3.5),0,DARK)
# Thick layered bezel with a recessed, separately replaceable display plane.
for x in (-5.35,5.35):
 box('侧面主边框',(.30,.60,7),(x,-.19,3.5),0,EDGE,b=.045)
 box('侧面内压框',(.08,.09,6.46),(x-math.copysign(.18,x),-.535,3.5),0,MID,b=.012)
for z in (.14,6.86):
 box('上下主边框',(11,.62,.28),(0,-.20,z),0,EDGE,b=.04)
 box('上下屏幕压条',(10.42,.09,.065),(0,-.54,z+(.15 if z<1 else -.15)),0,MID,b=.009)
for x in (-4.95,4.95):
 for z in (.16,6.84):bolt(x,-.522,z,.064,'Y')
for x in (-4.9,-4.2,-3.5,3.5,4.2,4.9):
 box('背壳加劲肋',(.18,.22,5.8),(x,.58,3.5),0,MID,b=.025)
for x in (-2.6,2.6):
 box('可拆背部检修模块',(3.8,.20,4.6),(x,.62,3.5),1,DARK,b=.065)
 for k in range(19):box('背部排热百叶',(3.35,.045,.07),(x,.75,1.48+k*.22),0,EDGE,b=.01)
for x in (-4.4,-1.5,1.5,4.4):
 box('电缆接线盒',(.62,.42,.55),(x,.63,.73),0,MID,b=.065)
 for dx in (-.17,.17):cylinder('线束防水接头',.105,.27,(x+dx,.96,.73),0,EDGE,16,'Y')
for x in (-3.5,3.5):
 box('悬挂机械背板',(.76,.33,1.35),(x,.65,5.82),0,EDGE,b=.055)
 cylinder('可转位铰轴',.32,.25,(x,.92,5.85),0,DARK,24,'Y')
 box('上沿挂耳',(.50,.58,.24),(x,.12,6.85),0,MID,b=.04)
for x in (-4.75,-4.52,-4.29):box('底框状态灯',(.085,.028,.043),(x,-.525,.145),3,RED,b=.006)
box('底框铭牌',(.9,.018,.09),(4.52,-.52,.14),0,STEEL,b=.006)
finish()

# Smooth hanging bundles. Route geometry is local to each screen, not a room baked mesh.
for slug,hand in [('cables_swept',-1),('cables_mirrored',1),('cables_crown',0)]:
 begin(slug)
 for side in (-1,1):
  for k in range(5 if hand else 3):
   x=side*(3.85+k*.22);sweep=side*(6.4+k*.34)+(hand*.5)
   controls=[(x,.72,.73),(x+side*.8,1.10,-.2),(sweep,1.8,-2.7-k*.20),(sweep+side*.8,2.0,3.8),(sweep+side*.3,1.3,13+k*.6),(side*(4.5+k*.40),2.0,23+k*.45)]
   curved('下垂重型电缆',controls,.09+(k%3)*.035,1,BLACK)
   if k%2==0:curved('伴随红色通信细缆',[(a+side*.16,b-.12,c+.04) for a,b,c in controls],.022,3,RED)
  for k in range(3):
   controls=[(side*(3.55+k*.30),.82,5.85),(side*(4.6+k*.25),1.8,8),(side*(5.3+k*.4),2.8,15),(side*(3.5+k*.4),3.5,25)]
   curved('顶部供电弧缆',controls,.115,1,BLACK)
  for z in (15,20,24):box('高位线束夹箍',(.85,.32,.24),(side*5.2,2.5,z),0,EDGE,b=.035)
 finish()

def tower(slug,w,d,h):
 begin(slug)
 plate('塔身主机箱',w,d,h,.24,(0,0,h/2),1,DARK)
 for x in (-w*.43,w*.43):
  box('错层外侧脊柱',(.28,d+.32,h*.96),(x,-.04,h*.50),0,EDGE,b=.045)
  box('竖向光槽衬底',(.18,.12,h*.82),(x,-d/2-.22,h*.48),1,BLACK,b=.02)
  box('嵌入式红色竖灯',(.075,.032,h*.79),(x,-d/2-.30,h*.48),3,RED,b=.008)
 for j,x in enumerate((-w*.22,w*.18)):
  z0=.55+j*.42;box('偏置机架槽',(w*.37,.16,h-1.4),(x,-d/2-.08,h/2),1,BLACK,b=.04)
  for k in range(int((h-1.6)/.65)):
   z=z0+k*.65
   box('模块插箱',(w*.34,.18,.48),(x,-d/2-.22,z),0,MID,b=.03)
   box('抽拔把手',(w*.18,.075,.05),(x,-d/2-.34,z+.12),0,EDGE,b=.008)
   for dx in (-.30,-.16):box('双列状态指示',(.055,.025,.066),(x+dx,-d/2-.325,z-.10),3,RED,b=.005)
   if k%3==1:
    for q in range(6):box('槽形散热网',(.035,.026,.22),(x+.08+q*.09,-d/2-.33,z-.02),1,BLACK,b=.003)
 for sign in (-1,1):
  for z in (h*.24,h*.62):
   box('侧置维修机箱',(.46,d*.72,h*.15),(sign*(w/2+.12),.16,z),0,MID,b=.06)
   for k in range(7):box('侧面散热隔片',(.07,d*.55,.08),(sign*(w/2+.38),.13,z-h*.05+k*.19),0,EDGE,b=.007)
  curved('外露侧边液冷管',[(sign*w*.49,.35,.7),(sign*(w*.5+.45),.5,1.2),(sign*(w*.5+.45),.5,h*.72),(sign*w*.49,.35,h*.79)],.09,0,MID)
 for z in (.28,h*.35,h*.76,h-.22):
  plate('分段承重装甲环',w+.36,d+.36,.38,.17,(0,0,z),0,MID)
  for x in (-w*.30,w*.30):box('偏置锁扣',(.40,.20,.52),(x,-d/2-.31,z),0,EDGE,b=.045);bolt(x,-d/2-.43,z,axis='Y')
 plate('顶端阶梯护盖',w+.12,d+.12,.18,.22,(0,0,h+.08),0,EDGE)
 for x in (-w*.21,w*.21):
  cylinder('顶部风机外壳',min(w,d)*.25,.09,(x,0,h+.20),0,DARK)
  for k in range(12):
   ang=k*math.tau/12;bar('风机径向格条',(x+.08*math.cos(ang),.08*math.sin(ang),h+.25),(x+min(w,d)*.23*math.cos(ang),min(w,d)*.23*math.sin(ang),h+.25),.035,.025,0,EDGE)
 for x in (-w*.42,w*.42):
  box('顶端提吊耳',(.25,.5,.42),(x,0,h+.29),0,MID,b=.045)
 finish()
tower('compute_tower_tall',4.0,3.6,20)
tower('compute_tower_stepped',4.7,4.2,15.5)
tower('compute_tower_compact',3.2,3.3,11.5)

begin('matrix_bay_5m')
box('矩阵承力背板',(5,1.3,11.9),(0,0,5.95),1,DARK,b=.04)
for x in (-2.29,2.29):box('矩阵竖梁',(.31,1.75,11.9),(x,-.12,5.95),0,EDGE,b=.03)
for x,h in ((-1.35,8.8),(0,10.5),(1.35,9.6)):
 box('错深计算单元',(1.05,.45,h),(x,-.78,h/2+.6),0,MID,b=.05)
 for k in range(int(h/.43)):
  z=.8+k*.43;box('存储阵列槽',(.81,.07,.30),(x,-1.035,z),1,DARK,b=.018)
  for dx in (-.27,-.13):box('矩阵状态像素',(.035,.02,.07),(x+dx,-1.082,z-.06),3,RED,b=.003)
  box('检修抓手',(.36,.06,.03),(x,-1.10,z+.065),0,EDGE,b=.005)
 for z in (1.2,4.4,7.6):box('单元装甲卡扣',(1.10,.14,.16),(x,-1.07,z),0,EDGE,b=.018)
for z in (.22,5.9,11.66):box('矩阵横向联接梁',(5,1.65,.38),(0,-.10,z),0,MID,b=.03)
for x in (-2.28,2.28):box('矩阵竖线光槽',(.045,.026,9.7),(x,-1.01,5.9),3,RED,b=.006)
finish()
begin('matrix_bus_5m')
for z in (.12,.58):box('横向桥架',(5,.7,.20),(0,0,z),0,DARK,b=.025)
for x in (-2.2,-1.1,0,1.1,2.2):box('桥架横肋',(.14,.8,.58),(x,0,.34),0,EDGE,b=.018)
for y in (-.2,0,.2):tube('桥架内通信管',[(-2.5,y,.37),(2.5,y,.37)],.055,0,MID)
finish()

begin('exit_portal')
for s in (-1,1):
 x=s*3.24
 box('装甲主门垛',(1.46,1.5,6.65),(x,0,3.325),0,DARK,b=.12)
 box('内侧门轨',(.20,1.8,5.85),(s*2.60,-.08,2.925),0,EDGE,b=.03)
 box('门垛分层面板',(.9,.20,5.5),(x,-.89,3.35),1,MID,b=.075)
 for z in (.65,2.3,4.4,6.10):box('门柱加固抱箍',(1.7,1.8,.28),(x,-.03,z),0,EDGE,b=.05)
 for z in (1.5,3.5,5.5):
  box('门柱检修槽',(.43,.045,.95),(x,-1.02,z),1,BLACK,b=.025)
  for k in range(5):box('门柱格栅',(.35,.027,.055),(x,-1.05,z-.32+k*.16),0,EDGE,b=.005)
 for z in (1.0,6.2):box('门状态红灯',(.12,.04,.22),(s*2.75,-1.02,z),3,RED,b=.012)
box('上部门机横梁',(8.3,1.9,1.15),(0,0,6.8),0,MID,b=.09)
box('门机内凹面板',(6.8,.18,.6),(0,-1.04,6.84),1,DARK,b=.04)
for x in (-3.5,-2.5,0,2.5,3.5):box('门机外侧锁扣',(.28,.3,1.3),(x,-.20,6.85),0,EDGE,b=.035)
box('门楣照明槽',(2.0,.3,.16),(0,-.96,5.97),0,BLACK,b=.015)
box('门楣白色照明',(1.65,.19,.07),(0,-1.035,5.93),3,WHITE,b=.01)
# Downward luminous arrow, geometry rather than a texture decal.
part('门楣三角标',[(-.26,-1.16,6.52),(.26,-1.16,6.52),(0,-1.16,6.19)],[(0,1,2)],role=3,cell=WHITE)
for x in (-3,-2,-1,1,2,3):bolt(x,-1.15,6.87,.085,'Y')
finish()
for slug,s in [('exit_leaf_a',-1),('exit_leaf_b',1)]:
 begin(slug)
 plate('分体门扇装甲',2.48,.34,5.72,.14,(0,0,2.86),0,DARK)
 box('门扇嵌入装甲',(2.16,.15,5.35),(0,-.22,2.86),1,MID,b=.08)
 for z in (.48,5.2):box('门扇横框',(2.05,.14,.16),(0,-.34,z),0,EDGE,b=.03)
 for x in (-.97,.97):box('门扇竖框',(.12,.15,4.6),(x,-.34,2.86),0,EDGE,b=.025)
 for z in (1,4.7):bar('斜向锁定装甲',(-s*.77,-.38,z),(s*.85,-.38,2.86),.16,.11,0,EDGE)
 box('中央机械锁盒',(.4,.21,.65),(s*.85,-.41,2.86),0,DARK,b=.05)
 for z in (2.68,3.02):bolt(s*.85,-.535,z,.075,'Y')
 box('门缝红指示',(.035,.026,.4),(s*1.20,-.39,2.85),3,RED,b=.003)
 finish()
begin('exit_passage')
box('出口内廊地坪',(5,6,.28),(0,0,.14),0,MID,b=.02)
for x in (-2.70,2.70):box('内廊侧墙',(.40,6,6),(x,0,3),1,DARK,b=.02)
box('内廊顶板',(5.8,6,.32),(0,0,5.84),0,DARK,b=.02)
for y in (-2.5,-1.25,0,1.25,2.5):
 for x in (-2.42,2.42):box('廊内竖向白光',(.045,.14,4.8),(x,y,2.8),3,WHITE,b=.009)
 box('廊内结构肋',(5.0,.16,.18),(0,y,5.48),0,EDGE,b=.02)
finish()

newinstances=[]
def inst(slug,loc=None,rz=0,matrix=None,name=None):
 o=bpy.data.objects.new(name or meta[slug]['definition']['name_zh']+f'_{len(newinstances):03}',None);out.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=masters[slug];o.empty_display_size=.2
 if matrix is not None:o.matrix_world=matrix
 else:o.location=loc;o.rotation_euler.z=math.radians(rz)
 o['component_id']=meta[slug]['definition']['component_id'];newinstances.append(o);return o
# Existing screen anchor objects are preserved exactly, including all three rotation axes.
for i,o in enumerate(screen_objects):
 for c in list(o.users_collection):c.objects.unlink(o)
 out.objects.link(o);o.instance_collection=masters['monitor_chassis'];o['component_id']=meta['monitor_chassis']['definition']['component_id'];o['user_pose_locked']=True
 slug=['cables_swept','cables_crown','cables_mirrored'][i]
 inst(slug,matrix=o.matrix_world@Matrix.Translation(Vector(meta[slug]['anchor'])))
# Under the deck: receding layer plus staggered forward machines, varied top and bottom lines.
for x in (-7.5,-2.5,2.5,7.5):inst('suspended_server_5m',(x,9.8,-19.5),180)
for s in (-1,1):
 for y in (-7.5,2.5,7.5):inst('suspended_server_5m',(s*8.4,y,-19),s*90)
 inst('compute_tower_tall',(s*4.1,-10.6,-22.05))
 inst('compute_tower_stepped',(s*9.1,-9.8,-17.6))
 inst('compute_tower_compact',(s*7.0,-11.4,-15.2))
 for y,z,slug in ((-5.4,-22.4,'compute_tower_tall'),(3.2,-18.9,'compute_tower_stepped'),(8.8,-23.2,'compute_tower_tall')):inst(slug,(s*10.55,y,z),90 if s>0 else -90)
 # Layered towers in each shaft: near/mid/deep tiers, no duplicated world-specific masters.
 for x,y,z,slug,rz in [(19,-14,-25,'compute_tower_tall',-12),(26,-7,-28,'compute_tower_stepped',8),(21,10,-25,'compute_tower_tall',-8),(29,-24,-23,'compute_tower_tall',5),(18,-32,-25,'compute_tower_compact',-7),(30,10,-22,'compute_tower_stepped',0),(25,20,-28,'compute_tower_tall',8),(31,-39,-23,'compute_tower_tall',-4),(24,-21,-29,'compute_tower_compact',9)]:inst(slug,(s*x,y,z),s*rz)
# Rear computer matrix: staggered depth and riser joints, centered behind user-positioned screens.
for row,z in enumerate((-18,-6.1,5.8,17.7)):
 for k,x in enumerate(range(-30,31,5)):
  y=17.1+(.0,.55,1.05)[(k+row)%3];inst('matrix_bay_5m',(x,y,z))
  if row in (1,3):inst('matrix_bus_5m',(x,y-1.0,z+.55))
for s in (-1,1):
 for y in (-30,-20,-10,10):
  for z in (-18,-6.1,5.8,17.7):inst('matrix_bay_5m',(s*33.5,y,z),90 if s>0 else -90)
for pm in portal_matrices:
 inst('exit_portal',matrix=pm)
 side='left' if pm.translation.x<0 else 'right';spread=1.245 if side=='left' else 3.72
 for slug,s in [('exit_leaf_a',-1),('exit_leaf_b',1)]:
  leaf=inst(slug,matrix=pm@Matrix.Translation(Vector((s*spread,-.03,.02))));leaf['door_role']='sliding_leaf';leaf['animation_axis_local']='+X' if s>0 else '-X';leaf['closed_x_m']=s*1.245;leaf['open_x_m']=s*3.72
 inst('exit_passage',matrix=pm@Matrix.Translation(Vector((0,3.25,-.28))))
 if side=='right':
  ld=bpy.data.lights.new('出口内廊展示灯','AREA');ld.energy=900;ld.color=(1,.82,.66);ld.size=3.5;lo=bpy.data.objects.new('出口内廊展示灯',ld);show.objects.link(lo);lo.location=pm@Vector((0,2,4.7));aim(lo,pm@Vector((0,-2,1)))

# Retired draft masters only; all deck, bridge, stair and camera objects remain unchanged.
for c in list(retire_cols):
 for o in list(c.objects):
  if o not in screen_objects:bpy.data.objects.remove(o,do_unlink=True)
for c in list(retire_cols):
 if c.name in bpy.data.collections:bpy.data.collections.remove(c)
bpy.context.view_layer.update()
changes=[n for n,h in locked.items() if n not in bpy.data.objects or sig(bpy.data.objects[n])!=h]
assert not changes,'LOCKED CONTENT CHANGED '+str(changes[:10])
screen_errors=[max(abs(o.matrix_world[i][j]-s['matrix'][i][j]) for i in range(4) for j in range(4)) for o,s in zip(screen_objects,baseline['screens'])]
assert max(screen_errors)<1e-6
write(WORK/'scope_lock_geometry.json',{'locked_match':not changes,'locked_count':len(locked),'unexpected_changes':changes,'screen_max_matrix_errors':screen_errors,'before':locked,'after':{n:sig(bpy.data.objects[n]) for n in locked}})
# Texture application and final catalog are a separate repeatable finishing step.
write(WORK/'geometry_state.json',{'meta':meta,'master_names':{s:c.name for s,c in masters.items()},'screen_objects':[o.name for o in screen_objects],'locked':locked})
bpy.context.view_layer.layer_collection.children[root.name].children[source.name].exclude=True
scene.frame_start=1;scene.frame_end=240;scene.render.fps=24
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print('V023_GEOMETRY_SAVED',str(BLEND),len(newinstances),'new instances',flush=True)
