"""18 independently authored lateral/backward carry loops from v026 poses."""
from pathlib import Path
import sys,math,json,hashlib
import bpy
from mathutils import Matrix,Vector
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_bunny_weapon_idles_v025 as h

SOURCE=h.BASE/'source/animation/chr_bunny01_animation_v026.blend'
TARGET=h.BASE/'source/animation/chr_bunny01_animation_v027.blend'
OUT=h.ROOT/'outputs/character_pipeline/directional_v027'
TRANSFER=h.BASE/'source/animation/chr_bunny01_directional_v027.json'
DIRECTIONS={'strafe_left':(-1,0,0),'strafe_right':(1,0,0),'backward':(0,-1,0)}
SPEEDS={'walking':(60,.55,.05),'moving':(48,.50,.075)}
SPECS={}
for family in h.SPECS:
    for speed,(period,stance,lift) in SPEEDS.items():
        for direction in DIRECTIONS:
            state=f'{family}_{speed}_{direction}'
            SPECS[state]=dict(family=family,speed=speed,direction=direction,period=period,stance=stance,lift=lift)

def phase_path(t,stance,span,lift):
    if t<stance:
        return span/2-span*t/stance,0.,True
    u=(t-stance)/(1-stance)
    # Hermite recovery matches the support velocity at both endpoints.
    tangent=-span*(1-stance)/stance
    x=(2*u**3-3*u*u+1)*(-span/2)+(u**3-2*u*u+u)*tangent+(-2*u**3+3*u*u)*(span/2)+(u**3-u*u)*tangent
    return x,lift*math.sin(math.pi*u)**2,False

def clone(template,name):
    s=bpy.data.scenes.new(name)
    mapping={}
    for o in template.objects:
        n=o.copy();s.collection.objects.link(n);mapping[o]=n
    for o,n in mapping.items():
        if o.parent in mapping:n.parent=mapping[o.parent]
        for m in n.modifiers:
            if m.type=='ARMATURE' and m.object in mapping:m.object=mapping[m.object]
        for c in n.constraints:
            if getattr(c,'target',None) in mapping:c.target=mapping[c.target]
    s.camera=mapping.get(template.camera)
    return s

def build():
    assert not TARGET.exists() or '--replace-generated' in sys.argv
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    original={a.name:h.curves_digest(a) for a in bpy.data.actions if not a.library}
    for a in bpy.data.actions:
        if not a.library:a.use_fake_user=True
    for number,(state,sp) in enumerate(SPECS.items(),17):
        template=next(s for s in bpy.data.scenes if s.get('preview_clip')==sp['family']+'_idle')
        scene=clone(template,f'{number:02}_{state}')
        bpy.context.window.scene=scene;scene.frame_set(1)
        rig=next(o for o in scene.objects if o.type=='ARMATURE')
        gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
        dg=bpy.context.evaluated_depsgraph_get()
        initial={p.name:p.matrix.copy() for p in rig.evaluated_get(dg).pose.bones}
        gun_initial=gun.evaluated_get(dg).matrix_world.copy()
        print('INITIAL_GRIP',state,list(gun_initial.translation),list(initial['hand_r']@Vector((0,rig.data.bones['hand_r'].length,0))),flush=True)
        rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
        rig.animation_data.action=bpy.data.actions.new('anim_bunny01_'+state+'_v027')
        gun.animation_data.action=bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v027')
        gun.animation_data.action['preview_only']=True
        rig.name='RIG_bunny01_'+state
        action=rig.animation_data.action
        for k,v in dict(state_id=state,gameplay_state='moving',weapon_family=sp['family'],direction=sp['direction'],speed_role=sp['speed'],duration=sp['period']/60,loop=True).items():action[k]=v
        scene['preview_clip']=state;scene['production_status']='authored_pending_export';scene['asset_id']='CHR-PLY-CAPSULE01-3D-BUNNY01'
        scene.render.fps=60;scene.frame_start=1;scene.frame_end=sp['period'];scene.use_preview_range=True;scene.frame_preview_start=1;scene.frame_preview_end=sp['period']
        direction=Vector(DIRECTIONS[sp['direction']]);back=sp['direction']=='backward'
        span=(.19 if back else .12)*(1.12 if sp['speed']=='moving' else 1)*( .88 if sp['family']=='machinegun' else 1)
        sp['stride_m']=span;sp['reference_speed_mps']=span/(sp['stance']*sp['period']/60)
        shoes={side:next(o for o in scene.objects if o.get('component_id')=='foot_'+side) for side in ('l','r')}
        local_bottom={side:min((initial['foot_'+side]@rest['foot_'+side].inverted()@v.co).z for v in shoes[side].data.vertices) for side in shoes}
        previous={}
        for i in range(sp['period']+1):
            t=i/sp['period'];w=math.tau*t
            bob=(.010 if sp['speed']=='walking' else .018)*(1-math.cos(2*w))/2
            weight=.007 if sp['family']=='machinegun' else .011
            shift=Vector((weight*math.sin(w),-.006 if back else 0,bob))
            upper=Matrix.Translation(shift)
            posed={n:(m.copy() if n=='root' or n.startswith(('foot_','thigh_','shin_')) else upper@m) for n,m in initial.items()}
            for side in ('l','r'):
                leading=side==('r' if sp['direction']=='strafe_right' else 'l')
                phase=(t+(.0 if leading else .5))%1
                pos,z,_=phase_path(phase,sp['stance'],span,sp['lift']*(.85 if sp['family']=='machinegun' else 1))
                foot='foot_'+side
                p=initial[foot].translation+direction*pos
                if not back:p.x+=-.035 if side=='l' else .035
                p.z+=z-local_bottom[side]
                posed[foot]=initial[foot].copy();posed[foot].translation=p
                # Helpers remain articulated; floating feet are the approved rig.
                hip=posed['waist']@rest['waist'].inverted()@rest['thigh_'+side].translation
                knee=(hip+p)*.5+Vector((0,.025,0))
                posed['thigh_'+side]=h.along(rest['thigh_'+side],hip,knee-hip)
                posed['shin_'+side]=h.along(rest['shin_'+side],knee,p-knee)
            h.key_pose(rig,rest,posed,i+1,previous)
            gm=upper@gun_initial;gun.location=gm.translation;gun.rotation_mode='QUATERNION';gun.rotation_quaternion=gm.to_quaternion()
            for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+1)
        h.cyclic(action,sp['period']);h.cyclic(gun.animation_data.action,sp['period'])
        cam=h.setup_camera(scene);h.point_camera(cam,(2.6,4,1.8));scene.render.resolution_x=scene.render.resolution_y=400
        scene.frame_set(1)
        print('AUTHORED',state,flush=True)
    assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'original_actions.json').write_text(json.dumps(original,indent=2),encoding='utf-8')
    (OUT/'specs.json').write_text(json.dumps(SPECS,indent=2),encoding='utf-8')
    bpy.context.window.scene=next(s for s in bpy.data.scenes if s.get('preview_clip')=='sidearm_moving_strafe_left')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)

