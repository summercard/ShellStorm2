# ShellStorm2 模块制作链路 · 工具 · 实用逻辑 · 评判维度

> 版本：2026-10-20 整理版
> 适用：ShellStorm2 v0.1.0（`project.godot` → `config/name="弹壳风暴2"`，`config/features=PackedStringArray("4.6","Forward Plus")`，主场景 `res://scenes/StartupLoadingScreen.tscn`）
> 统计口径：2026-10-20 14:20 在 2 号机（`I:\工作项目\shellstrom2\ShellStorm2`）实测，`src/**/*.gd` 递归统计文件数与行数
> 与既有文档的关系：`docs/v0.1/MODULE_INDEX.md`（43,146 字符）按 FeatureID 记「交付了什么」；本文补「每个模块怎么造、用什么工具、核心逻辑落在哪几个文件、验收怎么判」。两份不重复，一起看。

---

## 0 三句话用法

1. 接活先查第 1 节总表，定位模块 + 主入口文件 + 设计文档。
2. 按第 2 节六步链路走，每步产物落盘到指定位置，别只在脑子里过。
3. 收工用第 4 节五维判，**任一维缺证据就不许标「已完成」**；「专项通过」和「全局通过」必须分开写。

---

## 1 模块总表（按代码量排序）

| 模块 | 目录 | .gd 文件 | 行数 | 职责 | 主入口文件 | 设计依据 |
|---|---|---|---|---|---|---|
| 关卡场景 | `src/world3d` | 40 | 33,563 | 塔层副本、房间、门、波次、撤离 | `Dungeon3D.gd`(9482)、`TowerDescent3D.gd`(6979)、`DungeonRoom3D.gd`(5848) | `design/远征关卡01设计.md`、`design/远征关卡02设计.md`、`design/新关卡设计表_测试关卡99.md` |
| UI / HUD | `src/ui` | 51 | 16,274 | 全部界面、HUD、面板、交互 | `UIStyleFactory.gd`(1928)、`InventoryUI.gd`(1756)、`WorkbenchPanel.gd`(1355) | `design/UI与UX全局设计及全界面清单.md`、`design/UI风格规范_棱镜线框.md` |
| 玩家 | `src/player3d` | 32 | 9,182 | 移动、相机、动画状态机、手电、视野 | `Player3D.gd`(2828)、`PlayerAvatar3D.gd`(1786)、`FlashlightColorTweaker.gd`(1225) | `development/2026-10-07_player_*.md` 系列（v025–v037） |
| 关卡生成 | `src/map` | 9 | 7,174 | 平面图生成、方案校验、怪物注入 | `FloorPlanGenerator.gd`(3509)、`LevelPlanValidator.gd`(1562)、`MonsterInjector.gd`(875) | `design/关卡设计与制作流程.md`、`design/触发器刷怪设计.md` |
| 敌人 / AI | `src/enemy3d` | 17 | 6,355 | 怪物行为、AI 调度、精英池 | `Enemy3D.gd`(2923)、`MonsterAIManager.gd`(724)、`EnemyAvatar3D.gd`(534) | `design/怪物设计.md` |
| 特效 | `src/vfx` | 45 | 4,995 | 击杀、弹壳、弹体、云海等 3D 特效池 | `VfxGooDeathBase3D.gd`(528)、`VfxBulletBody3D.gd`(436) | `src/特效添加说明.md`（源内说明） |
| 基地 / 经济 | `src/base` | 10 | 4,574 | 存档、物品注册、蓝图、结算 | `BaseManager.gd`(1645)、`ItemRegistry.gd`(1399)、`BlueprintRegistry.gd`(658) | `design/基地经济与存档结算设计.md` |
| 武器 / 命运卡 | `src/weapons` | 13 | 4,484 | 装配树、工坊配方、命运卡引擎 | `FateCardEngine.gd`(1158)、`FateCardPresets.gd`(628)、`WeaponForge.gd`(547) | `design/命运卡六关投放设计.md`、`design/装备与棋盘式包裹设计.md` |
| 游戏规则层 | `src/game` | 12 | 2,736 | 卡牌桥接、背包模块、经济报价、地图触发 | `FateCardGameBridge.gd`(686)、`InventoryModule.gd`(582)、`FateEconomyService.gd`(354) | 同上 |
| 核心框架 | `src/core` | 16 | 2,651 | 25 个 autoload、时间、输入、画质、性能 | `GraphicsSettingsManager.gd`(406)、`AudioManager.gd`(392)、`GamepadInput.gd`(366) | `docs/DOCUMENTATION_STANDARD.md` + `project.godot` |
| 战斗 | `src/combat3d` | 6 | 2,508 | 枪械模型、弹道、命中华彩 | `WeaponModel3D.gd`(1272)、`Projectile3D.gd`(805)、`CombatEffect3D.gd`(209) | `design/战斗奖励与物品流转设计.md` |
| 叙事 | `src/narrative` | 4 | 2,135 | 剧情推进、适配器、脚本 | `NarrativeAdapter3D.gd`(1235)、`NarrativeDirector3D.gd`(605) | `design/主线剧情剧本.md`、`design/主线剧情节点表.md` |
| 奖励 | `src/rewards` | 6 | 2,079 | 掉落服务、奖池、掉落表 | `RewardService.gd`(654)、`RewardPoolRegistry.gd`(485)、`RewardSpec.gd`(350) | `design/战斗奖励与物品流转设计.md` |
| 训练场 | `src/training3d` | 9 | 1,819 | 靶场、刷怪台、卡牌台 | `TrainingRange3D.gd`(696) | 无独立设计文档（实验性） |
| 基地 3D | `src/base3d` | 9 | 1,324 | 99F 场景设施、广播、可推座椅 | `BaseFacility3D.gd`(281)、`BaseWorld3D.gd`(235) | `design/基地经济与存档结算设计.md` |
| 音频 | `src/audio` | 5 | 629 | 音乐调度、世界音环境 | `MusicManager.gd`(226)、`WorldAudioEnvironment3D.gd`(199) | `design/音效系统与资产设计.md`、`design/音乐播放清单.md` |
| 本地化 | `src/i18n` | 3 | 490 | 中英文文本包、回退链 | `GameTextPackZhCN.gd`(303)、`GameText.gd`(163) | `design/武器构建链路文本本地化设计.md` |
| 设计配置 | `src/framework` | 1 | 208 | 集中式设计常量 | `GameDesignConfig.gd`(208) | — |
| 后处理 | `src/postfx` | 1 | 110 | 后处理覆盖层 | `PostfxOverlay.gd`(110) | 调试面板文档 |
| 表情系统 | `src/presentation` | 2 | 73 | 角色表情 | `CharacterExpressionSystem.gd`(51) | `design/character_expression_system.md` |
| 开放世界 | `src/open_world` | 1 | 73 | 天际线建筑材质绑定 | `skyline08_existing_material_bind.gd`(73) | `design/rooftop_*`、`design/tower04_*` |
| 验收基建 | `src/testing` | 3 | 57 | 探针计时/输出/退出 | `VerificationClock.gd`、`VerificationOutput.gd`、`VerificationQuitter.gd` | `tests/README.md` |
| 伤害数字（旧） | `src/fx` | 1 | 45 | 旧版伤害数字实例 | `CombatDamageNumber3D.gd`(45) | 已被 `src/vfx` 取代，见第 6 节缺口 3 |
| 资源占位 | `src/assets` | 0 | 0 | 空目录 | — | — |

