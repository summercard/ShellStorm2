"""Boss room B: reference-led 25m deck and two 5x20m bridges, Blender source only.
Run in Blender 4.5. Component plan is frozen before creation of any geometry.
"""
import bpy, bmesh, math, json, hashlib, sys, shutil
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2')
sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
WORK=work_path('outputs/boss_structure_v022/session.json').parent
DEST=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v022'
BLEND=DEST/'Boss房B_平台与双桥结构_v022.blend'
REF=Path(r'C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-4bd9b72f-ca50-41de-acd5-e0fefcfcc1a3.png')
PALETTE=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
WHITEBOX=ROOT/'art_source/design/whitebox/tower_zones/expedition_01/boss_deep_chamber/layout_contract.json'
DEST.mkdir(parents=True,exist_ok=True)
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
defs=[
 ('deck_armor_5m','精加工甲板','deck', 'floor',24),
 ('deck_emblem_5m','中心菱形徽记甲板','deck','floor',1),
 ('rim_girder_5m','分层装甲边梁','rim','architecture',20),
 ('suspended_server_5m','下挂机柜承力塔','server_tower','architecture',20),
 ('corner_pylon','转角竖向承力灯柱','pylon','architecture',4),
 ('underframe_beam_5m','平台底部承重梁','underframe','architecture',100),
 ('deck_barrier_5m','平台低护栏灯柱','barrier','architecture',17),
 ('bridge_deck_5m','桥面格栅节段','bridge_deck','architecture',8),
 ('bridge_truss_5m','桥侧箱梁桁架','bridge_truss','architecture',16),
 ('bridge_rail_5m','桥缘低位灯柱护栏','bridge_rail','architecture',16),
 ('abutment_bracket','桥接头斜撑牛腿','bracket','architecture',4),
 ('equipment_cluster','平台阶梯设备组','equipment','facilities',4),
 ('draft_stair_5m','草稿入口长梯节段','draft_stair','draft',10),
 ('draft_screen','草稿巨屏','draft_screen','draft',3),
 ('draft_wall_5m','草稿井壁','draft_wall','draft',24),
 ('draft_tower','草稿远景塔','draft_tower','draft',16),
 ('draft_portal','草稿桥端门框','draft_portal','draft',2),
]
plan={'schema':'shellstorm2.room_component_plan','version':'v022','room_type':'BOSS_ROOM','block_id':'expedition','level_id':'expedition_01','status':'frozen_before_geometry','design_scope':'scene_art','reference_sha256':hashlib.sha256(REF.read_bytes()).hexdigest(),'whitebox_source':str(WHITEBOX),'whitebox_sha256':hashlib.sha256(WHITEBOX.read_bytes()).hexdigest(),'user_overrides':{'bridge_length_m':20,'bridge_width_m':5,'platform_m':[25,25],'other_geometry':'draft only'},'component_budget':{'limit':50,'planned':len(defs),'remaining':50-len(defs)},'components':[{'slug':s,'component_id':'ENV-EXPEDITION-BOSS-B-'+s.upper().replace('_','-'),'name_zh':n,'component_family':f,'category':cat,'estimated_instances':count,'scope':'room_type_local','serves_room_types':['BOSS_ROOM'],'front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270],'variant_axis':'structure_state' if f=='deck' else None,'variant_value':s if f=='deck' else None,'variant_reason':'Central emblem panel versus repeat armor plate' if f=='deck' else None} for s,n,f,cat,count in defs]}
write(DEST/'component_plan.json',plan)
write(DEST/'scope_contract.json',{'source':'New reference reconstruction; all previous blend files read-only','authorized':['25x25m platform deck','platform substructure','two 5x20m bridges','attached barriers and equipment'],'draft_only':['screens','shaft walls','distant towers','entrance stair','bridge end portals'],'locked_existing_files':[str(p) for p in DEST.parent.glob('v*/**/*.blend') if p.parent!=DEST],'room_frame':'Platform plan center at walk plane; XY plane, Z up','walk_plane_z_m':0,'platform_xy':[[-12.5,-12.5],[12.5,12.5]],'bridge_bounds':[[-32.5,-12.5,-2.5,2.5],[12.5,32.5,-2.5,2.5]],'inferred_understructure_depth_m':18,'inference_reason':'Reference-visible shaft depth is not metrically specified; preserve tall vertical server silhouette','prior_whitebox_bridge_length_m':15,'accepted_user_bridge_length_m':20,'runtime_changed':False})
shutil.copyfile(REF,DEST/'reference.png')
print('PLAN_FROZEN',len(defs),flush=True)

# Keep the initial Blender session as a separate safety snapshot.
if not (WORK/'before_session.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'before_session.blend'),copy=True)
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
for c in list(bpy.data.collections):bpy.data.collections.remove(c)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)
scene=bpy.context.scene;scene.name='Boss房B_平台双桥_制作验收'
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
def collection(name,parent=None):
 c=bpy.data.collections.new(name);(parent or scene.collection).children.link(c);return c
root=collection('Boss房B_中文资产管理_v022')
source=collection('01_制作组件_母版与可编辑零件',root)
out=collection('02_游戏输出_组件实例布局',root)
draft=collection('80_草稿_入口巨屏井壁',root)
show=collection('90_展示与验收_灯光相机',root)
img=bpy.data.images.load(str(PALETTE),check_existing=True)
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for i,n in enumerate(roles):
 m=bpy.data.materials.new(n);m.use_nodes=True;nodes=m.node_tree.nodes;links=m.node_tree.links;p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
 p.inputs['Metallic'].default_value=[.86,.03,.18,0][i];p.inputs['Roughness'].default_value=[.29,.69,.16,.38][i];p.inputs['Coat Weight'].default_value=[.15,0,.65,0][i]
 t=nodes.new('ShaderNodeTexImage');t.image=img;t.interpolation='Closest';u=nodes.new('ShaderNodeUVMap');u.uv_map='PaletteUV';links.new(u.outputs['UV'],t.inputs['Vector']);links.new(t.outputs['Color'],p.inputs['Base Color'])
 if i==3:links.new(t.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=1.6
 mats.append(m)
# Cold gunmetal, subtle red-brown panels, saturated red lenses from the shared palette.
DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8);WARM=(2,8)
cache={};masters={};edits={};meta={};parts=[];current=None
def uv(me,cells):
 u=me.uv_layers.new(name='PaletteUV');u.active_render=True;me.uv_layers.active=u
 for p,cell in zip(me.polygons,cells):
  for k,li in enumerate(p.loop_indices):
   a=math.tau*k/len(p.loop_indices);u.data[li].uv=((cell[0]+.5+.27*math.cos(a))/10,(cell[1]+.5+.27*math.sin(a))/10)
def geom_box(size,bevel):
 key=tuple(size)+(bevel,)
 if key in cache:return cache[key]
 bm=bmesh.new();bmesh.ops.create_cube(bm,size=1)
 for v in bm.verts:v.co.x*=size[0];v.co.y*=size[1];v.co.z*=size[2]
 if bevel:bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(size)*.24),segments=2,affect='EDGES',profile=.5)
 bm.normal_update();bm.verts.ensure_lookup_table();bm.verts.index_update()
 vs=[tuple(v.co) for v in bm.verts];fs=[tuple(v.index for v in f.verts) for f in bm.faces];bm.free();cache[key]=(vs,fs);return vs,fs
def part(name,vs,fs,loc=(0,0,0),role=0,cell=MID,rot=None):
 mat=Matrix.Translation(Vector(loc))@(rot.to_4x4() if rot is not None else Matrix.Identity(4));vs=[tuple(mat@Vector(v)) for v in vs]
 parts.append((name,vs,fs,role,cell));return len(parts)-1
def box(name,size,loc=(0,0,0),role=0,cell=MID,b=.025,rot=None):
 vs,fs=geom_box(size,b);return part(name,vs,fs,loc,role,cell,rot)
def bar(name,a,b,w=.08,d=None,role=0,cell=MID):
 a,b=Vector(a),Vector(b);return box(name,(w,d or w,(b-a).length),(a+b)/2,role,cell,min(w*.14,.025),(b-a).to_track_quat('Z','Y').to_matrix())
def plate(name,w,d,h,cut,loc,role=1,cell=MID):
 xy=[(-w/2+cut,-d/2),(w/2-cut,-d/2),(w/2,-d/2+cut),(w/2,d/2-cut),(w/2-cut,d/2),(-w/2+cut,d/2),(-w/2,d/2-cut),(-w/2,-d/2+cut)]
 vs=[(x,y,z) for z in (-h/2,h/2) for x,y in xy];fs=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
 return part(name,vs,fs,loc,role,cell)
def bolt(x,y,z,r=.055,axis='Z'):
 n=6;vs=[(r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),h) for h in (-.012,.012) for i in range(n)];fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 rot=Matrix.Rotation(math.pi/2,3,'X') if axis=='Y' else None
 part('六角沉头螺栓',vs,fs,(x,y,z),0,STEEL,rot)
