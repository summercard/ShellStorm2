import json
import glob
import os

base = "_scratch/expedition_spawn_boxes"
files = ["spawn_box_map.json", "spawn_box_map_12345.json", "spawn_box_map_999999.json"]

for name in files:
    path = os.path.join(base, name)
    if not os.path.exists(path):
        print("MISSING", path)
        continue
    doc = json.load(open(path, encoding="utf-8"))
    print("===== %s  seed=%s boxes=%s shifted=%s =====" % (
        name, doc["seed"], doc["box_total"], doc["shifted_total"]))
    for room in doc["rooms"]:
        for pl in room["placements"]:
            if "error" in pl:
                print("  ERROR %s#%s %s" % (room["room_id"], pl["index"], pl["error"]))
                continue
            if pl["shift"] > 0.01:
                print("  SHIFT %-14s #%-2d %-20s shift=%.3f  decl=%s fits=%s  decl_pool=%d cap=%d demand=%d"
                      % (room["room_id"], pl["index"], pl["box"], pl["shift"],
                         pl["center_declared"], pl["declared_fits"],
                         pl["declared_pool_count"], pl["capacity"], pl["demand_max"]))
    # 汇总 declared_fits=false 的
    nf = 0
    for room in doc["rooms"]:
        for pl in room["placements"]:
            if "error" in pl:
                continue
            if not pl["declared_fits"]:
                nf += 1
    print("  declared_fits=false total =", nf)
