"""Build Expedition 01 industrial low-wall variants with baked geometry, never scene scaling.

Run from the repository with Blender's --background --python-exit-code 1 --python.
The shipped high-wall GLBs are the shape/PaletteUV references. Their Blender masters,
GLBs and wrappers are never written. Output transforms and horizontal slots are unchanged.
"""
from collections import Counter
from hashlib import md5, sha256
from pathlib import Path
import json
import math
import os
import re

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
FAMILY = 'expedition_01_low_h28'
HEIGHT = 2.8
VERSION = 'v001'
TOWER = Path('assets/art/environments/tower_zones')
EXP = TOWER / 'expedition'
SOURCE = Path('art_source/environments/tower_zones/expedition/source') / FAMILY / VERSION
PALETTE = ROOT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
SCENES = EXP / 'runtime/room_instances/expedition_01'
ROOMS = ['start', *(f'room_{i:02d}' for i in range(1, 11)), 'extraction']


def component(base, slug):
    return base / slug / f'{slug}_root_top3d.tscn'


BATTLE = TOWER / 'battle/runtime/common_components'
LOCAL = EXP / 'runtime/room_type_components'
INPUTS = {
    **{f'{s}_h28': component(BATTLE, s) for s in ('wall_standard_5m', 'wall_door_5m')},
    **{f'{s}_h28': component(LOCAL / 'l_corridor', s) for s in ('wall_5m_a', 'wall_5m_c', 'wall_5m_d')},
    **{f'{s}_h28': component(LOCAL / 'office_room', s) for s in ('door_wall', 'wall_t615_5m', 'wall_t1110_5m', 'wall_t970_5m')},
    'wall_x780_h28': component(LOCAL / 'bridge_room', 'wall_x780'),
    'wall_corner_l_5m_h28': Path('assets/art/props/dungeon_3d/prp_corner_l_5m.tscn'),
}
DOORS = {'wall_door_5m_h28', 'door_wall_h28'}


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def asset_id(slug):
    return 'ENV-EXPEDITION-L01-LOW-' + slug.removesuffix('_h28').upper().replace('_', '-')


def prefab(slug):
    return component(EXP / 'runtime' / FAMILY, slug)


def metadata(text):
    return dict(re.findall(r'(?m)^metadata/(\w+) = (.*)$', text.split('\n[node ', 2)[1]))


def vec(values):
    return 'Vector3(' + ', '.join(f'{v:.6g}' for v in values) + ')'


def triple(text):
    return [float(n) for n in text.removeprefix('Vector3(').removesuffix(')').split(',')]


def low_vec(text):
    values = triple(text)
    values[1] = HEIGHT
    return vec(values)


def json_out(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def save_blend(path):
    bpy.context.preferences.filepaths.save_version = 0
    palette = bpy.data.images.get('ShellStorm2_SharedPalette')
    palette.filepath = '//' + os.path.relpath(PALETTE, path.parent).replace('\\', '/')
    bpy.ops.wm.save_as_mainfile(filepath=str(path), relative_remap=False, compress=True)


def cut(mesh, planes):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    # Glue exported UV splits topologically. UVs are loop attributes, not vertex attributes.
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.000001)
    cut_faces = 0
    uv = bm.loops.layers.uv.verify()
    for co, normal in planes:
        result = bmesh.ops.bisect_plane(bm, geom=[*bm.verts, *bm.edges, *bm.faces],
                                       dist=0.000005, plane_co=co, plane_no=normal, clear_outer=True)
        edge_list = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge) and e.is_valid and e.is_boundary]
        edge_set = set(edge_list)
        while edge_set:
            first = edge_set.pop()
            island = [first]
            stack = list(first.verts)
            while stack:
                v = stack.pop()
                for e in v.link_edges:
                    if e in edge_set:
                        edge_set.remove(e)
                        island.append(e)
                        stack.extend(e.verts)
            if len(island) < 3 or any(n != 2 for n in Counter(v for e in island for v in e.verts).values()):
                continue
            source_face = island[0].link_faces[0]
            material_index = source_face.material_index
            coords = [l[uv].uv.copy() for l in source_face.loops]
            # Pick a small UV island inside the exact source palette cell; never use a point UV.
            sample = sum(coords, Vector((0, 0))) / len(coords)
            cell = [min(9, max(0, math.floor(q * 10))) for q in sample]
            for face in bmesh.ops.holes_fill(bm, edges=island, sides=0)['faces']:
                face.material_index = material_index
                for i, loop in enumerate(face.loops):
                    angle = math.tau * i / len(face.loops)
                    loop[uv].uv = ((cell[0] + 0.5) / 10 + 0.009 * math.cos(angle),
                                   (cell[1] + 0.5) / 10 + 0.009 * math.sin(angle))
                cut_faces += 1
    if bm.faces:
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return cut_faces


