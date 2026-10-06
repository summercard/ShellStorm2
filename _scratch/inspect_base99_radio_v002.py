import bpy
from mathutils import Vector
from pathlib import Path

blend = r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v002.blend'
bpy.ops.wm.open_mainfile(filepath=blend)
print('SCENE', bpy.data.filepath)
for c in bpy.data.collections:
    print('COLLECTION', c.name, 'hide', c.hide_viewport, c.hide_render)
for o in bpy.data.objects:
    if o.type in {'MESH','EMPTY'}:
        print('OBJECT', o.name, 'type', o.type, 'parent', o.parent.name if o.parent else '', 'loc', tuple(round(v,5) for v in o.location), 'scale', tuple(round(v,5) for v in o.scale), 'dims', tuple(round(v,5) for v in o.dimensions), 'collections', [c.name for c in o.users_collection], 'props', dict(o.items()))
        if o.type == 'MESH':
            print('  MESH', len(o.data.vertices), len(o.data.polygons), 'materials', [m.name if m else '' for m in o.data.materials], 'uv', [u.name for u in o.data.uv_layers])
for m in bpy.data.materials:
    print('MATERIAL', m.name, dict(m.items()))
