"""Author six remaining basic clips on the approved v018 rest rig; no runtime edits."""
from pathlib import Path
import sys, math, json, hashlib, shutil
sys.dont_write_bytecode = True
import bpy
from mathutils import Matrix, Vector, Euler
sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_character_bundle import signature
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
PACKAGE = BASE/'v019'
MODEL = PACKAGE/'source/model/chr_bunny01_model_v019.blend'
TARGET = PACKAGE/'source/animation/chr_bunny01_animation_v019.blend'
OUT = ROOT/'outputs/character_pipeline/v019'
assert not TARGET.exists() or '--replace-generated' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(BASE/'v018/source/animation/chr_bunny01_animation_v018.blend'))
if bpy.context.object and bpy.context.object.mode != 'OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
def tr(p=(0,0,0), r=(0,0,0)):
    return Matrix.Translation(Vector(p)) @ Euler(r).to_matrix().to_4x4()
def pivot(p, r): return tr(p) @ tr(r=r) @ tr(-Vector(p))
def along(rest, p, d):
    q = (rest.to_3x3() @ Vector((0,1,0))).rotation_difference(d.normalized())
    return tr(p) @ q.to_matrix().to_4x4() @ rest.to_3x3().to_4x4()
def curves_digest(a):
    data=[(c.data_path,c.array_index,[(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right),k.interpolation) for k in c.keyframe_points]) for c in a.fcurves]
    return hashlib.sha256(repr(data).encode()).hexdigest()
existing={s['preview_clip']:curves_digest(next(o for o in s.objects if o.type=='ARMATURE').animation_data.action) for s in bpy.data.scenes}
template=bpy.data.scenes['03_待机_循环']
source_rig=next(o for o in template.objects if o.type=='ARMATURE')
sig=signature(source_rig)
rest={b.name:b.matrix_local.copy() for b in source_rig.data.bones}
# Each value is an animator-authored pose, not recycled locomotion curves.
# Parameters: torso pitch/side lean, pelvis height, head counterpose, shoulder
# swings, outward opening, left/right foot recovery, ear drag, whole-body roll.
defaults=dict(p=0, side=0, z=0, hy=0, hp=0, hs=0, al=0, ar=0, spread=.66,
              fy=0, fl=0, fr=0, fp=0, ear=0, roll=0, topple=0, air=0)
