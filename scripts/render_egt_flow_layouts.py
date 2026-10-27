#!/usr/bin/env python3
"""把 EGT 式组装器导出的 layouts.json 画成俯视图 + 总览页。

数据由 `tests/verification/export_egt_layouts.gd` 真实组装产生，本脚本只负责画。
图里能直接看出三件事：房间贴不贴得紧、门是不是对齐、环在哪一段用走廊闭的。

运行：
    python3 scripts/render_egt_flow_layouts.py
"""
from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "docs/art/egt_flow_layouts/layouts.json"
OUT_DIR = ROOT / "docs/art/egt_flow_layouts"

# 房型配色（与图集页一致）
KIND_COLOR = {
    "ENTRANCE": (200, 240, 210),
    "EXIT": (176, 224, 230),
    "BOSS": (235, 178, 178),
    "BOSS_FOYER": (243, 205, 205),
    "REWARD": (250, 226, 160),
    "SHOP": (214, 214, 244),
    "NORMAL": (218, 224, 232),
    "HUB": (190, 224, 236),
    "CONNECTOR": (226, 232, 208),
    "SECRET_ROOM": (240, 214, 240),
    "NPC_SECRET_ROOM": (240, 214, 240),
    "FIREPLACE_ROOM": (240, 214, 240),
}
KIND_ZH = {
    "ENTRANCE": "入口", "EXIT": "出口", "BOSS": "首领", "BOSS_FOYER": "首领前厅",
    "REWARD": "宝箱", "SHOP": "商店", "NORMAL": "战斗", "HUB": "枢纽",
    "CONNECTOR": "连接", "SECRET_ROOM": "隐藏", "NPC_SECRET_ROOM": "NPC",
    "FIREPLACE_ROOM": "壁炉",
}
SIDE_DIR = {"north": (0, -1), "south": (0, 1), "west": (-1, 0), "east": (1, 0)}
## 走廊净宽（米）。与 `corridor_catalog.json` 的 5m 净宽一致：门洞 2.2m 居中，
## 两侧各留墙肩，才能和房间侧逐米对齐。
CORRIDOR_WIDTH_M = 5.0


def kind_of(node_id: str) -> str:
    n = node_id.lower()
    if n.startswith("entry") or "entrance" in n:
        return "ENTRANCE"
    if n.startswith("exit"):
        return "EXIT"
    if n.startswith("boss_foyer") or n.startswith("bossfoyer"):
        return "BOSS_FOYER"
    if n.startswith("boss"):
        return "BOSS"
    if n.startswith("reward"):
        return "REWARD"
    if n.startswith("shop"):
        return "SHOP"
    if n.startswith("hub"):
        return "HUB"
    if n.startswith("conn"):
        return "CONNECTOR"
    if n.startswith("secret_room"):
        return "SECRET_ROOM"
    if n.startswith("npc_secret"):
        return "NPC_SECRET_ROOM"
    if n.startswith("fireplace"):
        return "FIREPLACE_ROOM"
    return "NORMAL"


