"""Prone somersault death and palm alignment to the user's live Blender gun edit."""
from pathlib import Path
import ast, sys, math, json, hashlib, shutil
sys.dont_write_bytecode=True
import bpy
from mathutils import Matrix, Vector, Euler
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_character_bundle import signature
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
PACKAGE=BASE/'v021'; OUT=ROOT/'outputs/character_pipeline/v021'
MODEL=PACKAGE/'source/model/chr_bunny01_model_v021.blend'
TARGET=PACKAGE/'source/animation/chr_bunny01_animation_v021.blend'
assert not TARGET.exists() or '--replace-generated' in sys.argv
# Reuse only pure authoring helpers, never execute an older version's build.
tree=ast.parse((ROOT/'scripts/blender/complete_character_basics_v019.py').read_text())
nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['tr','pivot','along','curves_digest','key','sample','build_pose'] or isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='defaults' for t in n.targets)]
exec(compile(ast.Module(body=nodes,type_ignores=[]),'<v019-pure-pose-helpers>','exec'))
bpy.ops.wm.open_mainfile(filepath=str(BASE/'v019/source/animation/chr_bunny01_animation_v019.blend'))
if bpy.context.object and bpy.context.object.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
changed={'dead','armed_moving','armed_walking','armed_idle'}
preserved={s['preview_clip']:curves_digest(next(o for o in s.objects if o.type=='ARMATURE').animation_data.action) for s in bpy.data.scenes if s['preview_clip'] not in changed}
# Read-only live capture: v018, armed jog, frame 8, moved mesh local location.
# The mesh basis remains identity rotation, unit scale; parent scale=1.5/2.475.
live_mesh_location=Vector((.16671323776245117,.24394561350345612,-.10994306951761246))
capture={'file':'v018/source/animation/chr_bunny01_animation_v018.blend','scene':'05_单手持枪_小跑','frame':8,'mesh':'吹风机_主体_金属哑光反光.002','local_location':list(live_mesh_location),'unsaved_live_scene_preserved':True}
scene=next(s for s in bpy.data.scenes if s['preview_clip']=='armed_moving')
gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
mesh=next(o for o in scene.objects if o.type=='MESH' and o.get('preview_only'))
delta=(live_mesh_location-mesh.location)*(1.5/2.475)
capture['author_world_grip_delta']=list(delta)
period=96
death_keys=[key(0),key(.08,p=-.24,z=-.06,hp=-.12,al=-.45,ar=-.45,ear=.28),
 key(.17,p=-.1,al=.7,ar=.7,spread=.8,fl=.12,fr=.12,ear=.7,roll=-.25,air=.14),
 key(.30,p=-.1,al=1.0,ar=1.0,spread=.85,fl=.14,fr=.14,ear=.8,roll=-2.2,air=.24),
 key(.46,p=-.05,al=.6,ar=.6,spread=.4,fl=.06,fr=.06,ear=.5,roll=-5.5,air=.19),
 key(.54,spread=.05,ear=.2,roll=-math.tau,air=.13),
 key(.66,spread=-1.20,roll=-2.5*math.pi,ear=.06),
 key(.75,spread=-1.22,roll=-2.5*math.pi+.07,ear=-.08,air=.075),
 key(.86,spread=-1.20,roll=-2.5*math.pi),key(1,spread=-1.20,roll=-2.5*math.pi)]
max_shoulder_shift=0
def raw_bottom(posed,meshes):
    bottom=10
    for obj in meshes:
        if obj.hide_render or obj.get('preview_only'): continue
        group=next(g for g in obj.vertex_groups if g.name in posed)
        m=posed[group.name]@rest[group.name].inverted()
        bottom=min(bottom,min((m@v.co).z for v in obj.data.vertices))
    return bottom