**合计：296 个 .gd 文件，约 103,538 行。**

读表要点：
- **一半以上的复杂度在前三名**：world3d + ui + player3d = 58,019 行，占 56%。改这三个目录要按「大改」流程走。
- **单文件风险最高**：`world3d/Dungeon3D.gd` 9,482 行，一个文件里塞了门后流程、刷怪、撤离、存档、命运卡三选。
- **`src/game` 是规则层**，不放界面不放表现，只放「怎么算」。它和 `src/weapons` 一起构成玩法真源。

---

## 2 通用六步链路（所有模块同一套）

| 步 | 做什么 | 产物写哪 | 工具 |
|---|---|---|---|
| 1 定身份 | 查 FeatureID、模块归属、当前版本 | `docs/v0.1/MODULE_INDEX.md` 对应条目 | 手查 + `Select-String` |
| 2 写规则 | 目标规则主源（不是施工笔记） | `docs/v0.1/design/<功能>.md` | 文档先行，代码后写 |
| 3 建独立入口 | 让功能能脱离正式流程被单独跑起来 | `tests/verification/*.gd` 或 `tools/probe_*.gd` + `.tscn` | Godot 场景直跑 |
| 4 实现 | 只动本模块目录，跨模块改接口要先记契约 | `src/<module>/` | Godot 4.6 + Codex CLI |
| 5 取证 | 真实渲染截图 / 探针日志 / 帧时采样 | 工程外 `ShellStorm2-work/`（工程内不落 `outputs/`） | 探针 + 截图 + `VerificationOutput` |
| 6 记账 | 交付记录 + 索引/台账同步 | `docs/v0.1/development/YYYY-MM-DD_<slug>.md` + `CHANGELOG.md` | 文档 |

