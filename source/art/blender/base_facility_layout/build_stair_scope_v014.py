import bpy
import math
from mathutils import Vector


MET = bpy.data.materials['01_精工金属_紫色骨架']
MAT = bpy.data.materials['02_细腻哑光_青绿大面']
GLS = bpy.data.materials['03_清漆反光_紫粉点缀']
EMI = bpy.data.materials['04_柔和自发光_UI灯光']

OUTPUT_PARENT = bpy.data.collections['02_游戏输出_独立资产包_v011']
SOURCE_PARENT = bpy.data.collections['01_制作组件_已统一材质']
OUTPUT_ROOT_NAME = '97_楼梯与梯下设施高还原迭代_v014'
SOURCE_ROOT_NAME = '97_楼梯与梯下设施高还原迭代_制作组件_v014'
QA_COLLECTION_NAME = '90_楼梯范围展示相机_v014'
CREATED_PACKAGES = []


def remove_collection_tree(name):
    root = bpy.data.collections.get(name)
    if root is None:
        return
    children = list(root.children_recursive)
    objects = set(root.all_objects)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in reversed(children):
        bpy.data.collections.remove(collection)
    bpy.data.collections.remove(root)


for collection_name in (OUTPUT_ROOT_NAME, SOURCE_ROOT_NAME, QA_COLLECTION_NAME):
    remove_collection_tree(collection_name)


def child(parent, name):
    collection = bpy.data.collections.new(name)
    parent.children.link(collection)
    return collection


OUTPUT_ROOT = child(OUTPUT_PARENT, OUTPUT_ROOT_NAME)
SOURCE_ROOT = child(SOURCE_PARENT, SOURCE_ROOT_NAME)
SOURCE_ROOT.hide_viewport = False
SOURCE_ROOT.hide_render = False
QA_COLLECTION = bpy.data.collections.new(QA_COLLECTION_NAME)
bpy.context.scene.collection.children.link(QA_COLLECTION)


def link_only(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)


def set_palette_uv(obj, column, row):
    if obj.type != 'MESH':
        return
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        if layer.name != 'PaletteUV':
            mesh.uv_layers.remove(layer)
    layer = mesh.uv_layers.get('PaletteUV') or mesh.uv_layers.new(name='PaletteUV')
    center_u = (column + 0.5) / 10.0
    center_v = 1.0 - (row + 0.5) / 10.0
    radius = 0.0275
    for polygon in mesh.polygons:
        loop_count = len(polygon.loop_indices)
        for index, loop_index in enumerate(polygon.loop_indices):
            angle = math.tau * index / max(3, loop_count)
            layer.data[loop_index].uv = (
                center_u + math.cos(angle) * radius,
                center_v + math.sin(angle) * radius,
            )
    mesh.uv_layers.active = layer
    for candidate in mesh.uv_layers:
        candidate.active_render = candidate == layer


def tag(obj, package_slug):
    obj['batch_scope'] = '楼梯及楼梯下方设施_v014'
    obj['asset_package'] = package_slug
    obj['reference_locked'] = True
    obj['scope_lock'] = '仅左主楼梯、右上楼梯、左楼梯下设施'


