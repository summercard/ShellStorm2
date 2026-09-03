# 基地99层独立资产包 v009

本目录与 `base_facility_runtime_layout_hq_v009.blend` 的叶级资产 Collection 一一对应。

- 共 91 个独立资产包，其中地面 36 包；每块地砖及其直接附着深化内容位于同一个 `floor/tile_rXX_cXX` 包。
- 本批东面设施位于 `east_facilities/`，门、补给机、配电系统、管线、三类垃圾设施、工作台、收纳、海报、安全设备、植物与吊灯均为独立目录。
- 每个资产目录内的 `asset_manifest.json` 记录 Collection 路径、对象清单、世界包络、材质角色、动画状态和未来导出文件名。
- 当前为 Blender 源场景与资产归类阶段；尚未制作独立 GLB、碰撞体或 Godot PackedScene。
- 公共色盘只引用 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`，不在单件资产目录重复存放。
