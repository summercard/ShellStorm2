"""Two follow-ups on the pair-shot panels + an ASCII look at all four shots.

1. High-pass comparison.  A raw pixel diff is dominated by the smooth terms: the
   two panels are mirrored in screen space, so the view-dependent part of the
   metal/sky reflection differs as a gradient even when the art is identical.  So
   compare the HIGH-PASS (detail) content instead, where the art's seams, plates
   and logos live, and use a deliberate 25px shift as the discrimination control.
2. ASCII grey dump, so the structure can be inspected without an image viewer.
"""

import math

from PIL import Image, ImageFilter

PAIR = "outputs/verification/corner_l_pair_with_wall_minus_z.png"
W, H = 1280, 720
CAM = (-2.75, 10.05775, -25.75346)
TGT = (-2.75, 5.95, -0.08)
FOV_DEG = 60.0
ARMOR_Z = -0.3175
SHIFT_PX = 25
RAMP = " .:-=+*#%@"


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def norm(a):
    length = math.sqrt(dot(a, a))
    return tuple(v / length for v in a)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


FORWARD = norm(sub(TGT, CAM))
RIGHT = norm(cross(FORWARD, (0.0, 1.0, 0.0)))
UP = cross(RIGHT, FORWARD)
TAN_V = math.tan(math.radians(FOV_DEG * 0.5))
TAN_H = TAN_V * (W / float(H))


def project(point):
    d = sub(point, CAM)
    depth = dot(d, FORWARD)
    return (
        W * 0.5 + (dot(d, RIGHT) / depth) / TAN_H * (W * 0.5),
        H * 0.5 - (dot(d, UP) / depth) / TAN_V * (H * 0.5),
    )


def panel_rect(x0, x1, y0, y1):
    corners = [project((x, y, ARMOR_Z)) for x in (x0, x1) for y in (y0, y1)]
    return (
        int(round(min(c[0] for c in corners))),
        int(round(min(c[1] for c in corners))),
        int(round(max(c[0] for c in corners))),
        int(round(max(c[1] for c in corners))),
    )


def highpass(image, radius=6):
    gray = image.convert("L")
    blurred = gray.filter(ImageFilter.BoxBlur(radius))
    a = list(gray.getdata())
    b = list(blurred.getdata())
    return [a[i] - b[i] for i in range(len(a))], gray.size


def hp_diff(one, two):
    total = 0
    for i in range(len(one)):
        total += abs(one[i] - two[i])
    return total / float(len(one))


def ascii_dump(path, cols=104, rows=34, title=""):
    image = Image.open(path).convert("L")
    small = image.resize((cols, rows), Image.BOX)
    pixels = list(small.getdata())
    lo, hi = min(pixels), max(pixels)
    print("=" * (cols + 12))
    print("# %s  (%s)  luma %d..%d" % (title, path.split("/")[-1], lo, hi))
    span = max(hi - lo, 1)
    for y in range(rows):
        line = "".join(
            RAMP[int((pixels[y * cols + x] - lo) / span * (len(RAMP) - 1))]
            for x in range(cols)
        )
        print("  |" + line + "|")


def main():
    image = Image.open(PAIR).convert("RGB")
    arm = image.crop(panel_rect(0.6, 4.9, 0.6, 10.4))
    wall = image.crop(panel_rect(-10.4, -6.1, 0.6, 10.4))
    arm_flipped = arm.transpose(Image.FLIP_LEFT_RIGHT)

    arm_hp, size = highpass(arm_flipped)
    wall_hp, _ = highpass(wall)
    aligned = hp_diff(arm_hp, wall_hp)

    inner_arm_hp, _ = highpass(arm_flipped.crop((0, 0, size[0] - SHIFT_PX, size[1])))
    inner_wall_hp, _ = highpass(wall.crop((SHIFT_PX, 0, size[0], size[1])))
    shifted = hp_diff(inner_arm_hp, inner_wall_hp)
    print("panel size            = %s" % (size,))
    print("high-pass aligned     = %.2f / 255" % aligned)
    print("high-pass shifted%3d  = %.2f / 255" % (SHIFT_PX, shifted))
    print("discrimination        = %.2fx" % (shifted / max(aligned, 1e-6)))
    print("arm  detail energy    = %.2f" % (sum(abs(v) for v in arm_hp) / len(arm_hp)))
    print("wall detail energy    = %.2f" % (sum(abs(v) for v in wall_hp) / len(wall_hp)))
    print()

    for name, title in (
        ("corner_l_pair_with_wall_minus_z.png", "pair: wall(rot180) | L's long arm"),
        ("corner_l_interior_plus_x_minus_z.png", "interior = room side (+X-Z)"),
        ("corner_l_exterior_minus_x_plus_z.png", "exterior = outer back (-X+Z)"),
        ("corner_l_top.png", "top"),
    ):
        ascii_dump("outputs/verification/" + name, title=title)


main()
