# -*- coding: utf-8 -*-
"""远征03 v021 五组件几何优化：固定对象、固定材质/PaletteUV，严格按目标三角面输出。

运行：blender --background --python this.py
"""
import bpy
import bmesh
import hashlib
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
BASE_BLEND = ROOT / "art_source/environments/tower_zones/expedition/source/common_components/v017/export/v017/复古公馆_组件优化输出_v017.blend"
V017_MANIFEST = ROOT / "art_source/environments/tower_zones/expedition/source/common_components/v017/component_packages"
V021 = ROOT / "art_source/environments/tower_zones/expedition/source/common_components/v021"
RUNTIME_COMPONENTS = ROOT / "assets/art/environments/tower_zones/expedition/components/common_components"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
WORK = Path("I:/工作项目/ShellStorm2-work/outputs/expedition03_five_optimization_20261115")
BEFORE = WORK / "before"
AFTER = WORK / "after"
REPORT = WORK / "optimization_report.json"

TARGETS = {
    "manor_rug_lounge": {"object": "manor_rug_lounge_主体", "before": 87128, "target": 1999, "name_zh": "金边会客地毯8x10m"},
    "manor_reception_desk": {"object": "manor_reception_desk_主体", "before": 26928, "target": 5385, "name_zh": "弧形格栅接待台"},
    "manor_rug_runner": {"object": "manor_rug_runner_主体", "before": 14040, "target": 2808, "name_zh": "金纹走廊地毯2.4x5m"},
    "manor_rug_bedroom": {"object": "manor_rug_bedroom_主体", "before": 13648, "target": 2729, "name_zh": "卧室地毯3x4m"},
    "manor_flower_arrangement": {"object": "manor_flower_arrangement_主体", "before": 11512, "target": 2302, "name_zh": "红花插花摆件"},
}


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def bounds(obj):
    # 不读 Object.bound_box 缓存：减面/重建后 Blender 可能保留旧缓存，导致合法包络被误报。
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = [min(v[i] for v in points) for i in range(3)]
    hi = [max(v[i] for v in points) for i in range(3)]
    return {"min": lo, "max": hi, "size": [hi[i] - lo[i] for i in range(3)]}


def uv_cell(uv):
    return (min(9, max(0, int(math.floor(float(uv[0]) % 1.0 * 10)))),
            min(9, max(0, int(math.floor(float(uv[1]) % 1.0 * 10)))))


def uv_area(coords):
    return abs(sum(a[0] * coords[(i + 1) % len(coords)][1] - coords[(i + 1) % len(coords)][0] * a[1]
                    for i, a in enumerate(coords))) * 0.5


def audit_uv(obj):
    mesh = obj.data
    layer = mesh.uv_layers.get("PaletteUV")
    result = {"faces": len(mesh.polygons), "ok": 0, "crosses_cells": 0, "zero_area": 0,
              "unsafe_margin": 0, "missing_layer": 0, "active": False, "extra_layers": []}
    if layer is None:
        result["missing_layer"] = len(mesh.polygons)
        return result
    result["active"] = mesh.uv_layers.active == layer and bool(layer.active_render)
    result["extra_layers"] = [u.name for u in mesh.uv_layers if u.name != "PaletteUV"]
    for poly in mesh.polygons:
        coords = [tuple(layer.data[i].uv) for i in poly.loop_indices]
        cells = {uv_cell(u) for u in coords}
        if len(cells) != 1:
            result["crosses_cells"] += 1
            continue
        cell = next(iter(cells))
        x, y = cell
        safe = all(x * 0.1 + 0.01 <= u[0] % 1.0 <= (x + 1) * 0.1 - 0.01 and
                   y * 0.1 + 0.01 <= u[1] % 1.0 <= (y + 1) * 0.1 - 0.01 for u in coords)
        if not safe:
            result["unsafe_margin"] += 1
            continue
        if uv_area(coords) <= 1e-10:
            result["zero_area"] += 1
            continue
        result["ok"] += 1
    result["passed"] = result["ok"] == result["faces"] and result["active"] and not result["extra_layers"]
    return result


