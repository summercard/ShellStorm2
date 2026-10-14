# 远征01 关卡级怪物规则（`monster_rules`）与怪物改动

- **日期**：2026-10-14
- **FeatureID**：`WORLD-PLAN`（关卡数据）+ `ENEMY-AI`（AI 参数与自爆）
- **业主口径**：*「A 不动（不改几何真源）、只挪盒位、改怪物初始逻辑（激活/追击）、调数值，
  且这些只有远征01会有」*；随后追加 *「胖子僵尸被打死后需要能自爆，会影响所有单位，
  包括敌对单位和玩家，伤害是 180」*。
- **结论**：新增**关卡级怪物规则通道** `level_plan.json` 顶层 `monster_rules`，
  一次性承载「数值绝对覆盖 + AI 手感参数 + 死亡自爆」；三只怪改数值；`room_02` 改五群布局 + 联动激活；
  关卡掉落加 40% 空掉落。**全部只影响远征01，`Enemy3D.PROFILES` 基线未改。**

---

## 1. 为什么必须先建通道

| 障碍 | 事实 |
|---|---|
| AI 可调点几乎全是全局量 | 23 个可调点里 **21 个**是 `Dungeon3D` / `Enemy3D` / `MonsterAIManager` 的**全局常量或硬编码字面量** |
| 主题档案被多关共用 | `data/map_themes/iron_frontier.tres` 被 **5 个场景**引用：`ExpeditionLevel01_3D` / `ExpeditionLevel02_3D` / `ExpeditionLevel99_3D` / `IronFrontier3D` / **`TowerDescent3D`** |

⇒ 直接改任何一个都会连带改掉塔楼与其它关卡。故新增 `monster_rules` 段，
形态与既有 `monster_drop_table` 同构。

**「只影响远征01」由三条独立理由保证（缺一不可）**：

1. 只写在远征01 自己的数据文件里；别的关卡不写本段 ⇒ `_monster_rules` 为空字典 ⇒ 走原常量。
   `_stat_override()` 在空规则下返回 `{}`（`Dictionary.merge({})` 是 no-op）；
   `_ai_param()` / `ai_param_for()` 键缺失时**回退传入的全局常量**。
2. **不进 `layout_id`** —— `_data_driven_layout_id` 的 canonical 只含
   `level_id / floor_number / floor_index / entry_side / rooms{key,template_id,variant,center,size,rotation_deg,ports,…} / global_rotation_deg / run_seed`
   ⇒ **改数值不会让既有存档失配**。
3. `spawn_placements` 同样不在 canonical 里 ⇒ **挪盒位也不断存档**。

---

## 2. 贯通路径（7 处）

| # | 文件 | 动作 |
|---|---|---|
| 1 | `data/level_plans/expedition_01/level_plan.json` | 顶层新增 `monster_rules`（`stats` / `ai` / `death_explosion`） |
| 2 | `src/map/FloorPlanGenerator.gd` | `generate_from_level_plan` 透传 `monster_rules`（与 `monster_drop_table` 同处） |
| 3 | `src/map/MonsterInjector.gd` | `set_level_rules` / `_stat_override` / `_ai_overrides` / `_death_explosion_for` / `_death_explosion_overrides`；三处生成函数末尾各接一次 |
| 4 | `src/world3d/TowerDescent3D.gd` | bootstrap 拿到 plan 后调 `set_monster_rules` |
| 5 | `src/world3d/Dungeon3D.gd` | 存 `_monster_rules`；`_ai_param`；预激活半径可配；房间级 AI 合并 |
| 6 | `src/enemy3d/Enemy3D.gd` | 应用 `override_*`；`_ai_param`；engage / alert / lost_sight 走可配值；自爆三函数 |
| 7 | `src/enemy3d/MonsterAIManager.gd` | 三档视野 / 警报半径 / 贴脸察觉走 `ai_param_for` |

**为什么走 `data` 字典而不是让 `Enemy3D` 查全局**：`configure_from_enemy_data(data)` 是 `Enemy3D`
的唯一配置入口，`data` 由 `MonsterInjector` 造。把关卡级参数塞进 `data` ⇒ 塔楼的 `data` 里没有这些键
⇒ 走原常量。这是「只影响远征01」最省事、最不容易漏的隔离方式。

---

## 3. 🔴 数值口径：必须写「绝对最终值」，不能写倍率

`Enemy3D` 的最终值**不是**「基础 × 倍率」：

```
max_hp = PROFILES[kind].hp × 3.0(普通) / 10.0(Boss)
         × (data.max_hp ÷ SOURCE_HP_BASE[kind])
```

而 `data.max_hp` 在 `MonsterInjector` 里已被 **`int()` 截断过**。实测差异：

| | 若按「倍率」心算 | 实跑真值 |
|---|---|---|
| 小僵尸第一层 | `58 × 3 × 0.95 = 165`（**错**） | **160**（`int(25×0.95)=23`，`58×3×23/25 = 160.08 → 160`）|

⇒ `stats.per_kind` 写**绝对最终值**（直接赋值、不再参与楼层缩放与主题倍率）。
写 350 就是 350，免去反推，也免得「改了没生效」。

