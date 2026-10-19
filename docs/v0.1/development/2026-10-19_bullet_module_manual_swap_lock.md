# 弹药模块手动更换整体关闭（枪械工坊专用通道待实现）

- 日期：2026-10-19
- 类型：玩法规则调整（弹药模块更换渠道）
- 关联：`2026-10-17_bullet_module_equipment_entry.md`、`2026-10-18_weapon_forge_alchemy.md`
- 业主口径：**玩家不能从背包直接替换枪的子弹模块；手动更换机制锁掉；随机在枪身上的机制保留；后续只能在枪械工坊通过特殊方法更换。只改这个，其它不动。**

## 变更前

| 枪械来源 | 身份锁 `bullet_module_locked` | 能否手动换弹 |
|---|---|---|
| 掉落枪 | true | 否（2026-10-18 起） |
| 出厂枪 / 蓝图合成 / 商人 / 训练场借枪 | false | **能**（背包左键、拖武器格、装备面板、局内快捷装配） |

## 变更后

| 枪械来源 | 身份锁 | 能否手动换弹 |
|---|---|---|
| 掉落枪 | true（不变） | 否 |
| 非掉落枪 | false（不变） | **否**（2026-10-19 起） |

随机配弹完全保留：`RewardService` 仍调用 `WeaponBulletDrop.roll()`，掉落那一刻定死弹种，
写 `bullet_module_id` + `bullet_module_locked = true`，读档只还原不掷骰。

## 唯一真源

`WeaponBulletDrop` 新增：

```text
MANUAL_SWAP_ENABLED = false
MANUAL_SWAP_BLOCK_REASON = "弹药模块已锁定，需在枪械工坊更换"
is_manual_swap_enabled()
manual_swap_block_reason()
```

这是**渠道总闸**，与 `bullet_module_locked` 的身份锁分工：

- 身份锁回答「这把枪的弹种是不是它自己的一部分」；
- 渠道总闸回答「当前版本有没有手动更换这个动作」。

两者都要判，顺序先身份后渠道，所以掉落枪仍先得到「已绑定」的专属原因。

## 拦截矩阵

| 入口 | 文件 | 行为 |
|---|---|---|
| 背包左键 | `Dungeon3D._on_inventory_item_clicked` → `_reject_manual_bullet_module_swap` | 扣背包前拒绝，状态栏提示枪械工坊 |
| 背包 → 武器格事务 | `Dungeon3D._install_bullet_module_from_inventory` | 再次判总闸，防止其它调用方绕过 |
| 局内快捷装配 | `Dungeon3D._install_weapon_module_from_item` | 先判运行树身份锁，再判总闸 |
| 装备面板 / 训练场事务 | `Player3D.install_bullet_module_to_weapon_slot` | 先判实例身份锁，再判总闸 |
| 拖到武器格 | `ItemSlot._can_drop_data` / `set_drag_feedback` | 总闸关闭时武器格不再接收子弹模块 |
| 拖放落点 | `InventoryUI._on_slot_drop_received` | 再判一次，不发出安装信号 |
| 训练场拖放信号 | `TrainingRange3D._on_bullet_module_install_requested` | 直接拒绝并提示 |

基地改造台（`WorkbenchPanel`）在 2026-10-18 改为炼金盘后已无换弹入口；本轮不动它，
`verify_weapon_drop_grade` 的反向门禁继续钉住「旁路不许长回来」。

## 界面

- 装备界面弹药行标题：`弹药` → `弹药（锁定）`（总闸关闭时）。
- 弹药格仍显示当前模块图标与名称，仍 `drag_disabled = true`；不隐藏 —— 玩家必须看得见当前弹种。
- 子弹模块悬浮卡：删掉「左键装配 / 拖到主/副武器格」，改为
  「当前版本不能从背包直接装到枪上 / 需在枪械工坊通过特殊流程更换（待开放）」。
- 武器悬浮卡：所有枪的弹药模块行追加「需枪械工坊更换」；掉落枪额外保留「已绑定」。
- 拒绝文案统一含「枪械工坊」，掉落枪额外含「绑定」。

## 物品流转不受影响

子弹模块物品仍可掉落、拾取、进背包、堆叠、存放、出售、进保险、带入带出。
「不能手动装配」不等于物品失效；工坊流程开放前它们只是待改造材料。