def begin(slug):
 global current,parts
 current=slug;parts=[]
def object_from(name,vs,fs,roles_p,cells,coll):
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update();uv(me,cells)
 unique=sorted(set(roles_p))
 for i in unique:me.materials.append(mats[i])
 for p,r in zip(me.polygons,roles_p):p.material_index=unique.index(r)
 o=bpy.data.objects.new(name,me);coll.objects.link(o);return o
def finish():
 info=next(d for d in plan['components'] if d['slug']==current);parent=collection('组件_'+info['name_zh'],source);edit=collection('制作零件_'+current,parent);final=collection('输出资产包_'+current,parent)
 vsall=[v for _,vs,_,_,_ in parts for v in vs];lo=Vector([min(v[i] for v in vsall) for i in range(3)]);hi=Vector([max(v[i] for v in vsall) for i in range(3)]);anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 merged={False:([],[],[],[]),True:([],[],[],[])}
 for index,(name,vs,fs,r,cell) in enumerate(parts):
  vs=[tuple(Vector(v)-anchor) for v in vs]
  obj=object_from(('自发光_' if r==3 else '')+info['name_zh']+'_'+name+f'_{index:03}',vs,fs,[r]*len(fs),[cell]*len(fs),edit)
  obj['semantic_part']=name
  mv,mf,mr,mc=merged[r==3];start=len(mv);mv.extend(vs);mf.extend([tuple(k+start for k in f) for f in fs]);mr.extend([r]*len(fs));mc.extend([cell]*len(fs))
 for emission,(vs,fs,rr,cc) in merged.items():
  if fs:object_from(info['name_zh']+('_自发光' if emission else '_主体'),vs,fs,rr,cc,final)
 final['component_id']=info['component_id'];final['front_axis']='-Y';final['local_origin']='bbox center XY / bottom Z';masters[current]=final;edits[current]=edit;meta[current]={'anchor':list(anchor),'bounds_size_m':list(hi-lo),'definition':info,'part_count':len(parts)}
 print('COMPONENT_BUILT',current,len(parts),flush=True)

