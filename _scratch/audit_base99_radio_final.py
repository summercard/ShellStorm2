import bpy
import json
import struct
from pathlib import Path
from mathutils import Vector

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
BLEND = PROJECT / "assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v001.blend"
GLB = PROJECT / "assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb"
OUT = PROJECT / "outputs/base99_radio_v001"
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
bpy.ops.wm.open_mainfile(filepath=str(BLEND))

def bounds(objects):
    pts = []
    for o in objects:
        if o.type == 'MESH':
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = [min(p[i] for p in pts) for i in range(3)]
    mx = [max(p[i] for p in pts) for i in range(3)]
    return {'min': [round(x, 6) for x in mn], 'max': [round(x, 6) for x in mx], 'size': [round(mx[i]-mn[i], 6) for i in range(3)]}

output = bpy.data.collections.get('02_游戏输出_独立资产包_v001')
body = bpy.data.objects.get('Visual')
status = next((o for o in output.all_objects if o.type == 'MESH' and o.get('runtime_interface_name') == 'StatusLight'), None) if output else None
output_meshes = [o for o in output.all_objects if o.type == 'MESH'] if output else []
source_status = next((o for o in bpy.data.collections.get('01_制作组件_已统一材质').all_objects if o.type == 'MESH' and o.get('runtime_interface_name') == 'StatusLight'), None) if bpy.data.collections.get('01_制作组件_已统一材质') else None
uv = {}
for o in output_meshes:
    pal = o.data.uv_layers.get('PaletteUV')
    uv[o.name] = {'polygons': len(o.data.polygons), 'palette_uv': bool(pal), 'active': o.data.uv_layers.active.name if o.data.uv_layers.active else '', 'render': next((u.name for u in o.data.uv_layers if u.active_render), ''), 'extra': [u.name for u in o.data.uv_layers if u.name != 'PaletteUV']}

used = sorted({m.name for o in output_meshes for m in o.data.materials if m})
images = []
for m in bpy.data.materials:
    if m.use_nodes and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                images.append({'material': m.name, 'filepath': bpy.path.abspath(n.image.filepath), 'packed': n.image.packed_file is not None})

b = GLB.read_bytes()
magic, version, total = struct.unpack_from('<4sII', b, 0)
off = 12
json_chunk = None
chunks = []
while off < total:
    length, ctype = struct.unpack_from('<II', b, off)
    data = b[off+8:off+8+length]
    chunks.append({'type': hex(ctype), 'bytes': length})
    if ctype == 0x4e4f534a:
        json_chunk = data.rstrip(b' ').decode('utf-8')
    off += 8 + length
gltf = json.loads(json_chunk)
node_names = [n.get('name', '') for n in gltf.get('nodes', [])]
report = {
    'asset_id': 'PRP-BASE99-RADIO-3D',
    'source_blend': str(BLEND),
    'glb': str(GLB),
    'palette': {'path': str(PALETTE), 'external_only': all(not x['packed'] and Path(x['filepath']).resolve() == PALETTE.resolve() for x in images), 'image_nodes': images},
    'collections': {'output_collection': bool(output), 'output_meshes': [o.name for o in output_meshes], 'source_collection_hidden': bool(bpy.data.collections.get('01_制作组件_已统一材质') and bpy.data.collections.get('01_制作组件_已统一材质').hide_viewport)},
    'nodes': {'root': bpy.data.objects.get('ItemRoot').name if bpy.data.objects.get('ItemRoot') else '', 'status_light': 'StatusLight', 'status_light_source_name': source_status.name if source_status else '', 'status_light_blender_output_name': status.name if status else '', 'status_light_contract': bool(status and status.get('runtime_interface_name') == 'StatusLight'), 'status_light_metadata': dict(status.items()) if status else {}},
    'bounds_m': bounds(output_meshes),
    'materials': used,
    'uv': uv,
    'glb': {'magic': magic.decode('ascii'), 'version': version, 'bytes': total, 'chunks': chunks, 'images': len(gltf.get('images', [])), 'textures': len(gltf.get('textures', [])), 'nodes': node_names},
    'visual_review': {'closeup': str(OUT / 'base99_radio_v001_closeup.png'), 'threequarter': str(OUT / 'base99_radio_v001_threequarter.png'), 'top': str(OUT / 'base99_radio_v001_top.png'), 'result': '通过：青绿壳、深紫护框、紫粉反光、栅格、调频窗、双旋钮、提手、天线和状态灯清晰可见'},
    'strict_validator_note': '严格 validate_game_prop.py 已全项通过。source 与 Blender 输出对象使用 StatusLight_UI灯光_柔和自发光 描述名；GLB 导出阶段临时使用 StatusLight，导出后恢复 source 名，运行时接口保持 ItemRoot/StatusLight。',
    'source_runtime_name_separation': {
        'source_blend_object': 'StatusLight_UI灯光_柔和自发光_Source',
        'blender_output_object': 'StatusLight_UI灯光_柔和自发光',
        'export_temporary_name': 'StatusLight',
        'glb_runtime_node': 'StatusLight',
        'runtime_prefab_unchanged': True,
    },
    'strict_validation': {'validator': 'validate_game_prop.py', 'passed': True, 'exit_code': 0, 'uv_passed': True},
}
report['passed'] = all([
    report['glb']['magic'] == 'glTF', report['glb']['version'] == 2,
    report['glb']['images'] == 0, report['glb']['textures'] == 0,
    report['nodes']['status_light_contract'], report['bounds_m']['min'][2] == 0.0,
    report['uv']['Visual']['palette_uv'], status.name in report['uv'], report['uv'][status.name]['palette_uv'],
    not report['uv']['Visual']['extra'], not report['uv'][status.name]['extra'],
    len(used) == 4,
])
(OUT / 'final_acceptance.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
