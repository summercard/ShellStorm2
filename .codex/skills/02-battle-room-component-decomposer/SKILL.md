---
name: 02-battle-room-component-decomposer
description: 当把已验收的战局房间种类 Blender 源拆成可复用组件 Blender 文件时使用。负责将墙、地板、门、固定设施、装饰和环境支撑拆成独立组件包，保持 AssetID、原点、包络、PaletteUV 和账本追溯；禁止从具体房间编号反向制造伪通用组件。
agent_created: true
metadata:
  display_name_zh: 02 战局房间组件拆解
---

# 战局房间种类源拆解为组件源

## 目标与边界

把已经通过 `blender-game-prop-standard` 验收的“房间种类源”拆成可复用的组件 Blender 文件。拆解单位是房间种类组件，不是具体房间编号：

```text
房间种类源
  -> 组件识别与所有权划分
  -> 可复用组件 Blender 源
  -> component manifest / catalog
  -> 交给 Godot 导入 Skill
```

只处理场景美术组件。不得修改玩法、规则、房间连接、敌人、掉落、存档、门 FSM、导航或 `TowerDescent3D`。

## 触发语句

- `拆解通用房种类 Blender 源`
- `把撤离房源文件拆成组件`
- `按组件规范拆解这个 BOSS 房`
- `从这个安全房源生成组件文件`

必须确认输入是房间种类源，而不是 `main_02` 之类的具体房间布局源。若输入是具体房间编号，停止并转交 `03-battle-room-instance-layout-authoring`。

## 组件分类

按以下所有权拆解：

| 分类 | 例子 | 处理要求 |
|---|---|---|
| 建筑结构 | 5m 墙、带门墙、地砖、天花、转角 | 单独包，保留接口、锚点和网格尺寸 |
| 房间设施 | 终端、机柜、工作台、固定装置 | 单独包，主体与发光分离 |
| 房间装饰 | 墙面装甲、门禁、压边、标识 | 优先并入宿主结构组件；不能随方位复制 |
| 环境支持 | 管线、跨设施支撑、固定灯带 | 跨设施内容单独包；宿主不可分内容并入宿主 |
| 撤离信标 | `extraction_beacon` | 固定设施组件，必须独立可替换，不得作为拾取道具 |

能服务多个房间种类的组件进入战局共享组件库；只服务一种房间种类但会在该类型的多个房间复用的组件，进入该房间种类组件库。禁止把同一几何复制到两个库后各自维护。

## 拆解流程

1. 读取源文件、源 manifest、范围锁定记录和白模契约，记录源 SHA-256。
2. 建立拆解表：`component_id`、中文名、类别、Collection、根对象、依赖对象、局部原点、包络、正面轴、允许旋转、碰撞责任、是否自发光。
3. 对每个组件建立独立资产包，并将组件母版统一放入：

```text
assets/art/environments/tower_zones/<block_id>/source/common_components/v###/
├─ *.blend                    # 组件库母版
├─ 01_制作组件_按组件拆分
├─ 02_游戏输出_独立资产包_v###
├─ component_catalog.json
├─ component_tree.txt
└─ component_packages/<component_id>/asset_manifest.json
```

组件 GLB 不放在该过程目录，而放入同级稳定目录：

```text
assets/art/environments/tower_zones/<block_id>/components/<component_slug>/
assets/art/environments/tower_zones/<block_id>/runtime/common_components/<component_slug>/
```

历史 `source/common_components/v###/` 目录继续兼容读取；新组件源不得再创建到房间种类目录或具体房间编号目录。

4. 组件根必须稳定；建筑模块默认底部中心原点，设施默认底部贴地；不得通过整体非等比缩放修正尺寸。
5. 输出主体与自发光为独立网格；保留四类材质角色、PaletteUV、公共色盘外链和材质索引。
6. 组件拆解文件必须能单独打开、单独渲染、单独验证；不要只保留房间总场景引用。
7. 生成组件源版本，不覆盖房间种类源，也不覆盖历史组件源。

## 必须记录的契约

每个组件 manifest 至少包含：

```json
{
  "component_id": "ENV-BATTLE-ROOMTYPE-COMPONENT-EXAMPLE",
  "room_type": "COMMON_ROOM",
  "source_room_type_blend": "...",
  "component_blend": "...",
  "collection": "...",
  "root_object": "...",
  "bounds_size_m": [5.0, 0.3, 11.9],
  "local_origin": [0.0, 0.0, 0.0],
  "front_axis": "-Z",
  "allowed_rotations_y_deg": [0, 90, 180, 270],
  "collision_owner": "godot_wrapper",
  "palette_uv_layer": "PaletteUV",
  "asset_ledger": "resolved_by_ledger_index"
}
```

撤离信标额外必须记录：

```text
component_id = stable and unique
facility_role = extraction_beacon
pickup = false
activation_socket = optional visual socket only
runtime_logic_owner = gameplay layer, not component
```

## 门禁

- 组件包不可为空；对象不得跨包重复归属。
- 组件不能携带房间编号布局位置作为固定世界坐标；房间位置属于后续布局清单。
- 禁止从具体房间实例反向生成“伪通用组件”。
- 禁止输出房间专用整屋 GLB/PackedScene。
- `room_owned_geometry` 对后续实例布局必须为 `false`。
- 所有组件必须有 AssetID、稳定原点、包络、旋转和来源追溯。
- 源文件必须通过范围锁定、材质、UV、尺寸和包络验收后，才可交给 `godot-model-asset-import-standard`。
