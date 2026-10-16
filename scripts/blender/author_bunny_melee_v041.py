"""Editable three-weapon full-body melee Pose Actions from the saved v039 master."""
from pathlib import Path
import sys,math,json
import bpy
from mathutils import Matrix,Vector
R=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(R/'scripts'),str(Path(__file__).parent)]
import refine_bunny_locomotion_v038 as h
from workspace_paths import work_path
from export_character_bundle import signature
SOURCE=R/'art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/source/animation/chr_bunny01_animation_v039.blend'
TARGET=SOURCE.with_name('chr_bunny01_animation_v041.blend')
OUT=work_path('sessions/2026-10-16_melee_v041/source_report.json').parent
FAMILIES={'bat':'baseball_bat','blade':'greatblade','axe':'waraxe'}
def mix(a,b,t):return tuple(x+(y-x)*t for x,y in zip(a,b))
def smooth(t):return t*t*(3-2*t)
def params(family,step,phase,t):
    hold={'bat':(8,22,42,0,0),'blade':(-12,-45,8,0,0),'axe':(0,0,65,-.01,0)}[family]
    side=1 if step!=2 else -1
    if family=='bat':
        wind=(-30*side,-85*side,15,-.025,-.025)
        strike=(5*side,0,0,-.035,.045)
        end=(30*side,80*side,5,-.01,.03)
    elif family=='blade':
        wind=(-55*side,-115*side,5,-.045,-.045)
        strike=(0,0,0,-.055,.075)
        end=(55*side,115*side,5,-.025,.04)
    else:
        # All axe attacks are overhead cleaves; stronger sagittal body lean.
        wind=(-8*side,-8*side,108,-.025,-.08)
        strike=(8*side,0,5,-.085,.16)
        end=(12*side,5*side,-8,-.075,.12)
    if phase=='charge':return mix(hold,wind,smooth(min(1,t/.3)))
    if phase=='charged_windup':return wind
    if phase=='charged_active':
        return mix(wind,strike,smooth(t/.45)) if t<=.45 else mix(strike,end,smooth((t-.45)/.55))
    if phase=='charged_recovery':return mix(end,hold,smooth(t))
    if phase=='spin':return (-360*t,-360*t,0,-.025,0)
    if phase=='spin_recovery':return mix((0,0,0,-.025,0),hold,smooth(t))
    if phase=='idle':return (hold[0]+4*math.sin(t*math.tau),hold[1]+4*math.sin(t*math.tau),hold[2]+2*math.sin(t*math.tau),hold[3]+.012*(1-math.cos(t*math.tau)),0)
    if phase=='windup':return mix(hold,wind,smooth(t))
    if phase=='active':return mix(wind,strike,smooth(t/.45)) if t<=.45 else mix(strike,end,smooth((t-.45)/.55))
    return mix(end,hold,smooth(t))
