"""只读实测：统计各库/源场景用到的色盘格与材质角色分布。

判据：
  · 每个 mesh 的 `PaletteUV` 层，按「逐面 UV 岛质心」落到 (u格, v格)。
  · UV 原点在左下，图面第 r 行（自上而下 0..9）对应 v 格 = 9-r。
  · 材质角色按材质名聚合统计面数。
"""

from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
BLENDS = [
    ("office_v004", "assets/art/environments/tower_zones/expedition/source/common_components/v004/expedition_office_room_components_source_v004.blend"),
    ("office_v006", "assets/art/environments/tower_zones/expedition/source/common_components/v006/expedition_office_room_components_source_v006.blend"),
    ("bridge_v005", "assets/art/environments/tower_zones/expedition/source/common_components/v005/expedition_bridge_room_components_source_v005.blend"),
    ("bridge_v007", "assets/art/environments/tower_zones/expedition/source/common_components/v007/expedition_bridge_room_components_source_v007.blend"),
    ("boss_v001", "assets/art/environments/tower_zones/expedition/source/common_components/v001/expedition_boss_room_components_source_v001.blend"),
    ("boss_v008", "assets/art/environments/tower_zones/expedition/source/common_components/v008/expedition_boss_room_components_source_v008.blend"),
    ("corridor_v002", "assets/art/environments/tower_zones/expedition/source/common_components/v002/expedition_l_corridor_components_source_v002.blend"),
    ("db_v003", "assets/art/environments/tower_zones/expedition/source/common_components/v003/expedition_db_room_components_source_v003.blend"),
    ("src_office_v001", "assets/art/environments/tower_zones/expedition/source/room_types/office_room/v001/办公室房间种类_开放办公_30x40m_v001.blend"),
    ("src_bridge_v002", "assets/art/environments/tower_zones/expedition/source/room_types/bridge_room/v002/通道桥房间种类_工字型_30x60m_v002.blend"),
]


def cell_of(uv):
    u, v = uv
    ci = min(9, max(0, int(u * 10)))
    vi_bottom = min(9, max(0, int(v * 10)))
    return ci, vi_bottom


def main() -> None:
    report = {}
    for label, rel in BLENDS:
        path = ROOT / rel
        if not path.is_file():
            print(f"SKIP {label}: 缺文件 {rel}")
            continue
        bpy.ops.wm.open_mainfile(filepath=str(path))
        cells = collections.Counter()
        mats = collections.Counter()
        uv_layers = collections.Counter()
        faces = 0
        seen_meshes = set()
        for obj in bpy.data.objects:
            if obj.type != "MESH":
                continue
            me = obj.data
            if me.name in seen_meshes:
                continue
            seen_meshes.add(me.name)
            if not me.uv_layers:
                uv_layers["<none>"] += 1
                continue
            layer = me.uv_layers.get("PaletteUV") or me.uv_layers[0]
            uv_layers[layer.name] += 1
            polys = me.polygons
            uvs = layer.data
            for poly in polys:
                if poly.loop_total == 0:
                    continue
                cu = cv = 0.0
                for li in poly.loop_indices:
                    uv = uvs[li].uv
                    cu += uv[0]
                    cv += uv[1]
                cu /= poly.loop_total
                cv /= poly.loop_total
                cells[cell_of((cu, cv))] += 1
                faces += 1
            for m in me.materials:
                if m:
                    mats[m.name] += 1
        report[label] = {
            "cells": {f"{c}_{v}": n for (c, v), n in cells.most_common()},
            "materials_by_mesh": dict(mats.most_common()),
            "uv_layer_names": dict(uv_layers),
            "face_count": faces,
        }
        print(f"===== {label}  faces={faces} =====")
        print("  uv 层名:", dict(uv_layers))
        print("  材质角色（按 mesh 数）:", dict(mats.most_common()))
        print("  色盘格 top20（u格, v格自下而上）:")
        for (c, v), n in cells.most_common(20):
            print(f"     u={c} v={v}（图面第 {9-v} 行）面数 {n}")
        print()

    out = ROOT / "_scratch/palette_shift/usage_report.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE:{out}")


if __name__ == "__main__":
    main()
