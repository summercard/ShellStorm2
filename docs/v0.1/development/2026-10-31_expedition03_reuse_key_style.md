# 远征03 美术复用键改「原型指纹」+ 修复公馆地砖挡住刷怪

功能：**WORLD-PLAN**（关卡结构）＋ **ASSET-PIPELINE**（房间资产生产）
日期：2026-10-31
前置记录：[公馆壳体铺装](2026-10-31_expedition03_manor_shell_build.md)、[壳体重铺](2026-10-31_expedition03_manor_shell_rebuild.md)、[复用键修复](2026-10-31_runtime_room_signature_fix.md)

---

## 1 报单与现象

业主截图：远征03 游戏内是**白盒**，但 `_exp03_manor_shell_verify` 报 `ok=17/17`、`_exp03_manor_geom_verify` 报 `gaps=0`，全绿。

截图 HUD 显示 **关卡种子 `3893044740`**。

用该种子实测：

| 判据 | 结果 |
|---|---|
| 按门位键命中 | **3 / 17** |
| 按原型键命中 | 16 / 17（同一次运行） |

跨 5 个种子：按门位 **1.4/17**，按原型 **15.8/17**。跨 24 个种子：缺口 **335**。

## 2 根因

### 2.1 门位进了文件名

`RuntimeRoomArtSource.art_path()` 生成
`<template>_<签名前12>_<门位指纹前6>.tscn`。

门位来自 `TowerDescent3D._shared_door_lane()` —— 由两端房间的 5m 墙组件**几何求交**算出，
每局都变（实测 `combat_45x40` 一个模板就有 53 种门位组合，无上界）。

于是同一份美术隔一局就认不出来。**验收器把 `SEED` 写死 `77003244`，只验了一个样本，所以全绿。**

### 2.2 窗位依赖门位，不能只替换门墙

`ManorShellPlan.window_cells(cells, door_indices, mode, side)` 的 `pair` / `double_pair` /
`clerestory` 三种节奏都要**避开门位格**。门位一挪，整面墙的「实墙/窗/门」序列全变 ——
不是挪一块门墙能补的。这是"运行时重排"必须重算整面、而不是只换门墙的原因。

### 2.3 部分注入房拿不到原型

`ARCHETYPES` 表缺 `STORAGE`，`reward_*` 抽到该类型时 `style_for()` 落兜底，
与烘焙侧指纹对不上。

### 2.4 安全房走另一条分支

`start` 的 `procedural_shell = false`，走 `_build_shell()` 的 else 分支
（"整个静态场景照常用"），因此：
- 烘焙文件里的 `prp_room_*` 白盒件**不会被剥离**；
- 烘焙器 `_exp03_manor_shell_builder` 的过滤条件 `if not room.procedural_shell: continue`
  把它整批跳过 → 从未被铺过公馆件。

### 2.5 修完之后暴露的新 bug：公馆地砖把地面变成"障碍"

`DungeonRoom3D._collect_spawn_blockers()` 原判据：

```gdscript
if bounds.end.y <= 0.05 or ...:   # 0.05 是硬编码
```

公馆地砖厚 **0.104598m**、原点在底面中心 ⇒ 盒顶 **0.1046**，刚越过 0.05，
于是**整间房的地面被当成障碍** ⇒ `_spawn_available` 空 ⇒ `_resolve_spawn_position()`
返回非有限值 ⇒ `_spawn_enemy_batch()` `return -1` ⇒ **一只怪都不刷**。

表现：`probe_expedition03_playable` 的 `alive_after` 从 7 掉到 0，稳定复现。

潜伏原因：美术接管率只有 ~8% 时，九成房间用程序化薄地板，撞不上这个阈值。

## 3 改法

### 3.1 新增 `src/world3d/ManorShellPlan.gd`（配方唯一真源）

只算不建：原型表 `ARCHETYPES`（含新登记的 `STORAGE`）、`style_for()`、
`style_fingerprint()`、`door_cells()`、`window_cells()`、`floor_plan()`、`wall_plan()`、
`instantiate_plan()`。烘焙器与运行时**调同一套**，逐格结果必然一致。

### 3.2 复用键第三段换成原型指纹

`RuntimeRoomArtSource.describe()` 增加 `style` / `style_label` / `style_fingerprint`；
`art_path()` 改用 `style_fingerprint`。`portal_fingerprint` 保留但**不再进文件名**（仅供诊断）。

原型是 `(room_type, 短边尺寸)` 的纯函数 + 枢纽 `room_id` 特判，零随机 ⇒ 跨种子恒定。

