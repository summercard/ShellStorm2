# 2026-11-07 主角换角色（女仆 maid01）验收与修复

把 `scenes/Player3D.tscn` 的 `Avatar3D` 从 `chr_bunny01_root_v021.tscn` 换成
`assets/art/characters/player/external/maid01/chr_maid01_root_v001.tscn`
（整块蒙皮 + GLB 自带 128 段剪辑），并新增 `src/player3d/ClipMotionLibrary3D.gd`
作为该装配的动作驱动通道。本轮做验收并修掉发现的缺陷。

## 装配与驱动通道

| 项 | 值 |
|---|---|
| 装配场景 | `assets/art/characters/player/external/maid01/chr_maid01_root_v001.tscn` |
| 元数据 | `assembly_version = "clip"`、`motion_driver = "clip"`、`asset_version = "v001"` |
| 骨架 | 65 骨，`Armature/Skeleton3D`，mixamorig 命名 |
| 剪辑 | 128 段（`AnimationPlayer`，与兔子同名同数） |
| 驱动 | `ClipMotionLibrary3D`（继承 `CharacterMotionLibrary3D`，同形接口） |
| 备用 | 查克2 `chr_chuck201_root_v001.tscn`（同结构，未启用） |

装配方式：复用 `chr_player_capsule01_root_top3d_v001.tscn` 作为基座，
隐藏原 `Body/Head/Scarf/Hand/Feet` 五个回退网格，新建 `BunnyRig` 骨架层
承载 `Model`（GLB）与全部表现挂点（武器 socket / 手 / 脚 / 头 / 腰 / 背包）。

## 验收口径

**静态探针不可作为判据。** `tools/ss2_char_swap_check.gd` 的 `posture` 读数
与 tscn 里的静态 rest 值逐位吻合（差 1e-5），而那**恰好也是「骨架根本没被驱动」
的读数** —— 两者不可区分。本轮采用两条独立判据：

1. **判活**（`tools/ss2_clip_motion_probe.gd`）：跨真帧测骨骼摆幅。
   冻结在 rest pose ≈ 1e-6 m，被驱动 ≥ 1e-3 m。
2. **真渲染**（`tools/ss2_clip_avatar_render.tscn`）：出 12 格图，人眼核对外观。

## 实测数据

### 几何（静态）

| 项 | 女仆 | 查克2 | 目标 |
|---|---|---|---|
| Model 盒总高 | 1.499997 m | 1.499997 m | 1.50 ±0.03 |
| 脚底 y | 0.0000 | 0.0000 | 0 ±0.005 |
| 剪辑数 | 128 | 128 | 128 |

GLB 原始高 0.9995 × 装配缩放 1.50073 = 1.4999 m，与角色契约一致。
「整机 AABB 高 3.01」是 `ReloadProgress3D` 悬在 y=2.92 造成的 —— 世界环已退役
（`RELOAD_RING_IN_WORLD = false`，节点保留但隐藏），非缺陷。

### 判活（跨 60 真帧最大摆幅）

| 通道 | idle | moving |
|---|---|---|
| `mixamorig_Hips` | 0.0038 m | 0.0414 m |
| `mixamorig_Head` | 0.0060 m | 0.0524 m |
| `mixamorig_RightHand` | 0.0375 m | 0.1192 m |
| `mixamorig_LeftFoot` | 0.0065 m | 0.2939 m |
| 表现层 `HandJointR` | 0.0530 m | 0.1794 m |
| 表现层 `HeadJoint` | 0.0088 m | 0.0786 m |
| 表现层 `FootJointL` | 0.0099 m | 0.4411 m |

全部通道 ≥ 3.8 mm ⇒ 骨架确实被驱动，且表现挂点跟随骨骼同步。

## 修复的缺陷

### ① 武器尺度未适配（最显眼）

`_apply_bunny_attachment_scale()` 的入口是 `if not _is_bunny_avatar(): return`，
而 `_is_bunny_avatar()` 在 clip 装配下恒为 false ⇒ **整条路径没有缩放**。

