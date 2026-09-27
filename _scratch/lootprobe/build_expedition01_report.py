# -*- coding: utf-8 -*-
"""生成《远征关卡01 · 怪物与掉落实况表》HTML。
数据源：
  ① 设计源 L2 source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json
  ② 运行时探针实测（Godot 4.6.3 headless，_scratch/lootprobe/probe_expedition_monsters.tscn，seed 77001199）
  ③ 掉落池明细 dump（_scratch/lootprobe/loot_pools_dump.tsv，源自 dump_loot.gd）
"""
import html
import os

BASE = os.path.dirname(os.path.abspath(__file__))
TSV = os.path.join(BASE, "loot_pools_dump.tsv")
OUT = os.path.abspath(os.path.join(BASE, "..", "..", "outputs", "expedition01_monsters_loot.html"))

# ---------------------------------------------------------------- 静态数据
# 序号 / 房号 / 内容类型 / 示例版图房型 / 波次 / 每波编成 / 期望只数 / floor_level / 怪物掉落池
ROOMS = [
    ("①", "entry", "—", "安全屋 15×15", "—", "不刷怪（起点；唯一弃局门）", "0", "0", "—", ""),
    ("②", "room_01", "COMBAT", "拐角走廊 L 45×40", "1",
     "W1 池[小僵尸·地刺虫] → 抽 1 种 → 2–4", "3", "0", "loot_floor_1_2", ""),
    ("③", "room_02", "SCAVENGE", "数据库 db_01 40×30", "1",
     "W1 池[小僵尸·孢子射手·地刺虫] → 抽 1–2 种 → 2–4", "3", "0", "loot_floor_1_2", ""),
    ("④", "room_03", "COMBAT", "办公室 30×40", "2",
     "W1 池[小僵尸·孢子射手·地刺虫] → 抽 1–2 种 → 3–5<br>W2 池[壳甲卫兵·孢子射手·蜂巢怪] → 抽 1–2 种 → 3–5",
     "8", "0", "loot_floor_1_2", ""),
    ("⑤", "room_04", "COMBAT", "拐角走廊 u_turn 45×40", "2",
     "W1 池[地刺虫·炸弹果·小僵尸] → 抽 1–2 种 → 3–5<br>W2 池[小僵尸·地刺虫] → 抽 1–2 种 → 3–5",
     "8", "1", "loot_floor_3_4", ""),
    ("⑥", "room_05", "COMBAT", "通道桥 30×60 工字型", "2",
     "W1 池[壳甲卫兵·孢子射手·小僵尸] → 抽 1–2 种 → 3–5<br>W2 池[蜂巢怪·小僵尸·炸弹果·孢子射手] → 抽 2–3 种 → 5–8",
     "10.5", "1", "loot_floor_3_4", "本关唯一立体战斗空间"),
    ("⑦", "room_06", "SCAVENGE", "数据库 db_02 40×30", "1",
     "W1 池[小僵尸·地刺虫·孢子射手] → 抽 1–2 种 → 2–4", "3", "1", "loot_floor_3_4", ""),
    ("⑧", "room_07", "STORAGE", "标准房 25×25", "1",
     "W1 池[壳甲卫兵·小僵尸·地刺虫] → 抽 1–2 种 → 2–4", "3", "1", "loot_floor_3_4", ""),
    ("⑨", "room_08", "COMBAT", "拐角走廊 L 45×40", "2",
     "W1 池[孢子射手·小僵尸·地刺虫] → 抽 2–3 种 → 5–7<br>W2 池[地刺虫·炸弹果·壳甲卫兵] → 抽 1–2 种 → 3–5",
     "10", "2", "loot_floor_5", ""),
    ("⑩", "room_09", "EVENT", "办公室 30×40", "—",
     "不刷怪（走紫色光柱「异常信号终端」事件）", "0", "2", "—", "全关唯一事件房"),
    ("⑪", "room_10", "SCAVENGE", "数据库 db_01 40×30", "1",
     "W1 池[小僵尸·孢子射手·壳甲卫兵] → 抽 1–2 种 → 3–5", "4", "2", "loot_floor_5", ""),
    ("⑫", "boss", "BOSS", "Boss竞技场 50×40", "—",
     "⚠ 无 Boss（未指派首领 ⇒ 合法空房，直接放行；也不配精英随从）", "0", "2", "loot_floor_5 *", "掉落实为 0"),
    ("⑬", "extraction", "—", "撤离屋 25×25", "—", "不刷怪（常驻撤离信标）", "0", "3", "—", ""),
]

