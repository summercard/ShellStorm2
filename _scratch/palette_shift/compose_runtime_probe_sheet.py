#!/usr/bin/env python3
"""把导入拼装后的 9 张运行时取证截图合成为一张 3x3 联系表（交付图）。

输入
  - 截图目录：I:/ss2_iso/room_type_after_import/*.png
  - 材质报告：I:/ss2_iso/probe_report.txt（由探针 stdout 落盘）
输出
  - outputs/room_type_runtime_probe_after_import.png
  - outputs/room_type_runtime_probe_after_import_metrics.json
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SHOT_DIR = Path("I:/ss2_iso/room_type_after_import")
REPORT = Path("I:/ss2_iso/room_type_after_import/probe_report.txt")
REPO = Path("I:/工作项目/shellstrom2/ShellStorm2")
OUT_PNG = REPO / "outputs" / "room_type_runtime_probe_after_import.png"
OUT_JSON = REPO / "outputs" / "room_type_runtime_probe_after_import_metrics.json"

ORDER = [
    "1_office_work_cluster",
    "2_office_wall_t615_5m",
    "9_office_floor_tile_5m",
    "3_bridge_tile_upper",
    "4_bridge_pit_side",
    "5_boss_server_rack",
    "6_boss_heavy_conduits",
    "7_boss_wall_solid_5m",
    "8_boss_workstation_a",
]

ROOM_ZH = {
    "office": "办公室 v006",
    "bridge": "通道桥 v007",
    "boss": "Boss 房 v008",
}

CELL_W, CELL_H = 636, 358
PAD = 14
CAP_H = 30
TITLE_H = 66
COLS = 3


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in (r"C:/Windows/Fonts/msyh.ttc", r"C:/Windows/Fonts/simhei.ttf"):
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def parse_report() -> dict[str, dict]:
    """从探针报告里抽出每个取样件的 aabb 与逐表面 metallic/roughness。"""
    cases: dict[str, dict] = {}
    current: dict | None = None
    header = re.compile(r"^== (\S+) \((\S+)\) aabb=\(([^)]*)\)")
    surface = re.compile(r"^surface(\d+) metallic=([\d.]+) roughness=([\d.]+)")
    for raw in REPORT.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        match = header.match(line)
        if match:
            current = {
                "tag": match.group(1),
                "slug": match.group(2),
                "aabb_m": [round(float(v), 3) for v in match.group(3).split(",")],
                "surfaces": [],
            }
            cases[current["tag"]] = current
            continue
        if current is None:
            continue
        match = surface.match(line)
        if match:
            current["surfaces"].append(
                {
                    "index": int(match.group(1)),
                    "metallic": float(match.group(2)),
                    "roughness": float(match.group(3)),
                }
            )
    return cases


def short_metallic(case: dict) -> str:
    values = "／".join(f"{s['metallic']:.3f}" for s in case["surfaces"])
    high = sum(1 for s in case["surfaces"] if s["metallic"] >= 0.5)
    return f"metallic {values}　高金属面 {high}/{len(case['surfaces'])}"


def main() -> None:
    cases = parse_report()
    missing = [t for t in ORDER if t not in cases]
    if missing:
        raise SystemExit(f"报告缺少取样件：{missing}")

    title_font = load_font(30)
    cap_font = load_font(17)
    meta_font = load_font(14)

    rows = (len(ORDER) + COLS - 1) // COLS
    width = PAD + COLS * (CELL_W + PAD)
    height = TITLE_H + rows * (CELL_H + CAP_H + PAD) + PAD
    canvas = Image.new("RGB", (width, height), (24, 27, 33))
    draw = ImageDraw.Draw(canvas)

    draw.text(
        (PAD + 6, 16),
        "导入拼装后运行时取证 · 房型组件（98 组件独立 PackedScene，2026-09-27）",
        font=title_font,
        fill=(232, 238, 246),
    )

    for index, tag in enumerate(ORDER):
        case = cases[tag]
        col = index % COLS
        row = index // COLS
        x = PAD + col * (CELL_W + PAD)
        y = TITLE_H + row * (CELL_H + CAP_H + PAD)

        shot = SHOT_DIR / f"{tag}.png"
        image = Image.open(shot).convert("RGB").resize((CELL_W, CELL_H), Image.LANCZOS)
        canvas.paste(image, (x, y))

        prefix = tag.split("_", 1)[1]
        room_key = tag.split("_", 1)[1].split("_", 1)[0]
        room_zh = ROOM_ZH.get(room_key)
        if room_zh is None:
            # tag 形如 1_office_work_cluster / 4_bridge_pit_side
            room_zh = "办公室 v006" if "office" in tag else ("通道桥 v007" if "bridge" in tag else "Boss 房 v008")
        slug = case["slug"]
        caption = f"{room_zh} · {slug}"
        draw.text((x + 2, y + CELL_H + 4), caption, font=cap_font, fill=(236, 241, 248))
        draw.text((x + 2, y + CELL_H + 4 + 18), short_metallic(case), font=meta_font, fill=(150, 200, 190))

    OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT_PNG)

    metrics = {
        "schema": "shellstorm2.expedition.room_type_runtime_probe_sheet.v001",
        "generated_at": "2026-09-27",
        "probe_report": str(REPORT),
        "cases": [cases[t] for t in ORDER],
        "note": (
            "每行是一个 MeshInstance3D 的表面（索引均为 0）；除 workstation_a 保留 1 个 0.860 高金属面外，"
            "全部取样件的可判面 metallic<=0.180，且 albedo 全部绑定共享设施色盘。"
        ),
    }
    OUT_JSON.write_text(json.dumps(metrics, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("SHEET_OK", OUT_PNG, canvas.size)
    print("METRICS_OK", OUT_JSON)


if __name__ == "__main__":
    main()
