import json
import math
import os


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_SCRIPT = os.path.join(SCRIPT_DIR, "build_japanese_bedroom.py")

# Load the previously validated art construction library without running a stage.
JBR_STAGE = ""
_wrapper_file = __file__
__file__ = BASE_SCRIPT
exec(compile(open(BASE_SCRIPT, "r", encoding="utf-8").read(), BASE_SCRIPT, "exec"), globals())
__file__ = _wrapper_file

LAYOUT_PATH = os.path.join(SCRIPT_DIR, "scene.json")
BLEND_PATH = os.path.join(SCRIPT_DIR, "日式卧室_新布局_微缩场景.blend")
PREVIEW_PATH = os.path.join(SCRIPT_DIR, "日式卧室_新布局_预览.png")
PALETTE_PATH = os.path.join(SCRIPT_DIR, "日式卧室_新布局_色盘_10x10_512.png")
REPORT_PATH = os.path.join(SCRIPT_DIR, "日式卧室_新布局_布局校验.json")

_base_box = box
_base_cyl = cyl
_base_sphere = sphere
_base_torus = torus
_base_curve_tube = curve_tube
_base_text_obj = text_obj

MIRROR_GLOBALS = False
ADJUST_PROP_ANCHORS = False


def _prop_delta(name, loc):
    if not ADJUST_PROP_ANCHORS:
        return 0.0, 0.0
    x, y, z = loc
    # Cabinet 1: old mirrored anchor (-4.335, -2.0) -> new (-4.35, -1.4).
    if x < -3.5 and 0.75 < y < 3.0 and z > 3.0:
        return -0.015, 0.60
    # Cabinet 2: old mirrored anchor (-4.5, 1.0) -> new (-4.35, 1.5).
    if x < -3.5 and -1.6 < y < 0.2 and z > 0.75:
        return 0.15, 0.50
    # Desk 1: old mirrored anchor (-4.0, 5.0) -> new (-4.25, 4.0).
    if x < -3.25 and y < -3.75 and z < 3.6:
        return -0.25, -1.00
    # Tea table 2: old mirrored anchor (5.0, -2.5) -> new (5.0, -3.15).
    if x > 4.0 and 1.75 < y < 3.1 and z > 0.75:
        return 0.0, -0.65
    return 0.0, 0.0


def _map_location(name, loc, parent=None):
    if parent is not None or not MIRROR_GLOBALS:
        return loc
    x, y, z = loc
    dx, dy = _prop_delta(name, loc)
    return x + dx, -y + dy, z


def _map_rotation(rot, parent=None):
    if parent is not None or not MIRROR_GLOBALS:
        return rot
    return -rot[0], rot[1], -rot[2]


def box(name, loc, dims, cell, role="MATTE", coll=None, rot=(0, 0, 0), bevel=0.035, parent=None):
    return _base_box(name, _map_location(name, loc, parent), dims, cell, role, coll,
                     _map_rotation(rot, parent), bevel, parent)


def cyl(name, loc, radius, depth, cell, role="MATTE", coll=None, rot=(0, 0, 0), vertices=24, parent=None):
    return _base_cyl(name, _map_location(name, loc, parent), radius, depth, cell, role, coll,
                     _map_rotation(rot, parent), vertices, parent)


def sphere(name, loc, scale, cell, role="MATTE", coll=None, parent=None):
    return _base_sphere(name, _map_location(name, loc, parent), scale, cell, role, coll, parent)


def torus(name, loc, major, minor, cell, role="MATTE", coll=None, rot=(0, 0, 0), parent=None):
    return _base_torus(name, _map_location(name, loc, parent), major, minor, cell, role, coll,
                       _map_rotation(rot, parent), parent)


def curve_tube(name, points, radius, cell, role="MATTE", coll=None, cyclic=False):
    mapped = [_map_location(name, point) for point in points]
    return _base_curve_tube(name, mapped, radius, cell, role, coll, cyclic)


def text_obj(name, body, loc, size, cell, coll, extrude=0.008, align='CENTER'):
    return _base_text_obj(name, body, _map_location(name, loc), size, cell, coll, extrude, align)