武器资产统一按「2.475 m 高角色」空间建模，原角色用
`BUNNY_LINEAR_SCALE = 1.5 / 2.475 ≈ 0.6061` 缩到 1.5 m 档。我们漏了这一步，
于是枪按 2.475 m 空间原样挂在 1.2 m 角色上 —— **大了 1.65 倍**（= 1 / 0.6061）。

| 枪 | 修复前 枪长/角色高 | 修复后 | 目标 |
|---|---|---|---|
| `bp_pistol` | 0.853 | **0.517** | 0.517 |
| `bp_rifle` | 1.072 | **0.649** | 0.650 |
| `bp_machinegun` | 1.241 | **0.751** | 0.752 |

修法：把缩放真源提成 `get_attachment_scale()`，`_apply_attachment_scale()`
改为**任何装配都执行**；新增 `_apply_attachment_scale_group()` 一次性处理
换弹环 / 挂件根 / StateVFX（原先同样只在兔子下执行）。
旧函数名保留为转发别名，不动历史调用点。

**连带契约**：`_ensure_wearable_nodes()` 里把兔耳 reparent 进 `Wearables` 时
按 `1.0 / BUNNY_LINEAR_SCALE` 反向抵消 —— 两侧必须同值，改一处要看另一处。

### ② 叙事钉帧在剪辑通道缺失（开场剧情会崩）

剧本 `data/narrative/nar_tower_opening_01_wake.json` 用

```json
{"do": "actor.pose", "clip": "dead", "phase": 1.0, "frozen": true}
```

让角色**趴在地上**开场，7 秒后 `to_phase: 0.0` 反向推回实现「起身」。
老通道在采样循环里读 `pose_lock_phase`；剪辑通道走 `AnimationPlayer`，
**没有相位参数可写**，首版漏了这条 ⇒ 换角色后角色会**站着播死亡动画**。

修法：`_apply_pose_lock()` 用 `seek(phase × 剪辑长度)` + `speed_scale = 0`
实现钉帧。不用 `pause()` —— 那会把整个 `AnimationPlayer` 冻住、解除时还要
记得 play 回来；`speed_scale = 0` 与 `play()` 组合是幂等的。
同时在 `_play_clip()` 里加保护：钉帧期间不改 `speed_scale`、不做淡化切换。

实测（同一根骨在不同相位的位移）：`dead@1.0` → `dead@0.5` 位移 0.0566 m，
解除钉帧后恢复位移 0.0086 m，`state` 回到 `idle`。

### ③ 换弹上报字段缺失（验收读不出「换弹在播」）

`active_overlay` / `overlay_progress` 是跨通道契约，老通道用它上报
「正在播哪段覆盖动作、走到几成」，验收用例与
`PlayerAvatar3D._get_missing_authored_action()` 都读它。
剪辑通道首版只设了 `overlay_progress`，随后又把 `active_overlay` 清空，
于是换弹这件事在快照里读不出来（验收全红）。

修法：换弹分支同时写 `active_overlay = "<family>_reload"`，并删掉后面那行
把两个字段一起清空的赋值（顺序错了）。

### ④ 快照标志位沿用旧判据

| 字段 | 旧值 | 新值 |
|---|---|---|
| `animation_driver` | `legacy_compatible` | `glb_clip` |
| `legacy_procedural_motion_enabled` | `true` | `false` |
| `missing_authored_action` 入口 | 只在 `v021` 下判 | 按 `AUTHORED_ASSEMBLY_VERSIONS` 判 |

前两个的判据从「是不是 v021」改成「在不在作者化通道」—— clip 装配同样
**不跑** `_update_state_motion()`（见 `_process()` 的分支），所以读数必须是
`false`；沿用旧判据会给验收一个假阳性。

`missing_authored_action` 原先只在 `v021` 下判，clip 装配恒返空 ——
这个字段成了「永远没问题」的假绿灯，而它正是验收用来抓
「开火/换弹/近战缺剪辑」的那根线。

### ⑤ 所有剪辑定格在末帧（主人 2026-11-07 报告）

**现象**：跑步动作播完停在最后一帧，不循环。