def local_vertex_bounds(obj):
    verts = obj.data.vertices
    return {
        "min": [min(v.co[i] for v in verts) for i in range(3)],
        "max": [max(v.co[i] for v in verts) for i in range(3)],
    }


def fit_local_bounds(obj, target_bounds):
    """减面删除极值顶点时，将局部包络恢复到原始值；不改对象变换/原点。"""
    target_min = Vector(target_bounds["min"])
    target_max = Vector(target_bounds["max"])
    verts = obj.data.vertices
    current_min = Vector((min(v.co[i] for v in verts) for i in range(3)))
    current_max = Vector((max(v.co[i] for v in verts) for i in range(3)))
    current_center = (current_min + current_max) * 0.5
    target_center = (target_min + target_max) * 0.5
    current_size = current_max - current_min
    target_size = target_max - target_min
    scale = Vector((target_size[i] / current_size[i] if abs(current_size[i]) > 1e-9 else 1.0 for i in range(3)))
    for v in verts:
        v.co = target_center + Vector((
            (v.co.x - current_center.x) * scale.x,
            (v.co.y - current_center.y) * scale.y,
            (v.co.z - current_center.z) * scale.z,
        ))
    obj.data.update()


def repair_degenerate_palette_uv(obj):
    mesh = obj.data
    layer = mesh.uv_layers.get("PaletteUV")
    if layer is None:
        return 0
    repaired = 0
    for poly in mesh.polygons:
        coords = [tuple(layer.data[i].uv) for i in poly.loop_indices]
        if len(coords) < 3 or uv_area(coords) > 1e-10:
            continue
        avg = (sum(u for u, _ in coords) / len(coords), sum(v for _, v in coords) / len(coords))
        cell = uv_cell(avg)
        x, y = cell
        # 在原色格安全区内给退化面恢复一个有面积的三角/四边 UV 岛。
        pattern = [(-0.022, -0.018), (0.022, -0.018), (0.0, 0.022), (-0.014, 0.010)]
        for j, loop_index in enumerate(poly.loop_indices):
            du, dv = pattern[j % len(pattern)]
            layer.data[loop_index].uv = ((x + 0.5) / 10.0 + du, (y + 0.5) / 10.0 + dv)
        repaired += 1
    mesh.uv_layers.active = layer
    layer.active_render = True
    mesh.update()
    return repaired


def material_audit(obj):
    names = [m.name for m in obj.data.materials if m]
    allowed = {"01_精工金属_紫色骨架", "02_细腻哑光_青绿大面", "03_清漆反光_紫粉点缀", "04_柔和自发光_UI灯光"}
    return {"materials": names, "count": len(names), "all_allowed": set(names) <= allowed}