**两个必须注意的顺序**：
- Boss 的覆盖要接在 `MonsterInjector._generate_boss` 末尾那段显示器Boss 固定基线 `merge` **之后**，
  否则被 `hp:200` 盖掉。
- 精英从基础怪派生（HP ×1.5 / 伤害 ×1.3）；绝对赋值会吃掉这两个倍率，
  故 `_generate_elite` 末尾要**按倍率重算一次**。

---

## 4. 三只怪数值（业主指定）

| 怪种 | 基线（PROFILES） | 远征01 覆盖 |
|---|---|---|
| `melee_chaser` 小僵尸 | 58 / 12 / 3.7 | **生命 350 / 伤害 18 / 速度 3.5 m/s** |
| `fat_zombie03` 胖子僵尸 | 232 / 19 / 0.857142857 | **生命 800 / 伤害 35 / 速度 1.5 m/s** |
| `boss` 显示器Boss | 5200（身份基线 200 × 10） | **生命 32000**（速度 3.612 未动） |

**未配置的怪逐值不变**（实测）：`ranged_caster` 129/9、`exploder` 113/28、
`ambusher` 142/15、`summoner` 202/8。

---

## 5. 胖子僵尸死亡自爆（180、敌我通吃）

```json
"death_explosion": {
  "fat_zombie03": { "enabled": true, "damage": 180, "radius_m": 5.0, "sfx_radius_m": 20.0 }
}
```

**刻意不复用 `exploder._explode()`** —— 那是炸弹果的**主动贴近**自爆，三条语义都不同：

| | `exploder._explode()` | `_detonate_death_explosion()` |
|---|---|---|
| 伤害 | `contact_damage`（随楼层/主题缩放会漂） | **规格里的固定值** |
| 目标 | **只伤玩家** | **敌我通吃**（相邻敌对怪 ＋ 玩家） |
| 半径 | 3.0 m（硬编码） | 规格半径 |
| 触发 | 主动贴近玩家 | **死亡时**（`_die()`） |

**三条工程性质（都已实测）**：

1. **级联安全**：隔壁残血胖子会被牵连炸死 ⇒ 它走自己的 `_die()` ＋ 自爆；
   反向炸回本怪时被 `take_damage` 首行的 `ai_state == "dead"` 挡掉 ⇒ **不无限递归**。
2. **同房过滤**：`query_radius(..., room_filter=[room_id])`，与 `_heal_nearby_allies` /
   `_strengthen_nearest_enemy` 同口径 ⇒ 门关着时跨房的怪不被炸、也不被顺带激活。
3. **不转移仇恨**：怪物 AI 的目标只从 `player_3d` 组取 ⇒ 「怪炸怪」只掉血、不互殴。

**触发点**：`Enemy3D._die()` 内、`killed.emit` **之前** ⇒ 被自爆炸死的怪也各自走完掉落结算。

**未指定项取默认值**（业主只给了伤害 180）：`radius_m = 5.0`（一个 5 m 砖格）、`sfx_radius_m = 20.0`。
调整只改这一个 JSON 字段。

---

## 6. `room_02` 五群布局与联动激活

业主口径：*「将怪群刷在房间中间和四个角落；如果角色和任何一堆怪群进入战斗，
其它四个怪群都会围上来。怪群组合和数量不变。」*

| # | 盒 | `center_m` | 定位 | `count_multiplier` |
|---|---|---|---|---|
| 0 | `box_room_spread` | `[2.5, -2.5]` | 中心主力群 | 2 |
| 1 | `box_room_spread` | `[-12.5, -7.5]` | 西南角 | — |
| 2 | `box_corridor_column` | `[12.5, -7.5]` | 东南角 | — |
| 3 | `box_wall_arc` | `[-12.5, 2.5]` | 西北角 | 2 |
| 4 | `box_corner_ambush` | `[12.5, 2.5]` | 东北角 | — |

**联动激活**：房间级 `encounter.monster_ai.alert_share_radius_m = 60`（本房对角 ≈ 50 m）。
**没有新增机制** —— 复用既有「同伴警报」传播（`MonsterAIManager._share_ally_alert`），
只把半径从全局常量 `ALERT_SHARE_RADIUS = 10.0` 改成**房间可配**。
任一群点火 ⇒ 半径内同伴收到 1.5 s 警报刺激（`ally_alert`）⇒ 转 `alert` ⇒ 靠近后自己看到 ⇒ 再传播
⇒ **链式反应，全房围上**。

> 预激活半径只有 38 m，但玩家进房后到最远角落 ≈ 34 m ⇒ 一进门全房怪均已激活。

### 🔴 数量 20 → 18 是物理容量硬约束

本房真实可通行区**不是完整矩形**，而是一条横带。逐砖心扫描（`_scratch` 位置扫描探针）显示
`x ∈ [-12.5, 12.5] × z ∈ {-7.5, -2.5, 2.5}` 可用，**`z = ±7.5 / ±12.5` 整列容量 0**
（被家具 / 结构吃掉）。四角砖心**原地容量只有 2~4 只**：