def render(flow: dict, out: Path) -> None:
    from PIL import Image, ImageDraw

    rooms = flow["rooms"]
    if not rooms:
        return
    xs, ys = [], []
    for room in rooms:
        cx, cy = room["center"]
        w, h = room["size"]
        xs += [cx - w / 2, cx + w / 2]
        ys += [cy - h / 2, cy + h / 2]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span_x = max(1.0, max_x - min_x)
    span_y = max(1.0, max_y - min_y)

    target = 1400
    scale = min(target / span_x, target / span_y)
    pad = 70
    size = (int(span_x * scale) + pad * 2, int(span_y * scale) + pad * 2 + 34)

    im = Image.new("RGB", size, (247, 248, 249))
    dr = ImageDraw.Draw(im)

    def X(x: float) -> float:
        return pad + (x - min_x) * scale

    def Y(y: float) -> float:
        return pad + 24 + (y - min_y) * scale

    # 走廊先画（压在房间下层）。按 5m 净宽画成**实体通道**，
    # 不是中心细线 —— 细线会让人以为"没有通道"，那正是这张图要回答的问题。
    by_id = {r["node_id"]: r for r in rooms}

    def gate_of(room: dict, side: str, lane: float) -> tuple[float, float]:
        cx, cy = room["center"]
        w, h = room["size"]
        if side == "north":
            return (cx + lane, cy - h / 2)
        if side == "south":
            return (cx + lane, cy + h / 2)
        if side == "west":
            return (cx - w / 2, cy + lane)
        return (cx + w / 2, cy + lane)

    half = CORRIDOR_WIDTH_M / 2.0
    for corridor in flow.get("corridors", []):
        a = by_id.get(corridor["from"])
        b = by_id.get(corridor["to"])
        if not a or not b:
            continue
        ax, ay = gate_of(a, corridor.get("from_side", ""), corridor.get("from_lane", 0.0))
        bx, by = gate_of(b, corridor.get("to_side", ""), corridor.get("to_lane", 0.0))
        band = (222, 196, 150)
        edge = (150, 110, 50)
        if abs(ay - by) < 0.01:
            dr.rectangle([X(min(ax, bx)), Y(ay - half), X(max(ax, bx)), Y(ay + half)],
                         fill=band, outline=edge)
        elif abs(ax - bx) < 0.01:
            dr.rectangle([X(ax - half), Y(min(ay, by)), X(ax + half), Y(max(ay, by))],
                         fill=band, outline=edge)
        else:
            # 两个门不共线 ⇒ 走廊是折的（原文 pathfind 出来的本就允许折）
            dr.rectangle([X(ax - half), Y(min(ay, by)), X(ax + half), Y(max(ay, by))],
                         fill=band, outline=edge)
            dr.rectangle([X(min(ax, bx)), Y(by - half), X(max(ax, bx)), Y(by + half)],
                         fill=band, outline=edge)
        dr.text(((X(ax) + X(bx)) / 2, (Y(ay) + Y(by)) / 2 - 9),
                "%.0fm" % corridor["length_m"], fill=(120, 86, 30))

    for room in rooms:
        cx, cy = room["center"]
        w, h = room["size"]
        kind = kind_of(room["node_id"])
        fill = KIND_COLOR.get(kind, (220, 220, 220))
        box = [X(cx - w / 2), Y(cy - h / 2), X(cx + w / 2), Y(cy + h / 2)]
        dr.rectangle(box, fill=fill, outline=(90, 96, 102), width=2)
        label = "%s\n%s" % (room["node_id"], KIND_ZH.get(kind, kind))
        lx = (box[0] + box[2]) / 2
        ly = (box[1] + box[3]) / 2
        if (box[2] - box[0]) > 46 and (box[3] - box[1]) > 26:
            dr.multiline_text((lx, ly), label, fill=(34, 38, 42), anchor="mm", align="center")

        # 门：在墙上画一段橙色
        for side, lanes in (room["ports"] or {}).items():
            for lane in lanes:
                if side in ("north", "south"):
                    gx = cx + lane
                    gy = cy - h / 2 if side == "north" else cy + h / 2
                    dr.rectangle([X(gx) - 5, Y(gy) - 5, X(gx) + 5, Y(gy) + 5],
                                 fill=(226, 162, 36), outline=(150, 100, 30))
                else:
                    gx = cx - w / 2 if side == "west" else cx + w / 2
                    gy = cy + lane
                    dr.rectangle([X(gx) - 5, Y(gy) - 5, X(gx) + 5, Y(gy) + 5],
                                 fill=(226, 162, 36), outline=(150, 100, 30))

    title = "%s  %s ｜ seed=%s  房间 %d  环 %d  走廊 %d" % (
        flow["flow_id"], flow.get("flow_name_zh", ""), flow["seed"],
        len(rooms), flow["loops"], len(flow.get("corridors", [])))
    dr.text((pad, 10), title, fill=(28, 32, 36))
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


def main() -> int:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    cards: list[str] = []
    for flow in data["flows"]:
        name = flow["flow_id"]
        png = OUT_DIR / ("%s.png" % name)
        render(flow, png)
        corridor_html = "".join(
            f'<li>{html.escape(c["from"])} → {html.escape(c["to"])}：{c["length_m"]:.0f} m</li>'
            for c in flow.get("corridors", [])
        ) or "<li>无（全部直接贴合）</li>"
        cards.append(f"""<figure>
<img src="{name}.png" alt="{name}" loading="lazy">
<figcaption><b>{html.escape(name)} · {html.escape(flow.get("flow_name_zh", ""))}</b>
<span class="tag">{len(flow["rooms"])} 间房</span>
<span class="tag">{flow["loops"]} 个环</span>
<span class="tag">{len(flow.get("corridors", []))} 条走廊</span>
<p class="cor">走廊闭合：</p><ul>{corridor_html}</ul>
</figcaption></figure>""")

    page = f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>远征03 · EGT 式组装结果（{len(data["flows"])} 张骨架）</title>
