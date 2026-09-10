"""One-time v012 animation authoring; refuses to overwrite artist work."""
from pathlib import Path
import sys, math, json, hashlib
sys.dont_write_bytecode=True
import bpy
from mathutils import Matrix, Vector, Euler, Quaternion
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_character_bundle import signature
ROOT=Path(__file__).resolve().parents[2]
PACKAGE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v012'
MODEL=PACKAGE/'source/model/chr_bunny01_model_v012.blend'
TARGET=PACKAGE/'source/animation/chr_bunny01_animation_v012.blend'
OUT=ROOT/'outputs/character_pipeline/v012/animation'
assert not TARGET.exists(),'Existing animation must not be overwritten'
model_hash=hashlib.sha256(MODEL.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(MODEL))
source_rig=bpy.data.objects['RIG_bunny01']
sig=signature(source_rig)
metadata={k:bpy.context.scene[k] for k in bpy.context.scene.keys() if isinstance(bpy.context.scene[k],(str,int,float,bool))}
bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(str(MODEL),link=True) as (_,dest): dest.collections=['01_部件']
linked=dest.collections[0]
scene=bpy.context.scene
scene.collection.children.link(linked)
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE').copy()
rig.data=rig.data.copy(); rig.name='RIG_bunny01_animation'
rig.animation_data_clear()
coll=bpy.data.collections.new('00_共享骨架'); scene.collection.children.link(coll); coll.objects.link(rig)
preview=bpy.data.collections.new('01_动作预览_关联模型'); scene.collection.children.link(preview)
for obj in list(linked.all_objects):
    if obj.type!='MESH': continue
    copy=obj.copy(); preview.objects.link(copy); copy.parent=rig
    for mod in copy.modifiers:
        if mod.type=='ARMATURE': mod.object=rig
    copy.hide_render=obj.get('variant_id')=='chibi_anime'; copy.hide_set(copy.hide_render)
scene.collection.children.unlink(linked)
for k,v in metadata.items(): scene[k]=v
scene['file_role']='animation'; scene['model_source']='../model/chr_bunny01_model_v012.blend'
scene['production_status']='authored_pending_export'; scene['weapon_pose_scope']='right_hand_sidearm_only'
scene.unit_settings.system='METRIC'; scene.render.fps=60
rig.animation_data_create()
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
def tr(p=(0,0,0),r=(0,0,0)):
    return Matrix.Translation(Vector(p))@Euler(r).to_matrix().to_4x4()
