"""Ear-only directional follow-through; retain all v027 limb/gun curves."""
from pathlib import Path
import sys, math, json, hashlib
import bpy
from mathutils import Matrix, Vector
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import author_bunny_directional_v027 as d
h = d.h
SOURCE = h.BASE/'source/animation/chr_bunny01_animation_v027.blend'
TARGET = h.BASE/'source/animation/chr_bunny01_animation_v028.blend'
OUT = h.ROOT/'outputs/character_pipeline/directional_v028'
TRANSFER = h.BASE/'source/animation/chr_bunny01_directional_v028.json'
SPECS = json.loads((d.OUT/'specs.json').read_text())
EARS = ('ear_l', 'ear_r')

def build():
    assert not TARGET.exists(), 'Never overwrite a delivered source'
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    original = {a.name:h.curves_digest(a) for a in bpy.data.actions if not a.library}
    for a in bpy.data.actions:
        if not a.library:a.use_fake_user=True
    reference = {}
    for state,sp in SPECS.items():
        scene=next(s for s in bpy.data.scenes if s.get('preview_clip')==state)
        bpy.context.window.scene=scene
        rig=next(o for o in scene.objects if o.type=='ARMATURE')
        action=rig.animation_data.action
        samples=[]; ref=[]
        for i in range(sp['period']*2+1):
            f=1+i/2;scene.frame_set(int(f),subframe=f%1)
            er=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mats={n:er.pose.bones[n].matrix.copy() for n in (*EARS,'head')}
            ref.append({n:[list(row) for row in m] for n,m in mats.items()})
            if i%2==0:samples.append(mats)
        reference[state]=ref
        new=action.copy();new.name=action.name.replace('_v027','_v028');new.use_fake_user=True
        rig.animation_data.action=new
        new['ear_follow_through']='opposite local travel, two-ear phase lag'
        lag=-Vector(d.DIRECTIONS[sp['direction']]);axis=Vector((0,0,1)).cross(lag).normalized()
        fast=sp['speed']=='moving'
        sp['ear_mean_degrees']=16 if fast else 10
        sp['ear_pulse_degrees']=4.5 if fast else 3
        previous={}
        for i,mats in enumerate(samples):
            phase=math.tau*i/sp['period']
            for side,n in enumerate(EARS):
                angle=math.radians(sp['ear_mean_degrees']+sp['ear_pulse_degrees']*math.sin(2*phase-.65-side*.32)+1.2*math.sin(phase-.9-side*.32))
                m=mats[n];pivot=m.translation
                posed=Matrix.Translation(pivot)@Matrix.Rotation(angle,4,axis)@Matrix.Translation(-pivot)@m
                bone=rig.data.bones[n];p=rig.pose.bones[n]
                basis=bone.convert_local_to_pose(posed,bone.matrix_local,parent_matrix=mats['head'],parent_matrix_local=bone.parent.matrix_local,invert=True)
                q=basis.to_quaternion()
                if n in previous and previous[n].dot(q)<0:q.negate()
                previous[n]=q.copy();p.rotation_mode='QUATERNION';p.rotation_quaternion=q
                p.keyframe_insert('rotation_quaternion',frame=i+1,group=n)
        # Copy retains original cyclic modifiers and all other F-curves verbatim.
        for oldcurve,newcurve in zip(action.fcurves,new.fcurves):
            if oldcurve.data_path in [f'pose.bones["{n}"].rotation_quaternion' for n in EARS]:continue
            assert oldcurve.data_path==newcurve.data_path
            assert [(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right)) for k in oldcurve.keyframe_points]==[(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right)) for k in newcurve.keyframe_points]
        scene['ear_revision']='v028';scene.frame_set(1)
        print('EAR_AUTHORED',state,flush=True)
    assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
    OUT.mkdir(parents=True,exist_ok=True)
    for name,value in [('original_actions',original),('specs',SPECS),('ear_reference',reference)]:
        (OUT/(name+'.json')).write_text(json.dumps(value,indent=2),encoding='utf-8')
    bpy.context.window.scene=next(s for s in bpy.data.scenes if s.get('preview_clip')=='sidearm_moving_strafe_left')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)

def check_ears():
    bpy.ops.wm.open_mainfile(filepath=str(TARGET))
    reference=json.loads((OUT/'ear_reference.json').read_text())
    report={}
    for state,sp in SPECS.items():
        scene=next(s for s in bpy.data.scenes if s.get('preview_clip')==state);bpy.context.window.scene=scene
        rig=next(o for o in scene.objects if o.type=='ARMATURE')
        lag=-Vector(d.DIRECTIONS[sp['direction']]);offsets={n:[] for n in EARS};base_error=0.;first=None
        for i,ref in enumerate(reference[state]):
            f=1+i/2;scene.frame_set(int(f),subframe=f%1)
            er=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mats={n:er.pose.bones[n].matrix.copy() for n in EARS}
            if first is None:first=mats
            for n,m in mats.items():
                old=Matrix(ref[n]);tip=Vector((0,rig.data.bones[n].length,0))
                offsets[n].append((m@tip-old@tip).dot(lag))
                base_error=max(base_error,(m.translation-old.translation).length)
        loop=max(abs(mats[n][a][b]-first[n][a][b]) for n in EARS for a in range(4) for b in range(4))
        assert base_error<1e-5 and loop<1e-5,(state,base_error,loop)
        assert all(min(v)>.025 and max(v)-min(v)>.02 for v in offsets.values()),(state,offsets)
        report[state]=dict(ear_root_error=base_error,loop_error=loop,tip_opposite_travel_m={n:dict(min=min(v),max=max(v)) for n,v in offsets.items()})
    (OUT/'ear_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('EAR_VALIDATED',len(report),flush=True)

if __name__=='__main__':
    if '--verify-only' not in sys.argv:build()
    check_ears()
    d.SOURCE=SOURCE;d.TARGET=TARGET;d.OUT=OUT;d.TRANSFER=TRANSFER;d.SPECS=SPECS
    d.verify()
    data=json.loads(TRANSFER.read_text(encoding='utf-8'))
    data.update(version='v028',note='v027 directional clips refined only on ear rotations; opposite-travel drag and delayed cyclic rebound. All weapon, body and foot curves unchanged. Source-only, no runtime binding.',ear_validation=json.loads((OUT/'ear_validation.json').read_text()))
    TRANSFER.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    print('V028_COMPLETE',flush=True)
