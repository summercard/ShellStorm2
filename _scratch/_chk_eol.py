import sys
from pathlib import Path
B = Path("assets/art/environments/tower_zones/expedition/runtime/room_type_components")
files = [
 "db_room/workbench_a/workbench_a_root_top3d.tscn",
 "office_room/filing_run/filing_run_root_top3d.tscn",
 "office_room/water_and_supply_corner/water_and_supply_corner_root_top3d.tscn",
 "office_room/work_cluster/work_cluster_root_top3d.tscn",
 "db_room/repair_island/repair_island_root_top3d.tscn",
 "db_room/raised_service_a/raised_service_a_root_top3d.tscn",
]
for f in files:
    b = (B / f).read_bytes()
    crlf = b.count(b"\r\n")
    lone_lf = b.count(b"\n") - crlf
    lone_cr = b.count(b"\r") - crlf
    hash_c = sum(1 for ln in b.split(b"\r\n") if ln.lstrip().startswith(b"#"))
    print(f"{f:70s} CRLF={crlf:4d} 孤立LF={lone_lf} 孤立CR={lone_cr} '#'注释行={hash_c}")
