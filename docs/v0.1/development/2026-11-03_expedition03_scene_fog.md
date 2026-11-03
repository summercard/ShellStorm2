# 远征03 场景雾定值：距离雾 0.0200 / 体积雾 0.0057

日期：2026-11-03。工程版本：0.1.0。FeatureID：WORLD-BLOCKS。
契约：[关卡接入规范](../关卡接入规范.md) §4（关卡专属内容按 ID 分支，须收口）、[远征关卡03设计](../design/远征关卡03设计.md)。
本次只改**表现数值与一条失效通道**，不更改玩法、存档 schema、layout_id 或房间资产。

## 症状与根因

业主在 P 键调参面板「镜头雾气」页把远征03调到**场景雾 0.0200 / 体积雾 0.0057**，但该页明写「临时 · 离开场景即复原」——面板走的是 `set_debug_scene_fog_override()`，值只活在本场景节点上，不写存档、不写 cfg。业主要的是**把这个值定下来**。

把值固化时发现一条**存在但从未生效的通道**：

- `TowerDescent3D` 早就有 `atmosphere_fog_density_override` / `atmosphere_volumetric_fog_density_override` 两个 export，注释写着「可选作者场景参数」，`_install_atmosphere()` 里也确有注入调用。
- 但 `TowerAtmosphere3D.set_fog_profile_override()` 写的是 `_authored_distance_fog_override` —— **与「房型自带雾档」共用同一对变量**。
- 而 `set_room_fog_profile(profile)` 在每次进出房间时都会跑，空档（普通房）分支会把 `_authored_*` 复位成 `-1`（L125-129 的 tween 回调，或 L115-117 的 immediate 分支）。

于是关卡级值最多活到玩家第一次换房。全工程 5 个远征场景**没有一处敢用这两个 export** —— 这就是它的证据。

实测复现（`baseline_scene_fog.log`，改动前）：

```
SCENE_FOG after_assembly        distance=0.030000 volumetric=0.009000   ← 塌回全塔基准
SCENE_FOG after_leaving_room    distance=0.029854 volumetric=0.009010
SCENE_FOG_FAIL after_assembly: distance 0.0300 != 0.0200 (塌回全塔基准 0.030)
```

## 变更

### 1. 拆开两个概念（`TowerAtmosphere3D.gd`）

| 变量 | 语义 | 生命周期 |
|---|---|---|
| `_level_*_fog_override` | 本关**普通区域**基准（新，本次加入） | 整关常驻，进/出任何房间都不变 |
| `_authored_*_fog_override` | 单间**房型自带雾档**（原有，Boss 房那类） | 只在该房期间，离开即撤 |
| `_debug_*_fog_override` | 调试面板临时覆盖（原有） | 不落盘，随场景销毁复原 |

`set_fog_profile_override()` 改走 `_level_*`。新增 `_ordinary_fog_density()` 作为「本关普通区域此刻值」的**唯一取值点**，`set_room_fog_profile()` 的回落基准也改从它取 —— 于是房间档离开后落回的是**本关值**而非全塔值。

`_apply_base_fog_density()` 的优先级链（低 → 高）：

```
全塔基准 / 99F 基地室内插值
  → 关卡级常驻覆盖（本关普通区域）
  → 单间房型雾档（只在该房期间）
  → 调试面板临时覆盖（不落盘）
```

### 2. 注入目标值（`scenes/ExpeditionLevel03_3D.tscn`）

```gdscript
atmosphere_fog_density_override = 0.02
atmosphere_volumetric_fog_density_override = 0.0057
```

走的是**数据层**（关卡自己的场景文件），符合《关卡接入规范》§2「新关卡 90% 的工作在数据层」。未在通用机制容器里加关卡 ID 分支；`check_level_decoupling.py` 7 个容器 0 违规。

### 3. 新增验收入口 `verify_expedition03_scene_fog`

盯的正是这条**隐形契约**：关卡级雾值一旦注入就必须整关常驻，不许被换房逻辑抹掉。四个采样点：装配后、房型档生效中、**离开房间后**（关键项）、真实进房后。

登记进 `run_verification_suite.sh` 的 `smoke_scenes`（无头逻辑测试，无视图纹理依赖）。

## 验证

采用独立 APPDATA 启动 Godot，未读取开发者真实存档。过程产物位于
`ShellStorm2-work/sessions/2026-11-03_expedition03_scene_fog/`。未运行整份聚合套件，专项结果不代表全工程通过。

| 项目 | 退出码 | 结果 |
|---|---|---|
| 改动前复现 `verify_expedition03_scene_fog` | 1 | 4 采样点全塌回 0.030/0.009，8 项失败，`baseline_scene_fog.log` |
| 改动后 `verify_expedition03_scene_fog` | 0 | 10 项断言全通过，4 采样点均为 0.0200/0.0057，`final_scene_fog.log` |
| `verify_tower_journey_polish`（基地雾回归） | 0 | 全部雾断言通过；1 条「跳时至夜晚太阳仍保持白昼」为**既有失败**，改动前后逐字相同 |
| `verify_expedition03_indoor_lighting` | 0 | 1096 项、2 项失败，与改动前**逐项逐字相同**（`ExtractionBeacon3D` 灯开关，既有问题） |
| `verify_expedition_level01_flow`（旧关卡未坏） | 0 | 错误集合与改动前逐条比对：仅多 1 条「关闭未完成相机返程」；该条在改动前后各连跑 3 次均为 0 次 → **偶发时序抖动**，非回归 |
| `verify_test_level_99_flow` | 0 | 99F 专项与改动前一致 |

三处「既有失败」均用**同一命令、隔离 APPDATA、改动前后各跑**的方式确认，不是凭断言文本推断。

### 静态检查

| 静态检查 | 退出码 | 结果 |
|---|---|---|
| `check_level_decoupling.py` | 0 | 7 个通用容器，0 违规 |
| `check_verification_registry.py` | 1 | 剩余 4 条 `verify_base_lamp_dynamics` / `verify_base_lamp_visual` / `verify_enemy_action_recovery` / `verify_stairwell_turn_rail` 未登记；已用 `git show HEAD:` 确认**既有**（HEAD 版 runner 中 4 个名字均为 0 次）。本次新增的 `verify_expedition03_scene_fog` 已登记、不再报 |
| `check_documentation_contracts.py` | 1 | 15 条断链 + 1 组 4 个验收入口未登记 + 媒体检查缺 `openpyxl`，均为既有问题；本轮未新增断链 |

## 边界与回滚

- **只影响远征03**。其他关卡两个 export 都是默认 `-1`，`_ordinary_fog_density()` 在 `_level_* < 0` 时逐字返回原插值结果 —— 主塔、99F 基地、远征01/02/99 的雾值不变（由 `verify_tower_journey_polish` 与 `verify_test_level_99_flow` 覆盖）。
- **`_level_*` 与 `_authored_*` 拆成两组变量是本次的关键**。若日后有人再让它们共用，`verify_expedition03_scene_fog` 的 `after_leaving_room` 一条会立刻变红 —— 这条断言就是为这个契约留的。
- 面板「清除雾气覆盖」只清 `_debug_*`，**不碰关卡值**。业主在面板上看到的两个数字现在会由关卡值直接回填；拖滑条仍是临时覆盖，退出场景后自动回到 0.0200/0.0057。
- 体积雾的 meta 重放源（`presentation_volumetric_fog_density`）在**所有**采样点（含房型档生效期间）都与实值一致，切画质不会把浓度闪回全塔值 —— 已断言。
