"""Update only the expedition03 wooden door; preserve stable Godot paths.

Blender --background --factory-startup --python this_file.py
The independent source is saved before optimization and reopened before export.
"""
import bpy
import bmesh
import hashlib
import json
import math
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from workspace_paths import work_path

WORK = work_path('sessions/2026-11-06_expedition03_wood_door/report.json').parent
OLD = ROOT / 'art_source/environments/tower_zones/expedition/source/common_components/v017'
BASE = ROOT / 'art_source/environments/tower_zones/expedition/source/common_components/v019'
PKG = BASE / 'component_packages/manor_door_double'
SOURCE = PKG / 'manor_door_double_source_v019.blend'
OPT = BASE / 'export/v019/manor_door_double_optimized_v019.blend'
GLB = ROOT / 'assets/art/environments/tower_zones/expedition/components/common_components/manor_door_double/env_manor_door_double_visual_top3d.glb'
PAL = ROOT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ORIGINAL = OLD / 'component_packages/manor_door_double/manor_door_double_source_v017.blend'
for folder in (PKG, OPT.parent):
    folder.mkdir(parents=True, exist_ok=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf8')

protected = {str(p): sha(p) for p in (ORIGINAL, PAL)}
bpy.ops.wm.open_mainfile(filepath=str(ORIGINAL))
scene = bpy.context.scene
scene.name = '暗红双面通顶木门_制作母版_v019'
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.render.resolution_x = 720
scene.render.resolution_y = 820
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
if scene.world is None:
    scene.world = bpy.data.worlds.new('门组件验收环境')
scene.world.color = (.10, .10, .10)
for image in bpy.data.images:
    if image.source == 'FILE':
        image.filepath = str(PAL)
        assert image.packed_file is None
for mat in bpy.data.materials:
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                node.interpolation = 'Closest'

obj = next(o for o in scene.objects if o.type == 'MESH')
obj.name = '通顶木门_双面暗红木饰与黄铜花纹'
me = obj.data
# Identify disconnected construction pieces before editing; do not scale the door.
adj = {v.index: [] for v in me.vertices}
for edge in me.edges:
    a, b = edge.vertices
    adj[a].append(b)
    adj[b].append(a)
seen, islands = set(), []
for index in adj:
    if index in seen:
        continue
    todo, ids = [index], []
    seen.add(index)
    while todo:
        q = todo.pop()
        ids.append(q)
        for v in adj[q]:
            if v not in seen:
                seen.add(v)
                todo.append(v)
    islands.append(ids)
core = max(islands, key=lambda ids: max(me.vertices[i].co.z for i in ids) - min(me.vertices[i].co.z for i in ids))
core_y = sum(me.vertices[i].co.y for i in core) / len(core)
for ids in islands:
    lo_z = min(me.vertices[i].co.z for i in ids)
    hi_z = max(me.vertices[i].co.z for i in ids)
    width = max(me.vertices[i].co.x for i in ids) - min(me.vertices[i].co.x for i in ids)
    for i in ids:
        v = me.vertices[i]
        v.co.y -= core_y
        if ids is core:
            v.co.y = math.copysign(.16, v.co.y)
            if v.co.z > 2:
                v.co.z += .3
        else:
            v.co.y -= .1  # move front ornament outward by the added half thickness
            # Deep raised fields, projecting brass frames, and readable handle clearance.
            if len(ids) == 16:
                v.co.y -= .07
            elif width > .5 and hi_z - lo_z > .3:
                v.co.y -= .045 if v.co.y < -.175 else 0
            else:
                v.co.y -= .08 if v.co.y < -.2 else .06
            if lo_z > 2:
                v.co.z += .3
            elif hi_z - lo_z > 1 and v.co.z > (hi_z + lo_z) / 2:
                v.co.z += .3

# Palette cells are zero-based in Blender UV space. Carpet main red is (3,8).
# Final user direction: dark burgundy, with an even deeper recessed panel.
uv = me.uv_layers['PaletteUV']
core_set = set(core)
for face in me.polygons:
    if face.material_index != 1:
        continue
    target = (0, 8) if all(i in core_set for i in face.vertices) else (0, 1)
    for li in face.loop_indices:
        old_uv = uv.data[li].uv.copy()
        uv.data[li].uv = ((target[0] + old_uv.x * 10 % 1) / 10,
                          (target[1] + old_uv.y * 10 % 1) / 10)

# Mirror the complete applied front design, preserving material and UV data.
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
front_faces = [f for f in bm.faces if not all(v.index in core_set for v in f.verts)]
front_verts = {v for f in front_faces for v in f.verts}
front_edges = {e for f in front_faces for e in f.edges}
dup = bmesh.ops.duplicate(bm, geom=list(front_verts) + list(front_edges) + front_faces)['geom']
for v in (g for g in dup if isinstance(g, bmesh.types.BMVert)):
    v.co.y = -v.co.y
mirrored = [g for g in dup if isinstance(g, bmesh.types.BMFace)]
bmesh.ops.reverse_faces(bm, faces=mirrored)
bm.to_mesh(me)
bm.free()

# A small brass quatrefoil and diamond echo the carpet's floral pattern on each face.
verts, faces = [], []
def ribbon(points, width=.012):
    start = len(verts)
    for i, p in enumerate(points):
        a = Vector(points[(i + 1) % len(points)]) - Vector(points[i - 1])
        t = Vector((-a.z, 0, a.x)).normalized() * width / 2
        verts.extend((tuple(Vector(p) + t), tuple(Vector(p) - t)))
    for i in range(len(points)):
        j = (i + 1) % len(points)
        faces.append((start + 2*i, start + 2*j, start + 2*j+1, start + 2*i+1))
for side in (-1, 1):
    for x in (-.55, .55):
        y, z = side * .267, 1.80
        ribbon([(x, y, z+.33), (x+.27, y, z), (x, y, z-.33), (x-.27, y, z)])
        ribbon([(x + (.13 + .045*math.cos(4*t))*math.cos(t), y+side*.002,
                 z + (.13 + .045*math.cos(4*t))*math.sin(t))
                for t in [2*math.pi*i/40 for i in range(40)]])
orn = bpy.data.meshes.new('双面黄铜菱花')
orn.from_pydata(verts, [], faces)
orn.materials.append(me.materials[0])
uv2 = orn.uv_layers.new(name='PaletteUV')
uv2.active_render = True
for f in orn.polygons:
    for j, li in enumerate(f.loop_indices):
        uv2.data[li].uv = ((6.5 + .23*math.cos(j*math.pi/2)) / 10,
                           (7.5 + .23*math.sin(j*math.pi/2)) / 10)
orn_ob = bpy.data.objects.new('双面黄铜菱花', orn)
scene.collection.objects.link(orn_ob)
# Give the floral inlay real edge walls and a small bevel, rather than a flat ribbon.
solid = orn_ob.modifiers.new('黄铜菱花浮雕厚度', 'SOLIDIFY')
solid.thickness = .018
solid.offset = 0
bevel = orn_ob.modifiers.new('黄铜菱花边缘倒角', 'BEVEL')
bevel.width = .003
bevel.segments = 1
bpy.context.view_layer.objects.active = orn_ob
orn_ob.select_set(True)
for modifier in list(orn_ob.modifiers):
    bpy.ops.object.modifier_apply(modifier=modifier.name)
uv2 = orn_ob.data.uv_layers['PaletteUV']
for face in orn_ob.data.polygons:
    for j, li in enumerate(face.loop_indices):
        angle = 2*math.pi*j / len(face.loop_indices) + .4
        uv2.data[li].uv = ((6.5+.23*math.cos(angle))/10,
                          (7.5+.23*math.sin(angle))/10)
bpy.context.view_layer.objects.active = obj
# The new inlay is already beveled: evaluate the original wood/frame bevel
# before joining so it does not subdivide the inlay for a second time.
for modifier in list(obj.modifiers):
    bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
orn_ob.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.join()
obj.data.uv_layers.active = obj.data.uv_layers['PaletteUV']
obj.data.uv_layers['PaletteUV'].active_render = True
uv = obj.data.uv_layers['PaletteUV']
for face in obj.data.polygons:
    center = sum((uv.data[li].uv for li in face.loop_indices), Vector((0, 0))) / len(face.loop_indices)
    cell = (int(center.x * 10), int(center.y * 10))
    for j, li in enumerate(face.loop_indices):
        angle = 2*math.pi*j/len(face.loop_indices)+.4
        uv.data[li].uv = ((cell[0]+.5+.23*math.cos(angle))/10,
                          (cell[1]+.5+.23*math.sin(angle))/10)
for face in obj.data.polygons:
    face.use_smooth = False
obj['asset_id'] = 'ENV-EXP03-MANOR-DOOR-DOUBLE'
obj['asset_version'] = 'v019'
obj['door_core_thickness_m'] = .32
obj['double_sided_design'] = True
scene.camera.data.type = 'ORTHO'
scene.camera.data.ortho_scale = 3.6
for mat in list(bpy.data.materials):
    if mat.users == 0:
        bpy.data.materials.remove(mat)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
source_hash = sha(SOURCE)

def triangles():
    dg = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(dg)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    n = len(mesh.loop_triangles)
    evaluated.to_mesh_clear()
    return n

def render_views(prefix):
    cam = scene.camera
    light = next(o for o in scene.objects if o.type == 'LIGHT')
    light.data.energy = 750
    light.data.shape = 'DISK'
    light.data.size = 4
    views = {'front': (3,-7,3.2), 'back': (-3,7,3.2),
             'side': (7,-1,3.2), 'game': (3,-4,7)}
    for name, position in views.items():
        cam.location = position
        cam.rotation_euler = (Vector((0,0,1.4))-cam.location).to_track_quat('-Z','Y').to_euler()
        light.location = (position[0]/2, position[1]/2, 5)
        light.rotation_euler = (Vector((0,0,1.4))-light.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath = str(WORK / (prefix+'_'+name+'.png'))
        bpy.ops.render.render(write_still=True)

before = triangles()
render_views('source')
# All optimization mutations are confined to this separately persisted derivative.
bpy.ops.wm.save_as_mainfile(filepath=str(OPT), compress=True)
dg = bpy.context.evaluated_depsgraph_get()
evaluated = obj.evaluated_get(dg)
optimized_mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=dg, preserve_all_data_layers=True)
obj.modifiers.clear()
obj.data = optimized_mesh
bm = bmesh.new()
bm.from_mesh(optimized_mesh)
nv = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
merged = nv - len(bm.verts)
zero = [f for f in bm.faces if f.calc_area() < 1e-12]
zero_count = len(zero)
if zero:
    bmesh.ops.delete(bm, geom=zero, context='FACES_ONLY')
loose = [v for v in bm.verts if not v.link_faces]
loose_count = len(loose)
if loose:
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(optimized_mesh)
bm.free()
optimized_mesh.update()
# Bevel cap UVs may collapse even when the source islands have area. Preserve
# each face's sampled palette cell and restore a small editable island.
uv = optimized_mesh.uv_layers['PaletteUV']
for face in optimized_mesh.polygons:
    center = sum((uv.data[li].uv for li in face.loop_indices), Vector((0, 0))) / len(face.loop_indices)
    cell = (int(center.x * 10), int(center.y * 10))
    for j, li in enumerate(face.loop_indices):
        angle = 2*math.pi*j / len(face.loop_indices) + .4
        uv.data[li].uv = ((cell[0]+.5+.23*math.cos(angle))/10,
                          (cell[1]+.5+.23*math.sin(angle))/10)
after = triangles()
bpy.ops.wm.save_as_mainfile(filepath=str(OPT), compress=True)
bpy.ops.wm.open_mainfile(filepath=str(OPT))
obj = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
scene = bpy.context.scene
render_views('optimized')
bpy.ops.object.select_all(action='DESELECT')
for ob in scene.objects:
    if ob.type in ('MESH', 'EMPTY'):
        ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', use_selection=True,
                         export_image_format='NONE', export_texcoords=True, export_normals=True,
                         export_materials='EXPORT', export_animations=False, export_cameras=False,
                         export_lights=False, export_yup=True)
