"""吸附与对齐计算：全部基于世界坐标包围盒，锚点按底面中心参与对齐。"""

from mathutils import Matrix, Vector

SIDE_ITEMS = (
    ("X_PLUS", "+X 右侧", "活动对象的 +X 面贴齐"),
    ("X_MINUS", "-X 左侧", "活动对象的 -X 面贴齐"),
    ("Y_PLUS", "+Y 后侧", "活动对象的 +Y 面贴齐"),
    ("Y_MINUS", "-Y 前侧", "活动对象的 -Y 面贴齐"),
    ("Z_PLUS", "上方堆叠", "活动对象的顶面贴齐"),
)

AXES_ITEMS = (
    ("X", "X 轴", "底面中心 X 对齐"),
    ("Y", "Y 轴", "底面中心 Y 对齐"),
    ("Z", "Z 轴", "底面标高对齐"),
    ("XY", "X+Y", "平面位置对齐"),
    ("XYZ", "X+Y+Z", "底面中心完全对齐"),
)


def unit_members(obj):
    """吸附单位：Append 的资产包整体，或组件对象连同其子级。"""
    for collection in obj.users_collection:
        if collection.get("shellstorm_library_asset"):
            return list(collection.all_objects)
    return [obj, *obj.children_recursive]


def unit_roots(obj):
    """位移时要移动的对象；子级跟随父级，不重复位移。"""
    for collection in obj.users_collection:
        if collection.get("shellstorm_library_asset"):
            return [member for member in collection.all_objects if member.parent is None]
    return [obj]


def world_bounds(objects):
    """返回 (最小点, 最大点)，没有网格时返回 None。"""
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        matrix = obj.matrix_world
        points.extend(matrix @ Vector(corner) for corner in obj.bound_box)
    if not points:
        return None
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def unit_bounds(obj):
    return world_bounds(unit_members(obj))


def translate_world(obj, delta):
    obj.matrix_world = Matrix.Translation(delta) @ obj.matrix_world


def snap_value(value, step):
    if step <= 0:
        return value
    return round(round(value / step) * step, 6)


def grid_delta(bounds, grid, height_step):
    """把底面中心吸附到平面网格、底面标高吸附到高度步进。"""
    low, high = bounds
    center = (low + high) / 2.0
    target_x = snap_value(center.x, grid)
    target_y = snap_value(center.y, grid)
    target_z = snap_value(low.z, height_step)
    return Vector((target_x - center.x, target_y - center.y, target_z - low.z))


def flush_delta(side, target, moving):
    """把 moving 的包围盒贴合到 target 的指定侧面，另一个水平轴居中、底面齐平。"""
    target_low, target_high = target
    low, high = moving
    center = (low + high) / 2.0
    target_center = (target_low + target_high) / 2.0
    delta = Vector((0.0, 0.0, 0.0))
    if side == "X_PLUS":
        delta.x = target_high.x - low.x
        delta.y = target_center.y - center.y
    elif side == "X_MINUS":
        delta.x = target_low.x - high.x
        delta.y = target_center.y - center.y
    elif side == "Y_PLUS":
        delta.y = target_high.y - low.y
        delta.x = target_center.x - center.x
    elif side == "Y_MINUS":
        delta.y = target_low.y - high.y
        delta.x = target_center.x - center.x
    else:
        delta.z = target_high.z - low.z
        delta.x = target_center.x - center.x
        delta.y = target_center.y - center.y
    if side != "Z_PLUS":
        delta.z = target_low.z - low.z
    return delta


def align_delta(axes, target, moving):
    target_low, target_high = target
    low, high = moving
    center = (low + high) / 2.0
    target_center = (target_low + target_high) / 2.0
    delta = Vector((0.0, 0.0, 0.0))
    if "X" in axes:
        delta.x = target_center.x - center.x
    if "Y" in axes:
        delta.y = target_center.y - center.y
    if "Z" in axes:
        delta.z = target_low.z - low.z
    return delta
