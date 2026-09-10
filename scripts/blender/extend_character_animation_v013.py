"""Preserve v012 walk, add jog, full-loop preview scenes and runtime pistol reference."""
from pathlib import Path
import sys, json, math, hashlib, shutil, re
sys.dont_write_bytecode=True
import bpy
from mathutils import Matrix, Vector, Euler
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_character_bundle import signature
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
PACKAGE=BASE/'v013'
SOURCE=BASE/'v012/source/animation/chr_bunny01_animation_v012.blend'
MODEL=PACKAGE/'source/model/chr_bunny01_model_v013.blend'
TARGET=PACKAGE/'source/animation/chr_bunny01_animation_v013.blend'
OUT=ROOT/'outputs/character_pipeline/v013'
WEAPON_SCENE=ROOT/'assets/art/weapons/weapon_3d/runtime/hair_dryer/wpn_hair_dryer_root_top3d_v001.tscn'
assert not TARGET.exists() or '--replace-generated' in sys.argv,'Do not overwrite artist work'
weapon_text=WEAPON_SCENE.read_text()
weapon_glb=ROOT/re.search(r'path="res://([^"]+\.glb)"',weapon_text)[1]
offset_match=re.search(r'\[node name="VisualRoot"[^\n]+\]\nposition = Vector3\(([^)]+)\)',weapon_text)
gx,gy,gz=map(float,offset_match[1].split(','))
offset=Vector((gx,-gz,gy))
scale=1.5/2.475
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
if rig.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
sig=signature(rig); rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
original={a['state_id']:a for a in bpy.data.actions if 'state_id' in a and a.library is None}
assert set(original)=={'moving','idle','armed_idle','armed_moving'}
initial_range=[scene.frame_start,scene.frame_end]
idle_curve_cycles={s:all(any(m.type=='CYCLES' for m in c.modifiers) for c in original[s].fcurves) for s in ['idle','armed_idle']}
def sample(action,t):
    rig.animation_data.action=action
    f=1+t*(action.frame_range.y-action.frame_range.x)
    scene.frame_set(int(f),subframe=f-int(f))
    return {p.name:p.matrix.copy() for p in rig.pose.bones}
def tr(p=(0,0,0),r=(0,0,0)):
    return Matrix.Translation(Vector(p))@Euler(r).to_matrix().to_4x4()
specs={'walking':('moving',60),'idle':('idle',192),'armed_idle':('armed_idle',192),
       'armed_walking':('armed_moving',60),'moving':('moving',42),'armed_moving':('armed_moving',42)}
