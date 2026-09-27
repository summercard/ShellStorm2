"""B2 复核（只读）：断言每个库内「母版 + 全部分包」的 `02_细腻哑光` PBR 参数完全一致。

背景：本机各库历史参数不同（v002=0.02、v003=0.04、v006=0.04、v007/v008=0.03），
分包缺该材质时若用硬编码参数补建，就会出现「同库内参数打架」。
本脚本逐库收集 (metallic, roughness, coat) 集合，>1 即 FAIL。
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

import bpy

LIBRARIES = (
    ("office_room", "v006"),
    ("bridge_room", "v007"),
    ("boss_room", "v008"),
    ("l_corridor", "v002"),
    ("db_room", "v003"),
)
LIBRARY_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/source/common_components"
)
MATTE = "02_细腻哑光_青绿大面"


def params(material: bpy.types.Material) -> tuple[float, float, float] | None:
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


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--project-root", required=True)
    args = p.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")
    root = Path(args.project_root).resolve()
    report: dict = {}
    failures: list[str] = []
    for room_slug, version in LIBRARIES:
        lib = root / LIBRARY_ROOT / version
        catalog = json.loads((lib / "component_catalog.json").read_text(encoding="utf-8"))
        blends = [lib / f"expedition_{room_slug}_components_source_{version}.blend"]
        for package in catalog["packages"]:
            slug = package["slug"]
            blends.append(lib / "component_packages" / slug / f"{slug}.blend")
        seen: dict[tuple, list[str]] = collections.defaultdict(list)
        missing: list[str] = []
        for blend in blends:
            bpy.ops.wm.open_mainfile(filepath=str(blend))
            material = bpy.data.materials.get(MATTE)
            if material is None:
                missing.append(blend.name)
                continue
            conf = params(material)
            seen[conf].append(blend.name)
        print(
            "===== %s/%s：%d blend，哑光参数 %d 种，缺哑光 %d"
            % (room_slug, version, len(blends), len(seen), len(missing))
        )
        for conf, names in sorted(seen.items(), key=lambda kv: -len(kv[1])):
            print("   %s  ×%d" % (conf, len(names)))
        if len(seen) > 1 or missing:
            failures.append("%s/%s" % (room_slug, version))
        report[f"{room_slug}/{version}"] = {
            "blends": len(blends),
            "matte_conf": {str(k): len(v) for k, v in seen.items()},
            "missing_matte": missing,
        }
        print()
    out = root / "_scratch/palette_shift/matte_conf_consistency.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("WROTE:%s" % out)
    if failures:
        print("MATTE_CONF_CONSISTENCY_FAIL:%s" % ", ".join(failures))
        return 1
    print("MATTE_CONF_CONSISTENCY_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
