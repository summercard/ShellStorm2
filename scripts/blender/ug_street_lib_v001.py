"""地下街区 v001 —— 几何/材质/色盘 UV 基础库。

只做四件事：
1. 用纯 Python 顶点/面累加器拼几何（不依赖 bpy.ops，主线程秒级完成，可幂等重跑）。
2. 四个共享材质角色 + 外链公共色盘（Closest）。
3. 逐面 PaletteUV 岛：每个面在所属色格内生成一个有面积的正多边形小岛。
4. 把累加器落成 Blender 网格对象（主体 / 自发光分离）。

坐标：Z 向上，地面走面 Z=0，组件局部原点 = 底面中心。
"""

from __future__ import annotations

import math

import bpy

PALETTE_PATH = r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\shared\palette\设施低亮多巴胺色盘_10x10_512.png"

ROLE_METAL = "01_精工金属_紫色骨架"
ROLE_MATTE = "02_细腻哑光_青绿大面"
ROLE_GLOSS = "03_清漆反光_紫粉点缀"
ROLE_EMIT = "04_柔和自发光_UI灯光"
ROLES = (ROLE_METAL, ROLE_MATTE, ROLE_GLOSS, ROLE_EMIT)

# ---- 色盘格（列 0-9 左→右，行 0-9 上→下，对应图内 R1..R10）----
C_BLACK = (0, 0)      # #090813
C_COAL = (9, 9)       # #C5CED8 浅蓝灰（灰阶最亮）
C_GREY_MID = (8, 9)   # #716D63 暖灰（旧漆白线）
C_GREY_COOL = (7, 9)  # #3B0B1E
C_VAPOR_DEEP = (9, 4)   # #4D5E72 冷蓝灰
C_VAPOR_MID = (9, 6)    # #718195
C_VAPOR_HIGH = (9, 7)   # #8998AA

C_NAVY = (1, 6)       # #0A1126
C_NAVY2 = (2, 9)      # #16153A
C_BLUE = (5, 6)       # #1B3B6F
C_BLUE_DARK = (3, 9)  # #0A232D
C_INDIGO = (2, 0)     # #311B73
C_PURPLE = (3, 7)     # #290F52
C_PURPLE2 = (4, 8)    # #56115F
C_MAGENTA = (3, 8)    # #490D4F

C_BRICK = (3, 1)      # #5A0E1A
C_BRICK2 = (5, 1)     # #6E1C2A
C_CRIMSON = (5, 0)    # #731B33 霓虹粉红基色
C_RUST = (5, 2)      # #70340A
C_AMBER = (6, 0)      # #736005
C_AMBER2 = (7, 3)     # #726520
C_TEAL = (5, 5)       # #145F56
C_TEAL_DARK = (4, 5)  # #09534B
C_GREEN = (6, 4)      # #21643A
C_MAUVE = (8, 8)      # #704C5F

ISLAND_RADIUS = 0.028  # 色格 0.1 宽 → 岛直径 0.056，占 56%


