import bpy, json, math
from pathlib import Path
from mathutils import Vector
blend = Path(bpy.data.filepath)
scene_objects = list(bpy.context.scene.objects)
meshes = [o for o in scene_objects if o.type == 'MESH']
locked = [o for o in scene_objects if o.get('locked_whitebox_geometry')]
output = [o for o in scene_objects if o.type == 'MESH' and any(c.name.startswith('02_游戏输出') for c in o.users_collection)]
def bounds(objects):
    pts = [o.matrix_world @ Vector(corner) for o in objects for corner in o.bound_box]
    return ([min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]) if pts else None
nonunit = [o.name for o in meshes if any(abs(v - 1.0) > 1e-5 for v in o.scale)]
doors = [o for o in locked if 'DOOR' in o.name]
report = {
  'blend': str(blend),
  'scene_object_count': len(scene_objects),
  'mesh_count': len(meshes),
  'output_mesh_count': len(output),
  'locked_whitebox_count': len(locked),
  'locked_bounds': bounds(locked),
  'non_unit_mesh_scales': nonunit,
  'door_objects': [{'name': o.name, 'bounds': bounds([o]), 'scale': list(o.scale)} for o in doors],
  'output_collections': sorted(c.name for c in bpy.data.collections if c.name.startswith('02_游戏输出')),
  'material_names': sorted(m.name for m in bpy.data.materials),
  'package_collection_count': len([c for c in bpy.data.collections if c.name.endswith('资产包')]),
  'has_gameplay_scripts': any('gd' in str(p).lower() for p in []),
}
Path(r'I:\工作项目\shellstrom2\ShellStorm2\_scratch\boss_datacore_verify.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('BOSS_DATACORE_PROBE_OK')
