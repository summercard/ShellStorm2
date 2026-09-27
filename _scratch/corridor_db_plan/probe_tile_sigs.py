"""探针：把指定库里的地砖包逐个打开，打印「兼容性签名」（网格数 / 每网格顶点数 / 材质多重集）。

归并工具的 `compatible()` 要求这四项完全一致才允许「记录为变体」；不一致就记
`geometry_shape_mismatch`（真正的几何丢失）。本探针用来判断某个族要不要靠
`--family-cap-overrides` 放宽上限，还是该把族拆细。

用法::
    blender --factory-startup --background --python probe_tile_sigs.py -- \
        --project-root <root> --source-lib <rel> --match <component_id 子串>
"""

from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

import bpy

_argv = sys.argv
_args = _argv[_argv.index("--") + 1 :] if "--" in _argv else []
ARGS = dict(zip(_args[0::2], _args[1::2]))

ROOT = Path(ARGS["--project-root"]).resolve()
SOURCE_LIB = (ROOT / ARGS["--source-lib"]).resolve()
MATCH = ARGS.get("--match", "")
PART_SUFFIX_RE = __import__("re").compile(r"_输出_")


def package_dir_name(package: dict) -> str:
    for key in ("source_package_id", "slug", "component_id"):
        name = str(package.get(key) or "").strip()
        if name and (SOURCE_LIB / "component_packages" / name).is_dir():
            return name
    return ""


def sig() -> dict:
    meshes = [
        obj
        for obj in bpy.data.objects
        if obj.type == "MESH" and PART_SUFFIX_RE.search(obj.name)
    ]
    return {
        "mesh_count": len(meshes),
        "vertex_counts": sorted(len(obj.data.vertices) for obj in meshes),
        "materials": sorted(
            {slot.material.name for obj in meshes for slot in obj.material_slots if slot.material}
        ),
    }


def main() -> int:
    catalog = json.loads(
        (SOURCE_LIB / "component_catalog.json").read_text(encoding="utf-8")
    )
    rows = [p for p in catalog["packages"] if MATCH in str(p["component_id"])]
    print("匹配包数 %d（过滤 %r）" % (len(rows), MATCH))
    groups: dict[tuple, list[str]] = collections.defaultdict(list)
    for row in rows:
        pkg = package_dir_name(row)
        blend = SOURCE_LIB / "component_packages" / pkg / ("%s.blend" % pkg)
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        data = sig()
        key = (
            data["mesh_count"],
            tuple(data["vertex_counts"]),
            tuple(data["materials"]),
        )
        groups[key].append(str(row["component_id"]))
    print("兼容性分组 %d 组：" % len(groups))
    for key, ids in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        print(
            "  成员 %-3d 网格 %-2d 顶点 %s 材质 %s"
            % (len(ids), key[0], list(key[1]), [m[:14] for m in key[2]])
        )
        print("        " + ", ".join(sorted(i.split("-")[-1] for i in ids)))
    print("TILE_SIG_GROUPS:%d" % len(groups))
    return 0


if __name__ == "__main__":
    sys.exit(main())
