# 收租人躯干贴地补底柱（受击盒 16 → 17）

日期：2026-11-09；记录ID：arms_taker_ground_column；功能ID：ELITE-ROSTER / ENEMY-AI / ASSET-PIPELINE；工程版本：0.1.0。
设计依据：[精英02收租人状态与动作契约](../design/精英02收租人状态与动作契约.md) r14（r13 的“两腿之间留空”由本记录替代）。
代码基线：工作区，尚未提交；工作区含其他会话改动，本记录只归入本任务的四处文件。

## 1. 起因

业主：“身体上的这个盒子，看一下能不能往下穿一些，穿到跟地面齐平，让子弹打到身体中间也可以受到攻击伤害，不然有时候子弹打不中他。”

r13 的 16 个跟骨盒把判定压在骨段轮廓内，两腿之间刻意留空。1 级实例（`elite_level = 1`，体型系数 `1.0`）在 idle 姿态下实测：

| 项 | 世界值 |
|---|---|
| 模型 bind 身高（3.5 m 预制体 × 0.70 全局倍率） | 2.45 m |
| idle 姿态头顶判定盒顶 | 1.95 m |
| 腰盒（Waist）y 范围 | 1.04 ~ 1.36 m |
| 大腿盒 y 范围 | 0.62 ~ 1.25 m |
| 小腿盒 y 范围 | 0.05 ~ 0.73 m |
| 两腿之间未覆盖宽度（y = 0.4 / 0.8 m） | **0.448 m** |

0.448 m 的空档远大于玩家弹体直径（`SphereShape3D` 半径 0.12 m，直径 0.24 m），因此中心线上的子弹会整条穿过去 —— 与业主“打不中”的观感一致。玩家枪口高度正落在这条缝上。

## 2. 改法

新增第 17 个盒 `Volume_TorsoColumn`（`GROUND_COLUMN`），不走跟骨路径：

- **横截面**：沿用腰盒 `0.111 × 0.119` 骨骼单位（1 级 ≈ 0.27 × 0.29 m）。
- **顶边**：接腰盒顶边（骨骼局部 y = 0.072），与躯干判定重叠、无接缝。
- **底边**：每帧取当前姿态 `_sample_foot_bottoms()` 里**最低的靴底** ⇒ 与支撑面齐平。跪地、起跳时柱高随之缩短/抬起，不会插进地板也不会浮空。
- **朝向**：`Basis.from_scale(...)`，世界轴竖直，不跟躯干倾斜。倾斜的长柱会在前倾/跪地时把判定甩到空气里。
- **柱高承载**：`size.y` 固定 1.0，真实高度写进变换的 Y 缩放。已实测（`_scratch/scale_probe`）Godot 4.6 的 `BoxShape3D` 吃非均匀 basis：世界 basis = `diag(2, 4, 2)` 时 x = 0.9 命中 / 1.1 不中、y = 1.9 命中 / 2.1 不中。
- `Enemy3D._build_animated_hit_volumes()` 增加可选 `label` 键：补底柱与腰盒都锚在 `Waist`，只用骨骼名会撞节点名。

补底柱之后，两腿之间剩余两条侧缝为 0.063 m 与 0.112 m，均小于弹体直径 0.24 m ⇒ 球体必然与某一侧的盒相交，不再存在可穿弹的直通道。

## 3. 验收

`verify_second_elite_state_flow` 同步改写（原断言“打两腿之间不掉血”是 r13 的设计，本轮随业主改向一起翻转）：

- 盒数 `16 → 17`，并断言 `Volume_TorsoColumn` 存在。
- 新增三条几何断言：柱底与最低靴底差 ≤ 0.01 m；柱顶与腰盒顶差 ≤ 0.06 m；横截面 > 0.15 × 0.15 m。
- 新增行为断言：真实子弹穿过两腿之间必须掉 1 点血；真实玩家手枪打两腿之间也必须掉血。
- `verify_hit_volume_pose` 对 `ground_locked` 盒改为校验“底边始终贴支撑面”，不再要求其与骨骼变换一致。
- 靴外侧 0.18 m 处仍然打不中（回归：柱子没有把判定撑到脚外）。