actions={}
for state,(source,period) in specs.items():
    armed=state.startswith('armed'); jog=state in ['moving','armed_moving']
    poses=[sample(original[source],i/period) for i in range(period+1)]
    if state in ['walking','idle']:
        action=original[source].copy() # Preserve existing artist curves exactly.
    else:
        action=bpy.data.actions.new('NewAction')
        for i,posed in enumerate(poses):
            t=i/period; w=math.tau*t; bounce=.5-.5*math.cos(2*w)
            if jog:
                for name in ['waist','chest']:
                    posed[name]=tr((0,0,.010+.017*bounce),(-.035,0,0))@posed[name]
                delta=tr((0,0,.008+.012*bounce),(-.018,0,0))
                for name in ['head','ear_l','ear_r']: posed[name]=delta@posed[name]
                for side,sign in [('l',-1),('r',1)]:
                    phase=(t+(0 if side=='l' else .5))%1
                    foot=rest['foot_'+side].translation.copy()
                    if phase<.43:
                        u=phase/.43; ease=u*u*(3-2*u); foot.y+=.135-.270*ease
                    else:
                        u=(phase-.43)/.57; ease=u*u*(3-2*u)
                        foot.y+=-.135+.270*ease; foot.z+=.105*math.sin(math.pi*u)**2
                    posed['foot_'+side]=tr(foot)@rest['foot_'+side].to_3x3().to_4x4()
                    if not (armed and side=='r'):
                        posed['hand_'+side].translation+=Vector((0,sign*.04*math.sin(w),.014+.012*bounce))
                    ear='ear_'+side
                    posed[ear]=posed[ear]@tr(r=(.035*math.sin(2*w-.8),0,sign*.015*math.sin(2*w-1.1)))
            if armed:
                shift=Vector((0,0,.115))
                posed['hand_r'].translation+=shift
                for prefix in ['thumb','index','fingers']:
                    for segment in ['01','02']: posed[prefix+'_'+segment+'_r'].translation+=shift
            # Re-articulate unweighted helper limbs to corrected endpoints; unit scale.
            for side,sign in [('l',-1),('r',1)]:
                for upper,lower,end,origin,bend in [
                    ('upper_arm_','forearm_','hand_',posed['chest']@rest['chest'].inverted(),Vector((sign*.025,-.025,0))),
                    ('thigh_','shin_','foot_',posed['waist']@rest['waist'].inverted(),Vector((0,.020,0)))]:
                    start=origin@rest[upper+side].translation; target=posed[end+side].translation
                    middle=(start+target)*.5+bend
                    for name,p,q in [(upper+side,start,middle),(lower+side,middle,target)]:
                        posed[name]=Matrix.LocRotScale(p,Vector((0,1,0)).rotation_difference((q-p).normalized()),Vector((1,1,1)))
        rig.animation_data.action=action
        previous={}
        for i,posed in enumerate(poses):
            for b in rig.data.bones:
                parent=b.parent.name if b.parent else None; p=rig.pose.bones[b.name]
                p.rotation_mode='QUATERNION'
                p.matrix_basis=b.convert_local_to_pose(posed[b.name],rest[b.name],parent_matrix=posed[parent] if parent else Matrix.Identity(4),parent_matrix_local=rest[parent] if parent else Matrix.Identity(4),invert=True)
                p.scale=(1,1,1)
                if b.name in previous and previous[b.name].dot(p.rotation_quaternion)<0: p.rotation_quaternion.negate()
                previous[b.name]=p.rotation_quaternion.copy()
                for prop in ['location','rotation_quaternion','scale']: p.keyframe_insert(prop,frame=i+1,group=b.name)
    action.name='anim_bunny01_'+state+'_v013'; action.use_fake_user=True
    action['state_id']=state; action['duration']=period/60; action['loop']=True
    action['weapon_class']='sidearm' if armed else 'unarmed'
    action['speed_role']='normal_jog' if jog else 'slow_walk' if 'walking' in state else 'idle'
    action.use_frame_range=True; action.frame_start=1; action.frame_end=period+1
    action.use_cyclic=True
    for curve in action.fcurves:
        if not any(m.type=='CYCLES' for m in curve.modifiers): curve.modifiers.new('CYCLES')
        for m in curve.modifiers:
            if m.type=='CYCLES': m.mode_before='REPEAT'; m.mode_after='REPEAT'
        if state not in ['walking','idle']:
            for key in curve.keyframe_points:
                key.interpolation='BEZIER'; key.handle_left_type=key.handle_right_type='AUTO_CLAMPED'
    actions[state]=action
rig.animation_data.action=actions['moving']
# Remove only old local action copies from this new file, never source v012.
for action in original.values(): bpy.data.actions.remove(action)
MODEL.parent.mkdir(parents=True,exist_ok=True); TARGET.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(BASE/'v012/source/model/chr_bunny01_model_v012.blend',MODEL)
for lib in bpy.data.libraries:
    if 'chr_bunny01_model_v012.blend' in lib.filepath: lib.filepath=str(MODEL)