**根因**：GLB 导入时若无 post-import 脚本，所有 `Animation` 的 `loop_mode`
默认为 `LOOP_NONE` ⇒ `AnimationPlayer.play()` 播完**定格末帧**。审计实测
**128 段全是 `LOOP_NONE`**，其中 73 段本该循环（`idle` / `moving` / `walking`
及全部持枪运动分支）。跑步剪辑长 0.708 s，播完就停 —— 与报告一致。

**真源**：老通道（Blender 采样库）的 JSON 里每段剪辑都带显式 `loop` 布尔
（75 true / 53 false）。**这个信息在 GLB 导入时不会被带进来**，是本 bug 的直接来源。

**修法**：`ClipMotionLibrary3D._apply_loop_flags()` 在 `bind()` 里、**任何 `play()` 之前**
把 `loop` 标记抄回 `Animation.loop_mode`。为什么不硬编码一份名字清单：
剪辑集是同一批（128 段同名），两份数据本该同源；硬编码会和未来的剪辑增删脱节。
读不到库时**不改** `loop_mode` 并在 `loop_source` 上报，不静默假装成功。

| 项 | 修复前 | 修复后 |
|---|---|---|
| `LOOP_NONE` | 128 段 | 53 段（一次性动作，正确） |
| `LOOP_LINEAR` | **0 段** | **75 段** |
| 与 JSON 库比对 | — | 匹配 128 段，不一致 **0** |

### ⑤-b 循环验收的判据设计（这条是新门禁的核心）

**标记对了不等于播放路径真的循环** —— `seek()` 钉帧、`speed_scale = 0`、
被打断的淡化都可能让画面停在末帧，而 `loop_mode` 读出来仍是 `LOOP_LINEAR`。
所以判据必须是**跨真帧观察骨骼是否周期性回归**：

| 判据 | 通过条件 | 抓什么 |
|---|---|---|
| 活性 | 过程中摆幅 > 0.002 m | 骨架没被驱动（实测严格 0） |
| 回归性 | 跑过一周期后离起点 < 0.045 m | 定格在末帧 |
| 反向对照 | 一次性剪辑（hurt/dead）追加一周期后漂移 < 0.045 m | loop 被误设成全员循环 |

**判据有效性经过反向验证**：临时禁用 `_apply_loop_flags()` 后，
`sidearm_idle` 与三个 `*_moving_forward` 的摆幅立刻变成 **0.0000** 并报红 ——
精确复现了主人的报告。恢复修复后 16/16 全绿。

**两个踩坑（都记在脚本注释里）**：

1. `get_bone_pose_position()` 读的是**静止姿态**（rest pose），AnimationPlayer
   播什么都不变 —— 首版用它量，摆幅恒 0.0000，差点把「没循环」误判成「读不到动作」。
   必须用 `get_bone_global_pose().origin`。
2. `AnimationPlayer` 靠**引擎帧**推进。紧循环手动调 `avatar._process()` 只会
   重跑运动库采样，AnimationPlayer 的时间一步没走 ⇒ 骨骼永远同姿态。
   必须 `await get_tree().process_frame`。

**阈值为什么是这两个数**：`0.002` 照着待机类剪辑定（`sidearm_idle` 实测
0.0038 m，本是呼吸级微动；而「没被驱动」是严格 0，两者可干净分开）。
`0.045` 因为采样是离散帧、一周期的结束点几乎不可能正好落在起始相位上，
运动越快错位越大（`sidearm_walking_forward` 实测 0.0271）；
而「定格」的偏差是整段动作幅度量级（跑步 0.3 m 以上），差一个数量级。

**新增正式用例**：`tests/verification/verify_player3d_clip_loop_behavior.tscn`
（16 项，已登记进 `MODULE_INDEX.md` 的 `PLAYER-STATE` 行）。

## 复核：非缺陷

**支撑手位置（`weapon_support_error_m`）**。该读数在长枪/机枪下报
0.17~0.31 m，看着像「左手没扶枪」。实测左手到**枪身包围盒**的距离：
`bp_rifle / bp_machinegun / bp_pistol` 全部为 **0.0000 m** —— 左手就贴在枪上。
那 0.3 m 是**度量口径**造成的：`weapon_support_error_m` 量的是左掌到武器
`SupportHandSocket`（护木处的名义挂点）的距离，而挂点位置与枪身几何可以差很远。
视觉上没有缺陷，**不改**。

