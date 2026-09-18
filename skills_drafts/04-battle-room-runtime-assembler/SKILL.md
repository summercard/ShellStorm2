---
name: 04-battle-room-runtime-assembler
description: 当使用场景美术资产在 Godot 中完成某个具体战局房间编号时使用。在“Blender布局加稳定PackedScene重放”和“没有房间布局时按白盒直接装配”两条支线间路由，产出最终运行房间，不修改玩法或程序化规则。
agent_created: true
metadata:
  display_name_zh: 04 战局具体房间Godot装配
---

# 战局具体房间 Godot 最终装配路由

## 目标

把一个具体房间编号完成为游戏内可调用的视觉房间。输入永远是“房间编号”，不是房间种类：

```text
房间编号
  -> 路由判断
  -> 分支 A：Blender 布局 + Godot 组件
  -> 分支 B：白盒 + Godot 组件
  -> 房间运行时节点 / 验收图 / 接入登记
```

只处理场景美术包装、组件导入和视觉装配。禁止修改玩法、关卡规则、房间拓扑、敌人、掉落、存档、门 FSM、导航或结算代码。

## 触发语句

- `拼装 main_02 房间`
- `把 exit_01 接入 Godot`
- `用白盒直装 branch_03`
- `按 Blender 布局完成安全房入口`
- `检查这个房间应该走哪个装配分支`

## 路由决策

### 分支 A：有具体房间 Blender 布局

判定条件：同时存在并通过验收：

- 具体房间编号对应的 `room_layout.json`；
- 匹配的 `room_type`；
- 布局引用的组件已按 `godot-model-asset-import-standard` 导出并包装；
- 所有 AssetID 能解析到稳定 PackedScene。

执行：

```text
读取 room_layout.json
  -> 校验布局和组件版本
  -> 由 AssetID 注册表解析稳定 PackedScene
  -> 按 position / rotation / scale 实例化
  -> 添加房间级玩法挂点，但不重做视觉摆位
  -> 运行具体房间验收
```

Blender 布局是视觉摆放事实源。Godot 不得再手工摆第二套视觉组件。

### 分支 B：没有具体房间 Blender 布局

判定条件：没有合格的具体房间 `room_layout.json`，但存在：

- 具体房间白盒；
- 匹配房间种类组件的 catalog、GLB 和 PackedScene；
- 白盒中可推导的墙、地板、门洞、连接和尺寸。

执行：

```text
读取白盒
  -> 生成临时/正式布局记录
  -> 只实例化已导入的 Godot 组件
  -> 将文字需求/效果图作为视觉排序和装饰决策输入
  -> 保存生成的 room_layout.json（若用户允许固化）
  -> 运行具体房间验收
```

分支 B 可以自动完成基本结构，但不应声称与 Blender 效果图完全一致。复杂的房间构图应转回 `03-battle-room-instance-layout-authoring`，完成分支 A 后再重放。

## Godot 资产来源

使用 `godot-model-asset-import-standard`：

```text
组件 Blender 源
  -> 组件输出 GLB
  -> 稳定 components/<asset_id>/...
  -> 稳定 runtime/<asset_id>/...tscn
  -> AssetID 注册表
```

运行时路径不携带版本号；版本只写在 source、manifest、PackedScene metadata、布局快照和场景账本。不得直接加载裸 GLB，不得从房间 Blender 源导入整屋 GLB。

组件账本路径必须通过：

```text
assets/registry/ledger_index.json
```

解析所属分账本；不得写死总账本或自行新建第二套台账。

## 房间输出

运行时装配不把 Blender 过程源、白盒源或整屋 GLB 复制到 Godot。过程源保持在：

```text
assets/art/environments/tower_zones/<block_id>/source/room_instances/<room_id>/v###/
```

运行时房间的登记、路由结果和验收文件保持在：

```text
assets/art/environments/tower_zones/<block_id>/runtime/room_instances/<room_id>/
```

每个具体房间的最终美术装配至少生成：

- 具体房间运行布局/装配 manifest；
- `assembly_route`：`blender_layout_replay` 或 `whitebox_direct_assembly`；
- 房间编号、房间种类、白模源、组件源、Godot PackedScene 引用；
- 实例数量、包络、门洞、碰撞责任和版本哈希；
- 运行时验收日志和至少一张游戏内或验收场景截图；
- 关卡调用登记。

建议目录：

```text
assets/art/environments/tower_zones/battle/runtime/room_instances/<room_id>/
├─ room_runtime_manifest.json
└─ acceptance/
```

## 撤离房门禁

对于 `EXTRACTION_ROOM`：

- 默认尺寸必须为 30×30m，除非白模 manifest 明确变更并完成审批记录；
- 必须实例化一个 `slot_role=extraction_beacon` 的固定设施组件；
- 信标不得是拾取物，不得把撤离判定写入视觉组件；
- 运行时必须报告信标实例存在、位置在房间边界内、无重复实例；
- 玩法层已有撤离逻辑时只绑定既有接口，不重新实现。

## 严格失败条件

遇到以下任一情况立即失败，不用旧资产冒充新链路：

- 房间编号、房间种类或白模无法唯一解析；
- 组件缺 GLB、PackedScene、AssetID、包络或来源；
- Blender 源版本高于 Godot 已接入版本；
- 布局包含房间自有共享 Mesh、整屋 GLB 或非法缩放；
- A 分支布局和 B 分支白盒同时被当成视觉事实源；
- Godot 代码需要新增房间专用拼装函数；
- 撤离房缺失信标；
- 资产导入任务试图触碰玩法/规则类文件。
