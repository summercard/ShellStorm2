# 远征03 逐房怪物编成 + 关闭旧刷怪逻辑（2026-10-29）

## 1. 业主指令

> 在远征03，按照挺进地牢的设计，将对应的怪物布置在对应的房间中，去掉原来的刷怪逻辑。
> 然后更新设计文档和账本。

拆成三件事：

| # | 事项 | 结论 |
|---|---|---|
| ① | 逐房布置怪物（按 EGT 设计） | 新增 `spawn_roster` + 8 个 EGT 敌群盒 |
| ② | 去掉原来的刷怪逻辑 | 四道闸门叠起来，旧路径在该关**不可达** |
| ③ | 更新设计文档与账本 | 怪物设计 §T5、远征03 §8.3、开发记录、敌人账本 12 行 |

## 2. 为什么"去掉旧逻辑"不能靠删代码

`Dungeon3D._spawn_room_enemies()` 里的房型公式分支（`desired = 4 + floor*2`）
是**远征01/02 与整座塔楼**共用的。删掉它等于把那几关一起改掉。

正确做法是**让旧路径在本关不可达**，而不是把它从代码里删掉。四道闸门：

| # | 闸门 | 落点 | 作用 |
|---|---|---|---|
| ① | `spawn_boxes_only = true` | `spawn_roster` | 真敌对房必须有盒；没盒就不刷（不回退公式） |
| ② | 删除 `monster_rules.enemy_pool` | `level_plan.json` | 公式路径拿不到池子 |
| ③ | 编成外补齐对该层返回 0 | `Dungeon3D._expedition_surplus_deficit()` | 不再按比例补原生怪 |
| ④ | 编成由生成器注入 | `FloorPlanGenerator._generate_flow_floor()` | 几何桥接只管形状，不碰内容 |

## 3. 为什么编成表只写盒 id、不写坐标

远征03 是 `mode: flow`：每局抽一张骨架，**房间位置与尺寸是运行时算的**
（`EgtFlowAssembler` 出口对出口拼装）。写死坐标只有两种下场：

- 房间小一点就 **越界** → 校验器判据 B 直接拒整层，整层生成失败；
- 侥幸放得下，换个种子就 **压进墙里**。

所以编成表只声明「这房摆哪几个敌群」，坐标由 `_auto_lay_boxes()` 算：
扣四周 5m → 按盒子数分格 → 每格中心摆一个。三条几何判据（盒在房内 / 盒边离墙 ≥5m /
同房不重叠）由生成器自检 + 校验器 + 探针三层复核。

## 4. 8 个 EGT 敌群盒

| 盒 | 只数 | 编成 | 设计意图 |
|---|---|---|---|
| `box_egt_kin_patrol` | 2 | bullet_kin ×2 | 最基础一组 |
| `box_egt_kin_trio` | 3 | bullet_kin + bandana_kin + veteran_kin | 同族三变种，逼玩家靠染色分辨 |
| `box_egt_shotgun_lead` | 2 | red_shotgun + bullet_kin | 一近一远错位压迫 |
| `box_egt_shotgun_heavy` | 2 | blue_shotgun + red_shotgun | 最重远程组合 |
| `box_egt_blob_cluster` | 2 | blobulon + blobuloid | 死亡分裂，实际目标数远超初始 |
| `box_egt_bomb_pair` | 2 | pinhead + nitra | 两种引爆，教"击杀后也要走位" |
| `box_egt_rush_line` | 3 | bullat ×2 + veteran_kin | 冲撞惩罚站桩，远程堵退路 |
| `box_egt_support_cell` | 3 | gunsinger + bandana_kin ×2 | 辅助+护卫，先杀辅助 |

逐房编成（10 个 node + 2 个 kind 兜底）按推进排难度：
`n01` 入门(4只) → `n02`(5) → `hub_01`(7) → `n03`(5) → `n04`(4) → **`hub_02`(10，顶点)**
→ `n05`(4，缓冲) → `n06`(5) → `n07`(7) → `n08`(兜底，仅三张骨架有)。

## 5. 六个真踩的坑

### 5.1 加了编成却刷出原生小僵尸（编成外补齐）

前三道闸门都开了之后，`hub_01` 编成 **7 只**却刷出 **9 只**，多出的 2 只是
`melee_chaser`（名字"边境小僵尸"）。

根因：`_apply_expedition_surplus()` —— 远征通用的「编成外补齐」，按存活数 ×30% 补原生怪。
它本来是给「设计源只写大致规模」的关卡兜底的，与逐房精确编成天然冲突。

修：`room.spawn_boxes_only` 时直接返回 0。判据用字段而非关卡 ID，
任何关卡写这一层都同样生效。

### 5.2 校验器要求 BOSS 房有刷怪盒 → 整层生成失败

`LevelPlanValidator` 判据 A 把 `ROOM_TYPES_WITH_HOSTILES` 全算作"必须有盒"，
而 BOSS 在其中。于是 `spawn_boxes_only` 层的远征03 被
`spawn_boxes_missing_for_hostile_room:boss` **直接拒掉**，启动失败 ——
日志只有那一行，看起来像关卡数据坏了。

修：判据 A 排除 BOSS 房。Boss 身份走 `BossContentCatalog` 名册，增援走
`boss_reinforcement_plan`，刷怪盒不该管它。

### 5.3 壁炉房：给编成或不给，两条路都是错的

注入房的 `content_type` 由内容洗牌决定，会被洗成 `COMBAT/TRAP/SCAVENGE`（都是敌对型）：

