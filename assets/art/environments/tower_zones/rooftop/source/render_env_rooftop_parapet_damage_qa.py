"""Visual acceptance render for the parapet damage variants.

Runs in the SAME Blender session right after author_env_rooftop_parapet_damage_v001.py,
so it renders the very objects that were just exported:

    blender --background <blend> --python-exit-code 1 \
        --python author_env_rooftop_parapet_damage_v001.py \
        --python render_env_rooftop_parapet_damage_qa.py

Two traps this script exists to avoid, both hit while building it:

* Re-importing the exported GLB does not work: the file repeats the library's scene
  layout (scene 0 "天台_参考拼装展示" carries no nodes) and Blender's glTF importer
  trips over that empty scene. The intact module fails the same way, so it is an
  importer quirk, not a defect in the export.
* The library objects are invisible to a render — their collections carry
  hide_render, and clearing the flag on the object does not override it. The intact
  module therefore silently dropped out of the frame while the projection still
  measured a full-width run. Hence the intact module is spawned as a scene-level copy,
  and every frame is checked afterwards by measuring the rendered pixels rather than
  by trusting the camera maths.

Output: ../../qa/parapet_damage_variants_row.png      three damage kinds side by side
        ../../qa/parapet_damage_variants_butted.png   intact + three kinds, at 5.0m pitch
        ../../qa/parapet_damage_variants_joint.png    intact -> crown-spall joint close-up
"""

from pathlib import Path
import math

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

QA_DIR = Path(__file__).resolve().parent.parent / "qa"
DAMAGE_A = "女儿墙直段破损A_主体"
DAMAGE_B = "女儿墙直段破损B_主体"
DAMAGE_C = "女儿墙直段破损C_主体"
VARIANTS = [DAMAGE_A, DAMAGE_B, DAMAGE_C]
INTACT_SOURCE = "女儿墙直段_水泥结构_制作"
INTACT_QA = "女儿墙直段完好_QA"
MODULE_LENGTH = 5.0
RESOLUTION_X = 1500
RESOLUTION_Y = 620


def _spawn_intact_copy():
    """Scene-level copy of the intact module — the library one never renders."""
    source = bpy.data.objects[INTACT_SOURCE]
    copy = source.copy()
    copy.data = source.data.copy()
    copy.name = INTACT_QA
    bpy.context.scene.collection.objects.link(copy)
    copy.hide_render = False
    copy.hide_viewport = False
    return copy


def _keep_only(names):
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.hide_render = obj.name not in names
        elif obj.type in {"CAMERA", "LIGHT"}:
            obj.hide_render = True
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise RuntimeError("render QA 找不到对象：%s" % name)
        obj.hide_viewport = False


def _layout(names, spacing):
    for index, name in enumerate(names):
        # 变体对象本来就是单位变换、局部坐标即契约坐标，直接平移排开即可。
        bpy.data.objects[name].location = Vector((index * spacing, 0.0, 0.0))
    bpy.context.view_layer.update()


def _world_bounds(names):
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for name in names:
        obj = bpy.data.objects[name]
        matrix = obj.matrix_world
        for vert in obj.data.vertices:
            world = matrix @ vert.co
            for axis in range(3):
                mins[axis] = min(mins[axis], world[axis])
                maxs[axis] = max(maxs[axis], world[axis])
    return Vector(mins), Vector(maxs)


