"""Three distinct reload overlays. Preserve all previous source actions."""
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
SOURCE=h.BASE/'source/animation/chr_bunny01_animation_v035.blend'
TARGET=h.BASE/'source/animation/chr_bunny01_animation_v036.blend'
OUT=h.ROOT/'outputs/character_pipeline/reload_v036'
assert not TARGET.exists() or '--replace-generated' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original={a.name:h.curves_digest(a) for a in bpy.data.actions if not a.library}
for a in bpy.data.actions:
    if not a.library:a.use_fake_user=True

def sample(keys,t):
    for (ta,pa),(tb,pb) in zip(keys,keys[1:]):
        if t<=tb:
            u=max(0,min(1,(t-ta)/(tb-ta)));u=u*u*(3-2*u)
            return pa.lerp(pb,u)
    return keys[-1][1].copy()

report={}
for family in ('machinegun',):
    old_scene=next(s for s in bpy.data.scenes if s.get('preview_clip')==family+'_reload')
    bpy.data.scenes.remove(old_scene)
    template=next(s for s in bpy.data.scenes if s.get('preview_clip')==family+'_idle')
    state=family+'_reload';scene=d.clone(template,'100_'+state)
    bpy.context.window.scene=scene;scene.frame_set(1)
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
    dg=bpy.context.evaluated_depsgraph_get();initial={p.name:p.matrix.copy() for p in rig.evaluated_get(dg).pose.bones}
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones};gm=gun.evaluated_get(dg).matrix_world.copy()
    start=gm.translation.copy();left0=initial['hand_l']@Vector((0,rig.data.bones['hand_l'].length,0))
    # All targets are authored in Blender character space (+Y forward).
    pwork=Vector((start.x+.12,start.y,start.z+.24))
    # Absolute source-space direction: +Y forward, -Z downward muzzle.
    # Raise the stock instead of rolling the old sideways carry pose.
    qwork=(Matrix.Rotation(-.12,4,'Z')@Matrix.Rotation(-math.pi/4,4,'X')).to_quaternion()
    # Service contact targets deliberately differ by family, not shared motion curves.
    contact=pwork+Vector({'sidearm':(-.06,-.025,-.12),'longgun':(-.14,.08,-.10),'machinegun':(-.15,.13,-.09)}[family])
    hip=Vector({'sidearm':(-.36,.23,.22),'longgun':(-.42,.20,.18),'machinegun':(-.48,.24,.16)}[family])
    service=contact+Vector({'sidearm':(.04,.015,.08),'longgun':(.02,.09,.05),'machinegun':(-.025,.16,.08)}[family])
    leftkeys=[(0,left0),(.18,contact),(.36,hip),(.52,hip),(.68,contact),(.78,service),(.86,contact),(1,left0)]
    rightkeys=[(0,start),(.18,pwork),(.38,pwork+Vector((.015,0,-.025))),(.56,pwork+Vector((-.015,0,.015))),(.70,pwork),(.80,pwork+Vector((0,0,-.025))),(1,start)]
    a=bpy.data.actions.new('anim_bunny01_'+state+'_v036');rig.animation_data.action=a
    a['state_id']=state;a['duration']=2.0;a['loop']=False;a['upper_body_only']=True;a['progress_owner']='WeaponModel3D'
    gun.animation_data.action=bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v036');gun.animation_data.action['preview_only']=True
    previous={}
    for i in range(241):
        t=i/240;posed={n:m.copy() for n,m in initial.items()}
        palm=sample(rightkeys,t)
        # Service hand follows the gun displacement during contact windows.
        follow=0 if t<=.08 or .36<=t<=.52 else min(1,(t-.08)/.1) if t<.18 else max(0,1-(t-.18)/.18) if t<.36 else min(1,(t-.52)/.16) if t<.68 else max(0,min(1,(1-t)/.14))
        solve(rig,rest,posed,'r',palm);solve(rig,rest,posed,'l',sample(leftkeys,t)+(palm-pwork)*follow)
        h.key_pose(rig,rest,posed,i+1,previous)
        u=min(1,t/.18,(1-t)/.14);u=max(0,u);u=u*u*(3-2*u)
        gun.location=palm;gun.rotation_mode='QUATERNION';gun.rotation_quaternion=gm.to_quaternion().slerp(qwork,u) @ Matrix.Rotation(math.sin(t*math.tau*2)*math.sin(t*math.pi)*.025,4,'X').to_quaternion()
        for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+1)
    for action in (a,gun.animation_data.action):
        action.use_fake_user=True;action.use_frame_range=True;action.frame_start=1;action.frame_end=241
        for curve in action.fcurves:
            curve.extrapolation='CONSTANT'
            for key in curve.keyframe_points:key.interpolation='LINEAR'
    scene['preview_clip']=state;scene['production_status']='authored';scene.frame_start=1;scene.frame_end=241;scene.render.fps=120
    scene.frame_set(1);report[state]={'duration':2.0,'loop':False,'progress_owner':'WeaponModel3D','overlay_tracks':['hand_l','hand_r','weapon_socket']}
assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'source_report.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
print('V036_SOURCE_SAVED',len(report),flush=True)
