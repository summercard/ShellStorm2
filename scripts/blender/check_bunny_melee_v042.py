"""Reopen the authored master and audit evaluated poses and phase joins."""
from pathlib import Path
import sys,json,math
import bpy
from mathutils import Vector
sys.path[:0]=[str(Path(__file__).parent),str(Path(__file__).resolve().parents[1])]
from author_bunny_melee_v041 import TARGET,OUT,FAMILIES
TARGET=TARGET.with_name('chr_bunny01_animation_v042.blend')
from workspace_paths import work_path
OUT=work_path('sessions/2026-10-17_axe_edge_v042/placeholder').parent
from export_character_bundle import signature
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
report={};ends={}
for scene in bpy.data.scenes:
 state=scene.get('preview_clip','')
 if not state.startswith('melee_'):continue
 bpy.context.window.scene=scene
 rig=next(o for o in scene.objects if o.type=='ARMATURE');gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
 a=rig.animation_data.action;first,last=map(int,a.frame_range)
 err=0;scale=0;root=0;yaws=[]
 for i in range((last-first)*2+1):
  f=first+i*.5;scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get();r=rig.evaluated_get(dg);g=gun.evaluated_get(dg)
  for side in ('r','l'):
   wanted=g.matrix_world.translation+(g.matrix_world.to_quaternion()@Vector((0,-.18,0)) if side=='l' else Vector())
   err=max(err,(r.pose.bones['hand_'+side].tail-wanted).length)
  scale=max(scale,max(abs(v-1) for b in r.pose.bones for v in b.matrix.to_scale()))
  root=max(root,r.pose.bones['root'].matrix.translation.length)
  yaws.append(r.pose.bones['chest'].matrix.to_euler('XYZ').z)
  if i in (0,(last-first)*2):ends[(state,'first' if i==0 else 'last')]={b.name:b.matrix.copy() for b in r.pose.bones}
 assert err<.002,(state,err)
 assert scale<.00001 and root<.00001,(state,scale,root)
 report[state]=dict(palm_error_m=err,scale_error=scale,root_motion_m=root,yaw_span_deg=math.degrees(max(yaws)-min(yaws)),signature=signature(rig))
for family in FAMILIES:
 for step in (1,2,3):
  names=[f'melee_{family}_idle']+[f'melee_{family}_{step}_{phase}' for phase in ('windup','active','recovery')]+[f'melee_{family}_idle']
  for x,y in zip(names,names[1:]):
   left=ends[(x,'first' if x.endswith('idle') else 'last')];right=ends[(y,'first')]
   error=max(abs(left[n][i][j]-right[n][i][j]) for n in left for i in range(4) for j in range(4))
   assert error<.00001,(x,y,error)
assert len(report)==37
(OUT/'source_validation.json').write_text(json.dumps(dict(clips=report,phase_joins=True,preview_weapons=True),indent=2))
print('MELEE_SOURCE_OK',len(report))
