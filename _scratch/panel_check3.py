"""Per-face detail measurement for the L corner's four previews.

The question this answers: "is the long arm's DECORATED face the one the player
sees from inside the room?"  The armor face is the 0.3175m protrusion, so its
world plane is known exactly, and each shot's camera is known exactly (the probe
logs eye/target and fov=60 vertical, 1280x720).  So each face can be projected,
cropped and measured:

    interior shot (+X-Z, the room side)  -> long arm armor plane z=-0.3175
                                            short arm armor plane x=+0.3175
    exterior shot (-X+Z, the outer back) -> long arm back plane  z=+0.15
                                            short arm back plane  x=-0.15
    pair shot   (-Z)                     -> wall(rot180) armor + arm armor

A decorated face carries armor plates, seams and emissive strips; a structural
back is a flat panel.  So "detail energy" (high-pass energy, i.e. local contrast)
separates them, and the ASCII dumps let the structure be checked directly.
"""

import math

from PIL import Image, ImageFilter

W, H = 1280, 720
FOV_DEG = 60.0
RAMP = " .:-=+*#%@"

SHOTS = {
    "interior": (
        "outputs/verification/corner_l_interior_plus_x_minus_z.png",
        (13.94837, 10.78982, -13.94837),
        (2.424999, 5.95, -2.424999),
    ),
    "exterior": (
        "outputs/verification/corner_l_exterior_minus_x_plus_z.png",
        (-9.098372, 10.78982, 9.098372),
        (2.424999, 5.95, -2.424999),
    ),
    "pair": (
        "outputs/verification/corner_l_pair_with_wall_minus_z.png",
        (-2.75, 10.05775, -25.75346),
        (-2.75, 5.95, -0.08),
    ),
}

# tag -> (shot, face spec: axis/index/value, span lo, span hi, y lo, y hi)
#   axis 0 = constant X (a face whose normal is +/-X), axis 2 = constant Z.
FACES = {
    "long-arm  ARMOR (room side, z=-0.3175)": ("interior", 2, -0.3175, 0.5, 5.0),
    "long-arm  BACK  (outer side, z=+0.15)": ("exterior", 2, 0.15, 0.5, 5.0),
    "short-arm ARMOR (room side, x=+0.3175)": ("interior", 0, 0.3175, -5.0, -0.5),
    "short-arm BACK  (outer side, x=-0.15)": ("exterior", 0, -0.15, -5.0, -0.5),
    "pair  reference wall (z=-0.3175)": ("pair", 2, -0.3175, -10.4, -6.1),
    "pair  L long arm     (z=-0.3175)": ("pair", 2, -0.3175, 0.6, 4.9),
}
Y_LO, Y_HI = 0.6, 10.4


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def norm(a):
    length = math.sqrt(dot(a, a))
    return tuple(v / length for v in a)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def camera(eye, target):
    forward = norm(sub(target, eye))
    right = norm(cross(forward, (0.0, 1.0, 0.0)))
    up = cross(right, forward)
    return eye, forward, right, up


def project(cam, point):
    eye, forward, right, up = cam
    d = sub(point, eye)
    depth = dot(d, forward)
    tan_v = math.tan(math.radians(FOV_DEG * 0.5))
    tan_h = tan_v * (W / float(H))
    return (
        W * 0.5 + (dot(d, right) / depth) / tan_h * (W * 0.5),
        H * 0.5 - (dot(d, up) / depth) / tan_v * (H * 0.5),
        depth,
    )


def face_rect(cam, axis, value, lo, hi):
    def point(a, y):
        return (a, y, value) if axis == 0 else (a, y, value)

    corners = []
    for a in (lo, hi):
        for y in (Y_LO, Y_HI):
            p = point(a, y)
            corners.append(project(cam, p))
    return (
        int(round(min(c[0] for c in corners))),
        int(round(min(c[1] for c in corners))),
        int(round(max(c[0] for c in corners))),
        int(round(max(c[1] for c in corners))),
        sum(c[2] for c in corners) / 4.0,
    )


def detail_energy(image):
    gray = image.convert("L")
    blurred = gray.filter(ImageFilter.BoxBlur(6))
    a = list(gray.getdata())
    b = list(blurred.getdata())
    return sum(abs(a[i] - b[i]) for i in range(len(a))) / float(len(a))


def mean_luma(image):
    pixels = list(image.convert("L").getdata())
    return sum(pixels) / float(len(pixels))


def ascii_dump(image, cols=54, rows=26):
    small = image.convert("L").resize((cols, rows), Image.BOX)
    pixels = list(small.getdata())
    lo, hi = min(pixels), max(pixels)
    span = max(hi - lo, 1)
    for y in range(rows):
        print(
            "    |"
            + "".join(
                RAMP[int((pixels[y * cols + x] - lo) / span * (len(RAMP) - 1))]
                for x in range(cols)
            )
            + "|"
        )


def main():
    cams = {}
    for key, (path, eye, target) in SHOTS.items():
        cams[key] = camera(eye, target)

    loaded = {}
    for key, (path, _eye, _target) in SHOTS.items():
        loaded[key] = Image.open(path).convert("RGB")

    print("face                                    shot      rect(x0,y0,x1,y1)   px      detail   mean_luma")
    print("-" * 104)
    results = {}
    for tag, (shot, axis, value, lo, hi) in FACES.items():
        rect = face_rect(cams[shot], axis, value, lo, hi)
        crop = loaded[shot].crop(rect[:4])
        detail = detail_energy(crop)
        luma = mean_luma(crop)
        results[tag] = (detail, luma, crop)
        print(
            "%-38s  %-8s  %-18s  %-6d  %6.2f  %7.1f"
            % (tag, shot, str(rect[:4]), crop.size[0] * crop.size[1] // 1000, detail, luma)
        )

    print()
    print("ASCII (each face rescaled to its own 54x26 grid):")
    for tag, (_detail, _luma, crop) in results.items():
        print("  %-38s crop=%s" % (tag, crop.size))
        ascii_dump(crop)


main()
