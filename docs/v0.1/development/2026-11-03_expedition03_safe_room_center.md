# 远征03 入口安全屋：出生点归中 + 中央五件易碎件撤除

日期：2026-11-03。FeatureID：WORLD-PLAN。

## 来源与裁定

业主：「远征03，安全屋，玩家进入后要出现在安全屋的正中间。还有中间五个易碎物品，之前说了要拿掉，还在。帮我拿掉。」

两条裁定都很明确，不涉及取舍：出生点 = 房心；中央那五个 = 撤除。

两件事占的是**同一处空间**（中央五件落点全在房心 ±2.16 m 内），只改一件会让玩家落地与罐子重叠，
故同批处理。

## 关键发现：上一轮只写了记录，没落地实现

`docs/v0.1/development/2026-11-02_expedition03_prop_scale_and_rug_matte.md` 与
`2026-11-02_lobby_lounge_and_fixture_lighting.md` 都声称「已通过
`furnishing.fixed_lobby_clutter_enabled=false` 关闭中央五件」，并附实测读数
`central_fixed_clutter: 0`。

**但该键在全仓不存在**：

| 检查 | 结果 |
|---|---|
| `src/` + `data/` 全量 grep | 0 命中 |
| `git log --all -S "fixed_lobby_clutter" -- src/ data/` | 空（从未进入任何提交） |
| 各分支 `git grep`（`0.1.1` / `0.1.2` / `main` / `origin/0.1.2` / `xuniyaogan`） | 全无命中 |

⇒ 记录里的那条实测读数（`central_fixed_clutter: 0`）与工作区实际不符。
本轮按记录把它**真正实现**并接到数据，业主的观察（"还在"）与代码现状一致。

## 改了什么

| 文件 | 改动 |
|---|---|
| `src/world3d/DungeonRoom3D.gd` | 新增 `fixed_lobby_clutter_enabled`（默认 `true`），`configure()` 接收，`get_room_snapshot()` 导出；`_build_interactive_clutter()` 的 STAIR_LOBBY 固定分支按它提前返回 |
| `src/world3d/TowerDescent3D.gd` | ① `_expedition_entry_spawn_offset()` 的 ID 名单 `["expedition_01"]` → `["expedition_01", "expedition_03"]`；② `_append_plan_room_record()` 从 `furnishing` 段透传该键；③ `_instantiate_dynamic_room()` 的 `configure()` 透传该键 |
| `src/world3d/Dungeon3D.gd` | `_prepare_layout_rooms()` 的 `configure()` 透传该键（与 `procedural_furniture_enabled` 同路径） |
| `data/level_plans/expedition_03/level_plan.json` | `furnishing` 段新增 `"fixed_lobby_clutter_enabled": false`，并更新该段 `note` 自解释 |
| `tests/verification/probe_exp03_safe_room_spawn_and_clutter.{gd,tscn}` | 新增探针（见下） |
| `docs/v0.1/关卡接入规范.md` | §4.1 表与 §4.2 范例同步为 `01 / 03 = 房心` |
| `docs/v0.1/design/远征关卡03设计.md` | 新增 §7.5.5 记录两项裁定与排查结论 |

### 为什么出生点按关卡 ID 分支是合规的

`docs/v0.1/关卡接入规范.md` §4 把「出生点偏移」列为**关卡专属内容**，允许按 ID 分支，
但有三条硬约束：

| # | 约束 | 本轮 |
|---|---|---|
| C1 | 注释说明为什么这关特殊 + 新关卡默认走哪支 | 函数注释已写：03 与 01 同口径（含"中央已清空"这层因果），其余走「偏 4 m」 |
| C2 | 分支收口在单一函数内 | 只改 `_expedition_entry_spawn_offset()` 一处，调用点不动 |
| C3 | 有明确默认分支，新关卡不写即可用 | `in [...]` 之外仍返回「朝前门偏 4 m」 |

反观五件那条：它是**能力段**，代码里不含 `expedition_03` 字样 —— 已由
`scripts/check_level_decoupling.py` 的零容忍约束（`Dungeon3D.gd` 属通用机制容器）。

## 验收

### 三段判据（探针实跑，真实远征03 场景）

| 段 | 判据 | 改前 | 改后 |
|---|---|---|---|
| A 出生点 | 偏移函数 + 玩家真实坐标距房心 ≤ 0.05 m；脚下有地面 | **4.000 m ❌** | 0.000 m ✅ |
| B 中央五件 | 房心半径 2.2 m 内易碎件 = 0；随机撒点未误伤 | **5 件 ❌** | 0 件 ✅ |
| B′ 流送重建 | 卸载重建后中央仍为 0 | **又冒 5 件 ❌** | 0 件 ✅ |
| C 开关对照 | 同规格安全房：开关 true 摆 5 件、false 摆 0 件 | — | 5 / 0 ✅ |

