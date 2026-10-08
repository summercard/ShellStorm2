"""Independent direction/contact/pose-preservation check against v026."""
from pathlib import Path
import bpy,json,math
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'outputs/character_pipeline/directional_v027'
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/animation'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'chr_bunny01_animation_v026.blend'))
reference={}
for family in ('sidearm','longgun','machinegun'):
    s=next(s for s in bpy.data.scenes if s.get('preview_clip')==family+'_idle');bpy.context.window.scene=s;s.frame_set(1)
    dg=bpy.context.evaluated_depsgraph_get();r=next(o for o in s.objects if o.type=='ARMATURE').evaluated_get(dg)
    g=next(o for o in s.objects if o.name.startswith('PREVIEW_GripSocket')).evaluated_get(dg)
    reference[family]={n:g.matrix_world.inverted()@r.pose.bones[n].matrix for n in ['chest','head','hand_l','hand_r']}
bpy.ops.wm.open_mainfile(filepath=str(BASE/'chr_bunny01_animation_v027.blend'))
specs=json.loads((OUT/'specs.json').read_text());report={}
for state,sp in specs.items():
    s=next(s for s in bpy.data.scenes if s.get('preview_clip')==state);bpy.context.window.scene=s
    rig=next(o for o in s.objects if o.type=='ARMATURE');gun=next(o for o in s.objects if o.name.startswith('PREVIEW_GripSocket'))
    upper_error=0.;stance_error=0.;swings={side:[] for side in ('l','r')}
    direction=Vector((-1,0,0) if sp['direction']=='strafe_left' else (1,0,0) if sp['direction']=='strafe_right' else (0,-1,0))
    previous={}
    for i in range(sp['period']*4+1):
        frame=1+i/4;s.frame_set(int(frame),subframe=frame%1);dg=bpy.context.evaluated_depsgraph_get();r=rig.evaluated_get(dg);g=gun.evaluated_get(dg)
        for n,m in reference[sp['family']].items():
            actual=g.matrix_world.inverted()@r.pose.bones[n].matrix
            upper_error=max(upper_error,max(abs(actual[a][b]-m[a][b]) for a in range(4) for b in range(4)))
        for side in ('l','r'):
            phase=((frame-1)/sp['period']+(0 if side==('r' if sp['direction']=='strafe_right' else 'l') else .5))%1
            p=r.pose.bones['foot_'+side].matrix.translation.copy();swings[side].append(list(p))
            if side in previous and .06<phase<sp['stance']-.06:
                v=(p-previous[side])/(.25/60)
                stance_error=max(stance_error,(v+direction*sp['reference_speed_mps']).length)
            previous[side]=p
    # Stationary source root, stance foot moves opposite intended travel. Runtime
    # must match recorded author-space speed; no claim of runtime foot locking.
    assert upper_error<1e-4 and stance_error<.03,(state,upper_error,stance_error)
    for side,points in swings.items():assert max(p[2] for p in points)-min(p[2] for p in points)>.035
    report[state]={'v026_upper_pose_relative_error':upper_error,'stance_velocity_error_mps':stance_error,'author_speed_mps':sp['reference_speed_mps'],'lift_m':{side:max(p[2] for p in points)-min(p[2] for p in points) for side,points in swings.items()}}
(OUT/'direction_contact_validation.json').write_text(json.dumps(report,indent=2))
print('DIRECTION_CONTACT_VALIDATED',len(report))
