# 出厂枪换回豌豆手枪 · 弹速换尺子 · 远征03 弹体放大与弹速定锚

- 日期：2026-10-30（当日第二轮，接上午的 `2026-10-30_pistol_egt_marine_alignment.md`）
- 触发：业主四句原话
  1. 「初始武器从步枪改成豌豆手枪」
  2. 「豌豆手枪的那个子弹速度调慢了，对标挺进地牢的陆战队的那把枪的速度」
  3. 「子弹特效那个出去那个模型，帮我放大一倍」
  4. 「怪物的子弹大小也放大一倍，怪物的子弹速度也去对标挺进地牢的怪物的子弹速度，要 1:1 匹配……我说的怪物是远征 03 的怪物，其他怪物不要修改」
- 影响文件：`src/base/BlueprintRegistry.gd`、`src/combat3d/WeaponModel3D.gd`、
  `src/combat3d/Projectile3D.gd`、`src/enemy3d/Enemy3D.gd`、`src/map/MonsterInjector.gd`、
  `data/narrative/nar_tower_opening_01_wake.json`、
  `data/level_plans/expedition_03/level_plan.json`、`tools/retune_egt_monsters.py`、
  新增 `tools/_egt_enemy_projectile_look_probe.gd/.tscn`、6 个验收脚本、内容数据库《武器》表、
  [04 §6.1](../04_技术施工_战斗与局内成长.md)、[怪物设计 §T2.5](../design/怪物设计.md)、
  [远征关卡03设计](../design/远征关卡03设计.md)、[初始手枪参考页](../reference/挺进地牢/初始手枪数据.md)

---

## 1. 初始武器：改的是一个常量，牵连的是三件事

`BlueprintRegistry.DEFAULT_STARTING_GUN_ID`：`bp_starter_rifle` → **`bp_pistol`**。

⚠ 但「新档首局的地面枪」**不在**这个常量里 —— 它是剧本 `nar_tower_opening_01_wake` 的
`scene.spawn_item`（`TowerDescent3D._clear_new_game_opening_loadout()` 会先收回白送的枪）。
只改常量，新档拿到的仍是旧枪，而且**不会报错**。两处必须同改，这一条本来就写在常量注释里。

三个连带项，逐条说清哪些是必然、哪些是选择：

| 项 | 改前 | 改后 | 性质 |
|---|---|---|---|
| 持枪移速惩罚 | `longgun` 0.8 m/s | `sidearm` **0.5 m/s** | **必然**：惩罚按枪族取，换族就变。新档持枪移速 3.7 → 4.0 m/s |
| 命运槽容量 | 4（前任出厂枪硬砍） | **8**（默认） | **选择**：豌豆手枪是同一 item id 的合成/掉落内容，砍槽会连带改掉落价值 |
| 初始步枪本体 | 出厂枪 | 仍是正式内容（tier0 / 掉落保留） | 换指针不删内容，`_check_retired_factory_guns()` 盯着 |

> 命运槽那条留给业主拍板：要收回成 4，得先把「白送实例」与「掉落实例」拆成两套口径，
> 否则砍的是整个 `weapon_pistol` 内容。

---

## 2. 核心错误：把原作的「单位」当成「米」

上午那版把 `Marine Sidearm` 的 `Shot Speed 25` 直接写成 `25 m/s`（倍率 `25/23`），
业主上手仍说「偏快」。**快 44% 的原因不是手感，是单位。**

```
原作玩家移速 6.5 单位/秒（第一层怪物数据表 §8.1，EnemyAPI 反编译量级）
本作玩家移速 4.5 m/s（Player3D.SPEED）
⇒ 1 原作单位 = 4.5 / 6.5 = 0.6923 m
⇒ Marine Sidearm 25 单位/秒 = 25 × 0.6923 = 17.31 m/s
```

落地：