改前实测（反向对照，把代码临时退回旧口径后跑同一探针）：

```
ERROR: EXP03_SAFE_ROOM: 出生点偏移函数没落在房心：水平 4.000 m（上限 0.05）(0.0, 0.05, -4.0)
ERROR: EXP03_SAFE_ROOM: 玩家没落在安全屋正中：距房心 4.000 m（上限 0.05）(0.0, 0.115794, -4.0)
ERROR: EXP03_SAFE_ROOM: 安全屋正中间仍有 5 件易碎物件（应 0）：
  ["breakable_jar@2.16", "breakable_book_stack@1.84", "breakable_vase@1.90",
   "breakable_chair@1.84", "breakable_crate@2.16"]
ERROR: EXP03_SAFE_ROOM: 流送重建后中央又冒出 5 件易碎物件
EXP03_SAFE_ROOM_SPAWN_AND_CLUTTER_FAIL count=4
```

改后实测：

```
EXP03_SAFE_ROOM_LEGACY front=north legacy=(0.0, 0.05, -4.0) horizontal=4.00
EXP03_SAFE_ROOM_SPAWN offset=(0.0, 0.05, 0.0) room=(2.5, 0.0, 2.5) player=(2.5, 0.115794, 2.5) ground=true
EXP03_SAFE_ROOM_CLUTTER central=0 room_total=24 random_total=713 rooms=18
EXP03_SAFE_ROOM_SWITCH enabled=5 disabled=0
EXP03_SAFE_ROOM_SPAWN_AND_CLUTTER_OK
```

### 两处"牙齿"（防假绿）

1. **C 段开关对照**：另建一间同规格 STAIR_LOBBY，把开关拨回 `true` 数出 5 件、`false` 数出 0 件。
   没有这条，若哪天 `interactive_clutter` 段被调成覆盖安全房，B 段依然全绿而业主的诉求已被破坏。
2. **A 段旧口径对照**：在**同一间真实入口房**上按旧口径算一遍，断言它显著偏离（4.00 m）。
   若 `front` 门向判断被写坏（取空 ⇒ 兜底返回零向量），这条会红 —— 不会出现"新旧口径都落在房心"的假绿。

另：C 段还断言固定五件的最远落点 ≤ 2.2 m，把 B 段的判定半径钉在**实测落点**上，不是拍的阈值。

### 不受影响的对照

| 项 | 改前 | 改后 |
|---|---|---|
| 随机撒点易碎件（`interactive_clutter`） | 713 件 / 18 间房 | **713 / 18，逐数一致** |
| 入口房作者易碎件（正式 TSCN 那批） | 24 件 | **24 件，保持** |
| 远征01 中央五件 | 5 件（`furnishing: {}`） | **5 件，保持**（未声明该键 ⇒ 缺省 true） |
| 远征02 出生点 | 朝前门偏 4 m | **不变**（不在 ID 名单里） |

### 存档不失配

`layout_id` 实测：

| 关卡 | 本轮 | 11-02 记录值 | 结论 |
|---|---|---|---|
| `expedition_03` | `f00_b5641fb3a7ead30d` | `f00_b5641fb3a7ead30d` | **逐字相同** |
| `expedition_01` | `f00_4c733531fcb31957` | — | 未受影响 |

机理：`furnishing` 与 `interactive_clutter` 同处「顶层透传、不进 `_data_driven_layout_id`
的 canonical」，加键不改几何指纹。`used_fallback=false`、`valid=true`、`entry_side=east` /
`exit_side=west` 均与改动前一致。

## 门禁

| 项 | 结果 |
|---|---|
| `scripts/check_level_decoupling.py` | exit 0（`violations: 0`，7 个通用机制容器） |
| `scripts/check_asset_runtime_naming.py` | exit 0（`ASSET_RUNTIME_NAMING_OK`，欠账只拦新增） |
| `scripts/check_documentation_contracts.py` | exit 0；17 项既有断链（编码乱码路径 / 3 篇 verify_* 未注册 / `openpyxl` 缺失），**本轮新增文件未报断链** |
| 行尾 | 4 个被改文件均纯 CRLF，`lone_LF=0`、`CRCR=0` |

## 隔离与未执行项

- 所有实跑在**工程外隔离副本**内进行（`ShellStorm2-work/verification/shellstorm-verification.probe_safe_room`，
  junction 链接主工程、独立 `config/custom_user_dir_name`），未读写主人正式存档。
- **未执行**：完整通关、全量战斗 / 寻路 / 结算套件、真实渲染截图、`core`/`aggregate` 完整套件。
  本文件不宣称整关状态提升。
- 探针**未登记进 `core_scenes`**（与 `probe_clutter_coin_drop` 同口径：只需一间房与一次真实装配，
  不必占套件预算）。手动跑法见探针文件头。
- 过程证据（qa json）留在隔离工作区，未入库。
