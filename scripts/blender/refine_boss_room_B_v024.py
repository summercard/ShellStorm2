"""Scoped silhouette reconstruction with upward lighting; execute on the live v023 session."""
import bpy,bmesh,ast,math,json,sys,hashlib,shutil
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_silhouette_v024/state.json').parent;W.mkdir(parents=True,exist_ok=True)
OLD=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v023'
D=OLD.parent/'v024';B=D/'Boss房B_方形塔体与底部上射灯_v024.blend'
assert not B.exists(),'Existing result protected; inspect before rerun'
assert 'v023' in bpy.data.filepath,'Expected current user v023 scene'
bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_live.blend'),copy=True)
scene=bpy.context.scene;scene.frame_set(1);bpy.context.view_layer.update()
source=bpy.data.collections['01_制作组件_母版与可编辑零件'];out=bpy.data.collections['02_游戏输出_组件实例布局'];show=bpy.data.collections['90_展示与验收_灯光相机']
def write(p,data):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
def signature(o):
 d={'type':o.type,'matrix':[list(r) for r in o.matrix_world],'data':o.data.name if o.data else None,'collection':o.instance_collection.name if o.instance_collection else None}
 if o.type=='MESH':d.update(v=[list(v.co) for v in o.data.vertices],f=[list(p.vertices) for p in o.data.polygons],uv=[[list(x.uv) for x in u.data] for u in o.data.uv_layers],materials=[m.name for m in o.data.materials])
 return hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()
rebuild=['compute_tower_tall','compute_tower_stepped','compute_tower_compact','suspended_server_5m']
catalog=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'))
excluded=set()
for slug in rebuild:
 info=next(r for r in catalog if r['slug']==slug);excluded.update(o.name for o in bpy.data.collections['组件_'+info['name_zh']].all_objects)
locked={o.name:signature(o) for o in scene.objects if o.name not in excluded}
poses={o.name:[list(r) for r in o.matrix_world] for o in scene.objects if o.name in ('草稿巨屏_246','草稿巨屏_247','草稿巨屏_248')}
def tris(col):return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in col.objects if o.type=='MESH')
before={r['slug']:tris(bpy.data.collections[r['collection']]) for r in catalog}
D.mkdir(parents=True,exist_ok=True)
for p in OLD.glob('*.json'):shutil.copy2(p,D/p.name)
shutil.copytree(OLD/'textures',D/'textures',dirs_exist_ok=True)
plan['version']='v024';plan['refinement']={'scope':rebuild+['door_support_pier','preview_uplights'],'priority':'Large rectangular masses, stepped recesses, broad shoulders, red vertical focal strips, curved pipes; reduce micro geometry','lighting':'Upward neutral fill plus red shaft bounce','frozen_before_geometry':True}
new={'slug':'door_support_pier','component_id':'ENV-EXPEDITION-BOSS-B-DOOR-SUPPORT-PIER','name_zh':'门侧方形承力巨柱','component_family':'door_support','category':'architecture','scope':'room_type_local','serves_room_types':['BOSS_ROOM'],'front_axis':'-Y','variant_axis':None}
plan['components'].append(new);plan['component_budget']={'limit':50,'planned':32,'remaining':18};write(D/'component_plan.json',plan)
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'];mats=[bpy.data.materials[n] for n in roles]
DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8);cache={};parts=[];current=None;masters={r['slug']:bpy.data.collections[r['collection']] for r in catalog};edits={};meta={}
for node in ast.parse((ROOT/'scripts/blender/build_boss_room_B_structure_v022.py').read_text(encoding='utf-8')).body:
 if isinstance(node,ast.FunctionDef) and node.name in {'collection','uv','geom_box','part','box','bar','begin','object_from','finish','aim'}:
  if node.name=='geom_box':
   for child in ast.walk(node):
    if isinstance(child,ast.keyword) and child.arg=='segments':child.value=ast.Constant(value=1)
   ast.fix_missing_locations(node)
  exec(compile(ast.Module(body=[node],type_ignores=[]),'<helpers>','exec'))
def pipe(name,points,r=.13):
 # Rounded elbows: 5 samples at each quadratic corner, 8 vertices per ring.
 p=[Vector(x) for x in points];q=[p[0]]
 for i in range(1,len(p)-1):
  a=p[i].lerp(p[i-1],.22);b=p[i].lerp(p[i+1],.22)
  for k in range(5):
   t=k/4;q.append((1-t)**2*a+2*t*(1-t)*p[i]+t*t*b)
 q.append(p[-1]);vs=[];fs=[]
 for i,pos in enumerate(q):
  tangent=q[min(i+1,len(q)-1)]-q[max(0,i-1)];rot=tangent.to_track_quat('Z','Y')
  vs.extend(tuple(pos+rot@Vector((r*math.cos(k*math.tau/8),r*math.sin(k*math.tau/8),0))) for k in range(8))
 for i in range(len(q)-1):
  for k in range(8):fs.append((i*8+k,i*8+(k+1)%8,(i+1)*8+(k+1)%8,(i+1)*8+k))
 fs.extend([tuple(reversed(range(8))),tuple(range((len(q)-1)*8,len(q)*8))]);part(name,vs,fs,role=0,cell=DARK)
