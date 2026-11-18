# 叙事A/B、安全信标与局内商人教学文档收口

- 日期：2026-11-18；记录ID：`narrative_ab_safe_extraction_20261118`；工程版本：0.1.0。
- 功能ID：`NARRATIVE-TRIGGER / DIALOGUE-UI / RUN-MERCHANT / SAVE-PROFILE / WORLD-ENTRY / WORLD-LOOT / BOSS-STAGES`。
- 任务范围：修正旧主线 A+B 混用、增加 Boss032 多机位演出、首次局内贩卖机方式B教学、稀土钥匙后的安全返航方式B通讯与不刷怪信标；同步代码、剧情 JSON、测试、验收 runner、设计文档与 `feature_registry`。资产源、wrapper 与场景分账本由资产线程完成，本记录只核对其落位和状态。
- 工作区基线：开始前已存在未提交代码、测试、临时文件和其他并发变更；未回滚、未覆盖、未修改这些范围外变更。
- 备份：`I:/工作项目/shellstrom2/ShellStorm2-backup/20261118_044942_narrative_ab_safe_extraction/before_edits/`，授权范围内13份既有文档已复制；旧审计记录 `2026-11-17_narrative_presentation_ab_audit.md` 未修改。

## 1. 本轮文档变更

### 1.1 叙事与呈现

- 更新主线剧本、节点表、3.1—3.3专项和对话/UI技术契约：保留设计§0冻结的A/B边界，按当前代码核对旧A+B混入事实。
- 3.2改为9组 `camera.shot`，时间范围26.2—66.6秒，每镜4.2—4.6秒；机位按真实房间锚点与 `room-frame` 局部起终点表达，前25秒真实坡道步行、真实激活4.4/5.4/6.4边界保持不变。
- 目录剧情数更新为21份：原17份主线/教学，新增 `nar_tutorial_run_vending_01` 与 `nar_main_032_key_return_call`，另2份为入场仪式且不计主线。
- NPC正式稳定身份继续使用“绿苔”，未将用户口称“青苔”写入ID或改名。

### 1.2 局内贩卖机教学

- 稳定ID：`nar_tutorial_run_vending_01`。
- 设计触发：当前房间真实入树且在范围内的merchant服务点首次接近；不以room08、远处/假模型、upgrade服务点、看见模型或购买动作替代接近事实。
- 教学内容：本局金币、有限货架、不同局可能刷出好货；不自动开店、购买、补钱或改货架。完整对白收口并正常提交既有history才计完成；中断、死亡、离房、卸载不计完成，可按仍在范围内的真实证据重试。
- 事实状态：稳定ID、JSON、目录接入及真实merchant/upgrade反例入口已存在于当前工作区；本轮未运行最终Godot验收，不把当前代码存在写成最终通过。

### 1.3 稀土钥匙返航与安全信标

- 稳定ID：`nar_main_032_key_return_call`；钥匙ID仍为 `mq_key_rare_earth`。
- 指定首领高级箱领取、首领已败/来源校验、首次禁拟态、普通奖励保留和领取同事务永久保存均保持；不改为Boss死亡即赠送。
- 旧8秒自动返航规则从现行设计与施工契约中移除，改为：领取成功进入`call_pending`→返航通讯正常完整结束并保存`beacon_ready`→真实投放安全信标→玩家主动按E→8秒同步成功结算返99F。
- 安全信标：`PRP-EXTRACTION-SAFE-BEACON-3D`，类型`STORY_SAFE`，`defense_encounter_enabled=false`；约0.6秒落到真实可走地面后可交互，不自动启动；同步可离开范围，不产生防守怪/遭遇；普通信标刷怪规则保持。
- 兼容/失败：`main_story_auto_extraction`仅作为兼容行动键，内部schema2阶段为`call_pending/beacon_ready/cancelled`；旧schema1 active阶段迁pending且不继续自动tick；坏schema、坏字段、不同run或不同map拒绝恢复；死亡取消待办但永久key不丢；保存失败不显示成功、不重复结算。
- 资产事实：安全信标blend/GLB/wrapper/source manifest已制作；场景分册主表1025、3D设施66、域log125为v0.1.95，状态“Blender源已完成（Godot待验）”。本轮不改账，不把该状态冒称Godot已验或正式接入。

