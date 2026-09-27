"""前后对照渲染取证（只读）：同一机位、同一光照，渲「提亮+亚光化前」与「后」。

- before 取 `--before-root` 下同相对路径的 blend（B2 前置备份 `I:/workbuddy_tmp/material_role_backup`）
- after  取 `--project-root` 下的当前库
- 相机与光照**按几何自动推导**（几何两次完全相同，故机位一致）；色盘贴图路径强制指向当前绝对路径，
  避免 before 副本因相对路径断裂而渲成无贴图。

用法：
  blender -b --python render_palette_ab.py -- --project-root <root> --before-root <bak> --out-dir <dir>
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

LIB_ROOT_REL = "assets/art/environments/tower_zones/expedition/source/common_components"
PALETTE_REL = "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

SAMPLES = (
    ("v006", "office_room", "component_packages/work_cluster/work_cluster.blend"),
    ("v007", "bridge_room", "component_packages/tile_upper/tile_upper.blend"),
    ("v008", "boss_room", "component_packages/server_rack/server_rack.blend"),
    ("v008", "boss_room", "component_packages/heavy_conduits/heavy_conduits.blend"),
    ("v002", "l_corridor", "component_packages/high_pipe_east_00/high_pipe_east_00.blend"),
    ("v002", "l_corridor", "component_packages/server_00/server_00.blend"),
    ("v003", "db_room", "component_packages/server_rack_row/server_rack_row.blend"),
    ("v003", "db_room", "component_packages/ceiling_ring_beam/ceiling_ring_beam.blend"),
)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--project-root", required=True)
    p.add_argument("--before-root", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--res", type=int, default=640)
    return p.parse_args(argv)


def fix_palette_images(palette: Path) -> int:
    """把场景里所有非打包的图像指向当前色盘绝对路径，保证贴图可读。"""
    patched = 0
    for image in bpy.data.images:
        if image.packed_file is not None or image.source == "GENERATED":
            continue
        if not image.filepath:
            continue
        current = Path(bpy.path.abspath(image.filepath))
        if not current.is_file() and palette.is_file():
            image.filepath = str(palette)
            image.reload()
            patched += 1
        elif current.is_file():
            image.filepath = str(current)
    return patched


def output_bbox() -> tuple[Vector, float]:
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or "_输出_" not in obj.name:
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                lo[axis] = min(lo[axis], world[axis])
                hi[axis] = max(hi[axis], world[axis])
    size = max(hi[axis] - lo[axis] for axis in range(3))
    return (lo + hi) * 0.5, size


def setup_scene(res: int) -> None:
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("ab_world")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs[0].default_value = (0.02, 0.024, 0.034, 1.0)
    background.inputs[1].default_value = 1.0
    scene.world = world


def aim_camera(center: Vector, size: float, res: int) -> None:
    direction = Vector((0.86, -1.0, 0.62)).normalized()
    distance = size * 2.1
    cam_data = bpy.data.cameras.new("ab_cam")
    cam_data.lens = 45.0
    camera = bpy.data.objects.new("ab_cam", cam_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = center + direction * distance
    look = center - camera.location
    camera.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    sun_data = bpy.data.lights.new("ab_sun", type="SUN")
    sun_data.energy = 3.4
    sun_data.angle = math.radians(6.0)
    sun = bpy.data.objects.new("ab_sun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = Vector((-0.55, -0.9, 0.75)).to_track_quat("-Z", "Y").to_euler()
    fill_data = bpy.data.lights.new("ab_fill", type="AREA")
    fill_data.energy = 60.0
    fill_data.size = size
    fill = bpy.data.objects.new("ab_fill", fill_data)
    bpy.context.scene.collection.objects.link(fill)
    fill.location = center + Vector((-1.1, -1.3, 0.5)).normalized() * distance * 0.8
    fill.rotation_euler = (center - fill.location).to_track_quat("-Z", "Y").to_euler()


def main() -> int:
    args = parse_args()
    root = Path(args.project_root).resolve()
    before_root = Path(args.before_root)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    palette = root / PALETTE_REL
    grid = []
    for version, room_slug, rel in SAMPLES:
        row: dict[str, str] = {"version": version, "room_slug": room_slug, "rel": rel}
        for mode, base in (("before", before_root), ("after", root)):
            candidates = [
                base / LIB_ROOT_REL / version / rel,
                base / version / rel,
                base / Path(LIB_ROOT_REL).name / version / rel,
            ]
            blend = next((c for c in candidates if c.is_file()), candidates[0])
            if not blend.is_file():
                print("MISSING %s" % blend)
                return 2
            bpy.ops.wm.open_mainfile(filepath=str(blend))
            setup_scene(args.res)
            patched = fix_palette_images(palette)
            center, size = output_bbox()
            aim_camera(center, size, args.res)
            png = out_dir / ("%s_%s_%s.png" % (room_slug, Path(rel).stem, mode))
            bpy.context.scene.render.filepath = str(png)
            bpy.ops.render.render(write_still=True)
            row[mode] = str(png)
            print(
                "RENDERED %s %s size=%.2f palette_patched=%d -> %s"
                % (room_slug, mode, size, patched, png.name)
            )
        grid.append(row)
    (out_dir / "grid.json").write_text(
        json.dumps(grid, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("PALETTE_AB_RENDER_DONE:%d" % len(grid))
    return 0


if __name__ == "__main__":
    sys.exit(main())