def deck(emblem=False):
 box('承力底板',(5,5,.32),(0,0,.16),0,DARK,.04)
 for x in (-1.235,1.235):
  for y in (-1.235,1.235):
   plate('切角装甲板',2.43,2.43,.10,.16,(x,y,.37),1,MID)
   for a in (-1.04,1.04):
    for b in (-1.04,1.04):bolt(x+a,y+b,.421)
 if not emblem:
  for y in (-2.16,2.16):
   box('嵌入检修槽',(1.3,.34,.014),(0,y,.427),1,BLACK,b=.008)
   for i in range(13):box('检修格栅',(.034,.26,.019),(-.6+i*.1,y,.44),0,EDGE,b=.005)
  plate('六边检修盖',.65,.45,.015,.08,(.64,-.66,.43),0,DARK)
  for x in (-2.25,2.25):
   box('导轨边条',(.055,1.5,.012),(x,0,.428),0,EDGE,b=.002)
   for y in (-.7,.7):box('方向标记',(.15,.035,.016),(x,y,.433),0,STEEL,b=.002)
 else:
  for r in (2.22,1.92,1.02,.65):
   pts=[(0,-r,.436),(r,0,.436),(0,r,.436),(-r,0,.436)]
   for a,b in zip(pts,pts[1:]+pts[:1]):bar('中心菱形蚀刻',a,b,.055,.02,0,BLACK)
  for s in (-1,1):
   bar('徽记折翼',(s*.30,-.58,.44),(s*1.36,.5,.44),.12,.018,0,DARK)
   bar('徽记折翼',(s*1.36,.5,.44),(s*.72,.5,.44),.12,.018,0,DARK)
begin('deck_armor_5m');deck();finish()
begin('deck_emblem_5m');deck(True);finish()