# 怪物名册：内部 id / 中文名 / 基础 hp / 实际 hp / 基础 dmg / 实际 dmg / 速度 / 行为 / 出场房
MONSTERS = [
    ("melee_chaser", "小僵尸", "25", "23", "5", "4", "80", "追击", "room_01/02/03/04/05/06/07/08/10"),
    ("ranged_caster", "孢子射手", "15", "14", "8", "7", "50", "远程", "room_02/03/05/06/08/10"),
    ("summoner", "蜂巢怪", "30", "28", "0", "0", "40", "召唤", "room_03 W2 / room_05 W2"),
    ("shielded", "壳甲卫兵", "40", "38", "3", "2", "30", "追击", "room_03 W2 / room_05 W1 / room_07 / room_10"),
    ("exploder", "炸弹果", "10", "9", "15", "14", "70", "自爆", "room_04 W1 / room_05 W2 / room_08 W2"),
    ("ambusher", "地刺虫", "18", "17", "7", "6", "90", "陷阱", "room_01/02/03/04/06/07/08"),
]

KILL_RULES = [
    ("普通怪 · 非货币物品", "26%", "从该房掉落池抽 1 件（数量恒为 1；堆叠只发生在拾取入包后）"),
    ("普通怪 · 备弹", "34%", "item_ammo_pack 通用弹药 3–8 个；若池里已抽到同一物品，以整包数量覆盖该件"),
    ("普通怪 · 魂（撤离点）", "100%", "extraction_points = 2 + 1 × floor = <b>3</b>（floor = 1）"),
    ("精英（本关无）", "—", "item_chance 1.0 / 弹药 8–16 / 魂 50 + 20×floor —— 本关无 ELITE 房、也无 Boss 随从"),
    ("Boss（本关无）", "—", "pool = boss_floor_1，item_chance 1.0 / 弹药 8–16 / 魂 200 + 20×floor"),
]

CONTAINER_RULES = [
    ("可搜容器从哪来", "房间随机器具里每个 prop 独立 50% 概率变成「可搜」"),
    ("每房 prop 总数", "size_class = tower_cell ⇒ 3 个；SCAVENGE / STORAGE 房 <b>+2</b> ⇒ 5 个；Boss 房 = 0 个"),
    ("每房可搜容器期望", "普通内容房 ≈ 1.5 个；SCAVENGE / STORAGE 房 ≈ 2.5 个；Boss 房 0 个"),
    ("开一个容器给什么", "从池 <b>scavenge_floor_1</b> 抽 1 件落地（魂类折算为 1）"),
    ("副作用", "开容器会发出 8 m 声音刺激，吸引附近怪物"),
    ("清房给钥匙", "房未声明 door_policies 时清房给 1 把 item_room_key（START/EXTRACTION 除外）"),
]

# 掉落池登记（dump 的 ##TOTAL 行）
POOLS_META = {
    "loot_floor_1_2": ("浅层掉落池（1–2 层）", "怪物击杀", "room_01 / room_02 / room_03"),
    "loot_floor_3_4": ("中层掉落池（3–4 层）", "怪物击杀", "room_04 / room_05 / room_06 / room_07"),
    "loot_floor_5": ("深层掉落池（5 层）", "怪物击杀", "room_08 / room_10"),
    "loot_abyss": ("深渊掉落池", "怪物击杀", "（本关无房命中）"),
    "scavenge_floor_1": ("搜刮掉落池（1 层）", "容器 / 搜刮", "所有可搜容器"),
    "elite_floor_1": ("精英掉落池（1 层）", "精英怪", "（本关无精英）"),
    "boss_floor_1": ("首领掉落池（1 层）", "Boss", "（本关无 Boss）"),
}
POOL_ORDER = ["loot_floor_1_2", "loot_floor_3_4", "loot_floor_5", "loot_abyss",
              "scavenge_floor_1", "elite_floor_1", "boss_floor_1"]

RARITY_COLOR = {
    "common": "#6b7280", "uncommon": "#0f9d58", "rare": "#2563eb",
    "epic": "#a855f7", "legendary": "#d97706",
}
RARITY_ZH = {"common": "普通", "uncommon": "精良", "rare": "稀有", "epic": "史诗", "legendary": "传说"}

