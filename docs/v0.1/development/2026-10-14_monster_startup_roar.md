# 怪物启动过程与头顶吼叫图标

日期：2026-10-14；记录ID：2026-10-14-monster-startup-roar；功能ID：ENEMY-AI / ASSET-PIPELINE；工程版本：0.1.0。
设计依据与修订：`docs/v0.1/06A_怪物AI系统完整设计_评审稿.md` §6.1.1–§6.1.4（2026-10-14 新增，用户设计）、
`docs/v0.1/06_技术施工_怪物精英与Boss.md` §3.2（新增）。
资产依据：`docs/v0.1/14.6_特效系统与制作规范.md` §2.2 / §10 版本历史 v003.1。
代码基线：工作区（未提交）。
交付提交：提交后补充，提交前标记工作区。

## 变更与原因

**问题。** 业主口径：怪物从 `idle / patrol`（待机 / 巡游）跨进「攻击玩家」是瞬时的 ——
玩家在完全没有前兆的情况下挨打，无法预判也无法反应。要求加入一段**必须看得见**的过渡。

**最终行为**（用户原话拆解为三件必须做到的事）：

1. **不许直接切换**：中间有 **0.30–0.60 秒的随机启动过程**。
2. **表现顺序固定**：**先向玩家方向转过来 → 然后大吼 → 再启动攻击**。
   当前没有吼叫状态机与动作片段，所以**先不做动画**，吼叫由头顶图标承担（时序不允许缺失，表现允许兜底 —— §13 既有原则）。
3. **头顶吼叫图标**：卡通风格、`gpt-image-2` 绘制、**不要太大，按怪物体型匹配**。

**新增代码。**

| 文件 | 作用 |
|---|---|
| `src/enemy3d/MonsterStartupProfile.gd` | 时长 / 尺寸 / 偏移公式的**唯一真源**（纯计算，不持节点） |
| `src/vfx/VfxMonsterRoarIcon3D.gd` | 头顶图标特效（`extends VfxEffectBase3D`）；弹出曲线、提前退场 `dismiss()` |
| `tests/verification/verify_monster_startup_roar.gd` + `.tscn` | 专项验收（已登记 `core_scenes`） |
| `tools/roar_icon_preview.gd` | 一次性渲染工具：六档体型并排对照 |

**新增资产**（FX01-16 `VFX-MONSTER-ROAR-ICON-3D`）。

| 文件 | 说明 |
|---|---|
| `assets/art/vfx/combat_3d/vfx_monster_roar_icon_root_top3d.tscn` | 独立 Prefab（纯视觉，无碰撞体） |
| `assets/art/vfx/textures/vfx_monster_roar_icon_atlas_v001.png` | 256² RGBA 透明底贴图（SHA-256 `44df5f2c…`） |
| `art_source/vfx/combat_3d/vfx_monster_roar_icon/source/v001/` | 四版原图（v4 入选；v1–v3 保留取舍痕迹） |
| `outputs/monster_roar_icon_size_contact_sheet.png` | 六档体型对照渲染（视觉证据） |

**关键数值口径**（公式化，不给拍脑袋的数字）：

```text
T_startup     = clamp( |normalize(Δyaw)| / 520 + 0.16 + jitter , 0.30 , 0.60 )   jitter ∈ [0, 0.18]
icon_edge_m   = clamp( health_bar_width × 0.42 , 0.45 , 1.20 )
icon_offset_y = health_bar_height × 0.5 + 0.12 + icon_edge_m × 0.5
```

尺寸**按体型等比**，体型输入直接复用现行头顶血条宽度（`Enemy3D.HEALTH_BAR_SIZE_BY_KIND`），
**刻意不新建第二份体型表** —— 两份表必然漂移。实测六档：炸弹果 0.483m → 小僵尸 0.580m →
护卫/召唤 0.651m → 胖子僵尸03 0.756m → 唯一精英 0.861m → Boss 1.113m。