scene['model_source']='../model/chr_bunny01_model_v013.blend'
scene['production_status']='authored_pending_export'
scene['preview_help']='Choose scene: each clip has its own full looping range. Preview pistol follows hand_r origin, not bone tail. Runtime aim/recoil overlays excluded.'
# Import exact Godot mesh; Blender glTF importer performs Y-up -> Z-up conversion.
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(weapon_glb))
imported=[o for o in bpy.data.objects if o not in before]
gun_collection=bpy.data.collections.new('90_预览环境_不导出')
gun_collection['export']=False; gun_collection['preview_only']=True
scene.collection.children.link(gun_collection)
gun=bpy.data.objects.new('PREVIEW_GripSocket_bp_pistol',None); gun_collection.objects.link(gun)
gun['preview_only']=True; gun['export']=False; gun['source_scene']=str(WEAPON_SCENE.relative_to(ROOT))
gun['grip_contract']='hand_r head = cuff center = Godot GripSocket; fixed baseline aim +Y'
gun.scale=(scale,)*3
constraint=gun.constraints.new('COPY_LOCATION'); constraint.name='Godot_GripSocket_右腕环中心'
constraint.target=rig; constraint.subtarget='hand_r'; constraint.head_tail=0
constraint.target_space='WORLD'; constraint.owner_space='WORLD'
for obj in imported:
    for c in list(obj.users_collection): c.objects.unlink(obj)
    gun_collection.objects.link(obj); obj['preview_only']=True; obj['export']=False
    if obj.parent not in imported:
        matrix=obj.matrix_world.copy(); obj.parent=gun; obj.matrix_parent_inverse=Matrix.Identity(4)
        obj.matrix_basis=Matrix.Translation(offset)@matrix
    obj.hide_set(False); obj.hide_render=False
    if obj.type=='MESH':
        for material in obj.data.materials:
            if material and material.use_nodes:
                bsdf=next((n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
                if bsdf: material.diffuse_color=bsdf.inputs['Base Color'].default_value
# Separate scenes avoid Action Editor changes leaving the short walk playback range.
template=list(scene.objects)
titles={'walking':'01_慢走','moving':'02_正常移动_小跑','idle':'03_待机_循环',
        'armed_walking':'04_单手持枪_慢走','armed_moving':'05_单手持枪_小跑','armed_idle':'06_单手持枪_待机循环'}
scenes={}; rigs={}; guns={}
for state in ['walking','moving','idle','armed_walking','armed_moving','armed_idle']:
    s=bpy.data.scenes.new(titles[state]); scenes[state]=s
    for k in scene.keys():
        if isinstance(scene[k],(str,int,float,bool)): s[k]=scene[k]
    s['preview_clip']=state; s.unit_settings.system='METRIC'; s.render.fps=60
    s.frame_start=1; s.frame_end=specs[state][1] # Exclude duplicate endpoint on playback.
    s.use_preview_range=True; s.frame_preview_start=1; s.frame_preview_end=s.frame_end
    mapping={}
    model_c=bpy.data.collections.new('01_角色预览_'+state); s.collection.children.link(model_c)
    preview_c=bpy.data.collections.new('90_预览环境_不导出_'+state); s.collection.children.link(preview_c)
    preview_c['preview_only']=True; preview_c['export']=False
    for obj in template:
        if obj.get('preview_only') and not state.startswith('armed'): continue
        copy=obj.copy(); mapping[obj]=copy
        (preview_c if obj.get('preview_only') else model_c).objects.link(copy)
    r=mapping[rig]; rigs[state]=r; r.name='RIG_bunny01_'+state
    r.animation_data_create(); r.animation_data.action=actions[state]
    for original_obj,copy in mapping.items():
        if original_obj.parent in mapping: copy.parent=mapping[original_obj.parent]
        for mod in copy.modifiers:
            if mod.type=='ARMATURE': mod.object=r
        for con in copy.constraints:
            if getattr(con,'target',None)==rig: con.target=r
        if copy.get('variant_id')=='chibi_anime': copy.hide_render=True; copy.hide_viewport=True
    if gun in mapping: guns[state]=mapping[gun]
    s.frame_set(1)
    s.view_layers[0].objects.active=r; r.select_set(True,view_layer=s.view_layers[0])
bpy.context.window.scene=scenes['moving']
bpy.data.scenes.remove(scene)
# Discard orphan template objects in the NEW file so no duplicate exporter armature remains.
for obj in template:
    if obj.users==0: bpy.data.objects.remove(obj)
bpy.context.view_layer.objects.active=rigs['moving']
bpy.ops.object.mode_set(mode='POSE')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
# Verify saved file, multi-period loop evaluation, ground, model signatures, gun origin.
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
OUT.mkdir(parents=True,exist_ok=True)
report={'skeleton_sha256':sig,'previous_scene_range':initial_range,'previous_idle_cycles':idle_curve_cycles,
    'model_identical_to_v012':hashlib.sha256(MODEL.read_bytes()).hexdigest()==hashlib.sha256((BASE/'v012/source/model/chr_bunny01_model_v012.blend').read_bytes()).hexdigest(),
    'weapon':{'logic_id':'bp_pistol','scene':str(WEAPON_SCENE.relative_to(ROOT)),'glb':str(weapon_glb.relative_to(ROOT)),
              'scale_in_authoring_space':scale,'godot_visual_offset':[gx,gy,gz],'blender_visual_offset':list(offset),'mount':'hand_r head / cuff center; COPY_LOCATION, baseline aim +Y'},'clips':{}}
for state,title in titles.items():
    s=bpy.data.scenes[title]; bpy.context.window.scene=s
    r=next(o for o in s.objects if o.type=='ARMATURE'); assert signature(r)==sig
    period=specs[state][1]; first=None; max_scale=0; min_ground=1; grip_error=0; samples={}
    for f in range(1,period*2+2):
        s.frame_set(f)
        depsgraph=bpy.context.evaluated_depsgraph_get()
        evaluated_rig=r.evaluated_get(depsgraph)
        matrices={p.name:p.matrix.copy() for p in evaluated_rig.pose.bones}
        if first is None: first=matrices
        if f<=period: samples[f]=matrices
        elif f<=period*2:
            prior=samples[f-period]
            assert max(abs(matrices[n][a][b]-prior[n][a][b]) for n in prior for a in range(4) for b in range(4))<1e-5
        for matrix in matrices.values(): max_scale=max(max_scale,max(abs(v-1) for v in matrix.to_scale()))
        for side in ['l','r']: min_ground=min(min_ground,matrices['foot_'+side].translation.z)
        if state.startswith('armed'):
            g=next(o for o in s.objects if o.name.startswith('PREVIEW_GripSocket'))
            grip_error=max(grip_error,(g.evaluated_get(depsgraph).matrix_world.translation-(evaluated_rig.matrix_world@matrices['hand_r'].translation)).length)
    seam=max(abs(matrices[n][a][b]-first[n][a][b]) for n in first for a in range(4) for b in range(4))
    assert max_scale<1e-5 and min_ground>-.00001 and grip_error<1e-5 and seam<1e-5,(state,max_scale,min_ground,grip_error,seam)
    report['clips'][state]={'period_frames':period,'duration':period/60,'scene':title,'two_periods_match':True,'loop_seam':seam,'scale_error':max_scale,'min_ground':min_ground,'grip_error':grip_error}
    s.render.engine='BLENDER_WORKBENCH'; s.display.shading.light='STUDIO'; s.display.shading.color_type='MATERIAL'; s.display.shading.show_cavity=True
    s.render.resolution_x=600; s.render.resolution_y=620; s.render.resolution_percentage=100
    camera=bpy.data.cameras.new('QA'); cam=bpy.data.objects.new('QA',camera); s.collection.objects.link(cam)
    cam.location=(2.6,4,1.9); cam.rotation_euler=(Vector((0,.15,.72))-cam.location).to_track_quat('-Z','Y').to_euler()
    camera.type='ORTHO'; camera.ortho_scale=1.9; s.camera=cam
    folder=OUT/state; folder.mkdir(exist_ok=True)
    for i in range(30):
        frame=1+i*period/30; s.frame_set(int(frame),subframe=frame-int(frame))
        s.render.filepath=str(folder/f'{i:03}.png'); bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)
(OUT/'animation_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger={'asset_id':'CHR-PLY-CAPSULE01-3D-BUNNY01','version':'v013','status':'authored_pending_export',
        'runtime_active_version':'v011','skeleton_id':'SKEL-BUNNY01-004','skeleton_sha256':sig,
        'files':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [MODEL,TARGET,WEAPON_SCENE,weapon_glb]],
        'validation':report,'export_requirements':['Exclude all preview_only objects and preview scenes; export one matching rig only.',
        'body maps to chest; walking/armed_walking are slow; moving/armed_moving are normal jog; sidearm only. Runtime integration not performed.']}
(PACKAGE/'character_transfer_ledger_v013.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('V013_SIX_CLIPS_VALIDATED',TARGET)
