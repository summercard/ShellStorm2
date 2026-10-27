#!/usr/bin/env python3
"""《挺进地牢》全房型白盒（56 种）门禁。

盯五件事，任一条不成立即退出 1：

1. **种类齐全** —— `egt_room_types/` 里的壳必须与 `EGT房型种类.csv` 的
   `(房型, 门面组合)` 集合**一一对应**：不多、不少。
2. **门数自洽** —— `door_sides`（如 `N1S2`）解析出的门数 == `door_count` == 实际端口数。
3. **每面放得下** —— 该面门数 <= 该面墙的合法槽数。`slot_count` **非单调**
   （2 格 2 槽、3 格 1 槽），所以「2 扇门挤在 15m 墙上」这种坏房必须拦住。
4. **尺寸符合规则** —— 重算 `宽/深`，必须与 TSCN 里声明的 `size_cells` 一致。
   这条防「手改了尺寸忘了重跑生成器」。
5. **不外溢** —— 目录里不许有清单认领不到的 `egt_*_static_layout.tscn`。

不做的事：不判材质、不判陈设、不判渲染。几何是否真的对，由
`tests/verification/verify_expedition03_room_whitebox.tscn` 真加载去量。

运行：
    python3 scripts/check_egt_room_types.py
    python3 scripts/check_egt_room_types.py --report
"""
from __future__ import annotations

import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "docs/v0.1/reference/挺进地牢/EGT房型种类.csv"
CATALOG = ROOT / "data/level_plans/egt_reference/room_types.json"
OUT_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/egt_room_types"
)
GRID = 5.0

BASE_CELLS: dict[str, tuple[int, int]] = {
    "ENTRANCE": (3, 3), "EXIT": (3, 3), "REWARD": (3, 3), "SHOP": (4, 3),
    "SPECIAL": (3, 3), "NORMAL": (5, 4), "BOSS_FOYER": (5, 4), "HUB": (6, 5),
    "CONNECTOR": (2, 4), "BOSS": (10, 8),
}

META_RE = re.compile(r"^metadata/(\w+) = (.+)$", re.M)
PORT_RE = re.compile(r'^\[node name="Port_[A-Z]"', re.M)


def slot_count(cells: int) -> int:
    return cells - 2 if cells >= 3 else cells


def expected_size(kind: str, sides: dict[str, int]) -> tuple[int, int]:
    """与 generate 脚本同一规则：从基准档往上逐格搜索。"""
    base_w, base_d = BASE_CELLS[kind]
    w = base_w
    while slot_count(w) < max(sides.get("N", 0), sides.get("S", 0)):
        w += 1
    d = base_d
    while slot_count(d) < max(sides.get("E", 0), sides.get("W", 0)):
        d += 1
    if kind == "CONNECTOR" and w > d:
        w, d = d, w
    return w, d


def parse_sides(key: str) -> dict[str, int]:
    out: dict[str, int] = {}
    i = 0
    while i < len(key):
        side = key[i]
        i += 1
        digits = ""
        while i < len(key) and key[i].isdigit():
            digits += key[i]
            i += 1
        out[side] = int(digits or 0)
    return out