def create_root(record, coll):
    root = bpy.data.objects.new(record["name"], None)
    coll.objects.link(root)
    p = record["position"]
    r = record["rotation"]
    s = record["scale"]
    root.location = (p["x"], p["y"], p["z"])
    root.rotation_euler = tuple(math.radians(r[axis]) for axis in ("x", "y", "z"))
    root.scale = (s["x"], s["y"], s["z"])
    root.empty_display_type = 'CUBE'
    root.empty_display_size = 0.18
    root.lock_location = (True, True, True)
    root.lock_rotation = (True, True, True)
    root.lock_scale = (True, True, True)
    root["fixed_component"] = True
    root["layout_type"] = record["type"]
    root["coordinate_system"] = "blender-z-up"
    root["source_position_xyz"] = json.dumps(p, ensure_ascii=False)
    root["source_rotation_xyz"] = json.dumps(r, ensure_ascii=False)
    root["source_scale_xyz"] = json.dumps(s, ensure_ascii=False)
    return root


def expected_dimensions(record):
    kind = record["type"]
    sx, sy, sz = (record["scale"][axis] for axis in ("x", "y", "z"))
    if kind == "墙壁":
        settings = record["surfaceSettings"]
        local = Vector((settings["width"] * sx, settings["thickness"] * sy, settings["height"] * sz))
    elif kind == "地板":
        settings = record["surfaceSettings"]
        local = Vector((settings["length"] * sx, settings["width"] * sy, settings["thickness"] * sz))
    elif kind == "柜子":
        local = Vector((1.4 * sx, 0.55 * sy, 1.65 * sz))
    elif kind == "床":
        local = Vector((2.25 * sx, 1.35 * sy, 1.06 * sz))
    elif kind == "椅子":
        settings = record["chairSettings"]
        local = Vector((settings["seatWidth"] * sx, settings["seatDepth"] * sy,
                        (settings["legHeight"] + 0.13 + settings["backHeight"]) * sz))
    else:
        settings = record["tableSettings"]
        local = Vector((settings["width"] * sx, settings["depth"] * sy,
                        (settings["legHeight"] + settings["topThickness"]) * sz))
    angle = math.radians(record["rotation"]["z"])
    cosine, sine = abs(math.cos(angle)), abs(math.sin(angle))
    return Vector((cosine * local.x + sine * local.y,
                   sine * local.x + cosine * local.y,
                   local.z))


def _mirror_fcurve(fcurve):
    if fcurve.data_path == "location" and fcurve.array_index == 1:
        for point in fcurve.keyframe_points:
            point.co[1] *= -1
            point.handle_left[1] *= -1
            point.handle_right[1] *= -1
    elif fcurve.data_path == "rotation_euler" and fcurve.array_index in (0, 2):
        for point in fcurve.keyframe_points:
            point.co[1] *= -1
            point.handle_left[1] *= -1
            point.handle_right[1] *= -1


def _mirror_curve_data(curve):
    for spline in curve.splines:
        for point in spline.bezier_points:
            point.co.y *= -1
            point.handle_left.y *= -1
            point.handle_right.y *= -1
        for point in spline.points:
            point.co.y *= -1


def mirror_animation_collections():
    collections = (bpy.data.collections["03_动态元素"], bpy.data.collections["90_展示环境_灯光相机"])
    seen_curves = set()
    for coll in collections:
        for obj in coll.objects:
            if obj.type == 'CURVE' and obj.data.as_pointer() not in seen_curves:
                _mirror_curve_data(obj.data)
                seen_curves.add(obj.data.as_pointer())
            if obj.parent is None or obj.parent.name not in coll.objects:
                obj.location.y *= -1
                obj.rotation_euler.x *= -1
                obj.rotation_euler.z *= -1
            if obj.animation_data and obj.animation_data.action:
                for fcurve in obj.animation_data.action.fcurves:
                    _mirror_fcurve(fcurve)
    bpy.context.scene.frame_set(bpy.context.scene.frame_current)


def run_stage(stage):
    global MIRROR_GLOBALS, ADJUST_PROP_ANCHORS
    if stage == "fixed":
        MIRROR_GLOBALS = False
        ADJUST_PROP_ANCHORS = False
        stage_fixed()
        bpy.context.scene["coordinate_system"] = "blender-z-up"
        bpy.context.scene["layout_version"] = 3
    elif stage == "environment":
        MIRROR_GLOBALS = True
        ADJUST_PROP_ANCHORS = False
        stage_environment()
    elif stage == "props":
        MIRROR_GLOBALS = True
        ADJUST_PROP_ANCHORS = True
        stage_props()
    elif stage == "animation":
        MIRROR_GLOBALS = False
        ADJUST_PROP_ANCHORS = False
        stage_animation()
        mirror_animation_collections()
    elif stage == "validate_render":
        MIRROR_GLOBALS = False
        ADJUST_PROP_ANCHORS = False
        stage_validate_save_render()


V3_STAGE = globals().get("JBR_V3_STAGE", "")
if V3_STAGE:
    run_stage(V3_STAGE)