begin('rim_girder_5m')
box('承重箱梁',(5,1.05,1.9),(0,0,.95),0,DARK,b=.075)
for z,d,h in ((.15,1.24,.24),(1.48,1.2,.24),(1.86,1.28,.18)):box('层叠翼缘',(5,d,h),(0,0,z),0,EDGE,b=.035)
for x in (-1.25,1.25):
 box('外侧机械凹槽',(2.16,.05,.78),(x,-.55,.85),1,BLACK,b=.025)
 box('内嵌支撑板',(1.94,.09,.48),(x,-.60,.86),0,MID,b=.035)
 for xx in (x-.77,x+.77):box('外挂卡扣',(.16,.2,.82),(xx,-.66,.94),0,EDGE,b=.025);bolt(xx,-.775,1.1,axis='Y')
 for xx in (x-.5,x,x+.5):box('梁侧短槽',(.18,.022,.07),(xx,-.656,.79),1,BLACK,b=.008)
for x in (-2.36,0,2.36):box('竖肋',(.22,1.35,1.7),(x,0,.99),0,MID,b=.04)
finish()

begin('suspended_server_5m')
box('塔体承重背板',(5,1.65,15.8),(0,0,7.9),1,DARK,b=.1)
for x in (-2.24,-.75,.75,2.24):
 box('垂直承力槽钢',(.26,.38,15.8),(x,-.94,7.9),0,EDGE,b=.04)
 box('槽钢阴影线',(.065,.045,14.5),(x,-1.151,7.85),1,BLACK,b=.005)
for x in (-1.5,0,1.5):
 box('服务器纵向内腔',(1.15,.16,14.7),(x,-.92,7.8),1,BLACK,b=.045)
 for k in range(24):
  z=.85+k*.57
  box('机架插槽面板',(1.08,.18,.47),(x,-1.04,z),0,MID,b=.021)
  box('面板嵌条',(.73,.033,.15),(x,-1.148,z+.025),1,DARK,b=.009)
  box('抽拔把手',(.46,.085,.045),(x,-1.195,z+.13),0,EDGE,b=.009)
  for dx in (-.42,-.31):box('服务器红色状态灯',(.042,.025,.055),(x+dx,-1.149,z-.10),3,RED,b=.006)
  if k%3==0:
   for dx in (.18,.29,.4):box('散热短槽',(.035,.025,.18),(x+dx,-1.15,z-.02),1,BLACK,b=.002)
for z in (.28,7.9,15.5):
 box('塔身分段环梁',(5,2.05,.38),(0,-.08,z),0,DARK,b=.04)
 for x in (-1.7,0,1.7):box('外扣',(.54,.18,.54),(x,-1.15,z),0,MID,b=.035)
for x in (-2.25,2.25):
 box('竖灯黑色灯槽',(.18,.10,12.7),(x,-1.19,7.9),0,BLACK,b=.02)
 box('分段竖向红灯',(.052,.027,12.25),(x,-1.257,7.9),3,RED,b=.006)
finish()

begin('corner_pylon')
box('主柱芯',(1.1,1.1,18),(0,0,9),0,DARK,b=.1)
for z in (.5,4.7,10.1,16.8):plate('机械抱箍',1.5,1.5,.65,.18,(0,0,z),0,EDGE)
for z in (4.3,12.3):
 for sign in (-1,1):
  box('柱灯凹槽',(.31,.06,6.5),(0,sign*.58,z),1,BLACK,b=.025)
  box('柱灯红色透光片',(.13,.03,6.16),(0,sign*.63,z),3,RED,b=.018)
  box('柱侧红色透光片',(.03,.13,6.16),(sign*.63,0,z),3,RED,b=.018)
plate('柱顶端盖',1.55,1.55,.26,.16,(0,0,17.87),0,MID)
finish()

begin('underframe_beam_5m')
box('横梁腹板',(5,.38,.86),(0,0,.57),0,DARK,b=.025)
for z in (.12,1.02):box('工字梁翼板',(5,.72,.22),(0,0,z),0,MID,b=.025)
for x in (-2.3,-1.15,0,1.15,2.3):box('横梁加劲肋',(.12,.66,.83),(x,0,.57),0,EDGE,b=.012)
finish()

begin('deck_barrier_5m')
box('栏杆踢脚梁',(5,.38,.20),(0,0,.1),0,DARK,b=.025)
for x in (-2.27,0,2.27):
 plate('短柱底座',.42,.52,.20,.07,(x,0,.27),0,EDGE)
 box('短柱',(.30,.37,.75),(x,0,.66),0,DARK,b=.05)
 plate('短柱帽',.44,.49,.12,.065,(x,0,1.06),0,MID)
 box('灯柱红色窗',(.08,.028,.4),(x,-.20,.71),3,RED,b=.01)
