"""Restore the shared palette to an absolute external path, matching project convention.

Material normalization only: no geometry, structure, UV, package or contract change.
Blender's save_as_mainfile defaults to relative_remap=True, which stores //../.. and
breaks as soon as the .blend is opened outside its authoring directory.
"""
import bpy, os, sys, json
from pathlib import Path
argv = sys.argv[sys.argv.index('--') + 1:]
palette = Path(argv[0]).resolve()
assert palette.exists(), palette
blend = Path(bpy.data.filepath).resolve()
report = {'blend': str(blend), 'palette': str(palette), 'changed': []}
for img in bpy.data.images:
    if img.name == 'Render Result' or not img.filepath:
        continue
    old = img.filepath
    if img.packed_file is not None:
        raise AssertionError('palette must stay external, found packed image: ' + img.name)
    img.filepath = str(palette)
    img.filepath_raw = str(palette)
    report['changed'].append({'image': img.name, 'old': old, 'new': img.filepath})
assert report['changed'], 'no external image path was rewritten'
# relative_remap=False keeps the absolute project path instead of re-relativising it.
bpy.ops.wm.save_as_mainfile(filepath=str(blend), relative_remap=False)
report['saved_mtime'] = os.path.getmtime(blend)
Path(argv[1]).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding='utf-8')
print('PALETTE_PATH_FIXED', len(report['changed']))