# ---------------------------------------------------------------- 读掉落池明细
pools = {k: {"rows": [], "total": 0.0, "count": 0} for k in POOL_ORDER}
with open(TSV, "r", encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if parts[0] == "##TOTAL":
            key = parts[1]
            if key in pools:
                pools[key]["count"] = int(parts[2])
                pools[key]["total"] = float(parts[3])
            continue
        pool = parts[0]
        if pool not in pools:
            continue
        pools[pool]["rows"].append({
            "id": parts[1], "name": parts[2], "type": parts[3], "subtype": parts[4],
            "rarity": parts[5], "tier": parts[6], "price": parts[7],
            "weight": float(parts[9]), "pct": float(parts[10]),
        })

# ---------------------------------------------------------------- HTML
CSS = """
* { box-sizing: border-box; }
body { margin: 0; padding: 32px 28px 64px; background: #ffffff; color: #1f2328;
  font: 14px/1.65 "Segoe UI", "Microsoft YaHei", -apple-system, sans-serif; }
h1 { font-size: 26px; margin: 0 0 6px; letter-spacing: .5px; }
h2 { font-size: 18px; margin: 38px 0 10px; padding-left: 10px;
  border-left: 4px solid #2563eb; line-height: 1.3; }
h3 { font-size: 15px; margin: 24px 0 8px; color: #374151; }
.sub { color: #6b7280; font-size: 13px; margin-bottom: 22px; }
.meta { background: #f6f8fa; border: 1px solid #e5e7eb; border-radius: 8px;
  padding: 14px 18px; margin: 0 0 8px; font-size: 13px; }
.meta b { color: #111827; }
table { border-collapse: collapse; width: 100%; margin: 10px 0 6px; font-size: 13px; }
th, td { border: 1px solid #e5e7eb; padding: 7px 9px; text-align: left; vertical-align: top; }
th { background: #f6f8fa; font-weight: 600; color: #374151; white-space: nowrap; }
tbody tr:nth-child(even) { background: #fcfcfd; }
td.c, th.c { text-align: center; }
td.num { text-align: right; font-variant-numeric: tabular-nums; }
code { background: #f3f4f6; padding: 1px 5px; border-radius: 4px;
  font-family: Consolas, "Courier New", monospace; font-size: 12px; }
.tag { display: inline-block; padding: 1px 7px; border-radius: 10px; font-size: 12px;
  border: 1px solid #d1d5db; background: #f9fafb; }
.warn { background: #fff8e6; border: 1px solid #f5d789; border-left: 4px solid #eab308;
  border-radius: 6px; padding: 12px 16px; margin: 12px 0; font-size: 13px; }
.warn b { color: #92400e; }
.ok { background: #f0fdf4; border: 1px solid #bbf7d0; border-left: 4px solid #22c55e;
  border-radius: 6px; padding: 12px 16px; margin: 12px 0; font-size: 13px; }
.pool { margin-top: 22px; }
.pool h3 span { color: #6b7280; font-weight: 400; font-size: 13px; }
.bar { display: inline-block; height: 9px; background: #93c5fd; border-radius: 3px;
  vertical-align: middle; min-width: 2px; }
.foot { margin-top: 40px; padding-top: 14px; border-top: 1px solid #e5e7eb;
  color: #9ca3af; font-size: 12px; }
"""


def esc(s):
    return html.escape(str(s))


out = []
out.append('<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">')
out.append('<title>远征关卡01 · 怪物与掉落实况表</title><style>' + CSS + '</style></head><body>')
out.append('<h1>远征关卡01 · 怪物与掉落实况表</h1>')
out.append('<div class="sub">数据源：设计源 L2 <code>floor_00.json</code>（编成）'
           '＋ 运行时 headless 探针实测（掉落地图 / 池命中）＋ <code>ItemRegistry</code> 掉落池明细。'
           '生成时间 2026-09-25。</div>')

out.append('<div class="meta">'
           '<b>关卡</b> expedition_01「远征前哨站」 · 单层独立行动 · 主路 13 房一线到底（安全屋 + 10 内容房 + Boss竞技场 + 撤离屋）<br>'
           '<b>运行时主题</b> <code>iron_frontier</code>（边境） · <code>difficulty_rank = 1</code> ⇒ '
           '<code>floor = 1</code>（数值缩放档 <code>FLOOR_SCALING[1] = 1.0 / 1.0</code>）<br>'
           '<b>主题倍率</b> HP ×0.95 · 伤害 ×0.95 · 速度 ×1.0 ⇒ 怪物名一律带前缀「边境」<br>'
           '<b>敌群总数</b> 设计源编成期望 <b>≈ 52.5 只</b>（13 房中 9 房刷怪、1 房事件、Boss 房空、共 12 波）<br>'
           '<b>每局变化</b> 波次<u>按房号钉死</u>，每波<b>种类与数量按 seed 抽</b>（种子 = <code>run_seed + 房 id</code>，同局同房可复现）'
           '</div>')

# ---- 表 A
out.append('<h2>表 A · 主路 13 房：怪物编成 × 掉落池（实测）</h2>')
out.append('<table><thead><tr>'
           '<th class="c">序</th><th>房号</th><th>内容类型</th><th>房型（示例版图）</th>'
           '<th class="c">波次</th><th>每波编成（种类池 → 抽几种 → 总量）</th>'
           '<th class="c">期望只数</th><th class="c">层档</th><th>怪物掉落池</th><th>备注</th>'
           '</tr></thead><tbody>')
for seq, rid, ctype, tmpl, waves, comp, exp_n, flv, table_name, note in ROOMS:
    out.append(
        '<tr><td class="c">%s</td><td><code>%s</code></td><td>%s</td><td>%s</td>'
        '<td class="c">%s</td><td>%s</td><td class="num">%s</td><td class="c">%s</td>'
        '<td>%s</td><td>%s</td></tr>' % (
            seq, esc(rid), esc(ctype), esc(tmpl), esc(waves), comp, esc(exp_n),
            ("lv" + flv) if waves != "—" else ("lv" + flv),
            ("<code>%s</code>" % esc(table_name)) if table_name else "—",
            esc(note) if note else "",
        )
    )
out.append('</tbody></table>')
out.append('<div class="meta"><b>层档（floor_level）怎么来的：</b>'
           '按房间在运行时记录表的<b>序号</b>线性折算 —— '
           '<code>floor_level = clamp(int(idx / (记录数−1) × 3), 0, 3)</code>，记录数 = 13 ⇒ 序列 '
           '<code>[0,0,0,0,1,1,1,1,2,2,2,2,3]</code>。'
           'lv0 → <code>loot_floor_1_2</code>；lv1 → <code>loot_floor_3_4</code>；'
           'lv2 → <code>loot_floor_5</code>；lv3 → <code>loot_abyss</code>。'
           '⚠ <b>它跟「越深越难」无关，只是"第几间房"</b> —— 前 3 间内容房吃浅层池、中间 4 间吃中层池、后 3 间吃深层池。</div>')

# ---- 表 B
out.append('<h2>表 B · 怪物名册与实跑数值（floor = 1，主题已乘 0.95）</h2>')
out.append('<table><thead><tr><th>内部 id</th><th>名称</th>'
           '<th class="c">基础 HP</th><th class="c">实跑 HP</th>'
           '<th class="c">基础伤害</th><th class="c">实跑伤害</th>'
           '<th class="c">速度</th><th class="c">行为</th><th>出场房</th></tr></thead><tbody>')
for mid, name, hp0, hp, dmg0, dmg, spd, ai, rooms in MONSTERS:
    out.append('<tr><td><code>%s</code></td><td>边境%s</td>'
               '<td class="num">%s</td><td class="num"><b>%s</b></td>'
               '<td class="num">%s</td><td class="num"><b>%s</b></td>'
               '<td class="num">%s</td><td class="c">%s</td><td>%s</td></tr>' % (
                   mid, esc(name), hp0, hp, dmg0, dmg, spd, esc(ai), esc(rooms)))
out.append('</tbody></table>')
out.append('<div class="ok"><b>本关只用 6 种普通怪，没有精英怪、没有 Boss。</b>'
           '数值一律由引擎出（<code>基础值 × 楼层缩放 × 主题倍率</code>，整数截断），设计源只写"要谁、几只"。'
           '其中「蜂巢怪」伤害为 0 —— 它靠召唤，本体不造成直接伤害。</div>')

# ---- 表 C
out.append('<h2>表 C · 单只怪死亡时的掉落规则</h2>')
out.append('<table><thead><tr><th>掉落项</th><th class="c">概率</th><th>内容</th></tr></thead><tbody>')
for item, chance, desc in KILL_RULES:
    out.append('<tr><td>%s</td><td class="c"><b>%s</b></td><td>%s</td></tr>' % (esc(item), chance, desc))
out.append('</tbody></table>')
out.append('<div class="meta"><b>按期望估算：</b>52.5 只怪 × 3 魂 ≈ <b>158 魂</b>；'
           '物品落地 ≈ 52.5 × 26% ≈ <b>14 件</b>；备弹 ≈ 52.5 × 34% ≈ <b>18 包</b>（每包 3–8 发）。'
           '普通怪掉落<b>每只至多 1 件非货币物品</b>。</div>')

# ---- 表 D
out.append('<h2>表 D · 搜刮容器（SCAVENGE / STORAGE 房的主要收益）</h2>')
out.append('<table><thead><tr><th>项</th><th>口径</th></tr></thead><tbody>')
for k, v in CONTAINER_RULES:
    out.append('<tr><td style="white-space:nowrap">%s</td><td>%s</td></tr>' % (esc(k), v))
out.append('</tbody></table>')
out.append('<div class="meta"><b>容器池名恒为 <code>scavenge_floor_1</code></b> —— '
           '表名 <code>scavenge_floor_%d % min(5, maxi(1, difficulty_rank))</code>，本关 difficulty_rank = 1。'
           '⚠ 本关 3 间 SCAVENGE 房 + 1 间 STORAGE 房 = 容器主要来源；'
           'Boss 房 <code>prop_count = 0</code>，<b>没有任何容器</b>。</div>')

# ---- 表 E
out.append('<h2>表 E · 掉落池总览（池 ↔ 消费点）</h2>')
out.append('<table><thead><tr><th>池 ID</th><th>中文名</th><th>用途</th>'
           '<th class="c">件数</th><th class="c">权重合计</th><th>本关命中房</th></tr></thead><tbody>')
for key in POOL_ORDER:
    name, usage, rooms = POOLS_META[key]
    p = pools[key]
    hit = "" if "（" in rooms else ""
    cls = ' style="color:#9ca3af"' if "（" in rooms else ""
    out.append('<tr%s><td><code>%s</code></td><td>%s</td><td>%s</td>'
               '<td class="num">%d</td><td class="num">%.2f</td><td>%s</td></tr>' % (
                   cls, key, esc(name), esc(usage), p["count"], p["total"], esc(rooms)))
out.append('</tbody></table>')

# ---- 表 F：池明细
out.append('<h2>表 F · 掉落池逐件明细（权重 = 相对抽取权重；占比 = 权重 / 池合计）</h2>')
for key in POOL_ORDER:
    name, usage, rooms = POOLS_META[key]
    p = pools[key]
    rows = sorted(p["rows"], key=lambda r: -r["weight"])
    out.append('<div class="pool"><h3><code>%s</code> · %s　<span>%d 件 / 权重合计 %.2f · %s</span></h3>' % (
        key, esc(name), p["count"], p["total"], esc(rooms)))
    out.append('<table><thead><tr><th>物品</th><th>类型</th><th>子类</th><th class="c">稀有度</th>'
               '<th class="c">Tier 门槛</th><th class="c">售价</th><th class="c">权重</th>'
               '<th class="c">占比</th><th style="width:150px">权重条</th></tr></thead><tbody>')
    maxw = max([r["weight"] for r in rows] or [1.0])
    for r in rows:
        color = RARITY_COLOR.get(r["rarity"], "#6b7280")
        bar_w = max(2, int(r["weight"] / maxw * 130))
        out.append('<tr><td>%s</td><td>%s</td><td>%s</td>'
                   '<td class="c" style="color:%s">%s</td>'
                   '<td class="c">%s</td><td class="num">%s</td>'
                   '<td class="num">%.2f</td><td class="num">%.2f%%</td>'
                   '<td><span class="bar" style="width:%dpx"></span></td></tr>' % (
                       esc(r["name"]), esc(r["type"]), esc(r["subtype"] or "—"),
                       color, esc(RARITY_ZH.get(r["rarity"], r["rarity"])),
                       esc(r["tier"]), esc(r["price"]), r["weight"], r["pct"], bar_w))
    out.append('</tbody></table></div>')

# ---- 风险与结论
out.append('<h2>表 G · 三个需要主人裁决的口径问题</h2>')
out.append('<table><thead><tr><th class="c">#</th><th>问题</th><th>证据</th><th>影响</th></tr></thead><tbody>')
out.append('<tr><td class="c">1</td>'
           '<td><b>Boss 房没有 Boss</b> —— 全关没有终局战斗</td>'
           '<td>设计源未写 <code>boss_content_id</code>；按层号指派的口径 '
           '<code>BossContentCatalog</code> 只登记 <b>95 / 90 / 85</b> 三层，'
           '而本关 <code>floor_number = 0</code> ⇒ <code>resolve_profile("", 0)</code> 返回空</td>'
           '<td>进 Boss 房只看到「首领房未指派首领 · 区域已放行」；'
           '<code>boss_floor_1</code> 掉落池<b>永不消费</b>；连精英随从也不刷（随 Boss 一起条件化）</td></tr>')
out.append('<tr><td class="c">2</td>'
           '<td><b>设计页的怪物中文名与代码不一致</b></td>'
           '<td>设计页 §4.5 写 <code>melee_chaser</code> = 「小菌猪」，'
           '代码 <code>BASE_ENEMY_TYPES</code> 里是 <b>「小僵尸」</b>（运行时显示「边境小僵尸」）</td>'
           '<td>只影响文档可读性，不影响运行；但同一只怪两个代号违反「一物一名」</td></tr>')
out.append('<tr><td class="c">3</td>'
           '<td><b>主题怪物池被设计源架空</b></td>'
           '<td>主题 <code>enemy_pool = [小僵尸, 小僵尸, 孢子射手, 炸弹果]</code>，'
           '但 9 间房被设计源 <code>enemy_spawn_plan</code> 接管，公式路径的池与权重<b>完全不参与</b></td>'
           '<td>设计源的池里出现了主题池没有的<b>壳甲卫兵 / 蜂巢怪 / 地刺虫</b> —— '
           '这是设计源有意的（不然编成没变化），但改主题时别指望能影响本关刷怪</td></tr>')
out.append('</tbody></table>')

# ---- 表 H / I：刷怪落点诊断（2026-09-25 追加）
out.append('<h2>表 H · 刷怪落点：为什么怪总出现在每间房的四个角</h2>')
out.append('<div class="meta"><b>结论：三层机制叠加的必然结果 —— 不是随机，也不是偶发 bug，'
           '但在「矩形房 + tower_cell」这个组合下会退化成"永远四角"。</b><br>'
           '① <b>落点数量由 <code>size_class</code> 定</b>：<code>tower_cell</code> ⇒ <b>4 个</b>，'
           '远征01 十三间房<b>全是 <code>tower_cell</code></b>（<code>small</code> 3 / <code>medium</code> 5 / '
           '<code>large</code> 7 / 其他 9）。<br>'
           '② <b>有授权布局地砖的房走 <code>_pick_ring_spawn_points()</code></b>：'
           '把 360° 均分 4 个扇区，<b>每扇区取「离房心最远」的格心</b>；矩形房里"离房心最远"'
           '在数学上就是四个角上的格心。<br>'
           '③ 没有地砖槽的房（如 <code>start</code> 安全房）走 fallback：'
           '环状等角 + <code>r = 尺寸 × 0.23</code> + ±0.24 rad 抖动 ⇒ 落在<b>内圈</b>而不是角。</div>')
out.append('<table><thead><tr><th>房</th><th class="c">尺寸</th><th class="c">地砖格数</th>'
           '<th>4 个落点（房间局部 x, z）</th><th class="c">到房心 r</th>'
           '<th class="c">离最近墙内面</th><th>判读</th></tr></thead><tbody>')
SPAWN_ROWS = [
    ("start", "15×15", "0", "环状：(3.42,0.48) (0.70,3.38) (−3.38,0.71) (−0.44,−3.42)",
     "3.45", "5.92", "⚠ 无地砖 ⇒ fallback 分支：内圈四点，<b>不是角</b>（r = 15×0.23 = 3.45）"),
    ("room_01", "25×25", "25", "(−10,−10) (10,−10) (10,10) (−10,10)", "14.14", "2.50",
     "四角（= 半宽 − 2.5）"),
    ("room_02", "25×25", "25", "同上", "14.14", "2.50", "四角"),
    ("room_03", "45×40", "72", "(−20,−17.5) (20,−17.5) (20,17.5) (−20,17.5)", "26.58", "2.50", "四角"),
    ("room_04", "40×30", "39", "(−17.5,−12.5) (17.5,−12.5) (17.5,7.5) (−17.5,2.5)",
     "21.51 / 21.51 / 19.04 / 17.68", "2.50",
     "⭐ <b>u_turn 凹口房：后两点被凹口顶到边上，不是角</b> ⇒ 机制在非矩形房是<b>对的</b>"),
    ("room_05", "25×25", "25", "同上（四角）", "14.14", "2.50", "四角"),
    ("room_06", "30×40", "48", "(−12.5,−17.5) (12.5,−17.5) (12.5,17.5) (−12.5,17.5)", "21.51", "2.50", "四角"),
    ("room_07", "25×25", "25", "四角", "14.14", "2.50", "四角"),
    ("room_08", "45×40", "72", "(−20,−17.5) (20,−17.5) (20,17.5) (−20,17.5)", "26.58", "2.50", "四角"),
    ("room_09", "25×25", "25", "四角（本房不刷怪）", "14.14", "2.50", "四角"),
    ("room_10", "30×60", "48", "(−12.5,−27.5) (12.5,−27.5) (12.5,27.5) (−12.5,27.5)", "30.21", "2.50",
     "四角；30×60 房中央 25×55 完全无落点"),
    ("boss", "50×40", "80", "(−22.5,−17.5) (22.5,−17.5) (22.5,17.5) (−22.5,17.5)", "28.50", "2.50", "四角"),
    ("extraction", "25×25", "25", "四角（本房不刷怪）", "14.14", "2.50", "四角"),
]
for rid, dims, tiles, pts, r, gap, note in SPAWN_ROWS:
    out.append('<tr><td><code>%s</code></td><td class="c">%s</td><td class="c">%s</td>'
               '<td>%s</td><td class="c">%s</td><td class="c">%s</td><td>%s</td></tr>' % (
                   rid, dims, tiles, esc(pts), r, gap, note))
out.append('</tbody></table>')
out.append('<div class="warn"><b>为什么是「离房心最远」这么挑：</b>'
           '注释写明目的是「怪贴房间外圈出现、彼此不重叠」，并且强制候选点必须落在<b>真有地砖的格心</b>上 —— '
           '<code>point_in_polygon</code> 在摆位阶段已经把凹口方向的砖剔掉，所以非矩形房不会刷到墙外或邻房。'
           '这个设计在 L / U / 工字房里是<b>正确且必要</b>的（上表 room_04 就是证据）。'
           '问题只出在：<b>矩形房里"每扇区最远"必然等于"角点"</b>。</div>')

out.append('<h3>表 I · 超量退让：第 5 只怪开始才往房间里走</h3>')
out.append('<div class="meta">环形点位只有 4 个，而设计源允许一波 5–8 只 ⇒ '
           '<code>spawn_point_for_index()</code> 按「每超一轮转 0.37 rad + 半径 ×0.83」逐层退让。'
           '以 <code>room_01</code>（25×25，四角 r=14.14）为例：</div>')
out.append('<table><thead><tr><th class="c">索引</th><th>落点（局部 x, z）</th>'
           '<th class="c">层</th><th>说明</th></tr></thead><tbody>')
for idx, pt, layer, note in [
    ("0–3", "(−10,−10) (10,−10) (10,10) (−10,10)", "第 0 层", "四角，r = 14.14"),
    ("4–7", "(−10.7,−4.7) (4.7,−10.7) (10.7,4.7) (−4.7,10.7)", "第 1 层", "转角 0.37 rad、半径 ×0.83 ⇒ 滑向墙中段"),
    ("8–11", "(−9.3,−0.4) (0.4,−9.3) (9.3,0.4) (−0.4,9.3)", "第 2 层", "转角 0.74 rad、半径 ×0.66 ⇒ 贴到墙中点"),
    ("12+", "继续每层 ×0.83（触底 0.12）", "第 3 层起", "半径触底后只靠角度区分，仍在最外圈附近"),
]:
    out.append('<tr><td class="c">%s</td><td>%s</td><td class="c">%s</td><td>%s</td></tr>' % (
        idx, esc(pt), layer, esc(note)))
out.append('</tbody></table>')

out.append('<h3>表 J · 后果与三种修法</h3>')
out.append('<table><thead><tr><th class="c">#</th><th>现象 / 代价</th><th>说明</th></tr></thead><tbody>')
for n, bad, why in [
    ("1", "单波 3 只 ⇒ 只占 3 个角，第 4 角空着", "按索引顺序取 idx0..2 ⇒ 每局同一房永远是同三角，分布不对称、也无随机性"),
    ("2", "怪全部贴脸开场", "门开在墙中，四角是房间里离门最远的点，但也是离玩家更近的『两侧包夹位』⇒ 没有纵深推进"),
    ("3", "房间中央永远空", "30×60 的 room_10 落点全在角上，中央 25×55 无怪出没"),
    ("4", "一波 ≤4 只时落点完全确定", "无随机 ⇒ 重复刷同一房时每局开场画面一模一样"),
    ("5", "⚠ 潜在穿模风险", "落点离墙内面恒 2.5 m，与随机家具（<code>x = ±尺寸×0.34</code> 一带）擦肩；"
          "落点算法<b>不做碰撞/家具检测</b>，家具若随机到角落就会与怪重叠"),
]:
    out.append('<tr><td class="c">%s</td><td>%s</td><td>%s</td></tr>' % (n, bad, why))
out.append('</tbody></table>')
out.append('<table><thead><tr><th class="c">方案</th><th>改法（含公式）</th><th class="c">影响面</th><th>代价</th></tr></thead><tbody>')
for plan, how, scope, cost in [
    ("A · 角点内缩<br><span class='tag'>最小改动</span>",
     "在 <code>_pick_ring_spawn_points()</code> 选出点后朝房心内缩：<code>p = 房心 + (p − 房心) × (1 − t)</code>，"
     "取 <code>t = 0.22</code> ⇒ 25×25 的四角从 (±10,±10) 收到 (±7.8,±7.8)",
     "98F 区块00 + 远征01 全房", "四角仍是四角，只是不贴角；不解决「3 只 = 三角」与「中央空」"),
    ("B · 环带取点<br><span class='tag'>推荐</span>",
     "把「每扇区取最远」改成「取落在目标环带内的格」：<code>target_r = 0.78 × min(半宽, 半深)</code>、"
     "带区间 <code>[0.75×target_r, 1.25×target_r]</code>；带内取最远，无格可取再退回全局最远。"
     "非矩形房的凹口方向本来就没有中距格 ⇒ 行为自动不变",
     "98F 区块00 + 远征01 全房", "需要跑一次 98F 回归对照（区块00 也在用同一函数）"),
    ("C · 设计源驱动<br><span class='tag'>最干净</span>",
     "新增房间级字段 <code>spawn_ring_inset_m</code> / <code>spawn_point_count</code>（设计源 L2 可写），"
     "缺省时行为逐字不变 ⇒ 只给远征01 单独声明",
     "仅声明的房", "要扩 schema，<b>并同步 <code>LevelPlanValidator</code> 与校验脚本</b>；改 schema 前需你裁定"),
]:
    out.append('<tr><td>%s</td><td>%s</td><td class="c">%s</td><td>%s</td></tr>' % (plan, how, scope, cost))
out.append('</tbody></table>')
out.append('<div class="warn"><b>我没动代码。</b>这三个方案都落在共用函数 '
           '<code>DungeonRoom3D._pick_ring_spawn_points()</code> 上，'
           '而它<b>同时服务塔楼 98F 区块00（主人的办公室）与远征01</b> —— '
           '属于跨关卡玩法口径，等你定方案再改。</div>')

out.append('<div class="foot">'
           '验签路径：<code>floor_00.json</code>（编成）· <code>MonsterInjector.BASE_ENEMY_TYPES</code> / '
           '<code>DROP_*</code> 常量（数值与掉落概率）· <code>Dungeon3D._spawn_room_enemies</code>（层档折算）· '
           '<code>Dungeon3D._on_prop_searched</code> 与 <code>DungeonRoom3D</code> 器具生成（容器）· '
           '<code>ItemRegistry</code> 的 <code>floor_loot_weights</code>（池明细）· '
           '<code>DungeonRoom3D._build_spawn_points</code> / <code>_pick_ring_spawn_points</code> / '
           '<code>spawn_point_for_index</code>（刷怪落点，表 H/I 实测自 '
           '<code>_scratch/lootprobe/probe_spawn_points.tscn</code>）。'
           '设计意图见 <code>docs/v0.1/design/远征关卡01设计.md</code> §4.5。</div>')
out.append('</body></html>')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out))
print("OK ->", OUT)
print("size =", os.path.getsize(OUT))
