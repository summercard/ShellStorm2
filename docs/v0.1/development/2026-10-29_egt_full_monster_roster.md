# 远征03：EGT 第一层怪物全量实装（12 → 33）

日期：2026-10-29（下午）
范围：`src/enemy3d/`、`src/map/`、`data/spawn_boxes/`、`data/level_plans/expedition_03/`、`docs/v0.1/design/`
上游决策：用户「先把怪物实装了，让怪物体系一致。ai 和攻击方式都需要一致。可以先用替代资产进行」

---

## 1. 一句话

第一层还剩 21 种怪没做（此前只做了 12 种）。这一批把它们全部做完，
**整层 33 种非 Boss 敌人都有行、都能刷、都编进房间了**，并且用的还是同一套数据驱动机制 ——
没有为任何一只怪新增一条攻击代码分支。

---

## 2. 做了什么

### 2.1 21 只新怪（详见 `怪物设计.md §T1`）

子弹族补 2（红衣主教 / 空尖弹）、霰弹枪族补 1（老兵霰弹）、爆炸族补 2（子弹榴弹王 / 榴弹子）、
分裂族补 1（骰子布洛布）、书怪族补 3（三色书怪）、法术族补 2（枪法师 / 吉吉）、
冲撞族补 3（霰弹榴弹 / 螺旋转弹）、触发族补 6（钥匙小子 / 运气小子 / 已确认者 / 拟态怪 /
枪精灵 / 抓握大师）、重型补 2（枪坚果 / 链枪手）。

数值一律走既有口径，**没有一个是手填的**：
- 血量 `hp_3d = clamp(round(42 × (egt_hp/15)^0.72), 6, 200)`，由 `_egt_monster_registry_probe` 逐只反算复核；
- 速度 = 目标 m/s ÷ 0.7（`PROFILES`）与 ×24 px/s（`BASE_ENEMY_TYPES`）两处同源；
- 伤害沿用「半颗心 ≈ 5~11、爆炸 14~22」。

### 2.2 新增的攻击能力（都是**参数**，不是分支）

| 能力 | 实现位置 | 谁在用 |
|---|---|---|
| 12 种弹道图案 | `_pattern_directions()` | V 型、环形、四叶草、罗盘 8 向、箭头群、字母、螺旋、蛇形、骰子 |
| `followup`（同一次攻击的第二段） | `_perform_volley_attack()` | 蓝霰弹「宽 5 发 → 快接 4 发」 |
| `volley_alt` + `alt_every`（每 N 次换招） | `_egt_active_volley_spec()` | 红衣主教、蓝书怪、拟态怪、枪坚果 |
| 子弹追踪（含**敌方**子弹） | `Projectile3D` 的 hostile 分支 | 红衣主教、已确认者、吉吉的蛋 |
| 子弹反弹 | 既有 `bounce_count`，本次接上怪侧入口 | 子弹榴弹王 |
| `egg`（延迟在落点炸开） | `_schedule_egg()` / `_tick_egt_eggs()` | 吉吉 |
| `blink`（瞬移） | `_blink_to_random()` | 空尖弹（定时）、枪法师（出手后） |
| `flee`（逃跑 + 超时消失） | `_tick_egt_flee()` / `_vanish()` | 钥匙小子、运气小子 |
| `disguise`（伪装成箱子） | `_tick_egt_disguise()` / `_reveal_disguise()` | 拟态怪 |
| `grab`（悬停下压抓人） | `_tick_egt_grab()` | 抓握大师 |
| `orbit`（绕圈子弹链） | `_tick_egt_orbit()` | 链枪手 |
| `chance_moves`（随机招式 + 自杀） | `_perform_chance_move()` | 骰子布洛布 |
| `death_split.children[]`（一次产**多种**子代） | `_perform_death_split()` | 子弹榴弹王 |

### 2.3 把「逐只 if」换成「读表分派」

`_perform_attack()` 里原来有 5 条 `egt_*` 的 kind 列表分支。第二批要加 21 只，
继续加就是 26 行长名单，且每加一只都要改"攻击代码"。

改成：

```
if _is_egt_kind():
    _perform_egt_attack(...)   # 按 profile.attack_style 分派
    return
match _table_kind():           # 老怪一行未改
```

`attack_style` 成了**唯一真源**：9 种骨架（volley / contact / explode / rush / support /
grab / orbit / chance / flee）。第一批 12 只也补上了显式 `attack_style`，
不再依赖"看有没有 volley 键去猜"。

### 2.4 编成：8 → 22 个敌群盒

新增 14 个 `box_egt_*`，让 33 种怪**全部有出场编成**（此前 21 种只在表里，游戏里见不到）。
房间分配按 node 推进重排：

