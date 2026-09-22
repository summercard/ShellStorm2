import bpy, json
from pathlib import Path
from mathutils import Vector
out = Path(r'I:\工作项目\shellstrom2\ShellStorm2\_scratch\boss_datacore_v002_probe.json')
objs=list(bpy.context.scene.objects)
meshes=[o for o in objs if o.type=='MESH']
locked=[o for o in meshes if o.get('locked_whitebox_geometry')]
output=[]
output_roots=[c for c in bpy.data.collections if c.name.startswith('02_游戏输出')]
for root in output_roots:
    output.extend(o for o in root.all_objects if o.type=='MESH')
def bounds(objects):
    pts=[o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    return ([min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]) if pts else None
names=[o.name for o in output]
report={
 'blend':bpy.data.filepath,
 'scene_object_count':len(objs),
 'mesh_count':len(meshes),
 'output_mesh_count':len(output),
 'locked_whitebox_count':len(locked),
 'locked_bounds':bounds(locked),
 'locked_scale_violations':[o.name for o in locked if any(abs(v-1)>1e-5 for v in o.scale)],
 'complete_server_meshes':[n for n in names if n.startswith('完整服务器_')],
 'damaged_server_meshes':[n for n in names if n.startswith('破损服务器_')],
 'heavy_conduit_meshes':[n for n in names if '粗重电线管' in n],
 'all_materials':sorted(m.name for m in bpy.data.materials),
 'output_collections':sorted(c.name for c in bpy.data.collections if c.name.startswith('02_游戏输出')),
 'package_collection_count':len([c for c in bpy.data.collections if c.name.endswith('资产包')]),
 'has_south_door':any('WALL_SOUTH_SLOT_06_DOOR' in n for n in names),
 'has_west_door':any('WALL_WEST_SLOT_04_DOOR' in n for n in names),
}
out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('BOSS_DATACORE_V002_PROBE_OK')