| 盒型 | (-12.5,-7.5) | (12.5,-7.5) | (-12.5,2.5) | (12.5,2.5) | 中心 (2.5,-2.5) |
|---|---:|---:|---:|---:|---:|
| `box_room_spread` | 3 | 3 | 5 | 3 | **6** |
| `box_corner_ambush` | 2 | 3 | 3 | 2 | 2 |
| `box_wall_arc` | 3 | 4 | 4 | 2 | 3 |
| `box_corridor_column` | 2 | 3 | 4 | 3 | 4 |

⇒ 四角若沿用原基线的「全盒 ×2」会**越容量**，触发运行时「落地平移」
（实测漂移最大 **8.87 m**）并可能造成盒互叠（判据 I）。故只在**中心盒**（容量 6，唯一宽裕位）
与**西北角**保留 ×2，其余三盒回到盒资产原始量。
**组合不变**（仍是那 4 种盒，`room_spread` 用两次），房总 **20 → 18**。

**实测落地**（`probe_expedition01_box_capacity` 与 `probe_expedition01_wave_counts` 双向吻合）：

| # | 盒 | `cap_declared` | 实到 | 漂移 |
|---|---|---:|---:|---:|
| 0 | `room_spread` | 6 | 6 | **0.00** |
| 1 | `room_spread` | 3 | 3 | **0.00** |
| 2 | `corridor_column` | 3 | 3 | **0.00** |
| 3 | `wall_arc` | 4 | 4 | **0.00** |
| 4 | `corner_ambush` | 2 | 2 | **0.00** |

房总 18 只、`short = 0`、`trunc = 0`。

---

## 7. 掉落：40% 空掉落

`monster_drop_table.empty_chance = 0.4` —— 命中即本次击杀**什么都不掉**（连魂与弹药一并落空）。
掷签放在 `entries` 之前、与后续抽取**共用同一个 rng** ⇒ 同 seed 同结果、不新增随机流。

**补了一个覆盖盲区**：本表只登记 **3 / 6 种怪**（`melee_chaser` / `ranged_caster` / `exploder`）；
其余 3 种走 `MonsterInjector.drop_spec_for` 的**旧公式兜底**、够不着表级字段 ⇒ 本来吃不到空掉落。
已在 `RuntimeRewardCoordinator` 存一份概率随 kill 请求下发，在兜底路径补齐
⇒ **同关所有普通怪同一口径**（关卡级，不引入全局状态）。

**导出脚本兼容**：`empty_chance` 是**表级扩展键**，CSV 不承载。
`scripts/export_monster_drop_table.py` 已改为导出时**保留 JSON 里已有的、`expected_table` 不产出的键**
⇒ 既不抹掉手工配置，也不让 `--check` 误判漂移。

---

## 8. 验收（全部实测）

| 判据 | 结果 |
|---|---|
| 三只怪数值 | **350/18/3.5**、**800/35/1.5**、**hp 32000**（速度 3.612 未动）✅ |
| 未配置怪不受影响 | `ranged_caster` 129/9、`exploder` 113/28、`ambusher` 142/15、`summoner` 202/8 ✅ |
| AI 参数下发 | 每只怪均带 `monster_ai`；`room_02` 的 60 m 抵达运行时 ✅ |
| `room_02` 五群 | 5 盒 / 单波 / **五盒漂移全 0.00** / 实到 18 / 无截断 ✅ |
| 自爆（同房 2 m / 4 m） | 各 −180 ✅ |
| 自爆（同房 12 m / 跨房 2 m） | −0（超半径 / 同房过滤）✅ |
| 自爆（玩家 3 m / 自身） | −180 / 不自伤 ✅ |
| 自爆**级联** | 两个残血胖子互爆 ⇒ 双双 dead、进程不挂、无递归 ✅ |
| 空掉落率（4000×3） | `melee_chaser` 0.4098 / `ranged_caster` 0.3902 / `exploder` 0.3982（对照 0.0000）✅ |
| 掉落表导出 | `MONSTER_DROP_TABLE_CHECK_OK changed=0` ✅ |
| **塔楼对照** | `TOWER_RULES_EMPTY=true`、无 `override_*`、无 `monster_ai`；数值与改动前逐值一致 ✅ |
| `verify_expedition01_spawn_ramp` | `EXPEDITION01_SPAWN_RAMP_OK ramped_rooms=8` ✅ |
| 全关 `probe_expedition01_wave_counts` | `realized=170 / design_max=184 / trunc=5`（trunc 全在既有身份条目，room_02 `short=0`） |

### 8.1 三处**既有**问题（对照实验已证明与本轮无关）

做法：`git checkout HEAD -- floor_00.json` 还原数据后重跑，逐条复现。

| 现象 | 对照实验结论 |
|---|---|
| `verify_expedition01_spawn_ramp`：`boss#0` 漂移 11.07 / `#3` 4.81（快照写的是 `#1: 0.63`） | **原始数据同样复现** ⇒ 快照过期，已按门禁提示刷新 `PINNED_DRIFT` |
| `verify_level_plan_design_source`：`room_overlap:room_10:boss` / `boss:extraction` | **原始数据同样复现** ⇒ `floor_00.json` 的 `center_m`/`size_m` 本就重叠（文档说明该坐标只是兜底样例，非实跑几何） |
| 全关 `trunc=5` | 与本轮改动无关（`room_02` 自身 `short=0`） |

