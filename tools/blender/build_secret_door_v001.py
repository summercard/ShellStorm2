"""Build the secret-door source master (two components) for ShellStorm2.

Components
----------
1. secret_door_leaf   : door frame + cavity + two leaves (one closed, one half-open
                        at 42 deg) + two emissive light strips deep in the cavity.
2. secret_door_boards : nailed board barricade covering the opening (removable).

Both components share the same local frame:
    origin  = bottom center, Z=0 is the walking surface
    +Y      = front (toward the player / room side), wall outer face at Y=0
    +Z      = up
    X       = right

Contract values are measured from the live office_room door_wall prefab in
assets/art/.../office_room/door_wall/door_wall_root_top3d.tscn:
    opening 2.2 m wide, 2.5 m high, wall body 1.11 m thick.

Run headless:
    blender --background --python tools/blender/build_secret_door_v001.py
Optional env:
    SECRET_DOOR_SKIP_RENDER=1   skip preview renders
    SECRET_DOOR_SKIP_EXPORT=1   skip GLB export
"""

import json
import math
import os
import struct
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("I:/工作项目/shellstrom2/ShellStorm2")
PALETTE = PROJECT / "assets" / "art" / "shared" / "palette" / "设施低亮多巴胺色盘_10x10_512.png"
SRC_DIR = PROJECT / "art_source/environments/tower_zones/expedition/source/secret_door/v001"
BLEND_PATH = SRC_DIR / "secret_door_v001.blend"
QA_DIR = SRC_DIR / "qa"
# component_packages_v###/<category>/<asset_slug>/asset_manifest.json  (spec 6.3)
PKG_ROOT = SRC_DIR / "component_packages_v001"
PKG_CATEGORY = "facilities"
WORK_DIR = Path("I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-10-18_secret_door_art")

RUNTIME_ROOT = PROJECT / "assets/art/environments/tower_zones/expedition/components/common_components"

# ---------------------------------------------------------------------------
# geometry contract (metres)
# ---------------------------------------------------------------------------
OPEN_W = 2.20          # clear opening width, matches office_room door_wall
OPEN_H = 2.50          # clear opening height
FRAME_T = 0.14         # frame face width
FRAME_D = 0.12         # frame depth in front of the wall face (Y 0 -> -0.12)
CAVITY_D = 1.70        # cavity depth behind the frame: room to swing a 2.14 m leaf
CAVITY_WALL = 0.05     # cavity side/top wall thickness
LEAF_T = 0.05          # leaf thickness
LEAF_OPEN_DEG = 45.0   # half-open angle of the single leaf (swings into the cavity)

# Assembly frame: Y=0 is the ROOM-SIDE wall face.
#   boards  : Y > 0   (nailed onto the room side, protruding into the room)
#   frame   : Y -0.12 .. 0
#   cavity  : Y -0.12 .. -(0.12 + CAVITY_D)
#   leaf    : swings from the hinge into negative Y
# Nothing is centred per component: the two components must be instantiated at
# the same origin and stack by themselves. (First attempt centred each one on
# its own bounds, which pushed the boards behind the door.)
#
# Why the cavity is deeper than the 1.11 m wall body: the wall behind a secret
# site is verified empty for 3 m outward (all four sites were probe-checked), so
# the cavity reads as "depth" rather than intersecting a neighbouring room. The
# leaf needs 2.14 * sin(45 deg) = 1.51 m of travel, which a 0.85 m cavity cannot
# provide -- that version had the leaf poking out through the cavity back wall.
ASSY_DEPTH = FRAME_D + CAVITY_D
WALL_FACE_Y = 0.0      # Y=0 already is the room-side face; kept for the manifests

BOARD_W = 2.36         # barricade width
BOARD_T = 0.045        # barricade board thickness
BOARD_Z0 = 0.06
BOARD_Z1 = 2.56

# ---------------------------------------------------------------------------
# palette cells (col, row). row0 is V=0 which is the BOTTOM of the palette image.
# ---------------------------------------------------------------------------
CELL = {
    "frame": (4, 2),        # 311262 deep violet  (precision metal)
    "frame_dark": (3, 2),   # 290f52 darker violet
    "cavity": (9, 3),       # 718195 cold light grey (matte inner wall)
    "cavity_floor": (0, 0), # 05050c near black
    "light": (4, 9),        # 733700 deep amber strip
    "light_soft": (4, 6),   # 692805 warm brown panel, lifted only by emission
    "light_glow": (6, 6),   # 715c09 brightest amber for the door-gap wedge
    "leaf": (5, 4),         # 145f56 teal leaf body
    "leaf_edge": (1, 4),    # 03231b much darker teal trim, reads as a seam
    "handle": (6, 2),       # 3f296f bright violet handle
    "board_a": (5, 7),      # 70340a mid brown
    "board_b": (2, 7),      # 451708 dark brown
    "board_c": (6, 7),      # 71421b lighter brown
    "nail": (9, 4),         # 5d6e82 cold steel
}

# canonical role names: the Godot post-import script matches these prefixes
ROLE_METAL = "01_精工金属_紫色骨架"
ROLE_MATTE = "02_细腻哑光_青绿大面"
ROLE_GLOSS = "03_清漆反光_紫粉点缀"
ROLE_EMISSIVE = "04_柔和自发光_UI灯光"