assert sha(SOURCE) == source_hash
assert all(sha(Path(p)) == h for p, h in protected.items())
vv = [obj.matrix_world @ v.co for v in obj.data.vertices]
low = [min(v[k] for v in vv) for k in range(3)]
high = [max(v[k] for v in vv) for k in range(3)]
manifest = json.loads((OLD/'component_packages/manor_door_double/asset_manifest.json').read_text(encoding='utf8'))
manifest.update(asset_version='v019', component_blend=SOURCE.relative_to(ROOT).as_posix(),
                component_blend_sha256=source_hash, optimized_blend=OPT.relative_to(ROOT).as_posix(),
                source_room_type_blend=SOURCE.relative_to(ROOT).as_posix(), source_room_type_sha256=source_hash,
                bounds_size_m=[round(high[k]-low[k],6) for k in range(3)],
                source_bounds_size_m=[round(high[k]-low[k],6) for k in range(3)],
                glb_sha256=sha(GLB), runtime_integrated=False,
                vertex_count=len(obj.data.vertices), double_sided_design=True,
                door_core_thickness_m=.32, color_contract={'carpet_main_cell':[3,8],
                'door_main_cell':[0,8], 'door_inset_cell':[0,1], 'main_srgb':'#29070E',
                'inset_srgb':'#240310'}, relief_contract={'raised_field_projection_m':.085,
                'brass_flower_thickness_m':.018,'handle_additional_clearance_m':.07})
