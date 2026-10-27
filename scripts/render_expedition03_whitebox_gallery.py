#!/usr/bin/env python3
"""远征03 白盒总览图集（房间 / 通道 / 门一屏核对）。

不是资产验收证据（那是 docs/art 各批次的事），是**看形状对不对**的核对页：
橙框＝门洞、蓝点＝端口，非矩形轮廓单独标出来。

运行：
    python3 scripts/render_expedition03_whitebox_gallery.py
"""
from __future__ import annotations

import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN_DIR = ROOT / "data/level_plans/expedition_03"
ROOM_DIR = ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03"
ROOM_IMG = ROOT / "docs/art/expedition03_room_whitebox"
COR_IMG = ROOT / "docs/art/expedition03_corridor_kit"
DOOR_IMG = ROOT / "docs/art/expedition03_door_kit"
OUT = ROOM_IMG / "index.html"

META_RE = re.compile(r"^metadata/(\w+) = (.+)$", re.M)


def read_meta(path: Path) -> dict[str, str]:
    return {k: v for k, v in META_RE.findall(path.read_text(encoding="utf-8"))}


def unquote(value: str) -> str:
    return value.strip().strip('"')


def room_cards() -> tuple[str, int]:
    cards: list[str] = []
    count = 0
    for png in sorted(ROOM_IMG.glob("rt_*_static_layout.png")):
        tscn = ROOM_DIR / f"{png.stem}.tscn"
        if not tscn.is_file():
            continue
        meta = read_meta(tscn)
        count += 1
        size = unquote(meta.get("size_m", "")).replace("[", "").replace("]", "").replace(", ", "×")
        area = unquote(meta.get("footprint_area_m2", ""))
        is_rect = unquote(meta.get("footprint_is_rect", "")) == "true"
        ports = unquote(meta.get("connection_port_count", ""))
        instances = unquote(meta.get("layout_instance_total", ""))
        variant = unquote(meta.get("variant", ""))
        variant_html = f' · 变体 <code>{html.escape(variant)}</code>' if variant else ""
        shape = "矩形" if is_rect else '<b class="warn">非矩形轮廓</b>'
        cards.append(
            f'<figure>\n<img src="{png.name}" alt="{png.stem}" loading="lazy">\n'
            f"<figcaption><b>{html.escape(unquote(meta.get('template_id', '')))}</b>{variant_html}\n"
            f'<span class="tag">{size} m · {area} m²</span>\n'
            f'<span class="tag">{ports} 端口 · {instances} 件</span>\n'
            f"<p>{shape}</p>\n"
            f"<code>{html.escape(unquote(meta.get('shell_id', '')))}</code></figcaption></figure>"
        )
    return "\n".join(cards), count


def corridor_cards(catalog: dict) -> str:
    cards: list[str] = []
    for shell in catalog.get("shells", []):
        sid = shell["shell_id"]
        w, d = shell["size_m"]
        cards.append(
            f'<figure>\n<img src="../expedition03_corridor_kit/{sid}.png" alt="{sid}" loading="lazy">\n'
            f"<figcaption><b>{html.escape(sid)}</b>\n"
            f'<span class="tag">{w:g}×{d:g} m</span>\n'
            f'<span class="tag">{len(shell["ports"])} 端口</span>\n'
            f"<p>{html.escape(shell['shape'])}</p>\n"
            f"<code>{html.escape(sid)}_static_layout.tscn</code></figcaption></figure>"
        )
    return "\n".join(cards)


def door_cards(catalog: dict) -> str:
    cards: list[str] = []
    for kind, entry in catalog.get("kinds", {}).items():
        policy = entry.get("access_policy")
        if policy:
            policy_text = " · ".join(
                f"{k.replace('requires_', '')}={str(v).lower()}" for k, v in policy.items()
            )
        else:
            policy_text = "<i>无开关语义（可打碎的墙）</i>"
        cards.append(
            f'<figure class="door">\n<img src="../expedition03_door_kit/wb_door_{kind}.png" '
            f'alt="{kind}" loading="lazy">\n'
            f"<figcaption><b>{html.escape(entry['display_name_zh'])}</b>\n"
            f'<span class="tag">{html.escape(entry["runtime_class"])}</span>\n'
            f'<p class="pol">{policy_text}</p>\n'
            f'<p class="egt">挺进地牢：{html.escape(entry["egt"]["behaviour"])}</p>\n'
            f"<code>{html.escape(kind)}</code></figcaption></figure>"
        )
    return "\n".join(cards)


