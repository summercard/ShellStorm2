# 远征01 room_01 进场即撞怪：盒位后移拉开进场缓冲

日期：2026-11-02；FeatureID：`WORLD-PLAN`；工程版本：0.1.0；交付：当前工作区，未提交。

代码基线：改动前设计源备份 `ShellStorm2-backup/2026-11-02_room01_entry_buffer/before_edits/floor_00.json.design_src`；运行时投影由 `scripts/sync_runtime_design_data.py` 生成，未手改。

> ⚠ **实现状态（2026-11-02 23:30 复核：未落地）**：本文描述的盒位后移在当前工作区**不存在**。
> 判据：`data/level_plans/expedition_01/floors/floor_00.json` 的 `box_room_spread` 仍是 `[-12.5, -2.5]` / `[-10.0, -12.5]`（未后移），`git status -- data/` 为空。
> 疑似被当日 17:07 的 `git pull --rebase` 洗掉。改前快照已入库，重做时按本文复跑并复验，**不要凭本文的"已完成"判定完成**。

## 用户要求与复现

业主：*「第一个房间，有一个入口进去，会直接迎面撞上一堆怪」*。

先量现状再改。`room_01` 运行时 40×45 m、L 形（`corner_ambush`/`room_spread` 均在竖臂，`wall_arc` 在横臂），进门口（安全屋方向、南墙 `lane −12.5`）局部 `(−12.5, 22.5)`：

| 盒 | 运行时盒心 | 盒心距进门口 | 盒边距进门口 | ×2 后只数 |
|---|---|---:|---:|---|
| `box_room_spread` | `[−12.5, 10.0]` | **12.50 m** | 10.50 m | 6（近战 4 ＋ 炸弹果 2） |
| `box_corner_ambush` | `[−12.5, −5.0]` | 27.50 m | 26.00 m | 4 |
| `box_wall_arc` | `[2.5, −15.0]` | 40.39 m | 38.75 m | 4 |

三盒 `drift = 0.00`（声明即落地，无平移），故「迎面」不是平移漂移造成的，是**声明坐标本身就压在门轴上**：前两盒 `x = −12.5` 与进门口同列。竖臂净宽 15 m（3 砖）、`box_room_spread` 占 4 m ⇒ 两侧各 5.5 m 是墙，**没有任何绕行通道**。首群还含 2 只炸弹果（贴脸自爆），与「本关第一次接触战斗」的节奏不符。

`trigger` 侧不是原因：`room_01` 走触发盒单波，没有 `encounter.trigger`；但 `monster_rules.ai.preactivation_range_m = 38.0` 按**纯平面距离**唤醒、不查视线 ⇒ 门一开，12.5 m 与 27.5 m 两群共 10 只同时进入运行态。

这是一条已复现的原因，不声称覆盖其他房与其他种子。

## 修正与所有权

改的是**数据**，不是机制。设计源 `art_source/design/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json` 的 `room_01.spawn_placements[].center_m` 三条：

| # | 盒 | 改前（JSON 帧） | 改后（JSON 帧） | 改后运行时帧 | 距进门口 |
|---|---|---|---|---|---:|
| 0 | `box_room_spread` | `[−10.0, −12.5]` | `[15.0, −12.5]` | `[−12.5, −15.0]` | 37.50 m |
| 1 | `box_corner_ambush` | `[5.0, −12.5]` | `[0.0, −12.5]` | `[−12.5, 0.0]` | **22.50 m** |
| 2 | `box_wall_arc` | `[15.0, 2.5]` | `[15.0, 7.5]` | `[7.5, −15.0]` | 42.50 m |

两套帧都在表里给出：`center_m` 是**设计源帧**，运行时会按房间落位姿态（本房 90°）转一次；直接把运行时坐标写进 JSON 会把盒子转到别处。

**没有改的东西**（逐项确认）：