| node | 编成 |
|---|---|
| n01 | kin_patrol + blob_cluster（入门） |
| n02 | kin_trio + hollow_line（瞬移首次登场） |
| hub_01 | shotgun_lead + cardinal_guard + nut_guard |
| n03 | rush_line + shotgun_vet |
| n04 | bomb_pair + chance_blob（随机性首次登场） |
| hub_02 | shotgun_heavy + support_cell + **king_bullat** + **heavy_pair**（顶点） |
| n05 | bomb_pair + jurer_pair（缓冲） |
| n06 | rush_line + rush_squad + escape_pair |
| n07 | support_cell + shotgun_heavy + **mimic_trap**（商店前） |
| n08 | kin_trio + book_row + confirmed_cell |
| NORMAL 兜底 | kin_patrol + blob_cluster |
| HUB 兜底 | kin_trio + shotgun_lead + **grip_pair** |

单房盒子数维持 2~4 组 —— **不靠加盒子加难度**，换的是每组种类更丰富。

---

## 3. 验收

| 项 | 命令 | 结果 |
|---|---|---|
| 注册一致性 | `godot --headless --path . --scene res://tools/_egt_monster_registry_probe.tscn` | `EGT_MONSTER_REGISTRY_PROBE_OK`（33 只 × 9 个注册点；血量复算全对；9 种骨架自洽；逐只真打一次） |
| 族内可区分 | `--scene res://tools/_egt_variant_visual_probe.tscn` | `EGT_VARIANT_VISUAL_PROBE_OK`（11 族；跨族无同形同色） |
| 数据/别名/关卡规则 | `--scene res://tools/_egt_monster_probe.tscn` | `EGT_MONSTER_PROBE_OK`（33 只） |
| 编成与几何 | `--scene res://tools/_egt_roster_probe.tscn` | `EGT_ROSTER_PROBE_OK`（6 种子全战斗房有编成、盒位三判据通过） |
| 真实进房 | `--scene res://tools/_egt_runtime_probe.tscn` | `EGT_RUNTIME_PROBE_OK`（hub_01 稳定 7 只、全 `egt_*`、零原生怪，连跑 3 次一致） |
| 敌人行为回归 | `tests/verification/verify_3d_enemy_behavior_flow.tscn` | exit 0（10 项） |
| 强化怪回归 | `tests/verification/verify_strong_variant_monsters.tscn` | `STRONG_VARIANT_OK`（samples=4261） |
| 资产账本结构门禁 | `check_asset_registry.py --scope structure` | `ASSET_REGISTRY_CHECK_OK assets=1374 ledgers=9`（敌人域 48 行） |
| 无损基线 | `tools/asset_pipeline/verify_ledger_split.py` | 敌人域归零（33 只全部进基线、无 `row_content_mutated`、无列漂移） |

---

## 4. 踩到的坑（都写进代码注释了）

**① 齐射 + 连发的节奏判据不能按"图案类型"分。**
第一版按 `pattern in ["letter","spiral"]` 判断是否逐发，结果三连发（bandana）变成
"三发同时出" —— 因为 `line` 图案一次出全部。改成**只认 `interval > 0`**：
有间隔就逐发排期，无间隔就整组齐射。判据少一个维度，就少一处会漂的分支。

**② `followup` 写在 profile 顶层时读不到。**
第一版把 `"followup"` 写成 `volley` 的兄弟键，而 `_perform_volley_attack` 读的是
`spec.get("followup")`（spec = `volley` 本身）⇒ 蓝霰弹的第二段 4 发**永远不出现**，
但探针只看到"排队 5"也说不清少了什么。修法：把 `followup` 放进 `volley` 内部。

**③ 注册探针专治"写了但没生效"。**
它抓住三类真实漏登记：第一批 12 只缺显式 `attack_style`（能跑但图纸与运行时不同源）、
`egt_pinhead` 靠回退拿颜色（探针无法区分"刻意同色"和"忘了登记"）、
`egt_mimic` 伪装时不出弹（探针把"该拦"与"坏了"分开查）。
这三条**都是自己看代码看不出来的**。

**④ 并发跑 headless 会污染刷怪数量。**
调试期间有一个 Godot 实例挂住不退（临时脚本 parse error 后空转），
期间连跑 3 次 `_egt_runtime_probe` 都是 6 只（少一只 `egt_red_shotgun`）。
杀掉挂住实例后连跑 3 次稳定 7 只。**结论：出现"稳定少一只"先查有没有并发实例**，
不要先去改落位算法。

