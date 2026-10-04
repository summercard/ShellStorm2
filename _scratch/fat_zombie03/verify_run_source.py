import bpy,json
from pathlib import Path
p=Path(__file__).resolve().parents[2]/'assets/art/enemies/normal_enemy_3d/fat_zombie03';results={};samples=[]
for version in ['v002','v003']:
 bpy.ops.wm.open_mainfile(filepath=str(p/f'source/animation/enm_normal_fat_zombie03_animation_{version}.blend'))
 a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');s=bpy.context.scene;data={}
 for clip,end in [('idle',96),('walking',60)]:
  a.animation_data.action=bpy.data.actions[clip];data[clip]=[]
  for k in range(end*2+1):
   s.frame_set(k//2,subframe=(k%2)/2);bpy.context.view_layer.update()
   names=[b.name for b in a.pose.bones if clip=='idle' or b.name in ['Root','Hip','L_Thigh','R_Thigh','L_Calf','R_Calf','L_Foot','R_Foot','L_ToeBase','R_ToeBase','L_Toe_End','R_Toe_End']]
   data[clip].append([x for n in names for row in a.pose.bones[n].matrix for x in row])
 samples.append(data)
for clip in ['idle','walking']:
 e=max(abs(a-b) for x,y in zip(samples[0][clip],samples[1][clip]) for a,b in zip(x,y));assert e<1e-6,(clip,e);results[clip+'_preservation_error']=e
# Saved-file running amplitude, hand separation, and unchanged unit bone scale.
a.animation_data.action=bpy.data.actions['running'];hips=[];heads=[];hands=[];elbows=[];scaleerror=0
for k in range(73):
 s.frame_set(k//2,subframe=(k%2)/2);bpy.context.view_layer.update()
 hips.append(list(a.pose.bones['Hip'].head*.7));heads.append(list(a.pose.bones['Head'].head*.7));hands.append([a.pose.bones[z+'_Hand'].head.x*.7 for z in ['L','R']]);elbows.append([a.pose.bones[z+'_Forearm'].head.x*.7 for z in ['L','R']]);scaleerror=max(scaleerror,max(abs(v-1) for b in a.pose.bones for v in b.scale))
results.update(running_hip_range_m=[max(v[i] for v in hips)-min(v[i] for v in hips) for i in range(3)],running_head_range_m=[max(v[i] for v in heads)-min(v[i] for v in heads) for i in range(3)],running_min_hand_span_m=min(v[1]-v[0] for v in hands),running_min_elbow_span_m=min(v[1]-v[0] for v in elbows),bone_scale_error=scaleerror)
assert results['running_hip_range_m'][0]>.07 and results['running_hip_range_m'][2]>.05 and results['running_min_hand_span_m']>1.4 and scaleerror<1e-6
(p/'previews/locomotion_v003/preservation_and_amplitude.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print('PRESERVATION_AMPLITUDE_OK',json.dumps(results))
