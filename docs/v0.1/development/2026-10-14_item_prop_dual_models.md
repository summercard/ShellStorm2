# 8件物品道具双模型源制作

FeatureID：ASSET-PIPELINE / WORLD-LOOT / INVENTORY-SLOTS。工程版本0.1.0。设计依据：[物品道具双模型制作规范](../design/物品道具双模型制作规范.md)。

用户参考图中的大型电池、小型电池、治疗药水、标准子弹模块、肉质弹匣、三叉枪口、橡皮枪托、放大镜瞄具均已制作preview母版，并由现有制作组件派生ground母版。高模文件哈希保持不变，两角色共享AssetID。低模通过删微小细节、减少圆周/截面采样和局部减面生成，非另做不相关占位。

制作前Godot实测物品工厂、GroundLootPickup3D与武器挂点表现；两种电池旧箱体占位源高0.66m，药水0.82m，子弹直立长0.94m；配件主轴基准：弹匣0.24m、枪口0.16m、枪托0.32m、瞄具0.28m。主轴锁定，其他轴按用户参考图比例；ground完整保持preview最终包围盒。地面包装现有倍率0.504没有烘入源。配件探针为纯视觉尺寸取样，直接设置四槽展示，不作为合法装配兼容性验收。

所有母版位于 `art_source/items_weapons/{props,weapons}/<slug>/source/`；每件有原preview源与`_ground_source_v001.blend`。配套契约、source_manifest与ground_manifest记录用途、哈希、尺寸和三角数。场景四材质、唯一外链色盘和PaletteUV沿用；药瓶使用不透明清漆与浅色肩部表达玻璃感。

验收：重新打开8份ground源，三角数均100–200；输出三角化、逐面UV、高低包围盒、根缩放1、色盘加载与高模哈希不变专项通过。完整统计与预览位于工程外 `ShellStorm2-work/items_reference_20261014/ground/`；源阶段无GLB/PackedScene导出或游戏用途分流，不提升正式接入状态。

账本：道具新增3资产、武器复用5资产身份；同一行登记两份源、分别记录哈希与面数。物品道具导航和武器物品索引同步制作进度。非目标资产基线指纹与Prefab分页保持。全域结构与无损基线检查通过；完整路径/哈希检查存在既有其他资产漂移，未批量接受其当前值。

规范skill：`item-prop-dual-model-authoring`，明确源尺寸实测、角色分流、100–200三角预算、减面后UV和轮廓检查、同AssetID登记及源/运行时状态分离。

## 最终交付统计

地面版按三角面统计：大型电池168、小型电池120、治疗药水178、标准子弹模块176、肉质弹匣192、三叉枪口198、橡皮枪托145、放大镜瞄具198。逐件源文件入口见 [交付清单](../../../art_source/items_weapons/reference_batch_20261014/DELIVERY.md)。

已完成的检查记录：8件源专项通过；全域账本结构与无损基线检查通过（1244资产、9分账本）；skill格式检查通过。全项目文档检查仍报告既有CHANGELOG失效链接、6项未登记验收脚本及UI账本数量差异；美术源目录检查报告另一批次`props/reference_kit/source/prp_reference_item_kit_source_v001.blend1`被Git忽略。这些全局问题未在本次物品制作中修改。