def tower(w,d,h,variant):
 box('大型方形主壳',(w*.9,d*.8,h),(0,d*.1,h/2),1,DARK,b=.09)
 box('内退纵向暗井',(w*.62,.16,h*.84),(-w*.08,-d*.315,h*.5),1,BLACK,b=0)
 for x,ww in ((-w*.39,w*.18),(w*.28,w*.29)):
  box('整面厚甲纵柱',(ww,d*.38,h*.94),(x,-d*.37,h*.49),0,DARK,b=.065)
  box('装甲浅层折面',(ww*.5,.12,h*.70),(x,-d*.575,h*.50),1,MID,b=.025)
 # Large projecting collars create a stepped silhouette with deep shadows beneath.
 for z,hh,depth,offset in ((h*.95,h*.10,d*.98,0),(h*.47,h*.095,d*1.13,-d*.10),(h*.13,h*.08,d*.97,0)):
  box('外凸方形肩座',(w,depth,hh),(0,offset,z),0,DARK,b=.09)
  box('肩座前端装甲块',(w*.66,.25,hh*.62),(w*.09,offset-depth/2-.09,z),1,MID,b=.04)
  for x in (-w*.38,w*.38):box('宽扣耳',(w*.13,.32,hh*.90),(x,offset-depth/2-.18,z),0,EDGE,b=.025)
 for k in range(8):
  z=h*(.23+k*.083)
  box('大号内凹服务器面板',(w*.37,.14,h*.057),(-w*.08,-d*.40,z),0,DARK,b=.016)
  box('简化状态红点',(.07,.025,.095),(-w*.20,-d*.481,z),3,RED,b=0)
 lx=w*.28
 box('主红灯深槽',(w*.13,.18,h*.56),(lx,-d*.59,h*.59),1,BLACK,b=.025)
 box('焦点红色长灯',(.16 if w<4 else .23,.055,h*.53),(lx,-d*.70,h*.59),3,RED,b=.012)
 box('灯带上端状态块',(.22,.055,.3),(lx,-d*.70,h*.90),3,RED,b=.01)
 # Exposed return pipes bridge the deep recess under the shoulder.
 for k in range(2):
  x=-w*.33+k*.29;y=-d*.58-k*.13
  pipe('弯曲回流管',[(x,y,h*.88),(x,y,h*.61),(x+w*.19,y-.20,h*.58),(x+w*.19,y-.20,h*.38),(x+w*.40,y,h*.33)],.10+k*.025)
 # Broad side plate instead of dozens of tiny grille cuts.
 box('侧面阶梯检修箱',(w*.27,d*.68,h*.31),(-w*.35,d*.06,h*.70),1,DARK,b=.055)
 for k in range(3):box('顶部横向压条',(w*.82,.12,.07),(0,-d*.26+k*d*.25,h+.025),0,EDGE,b=.01)

for slug,w,d,h,var in [('compute_tower_tall',4.8,4.2,20,0),('compute_tower_stepped',5.6,4.8,15.5,1),('compute_tower_compact',4.2,4.0,11.5,2),('suspended_server_5m',4.9,3.0,15.8,0)]:
 old=masters[slug];users=[o for o in scene.objects if o.instance_collection==old];info=next(r for r in catalog if r['slug']==slug);parent=bpy.data.collections['组件_'+info['name_zh']]
 for c in list(parent.children):
  for o in list(c.objects):bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.collections.remove(c)
 bpy.data.collections.remove(parent);begin(slug);tower(w,d,h,var);finish()
 for o in users:o.instance_collection=masters[slug]
begin('door_support_pier');tower(3.8,4.6,28,0);finish();catalog.append(new.copy())
for door in [o for o in scene.objects if o.instance_collection==masters['exit_portal']]:
 for side in (-1,1):
  o=bpy.data.objects.new('门侧巨柱_'+door.name+'_'+str(side),None);out.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=masters['door_support_pier'];o.matrix_world=door.matrix_world@Matrix.Translation((side*5.4,1.6,-20));o['component_id']=new['component_id']
# Light positions are below the structures, all aim upward. They remain preview-only.
light_specs=[('中心底部柔光',(0,-24,-28),(0,-8,-8),42000,(.63,.72,1),14),('中心深井红反射',(0,-12,-31),(0,0,-8),18000,(1,.018,.008),10)]
for side in (-1,1):
 light_specs.extend([(f'侧塔底部柔光{side}',(side*24,-27,-31),(side*24,-8,-7),36000,(.68,.75,1),12),(f'门柱底部上射{side}',(side*27,-5,-24),(side*34,0,1),26000,(.75,.80,1),9),(f'侧井红色上射{side}',(side*18,2,-30),(side*20,4,-3),15000,(1,.015,.006),9)])
