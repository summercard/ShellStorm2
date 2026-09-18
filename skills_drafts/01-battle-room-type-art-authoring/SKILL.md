---
name: 01-battle-room-type-art-authoring
description: 当制作或深化 ShellStorm2 战局中的通用房、安全房、BOSS房、撤离房等“房间种类”Blender 美术源时使用。沿用 blender-game-prop-standard，保持白盒尺寸和房间接口，产出可升版、可拆解的房间种类源，不修改玩法或程序化房间规则。
agent_created: true
metadata:
  display_name_zh: 01 战局房间种类美术源制作
---

# 战局房间种类美术源制作

## 目标与边界

将“房间种类”作为美术生产单位，而不是具体房间编号。处理以下类型：

- `SAFE_ROOM`：安全房；当前局内关卡01为 2 个实例。
- `COMMON_ROOM`：通用房；当前局内关卡01为 14 个实例。
- `BOSS_ROOM`：BOSS 房；当前局内关卡01为 1 个实例。
- `EXTRACTION_ROOM`：撤离房；当前新增类型，默认 30×30m，并且必须有撤离信标。

本 Skill 只负责白模约束下的房间级 Blender 美术源、结构表现和可拆解性。不得修改 `FloorPlanGenerator`、`TowerDescent3D`、战斗、敌人、掉落、存档、门状态机、导航规则或任何玩法/规则类代码。

## 触发语句

以下表达均触发本 Skill：

- `使用 blender-game-prop-standard 制作通用房种类`
- `制作安全房种类的 Blender 源`
- `制作 BOSS 房种类`
- `制作撤离房种类，30x30m，带撤离信标`
- `按这个效果图深化通用房种类`

必须从用户输入中确认：房间种类、白模路径、尺寸/门连接、效果图或文字需求、是否允许新增固定设施。缺少房间种类或白模时停止，不猜。

## 输入解析顺序

1. 读取战局白模 `source/art/whitebox/tower_zones/<level>/` 的 `unit_plan.json`、房间 manifest、尺寸、门洞和连接数据。
2. 读取房间种类对应的设计文档、参考图和既有房间源；不得从旧 Blender 场景猜尺寸。
3. 读取项目资产规范与 `blender-game-prop-standard`，沿用公共色盘、四类材质、PaletteUV、坐标和版本规则。
4. 确认 `block_id=battle`、`design_scope=scene_art`、`asset_ledger`。这三项贯穿后续源、组件、导入和验收。

## 房间种类源的所有权

房间种类源拥有：

- 房间级视觉构图、墙/地/顶/固定设施的设计；
- 白模规定的边界、层高、门洞、可走面和镜头内结构；
- 可被后续拆解的语义独立对象与区域布局；
- 参考相机、展示视图和美术验收渲染。

房间种类源不拥有：

- 玩法节点、敌人生成、掉落、存档和房间拓扑规则；
- 只能在 Godot 运行时存在的门 FSM、导航和交互脚本；
- 未登记的房间编号专用 GLB/PackedScene；
- 不能拆解或不能复用的整屋焊接网格。

## 制作要求

严格调用 `blender-game-prop-standard` 的流程：

1. 先建立白模与范围快照，记录尺寸、墙厚、逻辑高度、可见高度、门洞和连接方向。
2. 再按效果图制作房间种类视觉源，保留墙、地板、天花板、门框、固定设施、管线和环境支持的语义边界。
3. 所有独立设施、建筑模块、地砖、门和撤离信标必须能单独识别；不得把全屋合并成一个不可拆解网格。
4. 使用项目公共色盘 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`，仅使用四个共享材质角色，保留 PaletteUV。
5. 保留 `01_制作组件` 与 `02_游戏输出` 的层级；展示相机、灯光和参考辅助对象不得进入游戏组件输出。
6. 保存新版本，不覆盖历史源；房间种类源统一放置于：

```text
assets/art/environments/tower_zones/<block_id>/source/room_types/<room_type>/v###/
```

该目录只保存房间种类过程源、预览和验收；不放组件 GLB、Godot PackedScene 或具体房间编号布局。历史 `source/entry_safe_room/`、`source/main_room_02/` 等目录只作为兼容读取，不作为新任务落位。

## 撤离房硬契约

撤离房属于房间种类，不是把普通房改名。默认契约：

```text
room_type = EXTRACTION_ROOM
nominal_dimensions_m = [30.0, 30.0]
required_facility = extraction_beacon
beacon_asset_role = fixed_scene_facility
beacon_pickup = false
beacon_ownership = component_library
```

撤离信标必须是可拆解、可独立替换的固定设施组件。不得把信标焊进整屋网格，也不得把信标实现成可拾取道具；信标的激活、撤离判定和存档状态由玩法系统拥有，本 Skill 只负责视觉组件和挂点/接口预留。

## 输出与门禁

交付至少包含：

- 版本化房间种类 `.blend`；
- 房间种类 manifest，包含 `room_type`、`whitebox_source`、`dimensions_m`、`required_components`、`required_facilities`、`block_id`、`asset_ledger`；
- 参考全景、俯视图、关键近景；
- 可拆解对象清单；
- 范围锁定签名与 Blender 美术验收结果。

门禁：尺寸/门洞/墙高不符合白模则失败；房间只有整屋网格无法拆解则失败；材质、PaletteUV、色盘路径不符合规范则失败；新增玩法或规则代码则失败。通过后才能交给 `02-battle-room-component-decomposer`。
