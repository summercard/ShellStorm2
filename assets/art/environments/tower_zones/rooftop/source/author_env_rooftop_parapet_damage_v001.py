"""Author the three damaged variants of the rooftop parapet straight run.

Source blend : assets/art/environments/tower_zones/rooftop/source/reference_components/v002/
               天台区块_参考组件库_v002.blend   (opened read-only, never written back)
Run          : blender.exe --background <blend> --python-exit-code 1 --python this.py
Output       : ../../components/env_rooftop_ref_parapet_dmg_{a,b,c}_top3d.glb

Why procedural
--------------
Each variant is carved out of a private copy of 女儿墙直段_水泥结构_制作 by
boolean-differencing a handful of chaotic "eroder" solids. Everything (eroder shapes,
seeds, carve order) lives in RECIPES below, so the three patterns stay reproducible
and the pristine reference library keeps its single role as the art truth.

The module is a kit, not a slab — and that decides how the carve has to work
--------------------------------------------------------------------------
女儿墙直段_主体 is not one solid: it is 22 separate closed beveled blocks (a 5 x 0.50 x
0.24 base plinth, a 0.036 thick divider band, ten 0.5m middle body tiles and ten 0.5m
coping tiles), built so the profile reads as plinth -> recessed panel -> proud band ->
coping. Feeding that whole kit to one EXACT boolean destroys it: the solver's
preprocessing welds the 22 abutting shells and silently deletes the ten middle body
tiles (measured: 512 -> 272 verts, 4.52 -> 1.25 m^3, and the ten tiles' 31.53 m^2 of
faces just vanish — even when the cutter never touches the module at all).

So the carve runs per block: the kit is split into its loose parts, and each block is
booleaned only against the eroders that actually overlap it. A single beveled box is
rock solid under EXACT boolean, the blocks stay separate shells (no cross-shell
welding), and the kit structure survives.

Damage kinds (chosen by the project owner)
------------------------------------------
dmg_a 崩顶  crown spall   : the top edge is bitten away in three notches of falling
                            size, so the parapet breaks the skyline in steps.
dmg_b 贯穿  breach        : two jagged holes cut clean through the 0.43m panel
                            thickness; the eroders are wider than the wall in Y on
                            purpose, otherwise the cutter would only dent one face.
                            The plinth and the coping stay whole, so the hole reads as
                            framed by the surviving courses.
dmg_c 塌脚  base collapse : a middle span is knocked down to a ~0.5m stump (its stub
                            is still bedded in the plinth, so nothing appears to
                            hang), plus the plinth is hollowed out near the other end
                            by a shallow notch that keeps an 0.08m web behind it.

Contracts held by every exported variant
----------------------------------------
origin   : identical to the intact module — XY-centred, base face at local Z=0
envelope : X/Y AABB untouched (+-2.500 / +-0.250), Z stays [0, 1.800]
ends     : |x| >= END_BAND_START is bit-identical to the intact mesh, so any two
           segments still butt together with no gap and no step
palette  : every loop UV stays inside the concrete swatch box, so broken faces keep
           the concrete colour instead of sampling a neighbouring palette cell
volume   : strictly smaller than the intact mesh (asserted — a silent no-op carve
           would otherwise ship three "damaged" files identical to the intact one)
"""

from pathlib import Path
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

SOURCE_OBJECT = "女儿墙直段_水泥结构_制作"
SOURCE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SOURCE_DIR.parent / "components"
# 组件包按积木拼装，逐块布尔是本脚本的前提；积木数量变了说明库里换了做法，
# 需要人工确认后再改这个常量，不能让它悄悄漂移。
SOURCE_KIT_PART_COUNT = 22