```gdscript
const EGT_UNIT_TO_METER := 4.5 / 6.5        # ≈ 0.6923
const PISTOL_EGT_SHOT_SPEED := 25.0
"bullet_speed": PISTOL_EGT_SHOT_SPEED * EGT_UNIT_TO_METER / 23.0   # ≈ 0.7525
```

枪身只声明**倍率**（`23 × 倍率 × 弹种倍率 × 命运倍率`），不写 m/s —— 这是 §6.1 既有口径。
射程 15 m 不动，飞行时间从 0.60 s 变成 **0.87 s**。

> 反例，别混用：**敌人**弹速这一轮走的是另一套（见 §4），直接取 `Speed(6)` 的数值、**不乘** 0.6923。
> 业主对敌人点的是「数值 1:1」，对玩家枪点的是「手感对标」，两个要求不是一回事。

---

## 3. 弹体视觉 ×2：撞上「手枪 = 中性档」这个隐含约定

`WeaponModel3D.BULLET_GEOMETRY_BY_GUN_TAG` 原本的隐含语义是「**手枪 = 1.00 基准**，
其余枪族都是它相对倍数」（表里注释、验收脚本的注释、相对判据都这么写）。

手枪自己变成 2.00 之后，这张表的序关系当场崩了：

| 枪族 | 改前（相对手枪） | 改后（相对中性 1.00） |
|---|---:|---:|
| 手枪 | 1.00（= 基准） | **2.00** |
| 霰弹 | 2.00 | 2.00（**与手枪打平**） |
| 榴弹 | 1.55 | 1.55（**比手枪小**） |
| 狙击 | 0.95 | 0.95 |

处理方式：**中性档退回常量** `BULLET_GEOMETRY_NEUTRAL`，验收脚本的相对判据分母由「手枪」改为
`NEUTRAL_SCALE = 1.00`，并新增一条正面断言 `bp_pistol ≈ 2.00`。

- 纯视觉：`_collision_scale_factor()` 刻意不含枪身档位，判定仍 0.12 m（`verify_bullet_vfx_profiles` 有断言）。
- **副作用，业主已知悉**：本轮只改手枪，所以霰弹与手枪打平、榴弹比手枪小。
  要恢复「霰弹 > 榴弹 > 手枪 > 中性」的序关系，把 `shotgun 4.0 / launcher 3.1 / sniper 1.9`
  （同步 ×2）写进同一张表即可 —— 一处改动，不碰判定。

---

## 4. 远征03 弹速：把「1:1」定义清楚才有数

原作**没有公开的米/秒**（wiki 只给 `fast-moving` 这类相对词，EnemyAPI 只给字段名不给换算）。
第三轮的 `8 / 10 / 6` 是「可躲性反推」的结果 —— 那是个**判据**，不是原作事实。

这一轮业主点名「1:1 匹配」，于是换成唯一一个反编译实锤当锚：

| 档 | 第三轮 | **第四轮** | 依据 |
|---|---:|---:|---|
| 基准（28 只） | 8.0 | **6.0** | `new Speed(6f, SpeedType.Absolute)` |
| fast-moving（3 只） | 10.0 | **7.5** | 基准 ×1.25，保留「fast」的相对关系 |
| 慢弹（弹跳 / 追踪） | 6.0 | **4.5** | 基准 ×0.75，追踪 + 高速 = 无解 |
| 吉吉的蛋 | 4.2 | **3.15** | 蛋要慢慢飞才读得出「蛋」 |
| 链球（orbit） | 6.4 | **4.8** | ×0.75 |
| 红衣主教追踪弹簇 | 5.2 | **3.9** | ×0.75 |
| 枪坚果 jammed 大弹 / 碎片 | 6.5 / 6.0 | **4.875 / 4.5** | ×0.75 |

**全域 ×0.75（= 6/8），序关系一条不动** —— 谁比谁快、谁站着不动，逐条保留。
可躲性只会更好：8 m/s 时 8 m 处可横移 3.38 m，6 m/s 时是 4.88 m（扇形半宽 1.99 m）。

