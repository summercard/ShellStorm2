"""Independently inspect saved v039 bones and their evaluated subframes."""
from pathlib import Path
import sys, json, math
import bpy
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(R/'scripts'))
sys.path.insert(0,str(Path(__file__).parent))
from workspace_paths import work_path
from export_character_bundle import signature
from refine_bunny_motion_v039 import SOURCE, TARGET, selected as target
O=work_path('sessions/2026-10-15_player_motion_v039/source_validation.json')
MODEL=R/'art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/source/model/chr_bunny01_model_v021.blend'
bpy.ops.wm.open_mainfile(filepath=str(MODEL))
expected=signature(next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'))
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
report={}
for scene in bpy.data.scenes:
    state=scene.get('preview_clip','')
    if not target(state):continue
    bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    gun=next((o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')),None)
    assert signature(rig)==expected,state
    a=rig.animation_data.action
    first,last=map(int,a.frame_range)
    beginning=None; heights=[]; yaw=[]; err={'grip':0.,'support':0.,'scale':0.,'root':0.,'loop':0.,'aim':0.}
    for j in range((last-first)*2+1):
        f=first+j*.5;scene.frame_set(int(f),subframe=f%1)
        dg=bpy.context.evaluated_depsgraph_get()
        mats={p.name:p.matrix.copy() for p in rig.evaluated_get(dg).pose.bones}
        if beginning is None:beginning=mats
        heights.append(mats['head'].translation.z)
        # Rest-relative chest orientation avoids the rest bone's axis rotation.
        q=(mats['chest']@rig.data.bones['chest'].matrix_local.inverted()).to_quaternion()
        forward=q@Vector((0,1,0));yaw.append(math.degrees(math.atan2(-forward.x,forward.y)))
        err['scale']=max(err['scale'],*(abs(v-1) for m in mats.values() for v in m.to_scale()))
        err['root']=max(err['root'],*(abs(mats['root'][x][y]-beginning['root'][x][y]) for x in range(4) for y in range(4)))
        if gun:
            gm=gun.evaluated_get(dg).matrix_world
            for side in ('r','l') if not state.startswith('sidearm_') else ('r',):
                palm=mats['hand_'+side]@Vector((0,rig.data.bones['hand_'+side].length,0))
                wanted=gm.translation+gm.to_quaternion()@Vector(gun['support_local']) if side=='l' else gm.translation
                key='support' if side=='l' else 'grip'
                err[key]=max(err[key],(palm-wanted).length)
            if '_fire_' in state:
                err['aim']=max(err['aim'],((gm.to_quaternion()@Vector((0,1,0)))-Vector((0,1,0))).length)
    err['loop']=max(abs(mats[n][x][y]-beginning[n][x][y]) for n in mats for x in range(4) for y in range(4))
    # Subframe interpolation may introduce sub-millimeter chord error, never visible separation.
    assert max(err.values())<.0005,(state,err)
    assert max(heights)-min(heights)>(.018 if state=='idle' or state.endswith('_idle') else .028),(state,heights)
    assert max(yaw)-min(yaw)>(4.0 if state=='idle' or state.endswith('_idle') else 6.0),(state,yaw)
    report[state]=dict(errors=err,head_vertical_range_m=max(heights)-min(heights),body_yaw_range_deg=max(yaw)-min(yaw),samples=(last-first)*2+1)
    print('CHECKED',state,report[state]['head_vertical_range_m'],report[state]['body_yaw_range_deg'],flush=True)
assert len(report)==63
O.write_text(json.dumps(dict(skeleton_sha256=expected,clips=report,expected_errors=[],unexpected_errors=[]),indent=2))
print('SOURCE_VALIDATION_OK',len(report))
