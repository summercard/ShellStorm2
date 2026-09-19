"""Pair-shot panel comparison for the A-suite L corner (ENV-TOWER-CORNER-L-5M).

Why this exists: the probe's `CORNER_L_VISUAL_OK` only proves "something non-flat
got rendered".  The claim under test here is stronger -- "the corner's long arm is
the same art as the straight wall, in the same orientation, under the same light".
The pair shot puts exactly those two panels into one frame:

    reference wall (yawed 180 so its armor faces -Z)  world x[-10.5, -5.5]
    L's long arm                                      world x[  0.0,  5.0]

both at the same depth plane (z=-0.3175, the armor face) and both 11.9m tall, and
the camera aims at x=-2.75 -- the midpoint of the two panel centres.  So the two
panels are exact screen-space mirrors of each other, and comparing them (one
flipped) is a direct pixel test of "renders the same".

Discrimination control: the same comparison is repeated with a deliberate 25px
shift.  If the aligned diff is much smaller than the shifted diff, the match is a
real content match and not two flat regions that happen to be similar.
"""

import math
import sys

from PIL import Image

PAIR = "outputs/verification/corner_l_pair_with_wall_minus_z.png"
W, H = 1280, 720
CAM = (-2.75, 10.05775, -25.75346)
TGT = (-2.75, 5.95, -0.08)
FOV_DEG = 60.0          # Godot Camera3D.fov is vertical (KEEP_HEIGHT)
ARMOR_Z = -0.3175       # both panels present their armor at this plane
SHIFT_PX = 25


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def norm(a):
    length = math.sqrt(dot(a, a))
    return tuple(v / length for v in a)


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


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
    corners = [
        project((x, y, ARMOR_Z))
        for x in (x0, x1)
        for y in (y0, y1)
    ]
    return (
        int(round(min(c[0] for c in corners))),
        int(round(min(c[1] for c in corners))),
        int(round(max(c[0] for c in corners))),
        int(round(max(c[1] for c in corners))),
    )


def stats(image):
    gray = image.convert("L")
    pixels = list(gray.getdata())
    mean = sum(pixels) / float(len(pixels))
    var = sum((p - mean) ** 2 for p in pixels) / float(len(pixels))
    bright = sum(1 for p in pixels if p >= 160) / float(len(pixels))
    return mean, math.sqrt(var), bright


def mean_abs_diff(a, b):
    pa = list(a.convert("RGB").getdata())
    pb = list(b.convert("RGB").getdata())
    total = 0
    for i in range(len(pa)):
        total += sum(abs(pa[i][k] - pb[i][k]) for k in range(3))
    return total / float(len(pa) * 3)


def main():
    image = Image.open(PAIR).convert("RGB")
    if image.size != (W, H):
        raise SystemExit("unexpected pair image size %s" % (image.size,))

    # The arm crop stops at x=4.9 / starts at 0.6 so the L's own short arm
    # (screen x~567-578, near the corner at x=0) cannot leak into the crop.
    arm_rect = panel_rect(0.6, 4.9, 0.6, 10.4)
    # Mirrored world span about the camera aim (x=-2.75) -> inside the wall panel.
    wall_rect = panel_rect(-10.4, -6.1, 0.6, 10.4)
    print("arm  rect (x0,y0,x1,y1) = %s" % (arm_rect,))
    print("wall rect (x0,y0,x1,y1) = %s" % (wall_rect,))
    print(
        "mirror of the two rects about x=%.1f: x0 sums %.1f / %.1f, x1 sums %.1f / %.1f"
        % (
            W / 2.0,
            arm_rect[0] + wall_rect[2],
            arm_rect[2] + wall_rect[0],
            W,
            W,
        )
    )

    arm = image.crop(arm_rect)
    wall = image.crop(wall_rect)
    print("crop sizes: arm=%s wall=%s" % (arm.size, wall.size))
    if arm.size != wall.size:
        raise SystemExit("panel crops differ in size; cannot compare")

    arm_flipped = arm.transpose(Image.FLIP_LEFT_RIGHT)

    aligned = mean_abs_diff(wall, arm_flipped)
    inside = arm_flipped.crop((0, 0, arm.size[0] - SHIFT_PX, arm.size[1]))
    shifted = mean_abs_diff(wall.crop((SHIFT_PX, 0, wall.size[0], wall.size[1])), inside)

    wall_mean, wall_std, wall_bright = stats(wall)
    arm_mean, arm_std, arm_bright = stats(arm_flipped)

    print()
    print("wall panel : mean=%.1f std=%.1f bright_share=%.3f" % (wall_mean, wall_std, wall_bright))
    print("arm  panel : mean=%.1f std=%.1f bright_share=%.3f" % (arm_mean, arm_std, arm_bright))
    print("aligned mean |diff| = %.2f / 255" % aligned)
    print("shifted(%dpx) mean |diff| = %.2f / 255" % (SHIFT_PX, shifted))
    print("ratio shifted/aligned = %.2fx" % (shifted / max(aligned, 1e-6)))

    # Eyeball-level diagnostics for the other three shots: a panel that presents
    # armor carries the emissive UI role, so it should be busier than a plain back.
    print()
    for name in (
        "corner_l_interior_plus_x_minus_z.png",
        "corner_l_exterior_minus_x_plus_z.png",
        "corner_l_top.png",
    ):
        other = Image.open("outputs/verification/" + name).convert("RGB")
        mean, std, bright = stats(other)
        print("%-38s mean=%.1f std=%.1f bright_share=%.3f" % (name, mean, std, bright))


main()
