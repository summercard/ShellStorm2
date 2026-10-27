#!/usr/bin/env python3
"""《挺进地牢》56 种房型白盒总览图集。

按房型分组、按 EGT 实测出现次数降序 —— 看一眼就知道「哪种房型最常出现」。

运行：
    python3 scripts/render_egt_room_types_gallery.py
"""
from __future__ import annotations

import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/level_plans/egt_reference/room_types.json"
IMG_DIR = ROOT / "docs/art/egt_room_types"
OUT = IMG_DIR / "index.html"

SIDE_ZH = {"N": "北", "S": "南", "E": "东", "W": "西"}

KIND_ORDER = [
    ("NORMAL", "战斗房", "主干内容，占全部房间位最多"),
    ("HUB", "枢纽房", "出口更多的分叉点（原文：larger rooms with more exits）"),
    ("REWARD", "宝箱房", "奖励房，常见单门"),
    ("SHOP", "商店", "购物房"),
    ("CONNECTOR", "连接房", "细长的过渡房（原文：long, thin rooms）"),
    ("ENTRANCE", "入口", "每层唯一"),
    ("BOSS_FOYER", "首领前厅", "首领房之前的整备间"),
    ("EXIT", "出口", "通往下一层"),
    ("BOSS", "首领房", "每层唯一，尺寸最大"),
    ("SPECIAL", "特殊房", "只在第 2 / 5 层出现的特殊布局"),
]


def sides_zh(key: str) -> str:
    out = []
    for i, ch in enumerate(key):
        if ch in SIDE_ZH:
            digits = ""
            j = i + 1
            while j < len(key) and key[j].isdigit():
                digits += key[j]
                j += 1
            out.append(f"{SIDE_ZH[ch]}×{digits}" if digits and digits != "1" else SIDE_ZH[ch])
    return " + ".join(out) or "无门"


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    types = catalog["types"]
    by_kind: dict[str, list[dict]] = {}
    for item in types:
        by_kind.setdefault(item["egt_kind"], []).append(item)
    for kind in by_kind:
        by_kind[kind].sort(key=lambda x: (-x["egt_occurrences"], x["door_sides"]))

    sections: list[str] = []
    for kind, kind_zh, note in KIND_ORDER:
        items = by_kind.get(kind, [])
        if not items:
            continue
        total = sum(i["egt_occurrences"] for i in items)
        cards = []
        for item in items:
            w, d = item["size_m"]
            cw, cd = item["size_cells"]
            cards.append(
                f'<figure>\n'
                f'<img src="{item["shell_id"]}.png" alt="{item["shell_id"]}" loading="lazy">\n'
                f'<figcaption><b>{html.escape(item["door_sides"])}</b>'
                f'<span class="tag">{sides_zh(item["door_sides"])}</span>\n'
                f'<span class="tag">{w:g}×{d:g} m</span>'
                f'<span class="tag">{cw}×{cd} 格</span>'
                f'<span class="tag hot">{item["egt_occurrences"]} 处</span>\n'
                f'<code>{item["shell_id"]}</code></figcaption></figure>'
            )
        sections.append(
            f'<h2>{kind_zh} · <code>{kind}</code>'
            f'<span class="cnt">{len(items)} 种 / 实测 {total} 处</span></h2>\n'
            f'<p class="note">{html.escape(note)}</p>\n'
            f'<div class="grid">\n' + "\n".join(cards) + "\n</div>"
        )

    page = f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>挺进地牢 · 56 种房型白盒</title>
<style>
:root{{--ink:#16181A;--sub:#5F6569;--line:#D8DBDC;--bg:#EFF0F0;--paper:#fff;--accent:#0E9C86}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.7 "PingFang SC","Microsoft YaHei",system-ui,sans-serif}}
header{{padding:30px 40px 22px;background:var(--paper);border-bottom:1px solid var(--line)}}
h1{{margin:0 0 8px;font-size:25px}}
.sub{{color:var(--sub);font-size:13px;max-width:1020px}}
.wrap{{padding:10px 40px 70px;max-width:1500px;margin:0 auto}}
h2{{font-size:17px;margin:36px 0 6px;padding-left:10px;border-left:3px solid var(--accent);
   display:flex;align-items:baseline;gap:10px}}
h2 code{{font-size:13px;color:#7A8186;font-weight:400}}
.cnt{{margin-left:auto;font-size:12px;color:var(--sub);font-weight:400}}
.note{{margin:0 0 14px;padding-left:13px;font-size:12.5px;color:var(--sub);max-width:1050px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(212px,1fr));gap:14px}}
figure{{margin:0;background:var(--paper);border:1px solid var(--line);border-radius:10px;overflow:hidden;display:flex;flex-direction:column}}
figure img{{display:block;width:100%;height:auto;background:#f7f8f9;border-bottom:1px solid var(--line)}}
figcaption{{padding:9px 11px;font-size:12px;color:var(--sub)}}
figcaption b{{color:var(--ink);font-weight:600;display:block;font-size:13px;margin-bottom:5px;
  font-family:ui-monospace,Menlo,monospace}}
.tag{{display:inline-block;background:#F1EFE8;border:1px solid var(--line);border-radius:20px;
  padding:0 6px;font-size:10.5px;color:#444441;margin:0 3px 3px 0}}
.tag.hot{{background:#E3F4EF;border-color:#A9D9CD;color:#0E7A6B}}
figcaption code{{font-size:9.5px;color:#A8ADB1;word-break:break-all;display:block;margin-top:3px}}
.banner{{background:#FAEEDA;border:1px solid #EFC98A;border-radius:10px;padding:14px 18px;
  margin:18px 0 0;font-size:13px;line-height:1.8}}
.banner b{{color:#7A3E0B}}
</style></head><body>
<header><h1>挺进地牢 · 全部 {len(types)} 种房型白盒</h1>
<div class="sub">口径不是估的：从官方 flow 骨架图 PDF（<b>28 张 / 5 层 / {catalog['total_room_positions']} 个房间位</b>）
反推每个房间「门开在哪几面、每面几扇」，按 <code>(房型, 门面组合)</code> 去重 = <b>{len(types)} 种</b>。
28 张骨架的门面数全部等于边数，自检通过。</div>
<div class="banner"><b>看图看什么：</b>橙条＝门洞，格线＝5m。
<b>「N1S2」读作「北 1 扇、南 2 扇」</b> —— 同侧多门是真实房型，不是重复计数。<br>
<b>尺寸是推定值，不是 EGT 实测格数</b>：EGT 真实格数不可从公开截图反推（透视渲染图，拟合不收敛）。
尺寸由「该面墙的合法门槽数 >= 该面门数」+ 房型基准档推出，规则写在
<code>docs/v0.1/reference/挺进地牢/EGT房型种类.md</code>。<br>
房型内部顺序按<b>实测出现次数</b>降序 —— 排前面的就是每局最常撞见的形状。</div></header>
<div class="wrap">
{chr(10).join(sections)}
</div></body></html>"""
    OUT.write_text(page, encoding="utf-8")
    srcs = re.findall(r'src="([^"]+)"', page)
    missing = [s for s in srcs if not (OUT.parent / s).is_file()]
    print(f"gallery -> {OUT.relative_to(ROOT)}")
    print(f"images {len(srcs)}  missing {missing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