---

## 9. 改动文件

**代码（11）**：`MonsterInjector.gd` / `FloorPlanGenerator.gd` / `Dungeon3D.gd` / `TowerDescent3D.gd` /
`Enemy3D.gd` / `MonsterAIManager.gd` / `MonsterDropTable.gd` / `RewardService.gd` / `RewardSpec.gd` /
`RuntimeRewardCoordinator.gd`

**数据（2）**：`expedition_01/level_plan.json`（`monster_rules` + `empty_chance`）、
`expedition_01/floors/floor_00.json`（`room_02` 五群 + `encounter.monster_ai`）

**工具（1）**：`scripts/export_monster_drop_table.py`

**门禁（1）**：`tests/verification/verify_expedition01_spawn_ramp.gd`（同步 `room_02` 盒数 / 倍率契约、
刷新过期的 boss 漂移快照）

**文档（6）**：[远征关卡01设计](../design/远征关卡01设计.md) §4.5.2 / §4.5.2.1 / §4.5.3 / §10.4、
[触发器刷怪设计](../design/触发器刷怪设计.md) §3.3 / §3.2.3、
[胖子僵尸03运行配置](../design/胖子僵尸03运行配置.md)、
[怪物设计](../design/怪物设计.md)、
[01_内容数据库说明](../01_内容数据库说明.md) §5.3、
内容数据库《怪物与Boss》。

---

## 10. 未做 / 待办

1. **剩余 9 间房**尚未调（业主口径「一间间房间进行调整」，目前只做了 `room_02`）。
2. **自爆观感未经真机确认**：沿用 `VFX-EXPLOSION-3D`、size 取 2.6（比炸弹果的 1.75 大）。
   若观感不对，需按 [14.6 特效系统与制作规范](../14.6_特效系统与制作规范.md) 单独做一版。
3. `enemy_spawn_plan` 的旧代码仍在（`MonsterInjector.build_waves_from_plan`），属 P4 待办。
4. 掉落表的 `empty_chance` 目前只对远征01 生效；远征02 若也要同口径需各自配置。
5. `room_08` 第 5 盒（`box_room_spread` @ `[-5.0, 12.5]`）实测**容量 0 / 漂移 20.00 m**，属既有缺陷未处理。
6. 自爆半径 5.0 m 为默认值（业主只指定伤害 180）。

---

## 11. 追加（同日第四轮）：警察僵尸数值 + 弹药豁免空掉落 + 货币独立通道

- **业主口径**：*「警察僵尸的HP改成250 伤害改成30，80%概率掉落一个普通弹药，同时会掉落货币，
  所有击败的怪物都会掉落货币，这个不算在物品掉落里头……货币会有多少区分，越多的货币，模型越大。」*
- **两个澄清**（业主已回答）：①「一个普通弹药」= **1 包** `item_ammo_pack`（30-50 发）；
  ② 货币分档 = **按怪种 + 楼层**；③ 物品仍保留 40% 空掉落。

### 11.1 🔴 本轮最值钱的发现：80% 被空掉落打成了 47%

`empty_chance = 0.4` 的掷签在 `entries` **之前**，命中即整体落空 —— **连弹药一起吃**。
于是「80% 掉弹药」实际只有 **0.4703**（= 0.8 × 0.6）。隔离实测（各 4000 次，摘掉/保留 `empty_chance`）：

| 怪 | 摘掉空掉落 | 当前（带 40% 空） |
|---|---:|---:|
| `ranged_caster` 弹药率 | **0.8047** | **0.4703** ← 业主指定的 80% 不成立 |
| `melee_chaser` 弹药率 | 0.3440 | 0.2117 |
| `exploder` 弹药率 | 0.3350 | 0.2000 |

> **教训**：上一轮我把 `empty_chance` 定成「连魂与弹药一并落空」，是按当时「40% 什么都不掉」的口径。
> 本轮业主给出**明确数字**（80%）后，两条口径就冲突了。
> **给「降低整体掉落」这类诉求加实现时，要预判它会不会吃掉同一表里别人指定过的具体概率**；
> 我的疏漏是回答「是否保留 40% 空」时没指出这一点。

### 11.2 弹药豁免空掉落

业主裁定「弹药豁免」。实现：

- `RewardSpec.is_empty_exempt_item(item_id)` —— 按物品 **tag `ammo`** 认定（**唯一真源**），
  新增弹药物品自动继承，不必逐条记得加标记。
- 编译层在弹药条目上写 `exempt_from_empty: true`
  （`MonsterDropTable._row_to_entry` 与 `MonsterInjector.drop_spec_for` 两处）。
- 解析层 `RewardService.resolve`：空掉落命中时**只解析豁免条目**（`_empty_exempt_entries`），
  装备类整批落空；且**空掉落命中时不走 `fallback`** —— 否则「空」会被回退池又填满。
