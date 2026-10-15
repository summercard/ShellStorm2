# 背包挂到胸前的修复（2026-10-14）

- FeatureID：`INVENTORY-SLOTS` / `ASSET-PIPELINE`
- 业主口径：「我发现背包的挂点怎么会在胸前？还是说背包挂到胸前去了？……现在装备背包跑去胸前去了。」

## 一、症状与定位

**症状**：装备 2/4/8 格背包后，背包模型出现在角色**胸前**而不是背后。

**实测（探针，`BodyJoint` 局部空间，`v021` 骨架）**：

| 节点 | 躯干空间 z | 侧 |
|---|---|---|
| `WeaponSocket`（手部持握，前方锚） | −0.205 | 身前 |
| `StowedWeaponSocket*`（武器背负，后方锚） | +0.581 | 背后 |
| 作者手写 `BackpackSocket` | +0.335 | 背后（正确） |
| **运行时背包模型（修复前）** | **−0.344** | **身前（错误）** |
| 躯干可见包络 | z ∈ [−0.200, +0.200] | — |

**结论**：背面是 **+Z**，运行时偏移写了负号，把包放到了躯干前面。

## 二、两根缺陷叠在一起（第二根是真正的根因）

### 缺陷 A：方向反了

`v021` 骨架背面为 `+Z`，但 `Player3D._refresh_backpack_model()` 用的是：

```gdscript
_backpack_follow.position = Vector3(0.0, 0.04, -0.20 - size.z * WORN_SCALE * 0.5 - 0.015)
```

`−0.20 − ...` 把包放到躯干**前面**。同时 `y = 0.04` 是凭感觉写的高度，与作者手写的 `BackpackSocket`（`y ≈ 0.586`）也不一致。

### 缺陷 B：验收量法失效 —— 这才是让缺陷 A 藏了两个月的根因

`tests/verification/backpack_asset_contract.gd:measure_worn()` 每帧先跑动作驱动器 `motion.apply()`，然后量 `pack_bounds`。但它**没有调用运行时自己的 `Player3D._sync_backpack_body_follow()`**。而实现里：

- `_sync_backpack_body_follow()` 由 `PlayerAvatar3D._process()` 驱动，**在 `_process` 里、不在 `_physics_process` 里**；
- 测试是被 `PROCESS_MODE_DISABLED` 冻结的角色，且自己手动跑 `motion.apply()`。

⇒ 测试量到的 `_backpack_model.global_transform` 是**上一帧（甚至更早）的陈旧值**，背包在躯干空间里的位置随动作漂移，**三项判据全部变成噪声**：

| 判据 | 修复前实测 | 阈值 | 结果 |
|---|---|---|---|
| `max_back_gap` | 0.4519 / 0.4101 / 0.3965 | `< 0.04` | 全红 |
| `head_clearance` | −0.7615 / −0.7929 / −0.8322 | `≥ 0.015` | 全红 |
| `max_follow_error` | 0（**静默假绿**） | `< 0.0001` | 假绿 |

`max_follow_error` 之所以是 0，是因为同一段代码把节点按 `RemoteTransform3D` 取：

```gdscript
var follow := player.get("_backpack_follow") as RemoteTransform3D   # 实现是普通 Node3D
```

取到 `null` 后整条 `if follow != null:` 被短路，**「背包未跟随躯干」这条断言从未真正执行过**。

**判据本身也是无效量**：`head_clearance` 用了 `max(pack.min_z − head.max_z, head.min_y − pack.max_y)`，其中 `head.max_z` 恒为 **+0.44**（头在背后的边界），而包也在背后 ⇒ 该分量恒为**大负数**，**任何**背后位置的背包都必然失败。这条判据从写下那天起就不可能通过，等于从未在守任何东西。

**追溯**：`Player3D` 侧的负号与 `0.68` 从 `ed7c4da0`（2026-10-08，背包首次入库）就是如此，契约文件同轮引入。这段代码从未真正通过过自己的验收。

## 三、修复

### 产品侧（`src/player3d/Player3D.gd`）

把背负贴合做成**显式契约常量**（全部 `BodyJoint` 局部空间，`v021` 实测）：

| 常量 | 值 | 含义 |
|---|---|---|
| `BACKPACK_WORN_HEAD_BOTTOM_Y` | `0.272` | 头部动作包络最坏下沿（91 片段逐相位实测，出自 `landing@0.425`） |
| `BACKPACK_WORN_HEAD_CLEARANCE` | `0.020` | 包顶净空（判据要求 `≥ 0.015`） |
| `BACKPACK_WORN_TOP_Y` | `0.252` | `= 0.272 − 0.020` |
| `BACKPACK_WORN_BODY_BACK_Z` | `0.20` | 躯干可见包络背面 |
| `BACKPACK_WORN_BACK_GAP` | `0.012` | 包前脸与躯干背面的缝 |
| `BACKPACK_WORN_SCALE` | `0.40` | 背负显示倍率（**只作用于角色背负表现**） |
| `BACKPACK_WORN_FLOOR_Y` | `-0.155` | `BodyJoint` 局部的地面高度 |

摆放规则（**顶对齐**）：

```
follow.position.y = TOP_Y − size.y × k / 2
follow.position.z = BODY_BACK_Z + size.z × k / 2 + BACK_GAP
```

`_sync_backpack_body_follow()` 里的写死 `0.68` 改为引用 `BACKPACK_WORN_SCALE`（原先有两份独立数字，改一处就会不同步）。

### 验收侧（`tests/verification/backpack_asset_contract.gd`）