- `count_multiplier: 2` 三条保留 ⇒ 三盒仍是 6 / 4 / 4 = **14 只**，房总不变；
- `encounter.stages` 仍是单波 `{"boxes": [0, 1, 2]}`，波次结构不变；
- `data/spawn_boxes/*.json` 盒资产**未动** —— 五个小盒被 11 间房与 Boss 房共享，改资产会连带改别的房（§3.2.3 同一理由）；
- `rotation_deg` 未动（盒 2 仍 `90`，运行时合成 180）；
- `room_02` 与其余 12 房未动；
- 无代码改动、无 `monster_rules` 改动、无掉率改动。

**为什么顺序变成「先 4 只、后 6 只」**：进场第一眼看到的是 4 只小僵尸而非 6 只含炸弹果，压力曲线从低到高；第二群落在拐角之后（`z < −10` 才进横臂），而 AI 视线只有 8.5~15.5 m，**隔着墙角不会一开门就扑上来**。

**存档影响**：`spawn_placements` 不在 `_data_driven_layout_id` 的 canonical 里（与挪盒位同一条既有裁定），**不断旧存档**。

**`room_02` 刻意未动，列为待裁定**：它两盒距各自门口都是 7.50 m（盒边 5.50 m），物理上比 `room_01` 改前还近；但那是业主 2026-10-15 亲自钉的「中线左右两群」（两盒 `x = ±12.5`、同处 `z = −2.5` 主通行线，60 m 联动半径），**动它就是改业主口径而不是修缺陷**。本记录不擅自处理。

## 本次验收

所有 Godot 进程启动前独立隔离 `APPDATA`、`LOCALAPPDATA`、`XDG_DATA_HOME`、`XDG_CONFIG_HOME`（`I:\ss2_probe_appdata\final\`）；日志在工程外，未写入工作区。

| 验收 | 退出码与结果 | 预期故障 / 非预期错误 |
|---|---|---|
| `sync_runtime_design_data.py` | exit0；41 份投影，`issues: []` | 无预期故障，0 条错误 |
| `sync_runtime_design_data.py --check` | exit0；无投影漂移、无 manifest 漂移 | 无预期故障 |
| `probe_expedition01_door_box_distance`（种子 77001199） | exit0；三盒 `drift = 0.00`，距进门口 **22.50 / 37.50 / 42.50 m**（改前 12.50 / 27.50 / 40.39） | 无预期故障，0 条 ERROR/SCRIPT ERROR |
| `probe_expedition01_wave_counts`（种子 77001199） | exit0；`room_01\|1\|0..2` 实到 **6 / 4 / 4**、`short = 0`、`trunc = 0`、`drift = 0.00`；全关 `realized = 83 / design_max = 95 / trunc = 5 / drift_sum = 35.88 / drift_rows = 22` | 无预期故障；`trunc = 5` 为 Boss 房既有缺陷，改前后逐值相同 |
| `check_verification_log.py`（两份日志） | exit0；无非预期脚本/引擎错误 | — |

选点用的临时探针 `_scratch/probe_room01_entry_buffer.gd/.tscn`（全砖心 × 3 盒型的原地容量矩阵）**不进验收链**，只用于挑盒位；三个新盒心容量 7 / 4 / 6 ≥ 需求 6 / 4 / 4，判据 H 净距 7.5 m ≥ 5 m、判据 I 盒间距 ≥ 15 m。

改动后 `room_01` 的编成、只数、单波结构与改动前完全一致，**变的只有位置**；全关五项统计逐值不动 ⇒ 本次不影响其它房的既有红项判定。

## 范围与未执行项

- 只验了种子 77001199 一个；不同种子下盒位是固定的，但玩家走位与触发时序不同，未做多种子复测。
- **未做真实渲染下的观感复核**：无头帧率与相机不进房，不能证明「进门看到的是 4 只而不是 6 只」在真机上成立；这一条需要业主实机确认。
- `room_02` 的 7.5 m 近距离保留原状，待业主裁定是否按同一思路后移。
- 未跑全量 core/full、Android；`verify_expedition_level01_flow` / `verify_expedition01_spawn_ramp` 的既有红项（同 12 条 / 3 条）本次未复跑，本记录不改变其结论。
- 临时探针留在 `_scratch/`，未登记进验证登记表。