box('低位护栏横梁',(5,.16,.13),(0,0,.87),0,MID,b=.025)
box('腰梁',(5,.12,.08),(0,0,.43),0,EDGE,b=.018)
for x in (-1.15,1.15):box('断续边缘导光',(1.6,.05,.035),(x,-.22,.17),3,RED,b=.006)
finish()

begin('bridge_deck_5m')
box('桥面底盘',(5,5,.26),(0,0,.13),0,DARK,b=.025)
for y in (-2.32,2.32):
 box('桥缘压板',(5,.34,.14),(0,y,.33),0,EDGE,b=.025)
 for x in (-2,-1,0,1,2):
  box('压板红光凹槽',(.26,.18,.024),(x,y,.413),1,BLACK,b=.004)
  box('点状航道灯',(.11,.13,.023),(x,y,.43),3,RED,b=.004)
  bolt(x+.28,y,.411)
for x in (-2.4,-1.8,-1.2,-.6,0,.6,1.2,1.8,2.4):
 box('横向承力踏条',(.12,4.28,.15),(x,0,.335),0,MID,b=.018)
for x in [i*.14 for i in range(-17,18)]:box('真实格栅纵片',(.022,4.16,.085),(x,0,.334),0,EDGE,b=0)
for y in [i*.16 for i in range(-13,14)]:box('真实格栅横片',(4.86,.021,.082),(0,y,.333),0,MID,b=0)
finish()

begin('bridge_truss_5m')
for z in (.13,1.12):box('箱梁翼缘',(5,.5,.26),(0,0,z),0,EDGE,b=.025)
for x in (-2.36,0,2.36):box('桁架立腹杆',(.22,.35,1.0),(x,0,.62),0,MID,b=.022)
for x in (-2.35,0):
 bar('斜腹杆',(x,0,.26),(x+2.35,0,1.0),.19,.28,0,DARK)
 bar('反斜腹杆',(x,0,1.0),(x+2.35,0,.26),.19,.28,0,DARK)
for x in (-2.23,0,2.23):
 box('节点连接板',(.48,.055,.70),(x,-.20,.62),0,MID,b=.035)
 for z in (.42,.83):bolt(x,-.24,z,axis='Y')
finish()

begin('bridge_rail_5m')
box('桥护边踢脚',(5,.21,.18),(0,0,.09),0,DARK,b=.025)
for x in (-2.28,0,2.28):
 box('低位灯柱',(.26,.27,.61),(x,0,.46),0,MID,b=.035)
 box('双面灯窗',(.07,.022,.30),(x,-.15,.51),3,RED,b=.006)
 box('双面灯窗',(.07,.022,.30),(x,.15,.51),3,RED,b=.006)
 plate('柱帽',.34,.36,.10,.05,(x,0,.80),0,EDGE)
box('水平护栏',(5,.11,.095),(0,0,.64),0,MID,b=.016)
finish()

begin('abutment_bracket')
box('牛腿承接板',(1.65,1.3,.28),(0,0,2.95),0,EDGE,b=.04)
box('墙侧锚固背板',(.25,1.3,3),( -.7,0,1.5),0,DARK,b=.05)
for y in (-.43,.43):bar('斜撑',(-.63,y,.22),(.64,y,2.75),.28,.32,0,MID)
for z in (.42,1.5,2.66):box('锚固抱箍',(.38,1.45,.24),(-.65,0,z),0,EDGE,b=.025)
finish()

begin('equipment_cluster')
plate('设备共同底盘',3.3,2.6,.24,.2,(0,0,.12),0,DARK)
for x,y,w,d,h in ((0,.28,1.55,1.5,3.15),(-1.1,-.36,.70,1.10,1.70),(1.13,-.43,.70,1.0,.95)):
 plate('切角机柜壳',w,d,h,.12,(x,y,.24+h/2),1,DARK)
 for xx in (-w*.37,w*.37):box('机柜凸肋',(.085,.12,h*.86),(x+xx,y-d/2-.025,.24+h*.5),0,EDGE,b=.018)
 box('机柜面板',(w*.68,.1,h*.72),(x,y-d/2-.03,.26+h*.5),0,MID,b=.028)
 box('机柜黑色嵌入显示窗',(w*.48,.032,.25),(x,y-d/2-.093,.24+h*.77),2,BLACK,b=.018)
 for k in range(max(1,int(h/.27)-2)):
  z=.48+k*.25
  box('面板散热槽',(w*.42,.014,.045),(x,y-d/2-.097,z),1,BLACK,b=.007)
  if k%2==0:box('短红灯',(.035,.02,.055),(x-w*.23,y-d/2-.10,z),3,RED,b=.005)
 plate('机顶层叠盖板',w+.07,d+.07,.14,.1,(x,y,h+.3),0,EDGE)
 for k in range(7):box('顶盖风槽',(w*.5,.045,.016),(x,y-.32+k*.105,h+.379),1,BLACK,b=.007)