### 3.3 运行时按本局门位重铺结构件

`DungeonRoom3D._rebuild_manor_shell(art_root)`：
1. 删掉美术层里所有 `manor_*` 结构件（**只取顶层**，父子同族不能都收，否则 free 后父链失效）；
2. 按 `ManorShellPlan` 用本局 `connection_ports` 重算配方；
3. 建到 `ArtComponents` 下。

**幂等**：工坊保存的旧门位不会把过时布局带回来。

调用点两处：`_build_art_layer_only()`（`procedural_shell` 房）、else 分支（安全房）。
两处都在 `_art_layer_coverage()` **之前** —— 那条判据量的是"覆盖了多少格"，量旧布局会误判。

### 3.4 开关不再依赖上游传参

`start` 不走 `_instantiate_dynamic_room()`，那条 config 路径不带 `art_layer_keep_structure`。
改为在 `_build_shell()` 里按路径推导：

```gdscript
if not art_layer_keep_structure and static_layout_scene_path.contains("/expedition_03/"):
    art_layer_keep_structure = true
```

`TowerDescent3D` 侧也给所有远征03 房间落一次该字段（无害，两边一致）。

### 3.5 刷怪地面豁免阈值

`SPAWN_GROUND_TOP_MAX_M := 0.15`（原硬编码 0.05），注释写明公馆地砖厚度与踩过的坑。

### 3.6 烘焙器

- 去掉自维护的 `ARCHETYPES` / `HUB_IDS` / `_style_for`，统一走 `ManorShellPlan`；
- 过滤条件从 `procedural_shell` 改为「有静态布局 + 非模块壳」，纳入安全房与注入房；
- 新增 `--only=<room_id>` 单房烘焙、`--sweep` 跨 24 种子补齐（每个
  `(模板, 签名, 原型)` 只铺一次）。

## 4 验收

| 项 | 命令 | 结果 |
|---|---|---|
| 美术层接管 | `tools/_exp03_manor_shell_verify.tscn` | `ok=17/17`，35 门位 / 24 门扇 |
| 几何 | `tools/_exp03_manor_geom_verify.tscn` | `ok=17/17 gaps=0` |
| **跨种子覆盖** | `tools/_exp03_art_coverage_probe.tscn` | **`COV_MISSING_ROOMS 0`**（24 种子，249 复用键） |
| 端到端可玩 | `tests/verification/probe_expedition03_playable.tscn` | `PLAYABLE_OK`，`alive_after=7` |
| 敌人行为流 | `tests/verification/verify_3d_enemy_behavior_flow.tscn` | OK |
| 波次/刷怪失败 | `tests/verification/verify_dungeon_wave_intermission.tscn` | OK |

**已知既有红项（与本次无关，已用原始代码复跑确认数值一致）**：
`probe_expedition_spawn_safety` → `failures=5 legacy_unsafe=280`（远征01 旧债），
原始代码同样 `5 / 280`。

性能（`tools/_exp03_perf_probe.tscn`，全房强制 ACTIVE）：

| | 改前（美术覆盖 ~8%） | 改后（100%） |
|---|---:|---:|
| settle | 2470 ms | 3074 ms |
| 节点 | 10398 | 10470 |
| CPU 帧时 p95 | 30.2 ms | 17.0 ms |

节点量级没变（本来就只有那一个种子铺满），帧时反而更稳 —— 程序化生成路径被美术替代。

## 5 产物与清理

- 新增：`src/world3d/ManorShellPlan.gd`、`tools/_exp03_art_coverage_probe.*`、
  `tools/_exp03_art_diag.*`、`tools/_exp03_perf_probe.*`、`tools/_exp03_room_inspect.*`
- 烘焙目录由 38 份收敛到 20 份（18 份新命名 + 2 份走廊工坊产物）；
  改前 18 份旧命名文件已备份到
  `.workbuddy/backup/20261031_reuse_key_style/before_delete/`
- 安全房原工坊快照备份于 `.workbuddy/backup/20261031_start_manor_pilot/before_edits/`

## 6 留给后续

- 家具软装 29 件 / 门窗装饰 6 件 / 天花板仍未接入（独立设计决定）。
- `_egt_ai_flow_probe` 的轮转断言仍是假绿（见专项链路 §7.2）。
- `check_asset_registry` 在 Windows 上恒定红：账本记 LF 归一哈希、门禁比原始字节
  （抽文件验证过 sha 差异纯属 CRLF）；另有 114 条指向不存在的 `ShellStorm2-backup/`。
  这条门禁目前等于失效，建议单独修。
