"""Blender-side ground-truth probe: wall-mounted HVAC fan direction + riser grounding.

Reads ONLY `depsgraph.object_instances` -> `io.matrix_world` (the authoritative read for
collection instances; reading `ob.matrix_world` of the linked library object yields the
SOURCE-scene coordinates and produces false offset readouts).

Checks
  1. hvac_small: rotated local +Z (fan face) must equal the wall outward normal.
  2. hvac_small / hvac_vent: envelope back face must sit WALL_MOUNT_EMBED inside the wall skin.
  3. pipe_riser: the lower (tip=180) instance envelope bottom must be z=0.
  4. pipe_riser stack: lower 0..4.945, upper 4.945..9.89 -> no body gap.
  5. landing decor still grounded at z=0 (regression guard).
"""
import json
import sys

import bpy  # noqa: E402
from mathutils import Matrix, Vector

PROJECT = r"I:\工作项目\shellstrom2\ShellStorm2"
BASE = PROJECT + r"\assets\art\environments\tower_zones\rooftop"
LAYOUT = BASE + r"\source\layouts\100f_decorated_v001\rooftop_100f_decorated_layout_v001.json"
CATALOG = BASE + r"\source\reference_components\v002\component_packages_v002\catalog.json"
BLEND = BASE + r"\source\layouts\100f_decorated_v001\rooftop_100f_decorated_layout_v001.blend"

TOL = 1e-3
EMBED = 0.05
RISER_H = 4.945
WALL_HALF_T = 0.15
SHELL_HALF = 15.0
SOUTH_FACE_BY = -(5.0 + SHELL_HALF + WALL_HALF_T)   # gz 20.15
EAST_FACE_BX = SHELL_HALF + WALL_HALF_T             # 15.15
WEST_FACE_BX = -(SHELL_HALF + WALL_HALF_T)          # -15.15

errors = []
lines = []


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


layout = load_json(LAYOUT)
catalog = {entry["slug"]: entry for entry in load_json(CATALOG)}
instances = layout["instances"]
by_id = {record["instance_id"]: record for record in instances}
bounds = {slug: (Vector(e["bounds_min"]), Vector(e["bounds_max"])) for slug, e in catalog.items()}

bpy.ops.wm.open_mainfile(filepath=BLEND)
depsgraph = bpy.context.evaluated_depsgraph_get()
real = {}
for inst in depsgraph.object_instances:
    ob = inst.object
    if ob is None or not ob.name.startswith("INST_"):
        continue
    real[ob.name] = Matrix(inst.matrix_world)
lines.append("depsgraph instances=%d layout records=%d" % (len(real), len(instances)))
if len(real) != len(instances):
    errors.append("depsgraph instance count %d != layout records %d" % (len(real), len(instances)))


def envelope(slug, matrix):
    mn, mx = bounds[slug]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ix in (mn.x, mx.x):
        for iy in (mn.y, mx.y):
            for iz in (mn.z, mx.z):
                p = matrix @ Vector((ix, iy, iz))
                lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
                hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    return lo, hi


