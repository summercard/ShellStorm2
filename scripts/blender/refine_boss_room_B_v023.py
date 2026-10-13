"""Visual corrections from hero review: darker new computer casings and real exit clearance."""
import bpy,bmesh,ast,math,json,hashlib,sys
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_detail_v023/session.json').parent;D=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v023';B=D/'Boss房B_显示器电缆与矩阵深化_v023.blend'
scene=bpy.context.scene;source=bpy.data.collections['01_制作组件_母版与可编辑零件'];out=bpy.data.collections['02_游戏输出_组件实例布局'];show=bpy.data.collections['90_展示与验收_灯光相机']
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));catalog=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
slug='portal_backing_5m';info={'slug':slug,'component_id':'ENV-EXPEDITION-BOSS-B-PORTAL-BACKING-5M','name_zh':'出口井壁贯通背板','component_family':'portal_backing','category':'architecture','scope':'room_type_local','serves_room_types':['BOSS_ROOM'],'front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270],'variant_axis':None,'variant_value':None,'variant_reason':None}
plan['components'].append(info);plan['component_budget']={'limit':50,'planned':len(plan['components']),'remaining':50-len(plan['components'])};(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'];mats=[bpy.data.materials[n] for n in roles]
DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8);cache={};parts=[];current=None;masters={c['slug']:bpy.data.collections[c['collection']] for c in catalog};meta={};edits={}
tree=ast.parse((ROOT/'scripts/blender/build_boss_room_B_structure_v022.py').read_text(encoding='utf-8'))
for node in tree.body:
 if isinstance(node,ast.FunctionDef) and node.name in {'collection','uv','geom_box','part','box','bar','plate','bolt','begin','object_from','finish','aim'}:exec(compile(ast.Module(body=[node],type_ignores=[]),'<helpers>','exec'))
begin(slug);box('门口下方井壁',(5,.8,20),(0,0,10),1,DARK,b=.02);box('门口上方井壁',(5,.8,24),(0,0,38),1,DARK,b=.02);finish()
record={**info,'version':'v023','collection':masters[slug].name,'source_blend':str(B),'component_blend':str(D/'component_packages'/slug/(slug+'.blend')),'objects':[o.name for o in masters[slug].objects],'bounds_size_m':[5,.8,50],'local_origin':[0,0,0],'texture_exception':False,'collision_owner':'godot_wrapper_pending','runtime_connected':False,'registration_status':'未登记'};catalog.append(record)
scope=json.loads((W/'scope_lock_geometry.json').read_text(encoding='utf-8'));host_changes=[]
for o in bpy.context.scene.objects:
 if o.instance_type=='COLLECTION' and o.instance_collection.name=='输出资产包_draft_wall_5m' and abs(abs(o.location.x)-35)<.01 and abs(o.location.y)<.01:
  host_changes.append({'name':o.name,'old_signature':scope['before'][o.name],'reason':'Door host backing originally occluded the exit passage; user-authorized exit detailing requires a real 5m x 6m opening. Instance transform retained.'});o.instance_collection=masters[slug];o['component_id']=info['component_id'];scope['before'].pop(o.name);scope['after'].pop(o.name)
assert len(host_changes)==2
scope['authorized_door_host_changes']=host_changes;scope['locked_count']=len(scope['before']);(W/'scope_lock_geometry.json').write_text(json.dumps(scope,ensure_ascii=False,indent=2),encoding='utf-8')
# Only the newly made computers receive a darker palette. Old platform/bridge materials stay untouched.
newcols=[bpy.data.collections['组件_'+next(p['name_zh'] for p in plan['components'] if p['slug']==s)] for s in ('matrix_bay_5m','compute_tower_tall','compute_tower_stepped','compute_tower_compact')]
for c in newcols:
 for o in c.all_objects:
  if o.type!='MESH':continue
  uv=o.data.uv_layers['PaletteUV']
  for p in o.data.polygons:
   material=o.data.materials[p.material_index];co=uv.data[p.loop_start].uv;cell=(int(co.x*10),int(co.y*10));dest=None
   if material==mats[1] and cell==DARK:dest=BLACK
   if material==mats[0] and cell==MID:dest=DARK
   if dest:
    for li in p.loop_indices:uv.data[li].uv.x+=(dest[0]-cell[0])*.1;uv.data[li].uv.y+=(dest[1]-cell[1])*.1
# Tall vertical units break the repeated horizontal matrix seams.
for s in (-1,1):
 for k,x in enumerate((5,15,25)):
  name='后方矩阵凸出塔_'+str(s)+'_'+str(k);o=bpy.data.objects.new(name,None);out.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=masters['compute_tower_tall' if k!=1 else 'compute_tower_stepped'];o.location=(s*x,18.6+(k%2)*.7,-9.5+(k%2)*5)
# Rebuild actual catalog and full transform manifest after these authorized corrections.
instances=[]
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 s=next(s for s,c in masters.items() if c==o.instance_collection);d=next(c for c in catalog if c['slug']==s)
 instances.append({'instance_id':o.name,'component_id':d['component_id'],'slug':s,'position_m':list(o.location),'rotation_euler_xyz_deg':[math.degrees(v) for v in o.rotation_euler],'matrix_room_local':[list(r) for r in o.matrix_world],'scale':list(o.scale),'draft':d['category']=='draft','user_pose_locked':bool(o.get('user_pose_locked',False))})
data=json.loads((D/'component_instances.json').read_text(encoding='utf-8'));data['instances']=instances;(D/'component_instances.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
for rec in catalog:
 c=masters[rec['slug']];pts=[o.matrix_basis@v.co for o in c.objects for v in o.data.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)];rec.update(bounds_min=lo,bounds_max=hi,bounds_size_m=[hi[i]-lo[i] for i in range(3)],instance_count=sum(i['slug']==rec['slug'] for i in instances),instance_offset=list(c.instance_offset),materials=sorted({m.name for o in c.objects for m in o.data.materials}))
 rec['geometry_fingerprint']=hashlib.sha256(str([(o.name,[tuple(v.co) for v in o.data.vertices],[tuple(x.uv) for x in o.data.uv_layers.active.data]) for o in c.objects]).encode()).hexdigest()
 pkg=D/'component_packages'/rec['slug'];pkg.mkdir(parents=True,exist_ok=True);(pkg/'asset_manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2),encoding='utf-8')
 sc=bpy.data.scenes.new('Component_'+rec['slug']);sc.collection.children.link(c);sc.world=scene.world;sc.unit_settings.system='METRIC';r=max(rec['bounds_size_m']);target=Vector((0,0,rec['bounds_size_m'][2]/2))
 cd=bpy.data.cameras.new('组件预览');cam=bpy.data.objects.new('组件预览',cd);sc.collection.objects.link(cam);cam.location=target+Vector((r*.9,-r*1.8,r*.8));aim(cam,target);cd.type='ORTHO';cd.ortho_scale=r*1.7;sc.camera=cam
 ld=bpy.data.lights.new('组件柔光','AREA');ld.energy=r*r*100;ld.size=r;lamp=bpy.data.objects.new('组件柔光',ld);sc.collection.objects.link(lamp);lamp.location=target+Vector((r,-r,r));aim(lamp,target)
 sc.render.engine='CYCLES';sc.cycles.samples=16;sc.render.resolution_x=640;sc.render.resolution_y=640;sc.render.resolution_percentage=100
 bpy.data.libraries.write(rec['component_blend'],{sc},path_remap='RELATIVE',fake_user=True);bpy.data.scenes.remove(sc);bpy.data.objects.remove(cam,do_unlink=True);bpy.data.objects.remove(lamp,do_unlink=True)
(D/'component_catalog.json').write_text(json.dumps({'component_count':len(catalog),'components':catalog},ensure_ascii=False,indent=2),encoding='utf-8')
(D/'component_tree.txt').write_text('\n'.join(f'{r["category"]}/{r["slug"]} | {r["name_zh"]} | {r["instance_count"]}' for r in catalog),encoding='utf-8')
manifest=json.loads((D/'room_type_manifest.json').read_text(encoding='utf-8'));manifest['component_budget']=plan['component_budget'];(D/'room_type_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B));print('VISUAL_REFINEMENTS_SAVED',len(catalog),len(instances))
