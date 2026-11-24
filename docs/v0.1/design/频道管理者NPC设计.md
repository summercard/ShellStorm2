# 频道管理者｜固定式机械 NPC

资产 `CHR-NPC-CHANNEL-MANAGER`，内容键 `npc_channel_manager`，角色 / `npc`。本页定义独立演出 Prefab；房间交互由宿主持有，见[远征01第9房](远征关卡01设计.md)与[远征99固定测试支线](新关卡设计表_测试关卡99.md)。不改绿苔、玩家碰撞、伤害规则或存档结构。参见[基地 NPC 接口](../20_技术施工_基地NPC.md)与[角色美术工作流](../16.1_角色美术制作与动作导入流程.md)。来源：2026-11-24 业主概念图与动画要求。

## 骨架与制作边界

- 13 台电视各绑定一个刚性骨；六节上部线束分段加权；`fixed_root` 不打关键帧。`BaseFixed` 不蒙皮；接地部分至 `Z=0.61m` 的上部网格顶点仍固定在 `fixed_root`。外围地插、贴地线和整个 NPC 根不做位移、倾斜或转向。
- 表演骨架 `CHR-NPC-CHANNEL-MANAGER/CRT_RIG_002`：模型与动作两份 Blender 母版共享 20 骨、静止姿态与签名。模型输出不混入展示环境；Godot 用稳定路径导入 GLB，壳体重新绑定公共色盘，屏幕使用可替换图集及专用材质。不重复另存色盘。
- 标称激活包络约 3 × 3 × 6 m，主屏骨中心从 2.83 m 升至 4.98 m，中途反冲过冲。各台不做缩放；以错位回收和上部线束收拢形成矮塔。

## 状态与动作设计（24 fps）

| 状态 / 剪辑 | 时长 | 身体表演 | 屏幕表演 |
|---|---:|---|---|
| 休眠 `sleep` | 96 帧 / 4.000 s，循环 | 自地面往上挤叠，轻微沉降 | 只有暗雪花，无字、无眼 |
| 激活 `activate` | 60 帧 / 2.500 s | 上半截线束拉伸，各台错相抬升，越位后回弹 | 主屏先睁眼，其余分波点亮 |
| 激活待机 `active_idle` | 120 帧 / 5.000 s，循环 | 外壳随电缆呼吸式错相摆动 | 各屏随机静置后经过雪花换字/眼；近身时按屏面方向选出可跟踪的眼睛 |
| 普通 `talk_normal` | 48 帧 / 2.000 s，循环 | 主屏小幅三拍点头，副屏应声 | 跟随语气轻跳大小、亮度 |
| 开心 `talk_happy` | 48 帧 / 2.000 s，循环 | 上跳、左右摇晃，主屏最大跳动约 0.18 m | 暖色，字级弹跳 |
| 愤怒 `talk_angry` | 48 帧 / 2.000 s，循环 | 短而重的前顶和抖头，随后收回 | 字闪动与错行，偏红 |
| 阴谋 `talk_scheme` | 48 帧 / 2.000 s，循环 | 主屏压低、偏斜向前探，副屏隔拍附和 | 字收窄、暗紫调，缓慢漂移 |
| 技能前摇 `skill_windup` | 34 帧 / 1.417 s | 抬升后沿塔体传递短震 | 先统一警告；再进入每屏上下滚轮 |
| 技能锁定 `skill_lock` | 14 帧 / 0.583 s | 急停下挫，主屏预倾 | 单次技能使用同一个锁定结果：识别＝白底、监听＝紫底、中继＝蓝底 |
| 技能释放 `skill_release` | 22 帧 / 0.917 s | 最大 CRT 前探、点头，释放后回弹 | 光束从北向第 9 台 CRT 屏幕 socket（`screen_mounts.json` 数组索引 8，法线 `-Z`）射向北墙，不承担伤害 |

状态只由显式命令、近身请求及阶段计时推进。`sleep → activate → active_idle`；四种说话动作从 `active_idle` 选用，结束回待机；技能执行 `skill_windup → skill_lock → skill_release → active_idle`，优先级高于说话和追眼显示。效果正常进入、重复请求拒绝、退出必须清理。动画结束信号不写玩法结果。

近身判断只看水平投影：`dot(normal_xz, normalize(target_xz - screen_xz)) ≥ cos(45°) ≈ 0.7071`；在 6 米接近范围内只选满足该式的屏幕。瞳孔偏移按每个屏幕的右轴和上轴独立计算，限幅并平滑，不转电视或 NPC 根。换字转场发生在雪花内，不在干净画面跳帧。滚轮显示不重新抽取技能结果，卡面一旦锁定由发起方结果持有。

## 独立场景和验收

- 独立入口：`res://assets/art/characters/npc/channel_manager/runtime/channel_manager_runtime.tscn`。关卡只负责摆位并通过 `observer_path` 或 `set_observer(player)` 交付观察目标；有目标时可在 6 m 自动激活，也可调用 `activate()`。这里不接管正式关卡、碰撞、对白文本、技能规则或命中。
- 对话表现：`begin_talk("normal" | "happy" | "angry" | "scheme", duration)`，或 `end_talk()` 提前结束。技能演出：`trigger_skill("识别" | "监听" | "中继")` 可明确指定结果；空值在开始时抽一次，不在转盘中重抽。`cancel_skill()` 只允许在前摇、锁定阶段取消。外部如需对齐节拍，可监听 `skill_result_locked`、`release_started` 和 `release_finished`。
- 前摇的统一警告约 0.46 s；之后是独立相位滚屏，白/紫/蓝锁定持续约 0.58 s。主屏在释放第 5 帧后见光、第 14 帧前收光，偏转来自本屏骨骼，不转基座。
- Blender 双源、导出优化源与结果哈希见 `art_source/characters/npc/channel_manager/asset_manifest.json`。动作母版可按时间轴标记点播；其屏幕是离线预演，交互眼睛、警告、滚屏、三张锁定卡及光束以 Godot 为准。不需要补图，沿用旧频道图集，中间动效由材质生成。
- 验收：Blender 逐帧复核 548 帧，固定根、底座、860 个低位线束顶点无可测位移，6 个循环首尾闭合。Godot 从正式 GLB 实例化后用 `tests/verification/verify_channel_manager_runtime.gd` 核对导入剪辑、追眼和雪花切换、四情绪、三张锁定卡、取消/重复保护、光束窗口和固定底座：53 项、0 失败。`capture_channel_manager_runtime.gd` 已在 Compatibility 和 Forward+ 真实渲染取证。
- 角色账本：归属「角色 / `npc`」，计划以 `CHR-NPC-CHANNEL-MANAGER` 在《资产主表》登记为「原型已接入」。副本试写使旧行查重公式变成数组公式，未通过角色账本门禁，正式账本与基线均未替换。