finish()

# Drafts intentionally retain only the large silhouette and spatial composition.
begin('draft_stair_5m')
for k in range(10):box('草稿踏步',(5,.5,.14),(0,-2.25+k*.5,.14+(9-k)*.12),0,DARK,b=.015)
for x in (-2.4,2.4):
 bar('草稿楼梯扶手',(x,-2.5,2.26),(x,2.5,1.06),.12,.12,0,MID)
 for y in (-2.25,0,2.25):box('草稿梯柱',(.16,.18,.95),(x,y,1.1-y*.24),0,MID,b=.01)
finish()
begin('draft_screen')
box('草稿巨屏外框',(11,.52,7),(0,0,3.5),0,DARK,b=.09)
box('草稿红屏占位',(10.5,.06,6.5),(0,-.30,3.5),1,RED,b=.015)
for x in (-5.3,5.3):box('屏边微光',(.05,.028,6.6),(x,-.343,3.5),3,RED,b=.003)
finish()
begin('draft_wall_5m');box('草稿井壁',(5,.8,50),(0,0,25),1,DARK,b=.025);box('草稿竖向框架',(.35,1,50),(0,0,25),0,MID,b=.04);finish()
begin('draft_tower');box('草稿远塔',(3,3,20),(0,0,10),1,DARK,b=.08);box('草稿红竖线',(.10,.03,18),(0,-1.52,10),3,RED,b=.005);finish()
begin('draft_portal')
for x in (-3.15,3.15):box('草稿门垛',(1.3,1.4,6),(x,0,3),0,MID,b=.06)
box('草稿门楣',(7.6,1.4,1),(0,0,6.3),0,MID,b=.06);box('草稿门扇',(5,.32,5.8),(0,.35,2.9),1,DARK,b=.04);finish()

instances=[]
def inst(slug,loc,rz=0,name=None):
 c=masters[slug];o=bpy.data.objects.new(name or f'{meta[slug]["definition"]["name_zh"]}_{len(instances):03}',None);(draft if meta[slug]['definition']['category']=='draft' else out).objects.link(o);o.instance_type='COLLECTION';o.instance_collection=c;o.location=loc;o.rotation_euler.z=math.radians(rz);o.empty_display_size=.3
 o['component_id']=c['component_id'];instances.append({'instance_id':o.name,'component_id':c['component_id'],'slug':slug,'position_m':list(loc),'rotation_y_deg':rz,'scale':[1,1,1],'draft':meta[slug]['definition']['category']=='draft'})
 return o
deck_top=meta['deck_armor_5m']['bounds_size_m'][2]
for x in (-10,-5,0,5,10):
 for y in (-10,-5,0,5,10):inst('deck_emblem_5m' if x==0 and y==0 else 'deck_armor_5m',(x,y,-deck_top))
# Structural rim and server arrays face outwards on all four sides.
for rz in (0,90,180,270):
 R=Matrix.Rotation(math.radians(rz),4,'Z')
 for t in (-10,-5,0,5,10):
  for slug,loc in [('rim_girder_5m',(t,-11.78,-2.05)),('suspended_server_5m',(t,-10.94,-17.85))]:inst(slug,list(R@Vector(loc)),rz)
  # South entrance and east/west bridge interfaces retain exactly 5m open span.
  if not (t==0 and rz in (0,90,270)):inst('deck_barrier_5m',list(R@Vector((t,-12.22,0))),rz)
for x in (-11.63,11.63):
 for y in (-11.63,11.63):inst('corner_pylon',(x,y,-18))
for z in (-2.4,-17.6):
 for x in (-10,-5,0,5,10):
  for y in (-10,-5,0,5,10):
   inst('underframe_beam_5m',(x,y,z));inst('underframe_beam_5m',(x,y,z-.15),90)