def cycle(state,t):
    moving='moving' in state; armed=state.startswith('armed')
    w=math.tau*t; stride=math.sin(w); bounce=.5-.5*math.cos(2*w)
    posed={n:m.copy() for n,m in rest.items()}
    # Pelvis transfers weight; chest counter-turn is mild, without mesh scaling.
    waist_delta=tr((.014*stride if moving else .005*math.sin(w),0,
        .010+.012*bounce if moving else .004*math.sin(w)),
        (-.015 if moving else .008*math.sin(w),.025*stride if moving else .008*math.sin(w),
         .045*stride if moving else .012*math.sin(w)))
    posed['waist']=waist_delta@rest['waist']
    posed['chest']=waist_delta@rest['chest']@tr(r=(.012*math.sin(2*w-.3) if moving else .012*math.sin(w-.2),0,-.075*stride if moving else -.018*math.sin(w-.2)))
    head_delta=tr((.008*math.sin(w-.25) if moving else .004*math.sin(w-.3),0,
        .008+.010*bounce if moving else .006*math.sin(w-.25)),
        (.012*math.sin(2*w-.4) if moving else .012*math.sin(w-.4),.008*math.sin(w),-.016*stride))
    posed['head']=head_delta@rest['head']
    for side,sign in [('l',-1),('r',1)]:
        phase=(t+(0 if side=='l' else .5))%1
        foot=rest['foot_'+side].translation.copy()
        if moving:
            # 60% grounded stance, 40% lifted recovery; zero velocity at contact.
            if phase<.60:
                u=phase/.60; ease=u*u*(3-2*u)
                foot.y+=.105-.210*ease; lift=0
            else:
                u=(phase-.60)/.40; ease=u*u*(3-2*u)
                foot.y+=-.105+.210*ease; lift=.075*math.sin(math.pi*u)**2
            foot.z+=lift
        posed['foot_'+side]=tr(foot)@rest['foot_'+side].to_3x3().to_4x4()
        wrist=rest['hand_'+side].translation.copy()
        if armed and side=='r':
            wrist=Vector((.235,.335,.285))
            wrist.z+=.006*bounce if moving else .003*math.sin(w)
            wrist.y+=.004*math.sin(2*w-.2) if moving else .003*math.sin(w-.2)
            hand_rot=(-.06,0,1.445)
        else:
            wrist.y+=sign*.105*stride if moving else .016*math.sin(w-.4+sign*.15)
            wrist.z+=.012+.018*math.cos(w+sign*.4) if moving else .008*math.sin(w-.4)
            wrist.x+=sign*(.008+.008*bounce if moving else .003*math.sin(w))
            hand_rot=(sign*.17*stride if moving else .025*math.sin(w-.4),0,sign*.035*math.sin(w))
        posed['hand_'+side]=tr(wrist,hand_rot)@rest['hand_'+side].to_3x3().to_4x4()
        # Floating component rig: intermediate bones articulate with unit scale;
        # independent endpoint translations are intentional, not continuous-limb IK.
        for upper,lower,end,origin,bend in [
            ('upper_arm_','forearm_','hand_',posed['chest']@rest['chest'].inverted(),Vector((sign*.025,-.025,0))),
            ('thigh_','shin_','foot_',waist_delta,Vector((0,.020,0)))]:
            start=origin@rest[upper+side].translation; target=posed[end+side].translation
            mid=(start+target)*.5+bend
            for n,p,q in [(upper+side,start,mid),(lower+side,mid,target)]:
                posed[n]=Matrix.LocRotScale(p,Vector((0,1,0)).rotation_difference((q-p).normalized()),Vector((1,1,1)))
        for prefix in ['thumb','index','fingers']:
            for seg in ['01','02']:
                n=prefix+'_'+seg+'_'+side; parent=rig.data.bones[n].parent.name
                posed[n]=posed[parent]@rest[parent].inverted()@rest[n]@tr(r=(.45 if armed and side=='r' else .06,0,0))
        ear='ear_'+side
        lag=math.sin((2*w if moving else w)-.8+sign*.22)
        posed[ear]=posed['head']@rest['head'].inverted()@rest[ear]@tr(r=(
            (.13 if moving else .065)*lag,sign*(.035 if moving else .018)*math.sin(w-.6),
            sign*(.02+(.065 if moving else .035)*math.sin((2*w if moving else w)-1.1+sign*.2))))
    return posed

durations={'moving':1.0,'idle':3.2,'armed_idle':3.2,'armed_moving':1.0}
for state,duration in durations.items():
    action=bpy.data.actions.new('anim_bunny01_'+state+'_v012'); action.use_fake_user=True
    action['state_id']=state; action['loop']=True; action['duration']=duration
    action['weapon_class']='sidearm' if state.startswith('armed') else 'unarmed'
    action['authorship']='v012 original: grounded alternating walk, mild torso counterturn, lagging ears, right-hand-only ready'
    rig.animation_data.action=action
    total=round(duration*60)
    previous={}
    for index in range(total+1):
        posed=cycle(state,index/total)
        for b in rig.data.bones:
            parent=b.parent.name if b.parent else None; p=rig.pose.bones[b.name]
            p.rotation_mode='QUATERNION'
            p.matrix_basis=b.convert_local_to_pose(posed[b.name],rest[b.name],parent_matrix=posed[parent] if parent else Matrix.Identity(4),parent_matrix_local=rest[parent] if parent else Matrix.Identity(4),invert=True)
            p.scale=(1,1,1)
            if b.name in previous and previous[b.name].dot(p.rotation_quaternion)<0: p.rotation_quaternion.negate()
            previous[b.name]=p.rotation_quaternion.copy()
            for prop in ['location','rotation_quaternion','scale']: p.keyframe_insert(prop,frame=index+1,group=b.name)
    for curve in action.fcurves:
        curve.modifiers.new('CYCLES')
        for key in curve.keyframe_points:
            key.interpolation='BEZIER'; key.handle_left_type=key.handle_right_type='AUTO_CLAMPED'
    for phase,label in [(0,'起始 / 左脚接触'),(.25,'承重'),(.5,'交换支撑'),(.8,'抬脚经过')]:
        marker=action.pose_markers.new(label); marker.frame=1+round(total*phase)