ROLE_SPEC = {
    ROLE_METAL: (0.86, 0.28, 0.18, 0.0),
    ROLE_MATTE: (0.02, 0.70, 0.00, 0.0),
    ROLE_GLOSS: (0.16, 0.15, 0.68, 0.0),
    ROLE_EMISSIVE: (0.00, 0.36, 0.00, 1.15),
}

MATERIALS = {}
COLLECTIONS = {}


# ---------------------------------------------------------------------------
# scene / material helpers
# ---------------------------------------------------------------------------
def wipe_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.collections,
    ):
        for item in list(datablocks):
            try:
                datablocks.remove(item)
            except RuntimeError:
                pass


def make_collection(name, parent=None, hide=False):
    coll = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(coll)
    if hide:
        coll.hide_viewport = True
        coll.hide_render = True
    COLLECTIONS[name] = coll
    return coll


def setup_materials():
    if not PALETTE.exists():
        raise FileNotFoundError(f"shared palette missing: {PALETTE}")
    image = bpy.data.images.load(str(PALETTE), check_existing=False)
    image.name = "共享色盘_设施低亮多巴胺_10x10_512"
    image.colorspace_settings.name = "sRGB"
    # Keep the absolute path while building and rendering: a `//` relative path is
    # only resolvable once the .blend has been saved, and rendering happens before
    # the first save. `relink_palette_relative()` rewrites it after the save.
    image.filepath = str(PALETTE)
    image.use_fake_user = False

    for role, (metallic, roughness, coat, emission_strength) in ROLE_SPEC.items():
        mat = bpy.data.materials.new(role)
        mat.use_nodes = True
        mat.use_backface_culling = role != ROLE_MATTE
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()
        out = nodes.new("ShaderNodeOutputMaterial")
        out.location = (460, 0)
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.location = (160, 0)
        uv = nodes.new("ShaderNodeUVMap")
        uv.uv_map = "PaletteUV"
        uv.location = (-540, 0)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        tex.extension = "EXTEND"
        tex.location = (-280, 0)
        links.new(uv.outputs["UV"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if bsdf.inputs.get("Coat Weight"):
            bsdf.inputs["Coat Weight"].default_value = coat
        if emission_strength > 0.0:
            links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        MATERIALS[role] = mat


# ---------------------------------------------------------------------------
# mesh building
# ---------------------------------------------------------------------------
class MeshBuilder:
    """Accumulates axis-aligned or Y-rotated boxes into a single mesh.

    Every face gets its own small UV island parked in the centre of one palette
    cell, so one material role can carry several palette colours.
    """

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.face_mat = []
        self.face_cell = []
        self.slots = []

    def _slot(self, role):
        if role not in self.slots:
            self.slots.append(role)
        return self.slots.index(role)

    def box(self, center, size, role, cell, yaw_deg=0.0, pivot=None, pitch_deg=0.0):
        """Axis-aligned box, optionally tilted around Y first, then spun around Z.

        pitch_deg : rotation around the Y axis (tilts a board inside the XZ plane,
                    positive turns +X toward +Z). Used for the crossed braces.
        yaw_deg   : rotation around the Z axis (swings a door leaf, positive turns
                    +X toward +Y).
        """
        cx, cy, cz = center
        sx, sy, sz = size
        hx, hy, hz = sx / 2.0, sy / 2.0, sz / 2.0
        base = len(self.verts)
        corners = []
        for ix in (-1, 1):
            for iy in (-1, 1):
                for iz in (-1, 1):
                    corners.append(Vector((cx + ix * hx, cy + iy * hy, cz + iz * hz)))
        if pitch_deg:
            ang = math.radians(pitch_deg)
            cos_a, sin_a = math.cos(ang), math.sin(ang)
            pivoted = []
            for v in corners:
                dx, dz = v.x - cx, v.z - cz
                pivoted.append(
                    Vector((cx + dx * cos_a + dz * sin_a, v.y, cz - dx * sin_a + dz * cos_a))
                )
            corners = pivoted
        if yaw_deg:
            ang = math.radians(yaw_deg)
            px, py = pivot if pivot else (cx, cy)
            cos_a, sin_a = math.cos(ang), math.sin(ang)
            rotated = []
            for v in corners:
                dx, dy = v.x - px, v.y - py
                rotated.append(
                    Vector((px + dx * cos_a - dy * sin_a, py + dx * sin_a + dy * cos_a, v.z))
                )
            corners = rotated
        self.verts.extend(corners)

        # index layout: (ix, iy, iz) -> ix*4 + iy*2 + iz
        def idx(ix, iy, iz):
            return base + ix * 4 + iy * 2 + iz

        faces = [
            ((0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)),  # -X
            ((1, 0, 0), (1, 0, 1), (1, 1, 1), (1, 1, 0)),  # +X
            ((0, 0, 0), (0, 0, 1), (1, 0, 1), (1, 0, 0)),  # -Y
            ((0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)),  # +Y
            ((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)),  # -Z
            ((0, 0, 1), (0, 1, 1), (1, 1, 1), (1, 0, 1)),  # +Z
        ]
        mat_index = self._slot(role)
        for quad in faces:
            self.faces.append(tuple(idx(*c) for c in quad))
            self.face_mat.append(mat_index)
            self.face_cell.append(cell)
        return base

    def cylinder_y(self, center, radius, depth, role, cell, segments=8):
        """Cylinder whose axis runs along Y (used for nails)."""
        cx, cy, cz = center
        base = len(self.verts)
        ring = []
        for i in range(segments):
            a = math.tau * i / segments
            ring.append((cx + math.cos(a) * radius, cz + math.sin(a) * radius))
        for y in (cy - depth / 2.0, cy + depth / 2.0):
            for (px, pz) in ring:
                self.verts.append(Vector((px, y, pz)))
        mat_index = self._slot(role)
        half = segments // 2
        for i in range(segments):
            j = (i + 1) % segments
            # side quad
            self.faces.append((base + i, base + j, base + segments + j, base + segments + i))
            self.face_mat.append(mat_index)
            self.face_cell.append(cell)
        # caps: fan around the ring (triangles are legal glTF faces)
        for start in (0, segments):
            for i in range(1, segments - 1):
                self.faces.append((base + start, base + start + i, base + start + i + 1))
                self.face_mat.append(mat_index)
                self.face_cell.append(cell)
        return base

    def build(self, collection, version="v001", asset_id=None):
        """Create the output mesh in the shared assembly frame.

        X is centred and the lowest point sits at Z=0, per the scene/prop spec.
        Y is NOT centred: Y=0 is the room-side wall face, which is the only
        origin that lets the leaf and the boards be instantiated at the same
        point and stack correctly. Centring Y per component (what this script
        did first) silently pushed the barricade behind the door.
        """
        if WALL_FACE_Y:
            self.verts = [Vector((v.x, v.y + WALL_FACE_Y, v.z)) for v in self.verts]

        mesh = bpy.data.meshes.new(self.name + "_Mesh")
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.update()

        for role in self.slots:
            mesh.materials.append(MATERIALS[role])

        layer = mesh.uv_layers.new(name="PaletteUV")
        layer.active_render = True
        mesh.uv_layers.active = layer
        radius = 0.023
        for poly, cell in zip(mesh.polygons, self.face_cell):
            col, row = cell
            center_x = (col + 0.5) / 10.0
            center_y = (row + 0.5) / 10.0
            count = len(poly.loop_indices)
            for k, loop_index in enumerate(poly.loop_indices):
                angle = math.tau * k / max(3, count) + 0.25
                layer.data[loop_index].uv = (
                    center_x + math.cos(angle) * radius,
                    center_y + math.sin(angle) * radius,
                )
        for poly, mat_index in zip(mesh.polygons, self.face_mat):
            poly.material_index = mat_index
            poly.use_smooth = False

        # drop any legacy uv layer name, keep PaletteUV only
        for uv in list(mesh.uv_layers):
            if uv.name != "PaletteUV":
                mesh.uv_layers.remove(uv)

        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        obj["asset_id"] = asset_id or self.name
        obj["asset_version"] = version
        obj["origin_contract"] = "bottom_center"
        obj["front_axis_blender"] = "+Y"
        obj["up_axis"] = "+Z"
        obj["palette_uv_channel"] = "PaletteUV"
        obj["origin_contract"] = "wall_face_bottom_center"
        obj["assembly_frame_note"] = (
            "X 居中、Z 贴底；Y=0 是房间侧墙面（木板在 Y>0 向内凸，门腔在 Y<0 向内凹）。"
        )
        return obj


# ---------------------------------------------------------------------------
# component 1: secret door leaf (frame + cavity + leaves + light)
# ---------------------------------------------------------------------------
def build_leaf_body(builder):
    half_open = OPEN_W / 2.0
    frame_outer = half_open + FRAME_T
    frame_top = OPEN_H + FRAME_T

    # --- frame (precision metal) ---
    builder.box((-frame_outer + FRAME_T / 2, -FRAME_D / 2, frame_top / 2),
                (FRAME_T, FRAME_D, frame_top), ROLE_METAL, CELL["frame"])
    builder.box((frame_outer - FRAME_T / 2, -FRAME_D / 2, frame_top / 2),
                (FRAME_T, FRAME_D, frame_top), ROLE_METAL, CELL["frame"])
    builder.box((0.0, -FRAME_D / 2, OPEN_H + FRAME_T / 2),
                (OPEN_W, FRAME_D, FRAME_T), ROLE_METAL, CELL["frame"])

    # thin sill plate so the frame reads as a finished portal from the front
    builder.box((0.0, -FRAME_D / 2, 0.015), (OPEN_W + 2 * FRAME_T, FRAME_D, 0.03),
                ROLE_METAL, CELL["frame_dark"])

    # --- cavity walls (matte) ---
    inner = half_open - CAVITY_WALL
    cavity_mid_y = -FRAME_D - CAVITY_D / 2.0
    builder.box((-half_open + CAVITY_WALL / 2, cavity_mid_y, OPEN_H / 2),
                (CAVITY_WALL, CAVITY_D, OPEN_H), ROLE_MATTE, CELL["cavity"])
    builder.box((half_open - CAVITY_WALL / 2, cavity_mid_y, OPEN_H / 2),
                (CAVITY_WALL, CAVITY_D, OPEN_H), ROLE_MATTE, CELL["cavity"])
    builder.box((0.0, cavity_mid_y, OPEN_H - CAVITY_WALL / 2),
                (inner * 2, CAVITY_D, CAVITY_WALL), ROLE_MATTE, CELL["cavity"])
    # cavity back wall — dark, so the light strips read against it
    back_y = -FRAME_D - CAVITY_D + 0.02
    builder.box((0.0, back_y, OPEN_H / 2), (inner * 2, 0.04, OPEN_H),
                ROLE_MATTE, CELL["cavity_floor"])

    # --- ONE leaf, half open (user: 只要一个门，半掩着的) ---
    # Hinged on the left jamb, swinging INWARD (-Y) so the room side sees the
    # door standing ajar with light escaping around it. At 54 deg the leaf's
    # frontal projection is ~0.59 of the opening, leaving a clear gap on the
    # right plus a sliver at the top: that gap is where the light comes through.
    leaf_w = OPEN_W - 0.06
    leaf_h = OPEN_H - 0.05
    hinge_x = -half_open + 0.05
    leaf_center_x = hinge_x + leaf_w / 2.0
    leaf_y = -FRAME_D - LEAF_T / 2.0 - 0.03
    pivot = (hinge_x, leaf_y)
    yaw = -LEAF_OPEN_DEG

    builder.box((leaf_center_x, leaf_y, leaf_h / 2.0 + 0.02),
                (leaf_w, LEAF_T, leaf_h), ROLE_MATTE, CELL["leaf"],
                yaw_deg=yaw, pivot=pivot)

    # recessed border + two rails on the room-facing face. The leaf swings away
    # from the viewer, so the face that stays visible is its +Y side.
    trim_t = 0.018
    trim_w = 0.085
    face_y = leaf_y + LEAF_T / 2.0 + trim_t / 2.0
    half = leaf_w / 2.0
    z0, z1 = 0.10, leaf_h - 0.10
    for dx in (-half + trim_w / 2, half - trim_w / 2):
        builder.box((leaf_center_x + dx, face_y, (z0 + z1) / 2.0),
                    (trim_w, trim_t, z1 - z0), ROLE_MATTE, CELL["leaf_edge"],
                    yaw_deg=yaw, pivot=pivot)
    for z in (z0 + trim_w / 2, z1 - trim_w / 2):
        builder.box((leaf_center_x, face_y, z),
                    (leaf_w, trim_t, trim_w), ROLE_MATTE, CELL["leaf_edge"],
                    yaw_deg=yaw, pivot=pivot)
    for z in (leaf_h * 0.36, leaf_h * 0.68):
        builder.box((leaf_center_x, face_y, z),
                    (leaf_w - trim_w * 2, trim_t, trim_w), ROLE_MATTE, CELL["leaf_edge"],
                    yaw_deg=yaw, pivot=pivot)

    # lever handle near the free (right) edge, rides with the leaf
    handle_x = hinge_x + leaf_w - 0.13
    builder.box((handle_x, face_y + 0.028, OPEN_H * 0.45),
                (0.055, 0.055, 0.36), ROLE_METAL, CELL["handle"],
                yaw_deg=yaw, pivot=pivot)
    builder.box((handle_x - 0.11, face_y + 0.062, OPEN_H * 0.45),
                (0.24, 0.045, 0.055), ROLE_METAL, CELL["handle"],
                yaw_deg=yaw, pivot=pivot)

    # hinge knuckles on the hinge jamb
    for z in (0.32, leaf_h - 0.28, leaf_h * 0.5):
        builder.box((hinge_x + 0.015, leaf_y, z), (0.075, LEAF_T + 0.035, 0.17),
                    ROLE_METAL, CELL["frame"], yaw_deg=yaw, pivot=pivot)


def build_leaf_light(builder):
    """Emissive surfaces inside the cavity.

    The user's brief is "里面透光出来" — so the light source is a lit cavity
    behind a half-open door, not a lamp on the door. Three layers:
      1. a large soft panel on the back wall (the "room beyond"),
      2. brighter strips in front of it for depth,
      3. a floor spill that grazes the bottom gap.
    Board gaps in `build_boards` sit at the same heights, so light physically
    escapes through them instead of being faked with a glow overlay.
    """
    half_open = OPEN_W / 2.0
    inner = half_open - CAVITY_WALL
    back_y = -FRAME_D - CAVITY_D + 0.02

    # 1) soft backlight panel — the "lit room beyond". This is the brightest
    #    surface in the asset and the only reason the opening reads as lit.
    builder.box((0.0, back_y + 0.028, OPEN_H * 0.5),
                (inner * 1.80, 0.022, OPEN_H * 0.86), ROLE_EMISSIVE, CELL["light_glow"])
    # 2) brighter strips in front of it, for depth
    for z, height in ((0.56, 0.12), (1.08, 0.12), (1.59, 0.14), (2.08, 0.11)):
        builder.box((0.0, back_y + 0.055, z), (inner * 1.5, 0.03, height),
                    ROLE_EMISSIVE, CELL["light"])
    # 3) floor spill
    builder.box((0.0, back_y + 0.09, 0.045), (inner * 1.25, 0.05, 0.035),
                ROLE_EMISSIVE, CELL["light"])
    # 4) NO emissive slab in the doorway plane.
    #    Two attempts to put one there failed the same way: a flat emissive quad
    #    facing the camera reads as "another yellow door panel", not as light.
    #    Light only reads as light when you can see the lit volume BEHIND the
    #    opening, so the depth cue is handled by the 1.7 m cavity plus the bright
    #    back panel above. Nothing else belongs in the opening.


# ---------------------------------------------------------------------------
# component 2: nailed board barricade
# ---------------------------------------------------------------------------
def build_boards(builder):
    half = BOARD_W / 2.0
    # Five boards, deliberately uneven: ragged ends, varying nailing depth and
    # 0.10-0.14 m gaps between slats. The gaps are the point — the emissive
    # strips behind the door have to bleed through them, otherwise the barricade
    # reads as a solid wall and the "somebody nailed this shut" story is lost.
    rows = [
        (0.08, 0.50, -1.16 * half / 1.18, 1.10 * half / 1.18, CELL["board_a"], 0.000),
        (0.62, 1.02, -1.12 * half / 1.18, 1.19 * half / 1.18, CELL["board_c"], 0.006),
        (1.14, 1.52, -1.19 * half / 1.18, 1.05 * half / 1.18, CELL["board_a"], 0.002),
        (1.66, 2.02, -1.08 * half / 1.18, 1.19 * half / 1.18, CELL["board_c"], 0.008),
        (2.14, 2.52, -1.16 * half / 1.18, 1.12 * half / 1.18, CELL["board_b"], 0.003),
    ]

    nail_spots = []
    for (z0, z1, x0, x1, cell, y_off) in rows:
        builder.box(((x0 + x1) / 2, y_off + BOARD_T / 2, (z0 + z1) / 2),
                    (x1 - x0, BOARD_T, z1 - z0), ROLE_MATTE, cell)
        if z1 - z0 > 0.4:
            builder.box(((x0 + x1) / 2, y_off + BOARD_T / 2, (z0 + z1) / 2),
                        (x1 - x0, BOARD_T * 0.55, 0.016), ROLE_MATTE, CELL["board_b"])
        for tx in (0.10, 0.45, 0.80):
            nail_spots.append((x0 + (x1 - x0) * tx, y_off + BOARD_T, (z0 + z1) / 2))

    # two crossed braces, tilted inside the XZ plane (rotation around Y)
    span_x = BOARD_W - 0.26
    span_z = 2.40
    brace_len = math.hypot(span_x, span_z)
    angle = math.degrees(math.atan2(span_z, span_x))
    mid_z = (BOARD_Z0 + BOARD_Z1) / 2
    brace_y_a = BOARD_T + 0.018
    brace_y_b = brace_y_a + 0.038
    builder.box((0.0, brace_y_a, mid_z), (brace_len, 0.038, 0.17),
                ROLE_MATTE, CELL["board_b"], pitch_deg=angle)
    builder.box((0.0, brace_y_b, mid_z), (brace_len, 0.038, 0.17),
                ROLE_MATTE, CELL["board_b"], pitch_deg=-angle)
    ex = span_x / 2.0 * 0.88
    ez = span_z / 2.0 * 0.88
    for (bx, bz, by) in ((-ex, mid_z - ez, brace_y_b), (ex, mid_z + ez, brace_y_b),
                         (-ex, mid_z + ez, brace_y_a), (ex, mid_z - ez, brace_y_a)):
        nail_spots.append((bx, by + 0.019, bz))

    for (nx, ny, nz) in nail_spots:
        builder.cylinder_y((nx, ny + 0.011, nz), 0.016, 0.022, ROLE_METAL, CELL["nail"])


def relink_palette_relative():
    """Rewrite the palette image to a `//` link after the .blend exists on disk."""
    rel = "//" + os.path.relpath(PALETTE, BLEND_PATH.parent).replace("\\", "/")
    for image in bpy.data.images:
        if image.name.startswith("共享色盘"):
            # external link only, never pack the shared palette into the .blend
            image.filepath = rel
    print(f"PALETTE_RELINKED {rel}")


# ---------------------------------------------------------------------------
# scene assembly
# ---------------------------------------------------------------------------
def assemble():
    wipe_scene()
    setup_materials()

    root = make_collection("隐藏门_资产管理")
    src = make_collection("01_制作组件_已统一材质", root, hide=True)
    out = make_collection("02_游戏输出_整合模型", root)
    stage = make_collection("90_展示环境_灯光相机", root, hide=False)

    leaf_pkg = make_collection("隐藏门叶_资产包", out)
    boards_pkg = make_collection("木板封堵_资产包", out)

    leaf_body = MeshBuilder("secret_door_leaf_主体")
    build_leaf_body(leaf_body)
    leaf_body_obj = leaf_body.build(leaf_pkg, asset_id="ENV-EXPEDITION-SECRET-DOOR-LEAF")

    leaf_light = MeshBuilder("secret_door_leaf_自发光")
    build_leaf_light(leaf_light)
    leaf_light_obj = leaf_light.build(leaf_pkg, asset_id="ENV-EXPEDITION-SECRET-DOOR-LEAF")

    boards_body = MeshBuilder("secret_door_boards_主体")
    build_boards(boards_body)
    boards_obj = boards_body.build(boards_pkg, asset_id="ENV-EXPEDITION-SECRET-DOOR-BOARDS")

    # editable copies live in the hidden source collection
    for obj in (leaf_body_obj, leaf_light_obj, boards_obj):
        duplicate = obj.copy()
        duplicate.data = obj.data.copy()
        duplicate.name = obj.name + "_制作源"
        src.objects.link(duplicate)

    return {
        "leaf": (leaf_body_obj, leaf_light_obj),
        "boards": (boards_obj,),
        "stage": stage,
    }


# ---------------------------------------------------------------------------
# preview render
# ---------------------------------------------------------------------------
def render_previews(stage, objects):
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Filmic" if "Filmic" in [
        v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items
    ] else "Standard"

    world = bpy.data.worlds.new("预览世界")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.02, 0.022, 0.03, 1.0)
    bg.inputs[1].default_value = 1.0
    scene.world = world

    cam_data = bpy.data.cameras.new("预览相机")
    cam_data.lens = 42
    cam = bpy.data.objects.new("预览相机", cam_data)
    stage.objects.link(cam)
    scene.camera = cam

    def add_light(name, loc, energy, size=2.0, color=(1.0, 0.96, 0.9)):
        data = bpy.data.lights.new(name, type="AREA")
        data.energy = energy
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        stage.objects.link(obj)
        direction = Vector((0, -0.2, 1.3)) - Vector(loc)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        return obj

    add_light("主光_前上", (3.2, 4.6, 3.4), 520, 3.0)
    add_light("辅光_左侧", (-3.6, 2.4, 2.2), 150, 2.5, (0.72, 0.85, 1.0))
    add_light("轮廓光_背后", (-1.4, -4.2, 2.8), 120, 2.5, (0.78, 0.72, 1.0))
    # warm fill sitting where "the room beyond" would be, so the cavity reads as a
    # lit space instead of a black box
    add_light("门腔暖光", (0.0, -2.2, 1.75), 220, 2.0, (1.0, 0.72, 0.42))
    # a point light inside the cavity: makes the doorway glow spill onto the
    # floor in the preview. Lives in 90_展示环境, never exported.
    spill_data = bpy.data.lights.new("腔内溢光", type="POINT")
    spill_data.energy = 28
    spill_data.color = (1.0, 0.66, 0.34)
    spill_data.shadow_soft_size = 0.5
    spill = bpy.data.objects.new("腔内溢光", spill_data)
    spill.location = (0.0, -1.35, 1.25)
    stage.objects.link(spill)

    shots = [
        # boards visible: what the player sees from inside the level
        ("secret_door_boards_front", (0.0, 5.6, 1.55), (0.0, 0.0, 1.28), True),
        ("secret_door_boards_threequarter", (3.4, 4.4, 2.55), (0.0, 0.0, 1.25), True),
        # boards hidden: the door underneath, straight on so orientation is readable
        ("secret_door_leaf_front", (0.0, 6.0, 1.60), (0.0, 0.0, 1.30), False),
        ("secret_door_leaf_threequarter", (2.9, 4.2, 2.45), (0.0, -0.2, 1.25), False),
        ("secret_door_leaf_gap_closeup", (0.95, 1.95, 1.52), (0.35, -0.55, 1.35), False),
    ]

    saved = QA_DIR
    saved.mkdir(parents=True, exist_ok=True)

    for name, loc, target, show_boards in shots:
        for obj in objects["boards"]:
            obj.hide_render = not show_boards
        for obj in objects["leaf"]:
            obj.hide_render = False
        cam.location = loc
        direction = Vector(target) - Vector(loc)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(saved / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"RENDERED {name}")

    # keep working copies of the previews outside the project tree as well
    for png in saved.glob("*.png"):
        target = WORK_DIR / png.name
        if not target.exists():
            target.write_bytes(png.read_bytes())