**兼容性影响。** 无存档字段变化、无 AssetID 复用、无既有 Prefab 路径改动；纯新增 + 新增一条验收。
图标由怪物自身持有并随怪物销毁，**不进 `VfxPool3D`**（与头顶血条同量级，池化只抬峰值）。
Boss 由 `MonsterStartupProfile.plays_startup()` 豁免，不叠加其既有激活流程。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `verify_monster_startup_roar.tscn`（headless） | 无存档依赖；只构建 mesh/material，不读 viewport 纹理 | **通过** `MONSTER_STARTUP_ROAR_OK`，`samples=142` | `_scratch/roar_verify.log` |
| `tools/roar_icon_preview.gd` 六档体型渲染 | 一次性工具，Forward+ 真窗口 | **通过**，六图标与血条同比例可见 | `outputs/monster_roar_icon_size_contact_sheet.png` |
| `check_verification_registry.py` | — | 通过（新用例已登记 `core_scenes`；**6 条既有 `unregistered` 非本次引入**） | `_scratch/vreg.log` |
| `check_feature_traceability.py` | — | 通过（EXIT=0） | `_scratch/check_feature_traceability.log` |
| `check_domain_boundaries.py` | — | 通过（EXIT=0） | `_scratch/check_domain_boundaries.log` |
| `check_media_asset_domains.py` | — | **失败，非本次引入**：`ui row count: expected 16, got 18`（本次未触碰 UI 账本） | `_scratch/check_media_asset_domains.log` |

专项验收覆盖 13 组判据，含**三条负向自测/回归钉**：

- **转角归一化**（负向自测）：`359° → -1°`、`540° → -180°`、`±180° → -180°`。
  **实装时真实踩到的缺陷**：不做归一化会拿 `359/520 = 0.69s` 去转一个实际只要 `0.002s` 的角度，
  转身段直接顶穿 0.60s 启动窗口（首轮验收报 `转身段 0.6904s 不合理（yaw=359）`）。
- **体型缩放不被弹出动画覆盖**（回归）：首版把 `_base_scale` 与弹出曲线乘在同一个 `scale` 上，
  第二次 `activate()` 会被前一次的过冲值污染（`边长 0.2898m → scale 0.3516`）。
  现改为「基准缩放 × 时间曲线」两段分离，并留断言钉住。
- **贴图真实带 alpha**：断言四角透明 + 透明/不透明像素各 >200，
  防止以后有人换回不透明底图而没人发现（那会让图标在游戏里变成一个方块）。

**未执行项**：吼叫**动画**按业主明确口径不做（动作库没有吼叫片段），由头顶图标与转身承担表现。

> **2026-10-14 追加：运行时接线已完成。** 首次交付时 `Enemy3D` 内的计时驱动尚未落地，
> 业主反馈「怪物还是直接冲过来」—— 也就是本页当时写的「不能在游戏中看到该效果」被实际触发。
> 现已接线，见下节。

## 运行时接线（2026-10-14 追加）

**根因**：`Enemy3D._physics_process` 里原是
`if ai_state == "alert" and _state_time > alert_duration: transition_to("chase")`，
`alert_duration` 缺省 0.28s ⇒ 启动过程被整体跨过，公式与 Prefab 再对也没用。

**改动**（全部在 `src/enemy3d/Enemy3D.gd`）：

| 位置 | 职责 |
|---|---|
| `_tick_alert_state(to_target, delta, alert_duration)` | `alert` 进 `chase` 的**唯一出口**；返回 true = 本帧被启动过程独占 |
| `_physics_process` | 返回 true 就直接 `return`，不跑行动 match（不抢跑的实现点） |
| `_begin_monster_startup` / `_tick_monster_startup` / `_fire_roar_icon` / `_cancel_monster_startup` | 见 `06` §3.2 的接线表 |
| `transition_to()` | 中断收口：离开 `alert` 且不是转 `chase` ⇒ 撤图标 |
| `get_state_snapshot()` | 新增 `startup_*` 字段供探针与验收读取 |

**门禁为什么抽成具名函数**：内联在 `_physics_process` 时，验收只能自己复刻一遍分支逻辑，
于是「测试绿、游戏红」—— 本次回归正是这个形态。抽出来后验收能驱动**同一条**代码路径。

**验证结果（追加）**：

| 命令/场景 | 结果 | 证据 |
|---|---|---|
| `verify_monster_startup_roar`（含 3 组接线用例 + 端到端） | **通过** `MONSTER_STARTUP_ROAR_OK`，`samples=198` | `_scratch/e2e3.log` |
| 端到端实测 | 警觉→追击 **0.6000s**（窗口 [0.30, 0.60]）；警觉窗口内推进 **0.0000m**；图标出现 **true** | `[e2e]` 行 |
| **负向对照**（拆掉门禁重跑） | **红 17 条**，含「短于 0.30s」「图标从未出现」「启动过程没走完就放行」 | `_scratch/neg_e2e2.log` |
| `verify_monster_ai_system_complete` | 通过 | `_scratch/reg_*.log` |
| `verify_3d_enemy_behavior_flow` | 通过 | 同上 |
| `verify_enemy_illumination_states` | 通过 | 同上 |
| `verify_training_range_3d_flow` / `verify_unique_elite_roster_flow` | 通过 | `_scratch/reg2_*.log` |
| `monster_startup_capture.tscn` 实拍三帧 | 通过：① 背对玩家（图标无）→ ② 转身完成（图标弹出）→ ③ 吼叫中（图标可见）；结束 `state=chase` | `outputs/monster_startup_capture.png` |