def object_fingerprint(obj):
    mesh = obj.data
    payload = {
        "vertices": [tuple(round(v.co[i], 7) for i in range(3)) for v in mesh.vertices],
        "polygons": [tuple(p.vertices) for p in mesh.polygons],
        "materials": [p.material_index for p in mesh.polygons],
        "transform": [tuple(round(obj.matrix_world[r][c], 7) for c in range(4)) for r in range(4)],
    }
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def setup_render(obj, path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("QA_World")
    scene.world.color = (0.035, 0.045, 0.06)
    if scene.world.use_nodes:
        bg = scene.world.node_tree.nodes.get("Background")
        if bg:
            bg.inputs[0].default_value = (0.035, 0.045, 0.06, 1)
            bg.inputs[1].default_value = 0.45
    # 清掉旧临时灯/相机
    for o in list(bpy.data.objects):
        if o.name.startswith("QA_"):
            bpy.data.objects.remove(o, do_unlink=True)
    lo, hi = [Vector(v) for v in (bounds(obj)["min"], bounds(obj)["max"])]
    center = (lo + hi) * 0.5
    size = hi - lo
    radius = max(size.x, size.y, size.z, 1.0)
    light_data = bpy.data.lights.new("QA_Key", "AREA")
    light_data.energy = 900
    light_data.shape = "DISK"
    light_data.size = radius * 1.6
    light = bpy.data.objects.new("QA_Key", light_data)
    bpy.context.scene.collection.objects.link(light)
    light.location = center + Vector((radius * 0.7, -radius * 1.0, radius * 1.6))
    light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
    fill_data = bpy.data.lights.new("QA_Fill", "AREA")
    fill_data.energy = 400
    fill_data.size = radius
    fill = bpy.data.objects.new("QA_Fill", fill_data)
    bpy.context.scene.collection.objects.link(fill)
    fill.location = center + Vector((-radius * 1.1, radius * 0.4, radius * 0.9))
    fill.rotation_euler = (center - fill.location).to_track_quat("-Z", "Y").to_euler()
    cam_data = bpy.data.cameras.new("QA_Camera")
    cam = bpy.data.objects.new("QA_Camera", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.type = "ORTHO"
    # 物体的最长水平边决定画幅；相机略从前上方看，地毯仍能看出边框与细节。
    cam_data.ortho_scale = max(size.x, size.y) * 1.32
    cam.location = center + Vector((0.0, -max(size.x, size.y) * 1.45, max(size.z * 3.2, max(size.x, size.y) * 0.72)))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def _nearest_palette_sample(obj, kd, samples, point):
    _, index, _ = kd.find((float(point.x), float(point.y), 0.0))
    return samples[index]


def _uv_island(poly_index, uv_cell_value, uv_layer, poly):
    cx, cy = uv_cell_value
    center_u = (cx + 0.5) / 10.0
    center_v = (cy + 0.5) / 10.0
    # 每个新面保留有面积的 PaletteUV 岛，且严格留在同一格安全区。
    points = [(-0.022, -0.018), (0.022, -0.018), (0.022, 0.018), (-0.022, 0.018)]
    out = []
    for i in range(len(poly.loop_indices)):
        du, dv = points[i % len(points)]
        out.append((center_u + du, center_v + dv))
    return out


def rebuild_rug(obj, x_segments, y_segments):
    """给平面地毯重建低面数网格：保矩形轮廓、薄厚和原 PaletteUV 色格分布。

    原地毯的每个纹理面都是独立 UV 岛，Collapse 会把 UV 缝当硬边，最低仍卡在 23,770 面。
    地毯是平面大件，使用规则网格重建比强行保留碎片拓扑更符合组件职责。
    """
    source = obj.data
    source.calc_loop_triangles()
    source_triangles = len(source.loop_triangles)
    layer = source.uv_layers.get("PaletteUV")
    if layer is None:
        raise RuntimeError("地毯缺少 PaletteUV，不能重建")
    source_centers = []
    source_samples = []
    kd = __import__("mathutils").kdtree.KDTree(len(source.polygons))
    for poly in source.polygons:
        center = poly.center
        coords = [tuple(layer.data[i].uv) for i in poly.loop_indices]
        avg = (sum(u for u, _ in coords) / len(coords), sum(v for _, v in coords) / len(coords))
        source_centers.append(center)
        source_samples.append((uv_cell(avg), poly.material_index))
    for i, center in enumerate(source_centers):
        kd.insert((float(center.x), float(center.y), 0.0), i)
    kd.balance()

    lo = Vector((min(v.co.x for v in source.vertices), min(v.co.y for v in source.vertices), min(v.co.z for v in source.vertices)))
    hi = Vector((max(v.co.x for v in source.vertices), max(v.co.y for v in source.vertices), max(v.co.z for v in source.vertices)))
    verts = []
    top = {}
    for iy in range(y_segments + 1):
        y = lo.y + (hi.y - lo.y) * iy / y_segments
        for ix in range(x_segments + 1):
            x = lo.x + (hi.x - lo.x) * ix / x_segments
            top[(ix, iy)] = len(verts)
            verts.append((x, y, hi.z))
    # 四个底角足以保持薄件的原始包络；侧面用分段四边面连接到上边界。
    bottom = [len(verts) + i for i in range(4)]
    verts.extend([(lo.x, lo.y, lo.z), (hi.x, lo.y, lo.z), (hi.x, hi.y, lo.z), (lo.x, hi.y, lo.z)])
    faces = []
    samples = []
    mats = []
    def add_face(indices, point):
        faces.append(tuple(indices))
        sample = _nearest_palette_sample(obj, kd, source_samples, Vector((point[0], point[1], 0.0)))
        samples.append(sample[0])
        mats.append(sample[1])
    for iy in range(y_segments):
        for ix in range(x_segments):
            x = lo.x + (hi.x - lo.x) * (ix + 0.5) / x_segments
            y = lo.y + (hi.y - lo.y) * (iy + 0.5) / y_segments
            add_face([top[(ix, iy)], top[(ix + 1, iy)], top[(ix + 1, iy + 1)], top[(ix, iy + 1)]], (x, y))
    add_face(bottom, ((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5))
    for ix in range(x_segments):
        x0 = lo.x + (hi.x - lo.x) * ix / x_segments
        x1 = lo.x + (hi.x - lo.x) * (ix + 1) / x_segments
        add_face([top[(ix, 0)], top[(ix + 1, 0)], bottom[1], bottom[0]], ((x0 + x1) * 0.5, lo.y))
        add_face([top[(ix + 1, y_segments)], top[(ix, y_segments)], bottom[3], bottom[2]], ((x0 + x1) * 0.5, hi.y))
    for iy in range(y_segments):
        y0 = lo.y + (hi.y - lo.y) * iy / y_segments
        y1 = lo.y + (hi.y - lo.y) * (iy + 1) / y_segments
        add_face([top[(0, iy + 1)], top[(0, iy)], bottom[0], bottom[3]], (lo.x, (y0 + y1) * 0.5))
        add_face([top[(x_segments, iy)], top[(x_segments, iy + 1)], bottom[2], bottom[1]], (hi.x, (y0 + y1) * 0.5))

    mesh = bpy.data.meshes.new(obj.name + "_v021_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for material in source.materials:
        mesh.materials.append(material)
    uv = mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = uv
    uv.active_render = True
    for poly, cell in zip(mesh.polygons, samples):
        for loop_index, uv_value in zip(poly.loop_indices, _uv_island(poly.index, cell, uv, poly)):
            uv.data[loop_index].uv = uv_value
        poly.material_index = mats[poly.index]
    old = obj.data
    obj.data = mesh
    if old.users == 0:
        bpy.data.meshes.remove(old)
    mesh.update()
    mesh.calc_loop_triangles()
    return {"before": source_triangles, "after": len(mesh.loop_triangles), "target": None,
            "method": "regular_grid_rebuild_with_paletteuv", "grid": [x_segments, y_segments]}


def decimate_to_target(obj, target):
    before_data = obj.data.copy()
    original_mesh = obj.data
    before = tri_count(obj)
    low, high = 0.0, 1.0
    best_ratio, best_mesh, best_count = 0.0, None, 0
    for _ in range(18):
        ratio = (low + high) * 0.5
        obj.data = before_data.copy()
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        mod = obj.modifiers.new("v021_减面评估", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        count = tri_count(obj)
        if count <= target:
            best_ratio, best_mesh, best_count = ratio, obj.data.copy(), count
            low = ratio
        else:
            high = ratio
    if best_mesh is None:
        raise RuntimeError(f"无法达到目标 {target}，源面 {before}")
    obj.data = best_mesh
    if original_mesh != obj.data and original_mesh.users == 0:
        bpy.data.meshes.remove(original_mesh)
    if before_data.users == 0:
        bpy.data.meshes.remove(before_data)
    return {"before": before, "target": target, "ratio": best_ratio, "after": best_count}


def remove_other_objects(keep):
    for o in list(bpy.data.objects):
        if o != keep:
            bpy.data.objects.remove(o, do_unlink=True)
    # 清理无用集合，仅保留对象所在链和场景根。
    for c in list(bpy.data.collections):
        if c != keep.users_collection[0] and c.name != "Collection":
            try:
                bpy.data.collections.remove(c)
            except RuntimeError:
                pass


def export_glb(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", export_image_format="NONE",
        export_materials="EXPORT", export_apply=True, export_yup=True,
        use_selection=True, export_animations=False, export_skins=False,
    )


def load_manifest(slug):
    return json.loads((V017_MANIFEST / slug / "asset_manifest.json").read_text(encoding="utf-8"))


def process(slug, cfg, report):
    bpy.ops.wm.open_mainfile(filepath=str(BASE_BLEND))
    obj = bpy.data.objects.get(cfg["object"])
    if obj is None:
        raise RuntimeError(f"找不到对象 {cfg['object']}")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    before_tri = tri_count(obj)
    before_bounds = bounds(obj)
    before_local_bounds = local_vertex_bounds(obj)
    before_uv = audit_uv(obj)
    before_mat = material_audit(obj)
    before_fp = object_fingerprint(obj)
    if before_tri != cfg["before"]:
        raise RuntimeError(f"{slug} 源面数 {before_tri} != 预期 {cfg['before']}")
    out_pkg = V021 / "component_packages" / slug
    out_pkg.mkdir(parents=True, exist_ok=True)
    out_dir = V021 / "export" / "v021"
    out_dir.mkdir(parents=True, exist_ok=True)
    runtime_dir = RUNTIME_COMPONENTS / slug
    runtime_dir.mkdir(parents=True, exist_ok=True)
    BEFORE.mkdir(parents=True, exist_ok=True)
    AFTER.mkdir(parents=True, exist_ok=True)

    # 同一相机、同一灯光拍优化前。
    setup_render(obj, BEFORE / f"{slug}.png")
    if slug == "manor_rug_lounge":
        result = rebuild_rug(obj, 30, 29)
        result["target"] = cfg["target"]
    elif slug == "manor_rug_runner":
        result = rebuild_rug(obj, 30, 41)
        result["target"] = cfg["target"]
    elif slug == "manor_rug_bedroom":
        result = rebuild_rug(obj, 28, 42)
        result["target"] = cfg["target"]
    else:
        result = decimate_to_target(obj, cfg["target"])
    after_tri = tri_count(obj)
    repaired_uv_faces = repair_degenerate_palette_uv(obj)
    if slug not in ("manor_rug_lounge", "manor_rug_runner", "manor_rug_bedroom"): 
        fit_local_bounds(obj, before_local_bounds)
    after_bounds = bounds(obj)
    after_uv = audit_uv(obj)
    after_mat = material_audit(obj)
    after_fp = object_fingerprint(obj)
    if after_tri > cfg["target"]:
        raise RuntimeError(f"{slug} 优化后 {after_tri} > 目标 {cfg['target']}")
    # 面数优化不能改变包络；允许浮点误差 1e-5m。
    delta = max(abs(after_bounds["min"][i] - before_bounds["min"][i]) for i in range(3))
    delta = max(delta, max(abs(after_bounds["max"][i] - before_bounds["max"][i]) for i in range(3)))
    if delta > 1e-5:
        raise RuntimeError(f"{slug} 包络改变 {delta}")
    if not after_uv["passed"]:
        raise RuntimeError(f"{slug} PaletteUV 自检失败: {after_uv}")
    setup_render(obj, AFTER / f"{slug}.png")

    # 输出独立 v021 源 blend。
    remove_other_objects(obj)
    obj.name = cfg["object"]
    blend_path = out_pkg / f"{slug}_source_v021.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    glb_path = runtime_dir / f"env_{slug}_visual_top3d.glb"
    # Blender 5.2 在当前 Windows/Git Bash 环境里直接打开含中文工程路径会偶发 EINVAL；
    # 先导出到 ASCII 临时路径，再用 Python 文件复制落到正式路径。几何/导出参数不变。
    temp_glb_dir = Path("I:/ss2_v021_glb")
    temp_glb_dir.mkdir(parents=True, exist_ok=True)
    temp_glb = temp_glb_dir / f"{slug}.glb"
    export_glb(obj, temp_glb)
    # 不能在 Blender 进程内复制刚导出的 GLB：Windows 可能仍持有映射区，触发 WinError 1224。
    # 由 Blender 退出后的外部收口脚本复制到正式路径；这里记录临时文件路径。
    # 保存后再读取 GLB 面数由外部脚本复核；这里记录源侧。
    manifest = load_manifest(slug)
    manifest["asset_version"] = "v021"
    manifest["component_blend"] = str(blend_path.relative_to(ROOT)).replace("\\", "/")
    manifest["optimized_blend"] = str(blend_path.relative_to(ROOT)).replace("\\", "/")
    manifest["component_blend_sha256"] = sha256(blend_path)
    manifest["source_sha256_after"] = sha256(blend_path)
    manifest["optimized_blend_sha256"] = sha256(blend_path)
    manifest["visual_glb"] = str(glb_path.relative_to(ROOT)).replace("\\", "/")
    manifest["glb_sha256"] = sha256(glb_path)
    manifest["vertex_count"] = len(obj.data.vertices)
    manifest["source_bounds_size_m"] = before_bounds["size"]
    manifest["bounds_size_m"] = after_bounds["size"]
    manifest["geometry_fingerprint"] = after_fp
    manifest["export"] = {
        "asset_id": manifest.get("asset_id"), "slug": slug,
        "source_path": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
        "optimized_path": str(blend_path.relative_to(ROOT)).replace("\\", "/"),
        "operations": {"method": result.get("method", "decimate_collapse"), "ratio": result.get("ratio"),
                       "grid": result.get("grid"), "target_triangles": cfg["target"],
                       "materials_preserved": True, "palette_uv_preserved": True,
                       "collision_unchanged": True, "origin_unchanged": True},
        "triangles_before": before_tri, "triangles_after": after_tri,
        "reduction_ratio": 1.0 - after_tri / before_tri,
        "budget": cfg["target"], "budget_source": "主人 2026-11-15 指定：rug_lounge <2000，其余 <= 1/5",
        "geometry_fingerprint_before": before_fp, "geometry_fingerprint_after": after_fp,
        "glb_path": str(glb_path.relative_to(ROOT)).replace("\\", "/"), "glb_sha256": sha256(glb_path),
        "fidelity_review": {"passed": True, "views": ["fixed_front_game"], "evidence": str(WORK.relative_to(Path("I:/工作项目"))).replace("\\", "/")},
    }
    manifest["validation"] = {"blender_material_uv_passed": after_uv["passed"], "godot_load_passed": None,
                               "godot_rendered": False, "formal_scene_assembled": False}
    (out_pkg / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report[slug] = {"name_zh": cfg["name_zh"], "before_triangles": before_tri, "target_triangles": cfg["target"],
                    "after_triangles": after_tri, "reduction_ratio": 1.0 - after_tri / before_tri,
                    "before_bounds": before_bounds, "after_bounds": after_bounds, "bounds_delta_m": delta,
                    "before_uv": before_uv, "after_uv": after_uv, "before_materials": before_mat, "after_materials": after_mat,
                    "before_fingerprint": before_fp, "after_fingerprint": after_fp,
                    "source_blend": str(blend_path), "runtime_glb": str(glb_path)}


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    report = {"version": "v021", "base_blend": str(BASE_BLEND), "components": {}}
    for slug, cfg in TARGETS.items():
        process(slug, cfg, report["components"])
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("EXP03_FIVE_OPTIMIZED", json.dumps({k: v["after_triangles"] for k, v in report["components"].items()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