# ---------------------------------------------------------------------------
# export + manifest
# ---------------------------------------------------------------------------
def export_components(objects):
    results = {}
    specs = [
        ("secret_door_leaf", objects["leaf"], "ENV-EXPEDITION-SECRET-DOOR-LEAF"),
        ("secret_door_boards", objects["boards"], "ENV-EXPEDITION-SECRET-DOOR-BOARDS"),
    ]
    for slug, objs, asset_id in specs:
        target_dir = RUNTIME_ROOT / slug
        target_dir.mkdir(parents=True, exist_ok=True)
        glb_path = target_dir / f"{slug}_visual_top3d.glb"
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.hide_set(False)
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        kwargs = dict(
            filepath=str(glb_path),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
            export_texcoords=True,
            export_normals=True,
            export_materials="EXPORT",
            export_cameras=False,
            export_lights=False,
            export_extras=True,
        )
        try:
            bpy.ops.export_scene.gltf(export_image_format="NONE", **kwargs)
        except TypeError:
            bpy.ops.export_scene.gltf(**kwargs)
        results[slug] = measure_glb(glb_path)
        print(f"EXPORTED {slug} -> {glb_path}")
        print(f"BOUNDS {slug} {json.dumps(results[slug], ensure_ascii=False)}")
    return results


