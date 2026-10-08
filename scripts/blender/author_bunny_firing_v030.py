"""Author raised firing variants without changing any delivered carry actions."""
from pathlib import Path
import sys,json,math
import bpy
from mathutils import Vector,Matrix
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_bunny_directional_v027 as d
h=d.h
SOURCE=h.BASE/'source/animation/chr_bunny01_animation_v029.blend'
TARGET=h.BASE/'source/animation/chr_bunny01_animation_v030.blend'
OUT=h.ROOT/'outputs/character_pipeline/firing_v030'

def solve(rig,rest,posed,side,palm):
    n='upper_arm_'+side
    chest=posed['chest']@rest['chest'].inverted()
    shoulder=chest@rest[n].translation
    reach=sum(rig.data.bones[k+'_'+side].length for k in ('upper_arm','forearm','hand'))-.012
    delta=palm-shoulder
    adjusted=dict(rest);adjusted[n]=rest[n].copy()
    adjusted[n].translation+=chest.to_3x3().inverted()@(delta.normalized()*max(0,delta.length-reach))
    h.solve_arm(rig,adjusted,posed,side,palm)

assert not TARGET.exists() or '--replace-generated' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original={a.name:h.curves_digest(a) for a in bpy.data.actions if not a.library}
for a in bpy.data.actions:
    if not a.library:a.use_fake_user=True
# Original authored armed pose is the positional reference for the raised line.
old=next(s for s in bpy.data.scenes if s.get('preview_clip')=='armed_idle')
bpy.context.window.scene=old;old.frame_set(1)
oldrig=next(o for o in old.objects if o.type=='ARMATURE')
oldp=oldrig.evaluated_get(bpy.context.evaluated_depsgraph_get()).pose.bones['hand_r']
print('OLD_RAISED_PALM',list(oldp.tail),flush=True)
targets={'sidearm':tuple(oldp.tail),'longgun':(.20,.50,.34),'machinegun':(.22,.56,.30)}
templates=[s for s in bpy.data.scenes if s.get('preview_clip','').split('_')[0] in targets]
report={}
for template in templates:
    carry=template['preview_clip'];family,role=carry.split('_',1);state=family+'_fire_'+role
    scene=d.clone(template,f'{49+len(report):02}_{state}');bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
    prior=rig.animation_data.action;first,last=map(int,prior.frame_range);period=last-first
    samples=[]
    for f in range(first,last+1):
        scene.frame_set(f);er=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        samples.append({p.name:p.matrix.copy() for p in er.pose.bones})
    a=bpy.data.actions.new('anim_bunny01_'+state+'_v030')
    for k in prior.keys():a[k]=prior[k]
    a['state_id']=state;a['action_role']='fire';a['duration']=period/60;a['loop']=True
    rig.animation_data.action=a
    gun.animation_data.action=bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v030')
    gun.animation_data.action['preview_only']=True
    previous={}
    for i,posed in enumerate(samples):
        # Keep the exact source torso, lower body and directional ear response.
        shift=posed['chest'].translation-samples[0]['chest'].translation
        palm=Vector(targets[family])+shift
        solve(rig,rest,posed,'r',palm)
        if family!='sidearm':solve(rig,rest,posed,'l',palm+Vector(gun['support_local']))
        h.key_pose(rig,rest,posed,i+first,previous)
        gun.location=palm;gun.rotation_mode='QUATERNION';gun.rotation_quaternion=(1,0,0,0)
        for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+first)
    h.cyclic(a,period);h.cyclic(gun.animation_data.action,period)
    scene['preview_clip']=state;scene['production_status']='authored';scene['source_revision']='v030_firing'
    err=0.;preserved=0.;scale=0.;loop=0.;start=None
    for i in range(period*2+1):
        f=first+i/2;scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get()
        er=rig.evaluated_get(dg);gm=gun.evaluated_get(dg).matrix_world
        mats={p.name:p.matrix.copy() for p in er.pose.bones}
        if start is None:start=mats
        for side in ('r','l') if family!='sidearm' else ('r',):
            actual=er.pose.bones['hand_'+side].tail
            wanted=gm.translation+(Vector(gun['support_local']) if side=='l' else Vector())
            err=max(err,(actual-wanted).length)
        scale=max(scale,*(abs(v-1) for m in mats.values() for v in m.to_scale()))
        if i%2==0:
            for n in ('root','chest','head','ear_l','ear_r','foot_l','foot_r'):
                preserved=max(preserved,*(abs(mats[n][x][y]-samples[i//2][n][x][y]) for x in range(4) for y in range(4)))
    loop=max(abs(mats[n][x][y]-start[n][x][y]) for n in mats for x in range(4) for y in range(4))
    assert max(err,preserved,scale,loop)<1e-4,(state,err,preserved,scale,loop)
    report[state]=dict(grip_error=err,retained_body_ears_feet_error=preserved,unit_scale_error=scale,loop_error=loop,carry_source=carry)
    scene.frame_set(1);print('FIRING_AUTHORED',state,flush=True)
assert len(report)==27
assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'source_validation.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
print('V030_AUTHORED',len(report),flush=True)
