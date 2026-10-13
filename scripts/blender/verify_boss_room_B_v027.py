"""Native independent scope, image-surface, animation, package and material verification."""
import bpy,json,math,sys,hashlib,ast,importlib.util
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(R/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_depth_v027/acceptance.json').parent;D=R/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v027'
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));catalog=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];records=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances'];scope=json.loads((W/'scope_lock.json').read_text(encoding='utf-8'));snapshot=json.loads((R.parent/'ShellStorm2-work/outputs/boss_detail_v023/live_snapshot.json').read_text(encoding='utf-8'))
for node in ast.parse((R/'scripts/blender/refine_boss_room_B_v024.py').read_text(encoding='utf-8')).body:
 if isinstance(node,ast.FunctionDef) and node.name=='signature':exec(compile(ast.Module(body=[node],type_ignores=[]),'<signature>','exec'))
spec=importlib.util.spec_from_file_location('validator',r'C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
changed=[n for n,h in scope['before'].items() if n not in bpy.data.objects or signature(bpy.data.objects[n])!=h]
screen_errors={s['name']:max(abs(bpy.data.objects[s['name']].matrix_world[i][j]-s['matrix'][i][j]) for i in range(4) for j in range(4)) for s in snapshot['screens']}
inst=[o for o in bpy.context.scene.objects if o.instance_type=='COLLECTION'];meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];screenmeshes=[o for o in meshes if o.get('texture_exception')];structural=[o for o in meshes if not o.get('texture_exception')]
uv=[v.audit_palette_uv(o) for o in structural];facebad=[r for r in uv if r['valid_island_polygon_count']!=r['polygon_count']]
replayerr=[]
for rec in records:
 o=bpy.data.objects[rec['instance_id']];m=Matrix(rec['matrix_room_local']);replayerr.append(max(abs(m[i][j]-o.matrix_world[i][j]) for i in range(4) for j in range(4)))