这套流程不是本文发明的，是工程既有规范：`docs/DOCUMENTATION_STANDARD.md` 第 2 节「开发顺序」写的六步，和上表一一对应。所有历史交付都能在 `development/` 里找到对应记录（目前 200+ 篇）。

**四级验收口径（必须分开写，不能混）**：
1. **专项通过** — 探针脚本绿灯，只证明这条逻辑对
2. **真实渲染通过** — 有实际画面截图，不是编辑器视口
3. **完整工程通过** — 从启动到目标功能的全流程跑通
4. **设备通过** — 移动端 / 低配机实测

历史文档里大量出现「专项与真实渲染通过，完整工程与移动端未验」——这不是偷懒，是诚实分级。**判卷时看到只写了「通过」，要先问是哪一级。**

---

## 3 逐模块：链路 / 工具 / 逻辑 / 评判

### 3.1 核心框架 `src/core`（16 文件 / 2,651 行）

- **链路**：`project.godot` 注册 autoload → 单例提供全局状态 → 场景按名取用 → 调试开关走单一常量块
- **工具**：直接读 `project.godot` 的 `[autoload]` 段；启动日志 `> /tmp/ss2_run.log`
- **实用逻辑**：**25 个 autoload 就是全项目骨架**，加载顺序即依赖顺序：
  `VfxPool → Global → GameEntryFlow → GameManager → AudioManager → BaseManager → GameTimeManager → BlueprintRegistry → FateCardGameBridge → LevelSelect → InputSettings → InputDevice → GamepadInput → MobileInput → MonsterAIManager → EliteRosterService → GameplaySpatialRegistry3D → GraphicsSettingsManager → PostfxOverlay → RuntimePerformanceManager → SceneParticleToggle3D → MusicManager → DialogueUI → NarrativeDirector → IrisTransition`
- **评判**：autoload 名全局唯一（`check_classname_unique.py` 可查重）｜启动到主场景 8–12 秒（2026-10-11 启动诊断基线）｜启动日志 0 报错 0 资源缺失

### 3.2 玩家 `src/player3d`（32 文件 / 9,182 行）

