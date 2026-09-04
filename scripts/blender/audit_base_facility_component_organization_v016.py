#!/usr/bin/env python3
"""Read-only organization audit for Base Facility v016."""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VERSION = args[0] if args else "v016"
BLEND = PROJECT / f"source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_{VERSION}.blend"
PACKAGE_ROOT = PROJECT / f"source/art/blender/base_facility_layout/component_packages_{VERSION}"
VERIFY = PROJECT / f"outputs/verification/base_facility_runtime_layout_hq_{VERSION}"
REPORT = VERIFY / f"base_facility_component_organization_audit_{VERSION}.json"
MARKDOWN = VERIFY / f"base_facility_component_organization_audit_{VERSION}.md"


def asset_packages():
    return sorted((c for c in bpy.data.collections if c.get("资产包")), key=lambda c: c.name)


def descendants(coll):
    result = set(coll.objects)
    for child in coll.children:
        result.update(descendants(child))
    return result


def owner_packages(obj, packages):
    return sorted(c for c in obj.users_collection if c in packages)


def semantic_stem(name: str) -> str:
    name = name.replace("__源", "").replace("_源组件", "")
    name = re.sub(r"^v\d+_", "", name)
    name = re.sub(r"v\d{3,}", "", name)
    name = re.sub(r"_[0-9]+(?:\.[0-9]+)?$", "", name)
    return name.split("_")[0].strip()


if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("start audit from v016 only")

packages = asset_packages()
package_set = set(packages)
output_roots = [c for c in bpy.data.collections if c.name.startswith("02_游戏输出")]
output_objects = set().union(*(descendants(c) for c in output_roots)) if output_roots else set()
output_objects = {o for o in output_objects if o.type not in {"CAMERA", "LIGHT"} or any(c in package_set for c in o.users_collection)}

multi_package_owners = {}
unpackaged_output_objects = []
unpackaged_output_details = []
for obj in sorted(output_objects, key=lambda o: o.name):
    owners = owner_packages(obj, package_set)
    if len(owners) > 1:
        multi_package_owners[obj.name] = [c.name for c in owners]
    if not owners:
        unpackaged_output_objects.append(obj.name)
        unpackaged_output_details.append({
            "object": obj.name,
            "type": obj.type,
            "collections": sorted(c.name for c in obj.users_collection),
            "custom_scope_tags": sorted(k for k in obj.keys() if k.startswith("v0") or "scope" in k.lower()),
        })

empty_packages = [c.name for c in packages if not c.objects]
package_rows = []
for pkg in packages:
    slug = pkg.get("资产包键", pkg.name)
    category = pkg.get("资产类别", "uncategorized")
    objects = sorted(pkg.objects, key=lambda o: o.name)
    manifest = PACKAGE_ROOT / category / slug / "asset_manifest.json"
    manifest_ok = False
    manifest_count_match = False
    manifest_names_match = False
    manifest_error = None
    if manifest.exists():
        try:
            doc = json.loads(manifest.read_text(encoding="utf-8"))
            manifest_ok = True
            manifest_count_match = doc.get("object_count") == len(objects)
            manifest_names_match = doc.get("object_names") == [o.name for o in objects]
        except Exception as exc:
            manifest_error = str(exc)
    package_rows.append({
        "collection": pkg.name,
        "slug": slug,
        "category": category,
        "object_count": len(objects),
        "manifest": str(manifest.relative_to(PROJECT)),
        "manifest_exists": manifest_ok,
        "manifest_count_match": manifest_count_match,
        "manifest_names_match": manifest_names_match,
        "manifest_error": manifest_error,
        "v016_additions": sum(bool(o.get("v016_scope")) for o in objects),
    })

manifest_mismatches = [r for r in package_rows if not (r["manifest_exists"] and r["manifest_count_match"] and r["manifest_names_match"])]
count_by_category = Counter(r["category"] for r in package_rows)

# Source hierarchy audit: sources should mirror their output facility if a source package exists.
source_root = bpy.data.collections.get("01_制作组件_已统一材质")
direct_source_objects = list(source_root.objects) if source_root else []
all_source_objects = descendants(source_root) if source_root else set()
source_pair_map = {}
unmapped_sources = []
unmirrored_sources = []
for src in sorted((o for o in all_source_objects if o.name.endswith("__源") or o.name.endswith("_源组件")), key=lambda o: o.name):
    candidates = [src.name.replace("__源", ""), src.name.replace("_源组件", "")]
    out = next((bpy.data.objects.get(candidate) for candidate in candidates if bpy.data.objects.get(candidate)), None)
    if out is None:
        unmapped_sources.append(src.name)
        continue
    owners = owner_packages(out, package_set)
    source_pair_map[src.name] = {
        "output": out.name,
        "output_package": owners[0].get("资产包键") if len(owners) == 1 else None,
        "source_collections": sorted(c.name for c in src.users_collection),
    }
    if not any(c.name.startswith(f"{VERSION}_源资产包_") for c in src.users_collection):
        unmirrored_sources.append(src.name)

