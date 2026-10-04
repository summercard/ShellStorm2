import bpy,json
from pathlib import Path
p=Path(__file__).resolve().parents[2]/'assets/art/enemies/normal_enemy_3d/fat_zombie03';results={};samples=[]
for version in ['v003','v004']:
 bpy.ops.wm.open_mainfile(filepath=str(p/f'source/animation/enm_normal_fat_zombie03_animation_{version}.blend'))
 a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');s=bpy.context.scene;data={}
 for clip,end in [('idle',96),('walking',60),('running',36)]:
  a.animation_data.action=bpy.data.actions[clip];data[clip]=[]
  for k in range(end*2+1):
   s.frame_set(k//2,subframe=(k%2)/2);bpy.context.view_layer.update()
   names=[b.name for b in a.pose.bones]
   data[clip].append([x for n in names for row in a.pose.bones[n].matrix for x in row])
 samples.append(data)
for clip in ['idle','walking','running']:
 e=max(abs(a-b) for x,y in zip(samples[0][clip],samples[1][clip]) for a,b in zip(x,y));assert e<1e-6,(clip,e);results[clip+'_preservation_error']=e
(p/'previews/attack_v004/preservation.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print('ATTACK_PRESERVATION_OK',json.dumps(results))
