# -*- coding: utf-8 -*-
"""生成《远征关卡01 · 怪物掉落列表》Markdown 与 HTML。

数据源（全部为实测，无手工填入的数值）：
  ① `_scratch/lootprobe/exp01_drops_out.txt`
     —— 探针 `probe_exp01_drops.gd` 在 Godot 4.6.3 headless 下的运行时真值
        （seed 77001199；逐房调 Dungeon3D._spawn_box_waves；掉落规格调 MonsterInjector.drop_spec_for）
  ② `_scratch/lootprobe/loot_pools_dump_20260926.tsv`
     —— 探针 `dump_loot.gd` 从 ItemRegistry 导出的掉落池成员与权重

不复刻任何公式：房间 floor_level 由探针打印（探针内以 `plan` 记录 index 复算，仅供对照），
怪物编成与池名一律取自运行时对象。
"""
import html
import os
import json
import collections

BASE = os.path.dirname(os.path.abspath(__file__))
PROBE = os.path.join(BASE, "exp01_drops_out.txt")
POOLS_TSV = os.path.join(BASE, "loot_pools_dump_20260926.tsv")
FLOOR_JSON = os.path.abspath(os.path.join(
    BASE, "..", "..", "source", "art", "whitebox", "tower_zones",
    "expedition_01", "v001", "data", "floors", "floor_00.json",
))
OUT_DIR = os.path.abspath(os.path.join(BASE, "..", "..", "outputs"))
OUT_MD = os.path.join(OUT_DIR, "远征关卡01_怪物掉落列表.md")
OUT_HTML = os.path.join(OUT_DIR, "远征关卡01_怪物掉落列表.html")

# 设计源房表（只取房型模板与尺寸，用于把「房型」列填成真实模板名）
with open(FLOOR_JSON, "r", encoding="utf-8") as _handle:
    _plan = json.load(_handle)
TEMPLATE_BY_KEY = {}
for _spec in _plan.get("rooms", []):
    _size = _spec.get("size_m", [])
    _dim = "%g×%g m" % (float(_size[0]), float(_size[1])) if len(_size) == 2 else ""
    TEMPLATE_BY_KEY[str(_spec.get("key", ""))] = "%s %s" % (
        str(_spec.get("template_id", "")), _dim,
    )


def template_of(room_id):
    key = "entry" if room_id == "start" else room_id
    return TEMPLATE_BY_KEY.get(key, "—")


RARITY_CN = {
    "common": "普通", "uncommon": "罕见", "rare": "稀有", "epic": "史诗",
}
TYPE_CN = {
    "weapon": "枪械/近战", "module": "子弹模块", "attachment": "配件",
    "consumable": "消耗品", "equipment": "背包", "blueprint": "蓝图碎片", "key": "钥匙",
}
BOX_CN = {
    "box_room_spread": "混编主盒",
    "box_corner_ambush": "角落包夹",
    "box_corridor_column": "窄长纵列",
    "box_wall_arc": "贴墙远程",
    "box_center_elite": "精英点",
    "box_boss_arena": "Boss 台",
}
ENEMY_CN = {
    "melee_chaser": "小僵尸", "ranged_caster": "孢子射手", "summoner": "蜂巢怪",
    "shielded": "壳甲卫兵", "exploder": "炸弹果", "ambusher": "地刺虫", "boss": "首领",
}
ROOM_CN = {
    "start": "入口安全屋", "room_01": "01 号房", "room_02": "02 号房", "room_03": "03 号房",
    "room_04": "04 号房", "room_05": "05 号房", "room_06": "06 号房", "room_07": "07 号房",
    "room_08": "08 号房", "room_09": "09 号房", "room_10": "10 号房",
    "boss": "Boss 竞技场", "extraction": "撤离屋",
}