# Potential composite packages: flags are review candidates rather than automatic errors.
safe_group_words = ("管线", "照明", "灯光", "蒸汽", "尘埃", "动效", "栏杆", "墙体", "地砖")
composite_candidates = []
for row in package_rows:
    name = row["collection"]
    implied_multi = any(word in name for word in ("与", "及", "和", "组"))
    high_density = row["object_count"] >= 60
    if (implied_multi or high_density) and not any(word in name for word in safe_group_words):
        recommendation = "确认全部对象均为同一设施不可拆分的固定附件；若其中存在可独立替换/隐藏/导出的物件，应拆为独立资产包。"
        composite_candidates.append({**row, "reason": "名称含组合语义" if implied_multi else "对象数量较高", "recommendation": recommendation})

# Object stems spanning packages: useful to spot facility pieces scattered across folders.
stems = defaultdict(lambda: defaultdict(list))
for pkg in packages:
    for obj in pkg.objects:
        stem = semantic_stem(obj.name)
        if len(stem) >= 2:
            stems[stem][pkg.get("资产包键", pkg.name)].append(obj.name)
generic_stems = {"螺栓", "螺丝", "灯", "灯带", "标签", "标识", "支架", "面板", "线缆", "线束", "按钮", "管线", "地砖", "护栏", "栏杆", "挂钩", "图标"}
cross_package_stems = []
for stem, groups in stems.items():
    if len(groups) >= 2 and stem not in generic_stems:
        cross_package_stems.append({
            "stem": stem,
            "package_count": len(groups),
            "packages": {slug: len(items) for slug, items in sorted(groups.items())},
        })
cross_package_stems.sort(key=lambda item: (-item["package_count"], item["stem"]))

checks = {
    "asset_packages": len(packages),
    "empty_asset_packages": len(empty_packages),
    "output_objects_without_asset_package": len(unpackaged_output_objects),
    "objects_in_multiple_asset_packages": len(multi_package_owners),
    "disk_manifest_count": len(list(PACKAGE_ROOT.rglob("asset_manifest.json"))),
    "manifest_mismatches": len(manifest_mismatches),
    "direct_ungrouped_source_objects": len(direct_source_objects),
    "source_objects_total": len(all_source_objects),
    "sources_without_output_name_pair": len(unmapped_sources),
    f"{VERSION}_sources_not_in_mirrored_source_package": len(unmirrored_sources),
    "composite_package_review_candidates": len(composite_candidates),
    "cross_package_semantic_stem_candidates": len(cross_package_stems),
}
report = {
    "schema": "shellstorm2.base_facility.component_organization_audit.v1",
    "mode": "read_only",
    "blend": str(BLEND.relative_to(PROJECT)),
    "checks": checks,
    "counts_by_category": dict(sorted(count_by_category.items())),
    "empty_packages": empty_packages,
    "unpackaged_output_objects": unpackaged_output_objects,
    "unpackaged_output_details": unpackaged_output_details,
    "multi_package_owners": multi_package_owners,
    "manifest_mismatches": manifest_mismatches,
    "source_audit": {
        "direct_source_objects": len(direct_source_objects),
        "direct_source_examples": sorted(o.name for o in direct_source_objects)[:200],
        "all_source_objects": len(all_source_objects),
        "unmapped_source_examples": unmapped_sources[:100],
        f"{VERSION}_sources_not_mirrored": unmirrored_sources,
        "pair_examples": dict(list(source_pair_map.items())[:40]),
    },
    "composite_package_review_candidates": composite_candidates,
    "cross_package_semantic_stem_candidates": cross_package_stems[:100],
    "package_rows": package_rows,
}
VERIFY.mkdir(parents=True, exist_ok=True)
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = [
    f"# Base Facility {VERSION} 组件归类只读审计",
    "",
    "## 硬性归类结果",
    "",
    f"- 末级资产包：{checks['asset_packages']}",
    f"- 空资产包：{checks['empty_asset_packages']}",
    f"- 输出对象未归属资产包：{checks['output_objects_without_asset_package']}",
    f"- 输出对象多包归属：{checks['objects_in_multiple_asset_packages']}",
    f"- 磁盘 manifest：{checks['disk_manifest_count']}；不一致：{checks['manifest_mismatches']}",
    "",
    "## 需人工决策的拆分候选",
    "",
]
for item in composite_candidates:
    lines.append(f"- `{item['slug']}` / {item['collection']}：{item['object_count']} 对象；{item['reason']}。{item['recommendation']}")
lines += ["", "## 源组件归类", "", f"- 仍直接混放在旧制作根集合的源对象：{checks['direct_ungrouped_source_objects']}", f"- {VERSION} 源对象未镜像归类：{checks[f'{VERSION}_sources_not_in_mirrored_source_package']}", f"- 无法按名称配对输出对象的旧源对象：{checks['sources_without_output_name_pair']}", ""]
MARKDOWN.write_text("\n".join(lines), encoding="utf-8")
print(json.dumps({"checks": checks, "composite_candidates": [x['slug'] for x in composite_candidates], "cross_package_stem_count": len(cross_package_stems)}, ensure_ascii=False))
