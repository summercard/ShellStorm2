"""从 l_corridor/v003 房型源 blend 实测 121 个包的世界原点，补进组件库 v002 的 catalog，
并装配一份「归并工具可直接吃的 old_lib」（junction 指向真实件，不占空间）。

背景：走廊组件库 `common_components/v002`（旧 schema，121 包）的 `source_world_origin_m`
全为 None —— 因为它的源包清单 `l_corridor/v003/component_packages/catalog.json` 只有
`package_id / path / object_count` 三个键，没有 `world_origin_m`（数据库库 v003 的源清单有，
所以那本不为空）。归并工具要用这个字段生成实例位置，必须先补回来。

口径与 `decompose_room_type_components.py` 完全一致：
    origin = [bbox x 中心, bbox y 中心, bbox z 最小]

包 → 源集合的映射走源目录里每个包的 `asset_manifest.json`（含 `collection` 名）。

用法::
    blender --factory-startup --background --python _scratch/corridor_db_plan/fill_corridor_origins.py -- \
        --project-root <root>
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    return parser.parse_args(argv)


def world_points(collection) -> list:
    points = []
    stack = [collection]
    while stack:
        coll = stack.pop()
        stack.extend(coll.children)
        for obj in coll.objects:
            if obj.type != "MESH":
                continue
            points.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
    return points


def link_or_copy_dir(src: Path, dst: Path) -> str:
    if dst.exists():
        return "exists"
    proc = subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(dst), str(src)],
        capture_output=True, text=True,
    )
    if proc.returncode == 0:
        return "junction"
    shutil.copytree(src, dst)
    return "copied"


def link_or_copy_file(src: Path, dst: Path) -> str:
    if dst.exists():
        return "exists"
    try:
        subprocess.run(
            ["cmd", "/c", "mklink", "/H", str(dst), str(src)],
            capture_output=True, text=True, check=True,
        )
        return "hardlink"
    except Exception:
        shutil.copy2(src, dst)
        return "copied"


def main() -> int:
    args = parse_args()
    root = Path(args.project_root).resolve()
    lib = root / "assets/art/environments/tower_zones/expedition/source/common_components/v002"
    room = root / "assets/art/environments/tower_zones/expedition/source/room_types/l_corridor/v003"
    out_dir = root / "_scratch/corridor_db_plan/corridor/old_lib"
    out_dir.mkdir(parents=True, exist_ok=True)

    catalog = json.loads((lib / "component_catalog.json").read_text(encoding="utf-8"))
    packages = catalog["packages"]

    collection_by_pid: dict[str, str] = {}
    for manifest_path in sorted(room.glob("**/asset_manifest.json")):
        row = json.loads(manifest_path.read_text(encoding="utf-8"))
        pid = str(row.get("package_id") or "")
        if pid:
            collection_by_pid[pid] = str(row.get("collection") or "")
    print("源 asset_manifest 数:", len(collection_by_pid))

    blend = next(p for p in sorted(room.glob("*.blend")))
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    colls = {c.name: c for c in bpy.data.collections}
    print("源 blend 集合数:", len(colls))

    resolved = 0
    unresolved: list[str] = []
    for package in packages:
        pid = str(package.get("source_package_id") or package["component_id"])
        cname = collection_by_pid.get(pid, "")
        coll = colls.get(cname)
        if coll is None:
            unresolved.append(f"{pid} :: collection={cname!r}")
            continue
        points = world_points(coll)
        if not points:
            unresolved.append(f"{pid} :: empty collection {cname!r}")
            continue
        lo = [min(p[i] for p in points) for i in range(3)]
        hi = [max(p[i] for p in points) for i in range(3)]
        package["source_world_origin_m"] = [
            round((lo[0] + hi[0]) / 2.0, 6),
            round((lo[1] + hi[1]) / 2.0, 6),
            round(lo[2], 6),
        ]
        package["source_world_bounds_lo_m"] = [round(v, 6) for v in lo]
        package["source_world_bounds_hi_m"] = [round(v, 6) for v in hi]
        resolved += 1

    catalog["source_world_origin_note"] = (
        "本库源包清单无 world_origin_m；坐标由 _scratch/corridor_db_plan/fill_corridor_origins.py "
        "从 l_corridor/v003 源 blend 按每包 collection 的网格世界包围盒实测（bottom-center，口径同 decompose）。"
    )
    (out_dir / "component_catalog.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    master_name = str(catalog.get("component_library", "")).split("/")[-1]
    print("\n装配 old_lib：", out_dir)
    print("  component_packages ->", link_or_copy_dir(lib / "component_packages", out_dir / "component_packages"))
    if master_name:
        print("  %s -> %s" % (master_name, link_or_copy_file(lib / master_name, out_dir / master_name)))

    print("\n--- 墙件世界包围盒（含 WALL/CUTAWAY）---")
    for package in sorted(packages, key=lambda p: str(p["component_id"])):
        cid = str(package["component_id"])
        if not any(t in cid for t in ("WALL", "CUTAWAY")):
            continue
        print("  %-52s size=%-26s lo=%-34s hi=%s" % (
            cid.split("L-CORRIDOR-")[-1],
            str(package.get("bounds_size_m")),
            str(package.get("source_world_bounds_lo_m")),
            str(package.get("source_world_bounds_hi_m")),
        ))

    print("\nORIGINS_RESOLVED:%d / %d" % (resolved, len(packages)))
    for line in unresolved:
        print("  !! UNRESOLVED:", line)
    print("ORIGINS_%s" % ("OK" if not unresolved else "PARTIAL"))
    return 0 if not unresolved else 1


if __name__ == "__main__":
    sys.exit(main())
