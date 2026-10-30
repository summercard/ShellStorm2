"""把远征03 复刻怪的四族对照行拼成一张图，并画图注。

配套 `tools/_egt_variant_render.gd`：
    ① Godot 拍四张 `_egt_row_<族名>.png`，并写 `_egt_variant_rows.json`
    ② 本脚本读 JSON 拼合 + 画文字

## 为什么文字在 Python 里画，不在 Godot 里画
见 `_egt_variant_render.gd` 文件头：正交相机的可见范围是死区间，
Label3D 要么压在怪身上、要么落到视锥外被裁掉，两种都试过都不行。

## 为什么图注数据从 JSON 读，不在本脚本里写死
体型 / 颜色 / 血条宽度的唯一真源在 `Enemy3D` 与 `EnemyAvatar3D` 的常量表里。
本脚本若自己写一份，改了 GDScript 而忘了改 Python，图注就会显示旧数字且无人报警。

用法：
    python tools/compose_egt_variant_lineup.py
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "outputs", "verification")
MANIFEST = os.path.join(OUT_DIR, "_egt_variant_rows.json")
OUTPUT = os.path.join(OUT_DIR, "egt_variant_lineup.png")

BG = (12, 14, 19)
DIVIDER = (38, 46, 60)
TITLE = (235, 242, 255)
RULE = (138, 172, 208)
NOTE = (150, 158, 172)

HEAD_H = 46          # 每族标题带高度
CAPTION_H = 96       # 每族图注带高度（含与下一族标题之间的留白）
BG_TOL = 10          # 自动裁边时的背景容差


def load_font(size: int):
    for path in (
        "C:/Windows/Fonts/msyhbd.ttc",
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/simhei.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def trim_vertical(image: Image.Image, tol: int = BG_TOL, pad: int = 10) -> Image.Image:
    """只裁上下，**不动左右**。

    ## 为什么不能左右也裁（第一版踩过）
    各行成员数不同（5/3/3/1），若每行独立按内容裁左右，行宽就各不相同，
    图注按「画布宽 ÷ 成员数」均分列时，每行的列中心都落在不同位置 ——
    于是文字和怪**逐行错位**，最严重的一行文字跑到了两只怪中间（2026-10-29 出图）。
    只裁上下、保留原生宽高比例后，所有行共享同一个横向坐标系，
    列中心天然对齐，与成员数无关。
    """
    px = image.load()
    bg = px[4, 4]
    width, height = image.size
    ys: list[int] = []
    for y in range(0, height, 2):
        for x in range(0, width, 4):
            c = px[x, y]
            if any(abs(c[i] - bg[i]) > tol for i in range(3)):
                ys.append(y)
                break
    if not ys:
        return image
    return image.crop((0, max(0, min(ys) - pad), width, min(height, max(ys) + pad)))


def color_label(member: dict) -> str:
    """一句人能读懂的「它靠什么跟同族区分」。"""
    if member["tinted"]:
        return f"染色 {member['color']}"
    if member["uses_formal"]:
        return "未染色（同族刻意同色）"
    return f"外壳 {member['color']}"


def main() -> int:
    if not os.path.exists(MANIFEST):
        print(f"缺少 {MANIFEST}，先跑 _egt_variant_render.tscn", file=sys.stderr)
        return 1

    with open(MANIFEST, encoding="utf-8") as fh:
        rows = json.load(fh)["rows"]

    font_title = load_font(26)
    font_rule = load_font(17)
    font_cell = load_font(15)

    strips = []
    for row in rows:
        path = os.path.join(OUT_DIR, f"_egt_row_{row['family']}.png")
        if not os.path.exists(path):
            print(f"缺少 {path}", file=sys.stderr)
            return 1
        strips.append((row, trim_vertical(Image.open(path).convert("RGB"))))

    width = max(img.size[0] for _, img in strips)
    # 图注按列排：每只怪一列，列宽 = 画布宽 / 该行成员数
    total_h = sum(img.size[1] + HEAD_H + CAPTION_H for _, img in strips)

    canvas = Image.new("RGB", (width, total_h), BG)
    draw = ImageDraw.Draw(canvas)

    y = 0
    for row, img in strips:
        members = row["members"]

        # —— 标题带：族名 + 主区分维度 ——
        draw.text((26, y + 11), row["family"], font=font_title, fill=TITLE)
        tw = draw.textlength(row["family"], font=font_title)
        draw.text((26 + tw + 16, y + 17), f"—  {row['rule']}", font=font_rule, fill=RULE)
        y += HEAD_H

        # —— 图像 ——
        canvas.paste(img, (0, y))

        # —— 图注带：逐列对齐到怪的正上方 ——
        # 每列中心 = 图的横向中心线均分。图本身已裁边，可能与画布不同宽，故用画布中心对齐。
        # 列中心直接用 Godot 实测的屏幕 x（见 `_egt_variant_render.gd` 的 `_screen_x`）。
        # **不要**改成"画布宽 ÷ 成员数"：两套坐标系换算不等价，会横向偏移最多近 200px。
        for member in members:
            cx = float(member["screen_x"])
            lines = [
                member["kind"].replace("egt_", ""),
                f"体型 {member['body_scale']:.2f}  (世界高 {member['world_height']:.2f}m)",
                color_label(member),
                f"血条 {member['bar_width']:.2f} 宽",
            ]
            line_y = y + img.size[1] + 8
            for i, text in enumerate(lines):
                fill = TITLE if i == 0 else NOTE
                font = font_cell
                text_w = draw.textlength(text, font=font)
                draw.text((cx - text_w / 2, line_y + i * 17), text, font=font, fill=fill)

        y += img.size[1] + CAPTION_H
        draw.line([(0, y - 1), (width, y - 1)], fill=DIVIDER, width=1)

    canvas.save(OUTPUT)
    print(f"EGT_VARIANT_LINEUP {OUTPUT} {canvas.size}")

    for name in os.listdir(OUT_DIR):
        if name.startswith("_egt_row_") or name == "_egt_variant_rows.json":
            try:
                os.remove(os.path.join(OUT_DIR, name))
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