def finish_mesh(obj, collection, material, column, row, package_slug, bevel=0.0):
    link_only(obj, collection)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    if bevel:
        modifier = obj.modifiers.new('大倒角', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = 'ANGLE'
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    set_palette_uv(obj, column, row)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    tag(obj, package_slug)
    return obj


def box(name, location, dimensions, collection, package_slug,
        material=MET, column=0, row=9, bevel=0.025, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, collection, material, column, row, package_slug, bevel)


def cylinder(name, location, radius, depth, collection, package_slug,
             material=MET, column=0, row=9, rotation=(0.0, 0.0, 0.0), vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    return finish_mesh(obj, collection, material, column, row, package_slug, min(radius * 0.18, 0.018))


def sphere(name, location, radius, collection, package_slug,
           material=MAT, column=7, row=4):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    return finish_mesh(obj, collection, material, column, row, package_slug, 0.0)


def rod(name, start, end, radius, collection, package_slug,
        material=MET, column=0, row=9, vertices=10):
    start_v, end_v = Vector(start), Vector(end)
    direction = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=direction.length, location=midpoint
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_mode = 'XYZ'
    return finish_mesh(obj, collection, material, column, row, package_slug, min(radius * 0.14, 0.01))


def triangle(name, points, collection, package_slug, material=MAT, column=5, row=2):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], [(0, 1, 2)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return finish_mesh(obj, collection, material, column, row, package_slug)


def text_mesh(name, body, location, size, collection, package_slug,
              material=EMI, column=9, row=9, rotation=(math.pi / 2, 0.0, 0.0)):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = body
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.size = size
    curve.extrude = 0.008
    curve.bevel_depth = 0.003
    curve.bevel_resolution = 1
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object
    obj.name = name
    return finish_mesh(obj, collection, material, column, row, package_slug)


def area_light(name, location, color, energy, size, collection, package_slug,
               rotation=(-math.pi / 2, 0.0, 0.0)):
    data = bpy.data.lights.new(name, 'AREA')
    data.color = color
    data.energy = energy
    data.shape = 'RECTANGLE'
    data.size = size
    data.size_y = size * 0.28
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_euler = rotation
    collection.objects.link(obj)
    tag(obj, package_slug)
    return obj


def point_light(name, location, color, energy, radius, collection, package_slug):
    data = bpy.data.lights.new(name, 'POINT')
    data.color = color
    data.energy = energy
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    collection.objects.link(obj)
    tag(obj, package_slug)
    return obj


def collision_box(name, location, dimensions, collection, package_slug,
                  rotation=(0.0, 0.0, 0.0), collision_type='static_box'):
    obj = box(name, location, dimensions, collection, package_slug,
              MET, 0, 9, 0.0, rotation)
    obj.display_type = 'WIRE'
    obj.hide_render = True
    obj['collision_type'] = collision_type
    obj['gameplay_only'] = True
    return obj


def consolidate_materials(obj, allowed):
    old_materials = list(obj.data.materials)
    polygon_materials = []
    for polygon in obj.data.polygons:
        material = old_materials[polygon.material_index] if polygon.material_index < len(old_materials) else allowed[0]
        polygon_materials.append(material)
    obj.data.materials.clear()
    used = [material for material in allowed if material in polygon_materials]
    if not used:
        used = [allowed[0]]
    for material in used:
        obj.data.materials.append(material)
    material_index = {material.name: index for index, material in enumerate(used)}
    for polygon, material in zip(obj.data.polygons, polygon_materials):
        polygon.material_index = material_index.get(material.name, 0)
    layer = obj.data.uv_layers.get('PaletteUV')
    if layer:
        obj.data.uv_layers.active = layer
        for candidate in obj.data.uv_layers:
            candidate.active_render = candidate == layer


def join_copies(objects, output_collection, name, allowed, package_slug):
    copies = []
    for source in objects:
        duplicate = source.copy()
        duplicate.data = source.data.copy()
        duplicate.name = source.name.replace('_源组件', '') + '_输出组件'
        duplicate.hide_viewport = False
        duplicate.hide_render = False
        output_collection.objects.link(duplicate)
        copies.append(duplicate)
    if not copies:
        return None
    if len(copies) > 1:
        bpy.ops.object.select_all(action='DESELECT')
        for duplicate in copies:
            duplicate.select_set(True)
        bpy.context.view_layer.objects.active = copies[0]
        bpy.ops.object.join()
        result = bpy.context.object
    else:
        result = copies[0]
    result.name = name
    consolidate_materials(result, allowed)
    tag(result, package_slug)
    result['output_role'] = 'emission' if allowed == [EMI] else 'body'
    return result


def build_output(source_collection, output_collection, display_name, package_slug):
    meshes = [obj for obj in source_collection.objects if obj.type == 'MESH']
    body = [obj for obj in meshes if not obj.data.materials or obj.data.materials[0] != EMI]
    emission = [obj for obj in meshes if obj.data.materials and obj.data.materials[0] == EMI]
    outputs = []
    body_obj = join_copies(
        body, output_collection, f'{display_name}_主体_金属哑光反光', [MET, MAT, GLS], package_slug
    )
    if body_obj:
        outputs.append(body_obj)
    emission_obj = join_copies(
        emission, output_collection, f'{display_name}_UI灯光_柔和自发光', [EMI], package_slug
    )
    if emission_obj:
        outputs.append(emission_obj)
    for source in [obj for obj in source_collection.objects if obj.type == 'LIGHT']:
        duplicate = source.copy()
        duplicate.data = source.data.copy()
        duplicate.name = source.name.replace('_源组件', '')
        duplicate.hide_viewport = False
        duplicate.hide_render = False
        output_collection.objects.link(duplicate)
        tag(duplicate, package_slug)
        outputs.append(duplicate)
    source_collection.hide_viewport = True
    source_collection.hide_render = True
    output_collection.hide_viewport = False
    output_collection.hide_render = False
    output_collection['version'] = 'v014'
    output_collection['asset_slug'] = package_slug
    output_collection['visual_acceptance'] = '参考图比例、轮廓、摆位、材质、灯光与细节密度迭代'
    output_collection['scope_lock'] = '仅楼梯及左楼梯下方设施'
    CREATED_PACKAGES.append((package_slug, display_name, source_collection, output_collection, outputs))


def package(number, display_name, slug):
    source_collection = child(SOURCE_ROOT, f'{number}_{display_name}_制作组件_v014')
    output_collection = child(OUTPUT_ROOT, f'{number}_{display_name}_资产包_v014')
    return source_collection, output_collection, slug


# 97: Existing left L-stair, tertiary mechanical refinement only. Geometry envelope is unchanged.
src, out, slug = package('97', '西北L梯结构深化', 'northwest_l_stair_refinement')
for index, t in enumerate((0.08, 0.27, 0.46, 0.65, 0.84)):
    y = 8.24 + (12.80 - 8.24) * t
    z = 0.30 + (3.04 - 0.30) * t
    cylinder(f'西北L梯v014_下段外侧梁固定帽_{index + 1:02d}_源组件',
             (-12.865, y, z), 0.055, 0.045, src, slug, GLS, 9, 6,
             rotation=(0.0, math.pi / 2, 0.0))
for index, t in enumerate((0.08, 0.27, 0.46, 0.65, 0.84)):
    x = -12.80 + 4.56 * t
    z = 3.30 + 2.74 * t
    cylinder(f'西北L梯v014_上段外侧梁固定帽_{index + 1:02d}_源组件',
             (x, 12.865, z), 0.055, 0.045, src, slug, GLS, 9, 6,
             rotation=(math.pi / 2, 0.0, 0.0))
rod('西北L梯v014_转角平台外侧斜撑A_源组件', (-12.93, 12.96, 2.92), (-12.93, 13.62, 3.62),
    0.028, src, slug, MET, 0, 9)
rod('西北L梯v014_转角平台外侧斜撑B_源组件', (-12.93, 13.62, 3.62), (-12.93, 14.28, 2.92),
    0.028, src, slug, MET, 0, 9)
for x, y in ((-12.93, 12.95), (-12.93, 14.62), (-14.63, 12.95), (-14.63, 14.62)):
    box(f'西北L梯v014_平台栏杆脚座_{x:.2f}_{y:.2f}_源组件', (x, y, 3.14),
        (0.17, 0.17, 0.08), src, slug, MET, 0, 9, 0.018)
build_output(src, out, '西北L梯结构深化', slug)
collision = child(out, '03_西北L梯简化碰撞_v014')
left_lower_angle = math.atan2(2.74, 4.56)
left_upper_angle = math.atan2(2.75, 4.56)
collision_box('COLLISION_西北L梯_下段连续斜坡', (-13.80, 10.52, 1.67),
              (1.64, math.hypot(4.56, 2.74), 0.16), collision, slug,
              rotation=(left_lower_angle, 0.0, 0.0), collision_type='walkable_ramp')
collision_box('COLLISION_西北L梯_上段连续斜坡', (-10.52, 13.80, 4.72),
              (math.hypot(4.56, 2.75), 1.64, 0.16), collision, slug,
              rotation=(0.0, -left_upper_angle, 0.0), collision_type='walkable_ramp')
collision_box('COLLISION_西北L梯_转角平台', (-13.80, 13.80, 3.08),
              (1.90, 1.90, 0.16), collision, slug, collision_type='walkable_platform')
collision_box('COLLISION_西北L梯_顶层接驳平台', (-6.46, 13.80, 6.12),
              (3.44, 1.88, 0.16), collision, slug, collision_type='walkable_platform')
for side_x in (-14.63, -12.93):
    collision_box(f'COLLISION_西北L梯_下段栏杆_{side_x:.2f}', (side_x, 10.52, 2.18),
                  (0.08, math.hypot(4.56, 2.74), 0.92), collision, slug,
                  rotation=(left_lower_angle, 0.0, 0.0), collision_type='railing_blocker')
for side_y in (12.93, 14.63):
    collision_box(f'COLLISION_西北L梯_上段栏杆_{side_y:.2f}', (-10.52, side_y, 5.23),
                  (math.hypot(4.56, 2.75), 0.08, 0.92), collision, slug,
                  rotation=(0.0, -left_upper_angle, 0.0), collision_type='railing_blocker')
collision.hide_viewport = True
collision.hide_render = True


# 98: Existing upper-right stair, mounting hardware and connection readability only.
src, out, slug = package('98', '东侧上行楼梯结构深化', 'east_upper_stair_refinement')
for side_x in (12.315, 14.245):
    for index, t in enumerate((0.08, 0.28, 0.48, 0.68, 0.88)):
        y = 10.38 + 3.60 * t
        z = 6.30 + 2.43 * t
        cylinder(f'东侧楼梯v014_侧梁固定帽_{side_x:.3f}_{index + 1:02d}_源组件',
                 (side_x, y, z), 0.052, 0.044, src, slug, GLS, 9, 6,
                 rotation=(0.0, math.pi / 2, 0.0))
for side_x in (12.36, 14.20):
    box(f'东侧楼梯v014_底部接驳加强板_{side_x:.2f}_源组件', (side_x, 10.27, 6.17),
        (0.22, 0.18, 0.34), src, slug, MET, 0, 9, 0.028)
    box(f'东侧楼梯v014_顶部接驳加强板_{side_x:.2f}_源组件', (side_x, 14.05, 8.90),
        (0.22, 0.18, 0.34), src, slug, MET, 0, 9, 0.028)
build_output(src, out, '东侧上行楼梯结构深化', slug)
collision = child(out, '03_东侧上行楼梯简化碰撞_v014')
right_angle = math.atan2(2.73, 3.60)
collision_box('COLLISION_东侧上行楼梯_连续斜坡', (13.28, 12.18, 7.53),
              (1.78, math.hypot(3.60, 2.73), 0.16), collision, slug,
              rotation=(right_angle, 0.0, 0.0), collision_type='walkable_ramp')
for side_x in (12.36, 14.20):
    collision_box(f'COLLISION_东侧上行楼梯_栏杆_{side_x:.2f}', (side_x, 12.18, 8.04),
                  (0.08, math.hypot(3.60, 2.73), 0.92), collision, slug,
                  rotation=(right_angle, 0.0, 0.0), collision_type='railing_blocker')
collision.hide_viewport = True
collision.hide_render = True


# 99: Low green padded bench under the upper flight, matching the reference silhouette.
src, out, slug = package('99', '梯下绿色软垫长凳', 'understair_green_bench')
bench_x, bench_y = -11.15, 14.16
for x in (bench_x - 1.05, bench_x + 1.05):
    for y in (bench_y - 0.32, bench_y + 0.32):
        box(f'梯下长凳v014_圆角支腿_{x:.2f}_{y:.2f}_源组件', (x, y, 0.30),
            (0.14, 0.14, 0.54), src, slug, MET, 0, 9, 0.035)
for y in (bench_y - 0.32, bench_y + 0.32):
    box(f'梯下长凳v014_纵向承重梁_{y:.2f}_源组件', (bench_x, y, 0.46),
        (2.36, 0.12, 0.16), src, slug, MET, 0, 9, 0.025)
box('梯下长凳v014_座板壳体_源组件', (bench_x, bench_y, 0.62),
    (2.58, 0.86, 0.22), src, slug, MET, 0, 9, 0.065)
box('梯下长凳v014_墨绿厚软垫_源组件', (bench_x, bench_y - 0.015, 0.79),
    (2.32, 0.70, 0.18), src, slug, MAT, 7, 4, 0.085)
box('梯下长凳v014_靠背金属框_源组件', (bench_x, bench_y + 0.37, 1.22),
    (2.50, 0.14, 0.88), src, slug, MET, 0, 9, 0.045)
box('梯下长凳v014_墨绿靠垫_源组件', (bench_x, bench_y + 0.275, 1.23),
    (2.22, 0.20, 0.64), src, slug, MAT, 7, 4, 0.09)
for x in (bench_x - 0.38, bench_x + 0.38):
    box(f'梯下长凳v014_靠垫压线_{x:.2f}_源组件', (x, bench_y + 0.164, 1.23),
        (0.035, 0.018, 0.51), src, slug, GLS, 7, 4, 0.008)
for x in (bench_x - 1.04, bench_x + 1.04):
    cylinder(f'梯下长凳v014_侧面紧固件_{x:.2f}_源组件', (x, bench_y - 0.445, 0.62),
             0.055, 0.035, src, slug, GLS, 9, 6, rotation=(math.pi / 2, 0.0, 0.0))
build_output(src, out, '梯下绿色软垫长凳', slug)
collision = child(out, '03_梯下绿色软垫长凳简化碰撞_v014')
collision_box('COLLISION_梯下绿色软垫长凳', (bench_x, bench_y, 0.83),
              (2.58, 0.90, 1.66), collision, slug)
collision.hide_viewport = True
collision.hide_render = True


# 100: Framed bulletin board with layered paper notes and physical pins.
src, out, slug = package('100', '梯下公告留言板', 'understair_bulletin_board')
board_x, board_y, board_z = -10.92, 14.69, 2.25
box('梯下公告板v014_背板_源组件', (board_x, board_y, board_z),
    (1.90, 0.08, 1.42), src, slug, MET, 0, 9, 0.04)
box('梯下公告板v014_软木色内板_源组件', (board_x, board_y - 0.055, board_z),
    (1.65, 0.035, 1.17), src, slug, MAT, 4, 2, 0.018)
papers = (
    (-11.48, 2.48, 0.42, 0.50, 9, 8),
    (-10.95, 2.55, 0.39, 0.46, 8, 8),
    (-10.45, 2.42, 0.42, 0.55, 9, 9),
    (-11.38, 1.91, 0.48, 0.42, 8, 2),
    (-10.72, 1.91, 0.55, 0.40, 9, 7),
)
for index, (x, z, width, height, column, row) in enumerate(papers):
    box(f'梯下公告板v014_公告纸_{index + 1:02d}_源组件', (x, board_y - 0.082, z),
        (width, 0.014, height), src, slug, MAT, column, row, 0.012,
        rotation=(0.0, 0.0, math.radians((-4, 3, -2, 5, -3)[index])))
    cylinder(f'梯下公告板v014_图钉_{index + 1:02d}_源组件', (x, board_y - 0.098, z + height * 0.34),
             0.035, 0.018, src, slug, GLS, 5 if index % 2 == 0 else 3, 0,
             rotation=(math.pi / 2, 0.0, 0.0), vertices=10)
    for line in range(2):
        box(f'梯下公告板v014_纸面短线_{index + 1:02d}_{line + 1}_源组件',
            (x, board_y - 0.093, z + 0.03 - line * 0.11),
            (width * (0.52 + 0.13 * line), 0.006, 0.018), src, slug, GLS, 0, 9, 0.003)
build_output(src, out, '梯下公告留言板', slug)
out['collision_status'] = '贴墙薄件并入既有9m墙体阻挡'


# 101: Tall equipment cabinet at the high-clearance end of the stair.
src, out, slug = package('101', '梯下立式设备柜', 'understair_equipment_cabinet')
cab_x, cab_y = -6.82, 14.29
box('梯下设备柜v014_深灰柜体_源组件', (cab_x, cab_y, 1.58),
    (1.10, 0.78, 3.10), src, slug, MET, 0, 9, 0.075)
box('梯下设备柜v014_墨绿门板_源组件', (cab_x, cab_y - 0.418, 1.58),
    (0.91, 0.055, 2.82), src, slug, MAT, 1, 4, 0.035)
box('梯下设备柜v014_顶部压边_源组件', (cab_x, cab_y - 0.445, 2.98),
    (0.90, 0.055, 0.12), src, slug, GLS, 8, 5, 0.02)
box('梯下设备柜v014_控制屏黑框_源组件', (cab_x, cab_y - 0.462, 2.30),
    (0.64, 0.045, 0.52), src, slug, MET, 0, 9, 0.035)
box('梯下设备柜v014_控制屏青光_源组件', (cab_x, cab_y - 0.493, 2.30),
    (0.50, 0.018, 0.36), src, slug, EMI, 3, 0, 0.024)
for index, z in enumerate((1.05, 0.87, 0.69, 0.51)):
    box(f'梯下设备柜v014_下部散热栅_{index + 1:02d}_源组件', (cab_x, cab_y - 0.466, z),
        (0.59, 0.035, 0.065), src, slug, GLS, 9, 5, 0.012)
box('梯下设备柜v014_竖向门缝_源组件', (cab_x + 0.26, cab_y - 0.468, 1.52),
    (0.025, 0.026, 0.78), src, slug, GLS, 0, 9, 0.006)
triangle('梯下设备柜v014_警告三角底_源组件',
         [(cab_x - 0.20, cab_y - 0.505, 1.42), (cab_x, cab_y - 0.505, 1.82), (cab_x + 0.20, cab_y - 0.505, 1.42)],
         src, slug, MAT, 5, 2)
text_mesh('梯下设备柜v014_AUX小标识_源组件', 'AUX', (cab_x, cab_y - 0.526, 2.72), 0.13,
          src, slug, EMI, 9, 9, rotation=(math.pi / 2, 0.0, 0.0))
for x in (cab_x - 0.38, cab_x + 0.38):
    box(f'梯下设备柜v014_短柜脚_{x:.2f}_源组件', (x, cab_y, 0.10),
        (0.16, 0.52, 0.20), src, slug, MET, 0, 9, 0.035)
build_output(src, out, '梯下立式设备柜', slug)
collision = child(out, '03_梯下立式设备柜简化碰撞_v014')
collision_box('COLLISION_梯下立式设备柜', (cab_x, cab_y, 1.565),
              (1.10, 0.78, 3.13), collision, slug)
collision.hide_viewport = True
collision.hide_render = True


# 102: Compact shelf and restrained storage boxes under the upper flight.
src, out, slug = package('102', '梯下层架与收纳', 'understair_shelf_storage')
shelf_x, shelf_y = -8.58, 14.24
for x in (shelf_x - 0.55, shelf_x + 0.55):
    for y in (shelf_y - 0.31, shelf_y + 0.31):
        box(f'梯下层架v014_立柱_{x:.2f}_{y:.2f}_源组件', (x, y, 1.30),
            (0.085, 0.085, 2.55), src, slug, MET, 0, 9, 0.018)
for index, z in enumerate((0.18, 0.82, 1.46, 2.10)):
    box(f'梯下层架v014_层板_{index + 1:02d}_源组件', (shelf_x, shelf_y, z),
        (1.24, 0.72, 0.11), src, slug, MET, 0, 9, 0.025)
storage = (
    (-8.84, 13.99, 0.48, 0.45, 0.48, 0.42, 1, 4),
    (-8.35, 14.00, 0.49, 0.40, 0.46, 0.44, 5, 2),
    (-8.58, 14.03, 1.12, 0.77, 0.44, 0.43, 8, 5),
    (-8.76, 14.03, 1.79, 0.42, 0.44, 0.48, 3, 0),
    (-8.28, 14.03, 1.78, 0.38, 0.42, 0.44, 1, 4),
)
for index, (x, y, z, width, depth, height, column, row) in enumerate(storage):
    box(f'梯下层架v014_收纳盒_{index + 1:02d}_源组件', (x, y, z),
        (width, depth, height), src, slug, MAT, column, row, 0.045)
    box(f'梯下层架v014_收纳盒标签_{index + 1:02d}_源组件', (x, y - depth * 0.51, z),
        (width * 0.48, 0.018, 0.11), src, slug, GLS, 9, 8, 0.012)
build_output(src, out, '梯下层架与收纳', slug)
collision = child(out, '03_梯下层架与收纳简化碰撞_v014')
collision_box('COLLISION_梯下层架与收纳', (shelf_x, shelf_y, 1.30),
              (1.24, 0.86, 2.60), collision, slug)
collision.hide_viewport = True
collision.hide_render = True


# 103: Warm wall light, small plant and one compact side box for the lived-in corner.
src, out, slug = package('103', '梯下暖光与生活点缀', 'understair_lighting_decor')
box('梯下暖灯v014_墙面固定底座_源组件', (-7.72, 14.70, 3.52),
    (0.94, 0.10, 0.34), src, slug, MET, 0, 9, 0.055)
box('梯下暖灯v014_暖白灯罩_源组件', (-7.72, 14.625, 3.52),
    (0.72, 0.09, 0.16), src, slug, EMI, 5, 2, 0.055)
for x in (-8.05, -7.39):
    cylinder(f'梯下暖灯v014_固定螺丝_{x:.2f}_源组件', (x, 14.60, 3.52),
             0.032, 0.018, src, slug, GLS, 9, 8, rotation=(math.pi / 2, 0.0, 0.0), vertices=10)
area_light('梯下暖灯v014_局部暖光_源组件', (-7.72, 14.22, 3.42),
           (1.0, 0.43, 0.14), 260, 1.90, src, slug)
point_light('梯下暖灯v014_休息角柔光补偿_源组件', (-10.35, 13.72, 2.48),
            (1.0, 0.50, 0.20), 72, 0.85, src, slug)
box('梯下生活角v014_窄边柜体_源组件', (-9.65, 14.16, 0.40),
    (0.54, 0.63, 0.76), src, slug, MET, 0, 9, 0.055)
box('梯下生活角v014_窄边柜门_源组件', (-9.65, 13.83, 0.42),
    (0.43, 0.035, 0.58), src, slug, MAT, 5, 2, 0.025)
box('梯下生活角v014_边柜抽屉缝_源组件', (-9.65, 13.805, 0.51),
    (0.34, 0.012, 0.025), src, slug, GLS, 0, 9, 0.005)
cylinder('梯下生活角v014_花盆_源组件', (-8.58, 14.20, 2.35),
         0.19, 0.32, src, slug, MAT, 5, 2, vertices=12)
for index, (dx, dy, dz, radius) in enumerate((
    (-0.16, 0.00, 0.22, 0.18), (0.14, 0.02, 0.25, 0.19),
    (-0.04, -0.10, 0.35, 0.20), (0.03, 0.10, 0.45, 0.16),
)):
    rod(f'梯下生活角v014_植物茎_{index + 1:02d}_源组件',
        (-8.58, 14.20, 2.49), (-8.58 + dx * 0.72, 14.20 + dy * 0.72, 2.62 + dz * 0.72),
        0.018, src, slug, MAT, 7, 4, vertices=8)
    sphere(f'梯下生活角v014_植物叶团_{index + 1:02d}_源组件',
           (-8.58 + dx, 14.20 + dy, 2.58 + dz), radius, src, slug, MAT, 7, 4)
box('梯下生活角v014_边柜文件夹_源组件', (-9.66, 14.14, 0.88),
    (0.34, 0.23, 0.07), src, slug, MAT, 8, 8, 0.012,
    rotation=(0.0, 0.0, math.radians(-6)))
build_output(src, out, '梯下暖光与生活点缀', slug)
collision = child(out, '03_梯下生活角边柜简化碰撞_v014')
collision_box('COLLISION_梯下生活角窄边柜', (-9.65, 14.16, 0.44),
              (0.54, 0.63, 0.88), collision, slug)
collision.hide_viewport = True
collision.hide_render = True
out['collision_status'] = '窄边柜独立碰撞；壁灯与植物不阻挡角色'


# A close-up acceptance camera is display-only and does not enter any game package.
camera_data = bpy.data.cameras.new('楼梯下设施_高还原验收相机_v014')
camera_data.lens = 54
camera = bpy.data.objects.new('楼梯下设施_高还原验收相机_v014', camera_data)
camera.location = (-18.2, 1.7, 8.2)
target = Vector((-9.75, 14.05, 1.95))
camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
QA_COLLECTION.objects.link(camera)


OUTPUT_ROOT['version'] = 'v014'
OUTPUT_ROOT['reference_image'] = 'codex-clipboard-d6fe7251-fdf2-4d9b-b366-4c8cb0c189a3.png'
OUTPUT_ROOT['scope_lock'] = '左侧主楼梯、右上新增楼梯、左侧主楼梯下方设施；其他区域未修改'
SOURCE_ROOT['version'] = 'v014'
SOURCE_ROOT['editable_source'] = True
SOURCE_ROOT.hide_viewport = True
SOURCE_ROOT.hide_render = True
bpy.context.scene['visual_qa_v014'] = (
    '参考图逐项验收：双楼梯接口锁定；梯下长凳、公告板、设备柜、层架收纳、植物与暖光补齐'
)
bpy.context.scene['scope_lock_v014'] = '禁止修改一楼主体、一楼墙壁、无关家具与整体布局'
bpy.context.scene['stair_interfaces_v014'] = {
    'left_bounds': '[-14.8,8.21,0.0]..[-4.67,14.8,7.128]',
    'right_bounds': '[12.305,10.17,5.996]..[14.255,14.92,9.34]',
    'left_platform_z': 3.04,
    'left_top_z': 6.05,
    'right_bottom_z': 6.05,
    'right_top_z': 8.90,
}

save_path = r'I:\工作项目\shellstrom2\ShellStorm2\source\art\blender\base_facility_layout\base_facility_runtime_layout_hq_v014.blend'
bpy.ops.wm.save_as_mainfile(filepath=save_path, check_existing=False)
print('SAVED', save_path)
for slug, display_name, source_collection, output_collection, outputs in CREATED_PACKAGES:
    print('PACKAGE', slug, display_name, 'source', len(source_collection.objects),
          'output', len(outputs), [obj.name for obj in outputs])