**⑤ 设计文档里「血量 ×3」是错的，实测打的是 42 血那只。**
第一批写的是「`PROFILES.hp` 是基线，运行时 ×3 才是进场血量」，并据此在表里加了
「×3 后」列、账本规格列也写成 `hp42(x3=126)`。
进房实测（hub_01 采样）发现 `max_hp=42 / 56 / 165`，**就是表里的基线值** ——
因为 `stats.per_kind` 会下发 `override_max_hp` 并**在函数末尾直接赋值**，
把前面所有比例还原一起盖掉。已于本次一并修正：设计 §T0.2、§T1 九张表的列名（"进场 HP"）、
账本 33 行的规格串。**这类"两处都写了同一个数、彼此矛盾"的错，只有实测能发现。**

---

## 5. 明确没做到的

见 `怪物设计.md §T6`，六处：钥匙掉落 / 房间重置 / 开箱现形 / 线状爆炸 / 字母图案精度 / 穿墙链。
它们不影响"33 种都在、AI 与攻击同构"，但让这一层比原作**更容易**。

下一步优先级（承上文差异盘点）：**Boss 三只 > 钥匙与宝箱 > 剩余保真度**。
继续补怪已无对象 —— 第一层的怪做完了。

---

## 6. 账本与文档同步（本轮收尾）

代码跑通不等于交付完成：新增 33 行资产会让**无损基线**（拿拆分前的冻结快照做回归守卫）
报 `asset_not_in_baseline`。这是「预期的过期」，但必须按既有口径补录，否则门禁会一直红。

**① 敌人账本（`ShellStorm2_敌人账本_v001.xlsx`）**

| 页 | 改动 |
|---|---|
| 《资产主表》 | 新增 r21~r32（第一批 12）与 r33~r53（第二批 21），共 33 行 `egt_*`；`制作状态=程序占位`，表现列写「复用 X 的模型/程序壳」；查重列 R/S 公式范围由 `$R$32` 扩到 `$R$53` |
| 《总览》 | 六个统计公式区间同步扩到 `$6:$53`（资产总数 48） |
| 《域变更日志》 | v0.1.20（12 行）+ v0.1.21（21 行） |
| 《账本说明》 | 「登记范围」补「远征03 33 种复刻怪（表现占位）」；快照日期 2026-09-18 → 2026-10-29 |
| 《3D-敌人》 | **刻意未改**：该页口径是「一行 = 一个真实存在的 Godot PackedScene」，33 只复刻怪没有自己的 Prefab（借皮占位），加行会破坏这条契约。转正时再补 |

**② 无损基线（`assets/registry/ledger_split_baseline.json`）**

新增脚本 `scripts/refresh_ledger_baseline_egt_enemies.py`，沿用先例（敌人账本日志 v0.1.3）的
「最小外科补录」：备份 → **只加 33 个新 AssetID 的指纹** → `asset_count` / `category_counts` /
`column_digests` 从当前账本重算 → `sheet_digests` 不动（本批没改任何专表）。
脚本里写死 `EXPECTED_NEW`（33 个 ID 全列出来）且 `REFRESH_ALLOWED` 为空 ——
**新增集合与声明不一致就直接退出 1**，防止"什么新行都当合法"把守卫变成摆设。

结果：`added=33 / asset_count=1374 / 敌人 48`，`verify_ledger_split` 的敌人域清零。

> 该门禁目前**还剩一条红**：`vfx / 3D-特效` 的 `moved_sheet_mutated`。
> 差分定位确认它在本次改动**之前**就存在（特效账本文件在工作区未被修改，
> 且我们刷新时明确没动 `sheet_digests`），属特效域的基线过期，不在本批范围内 ——
> 要清需由特效域按同样口径补录，不要为了"变绿"直接刷 digest。

**③ 设计文档**

| 文档 | 改动 |
|---|---|
| `design/怪物设计.md` | §T1 按 9 族重排为 33 只；§T2 九种骨架 / 12 种图案 / 9 个行为键；§T3 逐只体型与染色（含「正式 GLB 不吃 `COLORS`」）；§T4 施工状态补「资产登记」「无损基线」两行；§T5 编成 22 盒；§T6 六处保真度差异；**新增 §T7「这一批的事实落在哪」**——把 9 处唯一真源和对应门禁列成一张表 |
| `design/远征关卡03设计.md` §8.3 | 覆盖度改 33 种 / 22 盒，补「资产登记 / 无损基线」行，并记录第二批的编排取舍（逃跑型只放 `n06` 与 HUB、拟态怪只放商店前、抓握大师只在 HUB） |
| `feature_registry.json` | `ENEMY-AI.development_records` +4（三份怪物记录 + 编成记录） |
| `development/CHANGELOG.md` | 新增两条：33 种全实装、逐房编成取代公式 |
| `development/README.md` | 索引补 4 条（33 种、编成、变种区分、EGT 小地图复刻） |

