import json
import os

base = "_scratch/expedition_spawn_boxes"
files = ["spawn_box_map.json", "spawn_box_map_12345.json", "spawn_box_map_999999.json"]

for name in files:
    path = os.path.join(base, name)
    if not os.path.exists(path):
        continue
    doc = json.load(open(path, encoding="utf-8"))
    degen = 0
    oneside = 0
    boxes_seen = 0
    detail = []
    for room in doc["rooms"]:
        # 按 box_index 汇总该盒**所有波**的实际落点（房局部）
        groups = {}
        for wave in room["waves"]:
            for e in wave:
                bi = e["box_index"]
                if bi is None or bi < 0:
                    continue
                groups.setdefault(bi, []).append((e["local"][0], e["local"][1]))
        # 盒信息（尺寸）用于「单侧堆积 < 盒宽 25%」
        pls = {p["index"]: p for p in room["placements"] if "error" not in p}
        for bi, pts in groups.items():
            if len(pts) < 2:
                continue
            boxes_seen += 1
            xs = [p[0] for p in pts]
            zs = [p[1] for p in pts]
            sx = max(xs) - min(xs)
            sz = max(zs) - min(zs)
            size = pls.get(bi, {}).get("size", [0, 0])
            bw, bd = size[0], size[1]
            tag = None
            if sx < 0.001 or sz < 0.001:
                degen += 1
                tag = "DEGEN"
            elif (sx < bw * 0.25) or (sz < bd * 0.25):
                oneside += 1
                tag = "ONESIDE"
            if tag:
                detail.append("    %-5s %-12s #%-2d n=%d span=(%.2f,%.2f) box=(%.1f,%.1f)"
                              % (tag, room["room_id"], bi, len(pts), sx, sz, bw, bd))
    print("%s: boxes_with_multi_spawn=%d degenerate=%d oneside=%d"
          % (name, boxes_seen, degen, oneside))
    for d in detail:
        print(d)
