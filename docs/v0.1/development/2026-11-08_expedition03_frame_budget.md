# 远征03「一直卡、一顿一顿」的帧预算归因（及一处 35% 的纯浪费）

日期：2026-11-08。功能：PERFORMANCE-RUNTIME / WORLD-LIGHT。
关联：[性能优化与热管理](../13_技术施工_性能优化与热管理.md)、[关卡进入与冷启动预热设计](../design/关卡进入与冷启动预热设计.md)、[材质变体代价](2026-10-31_hit_flash_material_variant_cost.md)。

业主报单：

> 「我现在在游戏内还是很卡，还会一顿一顿的。」

上一轮（11-07）刚修完「预热没在开圈前排空」，那条确实修好了。所以这次先不假设"还是同一个问题"，
而是按 [13 §8](../13_技术施工_性能优化与热管理.md) 的验收定义重新采一遍分项。

---

## 零、结论

三句话：

1. **上一轮那句「18~19 ms 的底子是渲染，4300 draw call」是错的。** 那是 `application/run/max_fps=60`
   的**限帧读数**，`set_process(false)` 前后不变也正是因为限帧器在决定 p50 —— 那个对照在限帧下零信息量。
2. **真实底盘是 GPU 19.0 ms**（720p / RTX 3060 / Forward+ 高档），而它在 60 fps 预算 16.67 ms 之外
   ⇒ 96.6% 的帧都掉出 60 fps。这是"一直不太顺"的来源。
3. **GPU 的 19 ms 里有 6.75 ms 是纯浪费**：27 盏开着阴影的灯中，24 盏 `light_energy == 0` ——
   玩家看不见的房间里那些不发光的灯，每帧仍在渲染完整阴影贴图。修掉后 **19.18 → 12.43 ms（−35%）**。

| 项 | 修前 | 修后 |
|---|---:|---:|
| GPU p50 | 19.03 ms | **13.10 ms** |
| 墙钟 p50（解除限帧） | 19.02 ms | **13.14 ms** |
| 超 16.7 ms 的帧 | 575 / 595（96.6%） | **17 / 595（2.9%）** |
| 超 50 ms 的帧 | 25 | 7 |
| Draw Call | 3752 | 1736 |
| 图元 | 1209 万 | 712 万 |
| 渲染对象 | 8443 | 4908 |

画面差异为 **0**：被关掉阴影的那 24 盏灯本来就不发光。

---

## 一、先把口径钉死（上一轮错在这里）

`project.godot` 有 `application/run/max_fps=60`。[13 §6.1](../13_技术施工_性能优化与热管理.md) 已经写过：

> 此前文档中的约 `6.88ms` 是未显式限帧时 `await process_frame` 的墙钟间隔，不能代表 60FPS 发布节拍。
> 短场景性能预算明确把 16.67ms 主动等待计入墙钟，并以 18ms 作为调度容差。

上一轮读到 p50 `18.3 / 18.6 / 17.8 ms`，正好是 16.67 + 调度容差 —— 那是限帧器的输出。
更关键的是：**限帧环境下 `tower.set_process(false)` 前后 p50 不变，不能推出"瓶颈不在脚本"**，
因为 p50 由限帧器决定。这条对照必须在 `Engine.max_fps = 0` 之后才成立。

本轮的采集口径：

```
Engine.max_fps = 0                     # 解除限帧
RuntimePerformanceManager.focused = true
RenderingServer.viewport_get_measured_render_time_cpu(vp)
RenderingServer.viewport_get_measured_render_time_gpu(vp)
Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME / PRIMITIVES / OBJECTS
```

⚠ `RuntimePerformanceManager.set_verification_frame_budget_override(0)` 会**立刻把 limit 写回前台的 60**，
所以顺序必须是「先让它应用一次，再解限帧」，否则解限帧那一行白写（本轮踩过）。

⚠ `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` 在本工程读不可信（实测 > 墙钟，口径不符），
本记录**不把它们当结论**，只用 `render_cpu` / `render_gpu` / draw call 这类独立来源。

---

## 二、分项：底盘在哪

真实入口（选关 → 读取页 → 预热 → 落地 → 稳定 120 帧后采样 600 帧）：