门禁下限跟着改：`_egt_bullet_visual_probe` 的「< 6 会读成静止飘浮」降到 **4.0**
（不降则基准档自己判红）。`_egt_dodgeability_probe` 18 只全绿。

### 生成器的一个坑（记录在案）

`tools/retune_egt_monsters.py` 的契约是「把 `hp` 那一行替换成 `stat + projectile_speed` 两行」，
但这张表里 `projectile_speed` **本来就独立成行** ⇒ 直接 `--apply` 会写出**重复键**
（GDScript 字典字面量重复键不报错，只取后者 = 旧值，表现是「改了没生效」）。
本轮落盘后按「相邻两行 `"projectile_speed"` 只留第一行」清理了 33 处；
再跑这个工具前先 `--dry-run` 看它到底插了几行。

---

## 5. 敌弹放大：一条跨四层的隐形契约

```
level_plan.json  monster_rules.projectile.visual_scale = 2.0
  → MonsterInjector._projectile_look_overrides()   # 只在配了本段的关卡产出键
  → 怪物 config  projectile_visual_scale
  → Enemy3D._projectile_visual_scale（每只怪一份）
  → 每发 config  visual_scale
  → Projectile3D.visual_scale → _visual_scale_factor()
  → VfxBulletVisual3D._base_scale
```

三个刻意的选择：

1. **只放视觉，不动判定**。判定球恒 0.12 m：放大判定等于顺手把远征03 变难、
   还会把可躲性判据一起改掉。弹幕游戏的通行做法就是「看得见的大、判定小」。
2. **`configure()` 逐发重取 `visual_scale`**（与 `gun_bullet_geometry` 同规则）：
   对象池复借时不重取，会把上一只怪的放大档带到下一发上 —— 不报错、只表现为"某些子弹突然变大"。
3. **弹速不搬进关卡表**。`projectile` 段只放「这一关看起来怎么样」；
   速度住在怪种级的 `Enemy3D.PROFILES`，免得同一只怪在两张表里各有一份速度、迟早漂移。

新增门禁 `tools/_egt_enemy_projectile_look_probe.gd`，五层逐层断言 + 中性档对照：

```
EGT_PROJECTILE_LOOK_PROBE_OK 远征03 敌弹视觉 ×2.0 已贯通「关卡→注入器→怪→弹」四层，
判定半径仍 0.12 m；其余关卡保持中性档
```

> 写这条探针时踩了一次：`MonsterInjector` 是 `RefCounted` 不是 `Node`，`add_child()` 是**解析期**错误，
> 整份脚本加载失败 ⇒ 场景永远不会 `quit()` ⇒ headless 挂死（表现为"跑了几分钟没输出"）。
> 以后跑探针一律带 `--quit-after`，卡住时至少能看到解析错误。

---

## 6. 换枪波及的断言（六处，逐条说明为什么必须改）

| 文件 | 原来钉的是 | 现在钉的是 |
|---|---|---|
| `verify_starting_weapon_contract` | 初始步枪：50 伤 / 30 发 / 120 价 / 命运槽 4 / 槽位与步枪同套 | 豌豆手枪：25 伤 / 10 发 / 70 价 / 命运槽 8 / 手枪 4 槽 + 槽名必须是合法名 + 步枪 6 槽不被改坏 |
| 同上 `_check_pistol_egt_baseline` | 倍率 `25/23`、实际 25 m/s | 倍率 **0.7525**、实际 **17.31 m/s**（三层：枪身 / 装配树 / `WeaponModel3D`） |
| 同上 `_check_retired_factory_guns` | 原型枪 + 花洒机枪 | 再补一条 **`bp_starter_rifle`**（前任出厂枪） |
| `verify_new_save_handoff` | `ITEM_ID = weapon_starter_rifle` | `weapon_pistol` |
| `verify_opening_script_runtime` | 地面枪 = `weapon_starter_rifle`（3 处） | `weapon_pistol` |
| `verify_fate_character_completion` | 隐者移速按 `longgun` 0.8 算 | 按 `sidearm` **0.5** 算 |
| `verify_bullet_vfx_profiles` | 手枪 = 中性 1.00，其余相对手枪 | 手枪 = **2.00**，相对判据的分母改中性 1.00 |