# ---- intact-module contract, measured from the v002 package -------------------
MODULE_HALF_LENGTH = 2.5
MODULE_HALF_THICKNESS = 0.25
MODULE_HEIGHT = 1.8
# Damage must stay out of this band at either end or consecutive segments stop lining
# up: the whole point of the variants is that they remain interchangeable with the
# intact module in the exterior-wall run.
END_MARGIN = 0.45
END_BAND_START = MODULE_HALF_LENGTH - END_MARGIN
# The eroders themselves are bounded too: even after their noise jitter overshoots,
# the clean end band must still be at least this wide.
ERODER_X_LIMIT = 2.15
# Palette swatch used by every concrete face in the intact module (measured: U in
# [0.923, 0.977], V in [0.123, 0.477]; all six face normals average to U=0.950,
# V=0.218). Broken faces interpolate inside that box, and the clamp below keeps
# floating-point drift from pushing a loop UV into the neighbouring palette cell.
PALETTE_U = (0.923, 0.977)
PALETTE_V = (0.123, 0.477)

RECIPES = [
    {
        "key": "dmg_a",
        "label": "崩顶 crown spall",
        "node": "女儿墙直段破损A_主体",
        "filename": "env_rooftop_ref_parapet_dmg_a_top3d.glb",
        "eroders": [
            {"center": (-0.90, 0.0, 1.80), "size": (1.50, 0.90, 1.10), "lump": 0.22, "seed": 11},
            {"center": (0.85, 0.0, 1.85), "size": (0.90, 0.90, 0.80), "lump": 0.24, "seed": 12},
            {"center": (1.58, 0.0, 1.90), "size": (0.50, 0.80, 0.50), "lump": 0.26, "seed": 13},
        ],
    },
    {
        "key": "dmg_b",
        "label": "贯穿 breach",
        "node": "女儿墙直段破损B_主体",
        "filename": "env_rooftop_ref_parapet_dmg_b_top3d.glb",
        "eroders": [
            {"center": (-0.55, 0.0, 0.95), "size": (0.95, 0.80, 0.75), "lump": 0.22, "seed": 21},
            {"center": (1.15, 0.0, 1.25), "size": (0.50, 0.80, 0.45), "lump": 0.24, "seed": 22},
        ],
    },
    {
        "key": "dmg_c",
        "label": "塌脚 base collapse",
        "node": "女儿墙直段破损C_主体",
        "filename": "env_rooftop_ref_parapet_dmg_c_top3d.glb",
        "eroders": [
            # 中段塌落：从 0.55m 往上整段挖掉，残根仍嵌在底座板里，不会出现悬空块。
            {"center": (0.55, 0.0, 1.55), "size": (1.80, 0.90, 2.00), "lump": 0.22, "seed": 31},
            # 墙脚掏空：只掏底座板下部 0.16m，留 0.08m 腹板，底座板不断开。
            {"center": (-1.42, 0.0, 0.005), "size": (0.90, 0.90, 0.31), "lump": 0.22, "seed": 32},
        ],
    },
]


def _require(condition, message):
    if not condition:
        raise RuntimeError(message)


def _world_aabb(obj):
    """World AABB from the vertices themselves.

    Not obj.bound_box: that cached value is stale (all-zero) for objects a fresh
    mesh.separate or a not-yet-updated depsgraph has just produced, which would make
    every overlap test fail and silently carve nothing.
    """
    matrix = obj.matrix_world
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for vert in obj.data.vertices:
        world = matrix @ vert.co
        for axis in range(3):
            mins[axis] = min(mins[axis], world[axis])
            maxs[axis] = max(maxs[axis], world[axis])
    return mins, maxs


def _aabbs_overlap(mins_a, maxs_a, mins_b, maxs_b, slack=0.0):
    for axis in range(3):
        if mins_a[axis] > maxs_b[axis] + slack:
            return False
        if maxs_a[axis] < mins_b[axis] - slack:
            return False
    return True


def _mesh_aabb(mesh):
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for vert in mesh.vertices:
        for axis in range(3):
            mins[axis] = min(mins[axis], vert.co[axis])
            maxs[axis] = max(maxs[axis], vert.co[axis])
    return mins, maxs


