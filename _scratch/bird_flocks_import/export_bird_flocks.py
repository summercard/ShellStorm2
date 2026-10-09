import bpy
import sys
from pathlib import Path

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
if len(args) != 3:
    raise SystemExit('usage: blender --background --python export_bird_flocks.py -- <source.blend> <optimized.blend> <output.glb>')
source_path = Path(args[0]).resolve()
optimized_path = Path(args[1]).resolve()
glb_path = Path(args[2]).resolve()

bpy.ops.wm.open_mainfile(filepath=str(source_path), load_ui=False)
kind = 'flyby' if 'flyby' in source_path.as_posix() else 'ground'
output_collection = bpy.data.collections.get('02_游戏输出_鸟群资产包')
if output_collection is None:
    raise RuntimeError('missing output collection: 02_游戏输出_鸟群资产包')

# Keep the original source untouched: this save is a new optimized working file.
# The output collection is already the Blender-authoritative game-output boundary.
selected = []
def collect(collection):
    for obj in collection.objects:
        if obj not in selected:
            selected.append(obj)
    for child in collection.children:
        collect(child)
collect(output_collection)
if not selected:
    raise RuntimeError('output collection is empty')

# Isolate export selection and keep game output objects active.
bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
bpy.ops.object.select_all(action='DESELECT')
for obj in selected:
    obj.hide_render = False
    obj.hide_viewport = False
    obj.select_set(True)
bpy.context.view_layer.objects.active = next((o for o in selected if o.type == 'ARMATURE'), selected[0])

optimized_path.parent.mkdir(parents=True, exist_ok=True)
glb_path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(optimized_path))

# Export only the game-output collection. Actions are exported as glTF animation clips.
kwargs = dict(
    filepath=str(glb_path),
    export_format='GLB',
    use_selection=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_skins=True,
    export_materials='EXPORT',
    export_texcoords=True,
    export_normals=True,
    export_tangents=False,
    export_apply=False,
)
try:
    bpy.ops.export_scene.gltf(**kwargs)
except TypeError:
    # Blender exporter option drift: retry with the stable minimum required by this project.
    kwargs.pop('export_apply', None)
    kwargs.pop('export_tangents', None)
    bpy.ops.export_scene.gltf(**kwargs)

print({
    'kind': kind,
    'source': str(source_path),
    'optimized': str(optimized_path),
    'glb': str(glb_path),
    'selected_objects': [o.name for o in selected],
    'selected_count': len(selected),
    'actions': sorted(a.name for a in bpy.data.actions),
    'frame_end': bpy.context.scene.frame_end,
})