for name,pos,target,energy,color,size in light_specs:
 ld=bpy.data.lights.new(name,'AREA');ld.energy=energy;ld.color=color;ld.shape='DISK';ld.size=size;o=bpy.data.objects.new(name,ld);show.objects.link(o);o.location=pos;aim(o,target);o['preview_only']=True;o['lighting_role']='bottom_to_top_silhouette'
# Relink explicit screen texture exception to the new version; palette stays shared.
for im in bpy.data.images:
 if im.source=='FILE' and 'screen_' in Path(bpy.path.abspath(im.filepath)).name:im.filepath=str(D/'textures'/Path(bpy.path.abspath(im.filepath)).name)
bpy.context.view_layer.update()
changed=[n for n,h in locked.items() if n not in bpy.data.objects or signature(bpy.data.objects[n])!=h];assert not changed,changed
write(W/'scope_lock.json',{'before':locked,'changed':changed,'screen_poses':poses,'authorized_geometry':rebuild+['door_support_pier']})
instances=[]
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 slug=next(s for s,c in masters.items() if c==o.instance_collection);rec=next(r for r in catalog if r['slug']==slug)
 instances.append({'instance_id':o.name,'component_id':rec['component_id'],'slug':slug,'position_m':list(o.location),'rotation_euler_xyz_deg':[math.degrees(v) for v in o.rotation_euler],'matrix_room_local':[list(r) for r in o.matrix_world],'scale':list(o.scale),'draft':rec['category']=='draft','user_pose_locked':o.name in poses})
write(D/'component_instances.json',{'schema_version':2,'version':'v024','instances':instances})
for rec in catalog:
 c=masters[rec['slug']];pts=[o.matrix_basis@v.co for o in c.objects for v in o.data.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 pkg=D/'component_packages'/rec['slug'];pkg.mkdir(parents=True,exist_ok=True)
 rec.update(version='v024',collection=c.name,source_blend=str(B),component_blend=str(pkg/(rec['slug']+'.blend')),objects=[o.name for o in c.objects],bounds_min=lo,bounds_max=hi,bounds_size_m=[hi[i]-lo[i] for i in range(3)],instance_count=sum(i['slug']==rec['slug'] for i in instances),triangle_count=tris(c),instance_offset=list(c.instance_offset),materials=sorted({m.name for o in c.objects for m in o.data.materials}),runtime_connected=False)
 write(pkg/'asset_manifest.json',rec)
 sc=bpy.data.scenes.new('Component_'+rec['slug']);sc.collection.children.link(c);sc.world=scene.world;sc.unit_settings.system='METRIC';r=max(rec['bounds_size_m']);target=Vector((0,0,hi[2]/2))
 cd=bpy.data.cameras.new('组件预览');cam=bpy.data.objects.new('组件预览',cd);sc.collection.objects.link(cam);cam.location=target+Vector((r,-r*1.8,r*.7));aim(cam,target);cd.type='ORTHO';cd.ortho_scale=r*1.7;sc.camera=cam
 ld=bpy.data.lights.new('组件柔光','AREA');ld.energy=r*r*100;ld.size=r;lamp=bpy.data.objects.new('组件柔光',ld);sc.collection.objects.link(lamp);lamp.location=target+Vector((r,-r,r));aim(lamp,target)
 bpy.data.libraries.write(rec['component_blend'],{sc},path_remap='RELATIVE',fake_user=True);bpy.data.scenes.remove(sc);bpy.data.objects.remove(cam,do_unlink=True);bpy.data.objects.remove(lamp,do_unlink=True)
write(D/'component_catalog.json',{'component_count':len(catalog),'components':catalog})
write(W/'geometry_budget.json',{'before_output_triangles':before,'after_output_triangles':{r['slug']:r['triangle_count'] for r in catalog},'rebuilt_before':sum(before[s] for s in rebuild),'rebuilt_after':sum(tris(masters[s]) for s in rebuild),'lights':[{'name':n,'position':p,'target':t,'watts':e,'color':c,'size':sz} for n,p,t,e,c,sz in light_specs]})
manifest=json.loads((D/'room_type_manifest.json').read_text(encoding='utf-8'));manifest.update(version='v024',source_blend=str(B),component_budget=plan['component_budget'],runtime_connected=False);write(D/'room_type_manifest.json',manifest)
(D/'component_tree.txt').write_text('\n'.join(f'{r["slug"]} | {r["name_zh"]} | {r["instance_count"]}' for r in catalog),encoding='utf-8')
for c in bpy.data.collections:
 if c.name=='Boss房B_中文资产管理_v023':c.name='Boss房B_中文资产管理_v024'
scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B));print('SAVED_V024',len(catalog),len(instances),sum(before[s] for s in rebuild),sum(tris(masters[s]) for s in rebuild))
