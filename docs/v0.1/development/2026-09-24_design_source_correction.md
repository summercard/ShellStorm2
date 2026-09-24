# 第五项：设计源与技术施工分层纠正

日期：2026-09-24；工程版本：`0.1.0`；范围：文档结构与14个FeatureID的目标规则入口；**未修改玩法代码、资产、数值或游戏版本**。

## 原问题与处理

此前[技术契约补齐](2026-09-24_design_contract_backfill.md)把04、07、09、18、15及新13.1的施工事实称为“主设计已补”。这些页确实记录了正式接口与未闭环故障，但混合目标/事实/验收，不能作为未来玩法变更的唯一决策依据。用户要求未来开发以设计文档为主，故补[战斗奖励与物品流转](../design/战斗奖励与物品流转设计.md)、[基地经济与存档结算](../design/基地经济与存档结算设计.md)、[对话与战斗信息呈现](../design/对话与战斗信息呈现设计.md)、[时间日夜与画质](../design/时间日夜与画质设计.md)四页，并把相关施工页回链。

14个已迁移FeatureID：`WEAPON-COMBAT`、`WEAPON-OWNERSHIP`、`INVENTORY-SLOTS`、`WORLD-LOOT`、`REWARD-SERVICE`、`BASE-SHOP`、`RUN-MERCHANT`、`SAVE-PROFILE`、`SAVE-RUN`、`RUN-SETTLE`、`DIALOGUE-UI`、`UI-HUD`、`TIME-DAYNIGHT`、`GRAPHICS-POSTFX`。在注册表与索引中按“设计→施工”排序；其余23项在跟踪表标为独立设计待补/待审，不冒称37项均已完成。

## 规则边界

设计页只收目标、玩家行为、跨功能责任、失败与验收意图；施工页保留当前API、schema、真实实现和缺口；本记录只描述本次编辑与验证。设计仍未冻结的统一命中schema、画质调参转正范围、复活来源等明确留作待裁决。现行游戏行为仅用于校正“当前事实”，不自动成为用户确认的未来设计。连续爬塔依用户裁决继续低优先级。

## 验证与未执行

`python3 scripts/check_documentation_contracts.py`：退出码0，130份文档/691个本地链接/37项功能，问题0（不验证设计语义）。`python3 scripts/check_feature_traceability.py`：退出码0，37项功能、追溯问题0。`python3 scripts/check_asset_runtime_naming.py`：退出码0，未新增版本化运行资产；存量欠账文件289/目录13/备份1仍在。注册表JSON解析与 `git diff --check`：退出码0。上述命令无故意故障注入或非预期脚本错误。本次无玩法代码变化，因此不重复把上轮11个逻辑场景历史通过当本轮通过。真实渲染、目标GPU、移动端、长测和所列功能故障分支均**未执行**，状态不变。
