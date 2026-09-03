import bpy
import math

MET = bpy.data.materials['01_精工金属_紫色骨架']
MAT = bpy.data.materials['02_细腻哑光_青绿大面']
GLS = bpy.data.materials['03_清漆反光_紫粉点缀']
EMI = bpy.data.materials['04_柔和自发光_UI灯光']
WALL = bpy.data.collections['95_二楼后墙参考图可读性深化_资产包_v013']
SOURCE = bpy.data.collections['95_二楼后墙参考图可读性深化_制作组件_v013']
CREATED = []


def link_only(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    WALL.objects.link(obj)


def uv(obj, column, row):
    mesh = obj.data
    layer = mesh.uv_layers.get('PaletteUV') or mesh.uv_layers.new(name='PaletteUV')
    u0, u1 = (column + .22) / 10, (column + .78) / 10
    v0, v1 = 1 - (row + .78) / 10, 1 - (row + .22) / 10
    values = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
    for polygon in mesh.polygons:
        for index, loop_index in enumerate(polygon.loop_indices):
            layer.data[loop_index].uv = values[index % 4]
    layer.active = True
    for candidate in mesh.uv_layers:
        candidate.active_render = candidate == layer


def finish(obj, material, column, row, bevel=.0):
    link_only(obj)
    obj.data.materials.append(material)
    uv(obj, column, row)
    if bevel:
        modifier = obj.modifiers.new('圆角', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    obj['batch_scope'] = '视觉高还原验收迭代_v013b'
    CREATED.append(obj)
    return obj


def box(name, location, dimensions, material=MET, column=0, row=9, bevel=.02):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, material, column, row, bevel)


def cylinder(name, location, radius, depth, material=MET, column=0, row=9):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12, radius=radius, depth=depth, location=location, rotation=(math.pi / 2, 0, 0)
    )
    obj = bpy.context.object
    obj.name = name
    return finish(obj, material, column, row, .01)


def light(name, location, color, energy, size):
    data = bpy.data.lights.new(name, 'AREA')
    data.color = color
    data.energy = energy
    data.shape = 'RECTANGLE'
    data.size = size
    data.size_y = size * .25
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_euler = (math.pi / 2, 0, 0)
    link_only(obj)
    obj['batch_scope'] = '视觉高还原验收迭代_v013b'
    CREATED.append(obj)


def triangle(name, points, material, column, row):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], [(0, 1, 2)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, material, column, row)


# Two narrow framed prints at the work-corner end of the rear wall, matching the reference's paired warm poster rhythm.
for index, x in enumerate((6.72, 7.72)):
    box(f'二楼后墙v013b_工位竖海报黑框_{index + 1}', (x, 14.34, 8.47), (.70, .055, 1.22), MET, 0, 9, .02)
    box(f'二楼后墙v013b_工位竖海报暖色纸面_{index + 1}', (x, 14.303, 8.47), (.56, .012, 1.04), GLS, 4 + index, 1, .006)
    box(f'二楼后墙v013b_海报上部浅色块_{index + 1}', (x, 14.292, 8.72), (.40, .008, .28), MAT, 9, 9, .004)
    triangle(
        f'二楼后墙v013b_海报山形图案_{index + 1}',
        [(x - .20, 14.285, 8.02), (x, 14.285, 8.43), (x + .20, 14.285, 8.02)],
        MAT if index == 0 else GLS, 3 if index == 0 else 2, 0 if index == 0 else 7
    )
    for dx in (-.27, .27):
        for dz in (-.51, .51):
            cylinder(f'二楼后墙v013b_海报铆钉_{index + 1}_{dx:+.2f}_{dz:+.2f}', (x + dx, 14.275, 8.47 + dz), .022, .018, GLS, 9, 9)

# Compact red junction box and a separate physical cable drop on the left section of the rear wall.
box('二楼后墙v013b_红色接线盒底座', (-10.90, 14.34, 7.35), (.60, .075, .68), MET, 0, 9, .025)
box('二楼后墙v013b_红色接线盒面板', (-10.90, 14.295, 7.35), (.43, .022, .46), GLS, 5, 0, .018)
box('二楼后墙v013b_接线盒状态灯_自发光', (-10.90, 14.278, 7.42), (.10, .012, .10), EMI, 4, 0, .012)
for dx in (-.20, .20):
    for dz in (-.21, .21):
        cylinder(f'二楼后墙v013b_接线盒螺丝_{dx:+.2f}_{dz:+.2f}', (-10.90 + dx, 14.27, 7.35 + dz), .025, .018, GLS, 9, 9)
box('二楼后墙v013b_接线盒垂直线管', (-10.90, 14.35, 8.04), (.075, .052, .76), MET, 0, 9, .012)
box('二楼后墙v013b_接线盒彩色短线束', (-10.84, 14.305, 7.85), (.022, .015, .46), MAT, 1, 0, .004)
light('二楼后墙v013b_暖色工作灯', (-10.90, 13.93, 7.55), (1.0, .43, .13), 36, .75)

for obj in CREATED:
    copy = obj.copy()
    if obj.data:
        copy.data = obj.data.copy()
    copy.name = obj.name + '__源'
    copy.hide_viewport = True
    copy.hide_render = True
    copy['source_for'] = obj.name
    SOURCE.objects.link(copy)
SOURCE.hide_viewport = True
bpy.context.scene['visual_qa_v013b'] = '补足参考图中的双竖海报、红色接线盒和暖色工作灯'
bpy.ops.wm.save_as_mainfile(
    filepath=r'I:\工作项目\shellstrom2\ShellStorm2\source\art\blender\base_facility_layout\base_facility_runtime_layout_hq_v013.blend',
    check_existing=False,
)
print('added', len(CREATED), 'reference anchors')