for scene in list(bpy.data.scenes):
    bpy.context.window.scene=scene; state=scene['preview_clip']
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones}; sig=signature(rig)
    old=rig.animation_data.action
    if state not in changed:
        old.name=old.name.replace('_v019','_v021'); continue
    meshes=[o for o in scene.objects if o.type=='MESH' and not o.get('preview_only')]
    nframes=period if state=='dead' else int(old.frame_end-1)
    samples=[]
    for i in range(nframes*2+1):
        f=1+i/2
        if state=='dead':
            v=sample(death_keys,i/(nframes*2)); clearance=v['air']; v=dict(v,air=0)
            posed=build_pose(rig,meshes,v)
            correction=clearance-raw_bottom(posed,meshes)
            for n in posed:
                if rig.data.bones[n].parent: posed[n]=tr((0,0,correction))@posed[n]
        else:
            scene.frame_set(int(f),subframe=f-int(f)); dg=bpy.context.evaluated_depsgraph_get()
            er=rig.evaluated_get(dg); posed={p.name:p.matrix.copy() for p in er.pose.bones}
            palm=posed['hand_r']@Vector((0,rig.data.bones['hand_r'].length,0))+delta
            shoulder=posed['upper_arm_r'].translation.copy()
            lengths=[rig.data.bones[n].length for n in ['upper_arm_r','forearm_r','hand_r']]
            direction=(palm-shoulder).normalized(); distance=(palm-shoulder).length
            # Preserve each bone's length. Small pose-only shoulder reach is
            # required because the user-approved palm is beyond the old reach.
            shift=max(0,distance-(sum(lengths)-.008))
            shoulder+=direction*shift; max_shoulder_shift=max(max_shoulder_shift,shift)
            wrist=palm-direction*lengths[2]
            d=(wrist-shoulder).length; axis=(wrist-shoulder).normalized()
            a=(lengths[0]**2-lengths[1]**2+d*d)/(2*d)
            h=math.sqrt(max(0,lengths[0]**2-a*a))
            bend=Vector((0,0,-1)); bend=(bend-axis*bend.dot(axis)).normalized()
            elbow=shoulder+axis*a+bend*h
            old_hand=posed['hand_r'].copy()
            posed['upper_arm_r']=along(rest['upper_arm_r'],shoulder,elbow-shoulder)
            posed['forearm_r']=along(rest['forearm_r'],elbow,wrist-elbow)
            posed['hand_r']=along(rest['hand_r'],wrist,palm-wrist)
            hand_delta=posed['hand_r']@old_hand.inverted()
            for prefix in ['thumb','index','fingers']:
                for seg in ['01','02']:
                    name=prefix+'_'+seg+'_r'; posed[name]=hand_delta@posed[name]
        samples.append(posed)
    action=bpy.data.actions.new('anim_bunny01_'+state+'_v021'); rig.animation_data.action=action
    previous={}
    for i,posed in enumerate(samples):
        for b in rig.data.bones:
            p=rig.pose.bones[b.name]; parent=b.parent.name if b.parent else None; p.rotation_mode='QUATERNION'
            p.matrix_basis=b.convert_local_to_pose(posed[b.name],rest[b.name],parent_matrix=posed[parent] if parent else Matrix.Identity(4),parent_matrix_local=rest[parent] if parent else Matrix.Identity(4),invert=True)
            p.scale=(1,1,1)
            if b.name in previous and previous[b.name].dot(p.rotation_quaternion)<0: p.rotation_quaternion.negate()
            previous[b.name]=p.rotation_quaternion.copy()
            for prop in ['location','rotation_quaternion','scale']: p.keyframe_insert(prop,frame=1+i/2,group=b.name)
    loop=state!='dead'; action.use_fake_user=True
    action['state_id']=state; action['duration']=nframes/60; action['loop']=loop
    action.use_frame_range=True; action.frame_start=1; action.frame_end=nframes+1; action.use_cyclic=loop
    for c in action.fcurves:
        c.extrapolation='CONSTANT'
        if loop: c.modifiers.new('CYCLES')
        for k in c.keyframe_points: k.interpolation='BEZIER'; k.handle_left_type=k.handle_right_type='AUTO_CLAMPED'
    old.use_fake_user=False
    scene.frame_end=nframes if loop else nframes+1; scene.frame_preview_end=scene.frame_end
    if state=='dead': scene.name='12_死亡_空翻趴地_弹起后保持'
    scene.frame_set(1)
for scene in bpy.data.scenes: scene['model_source']='../model/chr_bunny01_model_v021.blend'
MODEL.parent.mkdir(parents=True,exist_ok=True); TARGET.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(BASE/'v019/source/model/chr_bunny01_model_v019.blend',MODEL)
for lib in bpy.data.libraries:
    if 'chr_bunny01_model' in lib.filepath: lib.filepath='//../model/chr_bunny01_model_v021.blend'