def _band_coords(mesh, start_abs_x):
    """Coordinate signature of everything inside the band that tiling depends on."""
    return sorted(
        (round(vert.co.x, 5), round(vert.co.y, 5), round(vert.co.z, 5))
        for vert in mesh.vertices
        if abs(vert.co.x) >= start_abs_x
    )


def _shell_volumes(mesh):
    """Signed volume of every shell.

    Signed on purpose: a block whose winding got flipped by a carve shows up as a
    negative volume instead of hiding inside a sum of absolutes.
    """
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    seen = set()
    volumes = []
    for face in bm.faces:
        if face.index in seen:
            continue
        component = []
        stack = [face]
        while stack:
            current = stack.pop()
            if current.index in seen:
                continue
            seen.add(current.index)
            component.append(current)
            for edge in current.edges:
                for neighbour in edge.link_faces:
                    if neighbour.index not in seen:
                        stack.append(neighbour)
        volume = 0.0
        for current in component:
            # face.loops 是 BMLoopSeq 不可迭代；face.verts 按绕序给出顶点，够用。
            verts = list(current.verts)
            origin = verts[0].co
            for index in range(1, len(verts) - 1):
                volume += origin.dot(verts[index].co.cross(verts[index + 1].co)) / 6.0
        volumes.append(volume)
    bm.free()
    return volumes


def _build_eroder(spec, tag):
    """Chaotic solid used as a boolean cutter."""
    size = spec["size"]
    amplitude = float(spec.get("lump", 0.22)) * min(size)
    mesh = bpy.data.meshes.new("eroder_%s" % tag)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    # 先加密：5cm 级的沟壑需要足够的面密度才切得出来。
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
    for vert in bm.verts:
        vert.co.x *= size[0]
        vert.co.y *= size[1]
        vert.co.z *= size[2]
    bm.normal_update()
    rnd = random.Random(int(spec["seed"]))
    phase = Vector(
        (rnd.uniform(-80.0, 80.0), rnd.uniform(-80.0, 80.0), rnd.uniform(-80.0, 80.0))
    )
    for vert in bm.verts:
        coarse = noise.noise(vert.co * 1.6 + phase)
        fine = noise.noise(vert.co * 4.3 + phase * 1.7)
        vert.co += Vector(vert.normal) * ((coarse * 0.72 + fine * 0.28) * amplitude)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("eroder_%s" % tag, mesh)
    obj.location = Vector(spec["center"])
    obj.display_type = "WIRE"
    bpy.context.scene.collection.objects.link(obj)
    # matrix_world 要等 depsgraph 刷新才会带上 location；不刷新的话下面的相交判定
    # 会把每个生成器都当成躺在原点，于是所有积木都被判为"够不着"、一个都不切。
    bpy.context.view_layer.update()
    return obj


def _assert_eroder_reach(eroder, label):
    """Guard the eroder recipes instead of trusting hand-arithmetic.

    The noise jitter makes an eroder reach past its nominal half-size, and a cutter
    that overshoots into the end band would put new vertices there — that is exactly
    the failure that breaks the "any two segments still butt together" contract.
    """
    mins, maxs = _world_aabb(eroder)
    _require(
        abs(mins[0]) <= ERODER_X_LIMIT and abs(maxs[0]) <= ERODER_X_LIMIT,
        "%s: 生成器 X 触及 [%.4f, %.4f]，超出 ±%.2f 会啃进端头净空区"
        % (label, mins[0], maxs[0], ERODER_X_LIMIT),
    )
    print(
        "  eroder %-10s x=[%+.4f, %+.4f] y=[%+.4f, %+.4f] z=[%+.4f, %+.4f]"
        % (label, mins[0], maxs[0], mins[1], maxs[1], mins[2], maxs[2])
    )


def _isolate(obj, collection_name):
    """Park an object in a private collection so loose-part splitting is traceable."""
    collection = bpy.data.collections.new(collection_name)
    bpy.context.scene.collection.children.link(collection)
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    return collection


