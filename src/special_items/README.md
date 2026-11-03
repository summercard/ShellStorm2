# SPECIAL-ITEMS

独立玩法模块。规则和数据契约见 [特殊道具系统设计](../../docs/v0.1/design/特殊道具系统设计.md)，独立内容/资产账本见 [special_items_ledger.json](../../assets/registry/special_items_ledger.json)。

- `SpecialItemCatalog.gd`：读取 `data/special_items/catalog.json`，唯一数值源；`ItemRegistry`只注册其投影。
- `SpecialItemController3D.gd`：绑定一个内容ID，管理冷却、余油和右键输入。`configure(player, inventory, input_allowed)` 注入依赖；`equip`、`unequip`、`request_use`、`get_snapshot`、`export_state`、`restore_state`为公共接口。
- `SpecialItemWorld3D.gd`：当前场景的投掷、落地、火场、油迹图、传播与伤害。`launch`、`deposit_oil`、`add_fire`、`clear`为公共命令；`advance`允许纯时间步进验收。临时状态不写入持久档。
- `ui/`：读控制器快照；拖入特殊槽只更改绑定，不移动或复制库存。实际扣量只由库存模块完成。

允许依赖：注入的玩家瞄准/输入锁、`InventoryModule`、敌人公共伤害接口、`VfxPool3D`稳定AssetID。禁止从UI直接改库存；禁止世界模块读取 `Dungeon3D` 的房间、商店或存档私有状态。当前外部火源通过已有 `lamp_fire_patch_3d` 组识别；添加其他火源时通过明确的公共火源契约扩展。

正式接线只落在 `Player3D` 的控制器入口、`Dungeon3D` 的注入/HUD/快照与点击分流、`TowerDescent3D` 的跨层清理、`InventoryUI` 的槽位，训练场复用相同模块且不写正式档。

独立验收：`python scripts/verify_special_items.py verify_special_items_system verify_special_items_integration verify_special_item_assets`。原生图形验收：`python scripts/verify_special_items.py --visual preview_special_items`。Runner在启动Autoload之前隔离用户数据；产物落在工程外 `ShellStorm2-work/sessions/2026-11-03_special_items/`。