- **链路**：Blender 动作源 → Godot 导入 → `PlayerAvatar3D` 状态机 → `Player3D` 输入/移动/相机 → 视觉层（手电 `PlayerFlashlight3D`、视野 `PlayerVision3D`）→ 状态库截图取证
- **工具**：`Player3DStateGallery.tscn`（546 行状态画廊，逐个动作摆拍）、`FlashlightColorTweaker`（P 键面板）、`tests/verification/capture_*`、Blender
- **实用逻辑**：
  - 调试键：`;` `'` `[` `]` `F12` `=` `-`，相机步进常量集中在 `Player3D.gd` L61–L72（`DEBUG_SCALE_STEP_RATIO 0.10`、`DEBUG_CAMERA_TRAILING_STEP_M 0.20`、YAW 5°/-75~+75、PITCH 5°/-80~+60、`PAN_STEP_M 0.20`、`PAN_MAX_M 6.0`）
  - 近战顿帧：`request_melee_hit_stop(frames:=1)`，clamp 1..4，无通用 hitstop 字段
  - 动画播放保留用户指定的 1.25 倍速
- **评判**：四方向速度一致｜握枪贴合位置｜脚底锁地不滑｜真实渲染截图（非视口）｜移动端未验必须标红

### 3.3 战斗与枪械 `src/combat3d` + `src/weapons`（19 文件 / 6,992 行）

- **链路**：枪身底表 → `WeaponInstance` 实例 → `WeaponAssemblyTree` 装配树 → 计算属性 → `Projectile3D` 发射 → 命中结算 → 伤害数字 + 特效
- **工具**：`WeaponAssemblyTreePanel.tscn`（可视化装配）、`WorkbenchPanel`（工坊事务）、`tools/probe_weapon_drop_rates.gd`、`tools/probe_attachment_semantics.gd`
- **实用逻辑**：
  - **最终伤害 = `damage` + `bullet_damage`**，两项同时乘 `WeaponDropGrade.damage_multiplier(drop_grade)`；root 为空返回 `{}`
  - 近战顿帧 1–4 帧；伤害数字分层阈值 `HEAVY_AMOUNT_THRESHOLD 40`（`src/vfx/DamageNumberStyle.gd`）
  - `WeaponForge` 三配方：R1 `remelt`（1 武器 + ≥1 弹药模块）、R2 `fusion`（≥2 武器取伤害最高为蓝本）、R3 `synthesis`（熔炼值 ≥6，产出 `floor(V/6)` 把，上限 3）
  - 常量：`MELT_THRESHOLD 6`、`MAX_MELT_OUTPUT 3`、`MELT_VALUES`（common1/uncommon2/rare3/epic4/legendary6）、`WEAPON_WEIGHT_STEP`（blue 0.55 / purple 1.35 / gold 1.75）、托盘 `5×5 = 25`
- **评判**：弹道可见位置与实际命中点一致｜六件套体感数值（射速/后坐/换弹/散布/伤害/手感）逐项对表｜三配方成功率梯度可复现（R=0 约 70/25/5，R=10 约 53/35/12）｜整数进整数出无小数残留

### 3.4 敌人与 AI `src/enemy3d`（17 文件 / 6,355 行）

- **链路**：`design/怪物设计.md` → 白盒 → Blender 模型/动作 → `Enemy3D` 行为 → `MonsterAIManager` 调度 → 掉落表 → 探针（`probe_monster_drops`、`probe_weapon_drop_rates`）
- **工具**：`tools/monster_startup_capture.gd`（首用加载耗时）、`probe_ranged_eye_scan.gd`、`preview_melee_zombie.gd`、`preview_fat_zombie03.gd`
- **实用逻辑**：分离查询有节流（2026-09-29 记录）；重力与分离独立成篇（2026-09-29）；同类怪物首用加载曾测 259 / 327 ms
- **评判**：同屏 N 只时帧时不崩｜不穿墙不叠人｜掉落率复现（固定种子同结果）｜受击/死亡反馈可见

### 3.5 关卡生成 `src/map`（9 文件 / 7,174 行）