def key(t, **kw): return (t, defaults | kw)
SPECS={
 'dashing': ('07_冲刺_收身翻滚',24,False,[
   key(0), key(.10,p=-.22,z=-.055,hp=-.16,al=-.6,ar=-.6,ear=.28),
   key(.25,p=-.25,z=-.015,al=.85,ar=.85,spread=.95,fl=.12,fr=.12,ear=.8,roll=-.4,air=.10),
   key(.55,p=-.18,al=1.25,ar=1.25,spread=.9,fl=.16,fr=.16,ear=1.05,roll=-3.3,air=.12),
   key(.80,p=-.2,al=.7,ar=.7,fl=.08,fr=.08,ear=.55,roll=-5.8,air=.06),
   key(.90,p=-.2,z=-.055,hp=-.1,ear=-.20,roll=-math.tau),key(1,roll=-math.tau)]),
 'hurt': ('08_受击_甩头回弹',33,False,[
   key(0),key(.12,p=.30,side=-.14,z=.03,hp=.22,hs=.16,al=-.9,ar=-.5,ear=-.42,fy=-.04),
   key(.30,p=.18,side=-.20,hp=.32,hs=.22,al=-1.0,ar=-.7,ear=-.65,fl=.055),
   key(.53,p=-.15,side=.08,z=-.045,hp=-.18,al=.25,ar=.35,ear=.38),
   key(.76,p=.045,hp=.08,al=-.08,ar=-.12,ear=-.15),key(1)]),
 'locked': ('09_锁定_警觉循环',108,True,[
   key(0,spread=.5,p=-.035,hp=.05),
   key(.25,spread=.5,p=-.055,side=.055,z=.012,hp=.09,hs=.14,al=-.10,ar=.08,ear=.09),
   key(.5,spread=.5,p=-.035,hp=.05),
   key(.75,spread=.5,p=-.055,side=-.055,z=.012,hp=.09,hs=-.14,al=.08,ar=-.1,ear=-.09),
   key(1,spread=.5,p=-.035,hp=.05)]),
 'falling': ('10_下落_张臂失衡_末帧保持',39,False,[
   key(0),key(.18,p=.10,z=.035,hp=.12,al=-.45,ar=-.25,spread=.10,ear=-.32,fl=.03,fr=.06),
   key(.42,p=-.12,side=.08,z=.06,hp=.20,hs=-.08,al=-.65,ar=-.35,spread=-.85,ear=-.5,fl=.07,fr=.02,fp=-.3),
   key(.70,p=-.065,side=-.025,z=.055,hp=.08,al=-.38,ar=-.60,spread=-.70,ear=-.32,fl=.04,fr=.075,fp=-.2),
   key(1,p=-.07,z=.05,hp=.14,al=-.48,ar=-.42,spread=-.75,ear=-.38,fl=.06,fr=.05,fp=-.22)]),
 'landing': ('11_落地_下沉回弹',27,False,[
   key(0,p=-.07,z=.05,hp=.14,al=-.48,ar=-.42,spread=-.75,ear=-.38,fl=.06,fr=.05,fp=-.22),
   key(.22,p=-.30,z=-.07,hp=-.18,al=.45,ar=.45,spread=.30,ear=.55),
   key(.42,p=-.23,z=-.06,hp=-.26,al=.32,ar=.32,spread=.40,ear=.72),
   key(.67,p=.06,z=.035,hp=.15,al=-.22,ar=-.22,ear=-.32),
   key(.84,p=-.035,z=-.015,hp=-.06,ear=.15),key(1)]),
 'dead': ('12_死亡_失衡倒下_末帧保持',72,False,[
   key(0),key(.10,p=.20,side=-.10,z=.055,hp=.23,al=-.9,ar=-.75,spread=.2,ear=-.45),
   key(.25,p=.05,side=.16,hp=.12,hs=.1,al=-.2,ar=-.65,spread=.2,ear=.2,topple=-.22),
   key(.50,p=.10,hp=.1,al=.30,ar=-.45,spread=.5,ear=.5,topple=-1.35),
   key(.61,p=.08,hp=-.08,al=.2,ar=-.3,spread=.55,ear=.65,topple=-1.48),
   key(.73,p=.06,hp=.05,al=.12,ar=-.2,spread=.6,ear=.36,topple=-1.30,air=.035),
   key(.9,p=.07,hp=-.05,al=.15,ar=-.2,spread=.6,ear=.5,topple=-1.48),
   key(1,p=.07,hp=-.05,al=.15,ar=-.2,spread=.6,ear=.5,topple=-1.48)])
}
def sample(keys,t):
    for (a,va),(b,vb) in zip(keys,keys[1:]):
        if t<=b+1e-9:
            u=max(0,min(1,(t-a)/(b-a))); u=u*u*u*(10+u*(-15+6*u))
            return {n:va[n]+(vb[n]-va[n])*u for n in defaults}
    return keys[-1][1]
def build_pose(rig,meshes,v):
    posed={n:m.copy() for n,m in rest.items()}
    torso=tr((0,0,v['z'])) @ pivot(rest['waist'].translation,(v['p'],v['side'],0))
    posed['waist']=torso@rest['waist']; posed['chest']=torso@rest['chest']
    head=torso@tr((0,v['hy'],0))@pivot(rest['head'].translation,(v['hp'],0,v['hs']))
    posed['head']=head@rest['head']
    for side,sign in [('l',-1),('r',1)]:
        upper='upper_arm_'+side; lower='forearm_'+side; hand='hand_'+side
        basis=rest[upper].to_3x3().to_4x4()
        rotation=tr(r=(v['a'+side],0,0))@tr(r=(0,sign*v['spread'],0))
        posed[upper]=torso@rest[upper]@basis.inverted()@rotation@basis
        posed[lower]=posed[upper]@rest[upper].inverted()@rest[lower]
        posed[hand]=posed[lower]@rest[lower].inverted()@rest[hand]
        for prefix in ['thumb','index','fingers']:
            for seg in ['01','02']:
                n=prefix+'_'+seg+'_'+side; parent=rig.data.bones[n].parent.name
                posed[n]=posed[parent]@rest[parent].inverted()@rest[n]
        foot='foot_'+side; pos=rest[foot].translation+Vector((0,v['fy']*sign,v['f'+side]))
        rot=tr(r=(v['fp'],0,0))
        shoe=next(o for o in meshes if o.get('component_id')==foot)
        pos.z-=min((rot@(vert.co-rest[foot].translation)).z for vert in shoe.data.vertices)
        posed[foot]=tr(pos)@rot@rest[foot].to_3x3().to_4x4()
        hip=torso@rest['thigh_'+side].translation; knee=(hip+pos)*.5+Vector((0,.03,0))
        posed['thigh_'+side]=along(rest['thigh_'+side],hip,knee-hip)
        posed['shin_'+side]=along(rest['shin_'+side],knee,pos-knee)
        ear='ear_'+side
        posed[ear]=head@pivot(rest[ear].translation,(v['ear'],0,0))@rest[ear]
    whole=pivot((0,0,.6),(v['roll'],v['topple'],0))
    for n in posed:
        if rig.data.bones[n].parent: posed[n]=whole@posed[n]
    # Rigid mesh weights permit exact contact compensation before baking.
    bottom=10
    for obj in meshes:
        if obj.hide_render: continue
        group=next(g for g in obj.vertex_groups if g.name in posed)
        matrix=posed[group.name]@rest[group.name].inverted()
        bottom=min(bottom,min((matrix@p.co).z for p in obj.data.vertices))
    contact=max(0,min(1,(abs(v['topple'])-.1)/.4))
    contact=contact*contact*(3-2*contact)
    lift=max(0,-bottom)-max(0,bottom)*contact+v['air']
    for n in posed:
        if rig.data.bones[n].parent: posed[n]=tr((0,0,lift))@posed[n]
    return posed