```
states={ ACTIVE:1, DATA_ONLY:22, SHELL_READY:1 }  enemies=0  nodes=26877
wall        p50=19.02  p95=20.58  max=430.38
render_cpu  p50= 3.58  p95= 4.66
render_gpu  p50=18.96  p95=20.03
draw_calls  p50=3752
primitives  p50=1209 万
over16=575/595   over33=25   over50=25
```

`墙钟 19.02 ≈ render_gpu 18.96`，`render_cpu` 只有 3.58 ⇒ **主线程在等 GPU**。
提交侧（3.6 ms）很轻，所以"合批降 draw call"不是这一轮该投的方向。

### 2.1 GPU 里是几何还是后处理

默认档（`GraphicsSettingsManager.DEFAULT_SETTINGS`）全开：TAA + Bloom + SSAO + SSIL + SSR +
SDFGI(high, 4 级联, 204.8 m) + 体积雾 + 距离雾 + 4096 阴影。

四段对照（每段 240 帧）：

| 段 | 处置 | GPU p50 | Draw Call | 图元 |
|---|---|---:|---:|---:|
| A | 原样 | 19.03 ms | 3805 | 1294 万 |
| B | 关全部后处理 | **16.47 ms** | 3808 | 1295 万 |
| C | 隐藏整个世界 | 1.67 ms | 106 | 3073 |
| D | 两者都关 | 0.33 ms | 106 | 3073 |

⇒ **后处理只占 2.56 ms，几何占 17.4 ms。** 降画质档（SDFGI/SSIL/SSR/体积雾）救不了这个，
因为钱不在后处理里。

### 2.2 几何里有多少是玩家看不见的

远征03 是**单层室内**关卡，玩家同一时刻只可能在 1~2 间房里。

| 段 | 处置 | GPU p50 | Draw Call | 图元 |
|---|---|---:|---:|---:|
| A | 原样 | 19.05 ms | 3827 | 1298 万 |
| B | 隐藏 23 间非当前房 | 10.53 ms | 1115 | 173 万 |
| C | 关全部灯的阴影 | **4.92 ms** | **192** | 58.5 万 |
| D | 两者都做 | 4.48 ms | 183 | 19 万 |

C 这一列是决定性的：**关掉阴影后主 pass 只剩 192 个 draw call**。
也就是说 3827 个 draw call 里 3635 个来自阴影 pass —— 视锥剔除对主 pass 有效，对阴影 pass 无效。

---

## 三、根因：能量为 0 的灯仍在投阴影

把 27 盏 `shadow_enabled` 的灯点名（`tools` 侧只读探针）：

```
DirectionalLight3D            energy=2.95   ← 太阳
ForwardBeam (SpotLight3D)     energy=0.00   ← 手电未开，合理
LampLight (start)             energy=14.98  ← 当前房主灯
IndoorEnvelopeBounce × 24     energy=0.00   ← 其中 22 属于 DATA_ONLY、1 属于 SHELL_READY
```

`IndoorEnvelopeBounce` 由 `Expedition03IndoorLightEnvelope._add_room_bounce()` 给**每间房**挂一盏，
`shadow_enabled = true`（注释理由是正确的：室内主光必须自己投影，否则家具失去落地阴影）。

但非 ACTIVE 房的能量被 `DungeonRoom3D._sync_supplemental_room_lights()` 归零：

```gdscript
light.light_energy = float(_supplemental_room_lights[light]) if enabled and active else 0.0
```

**能量归零，`shadow_enabled` 没跟着关。** 能量 0 只表示"不发这个光"，不表示"不用为它渲染阴影贴图"。
于是 23 间玩家进不去的房间，每帧各渲染一遍完整阴影。

精确对照（只关 `energy == 0` 的那 24 盏，保留太阳/手电/当前房主灯）：

| 段 | 处置 | GPU p50 | Draw Call | 图元 |
|---|---|---:|---:|---:|
| A | 原样 | 19.18 ms | 3831 | 1301 万 |
| B | **只关 24 盏零能量灯阴影** | **12.43 ms** | 1731 | 709 万 |
| C | 再关剩下 3 盏 | 4.97 ms | 192 | 58.6 万 |

**B 就是可行的修法收益：−6.75 ms / −35%，画面零差异。**