- 每帧在 `motion.apply()` **之后**调用 `player._sync_backpack_body_follow()`，并 `force_update_transform()` 到模型，量真实当帧位置。
- `follow` 改按 `Node3D` 取，不再按 `RemoteTransform3D`。
- 新增两条显式接线断言：模型必须挂在 `BackpackSocket` 下、跟随节点必须挂在躯干下。
- 缩放判据改读 `Player3D.BACKPACK_WORN_SCALE` 常量。
- 新增「包底不得沉到地面 `+0.02` 以下」。

`tools/asset_pipeline/render_backpack_acceptance.gd` 里写死的 `0.68` 同步改读常量。

## 四、倍率上限为什么是 0.40（给公式）

躯干只有 **0.323 m 高**（`y ∈ [0, 0.323]`）：

- 包顶被头部下沿压住：`y_top ≤ 0.272`
- 包底要留在地面之上：`y_bottom ≥ −0.155 + 0.02 = −0.135`
- ⇒ 可用竖向带宽 `= 0.252 − (−0.135) = 0.387 m`

8 格源高 `0.88 m` ⇒ `k ≤ 0.387 / 0.88 = 0.44`。取 `0.40` 留余量。

**实测对照**（解析式测量，`follow.position ± size×k/2`，因契约已断言背包几何以原点为中心）：

| 方案 | 站立相交帧 | 全动作最小头间距 | 包底离地 | 判定 |
|---|---|---|---|---|
| `k=0.40`（已采用） | 0 | **+0.020** | 0.055 | 契约全绿 |
| `k=0.49`（按常态直立包络放宽） | 0 | −0.024（`landing@0.425`） | 0.020 | 落地帧穿头 |
| `k=0.56`（过肩） | **246** | −0.079 | 0.020 | 站立即穿头，且离背 0.042 超阈值 |

另实测确认**躯干动作包络与静态包络一致**（`z` 最大 `0.2000`，出自 `walking@0.9`；静态也是 `0.2000`）⇒ `BODY_BACK_Z` 量一次即可，不会被动画拱出。

## 五、三档一致性的取舍

共用同一倍率 ⇒ 宽 `1.000 : 1.179 : 1.357`、高 `1.000 : 1.233 : 1.467`，严格保持源比例。

**曾被否掉的方案**：逐档各抬到 `0.94 / 1.09 / 0.95`（即把大包缩小、小包放大以求「都好看」）。这会让三档宽 `0.526 / 0.719 / 0.722`、高 `0.564 / 0.807 / 0.836` ⇒ **4 档与 8 档几乎同体积**，大小档位在背后机位不可读。**不允许**。

**后端约束（需产品确认）**：躯干只有 `1.5m × 0.462m × 0.323m`，任何「正常尺寸的背包」都不可能既贴背又不进头部动作包络。三档之间在背后机位只能靠**配色与外形细节**读（`2槽` 无扣带 / `4槽` 1 扣带 / `8槽` 2 扣带 + 顶部卷铺盖）。**几何尺寸差不可再放大。**

**不改头部动画的理由**：抬高头部为容纳更高的包，会连带改头部节点的静态位置与全身动作基线（`verify_player3d_avatar_bounds` 等已验收套件随之全动），收益是「包能大一档」，风险远大于收益。故本轮不动骨架。

## 六、验收

| 项 | 结果 |
|---|---|
| `verify_backpack_equipment_flow` 位置三项（`离背` / `侵入头部` / `跟随`） | **全绿**：`BACKPACK_HEAD_FIT slots=2/4/8 gap=0.020018 samples=3731` |
| 缩放判据 | 绿（读常量） |
| 包底不沉地 | 绿（8 槽离地 0.055） |
| `verify_player3d_diy_flow` | `PLAYER3D_DIY_FLOW_OK` rc=0 |
| `verify_wardrobe_preview_fill_flow` | `WARDROBE_PREVIEW_FILL_FLOW_OK` rc=0 |
| `verify_player3d_avatar_bounds` | `BUNNY_V008_BOUNDS_OK` rc=0 |
| 真实渲染 | `outputs/backpack_worn_fix_20261014/`：`worn_{back,three_quarter,side,front}.png` 确认背包在躯干背面 |
| 临时探针 | 已全部删除（量法已并入契约文件） |

**常量推导依据（本地产物，`outputs/*` 不入版本库，复查时可重新生成）**：

| 文件 | 支撑的常量 |
|---|---|
| `outputs/backpack_worn_fix_20261014/measure/backpack_socket_probe.txt` | 定位「胸前」的关键证据：各挂点与运行时模型的躯干空间 z |
| `.../measure/head_envelope_worst.txt` | `BACKPACK_WORN_HEAD_BOTTOM_Y = 0.272`（出自 `landing@0.425`） |
| `.../measure/body_envelope_motion.txt` | `BACKPACK_WORN_BODY_BACK_Z = 0.200`（躯干动作包络 ≡ 静态包络）＋ 三档比例 |
| `.../measure/backpack_worn_sweep.txt` | 倍率上限 `k ≤ 0.44` 的竖向带宽推导 |

## 七、同轮发现、未处理（如实登记）

`99955a3b`（2026-10-13，道具低模生产流程 v0.2）重生产背包资产后三角数升到 **`322 / 334 / 424`**，与 `ed7c4da0` 时期收紧的契约预算 `≤100` 冲突 ⇒ `verify_backpack_equipment_flow` 稳定报 **6 条红**（每档 2 次，来自装备段与背负段各量一次）。

三角数与资产清单元数据（`triangle_count` 424）**自洽**，属该轮资产重做的**有意变更**。按「不擅自改契约预算」原则保留 `≤100` 原值待裁定，**不在本次修复范围**。该测试在 `run_verification_suite.sh` 的 `core_scenes` 内，因此套件仍会在这 6 条上红。