for state,(title,period,loop,keys) in SPECS.items():
    scene=bpy.data.scenes.new(title); scene.world=template.world
    scene['preview_clip']=state; scene['file_role']='animation'; scene['production_status']='authored_pending_export'
    scene.render.fps=60; scene.unit_settings.system='METRIC'
    collection=bpy.data.collections.new('01_角色预览_'+state); scene.collection.children.link(collection)
    mapping={}
    for obj in template.objects:
        if obj.type not in ('ARMATURE','MESH') or obj.get('preview_only'): continue
        copy=obj.copy(); collection.objects.link(copy); mapping[obj]=copy
    rig=mapping[source_rig]; rig.name='RIG_bunny01_'+state
    for orig,obj in mapping.items():
        if orig.parent in mapping: obj.parent=mapping[orig.parent]
        for mod in obj.modifiers:
            if mod.type=='ARMATURE': mod.object=rig
    bpy.context.window.scene=scene
    meshes=[o for o in scene.objects if o.type=='MESH']
    action=bpy.data.actions.new('anim_bunny01_'+state+'_v019')
    rig.animation_data_create(); rig.animation_data.action=action
    previous={}
    for i in range(period*2+1):
        posed=build_pose(rig,meshes,sample(keys,i/(period*2)))
        for b in rig.data.bones:
            p=rig.pose.bones[b.name]; p.rotation_mode='QUATERNION'; parent=b.parent.name if b.parent else None
            p.matrix_basis=b.convert_local_to_pose(posed[b.name],rest[b.name],parent_matrix=posed[parent] if parent else Matrix.Identity(4),parent_matrix_local=rest[parent] if parent else Matrix.Identity(4),invert=True)
            p.scale=(1,1,1)
            if b.name in previous and previous[b.name].dot(p.rotation_quaternion)<0: p.rotation_quaternion.negate()
            previous[b.name]=p.rotation_quaternion.copy()
            for prop in ['location','rotation_quaternion','scale']: p.keyframe_insert(prop,frame=i/2+1,group=b.name)
    action.use_fake_user=True; action['state_id']=state; action['duration']=period/60; action['loop']=loop
    action['authorship']='v019 original staged cartoon poses; rigid meshes, shoulder FK; no gameplay root motion'
    action.use_frame_range=True; action.frame_start=1; action.frame_end=period+1; action.use_cyclic=loop
    for c in action.fcurves:
        c.extrapolation='CONSTANT'
        if loop: c.modifiers.new('CYCLES')
        for k in c.keyframe_points: k.interpolation='BEZIER'; k.handle_left_type=k.handle_right_type='AUTO_CLAMPED'
    scene.frame_end=period if loop else period+1
    scene.use_preview_range=True; scene.frame_preview_start=1; scene.frame_preview_end=scene.frame_end
    scene['preview_help']='Single-shot clips restart only because Blender timeline playback wraps; exported loop=false. Falling/dead hold last pose.'
    scene.frame_set(1); scene.view_layers[0].objects.active=rig
for scene in bpy.data.scenes:
    scene['model_source']='../model/chr_bunny01_model_v019.blend'
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    rig.animation_data.action.name=rig.animation_data.action.name.replace('_v018','_v019')
MODEL.parent.mkdir(parents=True,exist_ok=True); TARGET.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(BASE/'v018/source/model/chr_bunny01_model_v018.blend',MODEL)
for lib in bpy.data.libraries:
    if 'chr_bunny01_model' in lib.filepath: lib.filepath='//../model/chr_bunny01_model_v019.blend'
