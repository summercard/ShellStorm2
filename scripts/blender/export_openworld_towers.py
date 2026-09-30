"""Export confirmed tower sources without modifying their geometry/layout masters.

blender --factory-startup --background --python scripts/blender/export_openworld_towers.py -- --project-root PATH
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\r\n')


def export_tower(root, slug, version):
    base = root / 'assets/art/environments/open_world'
    source_dir = base / 'source' / slug / version
    catalog = json.loads((source_dir / 'catalog.json').read_text(encoding='utf-8-sig'))
    source = next(source_dir.glob('*.blend'))
    source_hash = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    bpy.context.view_layer.update()
    packages = catalog['packages']
    keep = {name for p in packages for name in p['objects']}
    records = []
    # Freeze evaluated world-space output first; parent removal must not move crane parts.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for package in packages:
        objects = [bpy.data.objects[n] for n in package['objects']]
        # v003 cranes were grouped after their vertices had been baked to world space.
        # Their organizational parent adds world_origin a second time. Catalog bounds
        # are the frozen intended layout: cancel only this known grouping translation.
        matrices = {}
        for obj in objects:
            matrix = obj.matrix_world.copy()
            if package['slug'].startswith('crane_'):
                assembly = next(a for a in catalog['crane_assemblies'] if package['slug'] in a['component_packages'])
                matrix = Matrix.Translation(-Vector(assembly['world_origin'])) @ matrix
            matrices[obj.name] = matrix
        corners = [matrices[obj.name] @ Vector(c) for obj in objects for c in obj.bound_box]
        low = Vector([min(c[i] for c in corners) for i in range(3)])
        high = Vector([max(c[i] for c in corners) for i in range(3)])
        assert (low - Vector(package['bounds_min'])).length < 0.02, (package['slug'], list(low), package['bounds_min'])
        assert (high - Vector(package['bounds_max'])).length < 0.02, (package['slug'], list(high), package['bounds_max'])
        anchor = Vector(((low.x + high.x)/2, (low.y + high.y)/2, low.z))
        triangles = 0
        for obj in objects:
            assert obj.type == 'MESH', (package['slug'], obj.type)
            matrix = matrices[obj.name]
            mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), depsgraph=depsgraph)
            mesh.transform(matrix)
            mesh.transform(Matrix.Translation(-anchor))
            obj.parent = None
            obj.matrix_world.identity()
            obj.modifiers.clear()
            obj.data = mesh
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.triangulate(bm, faces=list(bm.faces))
            bm.to_mesh(mesh)
            bm.free()
            mesh.update()
            assert mesh.uv_layers, 'missing palette UV: ' + obj.name
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_render = False
            triangles += len(mesh.polygons)
        record = dict(package)
        record.update(anchor_blender=list(anchor), position_godot=[anchor.x, anchor.z, -anchor.y],
                      bounds_blender=[list(low), list(high)], triangle_count=triangles,
                      asset_id=catalog['asset_id']+'-'+package['slug'].upper().replace('_','-'))
        records.append(record)
    for obj in list(bpy.data.objects):
        if obj.name not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in bpy.data.collections:
        collection.hide_viewport = False
        collection.hide_render = False
    derived = base / 'source' / slug / 'export' / version / f'env_{slug}-{version}-runtime.blend'
    derived.parent.mkdir(parents=True, exist_ok=True)
    (derived.parent / '.gdignore').touch()
    bpy.ops.wm.save_as_mainfile(filepath=str(derived))
    # Mandatory disk roundtrip: the reopened derived file is the actual export source.
    bpy.ops.wm.open_mainfile(filepath=str(derived))
    for n, record in enumerate(records, 1):
        bpy.ops.object.select_all(action='DESELECT')
        selected = [bpy.data.objects[name] for name in record['objects']]
        for obj in selected:
            obj.hide_set(False)
            obj.select_set(True)
        bpy.context.view_layer.objects.active = selected[0]
        target = base / 'components' / slug / record['slug'] / f"env_{slug}_{record['slug']}_visual_top3d.glb"
        target.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True,
            export_apply=True, export_yup=True, export_texcoords=True, export_normals=True,
            export_tangents=True, export_materials='EXPORT', export_image_format='NONE',
            export_extras=False, export_cameras=False, export_lights=False, export_animations=False)
        record.update(glb=target.relative_to(root).as_posix(), glb_sha256=digest(target),
                      prefab=f"assets/art/environments/open_world/runtime/{slug}/{record['slug']}/env_{slug}_{record['slug']}_root_top3d.tscn")
        print(f'TOWER_EXPORT_PROGRESS {slug} {n}/{len(records)}', flush=True)
    assert digest(source) == source_hash, 'source master was changed'
    write_json(derived.parent / 'export_manifest.json', dict(schema='shellstorm2.openworld.export.v001',
        asset_id=catalog['asset_id'], version=version, source=source.relative_to(root).as_posix(),
        source_sha256=source_hash, derived=derived.relative_to(root).as_posix(), derived_sha256=digest(derived),
        coordinate_map='Blender (x,y,z) -> Godot (x,z,-y)', collision='none_visual_only',
        optimization='evaluated output meshes only; local bottom-center origin; triangulation; no source edits or silhouette decimation',
        records=records))
    print('TOWER_EXPORT_OK', slug, len(records), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--project-root', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    for slug, version in [('tower_02','v003'), ('tower_03','v001')]:
        export_tower(Path(args.project_root).resolve(), slug, version)