## 2. 当前已知结果与未执行项

| 项目 | 结果/状态 | 说明 |
|---|---|---|
| 设计与当前代码/JSON稳定ID核对 | 已完成 | 已确认两新增ID、`STORY_SAFE`分支、兼容键、3.2镜头字段与merchant真实接近入口存在；本轮只读核对，不修改代码/JSON |
| timeline | 已知 `133 passed` | 沿用当前工作区已知结果；不将其外推为本轮安全返航最终完整链 |
| performance | 已知 `52` | 沿用已知记录；不代签本轮新增链 |
| vending教学逻辑 | 已通过 | `20261118_081333_f23674/result.json`；headless Forward-independent，45 checks，failures=[]，金币/背包/货架不变，skip/close重试和history通过 |
| vending教学真实渲染 | 已通过 | `20261118_090825_a4754f/result.json`；Forward+/Vulkan，45 checks，failures=[]，4图；`04_vending_B_both_visible.png`目视确认左绿苔全息/右主角同屏 |
| 安全信标单元 | 已通过 | `20261118_082238_4ed503/result.json`；Forward+/Vulkan，38 checks，wrapper真实GLB、0.6秒落地、主动8秒同步、普通能力对照均通过 |
| 安全信标正式Tower集成 | 已通过 | `20261118_090057_ab6f79/result.json`；headless，119 checks，failures=[]；方式B通讯、skip重试、history、beacon_ready、真实投放、零防守/普通防守对照、8秒结算返99F全部通过 |
| Boss032真实Forward+ | 已通过 | `20261118_092340_e5907f/result.json`；Forward+/Vulkan，70 checks，failures=[]，52图；9组镜头/27采样点，当前JSON与证据同批 |
| Boss032视觉抽样 | 已通过 | 第2组镜头与第7组玩家反应镜头目视确认机位差异、显示器/环境入镜、无黑屏/穿模/侧边立绘；Vending B双侧截图同样目视通过 |
| 文档契约检查 | 未全绿（旧债） | 仍有历史断链与 `verify_fat_zombie21_gait` 登记债；本轮新增A/B、安全信标与贩卖机入口已登记，runner已解析safe报告 |
| 资产Godot接入验收 | 部分完成 | 安全信标 Blender/GLB/wrapper 单元与正式Tower集成均通过；分账本状态仍按资产线程记录“Blender源已完成（Godot待验）”，不擅自改正式资产状态 |
| 纯新档人工全关贯通 | 未执行 | 本轮验收覆盖正式fixture与隔离真实渲染，不等价于完整人工全关流程 |
| 文档契约检查 | 见§3 | 本轮命令退出状态与前19项旧债分开记录 |

最终结果回填表留给主线程；本记录不代签最终源码、最终渲染或最终资产状态。

## 3. 文档契约检查与旧债边界

本轮完成后运行：

```text
python3 scripts/check_documentation_contracts.py
```

结果：**退出码1**；本次输出 `documents=614`、`local_links=3320`、`features=44`、`test_references=140`。报告仍含历史断链与 `verify_fat_zombie21_gait` 注册债；本轮新增 `verify_story_safe_beacon` 已登记到 `feature_registry.json`，贩卖机/主线集成入口也已登记。未修复无关历史红项，不把旧债归因于本轮。

本轮已完成隔离 Godot 验收：贩卖机逻辑与真实 Forward+、安全信标单元与正式 Tower 集成、Boss032 当前版本 Forward+ 均有独立证据；未执行完整人工新档全关流程。旧`2026-11-17_narrative_presentation_ab_audit.md`仍保持历史性质，不与本轮证据混用。

## 4. 范围外保护

- 未修改任何 `.gd`、`.json`、`.tscn`、manifest、账本、`feature_registry`、测试、runner或资产文件。
- 未修改历史审计记录。
- 未改变后三个Boss、四钥匙齐备、中心塔最终战未实现边界。
