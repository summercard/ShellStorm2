"""Increase saved v038 locomotion and idle expression; preserve user runtime rates."""
from pathlib import Path
import sys, math, json
import bpy
from mathutils import Matrix, Vector
sys.path.insert(0,str(Path(__file__).parent))
import refine_bunny_locomotion_v038 as prior
from workspace_paths import work_path
h=prior.h
SOURCE=prior.TARGET
if not SOURCE.exists():
    SOURCE=prior.ROOT.parent/'ShellStorm2-backup/2026-10-15_player_motion_v039/before_edits'/SOURCE.relative_to(prior.ROOT)
TARGET=SOURCE.with_name('chr_bunny01_animation_v039.blend')
OUT=work_path('sessions/2026-10-15_player_motion_v039/source_report.json').parent
IDLES={'idle','sidearm_idle','longgun_idle','machinegun_idle','sidearm_fire_idle','longgun_fire_idle','machinegun_fire_idle'}

def selected(state):return prior.target(state) or state in IDLES

def build():
    assert not TARGET.exists() or '--replace-generated' in sys.argv
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    # Archived masters retain their relative links; point them back at the
    # current model library before evaluating the saved pose Actions.
    for library in bpy.data.libraries:
        if not Path(bpy.path.abspath(library.filepath)).exists():
            model=prior.ROOT/'art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/source/model'/Path(library.filepath).name
            assert model.exists(),library.filepath
            library.filepath=str(model)
            library.reload()
    report={}
    for scene in list(bpy.data.scenes):
        state=scene.get('preview_clip','')
        if not selected(state):continue
        bpy.context.window.scene=scene
        rig=next(o for o in scene.objects if o.type=='ARMATURE')
        gun=next((o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')),None)
        rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
        old=rig.animation_data.action;first,last=map(int,old.frame_range)
        samples=[]
        for f in range(first,last+1):
            scene.frame_set(f);dg=bpy.context.evaluated_depsgraph_get()
            samples.append(({p.name:p.matrix.copy() for p in rig.evaluated_get(dg).pose.bones},gun.evaluated_get(dg).matrix_world.copy() if gun else None))
        action=bpy.data.actions.new('anim_bunny01_'+state+'_v039')
        for k in old.keys():action[k]=old[k]
        prior.set_action(rig,action)
        if gun:
            prior.set_action(gun,bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v039'))
            gun.animation_data.action['preview_only']=True
        idle=state in IDLES;moving='_moving_' in state;firing='_fire_' in state
        weight=.78 if state.startswith('machinegun') else 1.0
        yaw=math.radians(5.5 if idle else 5.0 if moving else 2.5)*weight*(.65 if firing else 1)
        duration=float(old['duration'])*(.75 if idle else .875 if moving else .92)
        action['duration']=duration;action['source_revision']='v039_expressive_idle_jog';action['state_id']=state
        previous={}
        for i,(original,gm) in enumerate(samples):
            phase=math.tau*i/(last-first)
            swing=math.sin(phase)*(-1 if state.endswith('strafe_right') else 1)
            bounce=(1-math.cos(phase if idle else 2*phase))*.5
            pivot=Vector((0,0,original['chest'].translation.z))
            shift=Vector((.014*weight*math.sin(phase) if idle else 0,0,(.018 if idle else .020 if moving else .010)*weight*bounce))
            upper=Matrix.Translation(shift)@Matrix.Translation(pivot)@Matrix.Rotation(yaw*swing,4,'Z')@Matrix.Rotation(math.radians(1.6 if idle else 1.8 if moving else 1)*swing,4,'Y')@Matrix.Translation(-pivot)
            posed={n:(m.copy() if n=='root' or n.startswith(('foot_','thigh_','shin_')) else upper@m) for n,m in original.items()}
            hp=original['head'].translation
            hs=Vector((.009*math.sin(phase-.4) if idle else 0,0,shift.z+(.010 if idle else .008 if moving else .004)*bounce))
            head=Matrix.Translation(hs)@Matrix.Translation(hp)@Matrix.Rotation(math.radians(1.7 if idle else .9)*math.sin(phase-.4),4,'Z')@Matrix.Rotation(math.radians(1.2 if idle else .8)*math.sin((1 if idle else 2)*phase-.6),4,'X')@Matrix.Translation(-hp)
            for n in ('head','ear_l','ear_r'):posed[n]=head@original[n]
            if idle:
                for side in ('l','r'):
                    n='ear_'+side;p=posed[n].translation
                    ear=Matrix.Translation(p)@Matrix.Rotation(math.radians(3.5)*math.sin(phase-.7-(.3 if side=='r' else 0)),4,'Y')@Matrix.Translation(-p)
                    posed[n]=ear@posed[n]
            if gun:
                ng=upper@gm
                if firing:
                    ng=gm.copy();ng.translation=(upper@gm).translation
                    prior.solve(rig,rest,posed,'r',ng.translation)
                    if not state.startswith('sidearm'):
                        prior.solve(rig,rest,posed,'l',ng.translation+ng.to_quaternion()@Vector(gun['support_local']))
                gun.location=ng.translation;gun.rotation_mode='QUATERNION';gun.rotation_quaternion=ng.to_quaternion()
                for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+first)
            h.key_pose(rig,rest,posed,i+first,previous)
        for a in [action]+([gun.animation_data.action] if gun else []):
            a.use_fake_user=True;a.use_frame_range=True;a.frame_start=first;a.frame_end=last;a.use_cyclic=True
            for c in prior.curves(a):
                c.extrapolation='CONSTANT'
                for key in c.keyframe_points:key.interpolation='LINEAR'
        # Keep preview timing equal to the exported action duration.
        scene.render.fps=60;scene.render.fps_base=duration*60/(last-first)
        scene['source_revision']='v039_expressive_idle_jog';scene.frame_set(first)
        report[state]=dict(previous_duration=float(old['duration']),duration=duration,extra_yaw_deg=math.degrees(yaw),idle=idle,frames=last-first+1)
        print('AUTHORED',state,round(duration,3),flush=True)
    assert len(report)==63,len(report)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
    (OUT/'source_report.json').write_text(json.dumps(report,indent=2))

if __name__=='__main__':build()
