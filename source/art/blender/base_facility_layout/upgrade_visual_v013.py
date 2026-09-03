import bpy
import math


MET = bpy.data.materials['01_精工金属_紫色骨架']
MAT = bpy.data.materials['02_细腻哑光_青绿大面']
GLS = bpy.data.materials['03_清漆反光_紫粉点缀']
EMI = bpy.data.materials['04_柔和自发光_UI灯光']


def child(parent, name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if collection.name not in [item.name for item in parent.children]:
        parent.children.link(collection)
    return collection


def link_only(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def set_palette_uv(obj, column, row):
    if obj.type != 'MESH':
        return
    mesh = obj.data
    layer = mesh.uv_layers.get('PaletteUV') or mesh.uv_layers.new(name='PaletteUV')
    u0, u1 = (column + 0.22) / 10.0, (column + 0.78) / 10.0
    v0, v1 = 1.0 - (row + 0.78) / 10.0, 1.0 - (row + 0.22) / 10.0
    corners = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
    for polygon in mesh.polygons:
        for index, loop_index in enumerate(polygon.loop_indices):
            layer.data[loop_index].uv = corners[index % 4]
    layer.active = True
    for uv_layer in mesh.uv_layers:
        uv_layer.active_render = uv_layer == layer


def finish(obj, collection, material, column, row, bevel=0.0):
    link_only(obj, collection)
    if obj.type == 'MESH':
        obj.data.materials.append(material)
        set_palette_uv(obj, column, row)
        if bevel:
            modifier = obj.modifiers.new('圆角', 'BEVEL')
            modifier.width = bevel
            modifier.segments = 2
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            obj.select_set(False)
    obj['batch_scope'] = '视觉高还原验收迭代_v013'
    obj['reference_locked'] = True
    return obj


def box(name, location, dimensions, collection, material=MET, column=0, row=9, bevel=0.02):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, collection, material, column, row, bevel)


def cylinder(name, location, radius, depth, collection, material=MET, column=0, row=9, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    return finish(obj, collection, material, column, row, 0.01)


def sphere(name, location, radius, collection, material=EMI, column=6, row=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, collection, material, column, row)


def text_mesh(name, body, location, size, collection, material=EMI, column=9, row=9, rotation=(math.pi / 2, 0, 0)):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = body
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.size = size
    curve.extrude = 0.012
    curve.bevel_depth = 0.004
    curve.bevel_resolution = 2
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object
    obj.name = name
    return finish(obj, collection, material, column, row)


def area_light(name, location, color, energy, size, collection, rotation=(math.pi / 2, 0, 0)):
    data = bpy.data.lights.new(name, 'AREA')
    data.color = color
    data.energy = energy
    data.shape = 'RECTANGLE'
    data.size = size
    data.size_y = size * 0.24
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_euler = rotation
    link_only(obj, collection)
    obj['batch_scope'] = '视觉高还原验收迭代_v013'
    return obj


def triangle(name, points, collection, material, column, row):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], [(0, 1, 2)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, collection, material, column, row)


def clone_sources(output_collection, source_collection):
    for obj in list(output_collection.objects):
        copy = obj.copy()
        if obj.data:
            copy.data = obj.data.copy()
        copy.name = obj.name + '__源'
        copy.hide_viewport = True
        copy.hide_render = True
        copy['source_for'] = obj.name
        source_collection.objects.link(copy)
    source_collection.hide_viewport = True


def set_existing_uv(name, column, row, dimensions=None):
    for suffix in ('', '__源'):
        obj = bpy.data.objects.get(name + suffix)
        if obj is None:
            continue
        set_palette_uv(obj, column, row)
        if dimensions:
            obj.dimensions = dimensions


output_parent = bpy.data.collections['02_游戏输出_独立资产包_v011']
source_parent = bpy.data.collections['01_制作组件_已统一材质']
output_root = child(output_parent, '95_参考图高还原视觉迭代_v013')
source_root = child(source_parent, '95_参考图高还原视觉迭代_制作组件_v013')
source_root.hide_viewport = True
wall = child(output_root, '95_二楼后墙参考图可读性深化_资产包_v013')
stairs = child(output_root, '96_双楼梯暖光串灯深化_资产包_v013')
wall_source = child(source_root, '95_二楼后墙参考图可读性深化_制作组件_v013')
stairs_source = child(source_root, '96_双楼梯暖光串灯深化_制作组件_v013')

# Back-wall panel rhythm and colour-bundle hierarchy. These are thin overlays only.
box('后墙v013_顶部结构压边', (0.0, 14.47, 9.34), (28.8, 0.065, 0.14), wall, MET, 0, 9, 0.02)
box('后墙v013_上部内嵌分缝', (0.0, 14.445, 8.82), (28.2, 0.035, 0.055), wall, MET, 0, 9, 0.008)
for index, (x, z, width, height) in enumerate((
    (-12.25, 7.65, 3.70, 1.92),
    (-8.25, 7.72, 3.65, 1.82),
    (-4.25, 7.42, 3.35, 1.15),
    (3.65, 7.38, 3.55, 1.08),
    (7.50, 7.55, 3.30, 1.72),
)):
    for side, location, dimensions in (
        ('T', (x, 14.445, z + height / 2), (width, 0.04, 0.06)),
        ('B', (x, 14.445, z - height / 2), (width, 0.04, 0.06)),
        ('L', (x - width / 2, 14.445, z), (0.06, 0.04, height)),
        ('R', (x + width / 2, 14.445, z), (0.06, 0.04, height)),
    ):
        box(f'后墙v013_面板框{index + 1}_{side}', location, dimensions, wall, MET, 0, 9, 0.01)
    for sx in (-width * 0.43, width * 0.43):
        for sz in (-height * 0.40, height * 0.40):
            cylinder(
                f'后墙v013_面板铆钉{index + 1}_{sx:+.2f}_{sz:+.2f}',
                (x + sx, 14.405, z + sz), 0.025, 0.02, wall, GLS, 3, 0, (math.pi / 2, 0, 0)
            )
for index, (z, column) in enumerate(((9.18, 4), (9.11, 3), (9.04, 1))):
    box(f'后墙v013_彩色线束横向_{index + 1}', (-0.15, 14.355, z), (23.9, 0.018, 0.025), wall, GLS if index == 0 else MAT, column, 0, 0.004)
for x in (-11.8, -6.8, -1.8, 3.2, 8.2, 12.0):
    box(f'后墙v013_线束扎带_{x:+.1f}', (x, 14.325, 9.11), (0.10, 0.06, 0.38), wall, MET, 0, 9, 0.01)

# Reference-specific poster, neon and sign readability in their existing placements.
box('EXPLORE_v013_黑色海报框', (-2.12, 14.29, 8.05), (1.38, 0.045, 1.66), wall, MET, 0, 9, 0.02)
box('EXPLORE_v013_内层海报纸', (-2.12, 14.255, 8.00), (1.17, 0.012, 1.37), wall, GLS, 2, 7, 0.008)
text_mesh('EXPLORE_v013_标题', 'EXPLORE', (-2.12, 14.235, 8.55), 0.16, wall)
triangle('EXPLORE_v013_青色山峰', [(-2.62, 14.225, 7.60), (-2.20, 14.225, 8.20), (-1.78, 14.225, 7.60)], wall, MAT, 3, 0)
triangle('EXPLORE_v013_紫色远山', [(-2.36, 14.220, 7.58), (-1.98, 14.220, 7.96), (-1.65, 14.220, 7.58)], wall, GLS, 2, 7)
set_existing_uv('GOOD_VIBES_v012_粉紫背光安装底板', 0, 9, (1.46, 0.06, 0.72))
set_existing_uv('GOOD_VIBES_v012_粉色霓虹字', 9, 9)
box('GOOD_VIBES_v013_霓虹外框', (10.55, 14.315, 8.48), (1.58, 0.028, 0.84), wall, GLS, 2, 7, 0.02)
text_mesh('GOOD_VIBES_v013_白粉霓虹', 'GOOD\nVIBES', (10.55, 14.285, 8.48), 0.23, wall)
area_light('GOOD_VIBES_v013_粉紫洗墙', (10.55, 13.84, 8.47), (1.0, 0.10, 0.46), 58, 1.15, wall)
box('STAY_CURIOUS_v013_红色标识底板', (-14.47, 11.02, 5.18), (0.045, 1.72, 0.78), wall, GLS, 5, 0, 0.022)
text_mesh('STAY_CURIOUS_v013_白色发光字', 'STAY\nCURIOUS', (-14.435, 11.02, 5.18), 0.21, wall, EMI, 9, 9, (0, math.pi / 2, 0))
area_light('STAY_CURIOUS_v013_暖红洗墙', (-13.92, 11.02, 5.18), (1.0, 0.22, 0.05), 42, 0.9, wall, (0, math.pi / 2, 0))
area_light('后墙v013_冷白填充灯A', (-7.3, 13.75, 8.10), (0.26, 0.62, 1.0), 115, 4.4, wall)
area_light('后墙v013_冷白填充灯B', (5.8, 13.75, 8.18), (0.28, 0.65, 1.0), 105, 4.0, wall)

# Warm bulb strings attach to the existing rail axes only; treads and rail gaps remain untouched.
for index, t in enumerate((0.05, 0.18, 0.31, 0.44, 0.57, 0.70, 0.83, 0.96)):
    y = 8.24 + (12.80 - 8.24) * t
    z = 0.50 + (3.55 - 0.50) * t
    sphere(f'西北L梯v013_下段暖光串灯_{index + 1:02d}_自发光', (-12.86, y, z + 0.03), 0.065, stairs)
    x = -12.80 + (-8.24 + 12.80) * t
    z = 3.55 + (6.59 - 3.55) * t
    sphere(f'西北L梯v013_上段暖光串灯_{index + 1:02d}_自发光', (x, 12.86, z + 0.03), 0.065, stairs)
for side, x in enumerate((12.28, 14.12)):
    for index, t in enumerate((0.04, 0.20, 0.36, 0.52, 0.68, 0.84, 0.98)):
        y = 10.38 + (13.98 - 10.38) * t
        z = 6.55 + (8.90 - 6.55) * t
        sphere(f'东侧楼梯v013_{side + 1}侧暖光串灯_{index + 1:02d}_自发光', (x, y - 0.035, z + 0.03), 0.06, stairs)
for name, location in (
    ('西北L梯v013_下段串灯电源座', (-12.88, 8.18, 0.42)),
    ('西北L梯v013_上段串灯电源座', (-12.88, 12.86, 3.48)),
    ('东侧楼梯v013_左侧串灯电源座', (12.28, 10.30, 6.48)),
    ('东侧楼梯v013_右侧串灯电源座', (14.12, 10.30, 6.48)),
):
    cylinder(name, location, 0.09, 0.05, stairs, MET, 0, 9, (math.pi / 2, 0, 0))

clone_sources(wall, wall_source)
clone_sources(stairs, stairs_source)
for collection in (wall, stairs):
    collection['version'] = 'v013'
    collection['visual_acceptance'] = '参考图位置、轮廓、颜色、灯光、密度迭代'
    collection['scope_lock'] = '二楼后墙和已存在楼梯栏杆附属物'
for collection in (wall_source, stairs_source):
    collection.hide_viewport = True

bpy.context.scene['visual_qa_v013'] = '后墙面板节奏、标识可读性、线束和楼梯暖光串灯'
save_path = r'I:\工作项目\shellstrom2\ShellStorm2\source\art\blender\base_facility_layout\base_facility_runtime_layout_hq_v013.blend'
bpy.ops.wm.save_as_mainfile(filepath=save_path, check_existing=False)
print('saved', save_path, 'wall', len(wall.objects), 'stairs', len(stairs.objects))