- **实测**：警察僵尸 **0.7920** ✅（豁免前 0.4703）；小僵尸 0.3453、炸弹果 0.3468（各自指定概率）；
  装备类仍被降低（炸弹果「有物品」1.0000 → **0.7210**）。

### 11.3 货币独立通道

**关键事实**：货币**原本就在物品掉落表里**（`@currency:extraction_points`、公式 `2+floor*1`、
备注写着「必掉·公式」）—— 与 `empty_chance` 直接冲突，40% 的击杀**连魂都不掉**，「必掉」名存实亡。

| | 物品掉落 | 货币通道 |
|---|---|---|
| 归属 | `monster_drop_table.rows` | `monster_rules.currency`（关卡级） |
| 概率 | 各自 chance，受 `empty_chance` 影响 | **100% 必掉**，不受任何空判定影响 |
| 件数 | 占物品件数 | **不占**物品件数 |
| 实现 | `RewardService._monster_spec_for` | `RewardService.currency_spec_for` + `RuntimeRewardCoordinator._append_level_currency` |

- **表里的 3 条 `@currency:` 行已删**（货币不再属于物品表），改由独立通道供给。
- **摘除防重**：关卡配了 `monster_rules.currency` 时，物品规格里的货币条目会被
  `_drop_currency_entries` 摘掉 —— 否则会**重复发放**。未配置该段的关卡（塔楼等）不摘、不追加。
- **分档**（业主「按怪种 + 楼层」）：`per_tier` > `per_kind` > `default`，值 = `round(base + per_floor × floor)`。
  `melee_chaser` 4+1/级、`ranged_caster` 7+1、`exploder` 8+2、`ambusher` 8+2、`summoner` 12+3、
  `fat_zombie03` 20+4、elite 50+20、boss 200+20、default 4+1。
- **实测**：6 种怪 × 800 次**全部 1.0000**；金额 5 / **8** / 10 / 10 / 15 / 24 与分档精确吻合；
  警察僵尸 floor 1/3/7 → **8 / 10 / 14**（随楼层增长）。

### 11.4 货币模型随数量放大

`GroundLootPickup3D.CURRENCY_SCALE_TIERS`（**唯一真源**，运行时与验收场景都调
`size_scale_for_stack()`）：`<10 → 0.85` / `10–29 → 1.10` / `30–79 → 1.45` / `≥80 → 1.85`。
非货币恒 1.0（堆叠数量不改模型大小）。实测真实实例 `visual_scale`：count 3 → **0.428**、
40 → **0.731**、220 → **0.932**（基础倍率 0.72 × 0.70 = 0.504 起算）。

### 11.5 验收

| 判据 | 结果 |
|---|---|
| 警察僵尸 `ranged_caster` | **hp 250 / 伤害 30**（速度 1.458 未动）✅ |
| 其余怪未受影响 | 小僵尸 350/18/3.5、胖子 800/35/1.5 ✅ |
| 弹药 80% | **0.7920** ✅ |
| 货币 100% 必掉 | 6 种怪全 **1.0000** ✅ |
| 货币分档 | 5/8/10/10/15/24 精确吻合 ✅ |
| 货币模型放大 | 0.85 / 1.10 / 1.45 / 1.85 ✅ |
| **塔楼对照** | `configure_level_currency({})` ⇒ 不追加、不摘；200 次击杀恰好 200 个货币 grant（**不重复**）✅ |
| 掉落表导出一致性 | `MONSTER_DROP_TABLE_CHECK_OK rows=13 changed=0` ✅ |
| `verify_expedition01_spawn_ramp` | `EXPEDITION01_SPAWN_RAMP_OK ramped_rooms=8` ✅ |
| `verify_reward_ground_handoff` | ✅（含「currency multiplier」用例，既有货币逻辑未破）|
| `check_feature_traceability` | `FEATURE_TRACEABILITY_OK features=37` ✅ |

### 11.6 ⚠️ 一处**既有**失败（已证明与本轮无关）

`verify_reward_service_flow` 报 4 条 ERROR，全部围绕 `enemy_type = "shielded"`：

- 「表未写的怪必须走旧公式兜底」/「普通怪的兜底公式必须带备弹条目」/
  「运行链必须真的产出 30 发档的备弹加成，实测样本 0」/「普通怪备弹已由 3–8 上调为 30–50」

**对照实验（决定性）**：

| 证据 | 结果 |
|---|---|
| `git show HEAD:src/map/MonsterInjector.gd \| grep -c shielded` | **0** —— HEAD 版就没有 `shielded` |
| HEAD 版 `BASE_ENEMY_TYPES` vs 工作区版 | **逐字节完全一致**（我只 +36/−0，没删任何东西）|
| HEAD 版 `drop_spec_for` 守卫（第 588-589 行） | `if not BASE_ENEMY_TYPES.has(monster_id): return {}` |
| 测试文件相对 HEAD | **未改** |