rig.animation_data.action=bpy.data.actions['anim_bunny01_moving_v012']
scene.frame_start=1; scene.frame_end=61; scene.frame_set(1)
bpy.context.view_layer.objects.active=rig; rig.select_set(True); rig.show_in_front=True
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='DOPESHEET_EDITOR': area.spaces.active.mode='ACTION'
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=Vector((0,0,.7))
            area.spaces.active.region_3d.view_distance=2.7
            area.spaces.active.region_3d.view_rotation=Quaternion((0,0,1),math.pi)@Quaternion((1,0,0),math.pi/2)
bpy.ops.object.mode_set(mode='POSE')
TARGET.parent.mkdir(parents=True,exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
# Reopen actual saved asset and evaluate each frame, not the construction matrices.
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'); scene=bpy.context.scene
assert signature(rig)==sig
assert hashlib.sha256(MODEL.read_bytes()).hexdigest()==model_hash
report={'model_unchanged':True,'skeleton_sha256':sig,'clips':{}}
OUT.mkdir(parents=True,exist_ok=True)
for state,duration in durations.items():
    action=bpy.data.actions['anim_bunny01_'+state+'_v012']; rig.animation_data.action=action
    total=round(duration*60); first=None; error=0; min_floor=100
    for frame in range(1,total+2):
        scene.frame_set(frame)
        matrices={p.name:p.matrix.copy() for p in rig.pose.bones}
        if first is None: first=matrices
        for m in matrices.values(): error=max(error,max(abs(v-1) for v in m.to_scale()))
        for side in ['l','r']: min_floor=min(min_floor,matrices['foot_'+side].translation.z)
    seam=max(abs(matrices[n][r][c]-first[n][r][c]) for n in first for r in range(4) for c in range(4))
    assert error<1e-5 and seam<1e-5 and min_floor>-.00001,(state,error,seam,min_floor)
    report['clips'][state]={'frames':[1,total+1],'duration':duration,'loop_seam_error':seam,'unit_scale_error':error,'foot_floor_min':min_floor,'weapon_class':action['weapon_class']}
    # Render a full loop as an inspectable image sequence, without saving QA objects.
    scene.render.engine='BLENDER_WORKBENCH'; scene.display.shading.light='STUDIO'
    scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_cavity=True
    scene.render.resolution_x=480; scene.render.resolution_y=540; scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('QA'); cam=bpy.data.objects.new('QA',data); scene.collection.objects.link(cam)
    cam.location=(2,4,1.65); cam.rotation_euler=(Vector((0,.03,.75))-cam.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO'; data.ortho_scale=1.85; scene.camera=cam
    folder=OUT/state; folder.mkdir(exist_ok=True)
    for index in range(24):
        scene.frame_set(1+round(index*total/24)); scene.render.filepath=str(folder/f'{index:03}.png')
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)
(OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger_path=PACKAGE/'character_transfer_ledger_v012.json'; ledger=json.loads(ledger_path.read_text())
ledger.update(status='authored_pending_export',animation_source=str(TARGET.relative_to(ROOT)),
    animation_sha256=hashlib.sha256(TARGET.read_bytes()).hexdigest(),animation_checks=report,
    next_step='Two-hand poses not authored. Before Godot integration map body to chest, distinguish sidearm vs longgun, export and run runtime validation. Runtime remains v011.')
ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('V012_FOUR_ANIMATIONS_AUTHORED_AND_SOURCE_VALIDATED',TARGET)