- **链路**：关卡方案（`data/level_plans`）→ `LevelPlanLoader` → `FloorPlanGenerator` 生成 → `LevelPlanValidator` 校验 → `MonsterInjector` 注入刷怪 → 运行时落场景
- **工具**：`scripts/build_expedition02_level_plan.py`、`probe_expedition01_plan_dump.gd`、`probe_expedition02_assembly.gd`、`probe_expedition_room_footprint*`
- **实用逻辑**：
  - **`data/level_plans` 当前 0 个文件** —— 关卡方案没有落盘，靠程序生成或运行时内存，改关卡前必须先确认方案来源
  - 其余数据：`layouts` 2、`map_themes` 4、`spawn_boxes` 7
  - Validator 是硬门槛，必须 0 错才进场景
- **评判**：连跑 100 次无越界/无死房/无重叠｜门锚点严格对齐（2026-09-28 显式门洞锚点规范）｜刷怪容量不溢出｜生成耗时在预算内

### 3.6 关卡场景 `src/world3d`（40 文件 / 33,563 行）

- **链路**：设计文档出关卡表 → 白盒（`scenes/ExpeditionLevel01_3D.tscn` 等）→ 组件化装配 → 光照/氛围（`TowerAtmosphere3D`）→ 门/波次/撤离接线 → 探针取证
- **工具**：`tests/verification/probe_expedition*`（30+ 个）、`cam`/`shot` 系列截图探针、`F12` 截图
- **实用逻辑**：
  - `Dungeon3D.gd`（9,482 行）是门后全部流程的唯一执行者：三选命运卡、购买、波次、撤离、自动存档
  - 门后三选：`_show_door_fate_choices()` → 冻结报价 → 记录 policy 快照 → 逐张独立购买态 → 余额兜底
  - 房间层 `DungeonRoom3D` 管单房间内容，`SecretBranch3D` 管支线
- **评判**：走行空间无卡死｜门表现与锚点一致｜光照分层（雾/体积雾）｜**性能是历史挂点**：云海场景 P95 曾达 54–64 ms（2026-10-04），动 world3d 必须带帧时对比

### 3.7 基地与经济 `src/base` + `src/base3d`（19 文件 / 5,898 行）

- **链路**：`BaseManager`（唯一写入口）→ `ItemRegistry` / `BlueprintRegistry` 注册 → `ProfileSaveService` 落盘 → `BaseWorld3D` 表现 → 设施交互
- **工具**：`probe_insurance_capacity.gd`、`probe_base99_remaining_placement.gd`、`capture_workbench_entry.gd`
- **实用逻辑**：**存档只有 `BaseManager` 一个写入口**，其他模块一律调它；调试解锁走 `debug_unlock_expedition_level("expedition_02")`（仅 P 键面板「预留」页调用）
- **评判**：存档 schema 迁移有版本号且可回滚｜经济结算前后对账｜设施摆放不重叠不悬空｜旧档能读新档不能倒退

### 3.8 命运卡（跨 `weapons` / `game` / `ui` / `data`）

- **链路**：`TarotFateCatalog` 定义 → `FateCardPresets` 卡池 → `FateOfferPolicy` 关卡投放 → `Dungeon3D` 门后三选 → `FateEconomyService` 报价 → `FateCardGameBridge` 应用效果 → UI 呈现
- **工具**：`DivinationMenu.tscn`、`FateCardCollectionMenu.tscn`、`TrainingFateBenchPanel`（训练场试卡）、`data/fate/level_pools.json`
- **实用逻辑**：
  - 六关累计投放 **21 / 33 / 45 / 57 / 69 / 78** 个 `stable_card_id`；01、02 仅正位，03 起少量逆位，06 全开
  - `level_pools.json` 目前只配了 `expedition_01`（`upright_only: true`，21 张），其余关卡策略缺失时 **fail-closed 直接不投放**
  - 报价只由「门序号 + 该门基准房收益 + 种子」决定，**与玩家钱包无关**；`SCHEMA_VERSION 3`、价格带 0.85–1.15、`MIN_CARD_PRICE 40`、`fate_sun_bounty` 上限 100
  - 同一次三张不重复；旧局快照不重掷
- **评判**：投放分布对表｜报价恒在价格带内｜购买失败原额退币｜卡效果生效后存档一致｜逆位未实现的关卡不得误开

