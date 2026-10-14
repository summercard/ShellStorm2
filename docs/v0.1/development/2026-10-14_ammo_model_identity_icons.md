# 通用弹药模型用途、图标与倾角修正

后续调整：通用弹药高低源的蓝色弹壳UV改为公共色盘黄色格，重新导出覆盖稳定GLB；大型电池和治疗药瓶ground额外放大30%，最终显示倍率0.6552，图标尺寸配置保持。源、清单哈希、账本与当前源索引同步。

FeatureID：ASSET-PIPELINE / WORLD-LOOT / INVENTORY-SLOTS。工程版本0.1.0。

用户明确更正蓝金色弹头模型为通用弹药item_ammo_pack。道具分账本新增ITM-CONSUMABLE-ITEM-AMMO-PACK登记现有源与独立Prefab；标准子弹模块WPN-BUL-MOD-BULLET-STANDARD保留原内容身份并退回程序占位。实际Prefab登记从武器分页转入道具3D-物品，历史源和运行文件路径保持稳定。源文件未改写。

ItemModelFactory3D的正式模型表将原mod_bullet_standard键更正为item_ammo_pack。ItemModelIcon3D显式选择icon用途，8件已导入模型均用于图标，当前复用ground简模；高精度preview源保留供后续接入。未登记物品继续原工厂表现。

模型内部TiltedPresentation绕Z倾斜45度，中心移到倾斜支点并根据原尺寸补偿高度。地面外层继续绕世界Y旋转，倾角不随旋转消失；图标仍使用现有自动测量与居中。该表现调整不改变拾取碰撞及世界倍率。

账本主行、实际Prefab页、调用索引、资产清单与无损基线同步。独立检查结果以本次命令输出为准。

本次账本结构与无损基线检查通过（1245资产）；Godot重新导入完成。文档检查仍报告既有失效链接、未登记验收项及UI数量差异。真实游戏画面未复验。