def build():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    for old_scene in list(bpy.data.scenes):
        if old_scene.get('preview_clip','').startswith('melee_'):bpy.data.scenes.remove(old_scene)
    template=next(s for s in bpy.data.scenes if s.get('preview_clip')=='idle')
    bpy.context.window.scene=template;template.frame_set(1)
    source_rig=next(o for o in template.objects if o.type=='ARMATURE')
    initial={p.name:p.matrix.copy() for p in source_rig.evaluated_get(bpy.context.evaluated_depsgraph_get()).pose.bones}
    expected=signature(source_rig);report={}
    for family,slug in FAMILIES.items():
      for step,phase in [(0,'idle')]+[(i,p) for i in (1,2,3) for p in ('windup','active','recovery')]+([(0,'charge'),(0,'charged_windup'),(0,'charged_active'),(0,'charged_recovery')] if family=='axe' else [(0,'charge'),(0,'spin'),(0,'spin_recovery')] if family=='blade' else []):
        name=f'melee_{family}_{phase}' if not step else f'melee_{family}_{step}_{phase}'
        scene=h.d.clone(template,name);bpy.context.window.scene=scene
        rig=next(o for o in scene.objects if o.type=='ARMATURE')
        rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
        rig.animation_data_clear();rig.animation_data_create()
        a=bpy.data.actions.new('anim_bunny01_'+name+'_v041');h.set_action(rig,a)
        duration={'idle':1.6,'charge':1.0 if family=='axe' else .35,'spin':.55,'spin_recovery':.3,'charged_windup':.08,'charged_active':.18,'charged_recovery':.7}.get(phase,{'windup':.48 if family=='axe' else .2,'active':.14,'recovery':.4}.get(phase,.3))
        period=120 if phase in ('spin','charge') else 60 if phase=='idle' else 40
        for k,v in dict(state_id=name,duration=duration,loop=phase in ('idle','spin'),source_revision='v041_distinct_melee',gameplay_state='moving/idle',weapon_content_id='bp_'+slug).items():a[k]=v
        before=set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(R/f'assets/art/items_weapons/weapons/melee_{slug}/components/wpn_melee_{slug}_ground_visual_top3d.glb'))
        objects=set(bpy.data.objects)-before
        gun=bpy.data.objects.new('PREVIEW_GripSocket_'+name,None);scene.collection.objects.link(gun)
        gun['preview_only']=True;gun['support_local']=[0,-.18,0];gun.scale=(.78,)*3
        for o in objects:
          o['preview_only']=True
          if o.parent not in objects:o.parent=gun;o.matrix_parent_inverse=Matrix.Identity(4)
        gun.animation_data_create();h.set_action(gun,bpy.data.actions.new('PREVIEW_ONLY_'+name))
        previous={};previous_grip=None
        for i in range(period+1):
          t=i/period;yaw,wyaw,pitch,bob,fwd=params(family,step,phase,t)
          pivot=Vector((0,0,initial['chest'].translation.z))
          upper=Matrix.Translation((0,fwd,bob))@Matrix.Translation(pivot)@Matrix.Rotation(math.radians(yaw),4,'Z')@Matrix.Rotation(math.radians(-7 if phase=='active' else -2),4,'X')@Matrix.Translation(-pivot)
          # Phase joins must be exact: torso lean follows the same authored scalar.
          upper=Matrix.Translation((0,fwd,bob))@Matrix.Translation(pivot)@Matrix.Rotation(math.radians(yaw),4,'Z')@Matrix.Rotation(fwd*-1.2,4,'X')@Matrix.Translation(-pivot)
          posed={n:(m.copy() if n=='root' or n.startswith(('foot_','thigh_','shin_')) else upper@m) for n,m in initial.items()}
          rotation=Matrix.Rotation(math.radians(wyaw),4,'Z')@Matrix.Rotation(math.radians(pitch),4,'X')
          palm=upper@Vector((.22,.30,.49 if family=='axe' else .36))
          h.solve(rig,rest,posed,'r',palm)
          h.solve(rig,rest,posed,'l',palm+rotation.to_3x3()@Vector((0,-.18,0)))
          hp=initial['head'].translation
          head=Matrix.Translation((0,fwd*.65,bob*.7))@Matrix.Translation(hp)@Matrix.Rotation(math.radians(yaw*.32),4,'Z')@Matrix.Translation(-hp)
          for n in ('head','ear_l','ear_r'):posed[n]=head@initial[n]
          if phase=='spin':
            turn=Matrix.Rotation(-math.tau*t,4,'Z')
            posed={n:(m.copy() if n=='root' else turn@m) for n,m in initial.items()}
            palm=turn@Vector((.22,.30,.36))
            h.solve(rig,rest,posed,'r',palm);h.solve(rig,rest,posed,'l',palm+rotation.to_3x3()@Vector((0,-.18,0)))
          h.h.key_pose(rig,rest,posed,i+1,previous)
          gun.location=palm;gun.rotation_mode='QUATERNION';grip_q=rotation.to_quaternion()
          if previous_grip is not None and previous_grip.dot(grip_q)<0:grip_q.negate()
          gun.rotation_quaternion=grip_q;previous_grip=grip_q.copy()
          for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+1)
        for action in (a,gun.animation_data.action):
          action.use_fake_user=True;action.use_frame_range=True;action.frame_start=1;action.frame_end=period+1;action.use_cyclic=phase in ('idle','spin')
          for curve in h.curves(action):
            curve.extrapolation='CONSTANT'
            for key in curve.keyframe_points:key.interpolation='LINEAR'
        scene['preview_clip']=name;scene['asset_id']='CHR-PLY-CAPSULE01-3D-BUNNY01';scene['source_revision']='v041_distinct_melee'
        scene.render.fps=60;scene.render.fps_base=duration*60/period
        scene.frame_start=1;scene.frame_end=period+1;scene.frame_set(1)
        report[name]=dict(duration=duration,loop=phase in ('idle','spin'),skeleton_sha256=signature(rig),frames=period+1)
        assert signature(rig)==expected
        print('AUTHORED',name,flush=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
    (OUT/'source_report.json').write_text(json.dumps(report,indent=2))
if __name__=='__main__':build()