for s in (-1,1):
 for x0 in (15,20,25,30):
  x=s*x0;inst('bridge_deck_5m',(x,0,-meta['bridge_deck_5m']['bounds_size_m'][2]))
  for y in (-2.24,2.24):
   inst('bridge_truss_5m',(x,y,-1.62),0 if y<0 else 180)
   inst('bridge_rail_5m',(x,y,0))
 for y in (-1.65,1.65):inst('abutment_bracket',(s*12.85,y,-4.4),0 if s>0 else 180)
 for y in (-8.3,8.3):inst('equipment_cluster',(s*9.0,y,0),0)
 inst('draft_portal',(s*33.2,0,0),90 if s<0 else 270)
for k in range(10):inst('draft_stair_5m',(0,-15-5*k,1.2*k-.01))
for x,rz in ((-12,-18),(0,0),(12,18)):inst('draft_screen',(x,14.8,6.8),rz)
for x in range(-30,31,5):inst('draft_wall_5m',(x,19,-20))
for s in (-1,1):
 for y in (-30,-20,-10,0,10):inst('draft_wall_5m',(s*35,y,-20),s*90)
 for x,y,z in ((18,-14,-27),(26,-7,-29),(22,11,-25),(30,-23,-23),(18,-31,-27),(30,9,-23),(24,19,-27),(31,-38,-25)):inst('draft_tower',(s*x,y,z))

# Hide authoring storage only at the parent view-layer level; instances stay visible.
bpy.context.view_layer.update()
layer=bpy.context.view_layer.layer_collection.children[root.name].children[source.name];layer.exclude=True
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
def camera(n,loc,target,lens=38,ortho=None):
 d=bpy.data.cameras.new(n);o=bpy.data.objects.new(n,d);show.objects.link(o);o.location=loc;aim(o,target);d.lens=lens;d.clip_end=500
 if ortho:d.type='ORTHO';d.ortho_scale=ortho
 return o
cams=[camera('参考镜头_全景',(0,-65,22),(0,0,-1),32),camera('验收_俯视',(0,0,75),(0,0,0),45,70),camera('验收_平台机械近景',(24,-31,13),(0,-2,-3),48),camera('验收_桥梁近景',(23,-12,7),(22,0,-.4),47)]
def area(n,loc,target,col,energy,size):
 d=bpy.data.lights.new(n,'AREA');d.energy=energy;d.color=col;d.shape='DISK';d.size=size;o=bpy.data.objects.new(n,d);show.objects.link(o);o.location=loc;aim(o,target)
area('大面中性柔光',(0,-4,24),(0,0,0),(1,.78,.68),15000,24)
area('前侧结构反射',(0,-25,9),(0,-5,-7),(.72,.78,1),14000,20)
area('后侧红色反射',(0,16,13),(0,0,-2),(1,.015,.012),13000,18)
for s in (-1,1):
 area('侧桥柔光'+str(s),(s*23,-4,12),(s*20,0,0),(1,.78,.68),6000,13)
 area('深井红光'+str(s),(s*19,-5,-12),(s*9,0,-6),(1,.012,.009),11000,16)
world=bpy.data.worlds.new('深井展示世界');world.use_nodes=True;bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.05,.06,.08,1);bg.inputs[1].default_value=.4;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0
scene.render.image_settings.file_format='PNG';scene.camera=cams[0]
scene.use_nodes=True;nt=scene.node_tree;nt.nodes.clear();rl=nt.nodes.new('CompositorNodeRLayers');gl=nt.nodes.new('CompositorNodeGlare');gl.glare_type='FOG_GLOW';gl.threshold=.9;gl.quality='HIGH';gl.mix=-.92;co=nt.nodes.new('CompositorNodeComposite');nt.links.new(rl.outputs['Image'],gl.inputs['Image']);nt.links.new(gl.outputs['Image'],co.inputs['Image'])
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':
   a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL';a.spaces.active.overlay.show_extras=False

