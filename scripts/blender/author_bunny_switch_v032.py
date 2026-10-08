"""Four unarmed swing revisions and twelve source-authored stow/draw overlays."""
from pathlib import Path
import sys,ast,math,json
import bpy
from mathutils import Vector,Matrix
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_bunny_directional_v027 as d
h=d.h
tree=ast.parse((Path(__file__).parent/'author_bunny_firing_v030.py').read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='solve'],type_ignores=[]),'<solver>','exec'))
SOURCE=h.BASE/'source/animation/chr_bunny01_animation_v031.blend'
TARGET=h.BASE/'source/animation/chr_bunny01_animation_v032.blend'
OUT=h.ROOT/'outputs/character_pipeline/switch_v032'
assert not TARGET.exists() or '--replace-generated' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original={a.name:h.curves_digest(a) for a in bpy.data.actions if not a.library}
for a in bpy.data.actions:
    if not a.library:a.use_fake_user=True
report={}
for scene in list(bpy.data.scenes):
    state=scene.get('preview_clip','')
    if not state.startswith('unarmed_') or not state.endswith(('forward','backward')):continue
    bpy.context.window.scene=scene;rig=next(o for o in scene.objects if o.type=='ARMATURE')
    prior=rig.animation_data.action;first,last=map(int,prior.frame_range);period=last-first
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones};samples=[]
    for f in range(first,last+1):
        scene.frame_set(f);samples.append({p.name:p.matrix.copy() for p in rig.evaluated_get(bpy.context.evaluated_depsgraph_get()).pose.bones})
    a=bpy.data.actions.new('anim_bunny01_'+state+'_v032')
    for k in prior.keys():a[k]=prior[k]
    rig.animation_data.action=a;previous={}
    for i,source in enumerate(samples):
        posed={n:m.copy() for n,m in source.items()}
        for side in ('l','r'):
            phase=math.tau*i/period+(0 if side=='l' else math.pi)
            travel=(.22 if '_walking_' in state else .30)*math.sin(phase)
            if state.endswith('backward'):travel=-travel
            bob=source['chest'].translation-samples[0]['chest'].translation
            palm=Vector((-.38 if side=='l' else .38,travel,.35+.035*(1-math.cos(2*phase))))+bob
            solve(rig,rest,posed,side,palm)
        h.key_pose(rig,rest,posed,i+first,previous)
    h.cyclic(a,period);scene.frame_set(1);report[state]={'type':'swing','duration':period/60}

for family in ('sidearm','longgun','machinegun'):
    template=next(s for s in bpy.data.scenes if s.get('preview_clip')==family+'_idle')
    for slot in (0,1):
        for role in ('stow','draw'):
            state=f'{family}_{role}_slot{slot}';scene=d.clone(template,f'{80+len(report)}_{state}')
            bpy.context.window.scene=scene;scene.frame_set(1)
            rig=next(o for o in scene.objects if o.type=='ARMATURE');gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
            dg=bpy.context.evaluated_depsgraph_get();initial={p.name:p.matrix.copy() for p in rig.evaluated_get(dg).pose.bones}
            rest={b.name:b.matrix_local.copy() for b in rig.data.bones};gm=gun.evaluated_get(dg).matrix_world.copy()
            a=bpy.data.actions.new('anim_bunny01_'+state+'_v032');rig.animation_data.action=a
            a['state_id']=state;a['duration']=.45;a['loop']=False;a['upper_body_only']=True
            gun.animation_data.action=bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v032');gun.animation_data.action['preview_only']=True
            start=gm.translation;end=Vector((-.36 if slot==0 else .36,-.54,.82));via=Vector((.68,.02,.88))
            q0=gm.to_quaternion();q1=Matrix.Rotation(-math.pi/2,4,'X').to_quaternion();previous={}
            for i in range(109):
                t=i/108 if role=='stow' else 1-i/108
                if t<.55:
                    u=t/.55;u=u*u*(3-2*u);p=start.lerp(via,u)
                else:
                    u=(t-.55)/.45;u=u*u*(3-2*u);p=via.lerp(end,u)
                smooth=t*t*(3-2*t);q=q0.slerp(q1,smooth)
                posed={n:m.copy() for n,m in initial.items()};solve(rig,rest,posed,'r',p)
                # Left hand releases support early, settles beside the waist.
                left0=initial['hand_l']@Vector((0,rig.data.bones['hand_l'].length,0))
                release=min(1,t/.3);release=release*release*(3-2*release)
                solve(rig,rest,posed,'l',left0.lerp(Vector((-.38,.04,.34)),release))
                h.key_pose(rig,rest,posed,i+1,previous)
                gun.location=p;gun.rotation_mode='QUATERNION';gun.rotation_quaternion=q
                for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+1)
            for action in (a,gun.animation_data.action):
                action.use_fake_user=True;action.use_frame_range=True;action.frame_start=1;action.frame_end=109
                for curve in action.fcurves:
                    curve.extrapolation='CONSTANT'
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
            scene['preview_clip']=state;scene.frame_start=1;scene.frame_end=109;scene.render.fps=240
            scene.frame_set(1);report[state]={'type':role,'slot':slot,'duration':.45}
            print('AUTHORED',state,flush=True)
assert len(report)==16
assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'source_report.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
print('V032_SOURCE_SAVED',flush=True)