def measure_glb(path):
    raw = path.read_bytes()
    _, _, total = struct.unpack("<III", raw[:12])
    off = 12
    chunks = {}
    while off < total:
        clen, ctype = struct.unpack("<II", raw[off:off + 8])
        chunks[ctype] = raw[off + 8:off + 8 + clen]
        off += 8 + clen
    doc = json.loads(chunks[0x4E4F534A].decode("utf-8"))
    lo = [1e9] * 3
    hi = [-1e9] * 3
    tris = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            acc = doc["accessors"][prim["attributes"]["POSITION"]]
            for i in range(3):
                lo[i] = min(lo[i], acc["min"][i])
                hi[i] = max(hi[i], acc["max"][i])
            if "indices" in prim:
                tris += doc["accessors"][prim["indices"]]["count"] // 3
    return {
        "bounds_lo": [round(v, 3) for v in lo],
        "bounds_hi": [round(v, 3) for v in hi],
        "size": [round(h - l, 3) for l, h in zip(lo, hi)],
        "triangles": tris,
        "materials": [m.get("name") for m in doc.get("materials", [])],
        "images": len(doc.get("images", []) or []),
        "attributes": sorted({k for m in doc.get("meshes", []) for pr in m["primitives"]
                              for k in pr["attributes"]}),
    }


