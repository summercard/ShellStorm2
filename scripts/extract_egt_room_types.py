#!/usr/bin/env python3
"""从《挺进地牢》官方 flow 骨架图 PDF 反推**真实房型种类**。

## 为什么不用 flow JSON

`data/level_plans/expedition_03/flows/*.json` 只有邻接关系、没有坐标，
算不出「门开在哪几面」。而 PDF 里每个房间是一个**带位置的矩形框**，
连线是贝塞尔曲线 —— 这是唯一能拿到「房型 × 门面集合」的地方。

## 提取口径

- **房间**：`get_drawings()` 里只有 `re` 一种图元的矩形，且尺寸落在房间框区间内
- **连线**：图元里含 `c`（贝塞尔）的绘制项，取首段起点与末段终点
- **配对**：连线端点到矩形框边界距离 <= 12pt 视为相连
- **门面**：比较两房矩形中心，|dx| >= |dy| → 东西向；否则南北向
  （PDF 坐标系 y 向下 = 图的南方，与 `RoomDoorLane` 的 north=−Z 约定同向）
- **度数自检**：算出的门数必须与该房的边数一致，否则该图计为不可信

## 输出

`docs/v0.1/reference/挺进地牢/EGT房型种类.csv` —— 每条 (楼层, flow, 房型, 门面集合)
与 `EGT房型种类统计.md` 的结论表。

运行：
    python3 scripts/extract_egt_room_types.py
"""
from __future__ import annotations

import csv
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

PDF_DIR = Path("I:/挺进地牢/_src/flows")
ROOT = Path(__file__).resolve().parents[1]
REF_DIR = ROOT / "docs/v0.1/reference/挺进地牢"

# 房间框的尺寸区间（pt）。官方 flow 图的房间是 ~40×190 的矩形。
BOX_MIN_W, BOX_MAX_W = 34.0, 220.0
BOX_MIN_H, BOX_MAX_H = 26.0, 50.0
MATCH_TOL = 12.0

SIDE_ZH = {"N": "北", "S": "南", "E": "东", "W": "西"}
def shape_of(counts: dict[str, int]) -> str:
    """按「每面几扇门」归形状，旋转视为同一种。

    `counts` 形如 {"N": 2} 表示北墙两扇、其余面零扇。
    同侧多门是真实存在的房型（一个房间南墙接两个子房），不能当重复丢掉。
    """
    total = sum(counts.values())
    sides = sorted(counts.values(), reverse=True)
    if total == 0:
        return "0门"
    if total == 1:
        return "1门"
    if total == 2:
        if len(counts) == 1:
            return "2门·同侧"
        if set(counts) in ({"N", "S"}, {"E", "W"}):
            return "2门·相对"
        return "2门·相邻"
    if total == 3:
        if len(counts) == 1:
            return "3门·同侧"
        if len(counts) == 2:
            return "3门·一侧双门"
        return "3门"
    if total == 4:
        if len(counts) == 1:
            return "4门·同侧"
        if len(counts) == 2:
            return "4门·两侧各双"
        if len(counts) == 3:
            return "4门·一侧双门"
        return "4门"
    if total == 5:
        return "5门"
    return f"{total}门"


def classify(label: str) -> str:
    t = label.strip()
    up = t.upper()
    if "ENTRANCE" in up:
        return "ENTRANCE"
    if "EXIT" in up:
        return "EXIT"
    if "FOYER" in up:
        return "BOSS_FOYER"
    if up == "BOSS":
        return "BOSS"
    if "SHOP" in up:
        return "SHOP"
    if up.startswith("REWARD"):
        return "REWARD"
    if up.startswith("HUB"):
        return "HUB"
    if up.startswith("CONNECTOR"):
        return "CONNECTOR"
    if up.startswith("NORMAL"):
        return "NORMAL"
    return "SPECIAL"


def parse_page(page) -> tuple[list[dict], list[tuple]]:
    import pymupdf

    words = page.get_text("words")
    boxes: list[dict] = []
    conns: list[tuple] = []
    for block in page.get_drawings():
        items = block.get("items", [])
        kinds = {i[0] for i in items}
        rect = block.get("rect")
        if rect is None:
            continue
        if kinds == {"re"}:
            if not (BOX_MIN_W <= rect.width <= BOX_MAX_W):
                continue
            if not (BOX_MIN_H <= rect.height <= BOX_MAX_H):
                continue
            text = " ".join(
                w[4] for w in words
                if pymupdf.Point((w[0] + w[2]) / 2, (w[1] + w[3]) / 2) in rect
            )
            text = re.sub(r"\s+", " ", text).strip()
            if not text:
                continue
            boxes.append({"rect": rect, "label": text,
                          "cx": (rect.x0 + rect.x1) / 2, "cy": (rect.y0 + rect.y1) / 2})
        elif "c" in kinds and "re" not in kinds:
            first, last = items[0], items[-1]
            if first[0] == "c" and last[0] == "c":
                conns.append(((first[1].x, first[1].y), (last[4].x, last[4].y)))
    return boxes, conns


def dist_to_box(rect, point: tuple[float, float]) -> float:
    x, y = point
    dx = max(rect.x0 - x, 0.0, x - rect.x1)
    dy = max(rect.y0 - y, 0.0, y - rect.y1)
    return (dx * dx + dy * dy) ** 0.5


