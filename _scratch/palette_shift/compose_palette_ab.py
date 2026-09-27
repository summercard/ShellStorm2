"""把 render_palette_ab.py 产出的 before/after 图合成一张对照表（左=调整前，右=调整后）。"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SHOTS = Path("I:/workbuddy_tmp/palette_ab_shots")
OUT = Path("I:/工作项目/shellstrom2/ShellStorm2/outputs/palette_lighten_matte_ab.png")
FONT_CANDIDATES = (
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/msyhbd.ttc",
    "C:/Windows/Fonts/simhei.ttf",
)
ROW_LABELS = {
    ("office_room", "work_cluster"): "办公室 · 工位组",
    ("bridge_room", "tile_upper"): "通道桥 · 上层地砖",
    ("boss_room", "server_rack"): "Boss 房 · 服务器机柜",
    ("boss_room", "heavy_conduits"): "Boss 房 · 重载管道",
    ("l_corridor", "high_pipe_east_00"): "拐角走廊 · 东侧高架管道",
    ("l_corridor", "server_00"): "拐角走廊 · 服务器",
    ("db_room", "server_rack_row"): "数据库房 · 机柜列",
    ("db_room", "ceiling_ring_beam"): "数据库房 · 吊顶圈梁",
}


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def main() -> int:
    grid = json.loads((SHOTS / "grid.json").read_text(encoding="utf-8"))
    sample = Image.open(grid[0]["before"])
    tile = sample.width
    pad = 16
    header = 46
    label_w = 250
    title_h = 56
    width = label_w + tile * 2 + pad * 3
    height = title_h + header + len(grid) * (tile + pad) + pad
    canvas = Image.new("RGB", (width, height), (18, 20, 26))
    draw = ImageDraw.Draw(canvas)
    f_title = load_font(30)
    f_head = load_font(22)
    f_label = load_font(20)
    draw.text((pad, 12), "房型组件：UV 提亮 +3 档 / 材质亚光化 前后对照", font=f_title, fill=(228, 232, 240))
    draw.text((label_w + pad * 2, title_h - 4), "调整前（暗色 + 高金属度）", font=f_head, fill=(224, 120, 110))
    draw.text((label_w + tile + pad * 3, title_h - 4), "调整后（提亮 + 大面积哑光）", font=f_head, fill=(120, 200, 150))
    y = title_h + header
    for row in grid:
        label = ROW_LABELS.get(
            (row["room_slug"], Path(row["rel"]).stem), row["room_slug"]
        )
        draw.text((pad, y + tile // 2 - 12), label, font=f_label, fill=(206, 212, 224))
        for index, mode in enumerate(("before", "after")):
            image = Image.open(row[mode]).convert("RGBA").resize((tile, tile))
            backdrop = Image.new("RGBA", (tile, tile), (26, 29, 36, 255))
            image = Image.alpha_composite(backdrop, image).convert("RGB")
            x = label_w + pad * (2 + index) + tile * index
            canvas.paste(image, (x, y))
        y += tile + pad
    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT)
    print("WROTE:%s %dx%d" % (OUT, canvas.width, canvas.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