- 给它编成 ⇒ 凭空给「藏层入口」加一场仗；
- 不给 ⇒ 校验器判「敌对房缺盒」，整层启动失败。

修：把 `FIREPLACE_ROOM` 归入 `FLOW_PEACEFUL_KINDS`（与隐藏房同处理）。
**这是一处已知原作差异**（EGT 的壁炉房要打赢才能进隐藏层），已在
`远征关卡03设计 §8.3` 记为待裁定项。

### 5.4 25×25 房放不下两个 6m 盒（可用区多扣了一次半宽）

`usable = size - 2*(recess + max_half)` 相当于假设「盒心必须离墙 recess+half 以上」。
25×25 房扣完只剩 9m，分两格各 4.5m < 盒宽 6m ⇒ 判定"放不满"并**返回空** ⇒
又变成"缺盒"启动失败。

正确关系：格宽 ≥ 盒宽时把盒**居中放格心**，盒边到墙自然 ≥ recess。
所以 `usable` 只扣 recess，不预扣半宽。

### 5.5 盒太小导致稳定少出

盒内是「随机撒点 + 1.8m 最小间距」的硬约束，4×4 盒装 3 只常排不下 ⇒ 静默少出。
实测编成 7 只时出过 5 只。

修：盒尺寸按出怪数配 —— 3 只用 6×6，2 只用 5×5。

### 5.6 探针自身的三个错

| 错 | 后果 | 修 |
|---|---|---|
| 读盒子的 `count` | 永远得 0（规范化后是 `count_min/count_max`） | 改读 `count_min` |
| 按 `content_type` / `size` 读最终 plan | 得 0 间战斗房 → 误判"编成没生效" | 最终结构是 `type` / `dimensions` |
| 只采样一次 | 分不清"编成混了原生怪"与"后来生成的" | 两次采样（落门瞬间 / +1.7s）对比 |

另外：探测中曾直接调 `spawn_points_in_box()` 量落点，它会触发可达性计算 → 探针跑满
200 秒超时。**该诊断已移除**，改成看「波次总数 vs 存活账」。

## 6. 验收

| 项 | 命令 | 结果 |
|---|---|---|
| 编成注入 + 几何 | `tools/_egt_roster_probe.tscn`（6 个种子） | **`EGT_ROSTER_PROBE_OK`** —— 每个种子下战斗房 8~10 间**全部有编成**、`spawn_boxes_only` 生效、盒位满足三条几何判据 |
| 真实进房刷怪 | `tools/_egt_runtime_probe.tscn`（连跑 3 次） | **`EGT_RUNTIME_PROBE_OK`** —— `hub_01` 稳定刷出 **7 只，7 只全 egt_***，与编成逐项一致，零原生怪混入 |
| 回归：敌人行为流 | `verify_3d_enemy_behavior_flow.tscn` | exit 0，`3D_ENEMY_BEHAVIOR_FLOW_OK`（9 项全过） |
| 回归：强化怪专项 | `verify_strong_variant_monsters.tscn` | exit 0，ERROR 0 |
| 资产账本 | `scripts/check_asset_registry.py` | issues 16，**敌人域 0 问题**（16 项全在 scenes/props/vfx/ui，为既有失败） |
| 文档契约 | `scripts/check_documentation_contracts.py` | 本次改动文档无断链 |

**未验证项**：

- **逐房逐一实拍未做**。只验了 `hub_01`（本关最复杂的枢纽之一）。其余 8 个 node 的
  编成由数据层探针（6 种子）保证，但"进房后真的出这些怪"只抽查了一间。
- **难度曲线未试玩**。编成按 EGT 的推进顺序排了峰谷（`hub_02` 顶点、`n05` 缓冲），
  但"打起来爽不爽"必须真打才知道。

## 7. 改动文件

| 文件 | 改动 |
|---|---|
| `data/spawn_boxes/box_egt_*.json` | 新增 8 个 EGT 敌群盒 |
| `src/map/SpawnBoxCatalog.gd` | 注册 8 个盒；`ALLOWED_BOX_TYPES` 加 12 个 egt_* |
| `data/level_plans/expedition_03/level_plan.json` | 新增 `spawn_roster`；**删除 `monster_rules.enemy_pool`** |
| `src/map/FloorPlanGenerator.gd` | 新增 `_spawn_roster_for` / `_roster_placements` / `_auto_lay_boxes`；逐房注入 `spawn_placements` + `spawn_boxes_only`；`FLOW_PEACEFUL_KINDS` 加三类注入房 |
| `src/map/LevelPlanValidator.gd` | 判据 A 排除 BOSS 房 |
| `src/world3d/Dungeon3D.gd` | `_expedition_surplus_deficit()` 对 `spawn_boxes_only` 层返回 0 |
| `tools/_egt_roster_probe.gd/.tscn` | 新增，编成注入 + 几何断言 |
| `tools/_egt_runtime_probe.gd` | 两次采样、选房改为「挑有编成的房」、加在途/账面诊断 |
| `docs/v0.1/design/怪物设计.md` | §T4 状态更新；新增 §T5（编成总章，含闸门表与已知差异） |
| `docs/v0.1/design/远征关卡03设计.md` | §8.3 改为「已换形态」，列四道闸门与待裁定项 |
| `assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx` | 新增 12 行（`程序占位`）+ 日志 v0.1.20 + 查重/总览公式范围扩到 32 |
