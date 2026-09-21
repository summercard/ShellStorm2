import bpy, json
from pathlib import Path
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
paths=[
 P/'assets/art/weapons/weapon_3d/source/double_barrel_cannon/wpn_double_barrel_cannon_source_v001.blend',
 P/'assets/art/weapons/weapon_3d/source/broom_rifle/wpn_broom_rifle_source_v001.blend',
]
for path in paths:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    print('===',path.name,'===')
    print('objects',[(o.name,o.type,[round(x,3) for x in o.location], [round(x,3) for x in o.dimensions]) for o in bpy.context.scene.objects])
    print('collections',[c.name for c in bpy.data.collections])
    print('materials',[m.name for m in bpy.data.materials])
