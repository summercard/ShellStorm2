# 2026-10-23 角色全动画演示：128 个剪辑铺进同一张画面

业主：「帮我录制一套角色的所有动画演示，放在一个画面里的。」

交付两个文件（`outputs/anim_showcase_v001/`）：

| 文件 | 规格 | 内容 |
|---|---|---|
| `角色全动画总览.jpg` | 3840×3432 | 128 格静帧，每格取代表性相位 |
| `角色全动画演示.mp4` | 2880×2522 / 30fps / 15s / H.264 | 128 格同时循环播放 |
| `角色全动画演示_封面.jpg` | 2880×2522 | 视频首帧带标签版 |

## 1. 做法

三段，全部只读：

1. `tools/anim_showcase_capture.gd`（新场景 `tools/anim_showcase_capture.tscn`）——
   读 `anim_bunny01_library.json`，在 `SubViewport` 里摆 N×M 个 bunny01 变体实例，
   把骨骼帧手工采样到 `BodyJoint / HeadJoint / EarSocketL/R / HandJointL/R / FootJointL/R /
   WeaponSocket`，正交相机一次拍全，逐帧 `get_texture().get_image()` 存 jpg。
2. `scripts/render_anim_showcase.py` —— 排版（族分区 → 12 列）、调 Godot、PIL 贴中文标签
   与族色条、ffmpeg 编码。
3. 标签层做成独立的 `overlay.png`，静帧 `alpha_composite`、视频 `ffmpeg overlay`
   叠同一张 —— 两条链路共用一份排版，不会出现「图上有字、视频里没字」。

**没有复用 `PlayerAvatar3D._process`。** 那个状态机每帧都会覆写骨骼，且需要真实
`Player3D` 父节点；这里保留脚本只为拿它 `_ready()` 里的外观装配（面部电子面罩、配色），
随后 `set_process(false)`。

## 2. 踩到的三个坑（都是量出来的，不是猜的）

### 2.1 `visual_root.scale` 不能手动设

第一版按 `BUNNY_LINEAR_SCALE = 1.5/2.475` 自己设了缩放 → 角色只有格子高度的 **44%**。
根因：`PlayerAvatar3D._ready()` 已经按同一常数缩过 `Wearables / StateVFX / ReloadProgress3D`，
而 `VisualRoot` 本身**不缩**，缩的是各子件。再叠一次等于缩两遍。
修法：不碰 `VisualRoot`，实测可视包围盒高度 = **1.5066 m**（含兔耳），格子按它算。

### 2.2 斜视正交会让格子错位

第二版用 `camera.position = dir*34` + `look_at` 做 3/4 视角，结果世界 X 在屏幕上按
`cos(yaw)` 压缩、且不同行的透视基线不同 → 标签与角色对不上。
修法：相机固定 `(0,0,-34)` + `rotation_degrees.y = 180`（朝 +Z 看角色正面），
立体感改由**每格角色自身 `rotation.y = 26°`** 提供。屏幕右 = 世界 −X，
所以列坐标按 `(cols*0.5 - col - 0.5) * cell_w` 递增才不会左右翻。

### 2.3 基线不齐就读不出差异

`dead`（整体下沉 0.15 m）、`landing`（整体抬高）如果按同一 Y 摆，横向比较时
「倒地和站着」看着只差一点。修法：每格按**该剪辑全部帧里骨骼最低 Y** 下移对齐。

## 3. 数据侧发现

扫描全部 128 个剪辑的骨骼位移幅度（`max - min`，任何骨骼任何轴）：

| 剪辑 | 位移 | 帧数 | 时长 | 判断 |
|---|---|---|---|---|
| `melee_axe_charged_windup` | **0.0000 m** | 41 帧全同 | 0.08 s | **源数据是静止的** |
| `climbing` | **0.0000 m** | 49 帧全同 | 0.80 s | **源数据是静止的** |
| `seated` | 0.011 m | 73 | 1.20 s | 近乎静止（坐姿，合理） |
| `idle` | 0.094 m | 193 | 2.40 s | 正常 |
| `melee_axe_1_active` | 0.367 m | 41 | 0.14 s | 正常 |

两条完全静止的是**动画库自身的问题，不是渲染的问题**：

- `melee_axe_charged_windup` 同族普通三连的 windup 是 0.48 s / 41 帧，蓄力版只有 0.08 s
  且 41 帧逐字段相同 —— 更像是「长度填错 + 帧没换」。
- `climbing` 是 v042 里少数几个没有 `source_action` 的内置剪辑，全 49 帧完全一致，
  等于一个 T-pose 占位。

演示里这两格照实呈现（不伪造动作），但要修得回 Blender 侧重导。

## 4. 其他口径

- 每格按**剪辑自己的时长**循环；一次性动作（`dashing` / `hurt` / `dead` / 近战各段）
  播完从 0 重来，否则 15 秒里大半时间停在尾帧。
- 静帧相位：循环取 0.30，一次性取 0.42（避开首尾的过渡帧）。
- 默认**不挂道具**。武器 prefab 是直接挂在 `WeaponSocket` 上的，而插槽朝向由动画轨道
  驱动（`sidearm_idle` 的插槽前向是 `(0.12, 0.82, -0.56)`，偏上偏内），单独挂 prefab
  会引入朝向耦合，读成「枪穿在身上」。要看握持形态用 `--with-props`，并自行核对朝向。
- 校验：抽 5 个时间点比对每格像素最大差，128 格里 127 格 > 30，唯一静止的是
  `melee_axe_charged_windup` —— 与第 3 节的源数据结论一致。

## 5. 复跑

```bash
python scripts/render_anim_showcase.py                  # 总览图 + 15s 视频
python scripts/render_anim_showcase.py --still-only     # 只出总览图
python scripts/render_anim_showcase.py --reuse-frames   # 复用逐帧图，只重做标签与编码
python scripts/render_anim_showcase.py --with-props     # 挂道具
```

Godot 路径优先取环境变量 `GODOT_BIN`，默认
`I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe`。
子进程强制 `APPDATA` 指向 `_scratch/anim_showcase/appdata`，避免 `GameTimeManager`
自动存档刷屏（不隔离会每帧报 `Refusing stale save`）。

## 6. 未做

- 没做逐族单独成片（单族 8~23 格，单独一屏会更大更清楚，按需再加）。
- 没接真实玩家（`Player3D` 全链），因此不含枪口火光、弹壳、受击闪白等玩法 VFX ——
  这套图只展示**骨骼动画**本身。