bpy.context.window.scene=bpy.data.scenes[SPECS['hurt'][0]]
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
OUT.mkdir(parents=True,exist_ok=True)
assert MODEL.read_bytes()==(BASE/'v018/source/model/chr_bunny01_model_v018.blend').read_bytes()
report={'skeleton_sha256':sig,'model_byte_identical_to_v018':True,'preserved_curves':{},'clips':{}}
for scene in list(bpy.data.scenes):
    bpy.context.window.scene=scene; state=scene['preview_clip']; rig=next(o for o in scene.objects if o.type=='ARMATURE')
    assert signature(rig)==sig
    if state in existing:
        assert curves_digest(rig.animation_data.action)==existing[state]
        report['preserved_curves'][state]=True
        continue
    period=SPECS[state][1]; loop=SPECS[state][2]; maxscale=0; minground=10; gap=0; first=None; last=None; motion=0
    for i in range(period*4+1):
        f=1+i/4
        scene.frame_set(int(f),subframe=f-int(f))
        dg=bpy.context.evaluated_depsgraph_get(); er=rig.evaluated_get(dg)
        mats={p.name:p.matrix.copy() for p in er.pose.bones}
        assert max(abs(mats['root'][a][b]-rest['root'][a][b]) for a in range(4) for b in range(4))<1e-5
        if first is None: first=mats
        motion=max(motion,max(abs(mats[n][a][b]-first[n][a][b]) for n in mats for a in range(4) for b in range(4)))
        maxscale=max(maxscale,max(abs(v-1) for m in mats.values() for v in m.to_scale()))
        for side in ['l','r']:
            for a,b in [('upper_arm_','forearm_'),('forearm_','hand_')]:
                gap=max(gap,(mats[a+side]@Vector((0,rig.data.bones[a+side].length,0))-mats[b+side].translation).length)
        for obj in scene.objects:
            if obj.type!='MESH' or obj.hide_render: continue
            eo=obj.evaluated_get(dg); mesh=eo.to_mesh()
            minground=min(minground,min((eo.matrix_world@v.co).z for v in mesh.vertices)); eo.to_mesh_clear()
        last=mats
    assert maxscale<1e-5 and gap<1e-5 and minground>-.002 and motion>.02,(state,maxscale,gap,minground,motion)
    scene.frame_set(period*2+1)
    later={p.name:p.matrix.copy() for p in rig.evaluated_get(bpy.context.evaluated_depsgraph_get()).pose.bones}
    expected=first if loop else last
    repeat=max(abs(later[n][a][b]-expected[n][a][b]) for n in later for a in range(4) for b in range(4))
    assert repeat<1e-5,(state,repeat)
    report['clips'][state]={'duration':period/60,'loop':loop,'unit_scale_error':maxscale,'arm_joint_gap':gap,'min_visible_mesh_z':minground,'motion_extent':motion,'loop_or_hold_error':repeat}
    scene.render.engine='BLENDER_WORKBENCH'; scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_cavity=True
    scene.render.resolution_x=480; scene.render.resolution_y=480; scene.render.resolution_percentage=100
    camdata=bpy.data.cameras.new('QA'); cam=bpy.data.objects.new('QA',camdata); scene.collection.objects.link(cam); scene.camera=cam
    camdata.type='ORTHO'; camdata.ortho_scale=2.1
    for view,pos in [('threequarter',(2.8,4,1.6)),('side',(4,0,.85))]:
        cam.location=pos; cam.rotation_euler=(Vector((0,0,.72))-cam.location).to_track_quat('-Z','Y').to_euler()
        folder=OUT/(state+'_'+view); folder.mkdir(exist_ok=True)
        for i in range(32):
            f=1+i*period/(32 if loop else 31); scene.frame_set(int(f),subframe=f-int(f))
            scene.render.filepath=str(folder/f'{i:03}.png'); bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)
(OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger={'asset_id':'CHR-PLY-CAPSULE01-3D-BUNNY01','version':'v019','status':'authored_pending_export','runtime_active_version':'v011','skeleton_id':'SKEL-BUNNY01-004','validation':report,
 'files':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [MODEL,TARGET]],
 'scope':'six original unarmed basic states; six v018 locomotion/idle clips preserved; no combat overlays or two-handed authoring',
 'integration_warning':'Need body->chest and palm grip mapping; remove duplicate procedural roll/death transforms when integrating. Real state progress must still own timing.'}
(PACKAGE/'character_transfer_ledger_v019.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('V019_SIX_BASIC_CLIPS_VERIFIED',TARGET)