这也顺带纠正了一条既有记录的口径：13 §3.6 写「阴影只允许太阳、手电主光、当前房主灯三者
按质量档竞争预算」。实测 27 盏里**只有 3 盏真的在发光**，条文本身没错；
错的是"能量归零"这条路径没把阴影一起关掉，让 24 盏空灯绕过了预算。

---

## 四、修法

`src/world3d/DungeonRoom3D.gd`：

- 新增 `_apply_supplemental_shadow_state(light)`：能量 `<= 0.0001` 时关 `shadow_enabled`，
  恢复时按 meta 里记下的**原始意图**还原。
- `_sync_supplemental_room_lights()` 的两条分支（正常 / `reactive_light_disabled`）都调用它。

**为什么不能一律写 `true` 恢复**：`IndoorEnvelopeDarkFill` 这类底光本来就
`shadow_enabled = false`（见 `_add_dark_fill` 注释第 3 条），一律写 true 会给它凭空加一套假影子。

**为什么用 meta 而不是新字段**：灯可能是作者 TSCN 里的资产（`WastelandLight3D`），
不能假设有自定义属性；meta 对任意 `Light3D` 都成立。

代价：能量在 0 与非 0 之间切换时翻一次 `shadow_enabled`，会触发一次阴影管线准备。
但这只发生在**进出房间**，而进房本来就有 100~500 ms 的 `RuntimeDetail` 构建，这笔被淹没。

---

## 五、验收

| 项 | 命令 | 结果 |
|---|---|---|
| 灯清单（headless） | 只读探针 | `shadow_enabled` **26 → 4**（太阳 / 手电 / 当前房主灯 / 当前房 bounce） |
| 用户视角帧时（真渲染） | `Engine.max_fps=0` 采样 600 帧 | GPU 19.03 → **13.10 ms**；超 16.7 ms 帧 575 → **17** |
| 基地灯动态 | `verify_base_lamp_dynamics` | `ACCEPT base_lamp_dynamics` |
| 房间灯开关 | `probe_room_light_switch` | 贴墙/朝向全 OK |
| 房间灯落位 | `probe_expedition_room_light_footprint` | 既有红项，与本改动无关（见下） |

`probe_expedition_room_light_footprint` 报 `room_04 顶灯落位不在真砖格上`、
`start/room_08/room_09 站上可走砖后仍无交互候选`。这些是**布局与交互候选**判定，
不读 `shadow_enabled`；用 `git stash` 对照跑未修改版本，红项逐条相同。

---

## 六、还没做的

| 项 | 现状 | 量级 |
|---|---|---|
| 剩下 7.46 ms 阴影 | 太阳（室内其实被顶盖挡住）+ 当前房主灯 + 当前房 bounce | 12.43 → 4.97 ms 是上界，但**不能直接关**：室内主光投影是玩法读图信息 |
| 事件帧尖峰 | 进房建 `RuntimeDetail` 114~507 ms、首波刷怪同帧 ~545 ms | 采样里仍有 7 帧 > 50 ms，max 511 ms |
| 远房结构件主 pass | 视锥剔除已生效（主 pass 仅 192 draw call），不是问题 | — |
| 后处理 | 只占 2.56 ms | 降档收益有限，不要再往这里投 |

**下一个该动的是事件帧尖峰**（进房建 detail、首波同帧刷怪），不是稳态帧时 —— 稳态已经有 3.5 ms 余量。

---

## 七、探针口径备忘（防重犯）

1. **先 `Engine.max_fps = 0`，再谈墙钟**。工程写死 60，不解除就是在量限帧器。
2. **`set_verification_frame_budget_override(0)` 会把 limit 写回 60**，必须在它之后解限帧。
3. **`Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` 在本工程读不可信**（实测大于墙钟），
   结论必须落在 `render_cpu` / `render_gpu` / draw call 这些独立来源上。
4. **"关掉某类东西后 draw call 掉多少"比"总 draw call 多少"信息量大**：
   这次就是靠「关阴影后只剩 192 draw call」才确定 95% 的 draw call 在阴影 pass 里。
5. `--headless` 下阴影/变体不重建，这类结论**必须真渲染 + `--disable-vsync`**。