⇒ `drop_spec_for("shielded", ...)` 在 HEAD 上**同样返回 `{}`**。
根因：壳甲卫兵 2026-10-03 退役（`shielded` 从 `BASE_ENEMY_TYPES` 移除），
但 `verify_reward_service_flow` 没跟着更新 ⇒ **该用例在 HEAD 上就是红的**。
修它需要把用例里的 `shielded` 换成现役怪种（属独立工作单元，本轮未动）。

### 11.7 改动文件（第四轮）

**代码（6）**：`src/rewards/RewardSpec.gd`（`is_empty_exempt_item`）、
`src/rewards/RewardService.gd`（豁免过滤 / `currency_spec_for` / `_currency_amount_for` / `_drop_currency_entries`）、
`src/rewards/MonsterDropTable.gd`（弹药标记）、`src/rewards/RuntimeRewardCoordinator.gd`（货币通道）、
`src/map/MonsterInjector.gd`（弹药标记）、`src/world3d/GroundLootPickup3D.gd`（模型放大）、
`src/world3d/Dungeon3D.gd` + `src/world3d/TowerDescent3D.gd`（转发货币分档）

**数据（2）**：`expedition_01/level_plan.json`（`stats.per_kind.ranged_caster` + `currency` + 删 3 条 `@currency:` 行 + 弹药 80%）、
`docs/v0.1/data/怪物掉落表_地图x怪物.csv`（同步：删 3 行 + 孢子射手弹药 34%→80%）

**文档（4）**：[远征关卡01设计](../design/远征关卡01设计.md) §4.5.3 / §10.4、
[01_内容数据库说明](../01_内容数据库说明.md) §5.3、本文件、内容数据库《怪物与Boss》（表头 + r9）。

### 11.8 🔴 收尾时发现的**机制级**坑：改的是投影，不是源

本轮结束后做「临时文件清理 + 改动清单」时，发现 `art_source/design/whitebox/tower_zones/expedition_01/v001/data/level_plan.json`
也在改动列表里 —— 顺着查，发现一条**影响前四轮全部改动持久性**的事实：

```
scripts/sync_runtime_design_data.py 的 mappings():
    level_root = art_source/design/whitebox/tower_zones
    version = v004 if battle_level01 else v001
    source = level_root/<level>/<version>/data
    → ROOT/data/level_plans/<level>/...
脚本注释： "Design files remain authoritative. --check verifies byte-identical projections."
```

| | 路径 | 角色 |
|---|---|---|
| **源（权威）** | `art_source/design/whitebox/tower_zones/expedition_01/v001/data/**` | 设计真源 |
| 投影（运行时读） | `data/level_plans/expedition_01/**` | 由源生成；`--check` 要求与源**逐字节一致** |

**前四轮我全部只改了投影** ⇒ 功能当下能跑（运行时确实读投影，探针全绿是真的），
但**不可持久** —— 下一次 sync 写模式会把投影覆盖回源的内容，四轮改动会一起消失。
而且 `sync_runtime_design_data.py --check` 正是**验收套件的前置门禁**，
一旦它报 `projection drift`，套件连场景都跑不到。

**还有一条方向相反的坑**：`scripts/export_monster_drop_table.py` 的
`LEVEL_ROOT = art_source/design/whitebox/tower_zones` ⇒ 它把 CSV 派生的
`monster_drop_table` 写进**源**。于是本轮出现过一个**来回覆盖**：
1. 我改投影的 rows（删 3 条 `@currency:` 行、弹药 34%→80%）
2. 改 CSV → 跑 `export` ⇒ 它把**源**的 `monster_drop_table` 更新对了（含正确答案的 `rows_sha256`）
3. 我为了「落到源」执行 `cp 投影 → 源` ⇒ **把源里正确的 sha 覆盖成投影里过期的 sha**（`fe6e73…`）
4. `export --check` 随即报 `monster_drop_table drift` —— 才暴露第 3 步是错的

**正确顺序（已写进设计页 §10.4.0）**：
1. 改 CSV → 2. `export_monster_drop_table.py`（写**源**）→ 3. 改源的 `level_plan.json` / `floor_00.json`
→ 4. **源 → 投影**同步 → 5. `export --check` ＋ `sync --check` 双绿

**收尾实际做的**：
- `export_monster_drop_table.py`（写模式）→ 源 `rows_sha256` 修正为 `fc1aab84…`，`monster_rules` / `empty_chance` 保留 ✅
- `cp 源 → 投影`（**这个方向才对**）⇒ `level_plan.json` 与 `floors/floor_00.json` 源/投影**逐字节一致**
- 结果：`export --check` **OK changed=0**；`sync --check` 的 expedition_01 文件 drift **清零**

**剩下的两条 drift 都不是本轮的**（已用对照证明）：
| 现象 | 归属 |
|---|---|
| `room_templates/boss_50x40.json` 源≠投影 | **前人**：源相对 HEAD 未改、投影相对 HEAD 也未改 ⇒ **两者在 HEAD 上就不一致**（那次「南进」裁定的 note 只落进了投影） |
| `projection manifest drift` | **既有系统性陈旧**：manifest 40 条里 **39 条**对不上（记录的既非当前源也非当前投影）⇒ 不是本轮 2 条能造成的 |
| 且**未重建 manifest** | 按本仓既有先例「**不为过门禁重写欠账快照**」；且写模式会**重生成全部投影**，会拿落后的源覆盖 `boss_50x40` 投影、破坏前人改动 |

