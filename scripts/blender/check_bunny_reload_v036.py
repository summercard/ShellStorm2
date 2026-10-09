"""Reopen the saved source; check subframes and distinct service-hand paths."""
from pathlib import Path
import sys,json,math
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_bunny_weapon_idles_v025 as h
bpy.ops.wm.open_mainfile(filepath=str(h.BASE/'source/animation/chr_bunny01_animation_v036.blend'))
report={}
for scene in bpy.data.scenes:
    name=scene.get('preview_clip','')
    if not name.endswith('_reload'):continue
    bpy.context.window.scene=scene;rig=next(o for o in scene.objects if o.type=='ARMATURE');gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
    a=rig.animation_data.action;assert not a['loop'] and abs(a['duration']-2)<1e-6
    grip=0.;scale=0.;left=[];right=[];rotations=[]
    for i in range(481):
        f=1+i/2;scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get();er=rig.evaluated_get(dg)
        rotations.append(gun.evaluated_get(dg).matrix_world.to_quaternion())
        grip=max(grip,(er.pose.bones['hand_r'].tail-gun.evaluated_get(dg).matrix_world.translation).length)
        scale=max(scale,*(abs(s-1) for b in er.pose.bones for s in b.matrix.to_scale()))
        left.append(er.pose.bones['hand_l'].tail.copy());right.append(er.pose.bones['hand_r'].tail.copy())
    span=max((p-left[0]).length for p in left)
    assert grip<.002 and scale<1e-4 and span>.2,(name,grip,scale,span)
    assert (left[0]-left[-1]).length<1e-4 and (right[0]-right[-1]).length<1e-4
    gun_travel=max((p-right[0]).length for p in right)
    gun_angle=max(rotations[0].rotation_difference(q).angle for q in rotations)
    if name!='sidearm_reload':assert gun_travel>.20 and gun_angle>.45,(name,gun_travel,gun_angle)
    if name=='machinegun_reload':
        scene.frame_set(97);dg=bpy.context.evaluated_depsgraph_get()
        work=gun.evaluated_get(dg).matrix_world
        forward=work.to_quaternion()@Vector((0,1,0))
        assert abs(math.degrees(math.asin(-forward.z))-45)<2,tuple(forward)
        assert max(abs(p.y-right[0].y) for p in right)<.0001,'Gun pushed forward'
        assert work.translation.z-right[0].z<.27
        assert work.translation.z-right[0].z>.20
        print('MACHINEGUN_WORK_FORWARD',tuple(forward),'GRIP_HEIGHT',work.translation.z)
    report[name]={'gun_travel_m':gun_travel,'gun_rotation_degrees':gun_angle*180/3.14159265,'grip_error_m':grip,'unit_scale_error':scale,'service_hand_travel_m':span,'samples':481}
assert len(report)==3
(h.ROOT/'outputs/character_pipeline/reload_v036/source_validation.json').write_text(json.dumps(report,indent=2))
print('V036_SOURCE_VALIDATED',len(report))
