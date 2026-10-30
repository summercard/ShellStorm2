#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把远征03 怪物画像（Godot 出图 + 运行时数值）拼成一张自包含 HTML 表。

数据来源（全部为**运行时真实值**，不重算公式）：
  1. outputs/expedition03_monster_roster/manifest.json
     —— 由 tools/_egt_roster_portrait.gd 跑 Godot 导出，数值取
        `MonsterInjector.set_level_rules(远征03 monster_rules)` → `configure_from_enemy_data()`
        之后实例上的 max_hp / contact_damage / move_speed / attack_range / attack_cooldown。
        这一条链与游戏里刷怪完全相同，所以表里的数就是玩家会遇到的数。
  2. docs/v0.1/design/怪物设计.md §T1 —— 中文名、族、攻击方式自然语言描述。
  3. data/level_plans/expedition_03/level_plan.json + data/spawn_boxes/box_egt_*.json
     —— 出场房间（逐房编成反查）。
  4. src/enemy3d/Enemy3D.gd PROFILES —— 弹道图案 / 分裂子代 / 特殊行为键。

图片以 base64 内嵌，产出的 HTML 是**单文件**，发给谁都能直接打开。

用法：
    python tools/egt_roster_page.py
"""

from __future__ import annotations

import base64
import json
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "outputs" / "expedition03_monster_roster"
MANIFEST = OUT_DIR / "manifest.json"
DESIGN_MD = ROOT / "docs" / "v0.1" / "design" / "怪物设计.md"
LEVEL_PLAN = ROOT / "data" / "level_plans" / "expedition_03" / "level_plan.json"
BOX_DIR = ROOT / "data" / "spawn_boxes"
HTML_OUT = OUT_DIR / "远征03_怪物数值总表.html"

# 表里的行序 = 族序。与 Godot 出图脚本的 KINDS 同序，改一处要同步另一处。
FAMILY_ORDER = [
    "子弹族", "霰弹枪族", "爆炸族", "分裂族",
    "书怪族", "法术 / 辅助族", "一次性冲撞族", "触发 / 逃逸族", "重型",
]

# 族色：只用于 chip 底色，不承载数值含义
FAMILY_HUE = {
    "子弹族": "#38bdf8",
    "霰弹枪族": "#fb7185",
    "爆炸族": "#fb923c",
    "分裂族": "#a78bfa",
    "书怪族": "#facc15",
    "法术 / 辅助族": "#c084fc",
    "一次性冲撞族": "#2dd4bf",
    "触发 / 逃逸族": "#f472b6",
    "重型": "#94a3b8",
}

# 房间 id 的人话名（取 level_plan.spawn_roster.by_node[*].label 的前半段）
def _parse_design() -> dict[str, dict]:
    text = DESIGN_MD.read_text(encoding="utf-8")
    block = re.search(r"## T1\..*?\n## T2\.", text, re.S).group(0)
    family = ""
    rows: dict[str, dict] = {}
    for line in block.splitlines():
        head = re.match(r"### T1\.\d+\s*(.+)", line)
        if head:
            family = head.group(1).strip()
            family = re.sub(r"（\d+\s*种）", "", family).strip()
            continue
        if line.startswith("| `"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            kind = cells[0].strip("`")
            rows[kind] = {
                "name": cells[1],
                "egt_hp": cells[2],
                "family": family,
                "attack": _plain(cells[5]),
            }
    return rows


def _plain(text: str) -> str:
    """把 markdown 的 **粗体** / `代码` 抹掉，保留文字。"""
    text = text.replace("**", "").replace("`", "")
    text = re.sub(r"（原文.*?）", "", text)
    return text.strip()


def _rooms() -> dict[str, list[str]]:
    """反查每只怪出现在哪些房间。

    遍历 spawn_roster 的 by_node / by_kind，展开盒子里的 spawns。
    `by_kind` 是兜底（注入房被洗成 COMBAT/HUB 时用），标成 `兜底·NORMAL` 这类。
    """
    plan = json.loads(LEVEL_PLAN.read_text(encoding="utf-8"))
    roster = plan["spawn_roster"]
    boxes: dict[str, list[tuple[str, int]]] = {}
    for path in BOX_DIR.glob("box_egt_*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        boxes[data["box_id"]] = [
            (s["type"], int(s.get("count", 1))) for s in data.get("spawns", [])
        ]

    out: dict[str, list[str]] = {}

    def add(box_id: str, where: str) -> None:
        for kind, count in boxes.get(box_id, []):
            label = where if count == 1 else f"{where}×{count}"
            out.setdefault(kind, [])
            if label not in out[kind]:
                out[kind].append(label)

    for node, entry in roster.get("by_node", {}).items():
        for box_id in entry.get("boxes", []):
            add(box_id, node)
    for kind_key, entry in roster.get("by_kind", {}).items():
        for box_id in entry.get("boxes", []):
            add(box_id, f"兜底·{kind_key}")
    return out


def _volley_text(m: dict) -> str:
    """把 volley 参数翻成一句人话，附在攻击方式后面 —— 表里「几发怎么散」比形容词有用。"""
    volley = m.get("volley") or {}
    if not volley:
        return ""
    parts: list[str] = []
    pattern = volley.get("pattern")
    count = volley.get("count")
    spread = volley.get("spread_deg")
    predict = volley.get("predict")
    homing = volley.get("homing")
    bounce = volley.get("bounce")
    interval = volley.get("interval")
    if pattern:
        parts.append(f"图案 {pattern}")
    if count:
        parts.append(f"{count} 发")
    if spread:
        parts.append(f"±{spread:g}°")
    if interval:
        parts.append(f"间隔 {interval:g}s")
    if predict:
        parts.append(f"预判 {predict * 100:.0f}%")
    if homing:
        parts.append(f"追踪 {homing * 100:.0f}%")
    if bounce:
        parts.append(f"反弹 {bounce} 次")
    if m.get("alt_every"):
        parts.append(f"每 {m['alt_every']} 次换招")
    return "；".join(parts)


def _special_text(m: dict) -> str:
    """非弹道机制（分裂 / 自爆 / 瞬移 / 逃跑 / 辅助 / 抓取 / 绕圈 / 蛋 / 伪装 / 大弹）。"""
    bits: list[str] = []
    split = m.get("death_split") or {}
    if split:
        if split.get("children"):
            bits.append("死后产 " + " + ".join(
                f"{c['count']}×{c['child'].replace('egt_', '')}" for c in split["children"]
            ))
        elif split.get("child"):
            bits.append(f"死后裂 {split.get('count', 1)}×{split['child'].replace('egt_', '')}")
    burst = m.get("death_burst") or {}
    if burst:
        chance = burst.get("chance", 1.0)
        bits.append(
            f"死亡{'必' if chance >= 1.0 else f'{chance * 100:.0f}%'}喷 {burst.get('count')} 发"
        )
    blink = m.get("blink") or {}
    if blink:
        if blink.get("on_attack"):
            bits.append(f"出手后瞬移（冷却 {blink.get('cooldown')}s）")
        else:
            bits.append(f"每 {blink.get('interval')}s 瞬移 ≤{blink.get('radius_m')}m")
    flee = m.get("flee") or {}
    if flee:
        bits.append(f"{flee.get('vanish_after')}s 未击杀则消失")
    buff = m.get("support_buff") or {}
    if buff:
        bits.append(
            f"给同伴 +{buff.get('hp_ratio', 0) * 100:.0f}% 血 / 提速 {buff.get('speed_mult')}×，"
            f"半径 {buff.get('radius_m')}m"
        )
    grab = m.get("grab") or {}
    if grab:
        bits.append(
            f"悬停 {grab.get('hover_height_m')}m 下压抓人（不改血，改位置）"
        )
    orbit = m.get("orbit") or {}
    if orbit:
        bits.append(
            f"子弹链 {orbit.get('rev_per_sec')} 圈/s × {orbit.get('duration')}s，"
            f"半径 {orbit.get('radius_m')}m"
        )
    egg = m.get("egg") or {}
    if egg:
        bits.append(f"蛋落点炸 {egg.get('burst_count')} 发")
    disguise = m.get("disguise") or {}
    if disguise:
        bits.append(
            f"静止伪装（靠近 {disguise.get('reveal_radius_m')}m 或被打现形，{disguise.get('max_sec')}s 兜底）"
        )
    jammed = m.get("jammed") or {}
    if jammed:
        bits.append(f"大弹撞墙炸 {jammed.get('shatter_count')} 发")
    rush = m.get("suicide_rush") or {}
    if rush:
        extra = []
        if rush.get("repositions"):
            extra.append(f"中途重定位 {rush['repositions']} 次")
        if rush.get("predict"):
            extra.append(f"预判 {rush['predict'] * 100:.0f}%")
        on_hit = rush.get("on_hit") or {}
        if on_hit:
            extra.append(f"撞到吐 {on_hit.get('count')} 发")
        bits.append(f"冲撞 {rush.get('speed')}m/s" + (f"（{'，'.join(extra)}）" if extra else ""))
    chance_moves = m.get("chance_moves") or {}
    if chance_moves:
        bits.append(
            f"{chance_moves.get('self_destruct_chance', 0) * 100:.0f}% 不攻击直接死"
        )
    leap = m.get("leap") or {}
    if leap:
        bits.append(f"先扑 {leap.get('leap_speed')}m/s 再炸")
    wander = m.get("wander") or {}
    if wander:
        bits.append(f"房内游荡（半径 {wander.get('radius_m')}m）")
    if m.get("immobile"):
        bits.append("原地不动")
    if m.get("hover"):
        bits.append("浮空")
    return "；".join(bits)


def build() -> Path:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    design = _parse_design()
    rooms = _rooms()

    # 分裂子代（blobulin）只由死亡分裂产生，不在任何盒子里 —— 单独标出来，
    # 否则表里会有一只"查不到出场房间"的怪，看着像数据缺失。
    rooms.setdefault("egt_blobulin", ["分裂产物（布洛布幼体死后）"])

    monsters = []
    for m in manifest["monsters"]:
        kind = m["kind"]
        d = design.get(kind, {})
        png = Path(m["png"])
        b64 = base64.b64encode(png.read_bytes()).decode("ascii")
        monsters.append({
            **m,
            "name": d.get("name", kind),
            "family": d.get("family", ""),
            "attack_desc": d.get("attack", ""),
            "egt_hp": d.get("egt_hp", ""),
            "volley_text": _volley_text(m),
            "special_text": _special_text(m),
            "rooms": rooms.get(kind, []),
            "img": f"data:image/png;base64,{b64}",
        })

    order = {f: i for i, f in enumerate(FAMILY_ORDER)}
    # 族内**按血量升序**：横向一列读下来就是这条族线的强度阶梯，
    # 比按设计文档书写顺序更能看出"谁比谁硬"。
    # 同血量（子弹族三只、书怪三只全是同血）保持 manifest 里的原始顺序 ——
    # 那个顺序是按"行为从简到繁"排的，正好是同血怪该有的次序。
    seq = {m["kind"]: i for i, m in enumerate(monsters)}
    monsters.sort(key=lambda x: (order.get(x["family"], 99), x["hp"], seq[x["kind"]]))

    totals = {
        "count": len(monsters),
        "families": len({m["family"] for m in monsters}),
        "hp_sum": sum(m["hp"] for m in monsters),
        "hp_min": min(m["hp"] for m in monsters),
        "hp_max": max(m["hp"] for m in monsters),
    }
    html = _render(monsters, totals)
    HTML_OUT.write_text(html, encoding="utf-8")
    return HTML_OUT


def _render(monsters: list[dict], totals: dict) -> str:
    rows = []
    for m in monsters:
        rgb = FAMILY_HUE.get(m["family"], "#94a3b8")
        bar = min(100.0, m["hp"] / 10.0)
        dmg = f'{m["damage"]}' if m["damage"] else '<span class="zero">0</span>'
        proj = (
            f'{m["projectile_speed"]:g}'
            if m["projectile_speed"] and m["attack_style"] == "volley"
            # rush 类也有 `projectile_speed`（PROFILES 里统一填了 8.0），但那是
            # 撞到之后附加弹的**默认值**，不是冲撞速度 —— 冲撞速度在 `suicide_rush.speed`
            # （11.0 / 10.5 / 9.5），机制列已经写了。这里填 8 会让人以为是"这只怪以 8m/s 冲过来"。
            else '<span class="dash">—</span>'
        )
        cd = (
            f'{m["cooldown"]:g}'
            if m["cooldown"] < 90
            else '<span class="dash">—</span>'
        )
        mech = " · ".join(x for x in [m["volley_text"], m["special_text"]] if x)
        rooms = " ".join(f'<span class="room">{r}</span>' for r in m["rooms"]) or '<span class="dash">—</span>'
        # 分裂族刻意不染色（同一只怪的分裂体应同貌），借用的正式模型保持原贴图 ——
        # 此时 `body_color` 只是查表兜底的白色，不是设计意图，不能当体型色写出来。
        if not m.get("tinted", True):
            swatch = '<div class="swatch"><span class="dash">原贴图未染色 · 同族同貌</span></div>'
        else:
            swatch = (
                f'<div class="swatch"><i style="background:{m["body_color"]}"></i>'
                f'体型 {m["body_scale"]:.2f} · 高 {m["world_height"]:.2f}m</div>'
            )
        rows.append(f"""
    <tr class="row" data-family="{m['family']}">
      <td class="shot"><img src="{m['img']}" alt="{m['name']}" loading="lazy"></td>
      <td class="ident">
        <div class="nm">{m['name']}</div>
        <div class="kid">{m['kind']}</div>
        {swatch}
      </td>
      <td><span class="chip" style="--c:{rgb}">{m['family']}</span></td>
      <td class="num hp"><div class="hpv">{m['hp']}</div><div class="hpbar"><i style="width:{bar:.1f}%"></i></div></td>
      <td class="num">{dmg}</td>
      <td class="num">{m['move_speed']:.1f}</td>
      <td class="num">{m['attack_range']:g}</td>
      <td class="num">{cd}</td>
      <td class="num">{proj}</td>
      <td class="mech">{mech or '<span class="dash">—</span>'}</td>
      <td class="rooms">{rooms}</td>
    </tr>""")

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>远征03 · 怪物数值总表</title>
<style>
  :root {{
    --bg: #0e1116;
    --panel: #151a22;
    --panel-2: #1a212b;
    --line: #242c38;
    --text: #e6ecf5;
    --muted: #8794a8;
    --accent: #5eead4;
  }}
  * {{ box-sizing: border-box; }}
  html, body {{ margin: 0; background: var(--bg); color: var(--text); }}
  body {{
    font: 14px/1.55 "Microsoft YaHei UI", "PingFang SC", "Segoe UI", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }}
  .wrap {{ padding: 28px 30px 60px; max-width: 1780px; margin: 0 auto; }}

  header {{ display: flex; align-items: flex-end; justify-content: space-between;
            gap: 24px; padding-bottom: 18px; border-bottom: 1px solid var(--line); }}
  h1 {{ margin: 0 0 6px; font-size: 25px; letter-spacing: .5px; font-weight: 700; }}
  h1 small {{ font-size: 13px; color: var(--muted); font-weight: 400; margin-left: 10px; }}
  .sub {{ color: var(--muted); font-size: 12.5px; }}
  .stats {{ display: flex; gap: 26px; text-align: right; flex: none; }}
  .stat b {{ display: block; font-size: 22px; font-variant-numeric: tabular-nums; color: var(--accent); }}
  .stat span {{ font-size: 11.5px; color: var(--muted); }}

  .legend {{ display: flex; flex-wrap: wrap; gap: 8px; margin: 16px 0 12px; }}
  .legend .chip {{ cursor: pointer; opacity: .55; transition: opacity .15s; }}
  .legend .chip:hover {{ opacity: 1; }}
  .legend .chip.on {{ opacity: 1; outline: 1px solid var(--c); }}

  .note {{ display: flex; flex-wrap: wrap; gap: 6px 18px; margin: 0 0 16px;
           color: var(--muted); font-size: 12px; }}
  .note b {{ color: #b9c6d8; font-weight: 600; }}

  table {{ width: 100%; border-collapse: separate; border-spacing: 0; }}
  thead th {{
    position: sticky; top: 0; z-index: 5;
    background: var(--panel-2); color: #9fb0c6;
    font-size: 11.5px; font-weight: 600; letter-spacing: .4px;
    text-align: left; padding: 9px 10px; white-space: nowrap;
    border-bottom: 1px solid var(--line);
  }}
  thead th:first-child {{ border-top-left-radius: 8px; }}
  thead th:last-child {{ border-top-right-radius: 8px; }}
  tbody tr {{ background: var(--panel); }}
  tbody tr:nth-child(even) {{ background: #131922; }}
  tbody tr:hover {{ background: #1d2735; }}
  tbody tr.hide {{ display: none; }}
  td {{ padding: 10px; border-bottom: 1px solid #1c232d; vertical-align: middle; }}

  .shot {{ width: 118px; padding: 6px 4px 6px 10px; }}
  .shot img {{
    width: 104px; height: 112px; object-fit: contain; display: block;
    border-radius: 6px; background: radial-gradient(ellipse at 50% 78%, #182231 0%, #0e1116 72%);
  }}
  .ident {{ width: 190px; }}
  .nm {{ font-size: 15px; font-weight: 600; }}
  .kid {{ font-family: Consolas, "Cascadia Mono", monospace; font-size: 11px;
          color: #6f7f95; margin-top: 1px; }}
  .swatch {{ display: flex; align-items: center; gap: 5px; font-size: 11px;
             color: var(--muted); margin-top: 5px; }}
  .swatch i {{ width: 9px; height: 9px; border-radius: 2px; display: inline-block;
               box-shadow: 0 0 0 1px rgba(255,255,255,.18) inset; }}

  .chip {{
    --c: #94a3b8;
    display: inline-block; padding: 2px 8px; border-radius: 999px; white-space: nowrap;
    font-size: 11.5px; color: var(--c);
    background: color-mix(in srgb, var(--c) 14%, transparent);
    box-shadow: 0 0 0 1px color-mix(in srgb, var(--c) 30%, transparent) inset;
  }}

  .num {{ font-variant-numeric: tabular-nums; font-size: 13.5px; width: 74px; }}
  .hp {{ width: 100px; }}
  .hpv {{ font-weight: 600; }}
  .hpbar {{ height: 3px; border-radius: 2px; background: #232c38; margin-top: 4px; }}
  .hpbar i {{ display: block; height: 100%; border-radius: 2px;
              background: linear-gradient(90deg, #22d3ee, #818cf8); }}
  .zero {{ color: #f59e0b; font-weight: 600; }}
  .dash {{ color: #4b5768; }}

  .mech {{ font-size: 12.5px; color: #b3c0d2; max-width: 330px; }}
  .rooms {{ width: 170px; }}
  .room {{
    display: inline-block; margin: 1px 3px 1px 0; padding: 1px 6px; border-radius: 4px;
    background: #1e2836; color: #8fa3bd; font-size: 11px;
    font-family: Consolas, "Cascadia Mono", monospace;
  }}

  footer {{ margin-top: 26px; color: #63718a; font-size: 11.5px; line-height: 1.9; }}
  footer code {{ color: #8ea3bd; }}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div>
      <h1>远征03 · 怪物数值总表<small>《挺进地牢》第一层复刻 · 32 只</small></h1>
      <div class="sub">数值为<span style="color:#b9c6d8">运行时实战绝对值</span>（关卡 monster_rules 覆盖后），
        模型为游戏内实际加载的占位资产实拍。</div>
    </div>
    <div class="stats">
      <div class="stat"><b>{totals['count']}</b><span>怪物种类</span></div>
      <div class="stat"><b>{totals['families']}</b><span>族</span></div>
      <div class="stat"><b>{totals['hp_min']}–{totals['hp_max']}</b><span>血量区间</span></div>
    </div>
  </header>

  <div class="legend">{_legend(monsters)}</div>

  <div class="note">
    <span><b>血量</b> EGT 血 ×10，与初始步枪 50 伤对齐击杀发数</span>
    <span><b>伤害</b> 普通 17 = 玩家 100 血的 1/6；0 = 不造成伤害</span>
    <span><b>移速</b> m/s，已含全局 ×0.7 系数</span>
    <span><b>攻击距离</b> m，进入该距离才开始出手</span>
    <span><b>冷却</b> s，— = 一次性冲撞类无冷却</span>
    <span><b>弹速</b> m/s，— = 不发射子弹</span>
    <span><b>体型 / 高</b> 根缩放与模型世界高（玩家 1.8m）</span>
  </div>

  <table>
    <thead>
      <tr>
        <th>模型</th>
        <th>名称 / ID</th>
        <th>族</th>
        <th>血量</th>
        <th>伤害</th>
        <th>移速</th>
        <th>攻击距离</th>
        <th>冷却</th>
        <th>弹速</th>
        <th>攻击方式 / 机制</th>
        <th>出场房间</th>
      </tr>
    </thead>
    <tbody>{''.join(rows)}
    </tbody>
  </table>

  <footer>
    出图与数值：<code>tools/_egt_roster_portrait.gd</code>（Godot 正交相机统一比例尺，逐只单拍）→
    <code>outputs/expedition03_monster_roster/manifest.json</code> →
    本表由 <code>tools/egt_roster_page.py</code> 生成 · {stamp}<br>
    数值真源：<code>data/level_plans/expedition_03/level_plan.json → monster_rules.stats.per_kind</code> ·
    <code>src/enemy3d/Enemy3D.gd → PROFILES</code> ·
    编成真源：<code>spawn_roster</code> + <code>data/spawn_boxes/box_egt_*.json</code><br>
    占位美术：子弹/霰弹/触发/重型族借保安僵尸、胖子僵尸，分裂族借小僵尸，
    爆炸/冲撞族借炸弹果，法术/书怪/辅助族借蜂巢怪 —— 后期换正式模型时数值与 AI 不受影响。
  </footer>
</div>
<script>
  const chips = document.querySelectorAll('.legend .chip');
  const rows = document.querySelectorAll('tbody tr.row');
  chips.forEach(chip => {{
    chip.addEventListener('click', () => {{
      const on = chip.classList.toggle('on');
      const active = [...chips].filter(c => c.classList.contains('on')).map(c => c.dataset.f);
      rows.forEach(r => {{
        r.classList.toggle('hide', active.length > 0 && !active.includes(r.dataset.family));
      }});
      if (!on && active.length === 0) {{}}
    }});
  }});
</script>
</body>
</html>
"""


def _legend(monsters: list[dict]) -> str:
    seen: list[tuple[str, int]] = []
    for m in monsters:
        for i, (fam, n) in enumerate(seen):
            if fam == m["family"]:
                seen[i] = (fam, n + 1)
                break
        else:
            seen.append((m["family"], 1))
    return "".join(
        f'<span class="chip" data-f="{fam}" style="--c:{FAMILY_HUE.get(fam, "#94a3b8")}">'
        f"{fam} · {n}</span>"
        for fam, n in seen
    )


if __name__ == "__main__":
    path = build()
    print(f"ROSTER_PAGE {path}")
    print(f"size {path.stat().st_size / 1024:.0f} KB")