def main() -> int:
    door_catalog = json.loads((PLAN_DIR / "door_catalog.json").read_text(encoding="utf-8"))
    corridor_catalog = json.loads((PLAN_DIR / "corridor_catalog.json").read_text(encoding="utf-8"))
    room_html, room_count = room_cards()
    cor_html = corridor_cards(corridor_catalog)
    door_html = door_cards(door_catalog)
    cor_count = len(corridor_catalog.get("shells", []))
    door_count = len(door_catalog.get("kinds", {}))

    page = f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>远征03 白盒 · 房间 / 门 / 通道</title>
<style>
:root{{--ink:#16181A;--sub:#5F6569;--line:#D8DBDC;--bg:#EFF0F0;--paper:#fff;--accent:#0E9C86}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.7 "PingFang SC","Microsoft YaHei",system-ui,sans-serif}}
header{{padding:30px 40px 22px;background:var(--paper);border-bottom:1px solid var(--line)}}
h1{{margin:0 0 8px;font-size:25px}}
.sub{{color:var(--sub);font-size:13px;max-width:1000px}}
.wrap{{padding:10px 40px 70px;max-width:1500px;margin:0 auto}}
h2{{font-size:17px;margin:36px 0 6px;padding-left:10px;border-left:3px solid var(--accent)}}
.note{{margin:0 0 16px;padding-left:13px;font-size:12.5px;color:var(--sub);max-width:1050px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:16px}}
figure{{margin:0;background:var(--paper);border:1px solid var(--line);border-radius:10px;overflow:hidden;display:flex;flex-direction:column}}
figure img{{display:block;width:100%;height:auto;background:#f7f8f9;border-bottom:1px solid var(--line)}}
figure.door img{{height:210px;object-fit:contain;padding:10px 0}}
figcaption{{padding:10px 12px;font-size:12px;color:var(--sub)}}
figcaption b{{color:var(--ink);font-weight:600;display:block;font-size:12.5px;margin-bottom:5px}}
.tag{{display:inline-block;background:#F1EFE8;border:1px solid var(--line);border-radius:20px;padding:0 7px;font-size:11px;color:#444441;margin:0 4px 4px 0}}
figcaption p{{margin:4px 0 6px;line-height:1.5}}
figcaption code{{font-size:10.5px;color:#9AA0A4;word-break:break-all}}
.pol{{color:#0E7A6B;font-family:ui-monospace,Menlo,monospace;font-size:11px}}
.egt{{color:#8A8F93;font-size:11.5px}}
.warn{{color:#B4531F}}
.banner{{background:#FAEEDA;border:1px solid #EFC98A;border-radius:10px;padding:14px 18px;margin:18px 0 0;font-size:13px;line-height:1.8}}
.banner b{{color:#7A3E0B}}
</style></head><body>
<header><h1>远征03 白盒 · 房间 / 门 / 通道</h1>
<div class="sub">全部由脚本从 <code>data/level_plans/expedition_03/</code> 的模板契约生成，几何是
<b>契约的纯函数</b>（改 JSON → 重跑 → 几何跟着变）。三批产物共
<b>{room_count} 房间 + {cor_count} 通道 + {door_count} 门型</b>。</div>
<div class="banner"><b>看这张图要看什么：</b>不是看好不好看（白盒没有美术），是看<b>形状对不对</b>。<br>
橙框＝门洞位置，蓝点＝连接端口。标着「非矩形轮廓」的几张是这次重做的核心 ——
L 形缺东南角、U 形有西侧内岛、宝箱房两变体各缺角、通道桥是「工」字。<br>
<b>上一版把它们全做成了矩形</b>，缺角处多出了不存在的地面和墙。文本门禁查不出来，只有真加载 + 量几何才抓得到。</div></header>
<div class="wrap">

<h2>房间壳（{room_count} 份）</h2>
<p class="note">端口数不是写死的：从六张骨架的节点度数反推，<code>NORMAL</code> 取四选一池里的最大值；入口安全屋另 +1 弃局门。</p>
<div class="grid">
{room_html}
</div>

<h2>通道（{cor_count} 份）</h2>
<p class="note">{html.escape(corridor_catalog.get("design_rule", ""))}</p>
<p class="note">{html.escape(corridor_catalog.get("note_width", ""))}</p>
<div class="grid">
{cor_html}
</div>

<h2>门（{door_count} 型）</h2>
<p class="note">门<b>不在</b>房间 TSCN 里 —— 房间只声明「这面能接」（<code>ConnectionPorts</code>），
门由运行时按策略落上去。加一种门只改门表，不动任何房间文件。</p>
<div class="grid">
{door_html}
</div>

</div></body></html>
"""
    OUT.write_text(page, encoding="utf-8")
    srcs = re.findall(r'src="([^"]+)"', page)
    missing = [s for s in srcs if not (OUT.parent / s).is_file()]
    print(f"gallery -> {OUT.relative_to(ROOT)}")
    print(f"images {len(srcs)}  missing {missing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
