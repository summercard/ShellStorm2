# 普通怪变种（-强化怪）

日期：2026-10-16；记录ID：2026-10-16-strong-variant-monsters；功能ID：ENEMY-AI；工程版本：0.1.0。
设计依据：业主 2026-10-16 口径（本轮新增，见 `docs/v0.1/design/怪物设计.md` §普通怪变种）。
施工口径：`docs/v0.1/06_技术施工_怪物精英与Boss.md` §3.3（新增）。
代码基线：工作区（未提交）。

## 变更与原因

**需求。** 业主：「我要增加一个怪物的种类，属于普通怪变种，正式名称叫 xxx-强化怪，
做小僵尸、警察僵尸、胖子僵尸，体型放大 1.5 倍；小僵尸 hp 增加 2 倍、攻击增加 2 倍，
胖子僵尸也一样，同时自爆范围增加 1.5 倍；警察僵尸 hp 增加 1.5 倍、体型增加 1.5 倍、
发射的子弹速度变快 1.3 倍、距离增加 2 倍」。

**澄清后的口径**（业主逐条确认，共两轮提问）：

| 问题 | 结论 |
|---|---|
| 「增加 N 倍」怎么算 | **乘法**：×2 就是 ×2，不是 ×3 |
| 「警察僵尸」是谁 | 就是项目里的**保安僵尸**（`ranged_caster`，旧名孢子射手） |
| 怎么进战斗 | **独立怪种，进随机池**，约 15% 概率 |
| 怎么和普通怪区分 | **只放大 1.5 倍**，不做换色/发光 |
| 数值怎么存 | **引用原怪 × 倍率**（单一真源，非另抄一份） |
| 攻击距离要不要跟体型放大 | **要**，同步 ×1.5 |
| 保安僵尸子弹伤害 | **不变** |

**新增代码。**

| 文件 | 作用 |
|---|---|
| `src/enemy3d/MonsterVariants.gd` | 变种定义与倍率的**唯一真源**（纯数据 + 静态函数，不持节点） |
| `tests/verification/verify_strong_variant_monsters.gd` + `.tscn` | 专项验收（已登记 `core_scenes`） |

**修改代码。**

| 文件 | 改动 |
|---|---|
| `src/enemy3d/Enemy3D.gd` | `profile_for()` 静态派生；`_table_kind()` 变种回退基类；弹速/射程按种下发；新增两个基准常量 |
| `src/enemy3d/EnemyAvatar3D.gd` | 内部按种分叉改读 `_base_kind`；`get_footprint_profile()` 回退基类；快照暴露 `base_kind` |
| `src/map/MonsterInjector.gd` | 编成表登记 3 种；`_roll_strong_kind()` 出口升级；`_stat_override()` / `_death_explosion_for()` 派生；**修复 zone 丢失** |
| `src/map/SpawnBoxCatalog.gd` | `ALLOWED_BOX_TYPES` 加 3 种（允许点名） |
| `data/level_plans/expedition_01/level_plan.json` + whitebox 源 | `monster_rules.strong_variant = {enabled, chance: 0.15}` |
| `scripts/run_verification_suite.sh` | 新用例登记 `core_scenes` |

**倍率（唯一真源 `MonsterVariants`）。**

```text
melee_chaser   → melee_chaser_strong   hp×2  dmg×2  体型×1.5  攻击距离×1.5
fat_zombie03   → fat_zombie03_strong   hp×2  dmg×2  体型×1.5  攻击距离×1.5  自爆半径×1.5
ranged_caster  → ranged_caster_strong  hp×1.5 dmg×1.0 体型×1.5 攻击距离×1.5 弹速×1.3 射程×2
```

远征01 下的实际值（原怪 → 强化怪）：小僵尸 350→700 / 18→36；胖子 800→1600 / 35→70、自爆半径 5→7.5 m；
保安 250→375 / 伤害不变、弹速 7→9.1 m/s、射程 7→14 m。

## 四条关键实现决策

1. **变种不占 `PROFILES` 行，数值实时派生。** `Enemy3D.profile_for()` 从基类算，
   不写回表。⇒ 以后把 `PROFILES["melee_chaser"]["hp"]` 或远征01 的
   `per_kind.melee_chaser.hp` 调一个数，强化怪自动跟随。验收正面钉住
   `not Enemy3D.PROFILES.has(variant_id)`，防止有人"顺手补一行"。
2. **升级点必须在统一出口。** 落在 `MonsterInjector._generate_basic_enemy()`，
   刷怪盒 / 设计源 / 房型公式三条编成来源自动全覆盖。**远征01 是刷怪盒驱动**
   （`spawn_placements` 优先级最高），做在随机池里等于没做 —— 这是本轮最容易踩空的一步。
3. **随机流单独一条。** 新增 `_strong_rng`（由 `run_seed` 异或常量派生）。
   混进共用的 `_rng` 会让既有固定种子的抽取结果整体位移。
   未配 `strong_variant` 的关卡**一次都不掷** ⇒ 未配置关卡行为逐字不变。
