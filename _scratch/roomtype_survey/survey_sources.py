"""只读勘察：列出两个房型源 blend 的对象结构。

路径硬编码（避开 bash 中文参数转码坑）。用法:
    blender -b --python survey_sources.py
"""
from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")

TARGETS = {
    "l_corridor_v003": ROOT
    / "assets/art/environments/tower_zones/expedition/source/room_types/l_corridor/v003"
    / "L型走廊种类_数据连廊_45x40m_v003.blend",
    "db_room_v001": ROOT
    / "assets/art/environments/tower_zones/expedition/source/room_types/db_room/v001"
    / "数据库房间种类_数据机房_40x30m_v001.blend",
}

OUT = ROOT / "_scratch/roomtype_survey/survey.json"


def survey(path: Path) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    objs = list(bpy.data.objects)
    meshes = [o for o in objs if o.type == "MESH"]

    coll_of: dict[str, list[str]] = defaultdict(list)
    for c in bpy.data.collections:
        for o in c.objects:
            coll_of[c.name].append(o.name)

    rows = []
    for o in meshes:
        ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = Vector((min(p.x for p in ws), min(p.y for p in ws), min(p.z for p in ws)))
        hi = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
        size = hi - lo
        rows.append(
            {
                "name": o.name,
                "verts": len(o.data.vertices),
                "polys": len(o.data.polygons),
                "materials": [m.name if m else None for m in o.data.materials],
                "size": [round(v, 3) for v in size],
                "center": [round(v, 3) for v in (lo + hi) / 2.0],
                "collections": [c.name for c in o.users_collection],
            }
        )
    rows.sort(key=lambda r: -r["verts"])
    return {
        "blend": str(path).replace("\\", "/"),
        "object_count": len(objs),
        "types": dict(Counter(o.type for o in objs)),
        "mesh_count": len(meshes),
        "collections": {k: len(v) for k, v in sorted(coll_of.items())},
        "meshes": rows,
        "total_verts": sum(r["verts"] for r in rows),
    }


def main() -> None:
    result = {}
    for key, path in TARGETS.items():
        if not path.exists():
            result[key] = {"error": f"missing: {path}"}
            continue
        result[key] = survey(path)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"SURVEY_WRITTEN: {OUT}")
    for key, d in result.items():
        if "error" in d:
            print(f"  {key}: {d['error']}")
            continue
        print(
            f"  {key}: objects={d['object_count']} meshes={d['mesh_count']}"
            f" collections={len(d['collections'])} verts={d['total_verts']}"
        )


main()
