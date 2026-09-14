"""白盒组件几何：单网格生成，物体原点落在配置的锚点上。

实测游戏资产锚点（Blender 导入 GLB 后）：
- `env_tower_wall_solid_5m_top3d_v003.glb` 包围盒 X/Y 居中、Z 从 0 到 11.9，即底面中心原点。
- `env_tower_floor_tile_5m_top3d_v002.glb` 包围盒 Z 为 -0.15..0.15，即厚度居中原点，运行时再偏移 -0.15。
因此默认使用底面中心，需要与地砖运行时资产完全对齐时可切换到厚度居中。
"""

import bpy
from mathutils import Matrix, Vector

BOTTOM_CENTER = "BOTTOM_CENTER"
CENTER_Z = "CENTER_Z"

_BOX_FACES = ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7))
_BOX_CORNERS = (
    (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
)

_FALLBACKS = {
    "width": 1.0,
    "depth": 1.0,
    "height": 1.0,
    "thickness": 0.1,
    "opening_width": 1.0,
    "opening_height": 2.1,
    "step_count": 10,
    "step_height": 0.3,
    "tread_depth": 0.75,
    "railing_height": 1.1,
}


def dimension(props, name):
    """组件参数读取，允许传入只带部分字段的对象。"""
    return getattr(props, name, _FALLBACKS[name])


def component_boxes(component_type, props):
    """返回组件全部 (尺寸, 中心) 盒体，自然空间为底面贴 z=0、X/Y 居中。"""
    width = dimension(props, "width")
    depth = dimension(props, "depth")
    height = dimension(props, "height")
    if component_type == "FLOOR":
        thickness = dimension(props, "thickness")
        return [((width, depth, thickness), (0.0, 0.0, thickness / 2.0))]
    if component_type == "DOOR_OPENING":
        opening_width = dimension(props, "opening_width")
        opening_height = dimension(props, "opening_height")
        side = max(0.05, (width - opening_width) / 2.0)
        lintel = max(0.05, height - opening_height)
        return [
            ((side, depth, height), (-(opening_width + side) / 2.0, 0.0, height / 2.0)),
            ((side, depth, height), ((opening_width + side) / 2.0, 0.0, height / 2.0)),
            ((opening_width, depth, lintel), (0.0, 0.0, opening_height + lintel / 2.0)),
        ]
    if component_type == "STAIR":
        step_height = dimension(props, "step_height")
        tread_depth = dimension(props, "tread_depth")
        boxes = []
        for index in range(int(dimension(props, "step_count"))):
            riser = step_height * (index + 1)
            center_y = -(index + 0.5) * tread_depth
            boxes.append(((width, tread_depth, riser), (0.0, center_y, riser / 2.0)))
        return boxes
    if component_type == "RAILING":
        railing_height = dimension(props, "railing_height")
        thickness = min(dimension(props, "thickness"), railing_height)
        post_height = max(0.01, railing_height - thickness)
        post = max(0.01, depth)
        boxes = [((width, post, thickness), (0.0, 0.0, railing_height - thickness / 2.0))]
        for center_x in (post / 2.0 - width / 2.0, width / 2.0 - post / 2.0):
            boxes.append(((post, post, post_height), (center_x, 0.0, post_height / 2.0)))
        return boxes
    return [((width, depth, height), (0.0, 0.0, height / 2.0))]


def anchor_shift(points, anchor):
    """返回把 points 移到锚点位置所需的位移。"""
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    zs = [point[2] for point in points]
    offset = Vector((-(min(xs) + max(xs)) / 2.0, -(min(ys) + max(ys)) / 2.0, 0.0))
    offset.z = -(min(zs) + max(zs)) / 2.0 if anchor == CENTER_Z else -min(zs)
    return offset


def build_mesh(name, component_type, props, anchor=BOTTOM_CENTER):
    """按组件参数生成单个网格数据块，顶点已按锚点归零。"""
    vertices = []
    faces = []
    for size, center in component_boxes(component_type, props):
        base = len(vertices)
        half = [value / 2.0 for value in size]
        for corner in _BOX_CORNERS:
            vertices.append(
                (
                    center[0] + corner[0] * half[0],
                    center[1] + corner[1] * half[1],
                    center[2] + corner[2] * half[2],
                )
            )
        faces.extend(tuple(base + index for index in face) for face in _BOX_FACES)
    shift = anchor_shift(vertices, anchor)
    if shift.length_squared:
        vertices = [(point[0] + shift.x, point[1] + shift.y, point[2] + shift.z) for point in vertices]
    mesh = bpy.data.meshes.new(f"{name}_网格")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    return mesh


def reanchor_object(obj, anchor=BOTTOM_CENTER):
    """只移动网格数据，使锚点回到物体原点，世界坐标保持不变。"""
    if obj.type != "MESH" or not obj.data or not obj.data.vertices:
        return False
    points = [tuple(vertex.co) for vertex in obj.data.vertices]
    shift = anchor_shift(points, anchor)
    if shift.length_squared < 1e-12:
        return False
    matrix = obj.matrix_world.copy()
    obj.data.transform(Matrix.Translation(shift))
    obj.data.update()
    obj.matrix_world = Matrix.Translation(-(matrix.to_3x3() @ shift)) @ matrix
    return True