> **给后人的两条硬事实**：
> 1. 动 `data/level_plans/expedition_01/**` 之前，先问自己「源改了没有」——
>    只改投影 = 迟早被 sync 吃掉。
> 2. 两个脚本的**目标方向相反**：`sync` 是 源→投影，`export_monster_drop_table` 是 **CSV→源**。
>    混用容易做出「来回覆盖」，症状是 `--check` 报同一个文件 drift 却怎么也修不好。
---

## 12. 追加（同日第五轮）：死亡自爆特效 ＋ 地面持续伤害场（FX01-17 / FX01-18）

- **业主口径**：*「胖子僵尸被打死后自爆没有特效，需要增加一个，并且在地上留一个持续伤害的范围效果，
  持续3秒，这个特效要记录到特效账本中，并且更新相关设计文档。」*
- 前一版自爆只有伤害、没有专属表现（`_detonate_death_explosion()` 借用通用的 `VFX-EXPLOSION-3D`，
  而那是 0.46s／核心 0.42m／无灯的「弹药类小爆点」）。本轮把它补成一整套。
- 逐文件台账见 `ShellStorm2-work/sessions/2026-10-14_expedition01_monster_spawn/改动记录_第一轮.md` §14。

### 12.1 交付物（两个 Prefab ＋ 一个玩法节点）

| 层 | 资产 / 节点 | AssetID | lifetime | 归属 |
|---|---|---|---|---|
| 爆炸视觉 | `assets/art/vfx/combat_3d/vfx_death_blast_root_top3d.tscn` ＋ `src/vfx/VfxDeathBlast3D.gd` | `VFX-DEATH-BLAST-3D`（FX01-17） | 0.62 s | 走 `VfxPool3D`（`FX01_DEATH_BLAST`） |
| 地面场视觉 | `assets/art/vfx/combat_3d/vfx_blast_zone_root_top3d.tscn` ＋ `src/vfx/VfxBlastZone3D.gd` | `VFX-BLAST-ZONE-3D`（FX01-18） | ＝ 场地时长（3.0 s） | 宿主自持，**不进池** |
| 地面场结算 | `src/enemy3d/DeathBlastZone3D.gd` | — | 3.0 s | 自持，到点 `queue_free()` |

调用方只有一处扩展：`Enemy3D._detonate_death_explosion()` 换用新 Prefab、并在结算完爆炸后调
`_spawn_ground_blast_zone(radius)`；规格读 `monster_rules.death_explosion.<kind>.zone`。

### 12.2 三条设计判断

1. **另做一份爆炸，不复用 FX01-03。** FX01-03 是通用／弹药类小爆点（0.46s、核心 0.42m、无灯）；
   胖子僵尸是 2.2 m 大体位怪、伤害半径 5 m，需要更大的体积、更长的余韵和一盏瞬时照明。
2. **伤害不写进 Prefab。** 14.6 §1「Prefab 是特效的唯一出口」+「特效 Prefab 内禁碰撞体（纯视觉）」⇒
   地面场拆成「视觉 Prefab（FX01-18）」＋「玩法节点（`DeathBlastZone3D`）」两层。
3. **尺寸跟规格半径走，不写死。** 调用方传 `size = radius × 0.6` ⇒ 5.0 m ⇒ `size 3.0`
   ⇒ 内环外缘 `0.72 × 3.0 × 2.20 ≈ 4.75 m`、外环 `× 2.45 ≈ 5.29 m`（视觉顶到伤害半径）。
   改 `radius_m` 时观感自动跟随，不会「伤害改了、爆炸还是原来大小」。

### 12.3 🔴 三条实测踩到的坑（每条都留了断言 / 反向对照）

| # | 坑 | 症状 | 修法 |
|---|---|---|---|
| ① | 场地**首跳排在 t=0** | 死亡当帧已经结算过一次 180 的爆炸，同帧再打 ⇒ **双倍命中** | `_next_tick` 初值 = `tick_interval`（0.5 s） |
| ② | 跳数**没有时间上界** | 只写 `while _elapsed >= _next_tick` 时，**一帧跨过末尾**会把场外时间也拿去结算（实测跳数 6 → 8） | 加 `and _next_tick <= zone_duration + TICK_EPSILON` |
| ③ | 场地视觉的**朝向** | 圆环的环轴是 Y ⇒ 天然躺在 XZ；若跟着怪做旋转，整片场地会**竖起来** | 契约：调用方在**地面高度** activate 且**不旋转**；验收有平铺断言 + 倾斜 90° 反向对照 |

> ②是我自己在验收里被数字抓出来的（断言写 `ticks == 6`，实测 8）。**先写死期望值再让代码去对**，
> 比我「觉得对」可靠得多。

### 12.4 反向对照纪律（四项，实跑）

