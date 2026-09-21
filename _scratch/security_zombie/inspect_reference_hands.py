import bpy,json
from pathlib import Path
P=Path(r"I:\工作项目\shellstrom2\ShellStorm2")
bpy.ops.wm.open_mainfile(filepath=str(P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend'))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
print(json.dumps([{'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(b.head_local),'tail':list(b.tail_local)} for b in a.data.bones if b.name.startswith(('L_Thumb','L_Index','L_Middle','L_Pinky','R_Thumb','R_Index','R_Middle','R_Pinky'))],indent=2))