def triangles(objects):
    n = 0
    for ob in objects:
        ob.data.calc_loop_triangles()
        n += len(ob.data.loop_triangles)
    return n


def palette_link(objects):
    image = bpy.data.images.load(str(PALETTE), check_existing=True)
    image.name = 'ShellStorm2_SharedPalette'
    for mat in {m for obj in objects for m in obj.data.materials if m}:
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        tex.interpolation = 'Closest'
        tex.extension = 'EXTEND'
        uv = nodes.new('ShaderNodeUVMap')
        uv.uv_map = 'PaletteUV'
        mat.node_tree.links.new(uv.outputs['UV'], tex.inputs['Vector'])
        mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
        if mat.name.startswith('04_'):
            mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
            bsdf.inputs['Emission Strength'].default_value = max(1.0, bsdf.inputs['Emission Strength'].default_value)


def make_wrapper(slug, old, old_prefab, glb, source, manifest, bounds):
    old_meta = metadata(old)
    sections = re.split(r'(?m)(?=^\[(?:node|sub_resource) )', old)
    is_door = slug in DOORS
    jamb = 'jamb' if slug == 'door_wall_h28' else 'pier'
    out = []
    for section in sections[1:]:
        if section.startswith('[sub_resource'):
            if is_door and jamb not in section.splitlines()[0]:
                continue
            section = re.sub(r'(?m)^size = (Vector3\([^\n]+\))', lambda m: 'size = ' + low_vec(m[1]), section)
        elif ' parent=' not in section.splitlines()[0]:
            info = {k: old_meta[k] for k in ('origin_contract', 'forward_axis', 'front_axis_blender', 'up_axis',
                    'grid_unit_m', 'wall_thickness_m', 'collision_owner', 'collision_policy', 'visual_only',
                    'slot_role', 'wall_kind', 'door_clear_width_m', 'door_clear_height_m',
                    'pier_width_m', 'component', 'logic_id', 'component_slug') if k in old_meta}
            bb = [bounds[1][i] - bounds[0][i] for i in range(3)]
            info.update(asset_id=json.dumps(asset_id(slug)), asset_version=json.dumps(VERSION),
                        display_name_zh=json.dumps(f'远征01 2.8m工业墙 · {slug}', ensure_ascii=False),
                        asset_family=json.dumps(FAMILY), level_id='"expedition_01"',
                        source_blend=json.dumps('res://' + source.as_posix(), ensure_ascii=False),
                        source_manifest=json.dumps('res://' + manifest.as_posix(), ensure_ascii=False),
                        source_wall_prefab=json.dumps('res://' + old_prefab.as_posix()),
                        bounds_size_m=low_vec(old_meta['bounds_size_m']),
                        visual_bounds_size_m=vec([bb[0], bb[2], bb[1]]),
                        wall_visual_height_m='2.8', wall_logical_height_m='2.8',
                        visual_height_m='2.8', logical_height_m='2.8', visual_top_clearance_m='0.0',
                        preserve_authored_palette='true', shadow_policy='"cast_and_receive"',
                        runtime_instantiation='"per_instance_prefab"')
            if is_door:
                info.update(wall_kind='"door_portal"', slot_role='"door_wall"', collision_shape_count='2',
                            door_clear_width_m='2.2', door_clear_height_m='2.5', lintel_height_m='0.0')
            else:
                info['collision_shape_count'] = '2' if slug.startswith('wall_corner') else '1'
            section = section.splitlines()[0] + '\n' + ''.join(f'metadata/{k} = {v}\n' for k,v in info.items()) + '\n'
        elif 'type="CollisionShape3D"' in section.splitlines()[0]:
            if is_door and jamb not in section:
                continue
            section = re.sub(r'(?m)^position = Vector3\(([^,]+), [^,]+, ([^\n]+)', r'position = Vector3(\1, 1.4, \2', section)
            if slug.startswith('wall_corner'):
                section = section.replace(', 6, ', ', 1.4, ')
        out.append(section)
    count = 2 + sum(s.startswith('[sub_resource') for s in out)
    return f'[gd_scene load_steps={count} format=3]\n\n[ext_resource type="PackedScene" path="res://{glb.as_posix()}" id="1_visual"]\n\n' + ''.join(out)