**顺手修掉一个阻塞整个工程解析的外部缺陷**：工作区里另一个会话在改的
`src/world3d/Dungeon3D.gd` 同时声明了变量 `_fate_greyscale_material`（L276）与同名函数（L5961），
GDScript 禁止同名 ⇒ `Dungeon3D` 解析失败 ⇒ `MonsterAIManager` autoload 起不来 ⇒
**所有依赖 AI 的验收与游戏内 AI 全部失效**（`verify_monster_ai_system_complete`、
`verify_3d_enemy_behavior_flow` 当时都在红）。
处置：只把**函数**改名为 `_ensure_fate_greyscale_material()` 并同步其唯一调用点，变量名与语义未动；
备份 `_scratch/other_session_fix/Dungeon3D.gd.before_roar_collab_fix`。
改完 `verify_monster_ai_system_complete` 与 `verify_3d_enemy_behavior_flow` 由红转绿。

## 改版 v002：换成红色感叹号 + 弹出停顿（2026-10-14，业主指定）

业主口径：「把吼叫的图标改成一个感叹号，然后需要有个弹出停顿一下的动画。」

### 三处改动

| # | 改动 | 说明 |
|---|---|---|
| 1 | 图形换成**红色感叹号** | 整支（长条 + 圆点）**统一纯红 `#FD0104`**，保留粗黑描边；**去掉青色高光**。不是白长条 + 红圆点，也不是粉红/洋红 |
| 2 | **新增「弹出后停顿一下」的节奏** | 四段：① 弹出 `0.70→1.15`（t=0.10 过冲）② 回稳 `→1.00`（t=0.18）③ **停顿：`0.18→hold` 全程严格静止** ④ 淡出（尺寸不变、只降 alpha） |
| 3 | 图标-血条间隙：固定 0.12 m → **按图标边长 0.30 的比例** | 换图后暴露的连带问题，见下 |

**节奏参数**（`src/vfx/VfxMonsterRoarIcon3D.gd`）：`POP_START_SCALE 0.70` / `POP_PEAK_SCALE 1.15`
（比原来的 1.08 更弹）/ `POP_PEAK_AT 0.10` / `POP_SETTLE_AT 0.18`。③ 段是**真静止**，
不是「慢慢收」；新增 `get_hold_still_seconds()` / `is_in_still_hold()` 供验收直接断言，不必在测试里重算公式。

### 🔴 换图暴露的连带缺陷：固定间隙会贴住血条

原公式 `icon_offset_y = bar_h/2 + **0.12** + edge/2` 用的是**绝对米数**。大嘴图形底部在方框内还留着空白，
所以 0.12 m 读起来很宽；**感叹号的圆点正好落在方框底部**（内容 bbox 实测占 21/256…235/256），
换成感叹号后同一个 0.12 m 就**直接贴住血条**了 —— 体型对照图实测 elite/Boss 档间隙
**−1 px（即重叠）**。

处置：改成按比例 `gap = 0.30 × icon_edge`（`MonsterStartupProfile.ICON_BAR_GAP_RATIO`），
`间隙 / 图标` 恒定 ⇒ **任何体型、任何换图都保持同样的分离观感**。复测：六档间隙 `+4 → +10 px` 等比，
真引擎实拍 `+12 px`。

> 教训：跨资产的间距不要用绝对米数去对齐一个「内容在方框里怎么摆」会随贴图变的图形。

### 验证