# --------------------------------------------------------------- 解析探针输出
def load_probe():
    meta = {}
    records = []
    rooms = []
    waves = []
    specs = []
    boss = {}
    section = ""
    with open(PROBE, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            if line.startswith("#"):
                section = line
                continue
            parts = line.split("\t")
            tag = parts[0]
            if tag == "LEVEL":
                meta["level"] = parts[1]
                meta["theme"] = parts[2].split("=", 1)[1]
                meta["seed"] = parts[3].split("=", 1)[1]
                meta["floor"] = parts[4].split("=", 1)[1]
                meta["records"] = parts[5].split("=", 1)[1]
            elif tag == "REC":
                if not parts[1].isdigit():
                    continue  # 表头行
                records.append({"idx": int(parts[1]), "id": parts[2], "type": parts[3],
                                "role": parts[4], "floor_level": int(parts[5]), "pool": parts[6]})
            elif tag == "ROOM":
                if not parts[4].isdigit():
                    continue  # 表头行
                rooms.append({"id": parts[1], "type": parts[2], "size": parts[3],
                              "idx": int(parts[4]), "floor_level": int(parts[5]),
                              "placements": int(parts[6]), "waves": int(parts[7]),
                              "enemies": int(parts[8])})
            elif tag == "PLACE":
                rooms_by_id.setdefault(parts[1], []).append(parts[2])
            elif tag == "WAVE":
                if not parts[3].isdigit():
                    continue  # 表头行
                waves.append({
                    "room": parts[1], "room_type": parts[2], "floor_level": int(parts[3]),
                    "wave": int(parts[4]), "enemy": parts[7], "name": parts[8],
                    "tier": parts[9], "pool": parts[10], "hp": int(parts[11]),
                    "damage": int(parts[12]), "modifier": parts[13], "pos_ok": parts[14],
                })
            elif tag == "SPEC":
                if not parts[3].isdigit():
                    continue  # 表头行
                specs.append({"monster": parts[1], "tier": parts[2], "floor_level": int(parts[3]),
                              "pool": parts[4], "item_chance": parts[5], "ammo_chance": parts[6],
                              "ammo_range": parts[7], "currency": parts[8]})
            elif tag == "BOSS":
                boss = {"content_id": parts[1].split("=", 1)[1], "arena": parts[2].split("=", 1)[1]}
    return meta, records, rooms, waves, specs, boss


rooms_by_id = {}
meta, records, rooms, waves, specs, boss = load_probe()

# 每房盒子里出现过的盒型（设计源顺序）
boxes_by_room = collections.OrderedDict()
for rid, raw_json in rooms_by_id.items():
    ids = []
    for chunk in raw_json:
        # {"box":"box_xxx","center_m":[...]}
        marker = '"box":"'
        start = chunk.find(marker)
        if start < 0:
            continue
        start += len(marker)
        end = chunk.find('"', start)
        ids.append(chunk[start:end])
    boxes_by_room[rid] = ids

# 房间 → 怪种计数 / 波次结构 / 池
per_room = collections.OrderedDict()
for room in rooms:
    per_room[room["id"]] = {"room": room, "counts": collections.Counter(),
                            "pools": set(), "wave_map": collections.OrderedDict()}
for w in waves:
    bucket = per_room[w["room"]]
    bucket["counts"][w["enemy"]] += 1
    bucket["pools"].add(w["pool"])
    bucket["wave_map"].setdefault(w["wave"], collections.Counter())[w["enemy"]] += 1

# 怪种名册（实测数值）
roster = collections.OrderedDict()
for w in waves:
    key = w["enemy"]
    if key not in roster:
        roster[key] = {"name": w["name"], "hp": w["hp"], "damage": w["damage"],
                       "rooms": set(), "count": 0}
    roster[key]["rooms"].add(w["room"])
    roster[key]["count"] += 1

total_enemies = sum(int(r["enemies"]) for r in rooms)
total_elite = sum(1 for w in waves if w["tier"] == "elite")
total_boss = sum(1 for w in waves if w["tier"] == "boss")

# --------------------------------------------------------------- 解析掉落池明细
pools = collections.OrderedDict()
with open(POOLS_TSV, "r", encoding="utf-8") as handle:
    for raw in handle:
        line = raw.rstrip("\n")
        if not line or line.startswith("Godot Engine"):
            continue
        parts = line.split("\t")
        if parts[0] == "##TOTAL":
            pools.setdefault(parts[1], {"rows": [], "total": 0.0})
            pools[parts[1]]["total"] = float(parts[3])
            continue
        if not parts[0].startswith(("loot_", "scavenge_floor_", "elite_floor_", "boss_floor_", "combat_")):
            continue
        pools.setdefault(parts[0], {"rows": [], "total": 0.0})
        pools[parts[0]]["rows"].append({
            "item_id": parts[1], "name": parts[2], "type": parts[3], "subtype": parts[4],
            "rarity": parts[5], "tier": parts[6], "price": parts[7],
            "category": parts[8], "weight": float(parts[9]), "pct": float(parts[10]),
        })

USED_POOLS = ["loot_floor_1_2", "loot_floor_3_4", "loot_floor_5",
              "elite_floor_1", "boss_floor_1", "scavenge_floor_1", "loot_abyss"]

# --------------------------------------------------------------- Markdown
def md_room_table():
    lines = ["| # | 房间 | 房型（设计源模板） | 内容类型 | floor_level | 怪物池 | 波次 | 只数 | 盒型 |",
             "|---|---|---|---|---|---|---|---|---|"]
    order = sorted(rooms, key=lambda r: r["idx"])
    num = 0
    for room in order:
        bucket = per_room[room["id"]]
        if room["enemies"] > 0:
            num += 1
            idx_txt = str(num)
        else:
            idx_txt = "—"
        pools_txt = " / ".join(sorted(bucket["pools"])) if bucket["pools"] else "—"
        box_txt = "、".join(BOX_CN.get(b, b) for b in boxes_by_room.get(room["id"], [])) or "—"
        lines.append("| %s | %s | %s | %s | %d | %s | %d | %d | %s |" % (
            idx_txt, ROOM_CN.get(room["id"], room["id"]), template_of(room["id"]),
            room["type"], room["floor_level"], pools_txt, room["waves"],
            room["enemies"], box_txt,
        ))
    return "\n".join(lines)


def md_roster():
    lines = ["| 怪物 | 内部 id | 实测 HP | 实测伤害 | 出场房 | 出现只数 |",
             "|---|---|---|---|---|---|"]
    for key, info in roster.items():
        lines.append("| %s | `%s` | %d | %d | %s | %d |" % (
            info["name"], key, info["hp"], info["damage"],
            "/".join(sorted(info["rooms"])), info["count"],
        ))
    if not roster:
        lines.append("| — | — | — | — | — | 0 |")
    return "\n".join(lines)


def md_pool(pool_id):
    data = pools.get(pool_id)
    if not data or not data["rows"]:
        return "_（无成员）_\n"
    lines = ["| 物品 | item_id | 类别 | 稀有度 | 权重 | 池内占比 |",
             "|---|---|---|---|---|---|"]
    for row in sorted(data["rows"], key=lambda r: -r["weight"]):
        lines.append("| %s | `%s` | %s | %s | %.2f | %.2f%% |" % (
            row["name"], row["item_id"], TYPE_CN.get(row["type"], row["type"]),
            RARITY_CN.get(row["rarity"], row["rarity"]), row["weight"], row["pct"],
        ))
    lines.append("| **合计** | | | | **%.2f** | 100%% |" % data["total"])
    return "\n".join(lines) + "\n"


def md_wave_detail():
    lines = []
    for room in sorted(rooms, key=lambda r: r["idx"]):
        bucket = per_room[room["id"]]
        if not bucket["wave_map"]:
            continue
        lines.append("### %s（`%s` · %s · floor_level=%d）\n" % (
            ROOM_CN.get(room["id"], room["id"]), room["id"], room["type"], room["floor_level"],
        ))
        for wave_index in sorted(bucket["wave_map"].keys()):
            kinds = bucket["wave_map"][wave_index]
            parts = []
            for enemy, count in kinds.items():
                parts.append("%s×%d" % (roster.get(enemy, {}).get("name", enemy), count))
            lines.append("- **W%d**：%s" % (wave_index + 1, "、".join(parts)))
        lines.append("")
    return "\n".join(lines)


def build_md():
    head = """# 远征关卡01 · 怪物掉落列表

> 数据源：Godot 4.6.3 headless 运行时实测（`run_seed=77001199`、`test_mode=1`）。
> 探针：`_scratch/lootprobe/probe_exp01_drops.gd`（逐房调 `Dungeon3D._spawn_box_waves` 拿真实波次；
> 掉落规格调 `MonsterInjector.drop_spec_for`）、`dump_loot.gd`（`ItemRegistry` 导出池成员）。
> 未改动任何生产代码 / 设计源 / 数值。
> 生成日期：2026-09-26

## 0. 一句话结论

远征01 的怪物掉落**只来自触发器刷怪盒**（`content_type` 不再参与编成）：10 间内容房按主路序号落在
三档普通怪池上，`floor_level 0 → loot_floor_1_2`、`1 → loot_floor_3_4`、`2 → loot_floor_5`；
**本关实测只有普通怪，精英池与首领池一个都没触发**（见 §6）。

| 项 | 实测值 |
|---|---|
| 关卡层数 / 房间总数 | 单层 · 13 房（entry + room_01…10 + boss + extraction） |
| 内容房 | 10 间主路房（全部摆盒刷怪）+ Boss 房 |
| 刷怪来源 | 触发器刷怪盒（6 种盒型），无公式散怪 |
| 本局怪物总数 | **%d 只**（精英 %d · 首领 %d） |
| 普通怪掉落池 | `loot_floor_1_2` / `loot_floor_3_4` / `loot_floor_5` |
| 容器搜索池 | `scavenge_floor_1`（全关恒此一档） |
""" % (total_enemies, total_elite, total_boss)

    body = [head]
    body.append("\n## 1. 逐房编成与掉落池\n")
    body.append(md_room_table())

    body.append("\n## 2. 怪物名册（实测数值，已含主题倍率）\n")
    body.append("主题 `iron_frontier`（冷钢边境），`difficulty_rank=1` ⇒ `floor=1`。"
                "HP / 伤害已含主题倍率 `hp_multiplier=0.95`、`damage_multiplier=0.95`。\n")
    body.append(md_roster())

    body.append("\n## 3. 逐波编成明细\n")
    body.append(md_wave_detail())

    body.append("\n## 4. 单只怪的掉落规则（`MonsterInjector.drop_spec_for`）\n")
    body.append("| 怪物 | 档位 | floor_level | 掉落池 | 出物品概率 | 备弹概率 | 备弹数量 | 魂 |")
    body.append("|---|---|---|---|---|---|---|---|")
    for spec in specs:
        body.append("| %s | %s | %d | `%s` | %s | %s | %s | %s |" % (
            ENEMY_CN.get(spec["monster"], spec["monster"]), spec["tier"], spec["floor_level"],
            spec["pool"], spec["item_chance"], spec["ammo_chance"], spec["ammo_range"],
            spec["currency"],
        ))

    body.append("""
三条规则（本关 `floor=1`）：

1. **出物品**：每次击杀按上表概率掷一次，命中则从该房对应池**按权重抽 1 件**（数量恒为 1；堆叠只发生在拾取入包后）。
2. **出备弹**：普通怪 34% 掉 `item_ammo_pack` 通用弹药 3–8 个；若池里已抽到同一物品，以整包数量**覆盖**该件而非多出一件。
3. **出魂**：必掉 `extraction_points = 2 + floor × 1` = **3**（本关 `floor=1`）。精英 / 首领的魂是总额（50+20·floor / 200+20·floor），本关不可达。
""")

    body.append("\n## 5. 掉落池明细\n")
    body.append("### 5.1 `loot_floor_1_2` — 浅层池（room_01 ~ room_03）\n")
    body.append(md_pool("loot_floor_1_2"))
    body.append("### 5.2 `loot_floor_3_4` — 中层池（room_04 ~ room_07）\n")
    body.append(md_pool("loot_floor_3_4"))
    body.append("### 5.3 `loot_floor_5` — 深层池（room_08 ~ room_10 与 Boss 房）\n")
    body.append(md_pool("loot_floor_5"))
    body.append("### 5.4 `scavenge_floor_1` — 容器搜索池（搜索类容器，非怪物掉落）\n")
    body.append(md_pool("scavenge_floor_1"))

    body.append("\n## 6. ⚠ 实测异常：精英与首领一个都没出\n")
    body.append("""设计源已在 **room_05 / room_07 / room_08 / room_10** 摆了 `box_center_elite`，
Boss 房摆了 `box_boss_arena`（内含 Boss×1 + 精英×2 + 蜂巢怪×1）。实测结果：

| 位置 | 盒子声明 | 实测实到 | 缺口 |
|---|---|---|---|
| room_05 / 07 / 08 / 10 | `box_center_elite` = 精英×1 + 小僵尸×1 | 只有小僵尸×1 | **精英缺 1**（每处） |
| boss 房 W1 | `box_boss_arena` = Boss×1 + 精英×2 + 蜂巢怪×1 | 只有蜂巢怪×1 | **Boss 缺 1、精英缺 2** |

根因（两条独立，均为静默返回空字典，不报错）：

1. **精英**：`EliteRosterService.select_and_reserve` → `EliteContentCatalog.get_deployable_for_floor(floor_number)`。
   当前名册里只有一条可部署精英（`eligible_floor_numbers=[98,97,96]`），其余条目全是 `DESIGN_ONLY` 且层号列表为空。
   远征的 `floor_number = maxi(1, difficulty_rank) = 1` ⇒ 名册无匹配 ⇒ 返回 `roster_exhausted_or_reserved` ⇒ 不出精英。
2. **首领**：`BossContentCatalog.resolve_profile("", floor_number)` → 名册 `CONTENT` 只注册了 **95 / 90 / 85** 三层。
   远征 Boss 房 `boss_content_id` 为空、`floor_number=1` ⇒ `get_for_floor(1)` 空 ⇒ 返回 `{}` ⇒ 按「没写 boss 就是没有 boss」静默空房。

⇒ 远征01 目前**实际能掉到的最高档池是 `loot_floor_5`**，`elite_floor_1` 与 `boss_floor_1` 两个已登记池在本关完全落不下去
（下附两者明细，供裁决时对照）。

### 6.1 `elite_floor_1` — 精英池（本关登记但不可达）

""" + md_pool("elite_floor_1"))
    body.append("### 6.2 `boss_floor_1` — 首领池（本关登记但不可达）\n")
    body.append(md_pool("boss_floor_1"))

    body.append("\n## 7. 其他掉落来源\n")
    body.append("""| 来源 | 口径 | 远征01 取值 |
|---|---|---|
| 容器搜索 | `scavenge_floor_%d`，`%d = min(5, maxi(1, difficulty_rank))` | 恒 `scavenge_floor_1` |
| 清房钥匙 | 走独立路径（`_ensure_room_key_reward`），不经怪物掉落池 | 每个敌对房 |
| 魂兜底 | 每次击杀追加 `2 + floor` | 3 |

## 8. 与旧表的口径差异（2026-09-22 版已作废）

| 项 | 旧（09-22） | 现（09-26 实测） |
|---|---|---|
| 编成来源 | `enemy_spawn_plan` 半钉死波次 + 房型公式 | **触发器刷怪盒**（`spawn_placements` + `encounter`） |
| 房间数 | 7 房 | **13 房**（10 内容房 + boss + entry + extraction） |
| 内容房类型 | 每局按种子洗牌 | **设计源钉死**（COMBAT / SCAVENGE / EVENT / STORAGE） |
| Boss | 无 | 摆了盒，但**仍出不来**（§6） |
| 怪种 | 3 种 | **5 种**（小僵尸 / 孢子射手 / 巢怪 / 壳甲卫兵 / 炸弹果） |

## 9. 复现命令

```bash
# 1) 资源导入（独享 ASCII APPDATA）
export APPDATA='C:\\tmp\\ss2_appdata_probe'
cd ShellStorm2
"I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --import

# 2) 逐房刷怪与掉落规格实测
"I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe" --headless --path . \\
  res://_scratch/lootprobe/probe_exp01_drops.tscn      # 输出 _scratch/lootprobe/exp01_drops_out.txt

# 3) 掉落池成员导出
"I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe" --headless --path . \\
  --script res://_scratch/lootprobe/dump_loot.gd
```

## 10. 为什么这份表出自「运行时实测」而不是「设计文档」

（应「为什么不是从关卡的生成代码和设计文档里找」补写。）

### 10.1 真源链路（四方对照，实测核查）

| 层 | 载体 | 里面有掉落数值吗 |
|---|---|---|
| 玩法设计主文档 | `docs/v0.1/design/战斗奖励与物品流转设计.md`（r1 · 2026-09-24） | ❌ 只写规则与验收意图；**明文**「数值和具体内容以**内容数据库**为准」 |
| 关卡设计源（数据） | `level_plan.json` / `floor_00.json` | ❌ 只有几何、拓扑、房型池、刷怪盒 —— **一个掉落字段都没有** |
| 关卡设计文档 | `docs/v0.1/design/远征关卡01设计.md` | ❌ 全文唯一含「掉落」的一处是「`Dungeon3D` 不改变…**掉落数值**」＝免责声明，不是数值 |
| 内容数据库 | `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx` → `掉落物品` sheet | ⚠️ **物品侧视图**（按物品列「产出位置/权重」，如 `boss_floor_1×3；…`）；**没有「远征关卡01」这一行**。且该 sheet 第 13 列「**事实源**」逐行写的就是 `src/base/ItemRegistry.gd` |
| **运行时真源** | `src/base/ItemRegistry.gd`（`floor_loot_weights`）＋ `src/map/MonsterInjector.gd`（池选择与掉落常量）＋ `src/world3d/Dungeon3D.gd`（`floor_level` 公式） | ✅ **数值唯一真源在此（代码）** |

⇒ 不是「舍文档而取代码」，而是**这条链的终点本来就是代码**：设计文档把数值委派给内容数据库，
内容数据库又把「事实源」指回 `ItemRegistry.gd`。闭环落点 ＝ 代码。

### 10.2 那几份「掉落表设计文档」为什么没采用

2026-09-22 确有掉落设计文档，其中 `怪物掉落表_地图x怪物_设计定稿v2.md` 自称**设计定稿**，
形态正是「关卡ID × 怪物ID × 物品ID × 概率 × 权重 × 数量」总表（并附 `.xlsx` / `.csv` 示例）。
但实测其**施工清单逐项未落地**：

| 施工清单项 | 应为 | 实测 |
|---|---|---|
| 第 4 项 | 新 `src/rewards/MonsterDropTable.gd` | ❌ **文件不存在**（该目录只有 RewardPoolRegistry / RewardService / RewardSink / RewardSpec / RuntimeRewardCoordinator） |
| 第 2 项 | `level_plan.json` 顶层 `monster_drop_table` | ❌ **不存在**（顶层只有 schema / level_id / site / core / floors / room_templates / generation_policy / provenance 等） |
| 第 6 项 | `ItemRegistry` 加 6 个 `loot_monster_<type>` 池 | ❌ **0 个**（运行时 16 个池键全是旧的 `loot_floor_*` / `scavenge_floor_*` / `elite_floor_*` / `boss_floor_*`） |
| 全仓检索 | `monster_drop_table` / `MonsterDropTable` / `loot_monster_` | ❌ `src/` 下 **0 命中** |

文档自身状态也是「**待你点头（仅 1 项：表格载体）**」（同批 `掉落绑怪物_每怪独立池改造提案.md`
状态为「**待业主确认**」）。

⇒ **该改造从未落地**，运行时仍走旧口径 `MonsterInjector.get_loot_table_for_level(floor_level)`。
若照那份「定稿」出表，会得到一份**游戏里并不存在的掉落表**（每怪独立池 `loot_monster_*`）。

### 10.3 那运行时实测多测了什么

代码＋数据给得出「**应该**掉什么」，给不出下面三件 —— 而这三件恰好决定表对不对：

1. **每波实际出几只** —— `_roll_box_count()` 是按种子在盒容量内掷的随机数；
2. **声明了却出不来** —— §6 的精英 / 首领：数据文件明明写着 `elite×1`、`boss×1`，
   **只读数据必然误报**（会声称 `elite_floor_1` / `boss_floor_1` 可达）；
3. **盒的落地位置与容量** —— `_resolve_landing_box()` 在房型不符时会平移盒位，容量还取决于家具碰撞。

本表口径：**静态读代码与数据定「规则与映射」，运行时探针定「实际编成与数量」，两者对账**。
同方法先例是 `outputs/远征关卡01_掉落表与产出物设计核查.md`（2026-09-22，同 seed 77001199、
同样是 headless 运行时探针）—— 本表是该口径在**触发盒改造 ＋ 13 房**之后的重做版。
""")
    text = "\n".join(body)
    with open(OUT_MD, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    return text


# --------------------------------------------------------------- HTML
def esc(value):
    return html.escape(str(value))


def html_room_table():
    rows = []
    order = sorted(rooms, key=lambda r: r["idx"])
    num = 0
    for room in order:
        bucket = per_room[room["id"]]
        if room["enemies"] > 0:
            num += 1
            idx_txt = str(num)
        else:
            idx_txt = "—"
        pools_txt = " / ".join("`%s`" % p for p in sorted(bucket["pools"])) if bucket["pools"] else "—"
        pools_txt = pools_txt.replace("`", "")
        box_txt = "、".join(BOX_CN.get(b, b) for b in boxes_by_room.get(room["id"], [])) or "—"
        cls = ' class="dim"' if room["enemies"] == 0 else ""
        rows.append(
            "<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%d</td><td>%s</td><td>%d</td><td>%d</td><td>%s</td></tr>" % (
                cls, idx_txt, esc(ROOM_CN.get(room["id"], room["id"])),
                esc(template_of(room["id"])), esc(room["type"]), room["floor_level"],
                esc(pools_txt), room["waves"], room["enemies"], esc(box_txt),
            )
        )
    return """<table class="tbl">
<thead><tr><th>#</th><th>房间</th><th>房型（设计源模板）</th><th>内容类型</th><th>floor_level</th><th>怪物池</th><th>波次</th><th>只数</th><th>盒型</th></tr></thead>
<tbody>%s</tbody></table>""" % "\n".join(rows)


def html_roster():
    rows = []
    for key, info in roster.items():
        rows.append("<tr><td>%s</td><td class='mono'>%s</td><td class='num'>%d</td><td class='num'>%d</td><td class='mono'>%s</td><td class='num'>%d</td></tr>" % (
            esc(info["name"]), esc(key), info["hp"], info["damage"],
            esc("/".join(sorted(info["rooms"]))), info["count"],
        ))
    if not rows:
        rows.append("<tr><td colspan='6' class='dim'>—</td></tr>")
    return """<table class="tbl">
<thead><tr><th>怪物</th><th>内部 id</th><th>实测 HP</th><th>实测伤害</th><th>出场房</th><th>只数</th></tr></thead>
<tbody>%s</tbody></table>""" % "\n".join(rows)


def html_pool(pool_id, highlight=False):
    data = pools.get(pool_id)
    if not data or not data["rows"]:
        return "<p class='dim'>（无成员）</p>"
    rows = []
    for row in sorted(data["rows"], key=lambda r: -r["weight"]):
        rows.append("<tr><td>%s</td><td class='mono'>%s</td><td>%s</td><td>%s</td><td class='num'>%.2f</td><td class='num'>%.2f%%</td></tr>" % (
            esc(row["name"]), esc(row["item_id"]), esc(TYPE_CN.get(row["type"], row["type"])),
            esc(RARITY_CN.get(row["rarity"], row["rarity"])), row["weight"], row["pct"],
        ))
    rows.append("<tr class='total'><td>合计 %d 项</td><td></td><td></td><td></td><td class='num'>%.2f</td><td class='num'>100%%</td></tr>" % (
        len(data["rows"]), data["total"],
    ))
    return """<table class="tbl">
<thead><tr><th>物品</th><th>item_id</th><th>类别</th><th>稀有度</th><th>权重</th><th>池内占比</th></tr></thead>
<tbody>%s</tbody></table>""" % "\n".join(rows)


def html_specs():
    rows = []
    for spec in specs:
        rows.append("<tr><td>%s</td><td>%s</td><td class='num'>%d</td><td class='mono'>%s</td><td class='num'>%s</td><td class='num'>%s</td><td>%s</td><td>%s</td></tr>" % (
            esc(ENEMY_CN.get(spec["monster"], spec["monster"])), esc(spec["tier"]),
            spec["floor_level"], esc(spec["pool"]), spec["item_chance"], spec["ammo_chance"],
            esc(spec["ammo_range"]), esc(spec["currency"]),
        ))
    return """<table class="tbl">
<thead><tr><th>怪物</th><th>档位</th><th>floor_level</th><th>掉落池</th><th>出物品概率</th><th>备弹概率</th><th>备弹数量</th><th>魂</th></tr></thead>
<tbody>%s</tbody></table>""" % "\n".join(rows)


def html_waves():
    blocks = []
    for room in sorted(rooms, key=lambda r: r["idx"]):
        bucket = per_room[room["id"]]
        if not bucket["wave_map"]:
            continue
        items = []
        for wave_index in sorted(bucket["wave_map"].keys()):
            kinds = bucket["wave_map"][wave_index]
            parts = ["%s ×%d" % (esc(roster.get(e, {}).get("name", e)), c) for e, c in kinds.items()]
            items.append("<li><b>W%d</b>　%s</li>" % (wave_index + 1, "、".join(parts)))
        blocks.append("""<div class="card"><h4>%s <span class="mono dim">%s</span> <span class="tag">%s</span> <span class="tag">floor_level=%d</span></h4><ul>%s</ul></div>""" % (
            esc(ROOM_CN.get(room["id"], room["id"])), esc(room["id"]), esc(room["type"]),
            room["floor_level"], "".join(items),
        ))
    return "".join(blocks)


def build_html():
    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>远征关卡01 · 怪物掉落列表</title>
<style>
  :root {
    --bg: #f5f6f8; --panel: #ffffff; --ink: #1c2229; --ink-2: #5a6470; --ink-3: #8b949e;
    --line: #e3e6ea; --accent: #2f6fd0; --accent-soft: #eaf1fc; --warn: #b4531a; --warn-soft: #fdf1e7;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 32px 40px 64px; background: var(--bg); color: var(--ink);
    font: 14px/1.65 "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
  }
  .wrap { max-width: 1140px; margin: 0 auto; }
  h1 { font-size: 26px; margin: 0 0 6px; letter-spacing: .3px; }
  h2 { font-size: 19px; margin: 36px 0 12px; padding-bottom: 8px; border-bottom: 2px solid var(--line); }
  h3 { font-size: 15px; margin: 22px 0 10px; color: var(--ink); }
  h4 { font-size: 14px; margin: 0 0 8px; }
  .meta { color: var(--ink-2); font-size: 13px; margin-bottom: 22px; }
  .kpis { display: flex; gap: 12px; flex-wrap: wrap; margin: 18px 0 8px; }
  .kpi { flex: 1 1 150px; background: var(--panel); border: 1px solid var(--line);
         border-radius: 10px; padding: 12px 14px; }
  .kpi .k { color: var(--ink-3); font-size: 12px; }
  .kpi .v { font-size: 20px; font-weight: 700; margin-top: 2px; }
  table.tbl { width: 100%%; border-collapse: collapse; background: var(--panel);
              border: 1px solid var(--line); border-radius: 10px; overflow: hidden;
              margin: 10px 0 18px; font-size: 13px; }
  table.tbl th { background: #eef1f4; text-align: left; padding: 9px 11px; font-weight: 600;
                 color: var(--ink-2); border-bottom: 1px solid var(--line); white-space: nowrap; }
  table.tbl td { padding: 8px 11px; border-bottom: 1px solid var(--line); }
  table.tbl tbody tr:last-child td { border-bottom: none; }
  table.tbl tbody tr:hover { background: #fafbfc; }
  tr.dim td { color: var(--ink-3); }
  tr.total td { background: var(--accent-soft); font-weight: 600; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  .mono { font-family: Consolas, "Courier New", monospace; font-size: 12.5px; }
  .dim { color: var(--ink-3); }
  .tag { display: inline-block; background: var(--accent-soft); color: var(--accent);
         border-radius: 5px; padding: 1px 7px; font-size: 12px; margin-left: 6px; font-weight: 500; }
  .card { background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
          padding: 12px 16px; margin: 8px 0; }
  .card ul { margin: 0; padding-left: 20px; }
  .notice { background: var(--warn-soft); border: 1px solid #f0d3bb; border-left: 4px solid var(--warn);
            border-radius: 8px; padding: 14px 18px; margin: 14px 0 20px; }
  .notice b { color: var(--warn); }
  .notice ol, .notice ul { margin: 8px 0 0; padding-left: 20px; }
  .note { color: var(--ink-2); font-size: 13px; margin: 6px 0 14px; }
  code { background: #eceff3; border-radius: 4px; padding: 1px 5px; font-size: 12.5px;
         font-family: Consolas, monospace; }
  pre { background: #232a33; color: #d7dde5; border-radius: 10px; padding: 14px 16px;
        overflow-x: auto; font-size: 12.5px; line-height: 1.6; }
  pre code { background: none; color: inherit; padding: 0; }
</style>
</head>
<body>
<div class="wrap">
  <h1>远征关卡01 · 怪物掉落列表</h1>
  <div class="meta">
    数据源：Godot 4.6.3 headless 运行时实测（<code>run_seed=77001199</code>、<code>test_mode=1</code>）　·　
    探针：<code>_scratch/lootprobe/probe_exp01_drops.gd</code>　·　生成日期：2026-09-26
  </div>

  <div class="kpis">
    <div class="kpi"><div class="k">房间总数</div><div class="v">13</div></div>
    <div class="kpi"><div class="k">本局怪物</div><div class="v">%d 只</div></div>
    <div class="kpi"><div class="k">普通怪池</div><div class="v">3 档</div></div>
    <div class="kpi"><div class="k">怪种</div><div class="v">%d 种</div></div>
    <div class="kpi"><div class="k">精英 / 首领</div><div class="v">%d / %d</div></div>
  </div>
  <p class="note">
    编成来源为<b>触发器刷怪盒</b>（<code>spawn_placements</code> + <code>encounter</code>）；
    <code>content_type</code> 与房型公式均不参与编成。
    10 间内容房按主路序号落三档池：<code>floor_level 0 → loot_floor_1_2</code>、
    <code>1 → loot_floor_3_4</code>、<code>2 → loot_floor_5</code>。
  </p>

  <h2>1. 逐房编成与掉落池</h2>
  %s

  <h2>2. 怪物名册（实测数值，已含主题倍率）</h2>
  <p class="note">主题 <code>iron_frontier</code>（冷钢边境），<code>difficulty_rank=1</code> ⇒ <code>floor=1</code>；
  HP / 伤害已含 <code>hp_multiplier=0.95</code>、<code>damage_multiplier=0.95</code>。</p>
  %s

  <h2>3. 逐波编成明细</h2>
  %s

  <h2>4. 单只怪的掉落规则</h2>
  %s
  <p class="note">本关 <code>floor=1</code>：出物品 = 按概率掷一次，命中则从对应池按权重抽 1 件；
  备弹 = 34%% 掉通用弹药 3–8 个（与池内同物品合并且以整包数量覆盖）；
  魂 = 必掉 <code>2 + floor×1 = 3</code>。</p>

  <h2>5. 掉落池明细</h2>
  <h3>5.1 <code>loot_floor_1_2</code> — 浅层池（room_01 ~ room_03）</h3>
  %s
  <h3>5.2 <code>loot_floor_3_4</code> — 中层池（room_04 ~ room_07）</h3>
  %s
  <h3>5.3 <code>loot_floor_5</code> — 深层池（room_08 ~ room_10 与 Boss 房）</h3>
  %s
  <h3>5.4 <code>scavenge_floor_1</code> — 容器搜索池（非怪物掉落）</h3>
  %s

  <h2>6. 实测异常：精英与首领一个都没出</h2>
  <div class="notice">
    <b>设计源摆了盒，运行时一个都没生成。</b> 两处独立缺陷，且都是静默返回空字典（不报错、不写日志）：
    <ol>
      <li><b>精英缺位</b>：<code>EliteContentCatalog</code> 里可部署精英只有一条
          （<code>eligible_floor_numbers=[98,97,96]</code>），其余全是 <code>DESIGN_ONLY</code>；
          远征 <code>floor_number = maxi(1, difficulty_rank) = 1</code> ⇒ 名册无匹配 ⇒
          <code>select_and_reserve</code> 返回 <code>roster_exhausted_or_reserved</code> ⇒ 不出。</li>
      <li><b>首领缺位</b>：<code>BossContentCatalog.CONTENT</code> 只注册 <b>95 / 90 / 85</b> 三层；
          远征 Boss 房 <code>boss_content_id</code> 为空、<code>floor_number=1</code> ⇒
          <code>get_for_floor(1)</code> 空 ⇒ 按「没写 boss 就是没有 boss」静默空房。</li>
    </ol>
    影响：<code>elite_floor_1</code> 与 <code>boss_floor_1</code> 两个已登记池在本关完全落不下去，
    最高只能掉到 <code>loot_floor_5</code>。
  </div>
  <table class="tbl">
  <thead><tr><th>位置</th><th>盒子声明</th><th>实测实到</th><th>缺口</th></tr></thead>
  <tbody>
    <tr><td>room_05 / 07 / 08 / 10</td><td><code>box_center_elite</code> = 精英×1 + 小僵尸×1</td><td>只有小僵尸×1</td><td>精英缺 1（每处）</td></tr>
    <tr><td>Boss 房 W1</td><td><code>box_boss_arena</code> = Boss×1 + 精英×2 + 巢怪×1</td><td>只有巢怪×1</td><td>Boss 缺 1、精英缺 2</td></tr>
  </tbody>
  </table>
  <h3>6.1 <code>elite_floor_1</code> — 精英池（登记但本关不可达）</h3>
  %s
  <h3>6.2 <code>boss_floor_1</code> — 首领池（登记但本关不可达）</h3>
  %s

  <h2>7. 其他掉落来源</h2>
  <table class="tbl">
  <thead><tr><th>来源</th><th>口径</th><th>远征01 取值</th></tr></thead>
  <tbody>
    <tr><td>容器搜索</td><td><code>scavenge_floor_%%d</code>，<code>%%d = min(5, maxi(1, difficulty_rank))</code></td><td>恒 <code>scavenge_floor_1</code></td></tr>
    <tr><td>清房钥匙</td><td>独立路径，不经怪物掉落池</td><td>每个敌对房</td></tr>
    <tr><td>魂兜底</td><td>每次击杀追加 <code>2 + floor</code></td><td>3</td></tr>
  </tbody>
  </table>

  <h2>8. 与旧表的口径差异（2026-09-22 版已作废）</h2>
  <table class="tbl">
  <thead><tr><th>项</th><th>旧（09-22）</th><th>现（09-26 实测）</th></tr></thead>
  <tbody>
    <tr><td>编成来源</td><td><code>enemy_spawn_plan</code> 半钉死波次 + 房型公式</td><td><b>触发器刷怪盒</b></td></tr>
    <tr><td>房间数</td><td>7 房</td><td><b>13 房</b></td></tr>
    <tr><td>内容房类型</td><td>每局按种子洗牌</td><td><b>设计源钉死</b></td></tr>
    <tr><td>Boss</td><td>无</td><td>摆了盒，但仍出不来（§6）</td></tr>
    <tr><td>怪种</td><td>3 种</td><td><b>5 种</b></td></tr>
  </tbody>
  </table>

  <h2>9. 复现命令</h2>
  <pre><code># 1) 资源导入（独享 ASCII APPDATA；改过 GLB 后必做）
export APPDATA='C:\\tmp\\ss2_appdata_probe'
cd ShellStorm2
"&lt;godot&gt;" --headless --path . --import

# 2) 逐房刷怪与掉落规格实测（探头是 extends Node，用位置参数或 --scene）
"&lt;godot&gt;" --headless --path . res://_scratch/lootprobe/probe_exp01_drops.tscn
#   → _scratch/lootprobe/exp01_drops_out.txt

# 3) 掉落池成员导出（dump_loot.gd 是 extends SceneTree，--script 才成立）
"&lt;godot&gt;" --headless --path . --script res://_scratch/lootprobe/dump_loot.gd</code></pre>

  <h2>10. 为什么这份表出自「运行时实测」而不是「设计文档」</h2>
  <div class="notice">
    <b>结论：不是「舍文档而取代码」，而是这条链的终点本来就是代码。</b>
    设计文档把数值委派给内容数据库，内容数据库又把「事实源」指回 <code>ItemRegistry.gd</code> —— 闭环落在代码。
  </div>

  <h3>10.1 真源链路（四方对照）</h3>
  <table class="tbl">
  <thead><tr><th>层</th><th>载体</th><th>里面有掉落数值吗</th></tr></thead>
  <tbody>
    <tr><td>玩法设计主文档</td><td><code>docs/v0.1/design/战斗奖励与物品流转设计.md</code></td><td>❌ 只写规则与验收意图；明文「数值和具体内容以<b>内容数据库</b>为准」</td></tr>
    <tr><td>关卡设计源（数据）</td><td><code>level_plan.json</code> / <code>floor_00.json</code></td><td>❌ 只有几何、拓扑、房型池、刷怪盒 —— 一个掉落字段都没有</td></tr>
    <tr><td>关卡设计文档</td><td><code>docs/v0.1/design/远征关卡01设计.md</code></td><td>❌ 唯一含「掉落」的一处是「<code>Dungeon3D</code> 不改变掉落数值」＝免责声明</td></tr>
    <tr><td>内容数据库</td><td><code>ShellStorm2_游戏内容数据库_v010.xlsx</code> → <code>掉落物品</code></td><td>⚠️ <b>物品侧视图</b>（按物品列产出池×权重）；<b>没有「远征关卡01」这一行</b>，且第 13 列「事实源」写的就是 <code>src/base/ItemRegistry.gd</code></td></tr>
    <tr><td><b>运行时真源</b></td><td><code>ItemRegistry.gd</code> ＋ <code>MonsterInjector.gd</code> ＋ <code>Dungeon3D.gd</code></td><td>✅ <b>数值唯一真源在此（代码）</b></td></tr>
  </tbody>
  </table>

  <h3>10.2 那几份「掉落表设计文档」为什么没采用</h3>
  <p>2026-09-22 的 <code>怪物掉落表_地图x怪物_设计定稿v2.md</code> 自称<b>设计定稿</b>，
     形态正是「关卡ID × 怪物ID × 物品ID × 概率 × 权重 × 数量」总表。但其施工清单逐项未落地：</p>
  <table class="tbl">
  <thead><tr><th>施工清单项</th><th>应为</th><th>实测</th></tr></thead>
  <tbody>
    <tr><td>第 4 项</td><td>新 <code>src/rewards/MonsterDropTable.gd</code></td><td>❌ 文件不存在（该目录只有 RewardPoolRegistry / RewardService / RewardSink / RewardSpec / RuntimeRewardCoordinator）</td></tr>
    <tr><td>第 2 项</td><td><code>level_plan.json</code> 顶层 <code>monster_drop_table</code></td><td>❌ 不存在（顶层只有 schema / level_id / site / core / floors / room_templates / generation_policy / provenance 等）</td></tr>
    <tr><td>第 6 项</td><td><code>ItemRegistry</code> 加 6 个 <code>loot_monster_&lt;type&gt;</code> 池</td><td>❌ 0 个（运行时 16 个池键全是旧的 <code>loot_floor_*</code> 一系）</td></tr>
    <tr><td>全仓检索</td><td><code>monster_drop_table</code> / <code>MonsterDropTable</code> / <code>loot_monster_</code></td><td>❌ <code>src/</code> 下 0 命中</td></tr>
  </tbody>
  </table>
  <p>文档自身状态亦为「<b>待你点头（仅 1 项：表格载体）</b>」⇒ <b>该改造从未落地</b>，
     运行时仍走旧口径 <code>MonsterInjector.get_loot_table_for_level(floor_level)</code>。
     若照它出表，会得到一份<b>游戏里并不存在的掉落表</b>。</p>

  <h3>10.3 那运行时实测多测了什么</h3>
  <ol>
    <li><b>每波实际出几只</b> —— <code>_roll_box_count()</code> 是按种子在盒容量内掷的随机数；</li>
    <li><b>声明了却出不来</b> —— §6 的精英 / 首领：数据文件写着 <code>elite×1</code>、<code>boss×1</code>，<b>只读数据必然误报</b>；</li>
    <li><b>盒的落地位置与容量</b> —— <code>_resolve_landing_box()</code> 会平移盒位，容量取决于家具碰撞。</li>
  </ol>
  <p>本表口径：<b>静态读代码与数据定「规则与映射」，运行时探针定「实际编成与数量」，两者对账</b>。
     同方法先例：<code>outputs/远征关卡01_掉落表与产出物设计核查.md</code>（2026-09-22，同 seed 77001199）。</p>
</div>
</body>
</html>
""" % (
        total_enemies, len(roster), total_elite, total_boss,
        html_room_table(), html_roster(), html_waves(), html_specs(),
        html_pool("loot_floor_1_2"), html_pool("loot_floor_3_4"), html_pool("loot_floor_5"),
        html_pool("scavenge_floor_1"), html_pool("elite_floor_1"), html_pool("boss_floor_1"),
    )


def main():
    md = build_md()
    page = build_html()
    with open(OUT_HTML, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)
    print("MD   -> %s (%d chars)" % (OUT_MD, len(md)))
    print("HTML -> %s (%d chars)" % (OUT_HTML, len(page)))
    print("rooms=%d  enemies=%d  elite=%d  boss=%d  roster=%d" % (
        len(rooms), total_enemies, total_elite, total_boss, len(roster)))
    for key, info in roster.items():
        print("  %-14s %-8s hp=%-3d dmg=%-3d count=%d" % (
            key, info["name"], info["hp"], info["damage"], info["count"]))


main()
