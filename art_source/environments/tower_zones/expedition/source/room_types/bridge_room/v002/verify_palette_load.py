"""Prove the palette actually loads, from wherever this .blend sits."""
import bpy, os, json, sys
from pathlib import Path
argv = sys.argv[sys.argv.index('--') + 1:]
out = {'blend': bpy.data.filepath, 'images': [], 'materials': [], 'load_ok': True}
for img in bpy.data.images:
    if img.name == 'Render Result':
        continue
    fp = img.filepath
    ap = os.path.normpath(bpy.path.abspath(fp)) if fp else ''
    rec = {'name': img.name, 'filepath': fp, 'is_relative': fp.startswith('//'),
           'resolved': ap, 'exists_on_disk': os.path.exists(ap), 'packed': bool(img.packed_file)}
    try:
        img.reload()
        rec['size_after_reload'] = list(img.size)
        rec['reload_ok'] = img.size[0] > 0 and img.size[1] > 0
        rec['pixels_readable'] = len(img.pixels[:4]) == 4
    except Exception as exc:
        rec['reload_ok'] = False
        rec['error'] = repr(exc)
    if not rec.get('reload_ok'):
        out['load_ok'] = False
    out['images'].append(rec)
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    nodes = mat.node_tree.nodes
    tex = [n for n in nodes if n.type == 'TEX_IMAGE']
    uv = [n.uv_map for n in nodes if n.type == 'UVMAP']
    out['materials'].append({'name': mat.name, 'image_nodes': len(tex),
                             'all_images_bound': all(n.image is not None for n in tex),
                             'interpolation': [n.interpolation for n in tex], 'uv_map': uv})
    if not tex or not all(n.image is not None for n in tex):
        out['load_ok'] = False
Path(argv[0]).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding='utf-8')
print('PALETTE_LOAD_CHECK', out['load_ok'])
