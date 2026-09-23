# 连续爬塔与遗留合同优先级裁决

日期：2026-09-23；记录ID：HIDDEN-TOWER-PRIORITY-20260923；功能ID：`WORLD-ENTRY`、`WORLD-GATE`、`WORLD-SEGMENT`；工程版本：0.1.0。

## 用户裁决

连续爬塔不再是当前主要玩法。当前正式主线保持“99F基地远征情报室 → 读取界面 → 独立单层远征关卡 → 撤离返回基地”；塔楼连续下行路线保持隐藏和关闭，不在当前发布范围内修复。未来明确重新开放连续爬塔时，再恢复98—95/94—90/89—85区段、Boss下行门、隔离间、区段卸载与长时性能验收。

因此此前整改编号按以下口径处理：

| 编号 | 裁决 | 当前动作 |
|---|---|---|
| P0-4 | 不再作为当前主线Bug包 | 只确认当前正式版本与入口链正确；隐藏连续爬塔失败降为低优先级保留 |
| P0-7 | 不再作为当前P0遗留清零包 | 与连续爬塔有关的旧实现、旧资产路径和旧验收合同保留，未来重开时统一核签 |

## 当前最新版本确认

以下事实共同定义当前正式版本：

- `TowerDescent3D.DEEPEST_PLANNED_FLOOR = 98`，97F及以下不生成计划、Stage或下行边。
- `TowerDescent3D.INITIAL_LOOP_GATE_SEAL_ENABLED = false`，98↔99门是普通交通门，不执行旧首门封闭或反向撤退确认。
- 新存档直接在98F区块00办公室开场；98F为当前授权布局和和平区，不按旧随机战斗层首波合同验收。
- 当前正式关卡入口是`mission_operations`远征情报室；连续塔楼不出现在关卡列表。
- `verify_expedition_level01_flow`、`verify_central_expedition_hologram_facility`、`verify_block00_floor98_assembly`、`verify_unified_player_interaction_flow`与`verify_opening_script_runtime`已通过，支持当前入口、98F装配、交互和开场链。

## 保留但不立即修复

- `verify_arrival_gate_floor_bundle_flow`中98—95生成、95→94 Boss门/电梯、隔离间和区段卸载断言。
- `verify_three_segment_tower_generation_flow`覆盖的三区段连续塔楼能力。
- 只服务旧塔楼布局或版本化运行资产路径的验收合同。
- 只能在强制测试接缝中复现、尚未影响正式远征主线的流送问题。

上述内容不得被删除或伪装成通过；它们作为未来功能恢复清单保留，但不再占用当前P0修复排期。若共享门、流送、存档或奖励代码的问题可在正式远征路线复现，则按当前主线Bug重新提级。

## 验收与限制

本裁决不改玩法代码、不恢复塔楼深度、不修改测试阈值，也不删除旧验收。它只确定产品范围和整改优先级。现有`aggregate core`仍会报告部分隐藏路线/旧合同失败；后续如需形成严格的当前发布绿线，应另行把“当前正式主线门禁”与“隐藏路线保留门禁”拆成不同套件，而不是直接删除测试。