### 3.9 奖励与物品流转 `src/rewards` + `src/game/InventoryModule`（18 文件 / 4,815 行）

- **链路**：掉落表 `MonsterDropTable` → `RewardPoolRegistry` 奖池 → `RewardService` 结算 → `RuntimeRewardCoordinator` 派发 → 背包/仓库
- **工具**：`probe_monster_drops.gd`、`probe_weapon_drop_rates.gd`、`capture_run_loot_readout.gd`
- **实用逻辑**：掉落按档位分池（common/uncommon/rare/epic/legendary 五档），奖池权重在 `RewardPoolRegistry` 集中定义，`RewardSpec` 描述单条奖励
- **评判**：权重和归 1｜固定种子可复现｜背包满时的不丢失策略明确｜局内→撤离→基地三段不丢件

### 3.10 UI / HUD `src/ui`（51 文件 / 16,274 行）

- **链路**：`design/UI与UX全局设计及全界面清单.md` 定界面 → `UIStyleFactory` 出统一控件 → 各面板实现 → 截图取证
- **工具**：`UIStyleFactory.gd`（1,928 行，所有控件的唯一出处）、`preview_dialogue_ui.gd`、`probe_base_facility_label_visual.gd`
- **实用逻辑**：风格规范「棱镜线框」；`HudReloadRing.gd` 用 `_draw()` 画 2D 环贴在武器图标上；面板切换走 `IrisTransition` 转场
- **评判**：符合棱镜线框规范｜16:9 / 21:9 / 手机比例都不溢出｜暂停态可操作项正确｜键鼠与手柄都能走完

### 3.11 叙事 `src/narrative` + `ui/dialogue`（2,135 行 + 对话 UI）

- **链路**：`design/主线剧情剧本.md` → `data/narrative/*.json`（11 份）→ `NarrativeDirector3D` 推进 → `NarrativeAdapter3D` 适配场景 → `DialogueUI` 呈现
- **工具**：`preview_dialogue_ui.gd`、`probe_speech_bubble_3d.gd`
- **实用逻辑**：触发语义有独立规范（2026-09-23 剧情触发语义 + 跨局历史），同一节点不重复触发，跨局历史单独存
- **评判**：节点表与脚本一一对应｜跨局不重播｜跳过不卡流程｜对话文案与本地化包一致

### 3.12 音频 `src/audio` + `core/AudioManager` + `core/SynthSfx`（约 1,250 行）

- **链路**：`design/音效系统与资产设计.md` + `音乐播放清单.md` → 资产入 `assets` → `MusicCatalog` 登记 → `MusicManager` 调度 → `WorldAudioEnvironment3D` 做空间环境
- **工具**：`SynthSfx.gd`（229 行，程序化合成音效，无需外部素材）
- **实用逻辑**：音乐按场景/楼层切换；headless 退出曾有泄漏（2026-09-17 记录已修）
- **评判**：切场景不断音不叠音｜退出无残留进程｜循环点无爆音｜音量分层（BGM/SFX/环境）独立可调

### 3.13 特效 `src/vfx` + `src/postfx`（46 文件 / 5,105 行）

- **链路**：需求 → 单特效脚本 → `VfxPool`（autoload）池化 → 调用方按需 dispatch → 参数进 P 键面板
- **工具**：`VfxPool3D.gd`（全局池）、`FlashlightColorTweaker`（后处理参数实时调）、`preview_combat_vfx_batch2.gd`
- **实用逻辑**：全部特效走池，不在战斗帧里 new；后处理覆盖层走 `GraphicsSettingsManager.set_debug_postfx()`，可持久化到 `user://postfx_tuning.json`
- **评判**：同屏峰值不掉帧｜池化无泄漏（数量回落到基线）｜视觉不遮挡准星与敌人轮廓｜可一键关闭做性能对照

### 3.14 训练场 `src/training3d`（9 文件 / 1,819 行）