## 验收

改判据：`verify_bullet_module_equipment_flow`（文件名不变）

```text
BULLET_MODULE_LOCK_OK: manual swap locked / items not consumed / display marks lock / drop roll kept
```

覆盖：

1. 背包左键：弹种不变、模块数量不减、状态栏含「枪械工坊」。
2. 拖 `weapon_0` / `weapon_1`：弹种不变、模块数量不减、当前武器不切换。
3. 武器格 `_can_drop_data`：拒绝子弹模块；仍接受整枪；仍拒绝瞄具。
4. 悬浮卡含「枪械工坊」，不含「左键」「拖到主/副武器格」「丢弃到地面」。
5. 直接调用 `Player3D.install_bullet_module_to_weapon_slot`：拒绝且原因含「枪械工坊」。
6. 装备界面：两把武器都显示模块名，标题含「锁定」，弹药格只读。
7. 掉落枪：仍有合法随机弹种、身份锁为 true；拒绝原因先含「绑定」再含「枪械工坊」。
8. 源码门禁：`Player3D / Dungeon3D / InventoryUI / ItemSlot / TrainingRange3D` 均含
   `is_manual_swap_enabled`；`RewardService` 仍含 `WeaponBulletDrop.roll`。

实跑结果：

| 用例 | 结果 |
|---|---|
| `verify_bullet_module_equipment_flow` | `BULLET_MODULE_LOCK_OK`，exit 0 |
| `verify_weapon_drop_grade` | `WEAPON_DROP_GRADE_OK`，exit 0 |
| `verify_weapon_attachment_inventory_flow` | `WEAPON_ATTACHMENT_INVENTORY_FLOW_OK`，exit 0 |
| `verify_starting_weapon_contract` | `STARTING_WEAPON_CONTRACT_OK`，exit 0 |
| `verify_training_range_equipment_ui` | `TRAINING_RANGE_EQUIPMENT_UI_OK`，exit 0 |
| `tools/probe_bullet_lock` | `PROBE_BULLET_LOCK_DONE OK`，exit 0 |

`probe_bullet_lock` 的反向对照已改：非掉落霰弹枪不再「换弹成功」，而是「同样拒绝且原因含枪械工坊」。

## 文档与账本

- [04 战斗与局内成长 §22.14](../04_技术施工_战斗与局内成长.md)：新增 2026-10-19 口径变更、
  四条手动入口矩阵、界面/物品/工坊边界与验收。
- [07.1 枪械工坊](../07.1_玩法系统_枪械工坊.md)：工坊成为唯一合法更换渠道（未实现），
  新增待开发项。
- [07.2 武器改造台](../07.2_玩法系统_武器改造台.md)、[07.3 合成目录](../07.3_玩法系统_合成目录与兴趣曲线.md)：
  保留 `bullet_module_locked = false` 的数据口径，但删除「可自由换弹」的旧描述。
- [11.1 独立训练场](../11.1_测试功能_独立训练场.md)：军械库弹药选择标注为测试专用的整枪重装；
  背包换弹同样关闭。
- 内容数据库《字段字典》：更新 `bullet_module_locked` 验证规则，新增 `bullet_module_swap_channel`。
- 武器账本《背包物品调用索引》：8 个子弹模块的「使用/装配入口」指向
  `Dungeon3D._reject_manual_bullet_module_swap`，不再指向已关闭的安装入口。

## 未做 / 待裁决

- **枪械工坊更换流程未实现**。至少需要先定：设施/界面前提、材料或货币成本、旧模块去向、
  失败回滚、存档落盘与幂等。
- 工坊流程必须是独立命令，**不得**通过把 `MANUAL_SWAP_ENABLED` 翻成 true 来复用已关闭的
  四条手动入口。
- 子弹模块在工坊开放前没有消耗出口，掉落池占比是否需要调整属于平衡问题，本轮不擅自改权重。

## 存档兼容

- 不新增必需字段，旧存档照常读取。
- `bullet_module_locked` 语义不变；非掉落枪仍为 false。
- 读档不会重新掷弹种：`WeaponInstance.from_item` 只还原 `bullet_module_id` / 快照。