def _normal(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    leng = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return nx / leng, ny / leng, nz / leng


class Geo:
    """顶点/面累加器。所有零件都是凸体，法线按「背离零件质心」自动定向。"""

    def __init__(self) -> None:
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.frole: list[str] = []
        self.fcell: list[tuple[int, int]] = []

    # ---------- 基础 ----------
    def raw(self, verts, faces, role, cell):
        base = len(self.verts)
        verts = [tuple(float(v) for v in p) for p in verts]
        n = len(verts)
        cx = sum(p[0] for p in verts) / n
        cy = sum(p[1] for p in verts) / n
        cz = sum(p[2] for p in verts) / n
        self.verts.extend(verts)
        for f in faces:
            f = list(f)
            pts = [verts[i] for i in f]
            if len(pts) >= 3:
                nor = _normal(pts[0], pts[1], pts[2])
                fx = sum(p[0] for p in pts) / len(pts)
                fy = sum(p[1] for p in pts) / len(pts)
                fz = sum(p[2] for p in pts) / len(pts)
                if nor[0] * (fx - cx) + nor[1] * (fy - cy) + nor[2] * (fz - cz) < 0:
                    f.reverse()
            self.faces.append(tuple(base + i for i in f))
            self.frole.append(role)
            self.fcell.append(cell)

    def box(self, x0, x1, y0, y1, z0, z1, role, cell):
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        z0, z1 = min(z0, z1), max(z0, z1)
        v = [
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
        ]
        f = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.raw(v, f, role, cell)

    def boxc(self, cx, cy, z0, sx, sy, sz, role, cell):
        self.box(cx - sx / 2, cx + sx / 2, cy - sy / 2, cy + sy / 2, z0, z0 + sz, role, cell)

    def cyl(self, cx, cy, z0, z1, r, role, cell, seg=12, r2=None):
        r2 = r if r2 is None else r2
        z0, z1 = min(z0, z1), max(z0, z1)
        v = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((cx + r * math.cos(a), cy + r * math.sin(a), z0))
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((cx + r2 * math.cos(a), cy + r2 * math.sin(a), z1))
        f = [tuple(range(seg)), tuple(range(seg, 2 * seg))]
        for i in range(seg):
            j = (i + 1) % seg
            f.append((i, j, seg + j, seg + i))
        self.raw(v, f, role, cell)

    def cyl_x(self, x0, x1, cy, cz, r, role, cell, seg=12):
        v = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((x0, cy + r * math.cos(a), cz + r * math.sin(a)))
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((x1, cy + r * math.cos(a), cz + r * math.sin(a)))
        f = [tuple(range(seg)), tuple(range(seg, 2 * seg))]
        for i in range(seg):
            j = (i + 1) % seg
            f.append((i, j, seg + j, seg + i))
        self.raw(v, f, role, cell)

    def cyl_y(self, y0, y1, cx, cz, r, role, cell, seg=12):
        v = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((cx + r * math.cos(a), y0, cz + r * math.sin(a)))
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((cx + r * math.cos(a), y1, cz + r * math.sin(a)))
        f = [tuple(range(seg)), tuple(range(seg, 2 * seg))]
        for i in range(seg):
            j = (i + 1) % seg
            f.append((i, j, seg + j, seg + i))
        self.raw(v, f, role, cell)

    def prism(self, pts, z0, z1, role, cell):
        z0, z1 = min(z0, z1), max(z0, z1)
        n = len(pts)
        v = [(p[0], p[1], z0) for p in pts] + [(p[0], p[1], z1) for p in pts]
        f = [tuple(range(n)), tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            f.append((i, j, n + j, n + i))
        self.raw(v, f, role, cell)

    def prism_xz(self, pts, y0, y1, role, cell):
        """XZ 平面多边形沿 Y 拉伸（立面上的拱券、门洞、招牌板）。"""
        y0, y1 = min(y0, y1), max(y0, y1)
        n = len(pts)
        v = [(p[0], y0, p[1]) for p in pts] + [(p[0], y1, p[1]) for p in pts]
        f = [tuple(range(n)), tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            f.append((i, j, n + j, n + i))
        self.raw(v, f, role, cell)

    def arc_xz(self, cx, cz, r_in, r_out, y0, y1, a0, a1, role, cell, seg=8):
        """XZ 平面扇形环（拱券石）。角度从 +X 轴逆时针。"""
        for i in range(seg):
            a = a0 + (a1 - a0) * i / seg
            b = a0 + (a1 - a0) * (i + 1) / seg
            quad = [
                (cx + r_in * math.cos(a), cz + r_in * math.sin(a)),
                (cx + r_out * math.cos(a), cz + r_out * math.sin(a)),
                (cx + r_out * math.cos(b), cz + r_out * math.sin(b)),
                (cx + r_in * math.cos(b), cz + r_in * math.sin(b)),
            ]
            self.prism_xz(quad, y0, y1, role, cell)

    def beam(self, p0, p1, w, t, role, cell):
        """任意方向矩形截面梁：沿 p0→p1，宽 w，厚 t。"""
        ax = p1[0] - p0[0]
        ay = p1[1] - p0[1]
        az = p1[2] - p0[2]
        leng = math.sqrt(ax * ax + ay * ay + az * az) or 1.0
        d = (ax / leng, ay / leng, az / leng)
        up = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
        sx = (d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2], d[0] * up[1] - d[1] * up[0])
        sl = math.sqrt(sum(v * v for v in sx)) or 1.0
        sx = (sx[0] / sl, sx[1] / sl, sx[2] / sl)
        sy = (d[1] * sx[2] - d[2] * sx[1], d[2] * sx[0] - d[0] * sx[2], d[0] * sx[1] - d[1] * sx[0])
        hw, ht = w / 2, t / 2
        v = []
        for sign in (-1, 1):
            for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                v.append(tuple(
                    p0[k] + d[k] * (0 if sign < 0 else leng)
                    + sx[k] * hw * su + sy[k] * ht * sv
                    for k in range(3)
                ))
        f = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.raw(v, f, role, cell)

    def rbox(self, cx, cy, z0, sx, sy, sz, role, cell, rz=0.0):
        """绕 Z 旋转的方盒（用小段近似整体旋转）。"""
        if abs(rz) < 1e-9:
            self.boxc(cx, cy, z0, sx, sy, sz, role, cell)
            return
        ca, sa = math.cos(rz), math.sin(rz)
        pts = [(-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)]
        rot = [(cx + p[0] * ca - p[1] * sa, cy + p[0] * sa + p[1] * ca) for p in pts]
        self.prism(rot, z0, z0 + sz, role, cell)

    def panel(self, x0, x1, y0, y1, z0, z1, role, cell):
        self.box(x0, x1, y0, y1, z0, z1, role, cell)

    def arc_ring(self, cx, cy, r_in, r_out, z0, z1, a0, a1, role, cell, seg=10):
        """扇形环：用于拱券、通风口内圈。角度为弧度。"""
        pts = []
        for i in range(seg + 1):
            a = a0 + (a1 - a0) * i / seg
            pts.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a)))
        for i in range(seg, -1, -1):
            a = a0 + (a1 - a0) * i / seg
            pts.append((cx + r_in * math.cos(a), cy + r_in * math.sin(a)))
        # 扇形环不自闭合（首尾相连会封成整块）→ 用四边形带，逐段独立薄块
        for i in range(seg):
            a = a0 + (a1 - a0) * i / seg
            b = a0 + (a1 - a0) * (i + 1) / seg
            quad = [
                (cx + r_in * math.cos(a), cy + r_in * math.sin(a)),
                (cx + r_out * math.cos(a), cy + r_out * math.sin(a)),
                (cx + r_out * math.cos(b), cy + r_out * math.sin(b)),
                (cx + r_in * math.cos(b), cy + r_in * math.sin(b)),
            ]
            self.prism(quad, z0, z1, role, cell)

    # ---------- 落网格 ----------
    def build_mesh(self, name, materials):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        if len(me.polygons) != len(self.faces):
            raise RuntimeError(
                "%s: 面数不一致（from_pydata %d / 期望 %d），拒绝继续以免色盘错位"
                % (name, len(me.polygons), len(self.faces))
            )
        for mat in materials:
            me.materials.append(mat)
        slot = {mat.name: i for i, mat in enumerate(materials)}
        for poly in me.polygons:
            role = self.frole[poly.index]
            poly.material_index = slot.get(role, 0)
            poly.use_smooth = False
        layer = me.uv_layers.new(name="PaletteUV")
        for poly in me.polygons:
            cell = self.fcell[poly.index]
            loops = list(poly.loop_indices)
            n = len(loops)
            cu = (cell[0] + 0.5) / 10.0
            cv = 1.0 - (cell[1] + 0.5) / 10.0
            for k, li in enumerate(loops):
                ang = 2 * math.pi * k / n + math.pi / 4
                layer.data[li].uv = (cu + ISLAND_RADIUS * math.cos(ang), cv + ISLAND_RADIUS * math.sin(ang))
        me.uv_layers.active = layer
        layer.active_render = True
        me.update()
        return me