def check_one(path: Path, kind: str, sides_key: str) -> list[str]:
    errs: list[str] = []
    text = path.read_text(encoding="utf-8")
    metas = {k: v.strip().strip('"') for k, v in META_RE.findall(text)}
    label = path.name

    if metas.get("egt_kind") != kind:
        errs.append(f"{label}: egt_kind = {metas.get('egt_kind')} != CSV 的 {kind}")
    if metas.get("door_sides") != sides_key:
        errs.append(f"{label}: door_sides = {metas.get('door_sides')} != CSV 的 {sides_key}")

    sides = parse_sides(sides_key)
    want_doors = sum(sides.values())
    if str(want_doors) != metas.get("door_count", ""):
        errs.append(f"{label}: door_count = {metas.get('door_count')} != {sides_key} 的 {want_doors}")
    ports = len(PORT_RE.findall(text))
    if ports != want_doors:
        errs.append(f"{label}: 实际端口 {ports} != {want_doors}")

    try:
        cells = json.loads(metas.get("size_cells", "[]"))
    except json.JSONDecodeError:
        cells = []
    if len(cells) != 2:
        errs.append(f"{label}: size_cells 缺失或格式错：{metas.get('size_cells')}")
        return errs
    w_cells, d_cells = int(cells[0]), int(cells[1])

    for key, cells_n, axis in (("N", w_cells, "宽"), ("S", w_cells, "宽"),
                               ("E", d_cells, "深"), ("W", d_cells, "深")):
        need = sides.get(key, 0)
        if need and slot_count(cells_n) < need:
            errs.append(
                f"{label}: {key} 面要开 {need} 门，但{axis} {cells_n} 格只有 "
                f"{slot_count(cells_n)} 个槽"
            )

    want_w, want_d = expected_size(kind, sides)
    if (w_cells, d_cells) != (want_w, want_d):
        errs.append(
            f"{label}: 尺寸 {w_cells}×{d_cells} 格与规则推导的 {want_w}×{want_d} 不符"
            "（手改了尺寸？重跑 scripts/build_egt_room_types.py）"
        )

    size_m = json.loads(metas.get("size_m", "[]"))
    if len(size_m) == 2:
        if abs(float(size_m[0]) - w_cells * GRID) > 1e-6 or \
                abs(float(size_m[1]) - d_cells * GRID) > 1e-6:
            errs.append(f"{label}: size_m {size_m} 与 size_cells {cells} 不一致")

    if "walkable_navigation_polygons" not in metas:
        errs.append(f"{label}: 缺 walkable_navigation_polygons")
    if metas.get("footprint_is_rect") != "true":
        errs.append(f"{label}: EGT 房间谱应全部为矩形轮廓（footprint_is_rect != true）")
    return errs


def main(argv: list[str]) -> int:
    report_only = "--report" in argv
    issues: list[str] = []
    missing: list[str] = []
    present: list[str] = []

    if not CSV_PATH.is_file():
        issues.append(f"缺统计表 {CSV_PATH.relative_to(ROOT)}（先跑 extract_egt_room_types.py）")
        rows: list[dict] = []
    else:
        rows = list(csv.DictReader(CSV_PATH.open(encoding="utf-8-sig")))

    occ: dict[tuple[str, str], int] = defaultdict(int)
    for row in rows:
        occ[(row["房型"], row["门面"])] += 1

    for (kind, sides_key) in sorted(occ):
        name = f"egt_{kind.lower()}_{sides_key}_static_layout.tscn"
        path = OUT_DIR / name
        if not path.is_file():
            missing.append(name)
            continue
        present.append(name)
        issues.extend(check_one(path, kind, sides_key))

    if OUT_DIR.is_dir():
        known = {f"egt_{k.lower()}_{s}_static_layout.tscn" for k, s in occ}
        for path in OUT_DIR.glob("egt_*_static_layout.tscn"):
            if path.name not in known:
                issues.append(f"{path.name}: 目录里有但 CSV 里没有这个 (房型, 门面) 组合")

    if not CATALOG.is_file():
        issues.append(f"缺房型清单 {CATALOG.relative_to(ROOT)}")
    else:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        if int(catalog.get("type_count", -1)) != len(occ):
            issues.append(
                f"room_types.json type_count={catalog.get('type_count')} != CSV 的 {len(occ)} 种"
            )
        if int(catalog.get("total_room_positions", -1)) != len(rows):
            issues.append(
                f"room_types.json total_room_positions={catalog.get('total_room_positions')}"
                f" != CSV 的 {len(rows)}"
            )

    result = {
        "ok": (not issues and not missing) if not report_only else not issues,
        "csv_combos": len(occ),
        "csv_room_positions": len(rows),
        "required": len(occ),
        "present": len(present),
        "missing": missing,
        "issues": issues,
        "limit": "只校验契约自洽。几何是否真的对由 verify_expedition03_room_whitebox 真加载去量。",
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if report_only:
        return 0
    return 1 if (issues or missing) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
