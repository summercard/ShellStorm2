# 基地布局独立设施包 v008

本目录对应 `base_facility_runtime_layout_hq_v008.blend` 的 Blender Collection 资产包结构，供后续逐设施导出和游戏侧管理使用。

- `floor/`：统一地面系统；每个子目录对应一块 5×5m 地砖及直接依附于该砖的深化内容。
- `architecture/`：墙体、阁楼、楼梯和阁楼底部铁皮遮挡等建筑结构。
- `south_facilities/`：本批次深化的 BASE CAMP 主门、标识、柜体、全息平台、终端、墙面管线和栏杆附着细节。
- `loft/`、`warehouse/`、`support/`：既有阁楼设施、仓库设施和环境支持组件，本批次保持结构锁定。

每个末级设施目录包含 `asset_manifest.json`；一个独立设施只归属一个资产包。当前共 82 个资产包，其中 36 个为地砖包。

本批次未生成独立 GLB、碰撞或 Godot PackedScene；目录是后续导出边界，不代表已完成运行时接入。
