#!/usr/bin/env python3
"""boss 静态 TSCN <-> v011 房型源 逐实例位置比对。

目的:判定 f00_boss_static_layout.tscn 是否忠实重放 v011/component_instances.json,
以决定门位空阻挡的修复层次(改源重生成 vs 只改 tscn)。

映射(房间根无旋转): 源 position_m=[bx,by,bz] -> Godot 局部 (bx, bz, -by)
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scan_door_clearance as sdc  # noqa: E402

REPO = sdc.REPO
TSCN = os.path.join(
    REPO, "assets", "art", "environments", "tower_zones", "expedition",
    "runtime", "room_instances", "expedition_01", "f00_boss_static_layout.tscn",
)
SRC = os.path.join(
    REPO, "assets", "art", "environments", "tower_zones", "expedition",
    "source", "common_components", "v011", "component_instances.json",
)


def src_runtime(pm):
    return (pm[0], pm[2], -pm[1])


def main():
    text = open(TSCN, encoding="utf-8").read()
    ext = {}
    for m in re.finditer(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text):
        ext[m.group(2)] = m.group(1)

    tscn = {}
    for name, ntype, parent, rid, b in sdc.node_blocks(text):
        if not rid or rid not in ext:
            continue
        rows, origin = sdc.local_transform(b)
        tscn[name] = (origin, ext[rid], b)

    src = json.load(open(SRC, encoding="utf-8"))
    inst = {i["instance_id"]: i for i in src["instances"]}

    only_src = sorted(set(inst) - set(tscn))
    only_tscn = sorted(set(tscn) - set(inst))

    exact, mismatch = [], []
    for k in sorted(set(inst) & set(tscn)):
        o = tscn[k][0]
        r = src_runtime(inst[k]["position_m"])
        d = max(abs(o[i] - r[i]) for i in range(3))
        if d <= 0.011:
            exact.append(k)
        else:
            mismatch.append((k, r, o, d))

    print("TSCN 实例节点 %d / 源实例 %d" % (len(tscn), len(inst)))
    print("完全一致 %d / 不一致 %d / 仅源有 %d / 仅 tscn 有 %d"
          % (len(exact), len(mismatch), len(only_src), len(only_tscn)))
    print("\n-- 仅源有(tscn 缺) --")
    for k in only_src:
        print("   %-30s %s" % (k, inst[k]["component_slug"]))
    print("\n-- 仅 tscn 有(源无) --")
    for k in only_tscn:
        print("   %-30s %s" % (k, tscn[k][1]))

    print("\n-- 位置不一致(按偏差降序, 前 40) --")
    mismatch.sort(key=lambda t: -t[3])
    for k, r, o, d in mismatch[:40]:
        print("   %-30s slug=%-28s src=(%8.4f,%8.4f,%8.4f) tscn=(%8.4f,%8.4f,%8.4f) d=%.4f"
              % (k, inst[k]["component_slug"], r[0], r[1], r[2], o[0], o[1], o[2], d))

    # 门位相关实例单独列
    print("\n-- 门位阻碍件在源 vs tscn --")
    for k in ["wall_skin_west_04", "wall_skin_east_04", "west_damaged_01",
              "east_complete_03", "east_complete_04", "archive_shelf_02",
              "base_wall_west_slot_05_solid", "base_wall_east_slot_05_solid"]:
        if k in inst:
            r = src_runtime(inst[k]["position_m"])
            print("   %-32s src_runtime=(%8.4f,%8.4f,%8.4f)  in_tscn=%s"
                  % (k, r[0], r[1], r[2], k in tscn))
        else:
            print("   %-32s <源中不存在>  in_tscn=%s" % (k, k in tscn))


if __name__ == "__main__":
    main()