def _split_loose_parts(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")


def _carve_block(part, eroders, label):
    """Boolean one block against only the eroders that reach it."""
    part_mins, part_maxs = _world_aabb(part)
    cuts = 0
    for index, eroder in enumerate(eroders):
        eroder_mins, eroder_maxs = _world_aabb(eroder)
        if not _aabbs_overlap(part_mins, part_maxs, eroder_mins, eroder_maxs):
            continue
        modifier = part.modifiers.new("erode_%02d" % index, "BOOLEAN")
        modifier.operation = "DIFFERENCE"
        modifier.solver = "EXACT"
        modifier.object = eroder
        bpy.context.view_layer.objects.active = part
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        cuts += 1
    return cuts


def _join_parts(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    keeper = parts[0]
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = keeper
    if len(parts) > 1:
        bpy.ops.object.join()
    keeper.name = name
    keeper.data.name = name
    return keeper


def _release_work_collection(collection, keeper):
    collection.objects.unlink(keeper)
    bpy.context.scene.collection.objects.link(keeper)
    bpy.data.collections.remove(collection)


def _inside_damage(co, damage_regions, slack=1.4, pad=0.06):
    """Is this vertex within the reach of one of the eroders?"""
    for center, size in damage_regions:
        if (
            abs(co.x - center[0]) <= size[0] * 0.5 * slack + pad
            and abs(co.y - center[1]) <= size[1] * 0.5 * slack + pad
            and abs(co.z - center[2]) <= size[2] * 0.5 * slack + pad
        ):
            return True
    return False


def _roughen_fracture(bm, amplitude, seed, damage_regions):
    """Break up the boolean's flat cutter facets so they read as broken concrete.

    The intact module bevels every edge, so their normals are NOT axis-aligned and a
    pure "non-axis-aligned face" test would also match pristine bevel faces — that
    would silently reshape the undamaged silhouette. Every vertex displaced here must
    therefore sit inside an eroder's reach, which is where the boolean actually cut.
    """
    axes = (
        Vector((1.0, 0.0, 0.0)), Vector((-1.0, 0.0, 0.0)),
        Vector((0.0, 1.0, 0.0)), Vector((0.0, -1.0, 0.0)),
        Vector((0.0, 0.0, 1.0)), Vector((0.0, 0.0, -1.0)),
    )
    fracture_verts = []
    for face in bm.faces:
        aligned = max(abs(face.normal.dot(axis)) for axis in axes)
        if aligned >= 0.985:
            continue
        for vert in face.verts:
            if abs(vert.co.x) >= END_BAND_START:
                continue
            if _inside_damage(vert.co, damage_regions):
                fracture_verts.append(vert)
    if not fracture_verts:
        return 0
    rnd = random.Random(seed)
    phase = Vector(
        (rnd.uniform(-60.0, 60.0), rnd.uniform(-60.0, 60.0), rnd.uniform(-60.0, 60.0))
    )
    for vert in fracture_verts:
        coarse = noise.noise(vert.co * 9.0 + phase)
        vert.co += Vector(vert.normal) * (coarse * amplitude)
    return len(fracture_verts)


def _clamp_envelope(bm):
    """Pull the carve and the roughening back inside the intact module's envelope.

    Two separate reasons: boolean cuts reach below the floor slab while the module's
    base face has to stay at Z=0, and the roughening can nudge a surviving top-edge
    vertex past 1.80m. Clamping X is a no-op for damage (it never gets near +-2.5) and
    is pure insurance for the tiling contract.
    """
    for vert in bm.verts:
        vert.co.x = min(max(vert.co.x, -MODULE_HALF_LENGTH), MODULE_HALF_LENGTH)
        vert.co.y = min(max(vert.co.y, -MODULE_HALF_THICKNESS), MODULE_HALF_THICKNESS)
        vert.co.z = min(max(vert.co.z, 0.0), MODULE_HEIGHT)


def _clamp_palette_uv(bm, uv_layer):
    # bm.loops 是 BMLoopSeq，不可直接迭代；按面取 loop 才能遍历到全部 UV。
    for face in bm.faces:
        for loop in face.loops:
            uv = loop[uv_layer].uv
            uv.x = min(max(uv.x, PALETTE_U[0]), PALETTE_U[1])
            uv.y = min(max(uv.y, PALETTE_V[0]), PALETTE_V[1])


def _prune_degenerate_shells(bm, min_volume=1e-6):
    """Drop shells the carve left with no volume at all.

    A through-cut against the kit's abutting blocks can leave a zero-thickness sliver
    behind. One cubic centimetre at module scale is invisible, but it still counts as
    a shell and therefore trips the "no negative-volume shell" check below — and the
    check must stay strict, because a real winding flip looks like a whole block
    turning negative.
    """
    bm.faces.ensure_lookup_table()
    seen = set()
    doomed = []
    for face in bm.faces:
        if face.index in seen:
            continue
        component = []
        stack = [face]
        while stack:
            current = stack.pop()
            if current.index in seen:
                continue
            seen.add(current.index)
            component.append(current)
            for edge in current.edges:
                for neighbour in edge.link_faces:
                    if neighbour.index not in seen:
                        stack.append(neighbour)
        volume = 0.0
        for current in component:
            verts = list(current.verts)
            origin = verts[0].co
            for index in range(1, len(verts) - 1):
                volume += origin.dot(verts[index].co.cross(verts[index + 1].co)) / 6.0
        if abs(volume) < min_volume:
            doomed.extend(component)
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
    return len(doomed)


def _post_process(target, seed, damage_regions):
    mesh = target.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.get("PaletteUV")
    _require(uv_layer is not None, "damaged mesh lost its PaletteUV layer")
    pruned = _prune_degenerate_shells(bm)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    fracture_verts = _roughen_fracture(bm, 0.013, seed, damage_regions)
    _clamp_envelope(bm)
    _clamp_palette_uv(bm, uv_layer)
    # 不做 recalc_face_normals：22 个壳体互相贴合、还有互相包含的层次，重建法线会
    # 按射线内外判定翻错壳体。布尔自己产出的绕序是对的，保持原样更安全。
    bm.to_mesh(mesh)
    bm.free()
    # 源件全平面着色；破损件保持同一口径，避免断裂面出现平滑渐变的假圆角。
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    return fracture_verts, pruned


def _build_variant(source, recipe):
    target = source.copy()
    target.data = source.data.copy()
    target.name = recipe["node"]
    target.data.name = recipe["node"]
    target.animation_data_clear()
    # 组件包在库里停在展示位（y=-34），但它的网格局部坐标本来就是「XY 居中、底面
    # Z=0」的契约坐标系。把副本清成单位阵，局部空间就等于契约空间，生成器才可以
    # 直接写绝对坐标。必须先刷新 depsgraph：刚打开文件时 matrix_world 只是单位阵
    # 假象，拿它做校验会得到假绿（这条路已经踩过）。
    bpy.context.view_layer.update()
    target.matrix_world = Matrix.Identity(4)
    collection = _isolate(target, "damage_work_%s" % recipe["key"])
    _split_loose_parts(target)
    parts = [obj for obj in collection.objects if obj.type == "MESH"]
    _require(
        len(parts) == SOURCE_KIT_PART_COUNT,
        "%s: 拆出 %d 个积木，与预期 %d 不符——组件包做法变了，逐块布尔的假设需要重新确认"
        % (recipe["key"], len(parts), SOURCE_KIT_PART_COUNT),
    )
    eroders = [
        _build_eroder(spec, "%s_%02d" % (recipe["key"], index))
        for index, spec in enumerate(recipe["eroders"])
    ]
    for index, eroder in enumerate(eroders):
        _assert_eroder_reach(eroder, "%s#%d" % (recipe["key"], index))
    damage_regions = [(spec["center"], spec["size"]) for spec in recipe["eroders"]]
    cuts = sum(_carve_block(part, eroders, recipe["key"]) for part in parts)
    _require(cuts > 0, "%s: 没有任何积木被生成器切到，配方失效" % recipe["key"])
    for eroder in eroders:
        bpy.data.objects.remove(eroder, do_unlink=True)
    result = _join_parts(parts, recipe["node"])
    _release_work_collection(collection, result)
    print("  %s 积木=%d 布尔次数=%d" % (recipe["key"], len(parts), cuts))
    # 不能用内置 hash()：字符串哈希每个进程都加了随机盐，配方就不可复现了。
    rough_seed = sum(ord(char) * (index + 1) for index, char in enumerate(recipe["key"]))
    fracture_verts, pruned = _post_process(
        result, seed=rough_seed, damage_regions=damage_regions
    )
    if pruned:
        print("  %s 清掉零体积碎片面=%d" % (recipe["key"], pruned))
    return result, fracture_verts


def _verify_variant(variant, source, recipe, fracture_verts):
    mesh = variant.data
    mins, maxs = _mesh_aabb(mesh)
    label = recipe["key"]

    _require(
        abs(mins[0] + MODULE_HALF_LENGTH) < 1e-5 and abs(maxs[0] - MODULE_HALF_LENGTH) < 1e-5,
        "%s: X 包络被破坏 min=%.6f max=%.6f，两段墙体将接不上" % (label, mins[0], maxs[0]),
    )
    _require(
        abs(mins[1] + MODULE_HALF_THICKNESS) < 1e-5
        and abs(maxs[1] - MODULE_HALF_THICKNESS) < 1e-5,
        "%s: Y 厚度包络被破坏 min=%.6f max=%.6f" % (label, mins[1], maxs[1]),
    )
    _require(abs(mins[2]) < 1e-5, "%s: 底面没有落在 Z=0（原点契约 Z-min=%.6f）" % (label, mins[2]))
    _require(
        abs(maxs[2] - MODULE_HEIGHT) < 1e-5,
        "%s: 顶面高度不再是 1.80m（实际%.6f）" % (label, maxs[2]),
    )

    source_band = _band_coords(source.data, END_BAND_START)
    variant_band = _band_coords(mesh, END_BAND_START)
    _require(
        source_band == variant_band,
        "%s: |x|>=%.2f 的端头带被改动（%d -> %d 个顶点），破损越界会破坏拼接性"
        % (label, END_BAND_START, len(source_band), len(variant_band)),
    )

    source_shells = _shell_volumes(source.data)
    variant_shells = _shell_volumes(mesh)
    source_volume = sum(source_shells)
    variant_volume = sum(variant_shells)
    _require(
        min(variant_shells) > 0.0,
        "%s: 出现负体积壳体（最小 %.6f），有积木的绕序被布尔翻掉了" % (label, min(variant_shells)),
    )
    removed = (source_volume - variant_volume) / source_volume
    # 防假绿：挖不动（体积不变）说明布尔配方失效，导出的会是冒充破损的完好件。
    _require(
        removed > 0.01,
        "%s: 只削掉 %.4f%% 体积，破损配方没有真正生效" % (label, removed * 100.0),
    )
    _require(
        removed < 0.60,
        "%s: 削掉 %.4f%% 体积，破损过头不像可拼接的墙段" % (label, removed * 100.0),
    )

    uv_layer = mesh.uv_layers.get("PaletteUV")
    uv_min_u = min(loop.uv.x for loop in uv_layer.data)
    uv_max_u = max(loop.uv.x for loop in uv_layer.data)
    uv_min_v = min(loop.uv.y for loop in uv_layer.data)
    uv_max_v = max(loop.uv.y for loop in uv_layer.data)
    _require(
        uv_min_u >= PALETTE_U[0] - 1e-6 and uv_max_u <= PALETTE_U[1] + 1e-6,
        "%s: UV 的 U 越出色盘格子 [%.4f, %.4f]" % (label, uv_min_u, uv_max_u),
    )
    _require(
        uv_min_v >= PALETTE_V[0] - 1e-6 and uv_max_v <= PALETTE_V[1] + 1e-6,
        "%s: UV 的 V 越出色盘格子 [%.4f, %.4f]" % (label, uv_min_v, uv_max_v),
    )

    print(
        "VARIANT %-6s %-22s shell %d->%d verts %d->%d faces %d->%d fracture_verts=%d "
        "volume_removed=%.2f%% thin_faces=%d min_face_area=%.6f "
        "aabb=%.4f x %.4f x %.4f uv=[%.4f..%.4f]x[%.4f..%.4f]"
        % (
            label,
            recipe["label"],
            len(source_shells),
            len(variant_shells),
            len(source.data.vertices),
            len(mesh.vertices),
            len(source.data.polygons),
            len(mesh.polygons),
            fracture_verts,
            removed * 100.0,
            sum(1 for polygon in mesh.polygons if polygon.area < 1e-4),
            min(polygon.area for polygon in mesh.polygons),
            maxs[0] - mins[0],
            maxs[1] - mins[1],
            maxs[2] - mins[2],
            uv_min_u,
            uv_max_u,
            uv_min_v,
            uv_max_v,
        )
    )
    return removed


def _export(variant, filename):
    bpy.ops.object.select_all(action="DESELECT")
    variant.select_set(True)
    bpy.context.view_layer.objects.active = variant
    output_path = OUTPUT_DIR / filename
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    print(
        "EXPORTED %s -> %s (%d bytes)"
        % (variant.name, output_path, output_path.stat().st_size)
    )


bpy.context.view_layer.update()
source = bpy.data.objects.get(SOURCE_OBJECT)
_require(source is not None, "缺少源物体：%s" % SOURCE_OBJECT)
# 校验收在网格数据上，不看 matrix_world：后者在文件刚打开时是单位阵假象，而组件包
# 真正的对象变换是展示位 (0,-34,0)。网格局部坐标才是契约坐标系。
source_local_min, source_local_max = _mesh_aabb(source.data)
_require(
    abs(source_local_min[0] + MODULE_HALF_LENGTH) < 1e-5
    and abs(source_local_max[0] - MODULE_HALF_LENGTH) < 1e-5
    and abs(source_local_min[1] + MODULE_HALF_THICKNESS) < 1e-5
    and abs(source_local_max[1] - MODULE_HALF_THICKNESS) < 1e-5
    and abs(source_local_min[2]) < 1e-5
    and abs(source_local_max[2] - MODULE_HEIGHT) < 1e-5,
    "源件网格不在契约坐标系（XY 居中、底面 Z=0、高 1.80）：%s..%s"
    % (source_local_min, source_local_max),
)
_require(len(source.data.uv_layers) > 0, "源物体没有 UV 层")
_require(
    all(not polygon.use_smooth for polygon in source.data.polygons),
    "源物体不是全平面着色，破损件的着色口径需要跟着改",
)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# 先把完好件的数据指纹存下来，破损件必须保持在同一个包络与端头带上。
source_volume = sum(_shell_volumes(source.data))
print(
    "SOURCE %s verts=%d faces=%d shells=%d volume=%.6f end_band_verts=%d"
    % (
        SOURCE_OBJECT,
        len(source.data.vertices),
        len(source.data.polygons),
        len(_shell_volumes(source.data)),
        source_volume,
        len(_band_coords(source.data, END_BAND_START)),
    )
)

variants = []
for recipe in RECIPES:
    variant, fracture_verts = _build_variant(source, recipe)
    removed = _verify_variant(variant, source, recipe, fracture_verts)
    _export(variant, recipe["filename"])
    variants.append(
        {
            "name": variant.name,
            "key": recipe["key"],
            "removed": removed,
            "filename": recipe["filename"],
        }
    )

print(
    "DAMAGE_AUTHOR_OK variants=%d files=%s"
    % (len(variants), ",".join(item["filename"] for item in variants))
)