# Catalog from actual geometry. Output meshes have identity transform and collection offset zero.
catalog=[]
for slug,c in masters.items():
 md=meta[slug];rec=dict(md['definition']);rec.update(version='v022',collection=c.name,root_object=None,objects=[o.name for o in c.objects],local_origin=[0,0,0],bounds_size_m=md['bounds_size_m'],source_blend=str(BLEND),component_blend=str(DEST/'component_packages'/slug/(slug+'.blend')),instance_count=sum(i['slug']==slug for i in instances),materials=roles,collision_owner='godot_wrapper_pending',exported=False,runtime_connected=False,asset_ledger='assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx',registration_status='未登记',editable_part_count=md['part_count'],instance_offset=list(c.instance_offset),geometry_fingerprint=hashlib.sha256(b''.join(str(tuple(round(v,5) for v in vert.co)).encode() for o in c.objects for vert in o.data.vertices)).hexdigest())
 write(DEST/'component_packages'/slug/'asset_manifest.json',rec);catalog.append(rec)
write(DEST/'component_catalog.json',{'component_count':len(catalog),'components':catalog})
write(DEST/'component_instances.json',{'schema':'shellstorm2.battle.component_instances','schema_version':1,'library':'v022','block_id':'expedition','source_room_type_blend':str(BLEND),'coordinate_contract':{'source_space':'blender_room_local','origin_mode':'template_bounds_center_at_walk_plane','room_frame_world_translation_m':[0,0,0],'room_frame_world_rotation_z_deg':0,'walk_plane_z_m':0,'blender_plane':'XY','blender_up':'+Z','rotation_y_deg_semantics':'rotation_about_blender_Z','godot_mapping':'(bx, by, bz) -> (bx, bz, -by)'},'instances':instances})
(DEST/'component_tree.txt').write_text('\n'.join(f'{r["category"]}/{r["slug"]} | {r["name_zh"]} | {r["instance_count"]} instances' for r in catalog),encoding='utf-8')
manifest={'schema':'shellstorm2.room_type_manifest','room_type':'BOSS_ROOM','variant':'B','block_id':'expedition','level_id':'expedition_01','version':'v022','source_blend':str(BLEND),'whitebox_source':str(WHITEBOX),'design_scope':'scene_art','asset_ledger':'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx','registration_status':'未登记','dimensions_m':{'platform':[25,25],'bridges_each':[20,5],'walking_surface_z':0,'substructure_depth':18},'reference_image':str(DEST/'reference.png'),'component_budget':plan['component_budget'],'runtime_connected':False,'formal_godot_scene_modified':False,'scope':'platform, substructure, two lateral bridges; environment draft only','user_override':'20m bridges replace old 15m whitebox bridge length in this art variant only','source_status':'awaiting_visual_and_technical_validation','draft_components':[d['slug'] for d in plan['components'] if d['category']=='draft']}
write(DEST/'room_type_manifest.json',manifest)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
# Each independent component file has a real scene with its own output collection.
for slug,c in masters.items():
 sc=bpy.data.scenes.new('Component_'+slug);sc.collection.children.link(c);sc.unit_settings.system='METRIC';sc.world=world
 size=meta[slug]['bounds_size_m'];radius=max(size);target=Vector((0,0,size[2]/2))
 cd=bpy.data.cameras.new('组件预览相机');cam=bpy.data.objects.new('组件预览相机',cd);sc.collection.objects.link(cam);cam.location=target+Vector((radius*1.2,-radius*1.8,radius));aim(cam,target);cd.type='ORTHO';cd.ortho_scale=radius*1.7;sc.camera=cam
 ld=bpy.data.lights.new('组件预览柔光','AREA');ld.energy=radius*radius*100;ld.size=radius*1.2;lamp=bpy.data.objects.new('组件预览柔光',ld);sc.collection.objects.link(lamp);lamp.location=target+Vector((radius*.4,-radius,radius*1.5));aim(lamp,target)
 sc.render.engine='CYCLES';sc.cycles.samples=16;sc.render.resolution_x=640;sc.render.resolution_y=640;sc.render.resolution_percentage=100
 bpy.data.libraries.write(str(DEST/'component_packages'/slug/(slug+'.blend')),{sc},path_remap='RELATIVE',fake_user=True)
 bpy.data.scenes.remove(sc)
 bpy.data.objects.remove(cam,do_unlink=True);bpy.data.objects.remove(lamp,do_unlink=True)
write(WORK/'build_result.json',{'blend':str(BLEND),'components':len(masters),'instances':len(instances),'draft_instances':sum(i['draft'] for i in instances),'materials':len(mats),'output_meshes':sum(len(c.objects) for c in masters.values())})
print('BOSS_STRUCTURE_V022_SAVED',str(BLEND),flush=True)