def make_import(source_glb, glb):
    old_path = str(source_glb).replace('\\','/')
    res = 'res://' + glb.as_posix()
    remap = f'res://.godot/imported/{glb.name}-{md5(res.encode()).hexdigest()}.scn'
    text = (ROOT / (old_path + '.import')).read_text(encoding='utf-8')
    text = re.sub(r'(?m)^uid=.*\n', '', text)
    text = re.sub(r'(?m)^path=.*$', 'path=' + json.dumps(remap), text)
    text = re.sub(r'(?m)^source_file=.*$', 'source_file=' + json.dumps(res), text)
    text = re.sub(r'(?m)^dest_files=.*$', 'dest_files=[' + json.dumps(remap) + ']', text)
    text = re.sub(r'(?m)^_subresources=.*$', '_subresources={}', text)
    assert 'gltf/embedded_image_handling=0' in text and 'scene_facility_shared_palette_post_import.gd' in text
    (ROOT / (glb.as_posix() + '.import')).write_text(text, encoding='utf-8')


def build(slug, previous):
    old = (ROOT / previous).read_text(encoding='utf-8-sig')
    ref_glb = Path(re.search(r'path="res://([^"\n]+\.glb)"', old)[1]); before_hash = digest(ROOT / ref_glb)
    folder = SOURCE / 'component_packages' / slug
    source = folder / f'{slug}_source_{VERSION}.blend'
    optimized = folder / 'export' / VERSION / f'{slug}_optimized_{VERSION}.blend'
    manifest = folder / 'asset_manifest.json'
    glb = EXP / 'components' / FAMILY / slug / f'{slug}_visual_top3d.glb'
    for p in (source, optimized, glb, prefab(slug)):
        (ROOT / p.parent).mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.ops.import_scene.gltf(filepath=str(ROOT / ref_glb), merge_vertices=True)
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.context.view_layer.update()
    for obj in mesh_objs:
        xform = obj.matrix_world.copy()
        obj.parent = None
        obj.data.transform(xform)
        obj.matrix_world = Matrix.Identity(4)
        if obj.data.uv_layers:
            obj.data.uv_layers.active.name = 'PaletteUV'
            obj.data.uv_layers.active.active_render = True
    # Disconnect any imported hierarchy but retain model object names for VFX callers.
    for obj in list(bpy.context.scene.objects):
        if obj.type != 'MESH':
            bpy.data.objects.remove(obj, do_unlink=True)
    src_tris = triangles(mesh_objs)
    cuts = 0
    if slug in DOORS:
        for obj in mesh_objs[:]:
            other = obj.copy()
            other.data = obj.data.copy()
            obj.users_collection[0].objects.link(other)
            cuts += cut(obj.data, [((0, 0, HEIGHT), (0, 0, 1)), ((-1.1, 0, 0), (1, 0, 0))])
            cuts += cut(other.data, [((0, 0, HEIGHT), (0, 0, 1)), ((1.1, 0, 0), (-1, 0, 0))])
            mesh_objs.append(other)
    else:
        for obj in mesh_objs:
            cuts += cut(obj.data, [((0, 0, HEIGHT), (0, 0, 1))])
    for obj in mesh_objs[:]:
        if not obj.data.polygons:
            mesh_objs.remove(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
    assert mesh_objs, slug
    palette_link(mesh_objs)
    pts = [v.co for o in mesh_objs for v in o.data.vertices]
    bounds = [[fn(v[i] for v in pts) for i in range(3)] for fn in (min, max)]
    assert abs(bounds[0][2]) < 0.0001 and abs(bounds[1][2] - HEIGHT) < 0.0001, bounds
    if slug in DOORS:
        assert all(all(v.co.x <= -1.0999 for v in o.data.vertices) or all(v.co.x >= 1.0999 for v in o.data.vertices) for o in mesh_objs)
    save_blend(ROOT / source)
    low_tris = triangles(mesh_objs)
    for obj in mesh_objs:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.000001)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context='VERTS')
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
    optimized_tris = triangles(mesh_objs)
    save_blend(ROOT / optimized)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / optimized))
    bpy.ops.export_scene.gltf(filepath=str(ROOT / glb), export_format='GLB', export_image_format='NONE',
                             export_animations=False, export_texcoords=True, export_normals=True)
    assert digest(ROOT / ref_glb) == before_hash
    wrapper = make_wrapper(slug, old, previous, glb, source, manifest, bounds)
    (ROOT / prefab(slug)).write_text(wrapper, encoding='utf-8')
    make_import(ref_glb, glb)
    record = dict(asset_id=asset_id(slug), asset_version=VERSION, slug=slug, level_id='expedition_01',
                  block_id='expedition', asset_family=FAMILY, legacy_prefab=previous.as_posix(),
                  reference_glb=ref_glb.as_posix(), reference_glb_sha256=before_hash,
                  source_blend=source.as_posix(), source_sha256=digest(ROOT / source),
                  optimized_blend=optimized.as_posix(), optimized_sha256=digest(ROOT / optimized),
                  visual_glb=glb.as_posix(), glb_sha256=digest(ROOT / glb),
                  prefab_path=prefab(slug).as_posix(), prefab_sha256=digest(ROOT / prefab(slug)),
                  logical_wall_height_m=HEIGHT, visual_wall_height_m=HEIGHT, bounds_blender_m=bounds,
                  source_triangles=src_tris, triangles_before=low_tris, triangles_after=optimized_tris,
                  reduction_ratio=(low_tris - optimized_tris) / low_tris,
                  operations=['Preserve native proportions below 2.8m; planar mesh section with palette cap',
                              'Remove degenerate and loose geometry; triangulate independently saved derivative'],
                  cut_cap_faces=cuts, door_opening=({'clear_width_m': 2.2, 'lintel': False} if slug in DOORS else None),
                  source_reference_retained=True)
    json_out(ROOT / manifest, record)
    print('LOW_WALL_BUILT', slug, src_tris, low_tris, optimized_tris, cuts, flush=True)
    return record


