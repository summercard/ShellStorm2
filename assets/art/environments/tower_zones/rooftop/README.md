# Rooftop

100F 天台当前**没有 PackedScene 入口**。整层由 `src/world3d/TowerFloorStage3D.gd` 程序化装配：18×16 格 / 90×80m 轮廓、234 块地砖、68 段女儿墙围护、承重与四边外围碰撞。地砖、女儿墙、楼梯的**外观件**是 Blender 导入的 GLB（`visual_only`），由系统按网格摆放，不是整块天台 prefab。

## 旧聚落天台已整体移除（2026-09-19）

用户要求删除旧的那套。以下资产已从仓库移除，不再参与任何加载：

- AssetID `ENV-ROOFTOP-SHELTER-90X80`（含 68 个 layout 设施组件）
- Godot 包装：`runtime/zone_rooftop_v021.tscn`
- Blender 源：`assets/art/environments/rooftop_shelter_3d/`（整体目录）
- 微缩景观：`assets/art/environments/rooftop_shelter_diorama_3d/`
- 50m 制作源：`source/art/blender/environments_v01/rooftop_shelter_50m/`
- 连带清理：`verify_rooftop_shelter_asset_contract`、`src/world3d/RooftopAmbience3D.gd`、`tools/asset_pipeline/` 下 3 个天台专用脚本

回滚锚点：`git tag pre-old-rooftop-removal`（HEAD `73e3fac6`）。

## 现行替代：天台参考组件库

`source/reference_components/v002/`（47 个独立包 / 10 类）。2026-09-20 起女儿墙主库为方案A：直段/外角总高 0.80m（含压顶）、厚度 0.50m、平整墙板；并包含 DMG-A/B/C 三件直段破损变种。女儿墙相关 GLB 已导出到 `rooftop/components/`，Prefab 已接入 Godot；其余参考组件仍按原 Blender 源交付口径管理。纯包名清单见该版 `component_packages_v002/tree.txt`。

各版 `qa/` 里的 `build_rooftop.py` 与 `scope_before.json` 仍登记着 v021 源的 SHA-256——那是制作当时未被改动的历史证据，源文件移除后这些记录不再可复算，**保留原样用于回溯，不要改写**。

`runtime/` 目录当前为空，留给接入新组件库时的 PackedScene 入口。
