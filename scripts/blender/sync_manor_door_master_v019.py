"""Carry the approved door into a new full editable master; lock other components."""
import bpy
import hashlib
import json
import sys
from pathlib import Path

R = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(R/'scripts'))
from workspace_paths import work_path
S = R/'art_source/environments/tower_zones/expedition/source/common_components'
old = S/'v017/复古公馆_模块化组件母版_v017.blend'
new = S/'v019/复古公馆_模块化组件母版_v019.blend'
door = S/'v019/component_packages/manor_door_double/manor_door_double_source_v019.blend'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
old_hash = sha(old)
bpy.ops.wm.open_mainfile(filepath=str(old))
target = bpy.data.collections['Component_manor_door_double']
locked_names = [o.name for o in bpy.data.objects if o not in list(target.all_objects)]

def signature():
    values = []
    def plain(value):
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        try:
            return list(value)
        except TypeError:
            return str(value)

    def material_signature(mat):
        nodes = []
        if mat.use_nodes:
            for node in mat.node_tree.nodes:
                nodes.append((node.name, node.type,
                              [(s.name, plain(s.default_value)) for s in node.inputs if hasattr(s, 'default_value')],
                              getattr(node, 'uv_map', None), getattr(node, 'interpolation', None),
                              str(Path(bpy.path.abspath(node.image.filepath)).resolve()) if node.type == 'TEX_IMAGE' and node.image else None))
        return (mat.name, nodes)

    for name in locked_names:
        ob = bpy.data.objects[name]
        values.append((ob.name, ob.type, list(map(list, ob.matrix_world)),
                       [(list(v.co)) for v in ob.data.vertices] if ob.type == 'MESH' else None,
                       [tuple(p.vertices) for p in ob.data.polygons] if ob.type == 'MESH' else None,
                       [(p.material_index, p.use_smooth) for p in ob.data.polygons] if ob.type == 'MESH' else None,
                       [material_signature(m) for m in ob.data.materials] if ob.type == 'MESH' else None,
                       [(uv.name, uv.active_render, [list(v.uv) for v in uv.data]) for uv in ob.data.uv_layers] if ob.type == 'MESH' else None,
                       [(m.name, m.type, [(p.identifier, plain(getattr(m,p.identifier))) for p in m.bl_rna.properties if p.type in {'BOOLEAN','INT','FLOAT','ENUM','STRING'}]) for m in ob.modifiers],
                       str(ob.animation_data.action) if ob.animation_data else None,
                       ob.parent.name if ob.parent else None))
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()

before = signature()
old_root = next(o for o in target.objects if o.type == 'EMPTY')
with bpy.data.libraries.load(str(door), link=False) as (src, dst):
    dst.objects = [n for n in src.objects if n.startswith('通顶木门_')]
loaded = next(o for o in dst.objects if o is not None)
replacement = loaded.copy()
replacement.data = loaded.data.copy()
replacement.parent = old_root
for ob in list(target.objects):
    if ob.type == 'MESH':
        bpy.data.objects.remove(ob, do_unlink=True)
target.objects.link(replacement)
bpy.data.objects.remove(loaded, do_unlink=True)
for ob in list(bpy.data.objects):
    if ob.users == 0 and ob.name not in locked_names:
        bpy.data.objects.remove(ob, do_unlink=True)
# Use existing shared role materials to avoid appended duplicate names.
for i, mat in enumerate(replacement.data.materials):
    original = bpy.data.materials.get(mat.name.split('.00')[0])
    if original is not None:
        replacement.data.materials[i] = original
for mat in list(bpy.data.materials):
    if mat.users == 0:
        bpy.data.materials.remove(mat)
assert signature() == before, 'Locked objects changed'
for image in bpy.data.images:
    if image.source == 'FILE':
        image.filepath = str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png')
bpy.ops.wm.save_as_mainfile(filepath=str(new), compress=True)
assert sha(old) == old_hash
manifest_path = door.parent/'asset_manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf8'))
manifest['source_room_type_blend'] = new.relative_to(R).as_posix()
manifest['source_room_type_sha256'] = sha(new)
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
report = dict(old_master=str(old), new_master=str(new), old_sha256=old_hash,
              new_sha256=sha(new), locked_before=before, locked_after=signature(),
              locked_match=True, scope='Only Component_manor_door_double mesh replaced; all other objects locked.')
work_path('sessions/2026-11-06_expedition03_wood_door/master_sync.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
print('MANOR_MASTER_SYNC_OK', before)
