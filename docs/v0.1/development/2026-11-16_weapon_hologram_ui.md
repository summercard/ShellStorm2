# 枪械全息卡巢与弹体附魔表现

- 日期：2026-11-16。
- FeatureID：`WEAPON-COMBAT / WEAPON-OWNERSHIP / FATE-RULES / UI-HUD / VFX-POOL`。
- 工程版本：`0.1.0`；不提升存档 schema。
- 来源：用户三张参考图及三项表现要求。仅修改显示、不可逆确认和成功反馈，不改候选、报价、卡牌效果、作用域、弹药消耗、槽位容量或枪械实例身份。
- 设计：[04 §13.0](../04_技术施工_战斗与局内成长.md#130-全息卡巢构建页2026-11-16-用户设计表现修订-r2)、[战斗奖励与物品流转 r7](../design/战斗奖励与物品流转设计.md)、[塔罗](../14_技术施工_命运塔罗牌组.md)、[特效 §3.5a/b](../14.6_特效系统与制作规范.md)、[棱镜局部授权](../design/UI风格规范_棱镜线框.md)。
- 状态：正式路径已接入，本次逻辑及Forward+双分辨率专项通过；最终全局门禁复跑被安全检查拦截，未执行。以下事实不等于完整工程、全卡组合或目标设备验收。相关功能整体仍为 `partial`。

## 1. 实际改动

### 1.1 共用构建板与K页

`WeaponAssemblyTreePanel` 改为横幅外壳，保持既有类、信号和绑定接口；内部使用 `assets/art/ui/weapon_build/weapon_build_board.tscn`。左侧真实原枪3D、名字、实例尾号、品质及弹种/配件模块，右侧是上下交错的塔罗卡巢、PCB折线和只在已占链路上流动的光。按真实容量生成卡巢，空巢使用既有卡背，已装牌使用稳定ID对应的牌面与方位；支持拖动、滚轮、方向键聚焦及滚入第12槽。

构建板只读消费原实例与装配树，不扣款、不装卡、不写档；换枪重新绑定树。模型预览复用原物品模型工厂，专用子类保留真实挂枪Marker，关闭所有预览交互与战斗处理。普通配件与弹种模块用独立暖色模块栏区分于永久卡巢。

来源分支读取真实树。现有存档没有刻印到结构节点的稳定映射，故以 `shared_unmapped` 展示同类实际来源并在详情中说明，**不伪造逐卡归属，不为表现改存档**。重复同类卡精确逐槽追溯仍是数据契约待补项。

K页及购卡板从玩家当前持枪的活动相机投影锚点展开；无有效枪/相机或在相机背后时安全退化。关闭反向收拢，输入锁在动画结束才由宿主重算，不直接覆盖剧情锁。减少动效模式保留短淡入与明确成功反馈。

### 1.2 命运获取与确认

`Dungeon3D` 只在原购卡函数内精确接线，共用 `FateHologramPresentation`：先投影构建板，再下移，上方揭示原有三张候选。卡面与大购买按钮共用入口；唯一 `RunLootReadout` 临时放大加粗，关闭恢复字号、字体与层级。

星星卡先显示“购买后该枪械命运卡不可更换！”，默认聚焦“否”。确认绑定当时目标实例，目标变化拒绝且不扣款。原金币扣款、来源选择和Bridge提交仍是唯一事务；取消/失败先退款，再判断视图是否仍存在。成功先标已购并排队保存，之后才飞卡到返回的永久 `slot_index`；在途巢保持卡背，落巢短闪、整板脉冲与方块散射。动画不是提交点，忙锁防止重复购买和中途退出。月亮/太阳只播放相应作用域反馈，不填枪槽。

兼容占卜保留免费预选，不向当前枪刻印；训练台保留48张全量免费卡池和沙盒语义。两者同用构建板并补投影开闭，未恢复已经关闭的开门/开箱自动弹购卡入口。

### 1.3 弹体附魔

`Projectile3D` 最小增量持有视觉附件：火、冰、毒、电、反弹、追踪、返航各有独立Prefab和256×256 RGBA贴图，真实 `GPUParticles3D + QuadMesh` 发射，不用彩色球冒充元素。只按实际 `behavior` 键路由，元素去重；模块主体、碰撞、伤害和轨迹代码不改。

数量公式：同时启用N种不同属性，每种 `amount=max(1,floor(24/N))`；1/2/3/4属性对应24/12/8/6，总预算24，7属性各3，总21。仅减数量，不减持续时间或玩法效果。附件无碰撞、无灯、不投影，随ProjectilePool回收，复借停止旧发射并重置模拟、属性和生长时钟；不额外进VfxPool造成双重所有权。

## 2. 文件与资产

- UI代码：`src/ui/WeaponAssemblyTreePanel.gd`、`src/ui/weapon_build/`；正式宿主：`src/world3d/Dungeon3D.gd`、`src/ui/DivinationMenu.gd`、`src/training3d/TrainingFateBenchPanel.gd`。
- 弹体代码：`src/combat3d/Projectile3D.gd`、`src/vfx/projectile_enchant/`。
- 制作源：`art_source/vfx/projectile_enchant/generate_projectile_enchant.py`及生成贴图；运行贴图：`assets/art/vfx/textures/projectile_enchant_*.png`。
- UI分账本《资产主表》r27 `UI-WEAPON-BUILD-BOARD`、r28 `UI-FATE-HOLOGRAM-PRESENTATION`。
- 特效分账本r66 `VFX-WEAPON-CARD-SOCKET-IMPACT-2D`；r67—73 `VFX-PROJECTILE-ENCHANT-{FIRE,ICE,POISON,LIGHTNING,BOUNCE,HOMING,RETURN}-3D`。2D落巢效果明确为Control例外，不冒充3D。
- 本次新增10项。公式、overview、DV与基线最小补录；1448条旧资产记录与16份受保护分页摘要逐项保留，不接纳并行会话或既有哈希漂移。
- 同步媒体门禁UI数量21→23，并明确要求两项新增稳定ID；不是仅放宽数量阈值，迁移初始数量16不变。

## 3. 验收入口与已确认结果

所有Godot运行在Autoload前隔离APPDATA/LOCALAPPDATA和custom_user_dir，并使用工程外独立project/cache。引擎为Godot 4.7.2；真实渲染为Forward+/Vulkan，GPU RTX4060Ti。主工程正在运行的编辑器和其他会话进程不被停止。

入口：`python scripts/run_weapon_hologram_qa.py --logic --scene all`；真实渲染去掉 `--logic`，加 `--resolution 1280x720 1920x1080 --record-motion`。两个scene唯一登记为manual并排除full裸扫。仅复用有完整导入记录的隔离副本时允许 `--reuse-isolated-project ... --skip-import`，报告保留原导入证据，不冒充本轮冷导入通过。

| 验收 | 已确认事实 | 证据相对 `ShellStorm2-work/` |
|---|---|---|
| 初版逻辑复测 | UI120/120、附魔894/894；各exit0，0 SCRIPT ERROR/ERROR | `verification/weapon_hologram/20261116_180053_d92dfd/result.json` |
| 首轮真实双分辨率 | UI各137项、附魔各932项，四场均exit0且0 SCRIPT ERROR/ERROR；但冷import超600秒，整轮runner判失败 | `verification/weapon_hologram/20261116_182159_e1b7b7/result.json` |
| 细化模块样式复测 | 1080p UI137/137和附魔932/932 exit0；720p K入场等待超时及粒子进程超时保留，非预期脚本错误0；不签整轮通过 | `verification/weapon_hologram/20261116_193554_3b5983/result.json` |
| 旧购卡/双枪回归 | `FATE_CARD_PURCHASE_FLOW_OK`、`DUAL_WEAPON_QUICK_MAP_FATE_OK`，各exit0、0脚本/引擎ERROR | `sessions/weapon_hologram_regression/20261116_184153_47baed/result.json` |
| 所有权回归 | 修正旧4格/2格夹具容不下4×2整枪；完整保留去重/换装/保险/JSON/构筑断言，增加真实足迹与第二份合法空间；最终exit0、0 ERROR、成功marker | `sessions/weapon_hologram_regression/20261116_193227_10c98a/result.json` |

早期meta缺失读取已由 `has_meta` 前置修复，并有零错误复测。测试曾缓存提交前旧root导致free引用，已改每次从真实新树取source；同offer JSON的数值类型以整数/浮点语义比较，未改变身份/报价/已购断言。未用放宽目标阈值或删除失败路径换取通过。

旧HUD综合探针在headless等待真实帧后超时，未签该场景通过；正式新页双分辨率专项独立取证。

### 3.1 最终收口证据

| 验收 | 最终结果 | 证据相对 `ShellStorm2-work/` |
|---|---|---|
| 兼容入口逻辑 | 165/165，exit0，0 SCRIPT ERROR/ERROR；普通与减少动效两轮占卜/训练都保留原语义 | `verification/weapon_hologram/20261116_202734_138ffe/result.json` |
| 完整双分辨率专项 | UI720p/1080p各182/182，附魔各932/932，四场均exit0且0 SCRIPT ERROR/ERROR；runner passed=true | `verification/weapon_hologram/20261116_203028_cacbed/result.json` |
| 全息方块线框最终补绘 | UI720p/1080p各182/182，均exit0，0 ERROR；使用相同枪身投影、无静止厚框 | `verification/weapon_hologram/20261116_203227_5284a6/result.json` |

兼容smoke最初把购卡后的防抖保存与游戏时钟变化误认为面板写档；修正前先做无面板逐字段对照，发现 `/world_time_elapsed_game_seconds` 等来源属于时钟及既有写者。最终先冻结该fixture宿主和时钟、flush运行时/时钟barrier、join后台writer后建立稳定基线，继续保留**完整BaseData字典与存档字节摘要严格相等**，没有忽略字段或关闭面板回调。lambda释放节点错误来自测试捕获即将queue_free的对象，改为只捕获整数instance_id。K的8秒动画阈值不放宽，只将首次真实SubViewport绘制冷帧耗时与动画等待分开记录。

真实截图已逐张复核：左侧真实枪和模块、右侧PCB链路和来源模块、上三卡下构建板、默认否确认、飞卡及整板短闪、七附件网格和1—4属性同现。粒子展示图注明统一视觉展示倍率×2，不能作为压力性能证据。过程视频按真实采样序列与总时长编码，不冒充60fps实时录屏。

交付入口为 `outputs/weapon_hologram_20261116/delivery_201248/index.html`，带最新通过轮、旧失败轮对照、九类状态截图、H.264过程帧回放、原始结果与可下载ZIP。正式游戏代码不依赖此HTML。

## 4. 台账与文档门禁边界

逐格核对：`sessions/2026-11-16_weapon_hologram_ledger/run_170227_203052/resume_surgical_verify.json`，新10项hash匹配、旧内容保留、来源索引通过。UI structure exit0；运行命名exit0；全局structure17项、VFX full9项、UI full5项、ledger split24项在登记前后相同，详见同目录 `resume_gate_comparison.json`。不批量重写旧资产SHA、不清空baseline。

文档总检查已实际执行一次，exit1；当时开发记录尚未创建，报本记录缺失引用、另一会话尚未落地记录及媒体UI数量21→23未同步等。本记录与索引现已补齐，媒体门禁新增两稳定ID断言且单独执行得到 `MEDIA_ASSET_DOMAINS_OK domains=3 assets=216`。历史11条断链、并行工作未落地引用与本次问题分别记录。

**最终复跑未执行**：四项批量命令（文档总检查、运行命名、专项注册、功能追溯）被安全检查拒绝，原因为命令文本被判含不适用于PowerShell的cmd环境变量语法；未换壳或改写命令绕过。`outputs/weapon_hologram_20261116/delivery_201248/final_gates.json`明确 `blocked_not_run`，不能声称最终门禁全绿或新增问题已经最终归零。先前运行命名exit0、注册静态检查通过与台账前后对照仍只代表各自原时点。相关功能仍partial。

## 5. 遗留与未执行

- 本次不改变玩法与长期schema；无法仅靠显示层恢复历史未保存的精确“第几张卡对应哪把嵌套枪”映射。
- 人工从基地进入关卡再拾取/购买的完整游玩、所有卡牌/复杂嵌套穷举、Android与压力性能未验。
- 冷导入和部分场景在并行任务环境下超时，已如实记录；不将无错误日志等同于完成。
- 原全局资产漂移、旧UID路径回退与旧断链未在本事务修复。
- 改前副本位于 `ShellStorm2-backup/2026-11-16_weapon_hologram/before_edits/`；不覆盖并行会话改动，不提交或推送。

## 6. 未激活卡背暗色修订（2026-11-16 21:26）

来源：用户反馈未激活卡背太亮，要求改暗。只改共享 `WeaponBuildSocket.gd` 的卡背材质：原纹样去色后映射为暗灰蓝，底色 `(0.022,0.030,0.043)`、纹样上限 `(0.24,0.28,0.34)`；保留原透明通道并乘入继承颜色，不破坏投影淡入/退场。下一槽、镶嵌在途与其余空巢均用同一暗色材质，其余空巢再乘0.72透明度；槽序与外部细线继续强调下一槽，悬停不提亮背面。已刻印卡面和全局候选翻牌背图不改，无新资产、不改玩法或存档。技术契约同步04 §13.0。

专项增加K页/购卡板暗色检查、已装牌面不压暗以及全局卡背不受影响的反向断言。隔离逻辑170/170通过（exit0，0脚本/引擎错误），证据 `verification/weapon_hologram/20261116_212327_92d646/result.json`；Forward+/Vulkan真实720p与1080p各185/185通过（两场exit0、0脚本/引擎错误），证据 `verification/weapon_hologram/20261116_212459_578a05/result.json`。K页和购卡稳定态截图已人工图像复核：空巢暗灰蓝纹样仍可辨，已刻印与候选牌面亮度保持。复用已完整导入的独立工程，Autoload前重新隔离用户目录；不代签冷导入或全工程验收。本次未重试上节被拦截的全局门禁。

此修订改前副本：`ShellStorm2-backup/2026-11-16_weapon_socket_dark_back/before_edits/`。