def bounds(obs):
 pts=[o.matrix_world@m.matrix_basis@Vector(c) for o in obs for m in o.instance_collection.objects for c in m.bound_box]
 return [[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
deck=bounds([o for o in inst if o.instance_collection.name in ('输出资产包_deck_armor_5m','输出资产包_deck_emblem_5m')]);bridges=[bounds([o for o in inst if o.instance_collection.name=='输出资产包_bridge_deck_5m' and o.location.x*s>0]) for s in (-1,1)]
family={}
for c in catalog:family[c['component_family']]=family.get(c['component_family'],0)+1
checks={'locked_objects_unchanged':not changed,'user_screen_poses_exact':max(screen_errors.values())<1e-6,'component_budget':len(catalog)==len(plan['components'])<=50,'family_budget':max(family.values())<=3,'instance_replay':len(inst)==len(records) and max(replayerr)<1e-6,'unit_scale':all(max(abs(x-1) for x in o.scale)<1e-5 for o in inst),'four_shared_structural_materials':len({m.name for o in structural for m in o.data.materials})==4,'structural_palette_uv_all_faces':not facebad,'only_three_screen_exceptions':len(screenmeshes)==3,'material_total_seven':len(bpy.data.materials)==7,'platform_25x25':abs(deck[1][0]-deck[0][0]-25)<1e-5 and abs(deck[1][1]-deck[0][1]-25)<1e-5,'bridges_20x5':all(abs(b[1][0]-b[0][0]-20)<1e-5 and abs(b[1][1]-b[0][1]-5)<1e-5 for b in bridges)}
packages=[]
for c in catalog:
 col=bpy.data.collections[c['collection']];pts=[o.matrix_basis@v.co for o in col.objects for v in o.data.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 packages.append({'slug':c['slug'],'nonempty':bool(len(col.objects)),'origin_bottom_center':abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,'identity_mesh':all(max(abs(o.matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-6 for o in col.objects),'zero_collection_offset':col.instance_offset.length<1e-6,'unique_mesh_ownership':all(len(o.users_collection)==1 for o in col.objects)})
checks['all_component_geometry_contracts']=all(all(p[k] for k in ('nonempty','origin_bottom_center','identity_mesh','zero_collection_offset','unique_mesh_ownership')) for p in packages)
screens=[]
for o in screenmeshes:
 m=o.data.materials[0];nodes=m.node_tree.nodes;img=next(n.image for n in nodes if n.type=='TEX_IMAGE');layer=o.data.uv_layers.active
 screens.append({'object':o.name,'uv_layer':layer.name,'uv_area':v.uv_polygon_area([layer.data[i].uv for i in range(4)]),'texture_path':bpy.path.abspath(img.filepath),'texture_exists':Path(bpy.path.abspath(img.filepath)).is_file(),'resolution':list(img.size),'external_not_packed':img.packed_file is None})
checks['screen_uv_and_external_textures']=all(s['uv_layer']=='ScreenUV' and s['uv_area']>.99 and s['texture_exists'] and s['external_not_packed'] and min(s['resolution'])>=1024 for s in screens)
phases=[]
for frame in (1,61,121):
 bpy.context.scene.frame_set(frame);phases.append({'frame':frame,'phase':[o.data.materials[0].node_tree.nodes['ScanPhase'].outputs[0].default_value for o in screenmeshes]})
checks['native_scan_animation_changes']=all(abs(v-.5)<1e-5 for v in phases[1]['phase']) and all(abs(v)<1e-5 for v in phases[0]['phase'])
bpy.context.scene.frame_set(1);dg=bpy.context.evaluated_depsgraph_get()
right=bpy.context.scene.ray_cast(dg,Vector((31.0,.25,2.5)),Vector((1,0,0)),distance=8)
left=bpy.context.scene.ray_cast(dg,Vector((-31.0,.25,2.5)),Vector((-1,0,0)),distance=5)
checks['right_exit_closed_geometry']=bool(right[0]);checks['left_exit_closed_leaf_geometry']=left[0]
report={'checks':checks,'unexpected_locked_changes':changed,'locked_count':len(scope['before']),'authorized_host_changes':scope.get('authorized_door_host_changes',[]),'screen_pose_max_errors':screen_errors,'structural_uv_valid_faces':sum(r['valid_island_polygon_count'] for r in uv),'structural_total_faces':sum(r['polygon_count'] for r in uv),'screen_texture_exceptions':screens,'native_shader_phase_samples':phases,'package_checks':packages,'component_count':len(catalog),'instance_count':len(inst),'formal_instances':sum(not r['draft'] for r in records),'draft_instances':sum(r['draft'] for r in records),'bridge_bounds':bridges,'platform_bounds':deck,'right_exit_hit':right[4].name if right[0] else None,'left_exit_hit':left[4].name if left[0] else None,'runtime_validation':'not performed; Blender source only'}
standalone=[]
for c in catalog:
 bpy.ops.wm.open_mainfile(filepath=c['component_blend']);ms=[o for o in bpy.context.scene.objects if o.type=='MESH'];bad=[]
 for o in ms:
  if o.get('texture_exception'):continue
  a=v.audit_palette_uv(o)
  if a['valid_island_polygon_count']!=a['polygon_count']:bad.append(o.name)
 files=[{'path':bpy.path.abspath(im.filepath),'exists':Path(bpy.path.abspath(im.filepath)).is_file()} for im in bpy.data.images if im.source=='FILE']
 standalone.append({'slug':c['slug'],'loaded':True,'mesh_count':len(ms),'has_camera':bpy.context.scene.camera is not None,'uv_failures':bad,'images':files})
checks['independent_packages_reopen']=all(p['mesh_count'] and p['has_camera'] and not p['uv_failures'] and all(im['exists'] for im in p['images']) for p in standalone)
report['standalone_packages']=standalone;report['passed']=all(checks.values());(W/'acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'passed':report['passed'],'checks':checks,'scope_count':report['locked_count'],'uv_faces':report['structural_total_faces']},ensure_ascii=False))
if not report['passed']:raise RuntimeError('V023 VERIFICATION FAILED')




