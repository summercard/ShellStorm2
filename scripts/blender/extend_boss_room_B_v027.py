"""Low-poly downward continuations and inward-facing side database decorations."""
import bpy,bmesh,ast,math,json,sys,shutil,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_depth_v027/state.json').parent;W.mkdir(parents=True,exist_ok=True)
OLD=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v026';D=OLD.parent/'v027';B=D/'Boss房B_设施延伸井底与矩阵转向_v027.blend'
assert not B.exists();assert 'v026' in bpy.data.filepath
bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_live.blend'),copy=True)
scene=bpy.context.scene;scene.frame_set(1);bpy.context.view_layer.update();source=bpy.data.collections['01_制作组件_母版与可编辑零件'];out=bpy.data.collections['02_游戏输出_组件实例布局'];show=bpy.data.collections['90_展示与验收_灯光相机']
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
for n in ast.parse((ROOT/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in ('signature','tris'):exec(compile(ast.Module(body=[n],type_ignores=[]),'<helpers>','exec'))
catalog=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'));masters={r['slug']:bpy.data.collections[r['collection']] for r in catalog}
extend=['compute_tower_tall','compute_tower_stepped','compute_tower_compact','suspended_server_5m','door_support_pier','corner_pylon']
targets=[o for o in scene.objects if o.instance_collection in [masters[s] for s in extend]]
side_matrices=[o for o in scene.objects if o.instance_collection==masters['matrix_bay_5m'] and abs(o.location.x)>32]
mutable={o.name for o in targets+side_matrices}
for slug in extend:
 r=next(r for r in catalog if r['slug']==slug);mutable.update(o.name for o in bpy.data.collections['组件_'+r['name_zh']].all_objects)
locked={o.name:signature(o) for o in scene.objects if o.name not in mutable and o.type!='CAMERA'}
before_targets={o.name:{'matrix':[list(r) for r in o.matrix_world],'slug':next(s for s in extend if masters[s]==o.instance_collection)} for o in targets};before_sides={o.name:{'matrix':[list(r) for r in o.matrix_world],'position':list(o.location)} for o in side_matrices}
rec={'slug':'matrix_foundation_5m','name_zh':'矩阵低面数井底延伸','component_id':'ENV-EXPEDITION-BOSS-B-MATRIX-FOUNDATION-5M','component_family':'matrix_foundation','category':'architecture','scope':'room_type_local','front_axis':'-Y','serves_room_types':['BOSS_ROOM']};plan['components'].append(rec);catalog.append(rec.copy());plan.update(version='v027',component_budget={'limit':50,'planned':len(catalog),'remaining':50-len(catalog)},refinement={'tower_extension':'Extend plain lower shell by 40m; preserve existing detailed geometry in world space; may penetrate floor','matrix_extension':'Lowest wall-matrix rows receive a 22m low-poly continuation','side_facing':'Rotate 32 side database modules 180 degrees at unchanged instance origins; face room interior'})
D.mkdir(parents=True,exist_ok=True)
for p in OLD.glob('*.json'):shutil.copy2(p,D/p.name)
for p in OLD.glob('reference*.png'):shutil.copy2(p,D/p.name)
shutil.copytree(OLD/'textures',D/'textures',dirs_exist_ok=True);write(D/'component_plan.json',plan)
parts=[];current=None;cache={};edits={};meta={};DARK=(9,9);MID=(9,8);EDGE=(9,7);STEEL=(9,6);BLACK=(0,9);RED=(4,8)
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'];mats=[bpy.data.materials[n] for n in roles]
for n in ast.parse((ROOT/'scripts/blender/build_boss_room_B_structure_v022.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in {'collection','uv','geom_box','part','box','begin','object_from','finish','aim'}:exec(compile(ast.Module(body=[n],type_ignores=[]),'<helpers>','exec'))
budget=[];original_vertices={}
for slug in extend:
 col=masters[slug];edit=bpy.data.collections['制作零件_'+slug];original_vertices[slug]={o.name:[tuple(v.co) for v in o.data.vertices] for o in col.objects};before_tri=tris(col)
 core=next(o for o in edit.objects if o.get('semantic_part') in ('大型方形主壳','主柱芯'));lo=Vector([min(v.co[i] for v in core.data.vertices) for i in range(3)]);hi=Vector([max(v.co[i] for v in core.data.vertices) for i in range(3)]);center=(lo+hi)/2;w=hi.x-lo.x;d=hi.y-lo.y
 for o in list(edit.objects)+list(col.objects):
  if o.type=='MESH':
   for v in o.data.vertices:v.co.z+=40
 # Three simple prisms, 36 additional triangles per unique tower master.
 additions=[]
 for name,size,loc,role,cell in [('井底延伸主壳',(w,d,40.25),(center.x,center.y,20.125),1,DARK),('井底延伸左肋',(w*.12,.10,40.25),(lo.x+w*.08,lo.y-.045,20.125),0,DARK),('井底延伸右肋',(w*.12,.10,40.25),(hi.x-w*.08,lo.y-.045,20.125),0,DARK)]:
  vs,fs=geom_box(size,0);vs=[tuple(Vector(v)+Vector(loc)) for v in vs];o=object_from(slug+'_'+name,vs,fs,[role]*len(fs),[cell]*len(fs),edit);o['semantic_part']=name;additions.append(o)
 body=next(o for o in col.objects if mats[3] not in list(o.data.materials));vs=[tuple(v.co) for v in body.data.vertices];fs=[tuple(p.vertices) for p in body.data.polygons];rr=[roles.index(body.data.materials[p.material_index].name) for p in body.data.polygons];cc=[]
 for p in body.data.polygons:
  co=body.data.uv_layers['PaletteUV'].data[p.loop_start].uv;cc.append((int(co.x*10),int(co.y*10)))
 for o in additions:
  start=len(vs);vs.extend(tuple(v.co) for v in o.data.vertices)
  for p in o.data.polygons:
   fs.append(tuple(start+i for i in p.vertices));rr.append(roles.index(o.data.materials[p.material_index].name));co=o.data.uv_layers['PaletteUV'].data[p.loop_start].uv;cc.append((int(co.x*10),int(co.y*10)))
 name=body.name;bpy.data.objects.remove(body,do_unlink=True);object_from(name,vs,fs,rr,cc,col);budget.append({'slug':slug,'before_triangles':before_tri,'after_triangles':tris(col)})
for o in targets:o.matrix_world=o.matrix_world@Matrix.Translation((0,0,-40))
for o in side_matrices:
 inward=Vector((-o.location.x,0,0)).normalized();front=o.matrix_world.to_quaternion()@Vector((0,-1,0))
 if front.dot(inward)<0:o.rotation_euler.z+=math.pi
bpy.context.view_layer.update()
# Prove every original detailed vertex still occupies the same world-space position.
errors={}
for o in targets:
 old=Matrix(before_targets[o.name]['matrix']);slug=before_targets[o.name]['slug'];err=0
 for meshname,vertices in original_vertices[slug].items():
  mesh=bpy.data.objects[meshname]
  for i,v in enumerate(vertices):err=max(err,(old@Vector(v)-o.matrix_world@mesh.data.vertices[i].co).length)
 errors[o.name]=err
assert max(errors.values())<.0001
begin('matrix_foundation_5m');box('矩阵连续下壳',(5,1.3,22),(0,0,11),1,DARK,b=0)
for x in (-2.30,2.30):box('下延竖肋',(.18,.12,22),(x,-.68,11),0,DARK,b=0)
finish()
foundations=[]
lowest=[o for o in scene.objects if o.instance_collection==masters['matrix_bay_5m'] and abs(o.location.z+18)<.01]
for host in lowest:
 o=bpy.data.objects.new('井底延伸_'+host.name,None);out.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=masters['matrix_foundation_5m'];o.matrix_world=host.matrix_world@Matrix.Translation((0,0,-21.6));o['host_instance']=host.name;foundations.append(o.name)
for im in bpy.data.images:
 if im.source=='FILE' and 'screen_' in Path(bpy.path.abspath(im.filepath)).name:im.filepath=str(D/'textures'/Path(bpy.path.abspath(im.filepath)).name)
for name,loc,target,lens in [('验收_井底延伸',(7,-30,7),(15,-8,-29),32),('验收_西墙数据库',(-16,-37,7),(-33.5,-20,6),33),('验收_东墙数据库',(16,-37,7),(33.5,-20,6),33)]:
 cd=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,cd);show.objects.link(o);o.location=loc;aim(o,target);cd.lens=lens;cd.clip_end=250
bpy.context.view_layer.update();changed=[n for n,h in locked.items() if n not in bpy.data.objects or signature(bpy.data.objects[n])!=h];assert not changed,changed
write(W/'scope_lock.json',{'before':locked,'changed':changed,'camera_policy':'Preserve live user cameras, not part of geometry signature','authorized':'low-poly lower extension + side matrix orientation'})
instances=[]
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 slug=next(s for s,c in masters.items() if c==o.instance_collection);r=next(r for r in catalog if r['slug']==slug);instances.append({'instance_id':o.name,'component_id':r['component_id'],'slug':slug,'position_m':list(o.location),'matrix_room_local':[list(row) for row in o.matrix_world],'rotation_euler_xyz_deg':[math.degrees(v) for v in o.rotation_euler],'scale':list(o.scale),'draft':False})
write(D/'component_instances.json',{'schema_version':2,'version':'v027','instances':instances})
text=(ROOT/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8');chunk=text[text.index('for rec in catalog:\n'):text.index("write(D/'component_catalog.json'")];exec(compile(chunk.replace("version='v024'","version='v027'"),'<export>','exec'));write(D/'component_catalog.json',{'component_count':len(catalog),'components':catalog})
write(W/'extension_contract.json',{'floor_z':-36,'extension_length':40,'tower_instances':before_targets,'side_matrix_instances':before_sides,'matrix_foundations':foundations,'original_vertex_world_errors':errors,'master_triangle_budget':budget})
manifest=json.loads((D/'room_type_manifest.json').read_text(encoding='utf-8'));manifest.update(version='v027',source_blend=str(B),component_budget=plan['component_budget']);write(D/'room_type_manifest.json',manifest)
(D/'component_tree.txt').write_text('\n'.join(f'{r["slug"]} | {r["name_zh"]} | {r["instance_count"]}' for r in catalog),encoding='utf-8');scene.name='Boss房B_延伸井底与矩阵转向_v027';bpy.data.collections['Boss房B_中文资产管理_v026'].name='Boss房B_中文资产管理_v027';bpy.ops.wm.save_as_mainfile(filepath=str(B));print('SAVED_V027',len(catalog),len(instances),'extended',len(targets),'turned',len(side_matrices),'foundations',len(foundations),'max_world_error',max(errors.values()))