def verify():
    bpy.ops.wm.open_mainfile(filepath=str(TARGET))
    original=json.loads((OUT/'original_actions.json').read_text())
    assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
    report={}
    for state,sp in SPECS.items():
        scene=next(s for s in bpy.data.scenes if s.get('preview_clip')==state);bpy.context.window.scene=scene
        rig=next(o for o in scene.objects if o.type=='ARMATURE');gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
        assert h.signature(rig)=='203cbcaf9a7d4eaa55baacc6ea4d2093e157ad853ecab5bf08abb8a38f41edb8'
        err=dict(scale=0.,grip=0.,support=0.,loop=0.,root=0.,face=0.,arm=0.);ground=10.;first=None
        for i in range(sp['period']*2+1):
            f=1+i/2;scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get()
            er=rig.evaluated_get(dg);eg=gun.evaluated_get(dg);mats={p.name:p.matrix.copy() for p in er.pose.bones}
            if first is None:first=mats
            err['scale']=max(err['scale'],*(abs(v-1) for m in mats.values() for v in m.to_scale()))
            err['root']=max(err['root'],*(abs(mats['root'][a][b]-first['root'][a][b]) for a in range(4) for b in range(4)))
            err['face']=max(err['face'],mats['head'].to_quaternion().rotation_difference(first['head'].to_quaternion()).angle)
            for side in ('l','r'):
                palm=mats['hand_'+side]@Vector((0,rig.data.bones['hand_'+side].length,0))
                target=eg.matrix_world.translation.copy()
                if side=='l':target+=eg.matrix_world.to_quaternion()@Vector(gun['support_local'])
                if side=='r' or sp['family']!='sidearm':
                    k='grip' if side=='r' else 'support';err[k]=max(err[k],(palm-target).length)
                for a,b in [('upper_arm_','forearm_'),('forearm_','hand_')]:err['arm']=max(err['arm'],(mats[a+side]@Vector((0,rig.data.bones[a+side].length,0))-mats[b+side].translation).length)
            if i%4==0:
                for o in scene.objects:
                    if o.type!='MESH' or o.hide_render:continue
                    eo=o.evaluated_get(dg);me=eo.to_mesh();ground=min(ground,min((eo.matrix_world@v.co).z for v in me.vertices));eo.to_mesh_clear()
        err['loop']=max(abs(mats[n][a][b]-first[n][a][b]) for n in mats for a in range(4) for b in range(4))
        assert max(err.values())<.001 and ground>-.002,(state,err,ground)
        report[state]=dict(errors=err,ground_min_z=ground,duration=sp['period']/60)
        folder=OUT/state;folder.mkdir(exist_ok=True)
        # Front view for side-steps, side view for backward stride readability.
        h.point_camera(scene.camera,(4,0,.9) if sp['direction']=='backward' else (0,4,1.0))
        for j in range(20):
            f=1+j*sp['period']/20;scene.frame_set(int(f),subframe=f%1);scene.render.filepath=str(folder/f'{j:03}.png');bpy.ops.render.render(write_still=True)
        print('VERIFIED',state,flush=True)
    (OUT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    TRANSFER.write_text(json.dumps(dict(asset_id='CHR-PLY-CAPSULE01-3D-BUNNY01',version='v027',status='authored_pending_export',runtime_changed=False,source=str(TARGET.relative_to(h.ROOT)),sha256=hashlib.sha256(TARGET.read_bytes()).hexdigest(),source_parent=str(SOURCE.relative_to(h.ROOT)),parent_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),preserved_actions=len(original),clips=report,specs=json.loads((OUT/'specs.json').read_text()),note='v026 carry poses retained by explicit user direction; in-place loops, game speed synchronization pending. No forward clips or runtime binding.'),ensure_ascii=False,indent=2),encoding='utf-8')
    print('V027_COMPLETE',flush=True)

if __name__ == '__main__':
    if '--verify-only' not in sys.argv:build()
    verify()
