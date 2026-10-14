# 8件物品地面简模接入

FeatureID：ASSET-PIPELINE / WORLD-LOOT / INVENTORY-SLOTS。工程版本0.1.0。
设计依据：[物品道具双模型制作规范](../design/物品道具双模型制作规范.md)。

## 交付

大型电池、小型电池、治疗药水、标准子弹模块、肉质弹匣、三叉枪口、橡皮枪托、放大镜瞄具已从现有ground源导出。三角面数分别为168、120、178、176、192、198、145、198。

正式文件位于 `assets/art/items_weapons/{props,weapons}/<slug>/`：`components/*_ground_visual_top3d.glb`、`runtime/*_ground_root_top3d.tscn`、`asset_manifest.json`。路径无版本号，Prefab元数据记录v001。8份GLB的`.import`随资源登记，绑定既有公共色盘导入脚本，关闭自动LOD和动画导入。源高模和地面Blend均未改写。

`ItemModelFactory3D.GROUND_SCENES`集中维护8个内容ID到地面Prefab的映射；`create_model`增加可选model_role参数，默认preview。`GroundLootPickup3D._build_visual`显式传ground，替换这些物品的程序化地面外观。未知物品仍走既有生成路径。背包图标、预览和枪上配件本批不切换。拾取碰撞、库存、弹跳、收集和0.504倍率保持原所有者及规则。

## 账本

经ledger_index解析道具和武器分账本，更新同一AssetID资产行的Prefab路径、哈希、源追溯与进度；另以Prefab登记事务添加3条`3D-物品`、5条`3D-武器`记录，同步两页基线摘要。调用索引同步ground路径。非目标资产行指纹保留。

状态为`exported_pending_godot_validation`：资源已导入、代码已接线，未签署运行验收完成。高精度preview源仍保留，尚未导入。

## 执行记录与限制

- Blender后台导出退出0，产出8份GLB及独立包装；导出过程确认高低源哈希不变。
- Godot `--headless --import --path .`退出0，本次导入日志未出现ERROR或Parse Error；存在其他场景旧缓存色盘UID警告，Godot按文本路径解析。
- 本次未新增或运行测试；独立场景运行、实际拾取、真实渲染、账本及全项目门禁未执行。导入成功不等同于这些验收通过。
- 过程记录位于工程外 `ShellStorm2-work/sessions/2026-10-14_item_ground_import/`，包含export_report.json、import.log、ledger_transaction.json。改前副本位于`ShellStorm2-backup/2026-10-14_item_ground_import/before_edits/`。

后续重导工具：`tools/asset_pipeline/export_reference_ground_runtime.py`；登记工具：`tools/asset_pipeline/register_reference_ground_runtime.py`。重复登记复用现有Prefab路径行，不新增AssetID；域日志保留每次登记记录。
