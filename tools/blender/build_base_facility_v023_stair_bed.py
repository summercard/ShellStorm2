import bpy
import bmesh
import hashlib
import json
import math
from mathutils import Vector
from pathlib import Path

ROOT = Path('/Users/summercards/ShellStorm2')
SOURCE_V023 = ROOT / 'source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v023.blend'
EXPORT_DIR = ROOT / 'source/art/blender/base_facility_layout/export/v023'
DERIVED = EXPORT_DIR / 'base_facility_runtime_layout_hq-v023-stair_bed.blend'

PACKAGES = {
    'northwest_l_stair': {
        'package': '14_西北贴墙L型楼梯_资产包',
        'collection': '14_西北贴墙L型楼梯_资产包',
        'glb': ROOT / 'assets/art/environments/base_facility_3d/components/env_base99_stair_l_z5/env_base99_stair_l_z5_visual_top3d_v006.glb',
        'scope': 'stair',
    },
    'loft_bed_and_bedding': {
        'package': '31_参考床架床品与床下收纳_资产包',
        'collection': '31__02_游戏输出_整合模型',
        'glb': ROOT / 'assets/art/environments/base_facility_3d/components/env_base99_remaining_facilities_v021/loft_bed_and_bedding/loft_bed_and_bedding_visual_top3d_v004.glb',
        'scope': 'remaining',
    },
}

def recursive_objects(collection):
    return set(collection.all_objects)

def is_visual_mesh(obj):
    return obj.type == 'MESH' and not obj.name.startswith('COLLISION_')

def triangle_count(mesh):
    return sum(max(1, len(poly.vertices) - 2) for poly in mesh.polygons)

def uv_polygon_area(uvs):
    return abs(sum(uvs[index].x * uvs[(index + 1) % len(uvs)].y - uvs[(index + 1) % len(uvs)].x * uvs[index].y for index in range(len(uvs)))) * 0.5

def repair_degenerate_palette_uv(mesh, palette_uv):
    repaired = 0
    for polygon in mesh.polygons:
        loop_indices = list(polygon.loop_indices)
        uvs = [palette_uv.data[index].uv.copy() for index in loop_indices]
        if uv_polygon_area(uvs) > 0.0000001:
            continue
        average = sum(uvs, Vector((0.0, 0.0))) / len(uvs)
        cell_x = min(9, max(0, int(average.x * 10)))
        cell_y = min(9, max(0, int(average.y * 10)))
        center = Vector(((cell_x + 0.5) / 10.0, (cell_y + 0.5) / 10.0))
        for index, loop_index in enumerate(loop_indices):
            angle = math.tau * index / len(loop_indices)
            palette_uv.data[loop_index].uv = center + Vector((math.cos(angle), math.sin(angle))) * 0.02
        repaired += 1
    return repaired

def world_bbox(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects if is_visual_mesh(obj) for corner in obj.bound_box]
    assert points, 'target package has no visual meshes'
    return {
        'min': [min(point[i] for point in points) for i in range(3)],
        'max': [max(point[i] for point in points) for i in range(3)],
    }

def lock_signature(objects):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda item: item.name):
        digest.update(obj.name.encode('utf-8'))
        digest.update(obj.type.encode('utf-8'))
        digest.update(repr(tuple(round(value, 6) for row in obj.matrix_world for value in row)).encode())
        if obj.type == 'MESH':
            digest.update(str(len(obj.data.vertices)).encode())
            digest.update(str(len(obj.data.edges)).encode())
            digest.update(str(len(obj.data.polygons)).encode())
            digest.update('|'.join(material.name if material else '' for material in obj.data.materials).encode('utf-8'))
    return digest.hexdigest()

# Preserve the current editable v022 work as a new source version before runtime-only edits.
bpy.context.scene['asset_version'] = 'v023'
bpy.context.scene['v023_scope'] = '14_西北贴墙L型楼梯_资产包; 31_参考床架床品与床下收纳_资产包'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_V023))

target_objects = set()
for package in PACKAGES.values():
    collection = bpy.data.collections.get(package['collection'])
    assert collection is not None, f"missing collection {package['collection']}"
    target_objects.update(recursive_objects(collection))

locked_before = lock_signature(set(bpy.context.scene.objects) - target_objects)
stats = {}
for slug, package in PACKAGES.items():
    objects = recursive_objects(bpy.data.collections[package['collection']])
    before = after = removed = cleaned_uv_layers = repaired_uv_faces = 0
    for obj in objects:
        if not is_visual_mesh(obj):
            continue
        mesh = obj.data
        before += triangle_count(mesh)
        palette_uv = mesh.uv_layers.get('PaletteUV')
        assert palette_uv is not None, f'{obj.name} is missing PaletteUV'
        mesh.uv_layers.active = palette_uv
        palette_uv.active_render = True
        for uv in list(mesh.uv_layers):
            if uv != palette_uv:
                mesh.uv_layers.remove(uv)
                cleaned_uv_layers += 1
        repaired_uv_faces += repair_degenerate_palette_uv(mesh, palette_uv)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.normal_update()
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        downward = [face for face in bm.faces if (normal_matrix @ face.normal).normalized().z < -0.65]
        removed += sum(max(1, len(face.verts) - 2) for face in downward)
        if downward:
            bmesh.ops.delete(bm, geom=downward, context='FACES')
        bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='BEAUTY', ngon_method='BEAUTY')
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        palette_uv = mesh.uv_layers['PaletteUV']
        repaired_uv_faces += repair_degenerate_palette_uv(mesh, palette_uv)
        after += len(mesh.polygons)
    stats[slug] = {
        'package': package['package'],
        'collection': package['collection'],
        'scope': package['scope'],
        'glb': str(package['glb'].relative_to(ROOT)),
        'triangles_before': before,
        'triangles_after': after,
        'downward_triangles_removed': removed,
        'legacy_uv_layers_removed': cleaned_uv_layers,
        'degenerate_palette_uv_faces_repaired': repaired_uv_faces,
        'bbox_blender': world_bbox(objects),
    }

locked_after = lock_signature(set(bpy.context.scene.objects) - target_objects)
assert locked_before == locked_after, 'a locked object changed during v023 target optimization'
bpy.context.scene['v023_derived_stats'] = json.dumps(stats, ensure_ascii=False)
EXPORT_DIR.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED))

for slug, package in PACKAGES.items():
    objects = [obj for obj in recursive_objects(bpy.data.collections[package['collection']]) if is_visual_mesh(obj)]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    package['glb'].parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(package['glb']),
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_materials='EXPORT',
        export_image_format='NONE',
        export_lights=False,
        export_cameras=False,
        export_extras=True,
    )

manifest = {
    'asset_id': 'ENV-BASE99-V023-STAIR-BED',
    'version': 'v023',
    'source_blend': str(SOURCE_V023.relative_to(ROOT)),
    'source_sha256': hashlib.sha256(SOURCE_V023.read_bytes()).hexdigest(),
    'derived_blend': str(DERIVED.relative_to(ROOT)),
    'packages': stats,
    'lock_signature': {'before': locked_before, 'after': locked_after, 'locked_match': True},
}
(EXPORT_DIR / 'export_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print('BASE99_V023_STAIR_BED_BUILT=' + json.dumps({
    'packages': len(stats),
    'removed_triangles': sum(item['downward_triangles_removed'] for item in stats.values()),
    'locked_match': locked_before == locked_after,
}, ensure_ascii=False))
