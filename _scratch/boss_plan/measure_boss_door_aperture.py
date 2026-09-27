"""Measure the door aperture of the legacy boss door-slot packages (Blender side).

  blender --factory-startup --background --python _scratch/boss_plan/measure_boss_door_aperture.py -- <root>

Projects every output mesh of the door-slot packages onto the XZ plane (world coords,
i.e. the room's own vertical plane) and reports coverage of the aperture rectangle.
"""

from __future__ import annotations

import sys

import bmesh
import bpy


PACKAGES = (
    "base_wall_south_slot_06_door_left",
    "base_wall_south_slot_06_door_right",
    "base_wall_south_slot_06_door_lintel",
)
REL = "component_packages"

N = 44
X0, X1 = -1.10, 1.10
Y0, Y1 = 0.00, 2.80


def main() -> None:
    argv = sys.argv
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    root = args[0]
    collected = []
    for name in PACKAGES:
        path = f"{root}/{REL}/{name}/{name}.blend"
        bpy.ops.wm.open_mainfile(filepath=path)
        for obj in bpy.context.scene.objects:
            if obj.type != "MESH" or "_输出_" not in obj.name:
                continue
            mw = obj.matrix_world
            for v in obj.data.vertices:
                w = mw @ v.co
                collected.append((w.x, w.y, w.z))
            xs = [ (mw @ v.co).x for v in obj.data.vertices ]
            zs = [ (mw @ v.co).z for v in obj.data.vertices ]
            ys = [ (mw @ v.co).y for v in obj.data.vertices ]
            print(
                f"  {name}: {obj.name} world x[{min(xs):.3f},{max(xs):.3f}] "
                f"y[{min(ys):.3f},{max(ys):.3f}] z[{min(zs):.3f},{max(zs):.3f}]"
            )

    grid = [[0] * N for _ in range(N)]
    for x, _y, z in collected:
        gx = int((x - X0) / (X1 - X0) * N)
        gz = int((z - Y0) / (Y1 - Y0) * N)
        if 0 <= gx < N and 0 <= gz < N:
            grid[gz][gx] = 1
    covered = sum(sum(r) for r in grid)
    print(f"BOSS_DOOR_APERTURE x[{X0},{X1}] z[{Y0},{Y1}] coverage={covered / (N * N) * 100:.1f}% (vertex raster)")
    for gz in range(N - 1, -1, -1):
        print(f"  z{z_hi(gz):5.2f} |{''.join('#' if grid[gz][gx] else '.' for gx in range(N))}|")
    print("MEASURE_BOSS_DOOR_APERTURE_DONE")


def z_hi(gz: int) -> float:
    return Y0 + (gz + 1) * (Y1 - Y0) / N


main()
