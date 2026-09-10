"""Original shoulder-driven jog, explicit palm grip, preview-only pistol."""
from pathlib import Path
import sys, math, json, hashlib, shutil
sys.dont_write_bytecode=True
import bpy
from mathutils import Matrix, Vector, Euler
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_character_bundle import signature
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
PACKAGE=BASE/'v015'; OUT=ROOT/'outputs/character_pipeline/v015'
MODEL=PACKAGE/'source/model/chr_bunny01_model_v015.blend'
TARGET=PACKAGE/'source/animation/chr_bunny01_animation_v015.blend'
assert not TARGET.exists() or '--replace-generated' in sys.argv,'Preserve existing artist work'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'v014/source/animation/chr_bunny01_animation_v014.blend'))
if bpy.context.object and bpy.context.object.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
def tr(p=(0,0,0),r=(0,0,0)):
    return Matrix.Translation(Vector(p))@Euler(r).to_matrix().to_4x4()
def along(rest_matrix,p,direction):
    q=(rest_matrix.to_3x3()@Vector((0,1,0))).rotation_difference(direction.normalized())
    return Matrix.Translation(p)@q.to_matrix().to_4x4()@rest_matrix.to_3x3().to_4x4()
period=48 # 0.8s, a new rounded jog, not a retimed walk.
for scene in list(bpy.data.scenes):
    bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    state=scene['preview_clip']; old=rig.animation_data.action
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones}; sig=signature(rig)
    if state in ['moving','armed_moving']:
        armed=state.startswith('armed')
        action=bpy.data.actions.new('anim_bunny01_'+state+'_v015')
        rig.animation_data.action=action
        previous={}
        for i in range(period+1):
            t=i/period; w=math.tau*t
            pulse=.5-.5*math.cos(2*w)
            posed={n:m.copy() for n,m in rest.items()}
            # +Y is forward: negative global-X pitch leans the torso forward.
            pelvis=tr((.008*math.cos(w),.006,.010+.042*pulse),(-.105,.015*math.cos(w),.03*math.cos(w)))
            chest=pelvis@tr(r=(.014*math.sin(2*w-.25),0,-.065*math.cos(w)))
            posed['waist']=pelvis@rest['waist']; posed['chest']=chest@rest['chest']
            head_delta=tr((.004*math.cos(w-.25),.014,.012+.032*(.5-.5*math.cos(2*w-.18))),(-.035+.012*math.sin(2*w-.4),0,0))
            posed['head']=head_delta@rest['head']
            for side,sign in [('l',-1),('r',1)]:
                upper='upper_arm_'+side; lower='forearm_'+side; hand='hand_'+side
                ub=rig.data.bones[upper]; lb=rig.data.bones[lower]
                if armed and side=='r':
                    # Anatomical-length held chain: shoulder -> elbow -> wrist.
                    shoulder=chest@rest[upper].translation
                    posed[upper]=along(rest[upper],shoulder,Vector((.035,.058,-.055)))
                    elbow=posed[upper]@Vector((0,ub.length,0))
                    posed[lower]=along(rest[lower],elbow,Vector((.012,.075,.043)))
                    wrist=posed[lower]@Vector((0,lb.length,0))
                    posed[hand]=tr(wrist,(-.06,0,1.445))@rest[hand].to_3x3().to_4x4()
                else:
                    # Genuine FK. Only rotations on upper/lower/hand; the shoulder
                    # pivot and rest translations remain fixed in each parent frame.
                    swing=sign*1.02*math.cos(w)
                    rotation=Euler((swing,sign*.50,0)).to_matrix().to_4x4()
                    basis=rest[upper].to_3x3().to_4x4()
                    posed[upper]=chest@rest[upper]@basis.inverted()@rotation@basis
                    basis=rest[lower].to_3x3().to_4x4()
                    elbow_flex=.72+.18*math.sin(w+sign*.6)
                    local_hinge=basis.inverted()@tr(r=(elbow_flex,0,0))@basis
                    posed[lower]=posed[upper]@rest[upper].inverted()@rest[lower]@local_hinge
                    posed[hand]=posed[lower]@rest[lower].inverted()@rest[hand]
                for prefix in ['thumb','index','fingers']:
                    for seg in ['01','02']:
                        name=prefix+'_'+seg+'_'+side; parent=rig.data.bones[name].parent.name
                        posed[name]=posed[parent]@rest[parent].inverted()@rest[name]@tr(r=(.42 if armed and side=='r' else .12,0,0))
                phase=(t+(0 if side=='l' else .5))%1
                foot=rest['foot_'+side].translation.copy()
                if phase<.40:
                    u=phase/.40; ease=u*u*(3-2*u)
                    foot.y+=.16-.32*ease
                else:
                    u=(phase-.40)/.60; ease=u*u*(3-2*u)
                    foot.y+=-.16+.32*ease
                    foot.z+=.115*math.sin(math.pi*u)**2
                posed['foot_'+side]=tr(foot)@rest['foot_'+side].to_3x3().to_4x4()
                hip=pelvis@rest['thigh_'+side].translation
                knee=(hip+foot)*.5+Vector((0,.028,0))
                posed['thigh_'+side]=along(rest['thigh_'+side],hip,knee-hip)
                posed['shin_'+side]=along(rest['shin_'+side],knee,foot-knee)
                ear='ear_'+side
                # Rotate about CHARACTER X at each ear root, not the splayed
                # ear's local axes: this produces sagittal forward/back swing.
                ear_root=rest[ear].translation
                posed[ear]=head_delta@Matrix.Translation(ear_root)@tr(r=(.21*math.sin(2*w-.85+sign*.12),0,0))@rest[ear].to_3x3().to_4x4()
            for b in rig.data.bones:
                parent=b.parent.name if b.parent else None; p=rig.pose.bones[b.name]
                p.rotation_mode='QUATERNION'
                p.matrix_basis=b.convert_local_to_pose(posed[b.name],rest[b.name],parent_matrix=posed[parent] if parent else Matrix.Identity(4),parent_matrix_local=rest[parent] if parent else Matrix.Identity(4),invert=True)
                p.scale=(1,1,1)
                if b.name in previous and previous[b.name].dot(p.rotation_quaternion)<0: p.rotation_quaternion.negate()
                previous[b.name]=p.rotation_quaternion.copy()
                for prop in ['location','rotation_quaternion','scale']: p.keyframe_insert(prop,frame=i+1,group=b.name)
        action.use_fake_user=True; action['state_id']=state; action['duration']=period/60
        action['loop']=True; action['weapon_class']='sidearm' if armed else 'unarmed'
        action['authorship']='original FK shoulder arcs, variable elbow flexion, suspension, delayed ears; not walk retiming'
        action.use_frame_range=True; action.frame_start=1; action.frame_end=period+1; action.use_cyclic=True
        for c in action.fcurves:
            c.modifiers.new('CYCLES')
            for k in c.keyframe_points: k.interpolation='BEZIER'; k.handle_left_type=k.handle_right_type='AUTO_CLAMPED'
        scene.frame_end=period; scene.frame_preview_end=period
        old.use_fake_user=False
    else:
        old.name=old.name.replace('_v014','_v015')
    # The bone tail is exactly the bound ball-hand center in this source.
    for gun in [o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')]:
        gun['grip_contract']='weapon GripSocket = hand_r tail = palm sphere center; wrist is not grip'
        for con in gun.constraints:
            if con.type=='COPY_LOCATION': con.head_tail=1.0; con.name='GripSocket_掌心握点_非腕环'
        gun.hide_viewport=False; gun.hide_render=False; gun.hide_set(False)
    for obj in scene.objects:
        if obj.get('preview_only'):
            obj.hide_viewport=False; obj.hide_render=False; obj.hide_set(False)
    scene['preview_help']='Scene selector switches clips. Pistol shown only in armed scenes. Hand wrist pivot and palm GripSocket are distinct. Export selected character armature animation only.'
    scene['model_source']='../model/chr_bunny01_model_v015.blend'
    scene.frame_set(1)
for action in list(bpy.data.actions):
    if action.library is None and action.users==0: bpy.data.actions.remove(action)
MODEL.parent.mkdir(parents=True,exist_ok=True); TARGET.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(BASE/'v014/source/model/chr_bunny01_model_v014.blend',MODEL)
for lib in bpy.data.libraries:
    if 'chr_bunny01_model' in lib.filepath: lib.filepath='//../model/chr_bunny01_model_v015.blend'
# Open a gun-visible scene by default, rather than the unarmed jog.
bpy.context.window.scene=bpy.data.scenes['05_单手持枪_小跑']
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
bpy.context.view_layer.objects.active=rig
for obj in bpy.context.scene.objects: obj.select_set(False)
rig.select_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.shading.type='SOLID'
            area.spaces.active.region_3d.view_location=Vector((0,.12,.72))
            area.spaces.active.region_3d.view_distance=2.6
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
OUT.mkdir(parents=True,exist_ok=True)
report={'skeleton_sha256':sig,'model_unchanged':hashlib.sha256(MODEL.read_bytes()).hexdigest()==hashlib.sha256((BASE/'v014/source/model/chr_bunny01_model_v014.blend').read_bytes()).hexdigest(),
    'grip_cause':'v013 conflated wrist/cuff pivot and palm grip; bone tail is the palm, not head',
    'runtime_migration_required':'Godot still aligns weapon to cuff; must introduce palm offset in presentation adapter when integrating. Not changed in this authoring task.', 'clips':{}}
for scene in list(bpy.data.scenes):
    bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE'); state=scene['preview_clip']
    assert signature(rig)==sig
    period=scene.frame_end; errors={'scale':0,'arm_joint_gap':0,'grip':0,'free_arm_local_translation':0}
    first=None; samples={}; moving=state in ['moving','armed_moving']; min_ground=1
    for f in range(1,period*2+2):
        scene.frame_set(f); dg=bpy.context.evaluated_depsgraph_get(); er=rig.evaluated_get(dg)
        mats={p.name:p.matrix.copy() for p in er.pose.bones}
        if first is None: first=mats
        if f<=period: samples[f]=mats
        elif f<=period*2: assert max(abs(mats[n][a][b]-samples[f-period][n][a][b]) for n in mats for a in range(4) for b in range(4))<1e-5
        for m in mats.values(): errors['scale']=max(errors['scale'],max(abs(v-1) for v in m.to_scale()))
        for side in ['l','r']:
            min_ground=min(min_ground,mats['foot_'+side].translation.z)
            if moving:
                for a,b in [('upper_arm_','forearm_'),('forearm_','hand_')]:
                    endpoint=mats[a+side]@Vector((0,rig.data.bones[a+side].length,0))
                    errors['arm_joint_gap']=max(errors['arm_joint_gap'],(endpoint-mats[b+side].translation).length)
                if not(state.startswith('armed') and side=='r'):
                    for prefix in ['upper_arm_','forearm_','hand_']:
                        errors['free_arm_local_translation']=max(errors['free_arm_local_translation'],er.pose.bones[prefix+side].location.length)
        guns=[o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')]
        assert bool(guns)==state.startswith('armed')
        if guns:
            g=guns[0].evaluated_get(dg)
            palm=er.matrix_world@mats['hand_r']@Vector((0,rig.data.bones['hand_r'].length,0))
            errors['grip']=max(errors['grip'],(g.matrix_world.translation-palm).length)
    seam=max(abs(mats[n][a][b]-first[n][a][b]) for n in mats for a in range(4) for b in range(4))
    assert max(errors.values())<1e-5 and seam<1e-5 and min_ground>-.00001,(state,errors,seam,min_ground)
    report['clips'][state]={'period':period,'duration':period/60,'two_cycles_match':True,'errors':errors,'loop_seam':seam,'min_ground':min_ground}
    scene.render.engine='BLENDER_WORKBENCH'; scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_cavity=True
    scene.render.resolution_x=640; scene.render.resolution_y=640; scene.render.resolution_percentage=100
    camdata=bpy.data.cameras.new('QA'); cam=bpy.data.objects.new('QA',camdata); scene.collection.objects.link(cam)
    camdata.type='ORTHO'; camdata.ortho_scale=1.85; scene.camera=cam
    for view,position in [('threequarter',(2.8,4,1.8)),('side',(4,0,.9))]:
        if view=='side' and state not in ['moving','armed_moving','armed_idle']: continue
        cam.location=position; cam.rotation_euler=(Vector((0,.08,.74))-cam.location).to_track_quat('-Z','Y').to_euler()
        folder=OUT/(state+'_'+view); folder.mkdir(exist_ok=True)
        for i in range(32):
            frame=1+i*period/32; scene.frame_set(int(frame),subframe=frame-int(frame))
            scene.render.filepath=str(folder/f'{i:03}.png'); bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)
(OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger={'asset_id':'CHR-PLY-CAPSULE01-3D-BUNNY01','version':'v015','status':'authored_pending_export','runtime_active_version':'v011',
    'skeleton_id':'SKEL-BUNNY01-004','skeleton_sha256':sig,'files':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [MODEL,TARGET]],
    'validation':report,'preview_only_weapon':True,'next_step':'Confirm source art; implement palm grip presentation mapping and body chest mapping before runtime export/integration.'}
(PACKAGE/'character_transfer_ledger_v015.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('V015_LIVELIER_JOG_VALIDATED',TARGET)
