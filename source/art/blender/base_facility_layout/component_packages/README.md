# 基地场景组件资产包

本目录对应 `base_facility_runtime_layout_hq_v007.blend` 中的叶级资产包 Collection，用于后续逐设施导出、碰撞制作与 Godot PackedScene 接入。

## 目录规则

- `architecture/`：保留墙体、阁楼主体、阁楼下方铁皮封闭体、贴墙 L 型楼梯。
- `floor/`：统一地面系统；`tile_rXX_cXX/` 每个目录对应一块 5m × 5m 原地砖及该砖范围内的深化内容。
- `loft/`：阁楼生活设施；床、布帘、桌椅、工作台、电脑、电台、急救包、灭火器和补给柜分别成包。
- `underloft/`：阁楼铁皮封闭体外侧的视觉中心设施；电视、低柜、霓虹标识、各储物柜、武器工作台和自动补给机分别成包。
- `warehouse/`：仓库及辅助设施；货架、维修台、发电机、电池、配电、水处理、压缩机、卷盘、垃圾分类和资料板分别成包。
- `support/`：跨设施共享的吊灯、应急灯、蒸汽和尘埃动效。

每个叶级目录内的 `asset_manifest.json` 记录 Blender Collection、对象清单、对象数量和未来导出状态。当前阶段只完成清晰归类，尚未逐包导出 GLB、碰撞或 PackedScene。

## 约束

- 场景总资产 ID 保持 `ENV-BASE99-ART-LAYOUT-3D`，避免为本次整理重复创建资产 ID。
- v007 只改变 Collection 和磁盘目录归属，不改变对象坐标、父子关系、网格、材质、灯光、动画或画面。
- 后续独立导出时，以每个清单记录的叶级 Collection 为唯一选择范围。