def write_manifests(bounds, objects):
    leaf = bounds["secret_door_leaf"]
    boards = bounds["secret_door_boards"]

    def shift_of(obj):
        # Both components share one assembly frame, so the offset between them is
        # always zero. Kept as an explicit field for the prefab to assert on.
        return [0.0, 0.0, 0.0]

    leaf_shift = shift_of(objects["leaf"][0])
    boards_shift = shift_of(objects["boards"][0])
    common = {
        "library_id": "ENV-EXPEDITION-SECRET-DOOR-LIBRARY",
        "source_blend": str(BLEND_PATH),
        "palette_uv_layer": "PaletteUV",
        "shared_palette": str(PALETTE),
        "blender_forward_axis": "+Y",
        "blender_up_axis": "+Z",
        "origin_contract": "wall_face_bottom_center",
        "assembly_frame": {
            "shared_between": ["secret_door_leaf", "secret_door_boards"],
            "y_zero": "房间侧墙面",
            "boards_range_y": [round(BOARD_T * 0 + 0.0, 3), round(BOARD_T + 0.10, 3)],
            "frame_range_y": [-FRAME_D, 0.0],
            "cavity_range_y": [round(-(FRAME_D + CAVITY_D), 3), -FRAME_D],
            "note": "两件共用同一装配系，Godot 里都放在同一原点即可正确叠层，无需位移。",
        },
        "runtime_root": str(RUNTIME_ROOT),
    }
    leaf_manifest = dict(common, **{
        "asset_id": "ENV-EXPEDITION-SECRET-DOOR-LEAF",
        "slug": "secret_door_leaf",
        "name_zh": "隐藏门叶：门框 2.48×2.64m + 门腔 1.70m + 单扇半掩门（45°）+ 腔内自发光面",
        "component_family": "secret_door",
        "collection": "隐藏门叶_资产包",
        "root_object": "secret_door_leaf_主体",
        "assembly_shift_m": leaf_shift,
        "object_count": 2,
        "material_roles": [ROLE_METAL, ROLE_MATTE, ROLE_EMISSIVE],
        "material_count": 3,
        "bounds_size_m": leaf["size"],
        "opening_clear_m": [OPEN_W, OPEN_H],
        "cavity_depth_m": CAVITY_D,
        "leaf_open_deg": LEAF_OPEN_DEG,
        "collision_owner": "godot_prefab",
        "passage_owner": "godot_teleport_gate",
        "asset_ledger": "pending registration",
        "notes": "门腔深度 0.85m 用于容纳 42° 半掩门扇；墙体外表面在 Y=0，门腔全部位于 Y<0 一侧。",
    })
    boards_manifest = dict(common, **{
        "asset_id": "ENV-EXPEDITION-SECRET-DOOR-BOARDS",
        "slug": "secret_door_boards",
        "name_zh": "隐藏门木板封堵：5 条横板 + 2 条交叉斜撑 + 19 枚铁钉，可整体打掉",
        "component_family": "secret_door",
        "collection": "木板封堵_资产包",
        "root_object": "secret_door_boards_主体",
        "assembly_shift_m": boards_shift,
        "object_count": 1,
        "material_roles": [ROLE_MATTE, ROLE_METAL],
        "material_count": 2,
        "bounds_size_m": boards["size"],
        "board_count": 5,
        "brace_count": 2,
        "nail_count": 19,
        "collision_owner": "godot_prefab",
        "removable": True,
        "asset_ledger": "pending registration",
        "notes": "钉子朝 +Y 凸出；板面覆盖 2.36×2.50m，从 Y=0 起向外 0.12m。",
    })

    written = []
    for slug, payload in (("secret_door_leaf", leaf_manifest),
                          ("secret_door_boards", boards_manifest)):
        pkg_dir = PKG_ROOT / PKG_CATEGORY / slug
        pkg_dir.mkdir(parents=True, exist_ok=True)
        path = pkg_dir / "asset_manifest.json"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
        written.append((slug, path))

    plan = {
        "schema": "shellstorm2.battle.component_plan",
        "schema_version": 1,
        "status": "frozen_before_geometry",
        "version": "secret_door_v001",
        "block_id": "expedition",
        "level_id": "expedition_01",
        "design_scope": "scene_art",
        "asset_ledger": "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx",
        "registration_status": "已产出源与运行 GLB；账本登记待办",
        "component_budget": {"limit": 50, "planned": 2, "remaining": 48},
        "components": [
            {"slug": "secret_door_leaf", "family": "secret_door",
             "purpose": "半掩门 + 内腔透光，隐藏门被打破后可见"},
            {"slug": "secret_door_boards", "family": "secret_door",
             "purpose": "外侧钉死木板，可打掉，打掉后露出门"},
        ],
        "dimension_contract": {
            "opening_clear_m": [OPEN_W, OPEN_H],
            "frame_depth_m": FRAME_D,
            "cavity_depth_m": CAVITY_D,
            "leaf_open_deg": LEAF_OPEN_DEG,
            "board_cover_m": [BOARD_W, round(BOARD_Z1 - BOARD_Z0, 3)],
        },
        "derivation": {
            "opening_source": "office_room/door_wall/door_wall_root_top3d.tscn 实测门洞 2.2×2.5",
            "wall_thickness_m": 1.11,
            "note": "site x 坐标落在 5m 墙模块拼缝上，因此采用贴面门框方案，不改 5m 网格模块。",
        },
        "style": {
            "palette": "设施低亮多巴胺色盘_10x10_512.png",
            "roles": [ROLE_METAL, ROLE_MATTE, ROLE_GLOSS, ROLE_EMISSIVE],
        },
    }
    (SRC_DIR / "component_plan.json").write_text(
        json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # spec 6.3: Collection / disk manifests / catalog must agree on package count & names
    entries = []
    for slug, path in written:
        payload = json.loads(path.read_text(encoding="utf-8"))
        entries.append({
            "slug": slug,
            "asset_id": payload["asset_id"],
            "name_zh": payload["name_zh"],
            "collection": payload["collection"],
            "category": PKG_CATEGORY,
            "manifest": str(path.relative_to(SRC_DIR)).replace("\\", "/"),
            "glb": f"assets/art/environments/tower_zones/expedition/components/common_components/{slug}/{slug}_visual_top3d.glb",
            "bounds_size_m": payload["bounds_size_m"],
            "material_roles": payload["material_roles"],
        })
    catalog = {
        "schema": "shellstorm2.battle.component_catalog",
        "schema_version": 1,
        "version": "secret_door_v001",
        "level_id": "expedition_01",
        "block_id": "expedition",
        "package_root": f"component_packages_v001/{PKG_CATEGORY}",
        "package_count": len(entries),
        "collections": ["隐藏门叶_资产包", "木板封堵_资产包"],
        "entries": entries,
    }
    (SRC_DIR / "component_catalog.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = ["secret_door/v001/", "├─ secret_door_v001.blend"]
    for slug, _ in written:
        lines.append(f"├─ component_packages_v001/{PKG_CATEGORY}/{slug}/")
        lines.append("│  └─ asset_manifest.json")
    lines.append("├─ component_plan.json")
    lines.append("├─ component_catalog.json")
    lines.append("└─ qa/")
    (SRC_DIR / "component_tree.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(
        "MANIFESTS_WRITTEN packages=%d collections=%d catalog_entries=%d"
        % (len(written), len(catalog["collections"]), len(catalog["entries"]))
    )


def main():
    os.makedirs(SRC_DIR, exist_ok=True)
    os.makedirs(QA_DIR, exist_ok=True)
    assembled = assemble()
    objects = {"leaf": assembled["leaf"], "boards": assembled["boards"]}

    # Save first so the .blend has a real path: preview renders resolve the
    # palette through it, and `//` relinking below becomes meaningful.
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"SAVED {BLEND_PATH}")

    if not os.environ.get("SECRET_DOOR_SKIP_RENDER"):
        render_previews(assembled["stage"], objects)

    relink_palette_relative()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"RESAVED {BLEND_PATH}")

    bounds = {}
    if not os.environ.get("SECRET_DOOR_SKIP_EXPORT"):
        bounds = export_components(objects)
        write_manifests(bounds, objects)

    summary = {
        "blend": str(BLEND_PATH),
        "components": {
            "leaf": {"objects": [o.name for o in objects["leaf"]]},
            "boards": {"objects": [o.name for o in objects["boards"]]},
        },
        "bounds": bounds,
        "materials": sorted(MATERIALS.keys()),
    }
    print("SUMMARY " + json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
