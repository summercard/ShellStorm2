import json, math, os, sys
import bpy

args = sys.argv[sys.argv.index('--') + 1:]
scene_json, output_blend = args
with open(scene_json, 'r', encoding='utf-8') as handle: payload = json.load(handle)
active_roots = {(record.get('blenderSettings') or {}).get('rootObject') for record in payload.get('components', [])}
for root_name in (payload.get('blenderSource') or {}).get('managedRootObjects', []):
    if root_name in active_roots: continue
    root = bpy.data.objects.get(root_name)
    if root:
        for child in list(root.children_recursive): bpy.data.objects.remove(child, do_unlink=True)
        bpy.data.objects.remove(root, do_unlink=True)
for record in payload.get('components', []):
    settings = record.get('blenderSettings') or {}
    root = bpy.data.objects.get(settings.get('rootObject', ''))
    if not root: raise RuntimeError(f"找不到Blender根对象: {settings.get('rootObject')}")
    pos, rot, scale = record.get('position', {}), record.get('rotation', {}), record.get('scale', {})
    root.location = tuple(pos.get(axis, 0) for axis in 'xyz')
    root.rotation_euler = tuple(math.radians(rot.get(axis, 0)) for axis in 'xyz')
    root.scale = tuple(scale.get(axis, 1) for axis in 'xyz')
bpy.context.scene['3dgame_design_bidirectional'] = True
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(output_blend), check_existing=False)