| 命令/场景 | 结果 | 证据 |
|---|---|---|
| `verify_monster_startup_roar` | **通过** `MONSTER_STARTUP_ROAR_OK`，`samples=229` | `_scratch/red1.log` |
| 新增正面判据：**停顿段必须真静止** | 扫 4 个时刻断言 `scale` 与 `alpha` 不变 | 同上 |
| 新增文档契约（VFX 侧 4 个弹出常量）+ 尺寸表**偏移列**逐格核对 | 通过 | 同上 |
| **负向对照**（停顿段塞入缓慢脉动） | **红 18 条**，含「停顿段不是真静止」 | `_scratch/neg_hold.log` |
| 弹停节奏取样条 | 停顿三格 `scale` 逐位相同：**0.7031 / 0.7031 / 0.7031** | `outputs/monster_startup_capture_pop_rhythm.png` |
| 端到端（真 AI + 真 `_physics_process` + 真玩家） | 警觉→追击 `0.5333s`、窗口内推进 `0.0000m`、图标出现 | 同上日志 |
| 账本门禁 | `check_asset_registry --scope structure` **OK**；`verify_ledger_split` **failure_count 仍为 3**（与改动前逐条相同，全为另一会话未提交的 FX01-17/18），**本次零新增红项** | `_scratch/ledger_gate_cwd/` |

### 账本与基线（本行，不外扩）

- 资产版本升 **v002**（图形与节奏都变了，`v001` 不再如实）；AssetID / Prefab 路径 / **Prefab SHA 均不变**
  （`.tscn` 未改，SHA 仍是 `f8910918…`）⇒ 主表 T 列不动。
- 改：主表 r35 的 M / Y；`3D-特效` FX01-16 行的 版本 / 备注；`域变更日志 v0.1.18`。
- 基线：**只**更新 `assets["VFX-MONSTER-ROAR-ICON-3D"]["v"]`。
  🔴 **刻意不重算整表摘要**：同一本《3D-特效》里有另一会话未提交的 FX01-17 / FX01-18，
  整表重算等于把他们的半成品写进我拥有的检查点 —— 那是替别人背书。
  放宽只在本行，`column_digest_drift` / `extra_assets` 本就只报告不 fail。

### 素材迭代

`art_source/vfx/combat_3d/vfx_monster_roar_icon/source/v002/`：
`exclaim_raw_a`（奶白长条+红点，形态过窄）→ `exclaim_raw_b`（等宽梯形长条，形态定稿）→
**`exclaim_raw_c`（整支纯红，最终采用）**。`build_roar_icon_atlas.py` 随源保留，可复现裁切。

## 遗留与状态更新

- **待补动画**：本轮按业主明确口径不做吼叫动画。后续哪只怪补齐吼叫动作片段后，
  图标降级为该动作的伴随表现，`MonsterStartupProfile` 的时长公式作为动画播放速率的上限约束保留。
- **未验证**：真实帧率下的观感（0.30s 是否偏短、1.113m 的 Boss 图标是否过大）需业主实机确认；
  六档对照图与端到端数值是自动化证据，不等于动态手感。**建议业主进训练场或远征01 实机看一轮。**
- **实拍工具**：`tools/monster_startup_capture.tscn`（配 `.gd`）。三帧截图 `outputs/monster_startup_capture.png`。
  两个必须记住的口径：① 读根视口纹理要等 `RenderingServer.frame_post_draw`，只等 `process_frame`
  会拿到**全透明空图**；② 读回来的帧格式随驱动可能是浮点（`FORMAT_RGBAH`），
  而 `Image.blit_rect` 在源/目标格式不一致时**静默不写** ⇒ 必须显式 `convert(Image.FORMAT_RGBA8)`，
  否则「帧本身有内容、拼出来只有背景色」。两条都实测踩过。
- **注意**：`Enemy3D` 的重复吼叫节流只按「脱战静默 3.0s」重新武装；一局内同一只怪反复遭遇时
  若觉得吼得太密或太稀，改 `MonsterStartupProfile.REARM_AFTER_SECONDS` 一处即可。
- **调参入口（v002 后）**：节奏改 `VfxMonsterRoarIcon3D` 的 `POP_PEAK_SCALE` / `POP_PEAK_AT` /
  `POP_SETTLE_AT`（后者就是「停顿从什么时候开始」）；图标与血条的距离改
  `MonsterStartupProfile.ICON_BAR_GAP_RATIO`；图标大小改 `ICON_BAR_RATIO`。
- **索引状态更新（含 v002 改版）**：`06A` §6.1.1（已实装标注 + v002 用户设计条目）+ §6.1.4（尺寸表加「间隙」列、
  间隙改比例、弹出节奏四段、运行时收口）+ §13 表现规范表；`06` §3.2（接线表 + 节奏表 + 比例间隙）；
  `README` §9.2；`14.6` §2.2 + §10 版本历史 v003.3（改版）；`design/怪物设计.md`；
  `development/2026-10-14_monster_startup_roar.md`（本页）+ CHANGELOG + README 索引；
  `MODULE_INDEX` ENEMY-AI 行；`scripts/run_verification_suite.sh` 登记 `core_scenes`。