# ── 1 & 2. wall-mounted units: fan outward + back embedded in the wall skin ──
# (axis, back_is_min, inside_sign): inside = (back - face) * inside_sign, positive => inside wall
UNIT_CHECKS = [
    ("INST_362_hvac_small", "hvac_small", Vector((0.0, -1.0, 0.0)), "y", False, +1.0, SOUTH_FACE_BY),
    ("INST_363_hvac_small", "hvac_small", Vector((0.0, -1.0, 0.0)), "y", False, +1.0, SOUTH_FACE_BY),
    ("INST_364_hvac_small", "hvac_small", Vector((1.0, 0.0, 0.0)), "x", True, -1.0, EAST_FACE_BX),
    ("INST_365_hvac_small", "hvac_small", Vector((-1.0, 0.0, 0.0)), "x", False, +1.0, WEST_FACE_BX),
]
for name, slug, outward, axis, back_is_min, inside_sign, face in UNIT_CHECKS:
    matrix = real.get(name)
    if matrix is None:
        errors.append("missing instance %s" % name)
        continue
    fan = (matrix.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
    if (fan - outward).length > TOL:
        errors.append("%s fan axis %s != outward %s" % (name, tuple(round(v, 4) for v in fan), tuple(outward)))
    lo, hi = envelope(slug, matrix)
    back = (lo if back_is_min else hi)[0 if axis == "x" else 1]
    inside = (back - face) * inside_sign
    if abs(inside - EMBED) > TOL + 1e-4:
        errors.append("%s back face inside wall = %.4f (expect %.2f)" % (name, inside, EMBED))
    lines.append("  %-22s fan=%-22s lo=%s hi=%s back_inside=%.3f" % (
        name,
        str(tuple(round(v, 3) for v in fan)),
        str(tuple(round(v, 3) for v in lo)),
        str(tuple(round(v, 3) for v in hi)),
        inside,
    ))

# vents are NOT tipped: their front grille keeps facing outward, only the back must be snug
VENT_CHECKS = [
    ("INST_366_hvac_vent", "hvac_vent", "y", False, +1.0, SOUTH_FACE_BY),
    ("INST_367_hvac_vent", "hvac_vent", "x", True, -1.0, EAST_FACE_BX),
]
for name, slug, axis, back_is_min, inside_sign, face in VENT_CHECKS:
    matrix = real.get(name)
    if matrix is None:
        errors.append("missing instance %s" % name)
        continue
    lo, hi = envelope(slug, matrix)
    back = (lo if back_is_min else hi)[0 if axis == "x" else 1]
    inside = (back - face) * inside_sign
    if abs(inside - EMBED) > TOL + 1e-4:
        errors.append("%s back face inside wall = %.4f (expect %.2f)" % (name, inside, EMBED))
    lines.append("  %-22s (vent, not tipped) back_inside=%.3f" % (name, inside))

# ── 3 & 4. riser stack: both segments sit at h=4.945 (the lower one is flipped about its origin) ──
runs = {}
for name, record in by_id.items():
    if record["component_slug"] != "pipe_riser":
        continue
    lo, hi = envelope("pipe_riser", real[name])
    key = (record["position_m"][0], record["position_m"][1])
    runs.setdefault(key, []).append((lo.z, hi.z, record["rotation_x_deg"]))

if len(runs) != 4:
    errors.append("riser runs=%d expected=4" % len(runs))
for key, entries in sorted(runs.items()):
    entries.sort()
    (lower_lo, lower_hi, lower_tip), (upper_lo, upper_hi, upper_tip) = entries
    if abs(lower_tip - 180.0) > TOL or abs(upper_tip) > TOL:
        errors.append("riser run %s tips=%s/%s expected 180/0" % (str(key), lower_tip, upper_tip))
    if abs(lower_lo) > TOL:
        errors.append("riser run %s lower envelope bottom z=%.4f (expect 0.0)" % (str(key), lower_lo))
    if abs(upper_hi - 2 * RISER_H) > 0.02:
        errors.append("riser run %s stack top z=%.4f (expect %.3f)" % (str(key), upper_hi, 2 * RISER_H))
    if abs(lower_hi - RISER_H) > TOL or abs(upper_lo - RISER_H) > TOL:
        errors.append("riser run %s joint: lower_top=%.4f upper_bottom=%.4f (expect %.3f)"
                      % (str(key), lower_hi, upper_lo, RISER_H))
    lines.append("  riser run x=%.2f by=%.2f lower=[%.3f,%.3f] tip=%.0f upper=[%.3f,%.3f] top=%.3f" % (
        key[0], key[1], lower_lo, lower_hi, lower_tip, upper_lo, upper_hi, upper_hi))

# ── 5. landing decor regression（按 slug 全量计数 + 最低点必须落在 0）──
LANDING = {"flowerbox": 8, "plant_large": 6, "plant_small": 6, "parapet_ivy": 8, "ivy": 16, "pipe_riser": 8}
lowest = {}
counted = {}
for name, record in by_id.items():
    slug = record["component_slug"]
    if slug not in LANDING:
        continue
    lo, hi = envelope(slug, real[name])
    counted[slug] = counted.get(slug, 0) + 1
    lowest[slug] = min(lowest.get(slug, 1e9), lo.z)
for slug, expect in LANDING.items():
    if counted.get(slug, 0) != expect:
        errors.append("landing slug %s count=%d expected=%d" % (slug, counted.get(slug, 0), expect))
        continue
    if abs(lowest[slug]) > TOL:
        errors.append("landing slug %s lowest z=%.4f (expect 0)" % (slug, lowest[slug]))
    lines.append("  landing %-12s n=%d lowest_z=%.4f" % (slug, counted[slug], lowest[slug]))

print("WALL_MOUNT_RISER_PROBE_BEGIN")
for line in lines:
    print(line)
if errors:
    for err in errors:
        print("WALL_MOUNT_RISER_PROBE_FAIL: " + err)
    print("WALL_MOUNT_RISER_PROBE_FAIL count=%d" % len(errors))
    sys.exit(1)
print("WALL_MOUNT_RISER_PROBE_OK units=4 vents=2 risers=4 landing_slugs=%d" % len(LANDING))