def _camera_fit(names, azimuth_deg, elevation_deg, coverage=0.94):
    """Frame by measuring the real projection, never by assuming ortho_scale's meaning.

    Hand-picked ortho_scale values produced off-centre, half-out-of-shot frames, which
    is exactly the misread this render exists to prevent.
    """
    bpy.context.view_layer.update()
    low, high = _world_bounds(names)
    target = (low + high) * 0.5
    corners = [
        Vector(
            (
                high.x if mask & 1 else low.x,
                high.y if mask & 2 else low.y,
                high.z if mask & 4 else low.z,
            )
        )
        for mask in range(8)
    ]
    azimuth = math.radians(azimuth_deg)
    elevation = math.radians(elevation_deg)
    direction = Vector(
        (
            math.cos(azimuth) * math.cos(elevation),
            math.sin(azimuth) * math.cos(elevation),
            math.sin(elevation),
        )
    )
    data = bpy.data.cameras.new("qa_cam")
    data.type = "ORTHO"
    data.ortho_scale = 4.0
    data.clip_start = 0.1
    data.clip_end = 500.0
    camera = bpy.data.objects.new("qa_cam", data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = target + direction * 60.0
    camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    bpy.context.view_layer.update()

    scene = bpy.context.scene
    for _ in range(8):
        projected = [world_to_camera_view(scene, camera, corner) for corner in corners]
        us = [point.x for point in projected]
        vs = [point.y for point in projected]
        span = max(max(us) - min(us), max(vs) - min(vs))
        if span <= 1e-9:
            break
        data.ortho_scale *= span / coverage
        bpy.context.view_layer.update()

    projected = [world_to_camera_view(scene, camera, corner) for corner in corners]
    us = [point.x for point in projected]
    vs = [point.y for point in projected]
    return min(us), max(us), min(vs), max(vs), data.ortho_scale


def _render(path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = RESOLUTION_X
    scene.render.resolution_y = RESOLUTION_Y
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.68, 0.68, 0.65)
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    shading.show_shadows = True
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def _measure_content_u(path):
    """Horizontal extent of non-background pixels in the rendered PNG."""
    image = bpy.data.images.load(str(path))
    width, height = image.size
    pixels = image.pixels[:]
    background = (pixels[0], pixels[1], pixels[2])
    min_u = 1.0
    max_u = 0.0
    for y in range(2, height, 3):
        row = y * width * 4
        for x in range(2, width, 3):
            offset = row + x * 4
            delta = (
                abs(pixels[offset] - background[0])
                + abs(pixels[offset + 1] - background[1])
                + abs(pixels[offset + 2] - background[2])
            )
            if delta > 0.10:
                u = x / float(width)
                min_u = min(min_u, u)
                max_u = max(max_u, u)
    bpy.data.images.remove(image)
    return min_u, max_u


def _shoot(path, caption, names, azimuth_deg, elevation_deg, coverage=0.94):
    u_min, u_max, v_min, v_max, ortho_scale = _camera_fit(
        names, azimuth_deg, elevation_deg, coverage
    )
    if u_min < 0.002 or u_max > 0.998 or v_min < 0.002 or v_max > 0.998:
        raise RuntimeError("取景越出画幅：u=[%.3f, %.3f] v=[%.3f, %.3f]" % (u_min, u_max, v_min, v_max))
    _render(path)
    measured_min, measured_max = _measure_content_u(path)
    # 防假绿：相机算出来的框和真正画进 PNG 的内容必须对得上，否则"有东西"不代表
    # "框对"——某个对象整件没进画面（库对象被集合 hide_render 屏蔽）就是这么漏掉的。
    if abs(measured_min - u_min) > 0.05 or abs(measured_max - u_max) > 0.05:
        raise RuntimeError(
            "%s：渲染内容与取景预测不符 预测u=[%.3f, %.3f] 实测u=[%.3f, %.3f]"
            % (path.name, u_min, u_max, measured_min, measured_max)
        )
    print(
        "QA_SHOT %-38s ortho=%6.3f 预测u=[%.3f, %.3f] 实测u=[%.3f, %.3f] v=[%.3f, %.3f] | %s"
        % (path.name, ortho_scale, u_min, u_max, measured_min, measured_max, v_min, v_max, caption)
    )


QA_DIR.mkdir(parents=True, exist_ok=True)
_spawn_intact_copy()

# ---- A: 三种破损并排，看形态是否互相可辨 ----
_keep_only(VARIANTS)
_layout(VARIANTS, 5.6)
_shoot(
    QA_DIR / "parapet_damage_variants_row.png",
    "左=崩顶A 中=贯穿B 右=塌脚C",
    VARIANTS,
    -62.0,
    18.0,
)

# ---- B: 完好 + 三种破损，严格按 5.0m 模块长首尾相接 ----
order = [INTACT_QA] + VARIANTS
_keep_only(order)
_layout(order, MODULE_LENGTH)
_shoot(
    QA_DIR / "parapet_damage_variants_butted.png",
    "从左到右=完好 崩顶A 贯穿B 塌脚C，间距严格 5.00m",
    order,
    -74.0,
    14.0,
)

# ---- C: 接缝特写：完好段与崩顶段的交界 ----
joint = [INTACT_QA, DAMAGE_A]
_keep_only(joint)
_layout(joint, MODULE_LENGTH)
_shoot(
    QA_DIR / "parapet_damage_variants_joint.png",
    "左=完好段 右=崩顶段，接缝在中线，应齐平无错台",
    joint,
    -80.0,
    6.0,
    coverage=0.97,
)

print("QA_RENDER_OK files=3")