## 复跑结果

`tools/ss2_clip_fix_check.tscn`（本轮新增的专项验收）**19 项全通过**：
武器尺度 6 项（三个枪族 × 挂载缩放 + 长度比）、叙事钉帧 5 项、换弹上报 5 项、
快照标志位 3 项。

既有玩家验收用例的失败项**分两类**（详见下一节）：

| 用例 | 修复前错误行 | 修复后 | 性质 |
|---|---|---|---|
| `verify_player3d_firing_motion` | 133 | 82 | 混合 |
| `verify_player3d_reload_motion` | 56 | 47 | 混合 |
| `verify_player3d_diy_flow` | 18 | 17 | 兔子契约 |
| `verify_player3d_avatar_bounds` | 4 | 4 | 兔子契约 |
| `verify_player3d_weapon_pose_collision_flow` | 5 | 5 | 兔子契约 |
| `verify_player3d_head_accessory_flow` | 3 | 3 | 兔子契约（节点结构） |
| `verify_player3d_directional_motion` | 3 | 3 | 兔子契约（JSON 库字段） |
| `verify_player3d_melee_motion` | 1 | 1 | 兔子契约（JSON 库字段） |
| `verify_player3d_weapon_grip_visual` | 2 | 2 | 需真渲染 |
| `verify_player3d_weapon_switch` | 1 | 1 | 待判 |
| `verify_player3d_debug_scale_flow` | 0 | 0 | 通过 |
| `verify_player3d_lower_body_socket_flow` | 0 | 0 | 通过 |
| `verify_player3d_vertical_physics_flow` | 0 | 0 | 通过 |
| `verify_player3d_melee_styles` | 0 | 0 | 通过 |

## 仍未处理：旧验收用例的装配耦合

大量既有用例的断言**写死了兔子契约**，换角色后必然失效。这些不是本轮引入的
缺陷，但会长期挡门禁。分类如下（**未擅自放宽阈值**）：

| 类别 | 例子 | 建议 |
|---|---|---|
| 网格数写死 | `Expected 10 visible Bunny mesh primitives, got 1` | 按装配取期望值 |
| 兔子专属节点 | `HeadJoint/Model`、`HeadAccessoryChibiAnime`、兔耳 | `_is_bunny_avatar()` 时跳过 |
| 版本号写死 | `assembly_version != "v021"` 即失败 | 按 `AUTHORED_ASSEMBLY_VERSIONS` |
| JSON 库字段 | 读 `motion_library_version` meta、`clips` 字典 | clip 装配改读 `AnimationPlayer` |
| 兔耳动画 | `moving ears ...`（clip 装配无耳） | 限定兔子分支 |
| 材质槽 | `Bunny DIY slot has no live GLB material mapping` | 用 clip 槽位键 |

`verify_player3d_directional_motion` 与 `verify_player3d_melee_motion` 的
`SCRIPT ERROR` 属于**硬崩**（读不存在的 `clips` 字典键），优先修；
其余是可读的断言失败，按装配分支收敛即可。

## 交付物

| 文件 | 作用 |
|---|---|
| `src/player3d/ClipMotionLibrary3D.gd` | 剪辑驱动通道（本轮补钉帧 + 换弹上报） |
| `src/player3d/PlayerAvatar3D.gd` | 装配缩放真源 + 标志位判据（本轮修） |
| `src/player3d/Player3D.gd` | `character_authored_reload` 认 `clip`（上一会话） |
| `tools/ss2_clip_motion_probe.tscn` | 判活探针（跨真帧摆幅） |
| `tools/ss2_clip_fix_check.tscn` | 本轮修复专项验收（19 项） |
| `tools/ss2_clip_avatar_render.tscn` | 真渲染取证（12 格出图） |
| `tools/ss2_assembly_scale_probe.tscn` | 装配尺度实测 |
| `tools/ss2_support_hand_probe.tscn` | 支撑手实测 |
| `outputs/verification/ss2_clip_avatar_lineup.png` | 12 格出图（修复后） |

清理：本轮产生的 13 个临时输出文件与 7 个批处理脚本已移出仓库
（备份在 `I:\ShellStorm2-work\charswap_backup\`）。
