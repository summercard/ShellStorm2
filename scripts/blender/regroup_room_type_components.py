"""常驻工具：把「一个源对象一个包」的旧 schema 房型组件库，按冻结的 component_plan.json
归并为「一个唯一组件一个包」的新 schema 组件库。

## 为什么必须常驻仓库

`plan_components.py`（02 的规划脚本）**只用包络 + 材质 + 旋转做候选聚类**，它自己的 docstring
写着「几何指纹需 Blender 侧校验」。也就是说规划脚本给出的是**候选**簇；真正的等价性必须由
Blender 侧按「旋转不变 + 容差」逐件确认。本工具就是那条必须存在、且不能留在 `_scratch` 的
Blender 侧实现 —— Boss 房实测：规划候选把 214 包收敛成 28 个组件，但按几何真值只有
**140/214** 个成员与代表件等价；照候选合并会**静默丢掉 140 件各不相同的几何**。

## 归并判据（机器可判断）

  1. **族内先按几何等价类聚类**，不是「谁被命名成代表」。等价类判据：
     把包内 `_输出_` 网格顶点搬到组件 bbox 中心为原点的局部系，若成员顶点多重集在
     **Blender Z 轴 0/90/180/270° 旋转**下与类代表件逐点最大偏移 ≤ `--tol`（默认 5mm，
     远小于任何设计特征尺度，也远大于浮点噪声），且网格数 / 材质多重集 / 顶点数一致，即同族同类。
  2. **同类才允许合并**；同族等价类数超过 `--family-cap`（默认 3，即 02 的常规上限）时，
     只保留**成员数最多的 N 类**，其余类整体并入最接近的保留类，并逐件登记角度与最大偏移。
  3. 角度不落在 0/90/180/270 或顶点数不同 ⇒ 记 `shape_mismatch`；只并位置不并形状，
     一律写进 catalog 的 `absorbed_geometry_variant` / `absorbed_geometry_shape_mismatch`。

## 输入契约

  · `--source-lib`：旧库目录（`component_catalog.json` + `component_packages/<pkg>/<pkg>.blend`）。
    独立包形状：一个 `ROOT_*_组件` EMPTY + 若干 `<名>_输出_部件NN` / `_输出_自发光` MESH。
  · `--plan`：02 的 `component_plan.json`；只用它的**族归属**（`families[].representatives[].absorbed[]`）。
  · `--slug-map`：语义命名表，键 = 工具选出的**等价类代表件 component_id**（`--analyze` 出初稿）。

## 输出

  · `component_packages/<slug>/<slug>.blend` —— 每唯一组件一个独立包：scene `Component_<slug>`，
    集合 `01_制作组件_<slug>` + `<slug>_制作源` + `<slug>_输出包`，对象名换成语义 slug。
  · `<out-lib>/<library-blend-name>` —— 母版：只留保留件的集合与对象，其余场景/集合/对象清除。
  · `component_catalog.json` / `component_instances.json` / `regroup_analysis.json`。

## 边界

只做资产归并与重建：不碰玩法、数值、门状态机、关卡拓扑；源库只读。

用法::

    blender --factory-startup --background --python scripts/blender/regroup_room_type_components.py -- \
        --project-root <root> \
        --source-lib  assets/.../common_components/v001 \
        --plan        assets/.../common_components/v008/component_plan.json \
        --slug-map    assets/.../common_components/v008/component_slug_map.json \
        --out-lib     assets/.../common_components/v008 \
        [--analyze] [--family-cap 3] [--tol 0.005] \
        [--library-blend-name expedition_boss_room_components_source_v008.blend] \
        [--skip-master]

`--analyze` 只跑聚类与命名初稿，不写资产。正式构建要求命名表覆盖且只覆盖等价类代表件。
退出码：0 = 成功；2 = 前置条件不满足（命名表缺件/重复、源库缺件）。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import bpy

ROTATIONS = (0, 90, 180, 270)
QUANT = 3
AXIS_WORDS = ("north", "south", "east", "west", "front", "rear", "inner", "outer")
DEFAULT_ROTATIONS = [0, 90, 180, 270]
PART_SUFFIX_RE = re.compile(r"_输出_")
EMPTY_COLLECTION_PREFIX = "01_制作组件_"
LEGACY_PREFIX = "ENV-EXPEDITION-BOSSROOM-"


# --------------------------------------------------------------------------- io


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--source-lib", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--slug-map", required=True)
    parser.add_argument("--out-lib", required=True)
    parser.add_argument("--library-blend-name", default="")
    parser.add_argument("--family-cap", type=int, default=3)
    parser.add_argument(
        "--family-cap-overrides",
        default="",
        help="按族放宽上限：family=cap[,...]；仅用于 02 允许的破损/配色/结构状态轴族",
    )
    parser.add_argument("--tol", type=float, default=0.005)
    parser.add_argument("--analyze", action="store_true")
    parser.add_argument("--write-slug-map", action="store_true")
    parser.add_argument("--skip-master", action="store_true")
    argv = sys.argv
    tail = argv[argv.index("--") + 1 :] if "--" in argv else []
    return parser.parse_args(tail)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ------------------------------------------------------------------ blender side


def open_blend(path: Path) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(path))


def output_root():
    roots = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "EMPTY" and obj.name.endswith("_组件")
    ]
    if len(roots) != 1:
        raise RuntimeError(f"组件包输出根不唯一：{[o.name for o in roots]}")
    return roots[0]


def output_meshes():
    return sorted(
        (
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "MESH" and PART_SUFFIX_RE.search(obj.name)
        ),
        key=lambda obj: obj.name,
    )


def rotate_xy(point: tuple[float, float, float], degrees: int) -> tuple[float, float, float]:
    x, y, z = point
    if degrees == 0:
        return (x, y, z)
    if degrees == 90:
        return (-y, x, z)
    if degrees == 180:
        return (-x, -y, z)
    return (y, -x, z)


def signature() -> dict:
    meshes = output_meshes()
    if not meshes:
        raise RuntimeError("组件包没有 _输出_ 网格")
    points = []
    for obj in meshes:
        matrix = obj.matrix_world
        points.extend(matrix @ vert.co for vert in obj.data.vertices)
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    center = [(lo[i] + hi[i]) * 0.5 for i in range(3)]
    quantized = sorted(
        (
            round(p.x - center[0], QUANT),
            round(p.y - center[1], QUANT),
            round(p.z - center[2], QUANT),
        )
        for p in points
    )
    return {
        "points": quantized,
        "materials": sorted(tuple(m.name for m in obj.data.materials if m) for obj in meshes),
        "mesh_count": len(meshes),
        "vertex_counts": sorted(len(obj.data.vertices) for obj in meshes),
        "bounds_size_m": [
            round(hi[0] - lo[0], 4),
            round(hi[1] - lo[1], 4),
            round(hi[2] - lo[2], 4),
        ],
        "bounds_lo_m": [round(v, 4) for v in lo],
        "bounds_hi_m": [round(v, 4) for v in hi],
        "origin_offset_m": [round(v, 4) for v in center],
    }


def compatible(rep_sig: dict, member_sig: dict) -> bool:
    return (
        rep_sig["mesh_count"] == member_sig["mesh_count"]
        and rep_sig["materials"] == member_sig["materials"]
        and rep_sig["vertex_counts"] == member_sig["vertex_counts"]
    )


def best_rotation(rep_sig: dict, member_sig: dict) -> tuple[int, float]:
    """最接近的 Z 旋转与「逐点最大偏移」。形状不兼容时返回 (0, inf)。"""
    if not compatible(rep_sig, member_sig):
        return 0, float("inf")
    best_rotation_deg, best_delta = 0, float("inf")
    for degrees in ROTATIONS:
        rotated = sorted(rotate_xy(p, degrees) for p in rep_sig["points"])
        delta = max(
            (
                abs(a - b)
                for pa, pb in zip(rotated, member_sig["points"])
                for a, b in zip(pa, pb)
            ),
            default=0.0,
        )
        if delta < best_delta:
            best_rotation_deg, best_delta = degrees, delta
    return best_rotation_deg, best_delta


def same_class(rep_sig: dict, member_sig: dict, tol: float) -> bool:
    if not compatible(rep_sig, member_sig):
        return False
    return best_rotation(rep_sig, member_sig)[1] <= tol


# ------------------------------------------------------------------- clustering


def cluster_family(member_ids: list[str], sigs: dict[str, dict], tol: float) -> list[dict]:
    """族内贪心几何聚类；顺序确定性（按 bounds + 名字）。"""
    ordered = sorted(member_ids, key=lambda mid: (tuple(sigs[mid]["bounds_size_m"]), mid))
    classes: list[dict] = []
    for member_id in ordered:
        for cls in classes:
            if same_class(sigs[cls["rep_id"]], sigs[member_id], tol):
                cls["members"].append(member_id)
                break
        else:
            classes.append({"rep_id": member_id, "members": [member_id]})
    return classes


def parse_cap_overrides(text: str) -> dict[str, int]:
    overrides: dict[str, int] = {}
    for item in filter(None, (part.strip() for part in str(text).split(","))):
        family, _, cap = item.partition("=")
        overrides[family.strip()] = int(cap)
    return overrides


def build_components(
    plan: dict, sigs: dict[str, dict], tol: float, cap: int, cap_overrides: dict[str, int]
) -> list[dict]:
    components: list[dict] = []
    for family in plan["families"]:
        family_name = str(family["family"])
        family_cap = int(cap_overrides.get(family_name, cap))
        members = [
            str(rep["component_id"]) for rep in family["representatives"]
        ] + [
            str(m) for rep in family["representatives"] for m in rep["absorbed"]
        ]
        classes = cluster_family(members, sigs, tol)
        classes_before = len(classes)
        classes.sort(key=lambda cls: (-len(cls["members"]), cls["rep_id"]))
        kept = classes[:family_cap]
        for extra in classes[family_cap:]:
            target = min(
                kept,
                key=lambda cls: best_rotation(sigs[cls["rep_id"]], sigs[extra["rep_id"]])[1],
            )
            target["members"].extend(extra["members"])
            target.setdefault("absorbed_classes", []).append(extra["rep_id"])
        kept.sort(key=lambda cls: cls["rep_id"])
        for cls in kept:
            components.append(
                {
                    "family": family_name,
                    "rep_id": cls["rep_id"],
                    "members": sorted(cls["members"]),
                    "classes_in_family": classes_before,
                    "family_cap": family_cap,
                    "family_cap_relaxed": family_cap > cap,
                    "absorbed_classes": sorted(cls.get("absorbed_classes", [])),
                }
            )
    return components


def classify_members(component: dict, sigs: dict[str, dict], tol: float) -> dict:
    rep_sig = sigs[component["rep_id"]]
    rotations: dict[str, int] = {}
    exact, variant, shape_mismatch = [], [], []
    for member_id in component["members"]:
        member_sig = sigs[member_id]
        degrees, delta = best_rotation(rep_sig, member_sig)
        rotations[member_id] = degrees
        if not compatible(rep_sig, member_sig):
            shape_mismatch.append({"member": member_id, "rotation_deg": degrees})
        elif delta <= tol:
            exact.append(member_id)
        else:
            variant.append(
                {"member": member_id, "rotation_deg": degrees, "max_delta_m": round(delta, 4)}
            )
    component["rotations"] = rotations
    component["geometry_exact"] = exact
    component["geometry_variant"] = variant
    component["geometry_shape_mismatch"] = shape_mismatch
    return component


# ---------------------------------------------------------------------- naming


def base_family_slug(family: str) -> str:
    return re.sub(r"[^a-z0-9_]", "", str(family).lower()) or "component"


def draft_slug_map(components: list[dict], packages: dict) -> dict:
    """按等价类代表件生成命名初稿；同族多类用 `_a/_b/_c` 后缀，人工再语义化。"""
    by_family: dict[str, list[dict]] = {}
    for component in components:
        by_family.setdefault(component["family"], []).append(component)
    table: dict[str, dict] = {}
    for family, group in by_family.items():
        base = base_family_slug(family)
        for index, component in enumerate(sorted(group, key=lambda c: c["rep_id"])):
            slug = base if len(group) == 1 else f"{base}_{chr(ord('a') + index)}"
            table[component["rep_id"]] = {
                "component_id": f"ENV-EXPEDITION-L01-BOSS-{slug.upper()}",
                "slug": slug,
                "component_family": family,
                "name_zh": slug,
                "scope": "shared",
                "front_axis": "+Y",
                "variant_axis": "",
                "variant_value": "",
                "variant_reason": "",
            }
    return {
        "schema": "shellstorm2.component_slug_map",
        "schema_version": 1,
        "generated_from_plan": False,
        "note": "键 = 几何等价类代表件的 component_id；slug 必须唯一且禁方位词/槽位号/色盘格坐标。",
        "components": table,
    }


def sanitize_check(component_id: str, slug: str) -> list[str]:
    problems = []
    if re.search(r"(?i)(north|south|east|west|front|rear|inner|outer)", slug):
        problems.append(f"{slug}: slug 含方位词")
    if re.search(r"(?i)slot[_-]?\d+", slug):
        problems.append(f"{slug}: slug 含槽位号")
    if re.search(r"-?\d+\.\d+", slug):
        problems.append(f"{slug}: slug 含坐标小数")
    if re.search(r"(^|[_-])\d{1,3}($|[_-])", slug):
        problems.append(f"{slug}: slug 含纯数字段")
    if not slug or slug != slug.lower():
        problems.append(f"{slug!r}: slug 非小写或为空")
    if re.search(r"(?i)(north|south|east|west|front|rear|inner|outer)", component_id):
        problems.append(f"{component_id}: component_id 含方位词")
    return problems


# ----------------------------------------------------------------------- build


def rebuild_package(rep_pkg_dir: Path, slug: str, out_path: Path) -> None:
    open_blend(rep_pkg_dir / f"{rep_pkg_dir.name}.blend")
    root = output_root()
    for scene in bpy.data.scenes:
        scene.name = f"Component_{slug}"

    keep_collections = []
    for collection in list(bpy.data.collections):
        if collection.name.endswith("_制作源") or collection.name.endswith("_输出包"):
            keep_collections.append(collection)
            continue
        bpy.data.collections.remove(collection)

    scene = bpy.data.scenes[0]
    scaffold = bpy.data.collections.new(f"{EMPTY_COLLECTION_PREFIX}{slug}")
    scene.collection.children.link(scaffold)
    for collection in keep_collections:
        # 旧库把 `_制作源` / `_输出包` 嵌套在一个「父集合」下，而父集合已被删。
        # 必须先与所有父集合解绑、再统一挂回场景主集合；否则这两个集合不在任何场景里，
        # `orphans_purge` 会把它们连同对象一起当孤儿清掉 —— 这正是
        # 「导出时 expected exactly one output root, got []」的成因。
        parents = [c for c in bpy.data.collections if collection.name in c.children]
        parents.append(scene.collection)
        for parent in parents:
            if collection.name in parent.children:
                parent.children.unlink(collection)
        collection.name = (
            f"{slug}_制作源" if collection.name.endswith("_制作源") else f"{slug}_输出包"
        )
        scene.collection.children.link(collection)

    part_index = 0
    for obj in list(bpy.data.objects):
        if obj is root:
            obj.name = f"ROOT_{slug}_组件"
            continue
        if obj.name.endswith("_制作源"):
            obj.name = f"ROOT_{slug}_制作源"
            continue
        if obj.type != "MESH":
            continue
        if "_制作_" in obj.name:
            suffix = obj.name.rsplit("_制作_", 1)[1]
            if suffix.startswith("自发光"):
                obj.name = f"{slug}_制作_{suffix}"
            else:
                obj.name = f"{slug}_制作_部件{part_index:02d}"
                part_index += 1
        elif "_输出_" in obj.name:
            obj.name = f"{slug}_输出_{obj.name.rsplit('_输出_', 1)[1]}"

    for obj in list(bpy.data.objects):
        if not obj.users_collection:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out_path), copy=True)


def trim_master(master_path: Path, keep: dict[str, dict], out_path: Path) -> dict:
    open_blend(master_path)
    rename: dict[str, str] = {}
    for slug, info in keep.items():
        rename[str(info["collection"])] = f"{slug}_输出包"
        rename[str(info["editable_collection"])] = f"{slug}_制作源"
    for collection in list(bpy.data.collections):
        target = rename.get(collection.name)
        if target is None:
            bpy.data.collections.remove(collection)
            continue
        collection.name = target

    scene = bpy.data.scenes[0]
    for extra_scene in list(bpy.data.scenes)[1:]:
        bpy.data.scenes.remove(extra_scene)
    scene.name = "00_全部组件_总览"
    for child in list(scene.collection.children):
        scene.collection.children.unlink(child)
    for slug in sorted(keep):
        for name in (f"{slug}_制作源", f"{slug}_输出包", f"{EMPTY_COLLECTION_PREFIX}{slug}"):
            collection = bpy.data.collections.get(name)
            if collection is None:
                collection = bpy.data.collections.new(name)
            scene.collection.children.link(collection)

    for obj in list(bpy.data.objects):
        if not obj.users_collection:
            bpy.data.objects.remove(obj, do_unlink=True)
    # 旧母版里还有一批对象直接挂在「场景主集合」下（不属于任何命名集合），
    # 以及被删场景遗留下来的同批副本。判据一律收紧为：不在保留集合内即删。
    keep_objects = set()
    for slug in keep:
        for name in (f"{slug}_制作源", f"{slug}_输出包"):
            collection = bpy.data.collections.get(name)
            if collection is not None:
                keep_objects.update(collection.objects)
    for obj in list(bpy.data.objects):
        if obj not in keep_objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out_path))
    return {
        "master_objects": len(bpy.data.objects),
        "master_meshes": len(bpy.data.meshes),
        "master_collections": len(bpy.data.collections),
    }


# ------------------------------------------------------------------------ main


def main() -> int:
    args = parse_args()
    root = Path(args.project_root).resolve()
    source_lib = (root / args.source_lib).resolve()
    out_lib = (root / args.out_lib).resolve()
    slug_map_path = (root / args.slug_map).resolve()
    plan = load_json((root / args.plan).resolve())
    source_catalog = load_json(source_lib / "component_catalog.json")
    packages = {str(p["component_id"]): p for p in source_catalog["packages"]}

    all_ids = sorted(
        {
            str(rep["component_id"])
            for family in plan["families"]
            for rep in family["representatives"]
        }
        | {
            str(m)
            for family in plan["families"]
            for rep in family["representatives"]
            for m in rep["absorbed"]
        }
    )
    missing = [cid for cid in all_ids if cid not in packages]
    if missing:
        print(f"FAIL: 源库缺组件 {missing[:5]}（共 {len(missing)}）")
        return 2

    cap_overrides = parse_cap_overrides(args.family_cap_overrides)
    print(
        f"源库 {source_lib.name}｜包 {len(packages)}｜计划成员 {len(all_ids)}"
        f"｜族 {len(plan['families'])}｜容差 {args.tol}m｜常规族上限 {args.family_cap}"
        + (f"｜放宽 {cap_overrides}" if cap_overrides else "")
    )
    sigs: dict[str, dict] = {}
    for component_id in all_ids:
        pkg = str(packages[component_id].get("source_package_id", component_id))
        open_blend(source_lib / "component_packages" / pkg / f"{pkg}.blend")
        sigs[component_id] = signature()

    components = build_components(plan, sigs, args.tol, args.family_cap, cap_overrides)
    for component in components:
        classify_members(component, sigs, args.tol)

    total_variant = 0
    total_shape = 0
    for component in components:
        total_variant += len(component["geometry_variant"])
        total_shape += len(component["geometry_shape_mismatch"])
        print(
            "  %-16s %-44s 成员 %3d｜同类 %3d｜异形 %3d｜簇 %d→上限%d"
            % (
                component["family"][:16],
                str(packages[component["rep_id"]].get("source_package_id", ""))[:44],
                len(component["members"]),
                len(component["geometry_variant"]),
                len(component["geometry_shape_mismatch"]),
                component["classes_in_family"],
                component["family_cap"],
            )
        )
    print(f"COMPONENT_COUNT:{len(components)}")
    print(f"ABSORBED_VARIANT_TOTAL:{total_variant}")
    print(f"ABSORBED_SHAPE_MISMATCH_TOTAL:{total_shape}")
    families_over = sorted(
        {
            component["family"]
            for component in components
            if component["classes_in_family"] > component["family_cap"]
        }
    )
    print(f"FAMILIES_CONVERGED:{families_over}")

    analysis = {
        "schema": "shellstorm2.component_regroup_analysis",
        "schema_version": 1,
        "source_library": args.source_lib,
        "tolerance_m": args.tol,
        "family_cap": args.family_cap,
        "family_cap_overrides": cap_overrides,
        "package_count": len(packages),
        "plan_member_count": len(all_ids),
        "component_count": len(components),
        "absorbed_variant_total": total_variant,
        "absorbed_shape_mismatch_total": total_shape,
        "families_converged": families_over,
        "components": [
            {
                "family": component["family"],
                "representative_package_id": str(
                    packages[component["rep_id"]].get("source_package_id", "")
                ),
                "representative_component_id": component["rep_id"],
                "member_count": len(component["members"]),
                "classes_in_family": component["classes_in_family"],
                "family_cap_applied": component["family_cap"],
                "family_cap_relaxed": component["family_cap_relaxed"],
                "absorbed_classes": component["absorbed_classes"],
                "bounds_size_m": sigs[component["rep_id"]]["bounds_size_m"],
                "geometry_exact_count": len(component["geometry_exact"]),
                "geometry_variant": component["geometry_variant"],
                "geometry_shape_mismatch": component["geometry_shape_mismatch"],
                "members": [
                    str(packages[m].get("source_package_id", m)) for m in component["members"]
                ],
            }
            for component in components
        ],
    }

    if args.analyze:
        write_json(out_lib / "regroup_analysis.json", analysis)
        if args.write_slug_map:
            write_json(slug_map_path, draft_slug_map(components, packages))
            print(f"REGROUP_SLUG_MAP_DRAFTED:{slug_map_path}")
        print(f"REGROUP_ANALYZED:{out_lib / 'regroup_analysis.json'}")
        return 0

    slug_map_doc = load_json(slug_map_path)
    slug_table = slug_map_doc["components"]
    expected = {component["rep_id"] for component in components}
    if set(slug_table) != expected:
        only_map = sorted(set(slug_table) - expected)
        only_tool = sorted(expected - set(slug_table))
        print(f"FAIL: 命名表与等价类代表件不一致；多余 {only_map[:4]} 缺失 {only_tool[:4]}")
        return 2
    seen: dict[str, str] = {}
    problems: list[str] = []
    for rep_id, entry in slug_table.items():
        slug = str(entry.get("slug", ""))
        if slug in seen:
            print(f"FAIL: slug 重复 {slug}（{seen[slug]} / {rep_id}）")
            return 2
        seen[slug] = rep_id
        problems.extend(sanitize_check(str(entry.get("component_id", rep_id)), slug))
    print(f"NAMING_PROBLEMS:{len(problems)}")
    for line in problems[:20]:
        print(f"  {line}")
    if problems:
        print("REGROUP_ABORTED:naming")
        return 2

    version = out_lib.name
    room_type = str(source_catalog.get("room_type", "BOSS_ROOM"))
    # —— 走行面平移 ——
    # 运行时把 **y=0 当走行面**（与办公室/通道桥的通用地砖口径一致）。源房型的 z=0 往往
    # 不是走行面而是地板底板底面（Boss 房：底板底面 0 → 顶面 0.26 → 地砖顶面 0.358）。
    # 因此按命名表里声明的 `walk_plane.shift_z_m` 整房平移，使源走行面落到 y=0。
    walk_plane = slug_map_doc.get("walk_plane", {}) or {}
    shift_z = float(walk_plane.get("shift_z_m", 0.0))
    if shift_z:
        print("WALK_PLANE_SHIFT:%+.4f（%s）" % (shift_z, str(walk_plane.get("derived_from", ""))))
    # —— 预切门洞封堵 ——
    # 02 规范明确：**房型源不冻结门位、不预切门洞**，门位一律由运行时按门槽车道
    # 把标准实墙替换成门墙。若房型源预切了门洞（典型是「门垛×2 + 门楣」三件），
    # 而本关实际门位不在那里，那三件围出的净空就是**没有门扇的洞**（漏光 + 可穿行）。
    # 这里按命名表里的数据声明做两种处理，不改几何、不猜位置：
    #   drop: true                     —— 该类实例直接丢弃（左/右门垛）；
    #   seal_door_slot: <component_id> —— 该类实例改由该组件承接，且 z 归零（门楣 → 整樘实墙）。
    dropped_members: list[str] = []
    sealed_of: dict[str, str] = {}
    kept_components: list[dict] = []
    for component in components:
        entry = slug_table[component["rep_id"]]
        if bool(entry.get("drop", False)):
            dropped_members.extend(component["members"])
            continue
        target = str(entry.get("seal_door_slot", ""))
        if target:
            for member_id in component["members"]:
                sealed_of[member_id] = target
            continue
        kept_components.append(component)
    if dropped_members or sealed_of:
        print(
            "DOOR_SLOT_SEALING:dropped=%d sealed=%d"
            % (len(dropped_members), len(sealed_of))
        )
    if not kept_components:
        print("FAIL: 封堵后无剩余组件")
        return 2

    component_of: dict[str, str] = {}
    slug_of: dict[str, str] = {}
    rotation_of: dict[str, int] = {}
    for component in components:
        entry = slug_table[component["rep_id"]]
        for member_id in component["members"]:
            if member_id in dropped_members:
                continue
            component_of[member_id] = str(
                sealed_of.get(member_id) or entry["component_id"]
            )
            slug_of[member_id] = str(entry["slug"])
            rotation_of[member_id] = component["rotations"][member_id]
    target_slug = {
        str(slug_table[c["rep_id"]]["component_id"]): str(slug_table[c["rep_id"]]["slug"])
        for c in kept_components
    }
    for member_id, target in sealed_of.items():
        slug_of[member_id] = target_slug[target]

    for component in kept_components:
        slug = str(slug_table[component["rep_id"]]["slug"])
        pkg = str(packages[component["rep_id"]].get("source_package_id", component["rep_id"]))
        rebuild_package(
            source_lib / "component_packages" / pkg,
            slug,
            out_lib / "component_packages" / slug / f"{slug}.blend",
        )
    print(f"REGROUP_PACKAGES_WRITTEN:{len(kept_components)}")

    records = []
    stats: dict[int, int] = {}
    for component_id in all_ids:
        if component_id not in component_of:
            continue
        rotation = rotation_of[component_id]
        stats[rotation] = stats.get(rotation, 0) + 1
        package = packages[component_id]
        position = [round(float(v), 4) for v in package["source_world_origin_m"]]
        if component_id in sealed_of:
            position[2] = 0.0
        position[2] = round(position[2] + shift_z, 4)
        records.append(
            {
                "instance_id": str(package.get("source_package_id", component_id)),
                "component_id": component_of[component_id],
                "component_slug": slug_of[component_id],
                "position_m": position,
                "rotation_y_deg": float(rotation),
                "scale": [1.0, 1.0, 1.0],
                "source_package_id": str(package.get("source_package_id", component_id)),
            }
        )
    records.sort(key=lambda item: item["instance_id"])

    catalog_records = []
    for component in kept_components:
        entry = slug_table[component["rep_id"]]
        rep_sig = sigs[component["rep_id"]]
        slug = str(entry["slug"])
        component_id = str(entry["component_id"])
        catalog_records.append(
            {
                "component_id": component_id,
                "slug": slug,
                "name_zh": str(entry.get("name_zh", slug)),
                "component_family": str(entry.get("component_family", component["family"])),
                "room_type": room_type,
                "serves_room_types": [room_type],
                "scope": str(entry.get("scope", "shared")),
                "instance_count": len(component["members"]),
                "absorbed_variants": sorted(
                    str(packages[m].get("source_package_id", m))
                    for m in component["members"]
                    if m != component["rep_id"]
                ),
                "absorbed_geometry_exact_count": len(component["geometry_exact"]),
                "absorbed_geometry_variant": component["geometry_variant"],
                "absorbed_geometry_shape_mismatch": component["geometry_shape_mismatch"],
                "absorbed_classes": [
                    str(packages[c].get("source_package_id", c))
                    for c in component["absorbed_classes"]
                ],
                "variant_axis": str(entry.get("variant_axis", "")),
                "variant_value": str(entry.get("variant_value", "")),
                "variant_reason": str(entry.get("variant_reason", "")),
                "component_library_blend": "",
                "collection": f"{slug}_输出包",
                "editable_collection": f"{slug}_制作源",
                "bounds_size_m": rep_sig["bounds_size_m"],
                "bounds_lo_m": rep_sig["bounds_lo_m"],
                "bounds_hi_m": rep_sig["bounds_hi_m"],
                "origin_contract": "bottom-center of component bounds",
                "front_axis": str(entry.get("front_axis", "+Y")),
                "allowed_rotations_y_deg": list(DEFAULT_ROTATIONS),
                "collision_owner": str(entry.get("collision_owner", "self")),
                "palette_uv_layer": "PaletteUV",
                "material_roles": sorted({n for mats in rep_sig["materials"] for n in mats}),
                "source_package_id": str(
                    packages[component["rep_id"]].get("source_package_id", component["rep_id"])
                ),
                "source_library": source_lib.name,
            }
        )
    library_blend = args.library_blend_name or f"{version}_library.blend"
    for record in catalog_records:
        record["component_library_blend"] = f"{out_lib.as_posix()}/{library_blend}"
    catalog_records.sort(key=lambda item: str(item["slug"]))
    catalog = {
        "schema": "shellstorm2.component_catalog.v001",
        "component_library": f"{out_lib.as_posix()}/{library_blend}",
        "room_type": room_type,
        "block_id": str(source_catalog.get("block_id", "expedition")),
        "version": version,
        "source_room_type": str(source_catalog.get("source_room_type", "")),
        "source_room_type_sha256": str(source_catalog.get("source_room_type_sha256", "")),
        "source_package_list": str(source_catalog.get("component_library", "")),
        "source_catalog_sha256": sha256(source_lib / "component_catalog.json"),
        "runtime_connected": False,
        "ledger_registration": "pending",
        "packages": catalog_records,
        "independent_blend_count": len(catalog_records),
        "presentation": "separated component packages; isolated scene per component",
        "component_count": len(catalog_records),
        "regrouped_from": source_lib.name,
        "regroup_rule": (
            "族内几何等价类聚类（Z 轴旋转不变，容差 %sm）+ 同族最多 %d 类（skill 02）"
            % (args.tol, args.family_cap)
        ),
        "regroup_analysis": f"{out_lib.as_posix()}/regroup_analysis.json",
        "walk_plane_shift_z_m": shift_z,
        "output_mesh_count": sum(sigs[c["rep_id"]]["mesh_count"] for c in kept_components),
        "absorbed_geometry_variant_total": total_variant,
        "absorbed_geometry_shape_mismatch_total": total_shape,
        "door_slot_sealing": {
            "dropped_members": sorted(dropped_members),
            "sealed_members": {
                str(packages[m].get("source_package_id", m)): target
                for m, target in sorted(sealed_of.items())
            },
            "reason": (
                "02 规范要求房型源不冻结门位、不预切门洞；源里预切的门洞（门垛×2+门楣）"
                "与本关实际门位不一致，其净空是无门扇的洞。门垛丢弃、门楣改为整樘实墙，"
                "门位改由运行时按门槽车道把实墙提升为门墙。"
            ),
        },
    }
    instances_doc = {
        "schema": "shellstorm2.battle.component_instances",
        "schema_version": 1,
        "library": version,
        "room_type": room_type,
        "source_library": source_lib.name,
        "source_blend_sha256": sha256(source_lib / "component_catalog.json"),
        "instances": records,
        "validation": {
            "source_object_count": len(packages),
            "instance_count": len(records),
            "dropped_by_door_slot_sealing": len(dropped_members),
            "coverage_ok": len(records) + len(dropped_members) == len(packages),
            "rotation_inferred": True,
            "rotation_stats": {str(k): v for k, v in sorted(stats.items())},
        },
        "rotation_axis": "Z_blender (世界垂直轴；房间平面为 XY)",
        "rotation_inferred_from": "代表件与成员包输出网格顶点的 Z 轴 0/90/180/270 旋转不变等价（Blender 侧实测）",
    }
    analysis["component_count"] = len(catalog_records)
    analysis["door_slot_sealing"] = catalog["door_slot_sealing"]
    write_json(out_lib / "component_catalog.json", catalog)
    write_json(out_lib / "component_instances.json", instances_doc)
    write_json(out_lib / "regroup_analysis.json", analysis)
    print(f"REGROUP_CATALOG_WRITTEN:{len(catalog_records)}")
    print(f"REGROUP_INSTANCES_WRITTEN:{len(records)}")

    if not args.skip_master:
        built_master = out_lib / library_blend
        master_source = source_lib / str(source_catalog.get("component_library", "")).split("/")[-1]
        keep = {
            str(slug_table[c["rep_id"]]["slug"]): {
                "collection": str(packages[c["rep_id"]].get("collection", "")),
                "editable_collection": str(
                    packages[c["rep_id"]].get("editable_collection", "")
                ),
            }
            for c in kept_components
        }
        if master_source.is_file():
            info = trim_master(master_source, keep, built_master)
            print(
                "REGROUP_MASTER_WRITTEN:%s objects=%d meshes=%d collections=%d"
                % (
                    built_master.name,
                    info["master_objects"],
                    info["master_meshes"],
                    info["master_collections"],
                )
            )
        else:
            print(f"WARN: 母版源缺失，跳过 {master_source}")

    print("REGROUP_COMPLETE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