# ---------------- 场景 / 材质 ----------------

def purge_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras,
                  bpy.data.curves, bpy.data.node_groups):
        for item in list(block):
            block.remove(item)
    for img in list(bpy.data.images):
        if img.name not in ("Render Result", "Viewer Node"):
            bpy.data.images.remove(img)


def _palette_node(nt, x, y):
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    uv.location = (x, y)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(PALETTE_PATH, check_existing=True)
    tex.interpolation = "Closest"
    tex.extension = "CLIP"
    tex.location = (x + 200, y)
    nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])
    return tex


def ensure_materials():
    mats = {}
    specs = {
        ROLE_METAL: dict(metallic=0.88, roughness=0.26, coat=0.15),
        ROLE_MATTE: dict(metallic=0.06, roughness=0.70, coat=0.0),
        ROLE_GLOSS: dict(metallic=0.18, roughness=0.13, coat=0.68),
        ROLE_EMIT: dict(metallic=0.0, roughness=0.38, coat=0.0, emission=2.4),
    }
    for role in ROLES:
        spec = specs[role]
        mat = bpy.data.materials.get(role) or bpy.data.materials.new(role)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        out.location = (520, 0)
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.location = (180, 0)
        tex = _palette_node(nt, -420, 0)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = spec["metallic"]
        bsdf.inputs["Roughness"].default_value = spec["roughness"]
        if "Coat Weight" in bsdf.inputs:
            bsdf.inputs["Coat Weight"].default_value = spec["coat"]
        if "Coat Roughness" in bsdf.inputs:
            bsdf.inputs["Coat Roughness"].default_value = 0.08
        if spec.get("emission"):
            strength = bsdf.inputs.get("Emission Strength")
            if strength is not None:
                strength.default_value = spec["emission"]
            ecol = bsdf.inputs.get("Emission Color")
            if ecol is not None:
                nt.links.new(tex.outputs["Color"], ecol)
            if "Base Color" in bsdf.inputs and tex.outputs["Color"].is_linked:
                # 自发光件底色压暗，避免正面泛白
                dark = nt.nodes.new("ShaderNodeMixRGB")
                dark.blend_type = "MULTIPLY"
                dark.inputs[0].default_value = 1.0
                dark.inputs[2].default_value = (0.10, 0.10, 0.10, 1.0)
                dark.location = (-60, -120)
                nt.links.new(tex.outputs["Color"], dark.inputs[1])
                nt.links.new(dark.outputs["Color"], bsdf.inputs["Base Color"])
        if spec.get("alpha") is not None:
            bsdf.inputs["Alpha"].default_value = spec["alpha"]
            for attr, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
                if hasattr(mat, attr):
                    try:
                        setattr(mat, attr, value)
                    except (TypeError, AttributeError):
                        pass
            if hasattr(mat, "use_transparent_shadow"):
                mat.use_transparent_shadow = True
            mat.use_backface_culling = False
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        mat.use_backface_culling = False
        mats[role] = mat
    return mats