4. **`EnemyAvatar3D` 的按种分叉统一改读 `_base_kind`。** 该文件内有十几处
   `match enemy_kind` / `== "xxx"`；不改的话变种会掉进 `match` 默认分支，
   既拿不到正式小僵尸模型、也生不出正确外壳，**表现静默退化且日志一字不提**。

## 两处新旋钮与一处顺手修复

- **`DEFAULT_ENEMY_PROJECTILE_SPEED = 7.0`**：敌弹弹速原先**硬编码在 `_fire_projectile` 里**，
  被所有远程怪与 Boss 技能共用。抽成常量后由 `PROFILES[kind].projectile_speed` 按种覆盖，
  改强化怪不会连带改 Boss。
- **`DEFAULT_ENEMY_PROJECTILE_RANGE_M = 7.0`**：敌人子弹**原先没有射程概念**
  （`range_m = 0` = 不启用，靠 1 秒存活兜底 ≈ 7 m）。「距离 ×2」是个净新增旋钮，
  不是改原值。普通怪与 Boss **不下发**此键 ⇒ 仍走存活时间兜底，行为逐字不变。
- **顺手修掉的既有缺陷**：`MonsterInjector._death_explosion_for()` 原先返回时
  **丢弃配置里的 `zone` 段**，而 `Enemy3D._spawn_ground_blast_zone()` 正是靠它才生成
  地面持续伤害场 ⇒ 远征01 配的 `zone`（3 秒烫伤圈）**从来没有生效过**。现已原样透传，
  并留了回归钉。

## 验证

`tests/verification/verify_strong_variant_monsters.gd` — 实测
**`STRONG_VARIANT_OK`（samples=4259，engine ERROR 0 行，EXIT=0）**。

覆盖：定义表自洽 / 倍率逐条对业主口径 / **12 处登记逐表扫描**（漏一处即静默退化）/
真 `Enemy3D` 实例上的最终数值（生命、伤害、攻击距离、体型、移速不变）/
外观基类与正式模型确实取自原怪 / 头顶条宽不吃查表默认值 / 碰撞形状不被放大两遍 /
弹道只影响强化远程怪 / 关卡覆盖派生 / 自爆半径派生 / `zone` 透传回归 /
15% 概率统计（n=4000，容差 [0.12, 0.18]）/ 同种子可复现 / 未配置关卡不掷骰 / 精英不被升级。

**负向对照（证明门禁不是永远绿）：**

| 注入的故障 | 结果 |
|---|---|
| 变种 ID 改名（模拟漏登记 / 写错名） | `STRONG_VARIANT_FAIL: 20 failures` |
| 小僵尸 `hp_mult` 2.0 → 3.0 | `STRONG_VARIANT_FAIL: 1 failures` |
| 还原后复跑 | `STRONG_VARIANT_OK`（md5 与改前一致） |

**门禁对照（改前 / 改后）：**

| 门禁 | 结果 |
|---|---|
| `check_asset_registry --scope structure` | `ASSET_REGISTRY_CHECK_OK assets=1285 ledgers=9` |
| `check_verification_registry` | 本用例已登记；剩余 6 条 `unregistered` **与 2026-10-14 记录的同名同数，非本次引入** |
| `check_asset_runtime_naming` | 既有债务列表，新增文件不在其中 |
| `verify_ledger_split` | 15 条失败**全部落在 vfx 域**（`mod_bullet_*` 那批），enemies 域零红；`git status` 确认**本轮未触碰任何 xlsx / ledgers** ⇒ 既有红项 |

## 追加：红色发光眼与骨骼绑点（同日第二轮）

**需求。** 业主：「强化怪，帮我做一个红色发光特效，放在眼睛的位置，专门给强化怪用的，
眼睛位置需要有一个绑点，直接在 godot 引擎在对应骨骼的位置加上去。你需要自己去找到这个点，
然后加完后验证。」

**实现。** 新增 `src/enemy3d/StrongVariantEyeGlow3D.gd`（一对自发光眼球 + 弱溢光），
挂到 `Head` 骨的 `BoneAttachment3D` 上（与保安僵尸背的枪同一套机制）。
眼位由 `MonsterVariants.EYE_SOCKETS` 配方驱动，**按模型几何实时计算**，不写死坐标。

| 强化怪 | 眼高比例 | 眼距半宽 | 半径 |
|---|---|---|---|
| 小僵尸-强化怪 | 0.535 | 0.160 m | 0.030 m |
| 保安僵尸-强化怪 | 0.630 | 0.155 m | 0.030 m |
| 胖子僵尸-强化怪 | 0.880 | 0.195 m | 0.042 m |

**找眼睛这一步花了大力气，结论值得记下来。** 三个模型的下列事实（全部实测，非推测）：

- **没有 eye 骨**，只有 `Head`；
- 每个模型是**单 surface、单材质、`emission=off`** —— 眼睛在几何 / 材质 / 贴图上**没有可自动识别的特征**；
- 小僵尸与保安僵尸的 `Head` 骨 pose 在**胸口**（y≈0.85），网格的头在 y≈1.5 ⇒ 骨空间与网格**不同源**（bind pose 的 y 是 −0.890）；
- 胖子僵尸的手臂与头**同高**，取「最前顶点」必须收紧横向范围；
- 保安僵尸身上还有一把**无蒙皮的枪**，算进包围盒会把眼位比例算低 0.11。

