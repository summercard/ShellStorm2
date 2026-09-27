import json, io, sys

files = [
    "data/spawn_boxes/box_room_spread.json",
    "data/spawn_boxes/box_corridor_column.json",
    "data/spawn_boxes/box_corner_ambush.json",
    "src/map/SpawnBoxCatalog.gd",
]

for rel in files:
    with open(rel, "rb") as fh:
        b = fh.read()
    crlf = b.count(b"\r\n")
    lone_lf = b.count(b"\n") - crlf
    stray_cr = b.count(b"\r") - crlf
    line = "%-52s CRLF=%d loneLF=%d strayCR=%d" % (rel, crlf, lone_lf, stray_cr)
    if rel.endswith(".json"):
        try:
            d = json.loads(b.decode("utf-8"))
            line += "  JSON_OK size=%s spawns=%d" % (d.get("size_m"), len(d.get("spawns", [])))
        except Exception as exc:  # noqa: BLE001
            line += "  JSON_FAIL %s" % exc
    print(line)
