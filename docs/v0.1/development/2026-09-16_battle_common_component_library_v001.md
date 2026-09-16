# 战局区块通用组件库 v001

日期：2026-09-16；记录ID：ART-BATTLE-COMMON-V001；功能ID：ASSET-PIPELINE；工程版本：0.1.0。
设计依据：[区块设计](../05.1_关卡区块设计.md)、[3D美术流程](../10.1_3D场景美术生产流程.md)及资产内 `DESIGN_SCOPE.md`。代码基线：`02ca6481d7743017d77ae8d0e8a2d1460de7b880`；交付状态：工作区，未提交。

## 变更与原因

用户要求新增区块用 Blender 组件文件并排列组件。以已验收的主路内容房02数据机房 v003 为来源，不修改原房间，复制43个设施/环境支持包到 `assets/art/environments/tower_zones/battle/source/common_components/v001/战局区块_通用组件库_v001.blend`。组件按服务器、工作终端、中央设备岛、维修与机箱、门框与标识、环境陈设、环境支持7类排列。

每包建立独立 Empty 根节点，网格转换为根节点局部坐标，XY居中、底面Z=0；主体和自发光保持分离。制作源默认隐藏、输出默认显示；Collection、磁盘manifest和catalog一一对应。房间专属墙与地砖不进入通用库，长管线/地面电缆保留为需要目标房间重排的环境支持件。

## 验证结果

| 项目 | 结果 | 证据 |
|---|---|---|
| 保存后组件与清单 | 退出0；43包、7类、75个输出网格，无空包、重属、清单差异或局部底面穿零 | `qa/saved_scene_validation.json` |
| 材质与逐面UV | 退出0；制作源与输出共150网格、191482面，17项检查通过 | `qa/material_validation.json` |
| 展示渲染 | 设施与长距离环境支持分两张真实渲染图复核 | `renders/` |
| 资产台账 | 新增 `ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY`，记录源路径、状态、版本和SHA256 | `qa/registry_update.json` |

## 遗留与状态更新

Blender通用组件源完成，尚未创建碰撞、GLB、LOD、PackedScene或Godot运行时映射。通用库的资产身份不改变来源房间内组件身份；本次仅建立可复用编辑与导出入口。原房间继续作为视觉布局母版，回滚不依赖组件库。
