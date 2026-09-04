#!/usr/bin/env python3
"""Scoped v017 refinement: loft bed, lounge rug, and visible loft floor only."""
from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
CATALOG = VERIFY / "base_facility_component_catalog_v017.json"
TREE = VERIFY / "base_facility_component_tree_v017.txt"
REPORT = VERIFY / "loft_bed_rug_floor_refinement_acceptance.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with base_facility_runtime_layout_hq_v017.blend open")

spec = importlib.util.spec_from_file_location(
    "v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py"
)
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)


def package(slug):
    return reorg.package_by_slug(slug)


def source_package(slug):
    coll = bpy.data.collections.get(f"v017_源资产包_{slug}")
    if coll is None:
        raise RuntimeError(f"missing source package: {slug}")
    return coll


def new_source_package(category, slug, display):
    parent = bpy.data.collections.get(f"v017_源类别_{category}")
    if parent is None:
        root = bpy.data.collections.get("v017_全部制作源_按独立设施归类")
        if root is None:
            raise RuntimeError("missing v017 source root")
        parent = bpy.data.collections.new(f"v017_源类别_{category}")
        root.children.link(parent)
    coll = bpy.data.collections.new(f"v017_源资产包_{slug}")
    parent.children.link(coll)
    coll["源资产包"] = True
    coll["源资产包键"] = slug
    coll["显示名"] = display
    coll["组织版本"] = "v017"
    return coll


def move_to(obj, coll):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    coll.objects.link(obj)


def mat(name):
    result = bpy.data.materials.get(name)
    if result is None:
        raise RuntimeError(f"missing shared material {name}")
    return result


MAT_MATTE = mat("02_细腻哑光_青绿大面")
MAT_GLOSS = mat("03_清漆反光_紫粉点缀")


def set_uv(obj, cell):
    if obj.type != "MESH":
        return
    uv = obj.data.uv_layers.get("PaletteUV")
    if uv is None:
        uv = obj.data.uv_layers.new(name="PaletteUV")
    obj.data.uv_layers.active = uv
    uv.active_render = True
    u, v = cell
    radius = 0.018
    for poly in obj.data.polygons:
        loops = list(poly.loop_indices)
        for index, loop_index in enumerate(loops):
            angle = math.tau * index / max(3, len(loops)) + math.pi / 4.0
            uv.data[loop_index].uv = (u + radius * math.cos(angle), v + radius * math.sin(angle))
    obj["色盘UV"] = f"PaletteUV cell {cell[0]:.2f},{cell[1]:.2f}"


