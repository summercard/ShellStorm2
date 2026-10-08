"""Complete forward carry and all unarmed directions, retaining v028 sources."""
from pathlib import Path
import sys,math,json,hashlib
import bpy
from mathutils import Matrix,Vector
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_bunny_directional_v027 as d
h=d.h
SOURCE=h.BASE/'source/animation/chr_bunny01_animation_v028.blend'
TARGET=h.BASE/'source/animation/chr_bunny01_animation_v029.blend'
OUT=h.ROOT/'outputs/character_pipeline/runtime_v029'
DIRS=dict(d.DIRECTIONS,forward=(0,1,0))
assert not TARGET.exists() or '--replace-generated' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original={a.name:h.curves_digest(a) for a in bpy.data.actions if not a.library}
for a in bpy.data.actions:
    if not a.library:a.use_fake_user=True
specs={};validation={}
for family in ('sidearm','longgun','machinegun','unarmed'):
    for speed,(period,stance,lift) in d.SPEEDS.items():
        for direction in (DIRS if family=='unarmed' else ('forward',)):
            state=f'{family}_{speed}_{direction}'
            template=next(s for s in bpy.data.scenes if s.get('preview_clip')==('idle' if family=='unarmed' else family+'_idle'))
            scene=d.clone(template,f'{35+len(specs):02}_{state}');bpy.context.window.scene=scene;scene.frame_set(1)
            rig=next(o for o in scene.objects if o.type=='ARMATURE')
            gun=next((o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')),None) if family!='unarmed' else None
            er=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            initial={p.name:p.matrix.copy() for p in er.pose.bones};rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
            gm=gun.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world.copy() if gun else None
            rig.animation_data.action=bpy.data.actions.new('anim_bunny01_'+state+'_v029');a=rig.animation_data.action
            for k,v in dict(state_id=state,duration=period/60,loop=True,weapon_family=family,direction=direction,speed_role=speed).items():a[k]=v
            if gun:
                gun.animation_data.action=bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v029');gun.animation_data.action['preview_only']=True
            scene['preview_clip']=state;scene['asset_id']='CHR-PLY-CAPSULE01-3D-BUNNY01';scene['production_status']='authored_pending_export'
            scene.render.fps=60;scene.frame_start=1;scene.frame_end=period
            scene.use_preview_range=True;scene.frame_preview_start=1;scene.frame_preview_end=period
            travel=Vector(DIRS[direction]);lateral=direction.startswith('strafe')
            span=(.12 if lateral else .19)*(1.12 if speed=='moving' else 1)*(.88 if family=='machinegun' else 1)
            specs[state]=dict(family=family,speed=speed,direction=direction,period=period,stance=stance,lift=lift,stride_m=span,reference_speed_mps=span/(stance*period/60))
            shoes={s:next(o for o in scene.objects if o.get('component_id')=='foot_'+s) for s in ('l','r')}
            floor={s:min((initial['foot_'+s]@rest['foot_'+s].inverted()@v.co).z for v in o.data.vertices) for s,o in shoes.items()}
            previous={}
            for i in range(period+1):
                w=math.tau*i/period
                shift=Vector(((.007 if family=='machinegun' else .011)*math.sin(w),0,(.010 if speed=='walking' else .018)*(1-math.cos(2*w))/2))
                upper=Matrix.Translation(shift)
                posed={n:(m.copy() if n=='root' or n.startswith(('foot_','thigh_','shin_')) else upper@m) for n,m in initial.items()}
                for s in ('l','r'):
                    lead=s==('r' if direction=='strafe_right' else 'l')
                    phase=(i/period+(0 if lead else .5))%1
                    pos,z,_=d.phase_path(phase,stance,span,lift*(.85 if family=='machinegun' else 1))
                    p=initial['foot_'+s].translation+travel*pos
                    if lateral:p.x+=-.035 if s=='l' else .035
                    p.z+=z-floor[s];posed['foot_'+s]=initial['foot_'+s].copy();posed['foot_'+s].translation=p
                    hip=posed['waist']@rest['waist'].inverted()@rest['thigh_'+s].translation;knee=(hip+p)*.5+Vector((0,.025,0))
                    posed['thigh_'+s]=h.along(rest['thigh_'+s],hip,knee-hip);posed['shin_'+s]=h.along(rest['shin_'+s],knee,p-knee)
                    if family=='unarmed':
                        shoulder=posed['upper_arm_'+s].translation
                        swing=Matrix.Translation(shoulder)@Matrix.Rotation((1 if s=='l' else -1)*.10*math.sin(w),4,'X')@Matrix.Translation(-shoulder)
                        for part in ('upper_arm_','forearm_','hand_'):
                            posed[part+s]=swing@posed[part+s]
                    n='ear_'+s;m=posed[n];pivot=m.translation
                    angle=math.radians((16 if speed=='moving' else 10)+(4.5 if speed=='moving' else 3)*math.sin(2*w-.65-(.32 if s=='r' else 0))+1.2*math.sin(w-.9-(.32 if s=='r' else 0)))
                    posed[n]=Matrix.Translation(pivot)@Matrix.Rotation(angle,4,Vector((0,0,1)).cross(-travel).normalized())@Matrix.Translation(-pivot)@m
                h.key_pose(rig,rest,posed,i+1,previous)
                if gun:
                    matrix=upper@gm;gun.location=matrix.translation;gun.rotation_mode='QUATERNION';gun.rotation_quaternion=matrix.to_quaternion()
                    for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+1)
            h.cyclic(a,period)
            if gun:h.cyclic(gun.animation_data.action,period)
            # Check roots/scale/loop/ground from evaluated geometry, not source parameters.
            first=None;ground=10.;err=0.
            for i in range(period*2+1):
                f=1+i/2;scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get();er=rig.evaluated_get(dg)
                mats={p.name:p.matrix.copy() for p in er.pose.bones}
                if first is None:first=mats
                err=max(err,*(abs(v-1) for m in mats.values() for v in m.to_scale()))
                if gun:
                    actual=gun.evaluated_get(dg).matrix_world
                    palm=mats['hand_r']@Vector((0,rig.data.bones['hand_r'].length,0))
                    err=max(err,(palm-actual.translation).length)
                if i%4==0:
                    for o in shoes.values():
                        eo=o.evaluated_get(dg);me=eo.to_mesh();ground=min(ground,min((eo.matrix_world@v.co).z for v in me.vertices));eo.to_mesh_clear()
            loop=max(abs(mats[n][x][y]-first[n][x][y]) for n in mats for x in range(4) for y in range(4))
            assert err<1e-4 and loop<1e-4 and ground>-.002,(state,err,loop,ground)
            validation[state]=dict(scale_error=err,loop_error=loop,foot_ground_min=ground)
            scene.frame_set(1);print('COMPLETED',state,flush=True)
assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'new_specs.json').write_text(json.dumps(specs,indent=2))
(OUT/'new_source_validation.json').write_text(json.dumps(validation,indent=2))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
print('V029_SOURCE_COMPLETE',len(specs))
