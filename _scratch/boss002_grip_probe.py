import bpy,json
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/source/enm_boss_monitor002_model_v006.blend')
bpy.context.window.scene=bpy.data.scenes['BOSS002_SOURCE_TPOSE']
r={}
for n in ['Sculpted glove L','Sculpted glove R','Keyboard outer shell','Keyboard deck','Long data cable whip','Data connector body']:
 o=bpy.data.objects[n];v=[o.matrix_world@v.co for v in o.data.vertices];r[n]={'loc':list(o.location),'min':[min(p[i] for p in v) for i in range(3)],'max':[max(p[i] for p in v) for i in range(3)]}
rig=bpy.data.objects['Boss002_Rig'];r['bones']={b.name:{'head':list(b.head_local),'tail':list(b.tail_local)} for b in rig.data.bones if b.name.startswith(('digit','hand','cable'))}
open('I:/工作项目/shellstrom2/ShellStorm2/_scratch/boss002_grip_probe.json','w').write(json.dumps(r,indent=2))