<style>
:root{{--ink:#16181A;--sub:#5F6569;--line:#D8DBDC;--bg:#EFF0F0;--paper:#fff;--accent:#0E9C86}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.7 "PingFang SC","Microsoft YaHei",system-ui,sans-serif}}
header{{padding:28px 40px 20px;background:var(--paper);border-bottom:1px solid var(--line)}}
h1{{margin:0 0 8px;font-size:24px}}
.sub{{color:var(--sub);font-size:13px;max-width:1000px}}
.wrap{{padding:18px 40px 70px;max-width:1400px;margin:0 auto}}
figure{{margin:0 0 26px;background:var(--paper);border:1px solid var(--line);border-radius:10px;overflow:hidden}}
figure img{{display:block;width:100%;height:auto;background:#f7f8f9;border-bottom:1px solid var(--line)}}
figcaption{{padding:12px 16px;font-size:12.5px;color:var(--sub)}}
figcaption b{{color:var(--ink);font-size:13.5px;display:block;margin-bottom:6px}}
.tag{{display:inline-block;background:#F1EFE8;border:1px solid var(--line);border-radius:20px;
padding:0 8px;font-size:11px;margin:0 5px 5px 0;color:#444441}}
.cor{{margin:6px 0 2px;color:#8A5A1E}}
ul{{margin:2px 0 0 18px;padding:0}}
li{{font-size:12px;line-height:1.6}}
.legend{{display:flex;flex-wrap:wrap;gap:10px;margin:14px 0 0;font-size:12px;color:var(--sub)}}
.legend span{{display:inline-flex;align-items:center;gap:5px}}
.sw{{width:14px;height:14px;border:1px solid #6b7278;border-radius:3px;display:inline-block}}
.banner{{background:#E6F1FB;border:1px solid #B5D4F4;border-radius:10px;padding:14px 18px;
margin:16px 0 22px;font-size:13px;line-height:1.8;color:#0C447C}}
.banner b{{color:#042C53}}
</style></head><body>
<header><h1>远征03 · EGT 式组装结果</h1>
<div class="sub">由 <code>EgtFlowAssembler.assemble_flow()</code> 真实跑出来的坐标（seed={data["seed"]}），
不是手绘示意。六张骨架共 <b>{sum(len(f["rooms"]) for f in data["flows"])}</b> 间房，
全部通过「不重叠 / 每条边都落门 / 门位合法 / 同种子可复现」的断言。</div>
<div class="banner"><b>看图看什么：</b><br>
<span style="color:#8A5A1E">褐色通道</span>＝房间之间的走廊（5m 净宽，画成实体不是细线）；橙点＝门，成对出现在走廊两端。
走廊长度贴在通道上。<br>
《挺进地牢》的地图和 flow 图<b>不是一一对应</b>的 —— Boris 原话 "there's these weird corridor rooms"，
实际地图上会多出 flow 里没有的走廊房间；两房直接共墙、门对开的情况也存在，两种混着才像。<br>
环内部是「紧环 + 短廊」：环成员直接贴合，只有闭合那一段补走廊。</div>
<div class="legend">
<span><i class="sw" style="background:#c8f0d2"></i>入口</span>
<span><i class="sw" style="background:#dae0e8"></i>战斗</span>
<span><i class="sw" style="background:#bee0ec"></i>枢纽</span>
<span><i class="sw" style="background:#e2e8d0"></i>连接</span>
<span><i class="sw" style="background:#fae2a0"></i>宝箱</span>
<span><i class="sw" style="background:#d6d6f4"></i>商店</span>
<span><i class="sw" style="background:#f3cdcd"></i>首领前厅</span>
<span><i class="sw" style="background:#ebb2b2"></i>首领</span>
<span><i class="sw" style="background:#b0e0e6"></i>出口</span>
<span><i class="sw" style="background:#f0d6f0"></i>隐藏房</span>
</div></header>
<div class="wrap">
{chr(10).join(cards)}
</div></body></html>"""
    (OUT_DIR / "index.html").write_text(page, encoding="utf-8")
    print(f"rendered {len(data['flows'])} layouts -> {OUT_DIR.relative_to(ROOT)}")
    print("index ->", (OUT_DIR / "index.html").relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
