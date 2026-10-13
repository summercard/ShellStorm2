import bpy,json,math,sys,shutil,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(r'I:/工作项目/shellstrom2/ShellStorm2');sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_detail_v023/session.json').parent
D=ROOT/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v023'
B=D/'Boss房B_显示器电缆与矩阵深化_v023.blend'
state=json.loads((W/'geometry_state.json').read_text(encoding='utf-8'));meta=state['meta'];plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
scene=bpy.context.scene;source=bpy.data.collections['01_制作组件_母版与可编辑零件'];out=bpy.data.collections['02_游戏输出_组件实例布局'];show=bpy.data.collections['90_展示与验收_灯光相机'];masters={s:bpy.data.collections[n] for s,n in state['master_names'].items()}
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
def aim(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
screen_entries=[]
for index,side in enumerate(('left','center','right')):
 slug='screen_'+side;info=next(p for p in plan['components'] if p['slug']==slug)
 tex=D/'textures'/('screen_'+side+'.png');tex.parent.mkdir(exist_ok=True);shutil.copyfile(W/tex.name,tex)
 image=bpy.data.images.load(str(tex),check_existing=True);image.filepath='//textures/'+tex.name
 mat=bpy.data.materials.new(f'0{index+5}_动态屏幕_{side}_自发光');mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links;nodes.clear()
 output=nodes.new('ShaderNodeOutputMaterial');em=nodes.new('ShaderNodeEmission');links.new(em.outputs[0],output.inputs['Surface'])
 uv=nodes.new('ShaderNodeUVMap');uv.uv_map='ScreenUV';uv.label='独立屏幕UV';img=nodes.new('ShaderNodeTexImage');img.image=image;img.interpolation='Linear';img.extension='EXTEND';links.new(uv.outputs[0],img.inputs[0]);links.new(img.outputs['Color'],em.inputs['Color'])
 sep=nodes.new('ShaderNodeSeparateXYZ');links.new(uv.outputs[0],sep.inputs[0])
 phase=nodes.new('ShaderNodeValue');phase.name='ScanPhase';phase.label='扫描相位_120帧循环';phase.outputs[0].default_value=0;phase.outputs[0].keyframe_insert('default_value',frame=1);phase.outputs[0].default_value=1;phase.outputs[0].keyframe_insert('default_value',frame=121)
 for fc in mat.node_tree.animation_data.action.fcurves:
  for kp in fc.keyframe_points:kp.interpolation='LINEAR'
  fc.modifiers.new('CYCLES')
 def mathnode(op,a=None,b=None):
  n=nodes.new('ShaderNodeMath');n.operation=op
  for k,x in enumerate((a,b)):
   if x is None:continue
   if isinstance(x,(float,int)):n.inputs[k].default_value=x
   else:links.new(x,n.inputs[k])
  return n.outputs[0]
 p=mathnode('FRACT',mathnode('ADD',phase.outputs[0],index*.17));delta=mathnode('ABSOLUTE',mathnode('SUBTRACT',sep.outputs['Y'],p));line=mathnode('LESS_THAN',delta,.008)
 raster=mathnode('SINE',mathnode('MULTIPLY',sep.outputs['Y'],1100));raster=mathnode('MULTIPLY_ADD',raster,.035);raster.node.inputs[2].default_value=1.15
 strength=mathnode('ADD',raster,mathnode('MULTIPLY',line,.35));links.new(strength,em.inputs['Strength'])
 for j,n in enumerate(nodes):n.location=(j%6*220,-j//6*180)
 parent=bpy.data.collections.new('组件_'+info['name_zh']);source.children.link(parent);c=bpy.data.collections.new('输出资产包_'+slug);parent.children.link(c);c['component_id']=info['component_id']
 me=bpy.data.meshes.new(info['name_zh']+'_ScreenUV');me.from_pydata([(-5.17,0,0),(5.17,0,0),(5.17,0,6.32),(-5.17,0,6.32)],[],[(0,1,2,3)]);me.update();u=me.uv_layers.new(name='ScreenUV');u.active_render=True
 for i,co in enumerate(((0,0),(1,0),(1,1),(0,1))):u.data[i].uv=co
 me.materials.append(mat);mesh=bpy.data.objects.new(info['name_zh']+'_自发光_贴图输出',me);c.objects.link(mesh);mesh['texture_exception']='User-authorized Image-2 electronic display; uses ScreenUV rather than PaletteUV';mesh['animation_contract']='screen_dynamic_v1'
 screen=bpy.data.objects[state['screen_objects'][index]];anchor=Vector(meta['monitor_chassis']['anchor']);local=Vector((0,-.545, .34))-anchor
 inst=bpy.data.objects.new(info['name_zh']+'_内容实例',None);out.objects.link(inst);inst.instance_type='COLLECTION';inst.instance_collection=c;inst.matrix_world=screen.matrix_world@Matrix.Translation(local);inst['screen_anchor']=screen.name;inst['component_id']=info['component_id']
 masters[slug]=c;meta[slug]={'definition':info,'bounds_size_m':[10.34,0,6.32],'part_count':1,'anchor':[0,0,0]}
 screen_entries.append({'screen_anchor':screen.name,'content_instance':inst.name,'texture':str(tex),'texture_sha256':hashlib.sha256(tex.read_bytes()).hexdigest(),'material':mat.name,'uv_layer':'ScreenUV','local_matrix':[list(r) for r in Matrix.Translation(local)],'scan_phase_node':'ScanPhase','loop_frames':120,'fps':24,'generated_by':'gpt-image-2 via sofunny-image skill'})
 # Red spill is preview lighting only, not part of the exportable component.
 ld=bpy.data.lights.new('屏幕红光反射_'+side,'AREA');ld.energy=1450;ld.color=(1,.013,.009);ld.shape='RECTANGLE';ld.size=8;ld.size_y=4.8
 lo=bpy.data.objects.new('屏幕红光反射_'+side,ld);show.objects.link(lo);lo.location=screen.matrix_world@Vector((0,-1,3.5));aim(lo,screen.matrix_world@Vector((0,-8,1)))
scene.frame_set(1)
def camera(n,loc,t,lens):
 cd=bpy.data.cameras.new(n);o=bpy.data.objects.new(n,cd);show.objects.link(o);o.location=loc;aim(o,t);cd.lens=lens;cd.clip_end=500;return o
camera('验收_显示器电缆',(0,-28,13),(0,10,7),38)
camera('验收_右侧出口',(26,-10,6),(33.0,0,3),43)
camera('验收_左侧出口',(-26,-10,6),(-33.0,0,3),43)
camera('验收_错层机柜',(25,-35,6),(9,-7,-10),39)
scene.camera=bpy.data.objects['参考镜头_全景'];scene.cycles.samples=32
instances=[]
for o in bpy.context.scene.objects:
 if o.instance_type!='COLLECTION':continue
 slug=next((s for s,c in masters.items() if c==o.instance_collection),None)
 assert slug is not None,(o.name,o.instance_collection.name)
 euler=o.rotation_euler;instances.append({'instance_id':o.name,'component_id':meta[slug]['definition']['component_id'],'slug':slug,'position_m':list(o.location),'rotation_euler_xyz_deg':[math.degrees(v) for v in euler],'matrix_room_local':[list(r) for r in o.matrix_world],'scale':list(o.scale),'draft':meta[slug]['definition']['category']=='draft','user_pose_locked':bool(o.get('user_pose_locked',False))})
catalog=[]
for slug,c in masters.items():
 pts=[o.matrix_basis@v.co for o in c.objects for v in o.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 rec={**meta[slug]['definition'],'version':'v023','collection':c.name,'source_blend':str(B),'component_blend':str(D/'component_packages'/slug/(slug+'.blend')),'objects':[o.name for o in c.objects],'bounds_size_m':[hi[i]-lo[i] for i in range(3)],'bounds_min':lo,'bounds_max':hi,'local_origin':[0,0,0],'instance_offset':list(c.instance_offset),'instance_count':sum(i['slug']==slug for i in instances),'materials':sorted({m.name for o in c.objects for m in o.data.materials}),'collision_owner':'godot_wrapper_pending','registration_status':'未登记','runtime_connected':False,'texture_exception':slug.startswith('screen_'),'palette_uv_layer':None if slug.startswith('screen_') else 'PaletteUV','animation':'shader_scan_preview' if slug.startswith('screen_') else None,'geometry_fingerprint':hashlib.sha256(str([(o.name,[tuple(v.co) for v in o.data.vertices]) for o in c.objects]).encode()).hexdigest()}
 write(D/'component_packages'/slug/'asset_manifest.json',rec);catalog.append(rec)
write(D/'component_catalog.json',{'component_count':len(catalog),'components':catalog})
write(D/'component_instances.json',{'schema':'shellstorm2.battle.component_instances','schema_version':2,'library':'v023','block_id':'expedition','coordinate_contract':{'source_space':'blender_room_local','origin_mode':'template_bounds_center_at_walk_plane','walk_plane_z_m':0,'blender_plane':'XY','blender_up':'+Z','transform_authority':'matrix_room_local, full 3D rigid transforms; do not reduce tilted screen or cable poses to a yaw angle','godot_mapping':'C @ M @ inverse(C), C maps (bx,by,bz) to (bx,bz,-by)'},'instances':instances})
write(D/'screen_animation_contract.json',{'schema':'screen_dynamic_v1','scope':'Blender animated preview and future engine handoff, no runtime integration claimed','frames':[1,240],'fps':24,'phase_loop_frames':120,'screens':screen_entries,'controls':['base_texture','scan_phase_0_1','scan_width_uv_0_008','scan_emission_boost_0_35','raster_lines','alarm_tint_future'],'future_animation_options':['replace Image Texture with movie or image sequence','recreate procedural scan with runtime shader','add separate cube/orbit overlay without rebuilding chassis'],'door_leaf_contract':'independent leaf collections, local sliding axis and open/closed positions stored on instances; no gameplay door state machine authored','material_policy_exception':'Only three screen surfaces use the three image materials and ScreenUV; all structural meshes retain original four shared palette roles.'})
for side in ('left','center','right'):shutil.copyfile(W/('prompt_'+side+'.txt'),D/'textures'/('prompt_'+side+'.txt'))
write(D/'room_type_manifest.json',{'room_type':'BOSS_ROOM','variant':'B','version':'v023','block_id':'expedition','level_id':'expedition_01','design_scope':'scene_art','asset_ledger':'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx','registration_status':'未登记','source_blend':str(B),'whitebox_source':str(ROOT/'art_source/design/whitebox/tower_zones/expedition_01/boss_deep_chamber/layout_contract.json'),'user_pose_source':str(W/'user_adjusted_before.blend'),'dimensions_m':{'platform':[25,25],'bridges_each':[20,5]},'component_budget':plan['component_budget'],'scope':'monitor housings, content and cables; staggered compute towers; side exit doors; rear matrix','source_status':'awaiting final visual and technical verification','runtime_connected':False,'formal_godot_scene_modified':False,'material_roles':7,'texture_exception':'3 user-authorized Image-2 electronic display surfaces with ScreenUV','remaining_draft':['entrance long stair','plain shaft wall backing']})
(D/'component_tree.txt').write_text('\n'.join(f'{r["category"]}/{r["slug"]} | {r["name_zh"]} | {r["instance_count"]}' for r in catalog),encoding='utf-8')
# Save independent package scenes with preview camera, and relative external texture dependencies.
for rec in catalog:
 c=masters[rec['slug']];sc=bpy.data.scenes.new('Component_'+rec['slug']);sc.collection.children.link(c);sc.world=scene.world;sc.unit_settings.system='METRIC'
 r=max(rec['bounds_size_m']);target=Vector((0,0,rec['bounds_size_m'][2]/2));cd=bpy.data.cameras.new('组件预览');cam=bpy.data.objects.new('组件预览',cd);sc.collection.objects.link(cam);cam.location=target+Vector((r*.9,-r*1.8,r*.8));aim(cam,target);cd.type='ORTHO';cd.ortho_scale=r*1.7;sc.camera=cam
 ld=bpy.data.lights.new('组件柔光','AREA');ld.energy=r*r*100;ld.size=r;lamp=bpy.data.objects.new('组件柔光',ld);sc.collection.objects.link(lamp);lamp.location=target+Vector((r,-r,r));aim(lamp,target)
 sc.render.engine='CYCLES';sc.cycles.samples=16;sc.render.resolution_x=640;sc.render.resolution_y=640;sc.render.resolution_percentage=100
 # Relative image references are resolved from the main source when library writing.
 bpy.data.libraries.write(rec['component_blend'],{sc},path_remap='RELATIVE',fake_user=True)
 bpy.data.scenes.remove(sc);bpy.data.objects.remove(cam,do_unlink=True);bpy.data.objects.remove(lamp,do_unlink=True)
scene.frame_set(1);scene.camera=bpy.data.objects['参考镜头_全景']
bpy.ops.wm.save_as_mainfile(filepath=str(B))
print('FINISHED_SOURCE',str(B),'components',len(catalog),'instances',len(instances),'materials',len(bpy.data.materials))
