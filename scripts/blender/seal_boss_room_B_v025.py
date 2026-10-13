import bpy,bmesh,ast,json,math,sys
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');D=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v025';B=Path(bpy.data.filepath);scene=bpy.context.scene;source=bpy.data.collections['01_制作组件_母版与可编辑零件']
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));catalog=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];assert len(plan['components'])==39
rec={'slug':'door_seal_frame','name_zh':'门框密封边组件','component_id':'ENV-EXPEDITION-BOSS-B-DOOR-SEAL-FRAME','component_family':'door_seal','category':'architecture','scope':'room_type_local','front_axis':'-Y','serves_room_types':['BOSS_ROOM']};plan['components'].append(rec);catalog.append(rec.copy());plan['component_budget']={'limit':50,'planned':40,'remaining':10};write(D/'component_plan.json',plan)
masters={r['slug']:bpy.data.collections[r['collection']] for r in catalog if r.get('collection')};DARK=(9,9);MID=(9,8);EDGE=(9,7);BLACK=(0,9);RED=(4,8);STEEL=(9,6);cache={};meta={};edits={};parts=[];current=None
mats=[bpy.data.materials[n] for n in ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']]
for n in ast.parse((ROOT/'scripts/blender/build_boss_room_B_structure_v022.py').read_text(encoding='utf-8')).body:
 if isinstance(n,ast.FunctionDef) and n.name in {'collection','uv','geom_box','part','box','begin','object_from','finish','aim'}:exec(compile(ast.Module(body=[n],type_ignores=[]),'<helper>','exec'))
def tris(c):return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in c.objects)
begin('door_seal_frame')
for x in (-2.49,2.49):box('门缝密封立边',(.12,.50,6),(x,0,3),1,BLACK,b=0)
box('门楣搭接密封',(5.10,.5,.40),(0,0,5.80),0,DARK,b=0)
box('门槛密封',(5.1,.5,.10),(0,0,.05),0,DARK,b=0);finish()
out=bpy.data.collections['02_游戏输出_组件实例布局']
for i in range(3):
 frame=bpy.data.objects[f'外壳门框_{i}'];o=bpy.data.objects.new(f'外壳密封边_{i}',None);out.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=masters['door_seal_frame'];o.matrix_world=frame.matrix_world
 for slug,xx in [('exit_leaf_a',-1.235),('exit_leaf_b',1.235)]:bpy.data.objects[f'外壳门扇_{i}_{slug}'].matrix_world=frame.matrix_world@Matrix.Translation((xx,0,0))
bpy.context.view_layer.update();data=json.loads((D/'component_instances.json').read_text(encoding='utf-8'));instances=[]
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 slug=next(s for s,c in masters.items() if c==o.instance_collection);r=next(r for r in catalog if r['slug']==slug);instances.append({'instance_id':o.name,'component_id':r['component_id'],'slug':slug,'position_m':list(o.location),'rotation_euler_xyz_deg':[math.degrees(v) for v in o.rotation_euler],'matrix_room_local':[list(row) for row in o.matrix_world],'scale':list(o.scale),'draft':False})
data['instances']=instances;write(D/'component_instances.json',data)
text=(ROOT/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8');chunk=text[text.index('for rec in catalog:\n'):text.index("write(D/'component_catalog.json'")];exec(compile(chunk.replace("version='v024'","version='v025'"),'<export>','exec'));write(D/'component_catalog.json',{'component_count':len(catalog),'components':catalog})
manifest=json.loads((D/'room_type_manifest.json').read_text(encoding='utf-8'));manifest['component_budget']=plan['component_budget'];write(D/'room_type_manifest.json',manifest)
(D/'component_tree.txt').write_text('\n'.join(f'{r["slug"]} | {r["name_zh"]} | {r["instance_count"]}' for r in catalog),encoding='utf-8');bpy.ops.wm.save_as_mainfile(filepath=str(B));print('SEALED_NEW_DOOR_SEAMS',len(catalog),len(instances))