- **链路**：无独立设计文档 → 直接按测试需求搭 → `TrainingRange3D` 总管 → 子件（刷怪台/靶位/卡牌台/补给箱）
- **工具**：`scenes/TrainingRange3D.tscn`
- **实用逻辑**：靶位命中用真实弹道判定，不是假扣血；卡牌台调 `TrainingFateBenchPanel` 试卡；刷怪台可指定类型与数量
- **评判**：靶位判定与正式一致｜试卡效果与实战一致｜退出训练场不污染正式存档

### 3.15 本地化 `src/i18n`（3 文件 / 490 行）

- **链路**：玩家可见文案抽到 `GameTextPackZhCN` → 稳定 ID → `GameText` 统一取词 → 缺词走回退链
- **实用逻辑**：默认中文，英文预留（`GameTextPackEn` 仅 24 行，基本空壳）；内部 ID 与调试口径不翻译
- **评判**：无硬编码中文残留｜缺词回退不显示 key｜切换语言不重启

### 3.16 美术资产管线 `art_source` / `assets` / `scenes`

- **链路**：参考图 → Blender 源（`art_source/`，Git+LFS，不入包）→ 导出 glTF/场景 → Godot 导入 → 命名与台账 → 运行时引用
- **工具**：Blender + `blender_level_builder` 插件（2026-09-14 记录）、`scripts/art_source_paths.py`、`scripts/check_asset_registry.py`、`scripts/asset_guard.py`
- **实用逻辑**：贴图上限 **玩家 ≤1024、怪物（含 Boss）≤512、其他 ≤1024**；正式 PCK 曾从 502.73 MiB 压到 267.12 MiB；源文件 1,095 份 Blend 保真
- **评判**：命名符合 `check_asset_runtime_naming.py`｜三角数/材质数在预算内｜完全重复贴图 0｜源与运行资产一一对应（`check_asset_registry.py` 绿灯）

### 3.17 开放世界 `src/open_world` + `scenes/open_world_*`

- **链路**：`design/rooftop_*` / `tower04_*` 出方案 → 分块建（chunk 30/60/100/500 m）→ 手调摆位增量同步 → 运行时挂载
- **实用逻辑**：`skyline08` 只有 73 行材质绑定脚本，几何全在场景里；手调增量要单独同步回源，否则重生成会覆盖
- **评判**：与塔体高差不冲突（曾记「屋面比塔3主天台低 10m」）｜碰撞齐全｜路线回归不破（曾测 319/0）｜远景不穿帮

---

## 4 评判五维（统一尺子）

同一把尺子量所有模块，缺一维就不算完。

| 维度 | 合格线 | 证据要求 | 常见挂点 |
|---|---|---|---|
| **① 功能正确** | 主路径 + 拒绝路径都能跑通 | 探针输出 + 手工复现步骤 | 只测 happy path，失败分支没写 |
| **② 视觉达标** | 真实渲染截图，不是编辑器视口 | 1080p 或 1440p 截图，能看出材质/光照 | 用白盒代替成品；截图裁剪掩盖缺陷 |
| **③ 性能** | 同场景 P95 帧时与基线比不退化 | 帧时采样表（中位 + P95） | 只报平均帧率；不标测试机配置 |
| **④ 数据安全** | schema 有版本号，可迁移可回滚 | 存档前后 dump 对比 | 直接改字段不迁移；旧档读新档崩 |
| **⑤ 可回归** | 探针脚本入库且能重跑 | 探针文件名 + 最近一次日志 | 一次性截图，下次改动无法复验 |

**红线三条**：
1. 「专项通过」不许写成「已完成」。项目既有写法是四级（专项 / 真实渲染 / 完整工程 / 设备），照抄。
2. 改动超 500 行或跨 2 个以上模块，必须补一条 `development/` 记录，写清改前基线。
3. 数值类改动（伤害、掉落、价格）必须给「改前 → 改后」对照表，不给数字就当没做。

---