manifest['export'] = dict(asset_id=manifest['asset_id'], source_path=manifest['component_blend'],
    optimized_path=manifest['optimized_blend'], source_sha256_before=source_hash,
    source_sha256_after=sha(SOURCE), optimized_sha256=sha(OPT),
    operations={'evaluate_bevels':True,'merge_distance_m':1e-6,'merged_vertices':merged,
                'zero_area_faces_removed':zero_count,'loose_vertices_removed':loose_count,
                'recalculate_normals':True,'restore_bevel_cap_palette_islands':True,
                'internal_faces_preserved':'Both sides, core and shadow-casting surfaces retained.'},
    triangles_before=before, triangles_after=after, reduction_ratio=(before-after)/before,
    budget=None, budget_source='No user triangle budget; safe topology cleanup only.',
    glb_path=manifest['visual_glb'], glb_sha256=sha(GLB),
    palette_sha256_before=protected[str(PAL)], palette_sha256_after=sha(PAL),
    fidelity_review={'passed':False,'views':['front','back','side','game'],
                     'evidence':str(WORK),'scope':'Same camera/light source versus optimized images; awaiting review.'})
manifest['validation'] = dict(blender_material_uv_passed=False, godot_load_passed=False,
                              godot_rendered=False, formal_scene_assembled=False)
dump(PKG/'asset_manifest.json', manifest)
dump(WORK/'report.json',dict(bounds_min=low,bounds_max=high,manifest=manifest,
                            protected_hashes=protected,source_unchanged=True))
print('MANOR_DOOR_EXPORTED', before, after, manifest['bounds_size_m'])
