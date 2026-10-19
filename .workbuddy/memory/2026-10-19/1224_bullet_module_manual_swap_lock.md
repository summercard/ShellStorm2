# 2026-10-19 12:24 弹药模块手动更换关闭

## 业主口径

- 玩家不能从背包直接替换枪的子弹模块；手动更换机制锁掉。
- 「随机在枪身上」的机制保留（掉落枪仍随机自带弹种）。
- 后续只能在枪械工坊通过特殊方法更换。
- 只改这个，其它不动；记录设计文档与账本，调整对应测试。

## 落地

- 唯一真源：`WeaponBulletDrop.MANUAL_SWAP_ENABLED = false` + `MANUAL_SWAP_BLOCK_REASON`。
- 两层判据：`WeaponInstance.bullet_module_locked`（掉落身份锁）在前，渠道总闸在后。
- 四条手动入口全拦：`Player3D.install_bullet_module_to_weapon_slot`、`Dungeon3D` 背包左键/快捷装配、
  `ItemSlot`/`InventoryUI` 拖武器格；训练场拖放信号同样拒绝。
- UI：弹药标题「弹药（锁定）」、悬浮卡指向枪械工坊、武器卡追加「需枪械工坊更换」。
- 保留：`RewardService` 仍掷 `WeaponBulletDrop.roll()`；子弹模块仍可掉落/拾取/存放/出售/带入。
- 训练场：军械库组合（`equip_combination_for_test`）保留为测试专用整枪重装；背包换弹关闭。

## 验收

- `verify_bullet_module_equipment_flow` → `BULLET_MODULE_LOCK_OK` exit 0（改判据，文件名不变）
- `verify_weapon_drop_grade` → `WEAPON_DROP_GRADE_OK` exit 0（lock-guards 加严）
- `verify_training_range_equipment_ui` → `TRAINING_RANGE_EQUIPMENT_UI_OK` exit 0（新增背包换弹锁定）
- `verify_weapon_attachment_inventory_flow` / `verify_starting_weapon_contract` /
  `verify_training_range_3d_flow` / `verify_inventory_experience_visual` / `verify_weapon_forge` 全 exit 0
- `tools/probe_bullet_lock` → `PROBE_BULLET_LOCK_DONE OK`
- 负向自测：临时把 `MANUAL_SWAP_ENABLED` 改 true，新用例如期报红，已还原 false。

## 文档/账本

- 04 §22.14、07.1、07.2、07.3、11.1、12 完成度、README、MODULE_INDEX、CHANGELOG。
- 新记录 `docs/v0.1/development/2026-10-19_bullet_module_manual_swap_lock.md`，
  并登记 `feature_registry.json` 的 `WEAPON-COMBAT`。
- 内容数据库《字段字典》：更新 `bullet_module_locked`、`attachment_slots{}`，新增 `bullet_module_swap_channel`。
- 武器账本《背包物品调用索引》：8 个子弹模块入口改指 `Dungeon3D._reject_manual_bullet_module_swap`，
  同步 `ledger_split_baseline.json` 的 `背包物品调用索引` 指纹。

## 未做

- 枪械工坊更换流程未实现（成本、旧模块去向、回滚、幂等未定）。
- 工坊必须走独立命令，禁止把 `MANUAL_SWAP_ENABLED` 翻成 true 复用旧入口。
- 子弹模块掉落权重未调整（平衡问题，留给业主裁决）。