## 5 工具清单

| 工具 | 干什么 | 位置 / 命令 | 备注 |
|---|---|---|---|
| **Godot 4.6** (Forward+) | 引擎本体 | 工程根 `project.godot` | 主场景 `scenes/StartupLoadingScreen.tscn` |
| **Codex CLI 0.163.0** | 代码代理 | `C:\Users\zhuangmenghong\AppData\Roaming\npm\codex.cmd` | ChatGPT 账号登录，工作目录 `I:\工作项目\shellstrom2` |
| **WorkBuddy** | 工程助手 | `.workbuddy/`、`.workbuddy-ai/` | 与 Codex 并存 |
| **探针套件** | 取证主力 | `tests/verification/*.gd`（130+ 个） | 命名规律：`probe_` 查参数、`capture_` 出图、`preview_` 看表现 |
| **tools 探针** | 参数扫描 | `tools/probe_*.gd` + 同名 `.tscn` | 必须配 tscn 才能直跑 |
| **构建脚本** | 关卡/资产生成 | `scripts/*.py`（20+ 个） | `build_expedition02_level_plan.py`、`assemble_block00_facilities.py` 等 |
| **工具链自检** | Python 单测 | `tests/tooling/test_*.py` | 校验脚本本身别写错 |
| **Blender + 关卡插件** | 资产源 | `art_source/`（1,095 份 Blend） | 源不入包，Git+LFS |
| **Git + LFS** | 版本管理 | `.gitattributes` | 大文件走 LFS |
| **包体审计** | 体积台账 | `I:\工作项目\shellstrom2\包体审计_20261017.md`（8,322 B）、`仓库体积审计_20261011.md`（10,391 B） | 在工程上一层目录 |

---

## 6 本次整理发现的缺口（按风险排序）

1. **`world3d/Dungeon3D.gd` 9,482 行单文件** — 门后流程、购买、波次、撤离、存档全在一个文件。任何改动都可能牵连全局，建议先按「门流程 / 波次 / 撤离 / 存档」四块拆，再动功能。
2. **`data/level_plans` 是空的（0 文件）** — 关卡方案没落盘。改关卡前必须先确认方案是程序生成还是临时内存，否则改不到点子上。
3. **伤害数字两套并存** — `src/fx/CombatDamageNumber3D.gd`(45 行) 与 `src/vfx/VfxDamageNumber3D.gd` 同时在，容易改错文件。
4. **`WeaponForge.gd` 注释与常量不一致** — 文件头写「6×6 = 36 格」，实际常量 `TRAY_COLUMNS/ROWS = 5`、`TRAY_CAPACITY = 25`。以常量为准，注释待改。
5. **探针没有统一 runner** — `tests/` 根目录只有 `README.md` 和 `test_runtime_texture_roles.py`，130+ 探针靠手工逐个跑，回归成本高。
6. **`src/assets` 是空壳** — 0 个 `.gd`，目录还在，容易误以为有内容。

---

## 7 怎么复现本文数据

在 2 号机 PowerShell 里跑：

```powershell
# 各模块文件数与行数
$r='I:\工作项目\shellstrom2\ShellStorm2'
Get-ChildItem "$r\src" -Directory | ForEach-Object {
  $f=Get-ChildItem $_.FullName -Recurse -Filter *.gd -File
  $l=0; foreach($x in $f){$l+=(Get-Content $_.FullName | Measure-Object -Line).Lines}
  "{0}`t{1}`t{2}" -f $_.Name,$f.Count,$l
}

# autoload 清单
Select-String -Path "$r\project.godot" -Pattern '^\w+="\*res://'

# 各模块最大文件
Get-ChildItem "$r\src" -Recurse -Filter *.gd -File |
  Sort-Object Length -Descending | Select-Object -First 15 Name,Length
```

数字对不上就说明代码变了，以新数为准，本文日期不追改。

---

*整理：杰西卡　2026-10-20　机器：2 号机（SS-zhuangmenghong）*
