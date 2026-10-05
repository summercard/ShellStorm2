import bpy,json
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath=str(Path('assets/art/enemies/bosses/enm_boss_monitor002/source/enm_boss_monitor002_animation_v022.blend').resolve()))
r=bpy.data.objects['Boss002_Rig'];r.animation_data.action=bpy.data.actions['melee_keyboard'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;s.frame_set(1)
a={'bones':{p.name:{'head':list(p.head),'tail':list(p.tail),'length':p.bone.length,'parent':p.parent.name if p.parent else None} for p in r.pose.bones if p.name.startswith(('cable','hand.','hand_ctrl'))},'cable_objects':[(o.name,[g.name for g in o.vertex_groups]) for o in s.objects if o.type=='MESH' and any(g.name.startswith('cable') for g in o.vertex_groups)]}
Path('_scratch/cable_rig.json').write_text(json.dumps(a,indent=2))