| 用例 | 引擎退出码 | 结果 |
|---|---|---|
| `verify_second_elite_state_flow` | 0 | `SECOND_ELITE_STATE_FLOW_OK checks=1428`（改前 1390，新增 38 条） |

日志门禁**未通过**，原因既有且与本轮无关：该场景日志含 180 行 `ERROR: Basis [...] must be normalized ...`，堆栈全部落在 `src/vfx/VfxShellCasing3D.gd:264` 的 `_advance_settle()`（弹壳落定姿态 `slerp` 用了带缩放的 `global_transform.basis`）。该文件最后改动是 2026-10-09 `dd2a0aec`，工作区未修改；触发源是 `verify_player_pistol` 的真实手枪弹壳，与受击盒几何无关。`check_verification_log.py` 对该场景没有 `expected_errors` 条目，因此返回 3。**未修**：本轮不碰弹壳视觉。

运行方式说明：`scripts/run_verification_suite.sh` 的 preflight 在当前工作区另有两处既有红项（`check_expedition03_room_layouts.py` 在子 bash 里 stdout 落 GBK 抛 `UnicodeEncodeError`；`asset_guard.py` 不识别 `_v002` 台账命名；`sync_runtime_design_data --check` 的 3 条陈旧哈希已顺带重建）。因此本轮用同一 Godot 参数（`--headless --fixed-fps 1000`）配合隔离 `APPDATA` / `LOCALAPPDATA` 直接跑场景，再用套件同一个 `check_verification_log.py` 复核日志。

未执行：`verify_arms_taker_tactics` / `verify_arms_taker_roaming` 回归、真渲染观感、全量套件、随机布局通关。

## 3.1 r15 复核（同日两轮体型上调后重测）

§1 的 0.448 米是 **1.0 倍体型** 下的事实，保留为历史记录。同日体型先后改为 1.5 倍（1 级）与 3 倍（12 级），补底柱结论需按最终口径复核。

**第一轮校验（补底柱截面 0.111）暴露了它的极限**：腿间侧缝在骨骼单位里是 0.0261 / 0.0457，世界值 = 缝 x 3.5 x 0.70 x M(L)，**随体型线性放大**，而弹体直径固定 0.24 m。

| M | 世界侧缝 | 结论 |
|---|---|---|
| 1.5（1 级） | 0.096 / 0.168 m | ok |
| 2.14 | 0.137 / 0.240 m | 临界 |
| 2.18（6 级） | 0.140 / 0.245 m | 开始漏 |
| 3.0（12 级） | 0.192 / 0.336 m | 漏 |

也就是说 0.111 的截面只在"1.5 倍且不超过 5 级"时成立，**中段就开始漏**。故 r15 把截面 x 加宽到 **0.21**（半宽 0.105 ≥ 0.0457 + 0.0555）。

**加宽后实测（真实实例、idle 姿态）**：

| 项 | 1 级 M=1.5 | 6 级 M=2.182 | 12 级 M=3.0 |
|---|---|---|---|
| 世界身高 | 3.675 m | 5.345 m | 7.350 m |
| 头顶受击盒顶 | 2.921 m | 4.250 m | 5.844 m |
| y = 0.75 / 0.80 / 1.20 处侧缝 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

补底柱本身在 3 倍下自动跟随（柱高由变换 Y 缩放承载、横截面按实例倍率换算），除截面加宽外无需再改。

**反向对照**：把截面改回 0.111 ⇒ `verify_body_scale_curve` 报 6 级与 12 级各 3 条侧缝超弹径，退出 1。这条对照证明加宽不是"为极值兜底"，6 级就必需。

## 4. 同步的文件

- `assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/elite_arms_taker_formal_visual.gd`（`GROUND_COLUMN`、`_ground_column_transform()`）
- `src/enemy3d/Enemy3D.gd`（`_build_animated_hit_volumes()` 支持 `label`）
- `tests/verification/verify_second_elite_state_flow.gd`
- `enm_elite_arms_taker_manifest_v002.json` / `..._transfer_ledger_v002.json`（`bullet_hit_volumes.count = 17`、`.gd` 与清单哈希）
- 契约 r14、`docs/v0.1/MODULE_INDEX.md`、`06_技术施工_怪物精英与Boss.md`、`14.6_特效系统与制作规范.md`、本记录与 CHANGELOG