def box(name, coll, location, dimensions, material, cell):
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    x, y, z = (d / 2.0 for d in dimensions)
    vertices = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
                (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    obj.location = location
    set_uv(obj, cell)
    return obj


def clone_box(source, name, coll):
    clone = bpy.data.objects.new(name, source.data.copy())
    coll.objects.link(clone)
    clone.location = source.location
    clone.rotation_euler = source.rotation_euler
    clone.scale = source.scale
    for key, value in source.items():
        clone[key] = value
    return clone


def obj(name):
    result = bpy.data.objects.get(name)
    if result is None:
        raise RuntimeError(f"missing object: {name}")
    return result


bed = package("loft_bed_and_bedding")
bed_source = source_package("loft_bed_and_bedding")
rug = package("loft_lounge_rug")
rug_source = source_package("loft_lounge_rug")
mezz = package("east_mezzanine_structure")
mezz_source = source_package("east_mezzanine_structure")

allowed_existing = set(bed.objects) | set(bed_source.objects) | set(rug.objects) | set(rug_source.objects)
floor_base = bpy.data.objects.get("二楼地板_红棕生活基底") or bpy.data.objects.get("二楼地板_暖红生活基底") or obj("楼中楼_深色木纹生活面")
floor_base_source = bpy.data.objects.get("二楼地板_红棕生活基底__源") or bpy.data.objects.get("二楼地板_暖红生活基底__源") or obj("楼中楼_深色木纹生活面__源")
allowed_existing.update((floor_base, floor_base_source))
existing_floor = next((c for c in reorg.packages() if c.get("资产包键") == "loft_floor_finish"), None)
existing_floor_source = bpy.data.collections.get("v017_源资产包_loft_floor_finish")
if existing_floor is not None:
    allowed_existing.update(existing_floor.objects)
if existing_floor_source is not None:
    allowed_existing.update(existing_floor_source.objects)
locked_before = {o.name: reorg.signature(o) for o in bpy.data.objects if o not in allowed_existing}

# Restore the reference length on X, then widen the bed on Y (front/back).
for name in ("床架_长边_10.28", "床架_长边_12.22"):
    target = obj(name)
    target.location.x = 0.30
    target.dimensions.x = 4.75
obj("床架_长边_10.28").location.y = 10.05
obj("床架_长边_12.22").location.y = 12.45
obj("床架_短边_-2.0").location.x = -2.0
obj("床架_短边_2.6").location.x = 2.6
for name in ("床架_短边_-2.0", "床架_短边_2.6"):
    obj(name).dimensions.y = 2.55
for name, x, y in (
    ("床架_圆脚_-1.9_10.38", -1.9, 10.15), ("床架_圆脚_-1.9_12.12", -1.9, 12.35),
    ("床架_圆脚_2.5_10.38", 2.5, 10.15), ("床架_圆脚_2.5_12.12", 2.5, 12.35),
):
    obj(name).location.x = x
    obj(name).location.y = y
obj("床垫_厚软包").location.x = 0.30
obj("床垫_厚软包").scale.x = 1.0
obj("床垫_厚软包").scale.y = 2.30 / 1.86
obj("床面_墨绿床罩").location.x = 0.62
obj("床面_墨绿床罩").scale.x = 1.0
obj("床面_墨绿床罩").scale.y = 2.20 / 1.78
for name, y in (("床垫_滚边_10.39", 10.16), ("床垫_滚边_12.11", 12.34)):
    obj(name).location.x = 0.30
    obj(name).location.y = y
    obj(name).dimensions.x = 4.20
for name, x in zip(("床罩_细褶_00", "床罩_细褶_01", "床罩_细褶_02", "床罩_细褶_03"), (.35, 1.00, 1.65, 2.30)):
    obj(name).location.x = x
    obj(name).dimensions.y = 1.90
obj("v016_床罩脚端折叠毯").location.x = 2.02
obj("v016_床罩脚端折叠毯").scale.x = 1.0
obj("v016_床罩脚端折叠毯").scale.y = 2.15 / 1.72
for name, y in (("v016_折叠毯包边_10.48", 10.25), ("v016_折叠毯包边_12.02", 12.25)):
    obj(name).location.x = 2.02
    obj(name).location.y = y
    obj(name).scale.x = 1.0

# Keep source mirror transforms identical to the changed output objects.
for output in list(bed.objects):
    source = bpy.data.objects.get(f"{output.name}__源")
    if source is not None:
        source.matrix_world = output.matrix_world.copy()
        source.dimensions = output.dimensions

# Multi-colour low-saturation rug tied to the existing coffee-table lounge zone only.
rug_base = obj("休闲区低饱和地毯_软质基底")
set_uv(rug_base, (.45, .25))
for name, cell in zip(
    ("休闲区低饱和地毯_低对比编织线_01", "休闲区低饱和地毯_低对比编织线_02", "休闲区低饱和地毯_低对比编织线_03", "休闲区低饱和地毯_低对比编织线_04", "休闲区低饱和地毯_低对比编织线_05", "休闲区低饱和地毯_低对比编织线_06"),
    ((.35,.25), (.55,.25), (.45,.35), (.65,.35), (.35,.15), (.55,.15)),
):
    set_uv(obj(name), cell)
rug_details = [
    ("休闲地毯_紫灰外框_南", (6.18,8.45,6.123), (4.62,.07,.018), MAT_MATTE, (.55,.25)),
    ("休闲地毯_紫灰外框_北", (6.18,10.65,6.123), (4.62,.07,.018), MAT_MATTE, (.55,.25)),
    ("休闲地毯_暗红外框_西", (3.96,9.55,6.123), (.07,2.10,.018), MAT_GLOSS, (.35,.25)),
    ("休闲地毯_暗红外框_东", (8.40,9.55,6.123), (.07,2.10,.018), MAT_GLOSS, (.35,.25)),
    ("休闲地毯_暖棕细纹_01", (5.06,9.55,6.124), (.08,1.72,.020), MAT_GLOSS, (.65,.75)),
    ("休闲地毯_暖棕细纹_02", (7.30,9.55,6.124), (.08,1.72,.020), MAT_GLOSS, (.65,.75)),
]
legacy_rug_names = {
    "休闲地毯_青绿外框_南": "休闲地毯_紫灰外框_南",
    "休闲地毯_青绿外框_北": "休闲地毯_紫灰外框_北",
    "休闲地毯_紫灰外框_西": "休闲地毯_暗红外框_西",
    "休闲地毯_紫灰外框_东": "休闲地毯_暗红外框_东",
    "休闲地毯_暖橙细纹_01": "休闲地毯_暖棕细纹_01",
    "休闲地毯_暖橙细纹_02": "休闲地毯_暖棕细纹_02",
}
for old, new in legacy_rug_names.items():
    if bpy.data.objects.get(old) and not bpy.data.objects.get(new):
        bpy.data.objects[old].name = new
    if bpy.data.objects.get(f"{old}__源") and not bpy.data.objects.get(f"{new}__源"):
        bpy.data.objects[f"{old}__源"].name = f"{new}__源"
for name, loc, dims, material, cell in rug_details:
    output = bpy.data.objects.get(name)
    if output is None:
        output = box(name, rug, loc, dims, material, cell)
    output.location = loc
    output.dimensions = dims
    set_uv(output, cell)
    source = bpy.data.objects.get(f"{name}__源")
    if source is None:
        source = clone_box(output, f"{name}__源", rug_source)
    set_uv(source, cell)
for output in list(rug.objects):
    source = bpy.data.objects.get(f"{output.name}__源")
    if source is not None:
        source.matrix_world = output.matrix_world.copy()
        source.dimensions = output.dimensions
        if source.type == "MESH":
            set_uv(source, tuple(map(float, output["色盘UV"].replace("PaletteUV cell ", "").split(","))))

# Split the visible finish from the locked mezzanine structure into a standalone floor package.
if any(c.get("资产包键") == "loft_floor_finish" for c in reorg.packages()):
    floor = package("loft_floor_finish")
    floor_source = source_package("loft_floor_finish")
else:
    floor = reorg.new_package("tile_r01_c01", 116, "二楼地板色彩深化", "loft_floor_finish", "floor")
    floor["制作范围"] = "v017 二楼可见生活地面；不含承重楼板、楼梯、栏杆与家具"
    floor["视觉基准"] = "二楼暖红生活区、青绿功能区、紫灰边界的低饱和分区"
    floor_source = new_source_package("floor", "loft_floor_finish", "二楼地板色彩深化")
move_to(floor_base, floor)
move_to(floor_base_source, floor_source)
floor_base.name = "二楼地板_红棕生活基底"
floor_base_source.name = "二楼地板_红棕生活基底__源"
set_uv(floor_base, (.35,.75))
set_uv(floor_base_source, (.35,.75))
floor_details = [
    ("二楼地板_南侧暗红收边", (5,5.58,6.095), (18.85,.08,.006), MAT_MATTE, (.25,.85)),
    ("二楼地板_北侧暗红收边", (5,14.42,6.095), (18.85,.08,.006), MAT_MATTE, (.25,.85)),
    ("二楼地板_西侧暖棕收边", (-4.42,10,6.095), (.08,8.70,.006), MAT_GLOSS, (.65,.75)),
    ("二楼地板_东侧暖棕收边", (14.42,10,6.095), (.08,8.70,.006), MAT_GLOSS, (.65,.75)),
    ("二楼地板_睡眠区暗红拼板", (-.30,11.45,6.092), (6.80,4.40,.004), MAT_MATTE, (.25,.75)),
    ("二楼地板_休闲区红棕拼板", (6.10,8.50,6.092), (6.00,3.30,.004), MAT_MATTE, (.45,.75)),
    ("二楼地板_工位区紫灰拼板", (10.80,12.90,6.092), (5.40,2.30,.004), MAT_MATTE, (.55,.75)),
    ("二楼地板_睡眠区暖棕细缝", (-.30,9.28,6.095), (6.50,.06,.006), MAT_GLOSS, (.65,.75)),
    ("二楼地板_休闲区紫灰细缝", (6.10,6.82,6.095), (5.60,.06,.006), MAT_GLOSS, (.55,.35)),
    ("二楼地板_工位区暖棕细缝", (10.80,11.70,6.095), (5.00,.06,.006), MAT_GLOSS, (.65,.75)),
]
legacy_floor_names = {
    "二楼地板_南侧青绿嵌条": "二楼地板_南侧暗红收边",
    "二楼地板_北侧紫灰嵌条": "二楼地板_北侧暗红收边",
    "二楼地板_西侧暖橙嵌条": "二楼地板_西侧暖棕收边",
    "二楼地板_东侧青绿嵌条": "二楼地板_东侧暖棕收边",
    "二楼地板_睡眠区紫灰面": "二楼地板_睡眠区暗红拼板",
    "二楼地板_休闲区暖红面": "二楼地板_休闲区红棕拼板",
    "二楼地板_工位区青绿面": "二楼地板_工位区紫灰拼板",
    "二楼地板_睡眠区暖橙标线": "二楼地板_睡眠区暖棕细缝",
    "二楼地板_休闲区紫灰标线": "二楼地板_休闲区紫灰细缝",
    "二楼地板_工位区暖橙标线": "二楼地板_工位区暖棕细缝",
}
for old, new in legacy_floor_names.items():
    if bpy.data.objects.get(old) and not bpy.data.objects.get(new):
        bpy.data.objects[old].name = new
    if bpy.data.objects.get(f"{old}__源") and not bpy.data.objects.get(f"{new}__源"):
        bpy.data.objects[f"{old}__源"].name = f"{new}__源"
for name, loc, dims, material, cell in floor_details:
    if bpy.data.objects.get(name) is None:
        output = box(name, floor, loc, dims, material, cell)
        clone_box(output, f"{name}__源", floor_source)
    else:
        output = bpy.data.objects[name]
        output.location = loc
        output.dimensions = dims
        source = bpy.data.objects[f"{name}__源"]
        source.location = loc
        source.dimensions = dims
        set_uv(output, cell)
        set_uv(source, cell)

bpy.context.view_layer.update()
for name, before in locked_before.items():
    now = bpy.data.objects.get(name)
    if now is None or reorg.signature(now) != before:
        raise RuntimeError(f"out-of-scope object changed: {name}")
if floor_base.name in mezz.objects or floor_base_source.name in mezz_source.objects:
    raise RuntimeError("visible floor finish was not split out of mezzanine structure")


def write_manifest(coll, revision, extra):
    slug = str(coll.get("资产包键"))
    category = str(coll.get("资产类别"))
    path = PACKAGE_ROOT / category / slug / "asset_manifest.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    center, dims = reorg.bbox(list(coll.objects))
    data.update({
        "asset_slug": slug,
        "category": category,
        "display_name": coll.name,
        "organization_version": "v017",
        "revision": revision,
        "object_count": len(coll.objects),
        "center": center,
        "dimensions": dims,
        "source_mirror": f"v017_源资产包_{slug}",
        "source_object_count": len(source_package(slug).objects),
        "palette_uv": "PaletteUV",
        "shared_materials": [MAT_MATTE.name, MAT_GLOSS.name],
    })
    data.update(extra)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return data


bed_manifest = write_manifest(bed, "v017_loft_bed_width_corrected_006", {
    "acceptance": "恢复参考长度4.75m；床架沿Y方向加宽至2.55m、床垫宽2.30m，结构同步对齐。",
    "scope": "二楼床铺与床品",
})
rug_manifest = write_manifest(rug, "v017_loft_lounge_rug_reference_palette_006", {
    "acceptance": "桌毯按参考图采用暗紫红基底、紫灰边框与低饱和暖棕细纹；咖啡桌本体未改。",
    "scope": "二楼休闲区桌毯",
})
floor_manifest = write_manifest(floor, "v017_loft_floor_reference_redbrown_006", {
    "acceptance": "可见二楼地面恢复参考图深红棕主色，采用暗红、暖棕拼板与少量紫灰细缝；地面层低于桌毯，不含绿色大面与承重楼板。",
    "scope": "二楼可见地板表面与直接依附装饰",
})

catalog = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.is_file() else {}
entries = {entry["asset_slug"]: entry for entry in catalog.get("packages", [])}
for manifest in (bed_manifest, rug_manifest, floor_manifest):
    entries.setdefault(manifest["asset_slug"], {}).update(manifest)
catalog["packages"] = sorted(entries.values(), key=lambda item: item.get("asset_slug", ""))
catalog["package_count"] = len(catalog["packages"])
catalog["revision"] = "v017_loft_bed_rug_floor_005"
CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
TREE.write_text("\n".join(f"{entry.get('category','')}/{entry['asset_slug']}" for entry in catalog["packages"]) + "\n", encoding="utf-8")

report = {
    "status": "pass",
    "scope": ["loft_bed_and_bedding", "loft_lounge_rug", "loft_floor_finish"],
    "locked_unchanged_object_count": len(locked_before),
    "bed_length_m": 4.75,
    "bed_width_m": 2.55,
    "mattress_width_m": 2.30,
    "rug_object_count": len(rug.objects),
    "floor_object_count": len(floor.objects),
    "catalog_package_count": catalog["package_count"],
    "notes": "未调整咖啡桌、楼梯、栏杆、沙发、工位或一楼资产。",
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(report, ensure_ascii=False))