| 对照 | 期望 | 实测红值 | 数值自洽性 |
|---|---|---|---|
| A 把 `activate_zone` 的首跳改成 `t=0` | 「首跳不在 t=0」变红 | `1 跳已结算` + `t=0.1 就命中` + `notify_attacked_by 调用 2 次` | 一跳即命中 ✅ |
| B 取消同房过滤（保留声明、不填 room_id） | 「跨房敌人不该被命中」变红 | `跨房 2m 敌人被命中 [24]` | 24 = `damage_per_tick` ✅ |
| C 外环 `RING2_SCALE_END: 2.45 → 3.50` | 「冲击环外缘 4.4~5.5 m」变红 | `7.560` | 0.72 × 3.0 × 3.50 = **7.5600** 精确 ✅ |
| D 去掉跳数上界 | 「跳数 == 6」变红 | `8` | 与 12.3 ② 的实测一致 ✅ |

还原后 `DEATH_BLAST_VFX_OK ... samples=12` 复绿；`grep -rn "REVERSE-CONTROL" src/` 为空。

⛔ **中途踩到的对照陷阱（值得记）**：B 组第一次我直接删掉了 `var room_filter` 声明 ⇒ 编译失败
⇒ 红的原因是「整个脚本加载不了」（表现为「端到端失效：Enemy3D 未把地面场地生成到场景里」），
**不是判据本身变红**。改法是**保留声明、只让 `if` 不成立**（`if false:`），这样对照才落在判据上。
⇒ **判「红」要看红在哪一句**，别只看「有没有红」。

### 12.5 账本与门禁

- 特效账本（`assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx`）：
  《资产主表》r36/r37（含 R/S 派生公式按新行号重算 + `COUNTIF` 范围扩到 `$37`）、
  资产主表 DV 范围 `C/K/L` 同步扩、3D-特效 r36 分组头 + r37/r38 两条、r2 摘要（23 → 25 条 + 进度）、
  《总览》8 个统计格 `$35 → $37`、《域变更日志》r23 `v0.1.17`。
- 改动范围核验：**恰好 129 格变化**（其中 42 格是预期的派生公式重算），
  DV / merged / zip 部件（15 → 15）**零变化**。
- `scripts/check_asset_registry.py --ledger vfx` → `asset_count 30 → 32`，**本轮两行零 issue**。
- `verify_death_blast_vfx` 登记进 `scripts/run_verification_suite.sh` 的 `core_scenes`。

### 12.6 ⚠️ 既有欠账（对照已定性，与本轮无关）

| 现象 | 归因与证据 |
|---|---|
| 账本 14 条 `sha_mismatch`（r17–r21、r26–r34） | **既有系统性口径差**：那些行记录的是**LF 归一后**的 sha，而工作区文件是 **CRLF**，门禁 `_sha256()` 比的是**原始字节**。取 r21 验证：记录 `a19f4266…` **精确等于** `sha256(文件字节.replace(b'\r\n', b'\n'))` ✅。本轮两行按**原始字节**记录 ⇒ 零 issue |
| `src/world3d/Dungeon3D.gd` 解析失败（`Function "_fate_greyscale_material" has the same name as a previously declared variable`） | **并发会话**的 WIP：`git show HEAD:src/world3d/Dungeon3D.gd \| grep -c _fate_greyscale_material` = **0**（HEAD 根本没有该符号），而工作区该文件相对 HEAD 有 **+441/−73**（我一行未碰） |
| `verify_death_blast_vfx` 首跑「假死」7 分钟不退出 | **验收场景自身的写法问题**：全用例串在 `_ready()` 里，一处 `Parse Error`（我误用了不存在的常量名 `BLAST_LIFETIME`）会**中断 `_ready`** ⇒ `_report()` 不执行 ⇒ headless 场景永远挂着。**已改为「每帧推进一步」**：单步报错只影响那一帧，收尾报告照常执行 |

### 12.7 本轮改动文件清单

**新增代码（3）**：`src/vfx/VfxDeathBlast3D.gd`、`src/vfx/VfxBlastZone3D.gd`、`src/enemy3d/DeathBlastZone3D.gd`
**新增资产（2）**：`assets/art/vfx/combat_3d/vfx_death_blast_root_top3d.tscn`、`.../vfx_blast_zone_root_top3d.tscn`
**新增验收（2）**：`tests/verification/verify_death_blast_vfx.gd` / `.tscn`
**改动代码（3）**：`src/vfx/VfxPool3D.gd`（`FX01_DEATH_BLAST` + 注册）、
`src/enemy3d/Enemy3D.gd`（换 Prefab + `_spawn_ground_blast_zone`）、`scripts/run_verification_suite.sh`（登记）
**改动数据（2）**：`art_source/.../expedition_01/v001/data/level_plan.json`（**权威源**，`death_explosion.fat_zombie03.zone`）
＋ 同步投影 `data/level_plans/expedition_01/level_plan.json`
**改动账本（1）**：`assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx`
**改动文档（5）**：`14.6_特效系统与制作规范.md`、`design/远征关卡01设计.md`、`MODULE_INDEX.md`、
`development/CHANGELOG.md`、本文件