def nearest(boxes: list[dict], point: tuple[float, float]) -> int | None:
    best, best_d = None, 1e9
    for index, box in enumerate(boxes):
        d = dist_to_box(box["rect"], point)
        if d < best_d:
            best, best_d = index, d
    return best if best_d <= MATCH_TOL else None


def side_between(a: dict, b: dict) -> tuple[str, str]:
    dx, dy = b["cx"] - a["cx"], b["cy"] - a["cy"]
    if abs(dx) >= abs(dy):
        return ("E", "W") if dx >= 0 else ("W", "E")
    return ("S", "N") if dy >= 0 else ("N", "S")


def main() -> int:
    try:
        import pymupdf
    except ImportError:
        print("需要 pymupdf：pip install pymupdf")
        return 1

    pdfs = sorted(PDF_DIR.glob("*.pdf"))
    if not pdfs:
        print(f"找不到 PDF：{PDF_DIR}")
        return 1

    rows: list[dict] = []
    per_flow: list[dict] = []
    kind_sides: dict[str, Counter] = defaultdict(Counter)
    shape_by_kind: dict[str, Counter] = defaultdict(Counter)
    floor_of: dict[str, set] = defaultdict(set)

    for pdf in pdfs:
        match = re.match(r"(F\d)", pdf.stem)
        floor = match.group(1) if match else "?"
        doc = pymupdf.open(pdf)
        page = doc[0]
        boxes, conns = parse_page(page)
        doc.close()
        if not boxes:
            per_flow.append({"flow": pdf.stem, "floor": floor, "nodes": 0,
                             "edges": 0, "ok": False, "note": "无房间框"})
            continue

        sides: list[Counter] = [Counter() for _ in boxes]
        edges: set[tuple[int, int]] = set()
        unmatched = 0
        for start, end in conns:
            i, j = nearest(boxes, start), nearest(boxes, end)
            if i is None or j is None or i == j:
                unmatched += 1
                continue
            edges.add((min(i, j), max(i, j)))
            s_i, s_j = side_between(boxes[i], boxes[j])
            sides[i][s_i] += 1
            sides[j][s_j] += 1

        # 自检：门面数必须等于该房的边数（一个门面一扇门）
        degree = Counter()
        for i, j in edges:
            degree[i] += 1
            degree[j] += 1
        consistent = all(sum(sides[i].values()) == degree[i] for i in range(len(boxes)))
        loops = len(edges) - len(boxes) + 1
        per_flow.append({
            "flow": pdf.stem, "floor": floor, "nodes": len(boxes),
            "edges": len(edges), "loops": loops, "unmatched": unmatched,
            "ok": consistent and unmatched == 0,
            "note": "" if consistent else "门面数≠边数（同侧两门或配对错误）",
        })

        for index, box in enumerate(boxes):
            kind = classify(box["label"])
            counts = sides[index]
            sides_key = "".join(
                f"{s}{counts[s]}" for s in ("N", "S", "E", "W") if counts[s]
            )
            shape = shape_of(dict(counts))
            kind_sides[kind][sides_key] += 1
            shape_by_kind[kind][shape] += 1
            floor_of[kind].add(floor)
            rows.append({
                "楼层": floor, "flow": pdf.stem, "房型": kind, "原始标签": box["label"],
                "门数": sum(counts.values()), "门面": sides_key,
                "门面中文": "+".join(
                    f"{SIDE_ZH[s]}×{counts[s]}" if counts[s] > 1 else SIDE_ZH[s]
                    for s in ("N", "S", "E", "W") if counts[s]
                ) or "无",
                "形状": shape,
            })

    REF_DIR.mkdir(parents=True, exist_ok=True)
    out_csv = REF_DIR / "EGT房型种类.csv"
    with out_csv.open("w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(f"PDF {len(pdfs)} 张 · 房间位 {len(rows)} 个 -> {out_csv.name}\n")
    print("== 每张 flow 的自检 ==")
    for item in per_flow:
        flag = "OK" if item["ok"] else "FAIL"
        extra = f" unmatched={item['unmatched']}" if item.get("unmatched") else ""
        note = f"  {item['note']}" if item.get("note") else ""
        print(f"  {item['flow'][:44]:46s} n={item['nodes']:2d} e={item['edges']:2d} "
              f"loops={item.get('loops', '-')} {flag}{extra}{note}")

    print("\n== 房型 × 门面组合（这是「房型种类」的真实口径）==")
    total_combos = 0
    for kind in sorted(kind_sides):
        combos = kind_sides[kind]
        total_combos += len(combos)
        parts = ", ".join(f"{k}({v})" for k, v in sorted(combos.items(), key=lambda x: -x[1]))
        print(f"  {kind:12s} {len(combos)} 种: {parts}")

    print(f"\n=> 房型 × 门面组合总数 = {total_combos}")

    print("\n== 按形状归一（旋转视为同一种）==")
    shape_total: Counter = Counter()
    for kind in sorted(shape_by_kind):
        for shape, count in shape_by_kind[kind].items():
            shape_total[shape] += count
        print(f"  {kind:12s} {dict(sorted(shape_by_kind[kind].items()))}")
    print(f"\n== 全部形状出现次数 ==")
    for shape, count in sorted(shape_total.items(), key=lambda x: -x[1]):
        print(f"  {shape:10s} {count}")
    print(f"=> 不同形状 {len(shape_total)} 类")

    print(f"\n== 各房型所在楼层 ==")
    for kind in sorted(floor_of):
        print(f"  {kind:12s} {sorted(floor_of[kind])}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