def new_collection(name, parent=None, hide=False):
    coll = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(coll)
    coll.hide_viewport = hide
    coll.hide_render = hide
    return coll


def link_mesh(coll, name, geo, mats):
    body_roles = [r for r in (ROLE_METAL, ROLE_MATTE, ROLE_GLOSS)]
    has_body = any(r in body_roles for r in geo.frole)
    has_emit = ROLE_EMIT in geo.frole
    if has_body:
        me = geo.build_mesh(name + "_主体", [mats[r] for r in body_roles])
        obj = bpy.data.objects.new(name + "_主体", me)
        coll.objects.link(obj)
    for role, suffix in ((ROLE_EMIT, "_UI灯光自发光"),):
        if role not in geo.frole:
            continue
        keep_faces = [f for f, r in zip(geo.faces, geo.frole) if r == role]
        keep_cells = [c for c, r in zip(geo.fcell, geo.frole) if r == role]
        used = sorted({i for f in keep_faces for i in f})
        remap = {old: new for new, old in enumerate(used)}
        sub = Geo()
        sub.verts = [geo.verts[i] for i in used]
        sub.faces = [tuple(remap[i] for i in f) for f in keep_faces]
        sub.frole = [role] * len(keep_faces)
        sub.fcell = keep_cells
        me = sub.build_mesh(name + suffix, [mats[role]])
        obj = bpy.data.objects.new(name + suffix, me)
        coll.objects.link(obj)
    return


def bounds_of(geo):
    xs = [v[0] for v in geo.verts]
    ys = [v[1] for v in geo.verts]
    zs = [v[2] for v in geo.verts]
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


def poly_count(geo):
    return len(geo.faces)