def replace_room_references(records):
    rules = {item['legacy_prefab']: item for item in records}
    totals = Counter()
    outputs = {}
    for room in ROOMS:
        path = ROOT / SCENES / f'f00_{room}_static_layout.tscn'
        raw = path.read_bytes()
        newline = b'\r\n' if b'\r\n' in raw else b'\n'
        text = raw.decode('utf-8').replace('\r\n', '\n')
        assert '\r' not in text
        sections = re.split(r'(?m)(?=^\[node )', text)
        refs = {}
        for match in re.finditer(r'(?m)^\[ext_resource [^\n]*?path="res://([^"\n]+)" [^\n]*?id="([^"]+)"[^\n]*\]$', sections[0]):
            item = rules.get(match[1])
            if item is not None and match[2] != 'enclosure_wall':
                refs[match[2]] = item
        # Remove OLD path UID when swapping to a new resource so the editor cannot select the previous asset.
        def redirect(match):
            line = match[0]
            rs = re.search(r' id="([^"]+)"', line)
            item = refs.get(rs[1]) if rs else None
            if not item:
                return line
            return re.sub(r' uid="[^"]+"', '', line.replace(item['legacy_prefab'], item['prefab_path']))
        sections[0] = re.sub(r'(?m)^\[ext_resource [^\n]+\]', redirect, sections[0])
        sections[1] = sections[1].replace('\n', f'\nmetadata/room_wall_height_m = {HEIGHT}\n', 1)
        for i, block in enumerate(sections[2:], 2):
            ref = re.search(r'instance=ExtResource\("([^"]+)"\)', block.splitlines()[0])
            item = refs.get(ref[1]) if ref else None
            if not item:
                continue
            totals[room] += 1
            # Godot-captured scenes occasionally serialize an entire copy of the previous prefab metadata.
            # Leave all layout identity/tower-side fields but let the new prefab own asset definition metadata.
            owner = set(metadata((ROOT / item['legacy_prefab']).read_text(encoding='utf-8-sig')))
            owner |= {'visual_bounds_size_m','bounds_size_m','logical_height_m','visual_height_m'}
            block = re.sub(r'(?m)^metadata/(\w+) = [^\n]*\n', lambda m: '' if m[1] in owner else m[0], block)
            block = re.sub(r'(?m)^metadata/authored_component_id = [^\n]+', 'metadata/authored_component_id = ' + json.dumps(item['asset_id']), block)
            sections[i] = block
        outputs[path] = ''.join(sections).encode('utf-8').replace(b'\n', newline)
    assert len(totals) == 12 and sum(totals.values()) == 304, totals
    for path, payload in outputs.items():
        path.write_bytes(payload)
    print('EXP01_LOW_WALL_ROOM_REFERENCES', dict(totals), flush=True)


if __name__ == '__main__':
    import sys
    mode = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if mode == ['rooms']:
        records = [json.loads((ROOT / SOURCE / 'component_packages' / slug / 'asset_manifest.json').read_text(encoding='utf-8')) for slug in INPUTS]
        replace_room_references(records)
    else:
        records = [build(slug, root) for slug, root in INPUTS.items() if not mode or slug in mode]
        if not mode:
            json_out(ROOT / SOURCE / 'component_catalog.json', records)
