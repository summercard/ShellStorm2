# 2026-10-15 装备与棋盘包裹体验深化

- FeatureID：INVENTORY-SLOTS / WEAPON-OWNERSHIP / PRESENTATION。
- 工程版本：0.1.0；设计修订 r2；来源：本次用户三张参考图，前两张负责风格，第三张负责布局关系。
- 范围：修改正式 InventoryUI、GridInventoryBoard、ItemSlot、ItemModelIcon3D，以及 InventoryModule 的空间事务；未增加平行背包实现。
- 工作区已有大量未提交修改。本次改前副本位于工程外 `ShellStorm2-backup/2026-10-15_inventory_experience/before_edits/`，未重置已有改动。

## 交付

左侧深蓝圆角装备面板中间显示当前换装角色，主副武器和对应配件位于两边，下方是背包装备、快捷道具及命运信息。右侧为六列连续棋盘，容量按格面积与物品件数分别显示。取消全屏实色底板，保留中央游戏画面；保险、丢弃和返回操作固定在棋盘滚动区域外。

跨格物品的输入矩形与显示矩形一致，覆盖格不再抢走输入。物品名称、堆叠数及尺寸可见，橙色悬停描边；大图标使用384px最长边投影，角色取景排除隐藏网格，避免角色缩成一小团。UI色板/面板样式由UIPalette/UIStyleFactory提供，不覆盖其它界面的主题树。

拖拽提供合法/冲突占格预览、R旋转和Esc取消，释放位置转换为棋盘左上锚点。移到面板外取消，仅明确丢弃区执行丢弃。关闭界面取消未提交拖拽。物品真实所有权仍通过现有装备、快捷栏与保险服务交接。

InventoryModule新增只读can_move_or_swap_slots，提交复用该预检；修复拒绝旋转会改写源朝向、同格不能旋转、交换后两矩形可相互重叠，以及ignored_index参数未参与空间判定的问题。未改存档schema。

## 验收证据

日志、截图与独立改前对照工程位于 `ShellStorm2-work/sessions/2026-10-15_inventory_experience/`。所有Godot测试在进程启动前设置独立APPDATA/LOCALAPPDATA，未使用正式存档。真实渲染采用Godot 4.6.3，1280×720及1920×1080，原生鼠标拖放事件；自动化鼠标与OS位置逐帧同步，避免合成输入与系统鼠标位置不同步造成假失败。

| 检查 | 退出码/结果 | 限制 |
|---|---|---|
| verify_inventory_experience_visual | 0，23项检查通过 | 大物品末格悬停/点击/拖动、R旋转、Esc回滚、装备/卸下、快捷栏往返、第二保险格往返、整理保量、扩容滚动、双分辨率截图、关闭 |
| verify_grid_inventory_layout | 0 | 典型尺寸、占格碰撞、JSON恢复、旋转失败快照不变、同格旋转、交换重叠拒绝；旧12格断言按设计24格修正 |
| verify_gamepad_input_flow | 0，输出OK | headless出现2条dummy renderer material-null错误，不签署无错误通过；不等于完整手柄棋盘摆放已实现 |
| verify_equipment_transaction_service | 1 | 改前与改后错误集合相同（8条）；未标绿 |
| verify_backpack_equipment_flow | 1 | 改前与改后错误集合相同（188条，含旧背包尺寸/面数契约）；未标绿 |
| verify_tactical_inventory_minimap_flow | 1 | 旧用例仍使用“无锚点=空格”的_find_empty_slot，不能正确找连续矩形；新版预检提前拒绝被覆盖的格，旧断言待迁移。实际快捷/保险回程已由新真实鼠标专项覆盖 |
| UI账本structure | 0 | 18行结构/公式通过 |
| UI账本full | 1 | 5项存量问题，未批量回填其它UI的哈希 |
| check_media_asset_domains | 1 | 固定预期16行，当前UI账本18行；本次没有新增资产行 |
| check_asset_runtime_naming | 1 | 工作区存量带版本资产债务；本次未新增运行模型路径，角色复用已有衣柜预览常量 |
| check_documentation_contracts | 1 | 现有CHANGELOG链接缺失、其它未登记测试、媒体行数门禁失败；本次两个专项已登记 |
| verify_ledger_split | 1，剩余15项；UI域无失败 | 只更新本次两个UI条目的无损指纹，保留其它域漂移与未登记资产 |

未执行：全量游戏套件、完整远征存读档、移动端性能、完整手柄棋盘操作、共享图标全品类像素裁边专项。当前预览同步角色换装，不宣称已展示所有实时持枪动作及背负装备。

## 文档与台账

主设计《装备与棋盘式包裹设计》增加r2交互/视觉契约，MODULE_INDEX同步功能状态；复用UI-SCREEN-INVENTORY-3D与UI-ICON-ITEM-MODEL-3D，更新规格、时间、说明和本次InventoryUI源码SHA。图标场景文件未修改，其历史哈希漂移保持待核验。UI账本只改既有两行及追加域日志，未改其它资产数据、查重公式或数据验证范围。

## 后续边界

旧回归迁移必须依据物品矩形选择合法落点，不能恢复只按单格判断的旧规则。防具/战术/护符显示未开放，未冒充已实现玩法。完整手柄棋盘操作与全部历史回归闭环仍应单独验收。