bpy.context.window.scene=next(s for s in bpy.data.scenes if s['preview_clip']=='armed_moving')
bpy.context.scene.frame_set(8)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
OUT.mkdir(parents=True,exist_ok=True)
report={'capture':capture,'max_pose_shoulder_reach_m':max_shoulder_shift,'preserved_curves':{},'clips':{},'skeleton_sha256':sig}
for scene in list(bpy.data.scenes):
    bpy.context.window.scene=scene; state=scene['preview_clip']; rig=next(o for o in scene.objects if o.type=='ARMATURE')
    assert signature(rig)==sig
    if state not in changed:
        assert curves_digest(rig.animation_data.action)==preserved[state]
        report['preserved_curves'][state]=True; continue
    length=int(rig.animation_data.action.frame_end-1); first=None; last=None; scale=0; gap=0; grip=0; ground=10
    for i in range(length*4+1):
        f=1+i/4; scene.frame_set(int(f),subframe=f-int(f)); dg=bpy.context.evaluated_depsgraph_get(); er=rig.evaluated_get(dg)
        mats={p.name:p.matrix.copy() for p in er.pose.bones}
        if first is None: first=mats
        last=mats
        scale=max(scale,max(abs(v-1) for m in mats.values() for v in m.to_scale()))
        for side in ['l','r'] if state=='dead' else ['r']:
            for a,b in [('upper_arm_','forearm_'),('forearm_','hand_')]:
                gap=max(gap,(mats[a+side]@Vector((0,rig.data.bones[a+side].length,0))-mats[b+side].translation).length)
        if state!='dead':
            g=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')).evaluated_get(dg)
            palm=er.matrix_world@mats['hand_r']@Vector((0,rig.data.bones['hand_r'].length,0))
            grip=max(grip,(palm-g.matrix_world.translation).length)
        else:
            for obj in scene.objects:
                if obj.type!='MESH' or obj.hide_render: continue
                eo=obj.evaluated_get(dg); me=eo.to_mesh(); ground=min(ground,min((eo.matrix_world@v.co).z for v in me.vertices)); eo.to_mesh_clear()
    scene.frame_set(length*2+1)
    end={p.name:p.matrix.copy() for p in rig.evaluated_get(bpy.context.evaluated_depsgraph_get()).pose.bones}
    target=last if state=='dead' else first
    repeat=max(abs(end[n][a][b]-target[n][a][b]) for n in end for a in range(4) for b in range(4))
    assert max(scale,gap,grip,repeat)<1e-4 and ground>-.002,(state,scale,gap,grip,repeat,ground)
    if state=='dead':
        forward=(last['head']@rig.data.bones['head'].matrix_local.inverted()).to_3x3()@Vector((0,1,0))
        assert forward.z<-.99,forward
    report['clips'][state]={'scale_error':scale,'arm_chain_gap':gap,'grip_error':grip,'loop_or_hold_error':repeat,'ground_min_z':ground if state=='dead' else None,'duration':length/60}
    scene.render.engine='BLENDER_WORKBENCH'; scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_cavity=True
    scene.render.resolution_x=480; scene.render.resolution_y=480; scene.render.resolution_percentage=100
    camdata=bpy.data.cameras.new('QA'); cam=bpy.data.objects.new('QA',camdata); scene.collection.objects.link(cam); scene.camera=cam
    camdata.type='ORTHO'; camdata.ortho_scale=2.2 if state=='dead' else 1.85
    views=[('threequarter',(2.8,4,1.9)),('side',(4,0,.9)),('front',(0,4,.8))]
    for view,pos in views:
        cam.location=pos; cam.rotation_euler=(Vector((0,.12,.75))-cam.location).to_track_quat('-Z','Y').to_euler()
        folder=OUT/(state+'_'+view); folder.mkdir(exist_ok=True)
        for i in range(40):
            f=1+i*length/(39 if state=='dead' else 40); scene.frame_set(int(f),subframe=f-int(f))
            scene.render.filepath=str(folder/f'{i:03}.png'); bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)
assert MODEL.read_bytes()==(BASE/'v019/source/model/chr_bunny01_model_v019.blend').read_bytes()
report['model_unchanged']=True
(OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger={'asset_id':'CHR-PLY-CAPSULE01-3D-BUNNY01','version':'v021','status':'authored_pending_export','runtime_active_version':'v011','skeleton_id':'SKEL-BUNNY01-004','validation':report,
 'files':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [MODEL,TARGET]],'scope':'death and three sidearm poses; user live edit captured without overwriting unsaved Blender state','integration_warning':'No Godot integration. New palm mapping and pose-only shoulder reach must be retained; avoid duplicate procedural death transforms.'}
(PACKAGE/'character_transfer_ledger_v021.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('V021_VALIDATED',TARGET)