---

## 7. 回归与反向验证

| 场景 | 结果 |
|---|---|
| `verify_starting_weapon_contract` | **绿**（`STARTING_WEAPON_CONTRACT_OK`，出厂枪 豌豆手枪 / 10 发 / 25 伤 / 命运槽 8） |
| `verify_bullet_vfx_profiles` | **绿**（samples=69，含 `pistol ≈ 2.00`、霰弹 2.00、榴弹 >1.30、判定仍 0.12） |
| `_egt_bullet_visual_probe` | **绿**（33 只：有弹、有视觉、有射程、弹速 ≥ 4.0） |
| `_egt_dodgeability_probe` | **绿**（18 只会开火的怪，窄弹走位可躲 / 宽扇形翻滚可躲） |
| `_egt_monster_registry_probe` | **绿**（33 种 × 九个注册点） |
| `_egt_enemy_projectile_look_probe` | **绿**（新增，四层贯通 + 判定不变 + 其它关卡中性） |
| `verify_new_save_handoff` | **绿** |
| `probe_death_return_loadout` | **绿**（按 `DEFAULT_STARTING_GUN_ID` 取，自动跟随） |
| `verify_synthesis_catalog` / `verify_weapon_instance_contract_matrix` / `verify_bullet_module_equipment_flow` / `verify_3d_reload_state_flow` | **绿** |

**既有红项（已证与本次无关，改前改后逐条同文）**：

| 场景 | 红项 | 怎么证的 |
|---|---|---|
| `verify_opening_script_runtime` | 4 条（会议室第二段剧情不触发 / 手电提示 3 条） | 把 `DEFAULT_STARTING_GUN_ID` 与剧本 `item_id` 一起改回旧值重跑，同样 4 条 |
| `verify_fate_character_completion` | 3 条（`启动前隔离APPDATA` / `启动前隔离LOCALAPPDATA` / `失败不消耗命运槽`） | 改回旧出厂枪重跑，同样 3 条（外加我新加的 4 条移速断言，那是预期内） |
| `verify_3d_inventory_weapon_flow` | 12 条（headless 下 SubViewport 96×96 投影预算） | 与上午那轮的记录逐条同文 |

**反向验证**（证明门禁真的会红，不是摆设）：
把 `DEFAULT_STARTING_GUN_ID` 改回 `bp_starter_rifle` ⇒ 隐者移速 2 条 + 出厂枪身份 1 条立刻报红；
把 `pistol` 档从表里删掉 ⇒ `verify_bullet_vfx_profiles` 的 `pistol ≈ 2.00` 报红；
把 `monster_rules.projectile` 段删掉 ⇒ `_egt_enemy_projectile_look_probe` 报「敌弹不会放大」。

---

## 8. 未做 / 留给后面的

- **其它枪族的弹体尺寸没跟着 ×2**，所以霰弹与手枪打平、榴弹比手枪小（见 §3）。
- **其它枪的弹速没换尺子**：仍按 23 m/s 基准，于是手枪 17.31 现在是全枪最慢。
  要不要把「原作单位 → 米」推广到全部枪身，是一次平衡决定，业主没点。
- **出厂枪的命运槽**：本轮沿用默认 8，未收回成 4（见 §1）。
- **Boss 的弹道**没单独验证是否吃 `projectile.visual_scale`（`MonsterInjector` 三条合并路径都带了，
  但远征03 的 Boss 是否走 `_fire_projectile` 未逐一核）。