期间试过并**否决**了五条自动定位路线（都留了记录）：骨骼直读、顶点「最前簇」、
像素亮度亮斑、贴图 UV 匹配「眼白」、蒙皮矩阵反解。最后可行的是
**「带烧入刻度线的实拍标定图 + 逐档目视比对」** —— 眼睛在这三只低模上无法自动识别，
只能靠人眼看图定档，再把结果落成可复现的配方常量。

**四个实现坑（已写进代码注释）：**

| 坑 | 现象 | 正解 |
|---|---|---|
| `BoneAttachment3D` 的 global 含**骨旋转 basis** | 手写骨位姿求逆，眼睛飞到胸口 / 下巴 / 脚底各一次 | 对**引擎给的挂点世界矩阵**求逆 |
| GLB 本帧刚实例化 | 同帧读数未解析，眼位算成 0.057 | 分两步：本帧建挂点，**下一帧**算偏移 |
| 保安僵尸的**无蒙皮枪网格** | 包围盒下界被拉到 −0.41，眼位比例低 0.11 | 只取**有蒙皮**的角色本体顶点 |
| `BoneAttachment3D` 在自己通知里更新 | 同帧 seek 后读 →「骨动 0.27m、绑点动 0m」假故障 | 读数前**等一帧** |

**负向自测中抓到一条假绿 —— 这是本轮最有价值的发现。** 最初只断言
「配方 ↔ 生效值自洽」：把 `y_ratio` 从 0.535 改成 0.30，实现跟着用 0.30，
两边仍然自洽、**测试照样绿**，而眼睛已经掉到肚子上。
⇒ 补了一份文档侧硬编码的 `DOC_EYE_SOCKETS` 逐值比对（与 `verify_monster_startup_roar`
把文档数字再写一遍是同一套纪律）。

**验收。** `tests/verification/verify_strong_variant_eye_glow.gd` →
实测 **`EYE_GLOW_OK`（samples=35，0 engine ERROR）**。
覆盖配方绝对值、三变种各一对红眼、**普通怪一只都不长**、
绑点是 `Head` 骨的 `BoneAttachment3D`、材质真发红光、左右对称、眼位比例、
**动画播放下绑点与骨完全同步**、零碰撞体、`dismiss` 幂等。

| 注入的故障 | 结果 |
|---|---|
| `y_ratio` 0.535 → 0.300 | 红 1 条 |
| 绑点改挂 `Root` 骨（脱离 Head） | 红 3 条 |
| 让普通怪也放行（回退分支） | 红 3 条 |
| 眼球半径 0.030 → 0.015 | 红 1 条 |
| 还原后复跑 | `EYE_GLOW_OK`，md5 与改前一致 |

**视觉证据。** `outputs/strong_variant_eye_glow_evidence.png`（三组「原怪 ｜ 强化怪」头部对照）。
**保留的标定工具**：`tools/probe_eye_confirm.tscn`（眼位标定，烧入刻度）、
`tools/probe_ranged_eye_scan.tscn`（保安僵尸单独标定）、
`tools/probe_attachment_semantics.tscn`（挂点语义实测）、
`tools/probe_eye_glow_capture.tscn`（视觉证据）；其余一次性探索探针已清理。

**已知局限（如实报告）：**

- 标定精度约 **±0.03 m**：低模、单 surface、无眼骨，眼球在网格上只有几个面片。
  对「眼睛处一团红光」足够；要更准须改模型加眼骨。
- 三个模型的动画以整体位移为主、**几乎不转头**（实测最大头位移 1.3~3.4 mm），
  所以跟随测试断言的是「绑点与骨完全同步」而不是位移量级。
- 溢光刻意压得很低（半径 0.85 m / 能量 0.22）：第一版给 0.85 能量把整只怪染成红灯笼 ——
  那不是「眼睛发光」，是把怪泡在红灯里。游戏内开了 bloom（`GraphicsSettingsManager`），
  实际观感比标定图更「发光」。

## 未做与遗留

- **账本未新增行（有意）**：三个变种**零新美术资产** —— 模型、材质、贴图、动画、
  PackedScene 全部复用原怪，只是运行时放大。账本「一行 = 一个真实资产」，
  加行会造出三行指向同一 tscn 的伪资产，破坏 AssetID ↔ 文件路径的一一对应
  （《3D-敌人》分页更是明文写「没有 Prefab 就不能加行」）。
  变种关系已落在怪物设计页与本文档。**若要在账本留痕**，做法是在既有三行的
  「备注」列补一句变种说明并重建 `ledger_split_baseline.json` —— 需要重建 9 域摘要，
  属独立事务，本轮未擅自执行。
- 强化怪目前**没有专属视觉标识**（业主明确「只放大 1.5 倍」）。若后续发现可辨识度不足，
  建议按 `scene-art-*` 系列 skill 走一次「变种皮肤」派生，届时才需要账本登记。
- `chance` 目前只有远征01 配置。其它关卡未配置 ⇒ 不产出强化怪，行为逐字不变。
