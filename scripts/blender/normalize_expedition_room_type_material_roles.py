"""房型组件材质角色校正 —— 「大面积亚光、小部分金属/反光」的**每组件主面判据**。

背景：房型源的建模脚本把精工金属（metallic 0.86 / rough 0.26）当成结构件的默认材质
（`box(..., mat=0, cell=PANEL)`），于是管道、桥架、吊顶、机柜、门垛这类**大面**全成了高金属度。
Godot 侧没有反射来源（`reflected_light_source = SKY` 但无天空，全项目无 ReflectionProbe），
金属面只剩直接高光 ⇒ 大面积发黑。项目其它房间的结构面统一用「细腻哑光」（metallic 0.03）。

## 判据（每组件内，按**面积**而非面数）
`金属面积 >= 哑光面积 + 反光面积` ⇒ 金属不是「小部分」，按槽面积**从大到小**改哑光，
直到 `金属面积 < 哑光面积 + 反光面积` 为止（或金属清空）。
- 大面积结构件（管道/桥架/吊顶/机柜/货架/警示带/地面标识）⇒ 变哑光，恢复受光。
- 面积本来就小的金属件（工位/座椅/档案架/碎屑/墙体金属压条）⇒ 保留金属。
- 屏幕/玻璃（`03_清漆反光`）与自发光（`04_柔和自发光`）不参与判定也不被改，语义保留。

**不新增材质球种类、不改既有 PBR 参数**：只把槽指向已有的 `02_细腻哑光_青绿大面`；
几何、UV、色盘格一律不动（配色由 `lighten_expedition_room_type_palette_uv.py` 负责）。
个别**分包**本来就只带金属/自发光、库里根本没有哑光数据块（实测 30 个：v002 走廊 29 + v008 heavy_conduits），
此时按**本库母版既有哑光的实际 PBR 参数**补建同名数据块（`master_matte_conf`），
保证同库内所有组件的哑光参数一致；母版也没有才退回 `MATTE_CONF_FALLBACK`。
幂等：校正后金属已非「大面积」，重复执行 0 改动。

分组口径（**平衡单元 = 组件 × 镜像集合**）：母版里一个组件有 `_制作源` 与 `_输出包` 两套镜像集合，
两者必须**各自独立**跑判据，不能合并。

为什么不能合并：判据是「改到金属成为小部分就停」的**中途停止**规则。合并后两套镜像面积相加，
转一个槽就能满足 `金属 < 哑光`，于是只改掉镜像 A、镜像 B 原封不动 —— 而导出链只取 `_输出_` 那一侧，
正好可能把该改的一侧漏掉（实测 boss `server_rack` 输出包 211.09 m² 仍为金属，27 个包因此未达标）。
两套镜像几何同倍率、槽结构一致，独立判据会得到完全相同的结论，因此结果自洽。

集合名判定必须先剥掉 Blender 的重名去重后缀（`.001`/`.002`）：走廊母版有 16 个
`X_输出包.001` 这类集合，不剥后缀就会被漏判并并进 `<未分组>` 一起判（实测 6 个包因此未达标）。

Run with Blender 4.5+:
  blender --factory-startup --background --python <this> -- --project-root <root> [--dry-run]
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

import bpy

LIBRARIES = (
    ("office_room", "v009"),
    ("bridge_room", "v010"),
    ("boss_room", "v011"),
    ("l_corridor", "v002"),
    ("db_room", "v003"),
)
LIBRARY_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/source/common_components"
)
SHARED_PALETTE = Path("assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
REPORT_REL = Path(
    "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
    "/material_role_correction.json"
)

METAL_ROLE_PREFIX = "01_精工金属"
MATTE_ROLE = "02_细腻哑光_青绿大面"
GLOSS_ROLE_PREFIX = "03_清漆反光"
EMISSIVE_ROLE_PREFIX = "04_柔和自发光"
## 仅在库里缺 `02_细腻哑光` 时用于新建。**优先取本库母版既有哑光的实际 PBR 参数**
## （见 `master_matte_conf`）—— 本机各库历史参数并不统一（实测母版：v002=0.02/0.70、
## v003=0.04/0.72、v006=0.04/0.72、v007=0.03/0.70、v008=0.03/0.70），
## 用本表硬编码会让同一库里的分包与母版参数打架。
MATTE_CONF_FALLBACK = (0.03, 0.70, 0.0)
COMPONENT_SUFFIXES = ("_输出包", "_制作源", "_扩展资产包_输出包", "_扩展资产包_制作源")
## Blender 对**重名集合**自动追加 `.001`/`.002`…；判定镜像集合时必须先剥掉它再比后缀，
## 否则 `固定维修设备箱_输出包.001` 漏判、其对象被并进 `<未分组>` 一起判（走廊母版有 16 个这种集合）。
_DEDUP_RE = re.compile(r"\.\d{3}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--libraries", default="", help="逗号分隔 room_slug")
    parser.add_argument("--report", default="")
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def role_of(name: str) -> str:
    if name.startswith(METAL_ROLE_PREFIX):
        return "metal"
    if name.startswith(MATTE_ROLE):
        return "matte"
    if name.startswith(GLOSS_ROLE_PREFIX):
        return "gloss"
    if name.startswith(EMISSIVE_ROLE_PREFIX):
        return "emissive"
    return "other"


def material_conf(material: bpy.types.Material) -> tuple[float, float, float] | None:
    """读 Principled BSDF 的 (metallic, roughness, coat)；不是节点材质则 None。"""
    if not material.use_nodes:
        return None
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return (
                round(node.inputs["Metallic"].default_value, 4),
                round(node.inputs["Roughness"].default_value, 4),
                round(node.inputs["Coat Weight"].default_value, 4),
            )
    return None


def master_matte_conf(root: Path, room_slug: str, version: str) -> tuple[float, float, float]:
    """从本库母版读既有 `02_细腻哑光` 的 PBR 参数；母版缺失该材质时退回 MATTE_CONF_FALLBACK。"""
    master = (
        root
        / LIBRARY_ROOT
        / version
        / f"expedition_{room_slug}_components_source_{version}.blend"
    )
    if not master.is_file():
        return MATTE_CONF_FALLBACK
    bpy.ops.wm.open_mainfile(filepath=str(master))
    existing = bpy.data.materials.get(MATTE_ROLE)
    if existing is None:
        return MATTE_CONF_FALLBACK
    conf = material_conf(existing)
    return conf if conf is not None else MATTE_CONF_FALLBACK


def ensure_matte_material(
    conf: tuple[float, float, float], palette_path: Path
) -> bpy.types.Material:
    existing = bpy.data.materials.get(MATTE_ROLE)
    if existing is not None:
        return existing
    metallic, roughness, coat = conf
    material = bpy.data.materials.new(MATTE_ROLE)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    texture = nodes.new("ShaderNodeTexImage")
    if palette_path.is_file():
        texture.image = bpy.data.images.load(str(palette_path), check_existing=True)
    texture.interpolation = "Closest"
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    output = nodes.new("ShaderNodeOutputMaterial")
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Coat Weight"].default_value = coat
    links.new(uv.outputs["UV"], texture.inputs["Vector"])
    links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    print(
        "  ! 新建材质 %s（metallic=%s rough=%s coat=%s）"
        % (MATTE_ROLE, metallic, roughness, coat)
    )
    return material


def mirror_suffix(name: str) -> str | None:
    """集合名（剥掉 Blender 去重后缀后）命中的镜像后缀；不是镜像集合则 None。"""
    base = _DEDUP_RE.sub("", name)
    for suffix in COMPONENT_SUFFIXES:
        if base.endswith(suffix):
            return suffix
    return None


def component_key(obj: bpy.types.Object) -> str:
    """平衡单元 = 带镜像后缀的集合名（`X_输出包` 与 `X_制作源` 分开判定）。

    重名集合（`X_输出包.001`）是**独立的平衡单元**，不能与 `X_输出包` 合并。
    """
    names = [c.name for c in obj.users_collection]
    for suffix in COMPONENT_SUFFIXES:  # 按规范后缀优先序挑，避免 `_输出包` / `_扩展资产包_输出包` 歧义
        hit = next((n for n in names if mirror_suffix(n) == suffix), None)
        if hit:
            return hit
    return "<未分组>"


def component_of(unit: str) -> str:
    """从平衡单元名还原组件名（仅用于报告可读性）：`X_输出包.001` -> `X.001`。"""
    for suffix in COMPONENT_SUFFIXES:
        base = _DEDUP_RE.sub("", unit)
        if base.endswith(suffix):
            return base[: -len(suffix)] + unit[len(base) :]
    return unit


def collect_slot_areas() -> dict[str, dict]:
    """按组件归组，统计每个 (对象, 槽位, 材质) 的面数/面积与按角色的面积小计。"""
    groups: dict[str, dict] = collections.defaultdict(
        lambda: {"slots": [], "roles": collections.Counter(), "objects": 0}
    )
    seen: set[int] = set()
    ungrouped: list[str] = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.material_slots:
            continue
        me = obj.data
        if me.as_pointer() in seen:
            continue
        seen.add(me.as_pointer())
        key = component_key(obj)
        if key == "<未分组>":
            ungrouped.append(
                "%s -> %s" % (obj.name, sorted(c.name for c in obj.users_collection))
            )
        group = groups[key]
        group["objects"] += 1
        per_slot_faces = collections.Counter()
        per_slot_area = collections.Counter()
        for poly in me.polygons:
            per_slot_faces[poly.material_index] += 1
            per_slot_area[poly.material_index] += poly.area
        fused = collections.Counter()
        for index, slot in enumerate(obj.material_slots):
            material = slot.material
            if material is None:
                continue
            role = role_of(material.name)
            area = per_slot_area.get(index, 0.0)
            faces = per_slot_faces.get(index, 0)
            group["roles"][role] += area
            if role == "other":
                fused[material.name] += area
            group["slots"].append(
                {
                    "object": obj.name,
                    "slot": index,
                    "material": material.name,
                    "role": role,
                    "area_m2": round(area, 6),
                    "faces": faces,
                }
            )
        for name, area in fused.items():
            print("  ! 未知材质角色 %s（%.2f m²）在 %s" % (name, area, obj.name))
    if ungrouped:
        print("  ! 有 %d 个网格对象未归入任何镜像集合（将被并成一组判定）：" % len(ungrouped))
        for line in ungrouped[:20]:
            print("      %s" % line)
        if len(ungrouped) > 20:
            print("      …（另有 %d 个）" % (len(ungrouped) - 20))
    else:
        print("  · 全部网格对象均已归入镜像集合（未分组=0）")
    return groups


def balance_group(group: dict) -> tuple[list[dict], dict]:
    """在组件内按「大面积亚光」判据挑出要改哑光的槽。返回 (待改槽, 判决)。"""
    roles = group["roles"]
    matte = roles.get("matte", 0.0)
    gloss = roles.get("gloss", 0.0)
    metal_slots = [s for s in group["slots"] if s["role"] == "metal" and s["area_m2"] > 0]
    metal = sum(s["area_m2"] for s in metal_slots)
    decision = {
        "metal_area_m2": round(metal, 3),
        "matte_area_m2": round(matte, 3),
        "gloss_area_m2": round(gloss, 3),
        "emissive_area_m2": round(roles.get("emissive", 0.0), 3),
    }
    if metal == 0:
        decision["verdict"] = "无金属，跳过"
        return [], decision
    if metal < matte + gloss:
        decision["verdict"] = "金属已是小部分，保留"
        return [], decision
    convert: list[dict] = []
    for slot in sorted(metal_slots, key=lambda s: -s["area_m2"]):
        convert.append(slot)
        metal -= slot["area_m2"]
        matte += slot["area_m2"]
        if metal < matte + gloss:
            break
    decision["verdict"] = "金属为大面积 ⇒ 由大到小改哑光 %d 槽" % len(convert)
    decision["metal_area_after_m2"] = round(metal, 3)
    decision["matte_area_after_m2"] = round(matte, 3)
    return convert, decision


def remap_blend(
    blend_path: Path,
    matte_conf: tuple[float, float, float],
    palette_path: Path,
    dry_run: bool,
) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    groups = collect_slot_areas()
    record: dict = {
        "blend": blend_path.as_posix(),
        "groups": {},
        "slots_replaced": 0,
        "faces_affected": 0,
        "saved": False,
    }
    matte = None
    for key in sorted(groups):
        group = groups[key]
        convert, decision = balance_group(group)
        if convert and matte is None:
            matte = ensure_matte_material(matte_conf, palette_path)
        faces = 0
        for entry in convert:
            obj = bpy.data.objects.get(entry["object"])
            if obj is None:
                raise KeyError(entry["object"])
            obj.material_slots[entry["slot"]].material = matte
            record["slots_replaced"] += 1
            faces += entry["faces"]
        record["faces_affected"] += faces
        record["groups"][key] = {
            **decision,
            "component": component_of(key),
            "converted": [
                {
                    "object": e["object"],
                    "slot": e["slot"],
                    "from": e["material"],
                    "area_m2": round(e["area_m2"], 3),
                    "faces": e["faces"],
                }
                for e in convert
            ],
        }
    if record["slots_replaced"] and not dry_run:
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
        record["saved"] = True
    return record


def library_targets(root: Path, room_slug: str, version: str) -> list[Path]:
    library_root = root / LIBRARY_ROOT / version
    catalog = json.loads(
        (library_root / "component_catalog.json").read_text(encoding="utf-8")
    )
    targets: list[Path] = []
    master = library_root / f"expedition_{room_slug}_components_source_{version}.blend"
    if master.is_file():
        targets.append(master)
    for package in catalog["packages"]:
        slug = package["slug"]
        blend = library_root / "component_packages" / slug / f"{slug}.blend"
        if not blend.is_file():
            raise FileNotFoundError(blend)
        targets.append(blend)
    return targets


def main() -> None:
    args = parse_args()
    root = Path(args.project_root).resolve()
    palette_path = root / SHARED_PALETTE
    wanted = {t for t in args.libraries.split(",") if t}
    records: list[dict] = []
    for room_slug, version in LIBRARIES:
        if wanted and room_slug not in wanted:
            continue
        targets = library_targets(root, room_slug, version)
        matte_conf = master_matte_conf(root, room_slug, version)
        print(
            "==== %s / %s 目标 blend %d 个，本库哑光参数 %s"
            % (room_slug, version, len(targets), matte_conf)
        )
        for blend in targets:
            rec = remap_blend(blend, matte_conf, palette_path, args.dry_run)
            rec.update(
                {
                    "room_type": room_slug,
                    "version": version,
                    "matte_conf": list(matte_conf),
                }
            )
            records.append(rec)
            print(
                "  %-46s 槽=%-5d 面=%-7d 平衡组=%d%s"
                % (
                    blend.name,
                    rec["slots_replaced"],
                    rec["faces_affected"],
                    len(rec["groups"]),
                    "" if rec["saved"] else "（未改）",
                )
            )
        print()
    if args.dry_run:
        print("DRY-RUN：未写任何 blend")
    report_path = root / (args.report or REPORT_REL)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(
            {
                "schema": "shellstorm2.expedition.room_type_material_role_correction.v002",
                "policy": (
                    "每组件主面判据：金属面积 >= 哑光+反光面积 ⇒ 按槽面积从大到小改哑光，"
                    "直到金属 < 哑光+反光。只改槽指向，不动 PBR 参数、几何、UV、色盘格。"
                    "平衡单元 = 组件 × 镜像集合（_输出包 与 _制作源 各自独立判定，"
                    "集合名先剥掉 Blender 重名去重后缀 .001/.002）。"
                    "库内缺 02_细腻哑光 数据块时按本库母版实际参数补建同名数据块。"
                ),
                "from_role": METAL_ROLE_PREFIX,
                "to_role": MATTE_ROLE,
                "libraries": [f"{a}/{b}" for a, b in LIBRARIES],
                "records": records,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    slots = sum(r["slots_replaced"] for r in records)
    faces = sum(r["faces_affected"] for r in records)
    print(
        "ROOM_TYPE_MATERIAL_ROLE_NORMALIZED:blends=%d slots=%d faces=%d => %s"
        % (len(records), slots, faces, report_path)
    )


if __name__ == "__main__":
    main()
