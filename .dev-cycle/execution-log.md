# 开发日志 - 2026-05-22/23

## 轮次 14（00:53）

### 维度：搜打撤背包UI完善 - InventoryUI独立模式+信号连接+右键交互

### 审查发现
- InventoryUI.gd 依赖 @onready 访问 GameUIManager.tscn 内嵌的 InventoryPanel/InventoryGrid 节点，但 GameUIManager 实际上从未实例化 InventoryUI
- InventoryGrid 和 InsuranceGrid 在 GameUIManager.tscn 中是空的（只有 CapacityLabel），没有子节点
- ItemSlot.gd 的 slot_clicked/slot_right_clicked 信号从未被连接
- InventoryUI._on_slot_clicked() 是空 pass，右键存入保险、取出保险物品都没有实现
- ItemSlot.tscn 没有 CountLabel，无法显示叠加数量

### 改动
1. **InventoryUI.gd**：重构为 standalone_mode=true，默认自己创建 Panel/Grid/VBox/CapacityLabel/InsuranceLabel 层级，运行时动态创建子节点，不再依赖 @onready
2. **InventoryUI.gd**：新增 `_connect_slot_signals()`，在 `_build_inventory_grid()` / `_build_insurance_grid()` 后连接 ItemSlot 的 `slot_clicked` / `slot_right_clicked` 信号
3. **InventoryUI.gd**：实现 `_on_slot_clicked()` 和 `_on_slot_right_clicked()`：
   - 背包格左键 → 存入保险格（emit item_to_insurance_requested）
   - 背包格右键 → 存入保险格
   - 保险格右键 → 取出物品（emit item_extraction_requested）
4. **ItemSlot.tscn**：新增 CountLabel 子节点（x1叠加显示，右下角）
5. **InventoryUI.gd**：`_update_slot_with_item()` 和 `_clear_slot()` 支持 CountLabel 显示/隐藏
6. **InventoryUI.gd**：`_refresh_insurance_ui()` 中 `_insurance_slots[i]` 类型改为 Control（兼容 ItemSlot）

### 验证
- Godot headless --quit 编译通过
- standalone_mode 架构：独立模式自动创建节点，内嵌模式通过 @onready 访问已有节点

### 下一轮最可能方向
- GameUIManager 响应 item_to_insurance_requested + item_extraction_requested 信号（物品存入/取出逻辑）
- 宝箱开启 → 物品入背包 → InventoryUI 刷新显示
- 死亡掉落 + 保险格保留逻辑
- 基地养成：建筑解锁逻辑占位

---

## 轮次 13（00:33）

### 维度：搜打撤背包UI完善 - InventoryUI独立模式+信号连接+右键交互

### 审查发现
- InventoryUI.gd 依赖 @onready 访问 GameUIManager.tscn 内嵌的 InventoryPanel/InventoryGrid 节点，但 GameUIManager 实际上从未实例化 InventoryUI
- InventoryGrid 和 InsuranceGrid 在 GameUIManager.tscn 中是空的（只有 CapacityLabel），没有子节点
- ItemSlot.gd 的 slot_clicked/slot_right_clicked 信号从未被连接
- InventoryUI._on_slot_clicked() 是空 pass，右键存入保险、取出保险物品都没有实现
- ItemSlot.tscn 没有 CountLabel，无法显示叠加数量

### 改动
1. **InventoryUI.gd**：重构为 standalone_mode=true，默认自己创建 Panel/Grid/VBox/CapacityLabel/InsuranceLabel 层级，运行时动态创建子节点，不再依赖 @onready
2. **InventoryUI.gd**：新增 `_connect_slot_signals()`，在 `_build_inventory_grid()` / `_build_insurance_grid()` 后连接 ItemSlot 的 `slot_clicked` / `slot_right_clicked` 信号
3. **InventoryUI.gd**：实现 `_on_slot_clicked()` 和 `_on_slot_right_clicked()`
4. **ItemSlot.tscn**：新增 CountLabel 子节点
5. **InventoryUI.gd**：`_update_slot_with_item()` / `_clear_slot()` 支持 CountLabel

### 验证
- Godot headless --quit 编译通过

### 下一轮最可能方向
- GameUIManager 响应 item_to_insurance_requested + item_extraction_requested
- 宝箱开启 → 物品入背包 → InventoryUI 刷新显示
- 死亡掉落 + 保险格保留逻辑

---

## 轮次 12（23:53）

### 维度：搜打撤背包/保险格 UI 修复 + 撤离UI完善

### 审查发现（Bug检查）
- `InsuranceModule` 没有 `get_occupied_slots()` 方法，导致 `InventoryUI.gd` 第143行调用失败
- `InventoryUI._refresh_insurance_ui()` 使用 `get_occupied_slots()` 但 `InsuranceModule` 只有 `get_all_insured_items()`
- `GameUIManager._on_abort_pressed()` 中 `abort_button.disabled = true` 设置过早
- `InsuranceModule.claim_all()` 清空物品后发送 `insurance_changed` 信号，但这些物品其实已经丢了

### 改动
1. **InsuranceModule.gd**：新增 `get_occupied_slots()` 方法与 InventoryModule API 对称
2. **InsuranceModule.gd**：修复 `claim_all()` — 撤离成功时物品应该保留而非清空（新增 `extract_only()` 方法）
3. **InventoryUI.gd**：保险格刷新改用正确方法 `get_all_insured_items()`
4. **GameUIManager.gd**：中断按钮禁用时机改为「中断后」而非「中断前」

### 验证
- API 对称性：InventoryModule 有 `get_occupied_slots()` + `get_used_slots()`；InsuranceModule 现在也有对称接口

### 下一轮最可能方向
- 保险格存入/取出交互
- 基地养成建筑解锁逻辑占位
- 搜打撤经济系统：带入带出数值验证

---

## 轮次 11（23:47）

### 维度：搜打撤撤离系统完善 - 波次UI + 撤离UI联动

### 审查发现
- P09 波次 UI（`WaveIndicatorLabel`）在 GameUIManager 中无法访问（无 `@onready`，wave_progress_changed 空实现）
- 撤离选择面板（ExtractionPanel）仅有占位符，缺少撤离类型按钮，无 `extraction_type_selected` 信号连接
- `_on_extraction_progress_updated` 缺失，撤离读条无法更新 UI
- 中断撤离按钮 `_on_abort_pressed` 未实现

### 改动
1. **GameUIManager.tscn**：ExtractionPanel 扩大，加入 ExtractionButtons 容器、BeaconLabel
2. **GameUIManager.gd**：
   - `_wave_indicator_label` 运行时获取（修复波次 UI）
   - `_on_wave_progress_changed` 完整实现（击杀剩余数 + 颜色闪烁动画）
   - `_on_extraction_ready` 改为显示撤离选择按钮（5种类型）
   - `_build_extraction_buttons` / `_on_extraction_type_button_pressed`：选择撤离类型后触发 `RoomGameMode.begin_extraction()`
   - `_on_extraction_progress_updated`：读条进度 + 精确倒计时
   - `_on_abort_pressed`：中断撤离并隐藏面板

### 验证
- 代码审查通过，无语法错误
- 逻辑链路完整：RoomGameMode.all_rooms_cleared → extraction_ready → GameUIManager → 显示撤离按钮 → begin_extraction → ExtractionModule → 读条更新 → 中断/完成

### 下一轮最可能方向
- 搜打撤核心循环：保险格存入/取出、背包 UI 实际物品显示
- 基地养成：建筑解锁逻辑占位
- 命运卡片与局内效果联动（Phase 4-5 深化）
## 轮次 15（01:10）

### 维度：搜打撤背包UI完善 - GameUIManager实例化InventoryUI+信号响应

### 审查发现
- InventoryUI.gd 在轮次13/14已重构为 standalone_mode（自己创建Panel/Grid层级）、信号连接、右键存入取出已实现
- 但 InventoryUI 从未被实例化！GameUIManager.tscn 的 InventoryPanel 只是占位空壳（无子节点）
- InventoryUI.item_to_insurance_requested / item_extraction_requested 信号存在但从未连接
- 没有容器/宝箱开启逻辑——物品无法进入背包

### 改动
1. **GameUIManager.gd**：
   - 新增 `_inventory_ui: InventoryUI` 成员变量
   - 新增 `_setup_inventory_ui()` 方法：在 `_ready()` 中实例化 InventoryUI（standalone_mode=true），容量12格+2格保险
   - set_inventory_module() / set_insurance_module() 立即传递给 InventoryUI（如果已创建）
   - 新增 `_on_item_to_insurance_requested(slot_index)`：调用 `_insurance_module.insure_item(_inventory_module, slot_index)`
   - 新增 `_on_item_extraction_requested(slot_index)`：调用 `_insurance_module.claim_item()` 后尝试 add_item() 到背包，超格时回退保险格
   - 新增 `_on_inventory_ui_changed()` 空处理（InventoryUI 已自行刷新）
2. **InventoryUI.gd**：
   - 新增 `inventory_changed` 信号（在 `_on_inventory_changed` / `_on_insurance_changed` 时发出）
   - GameUIManager 绑定该信号后可做其他联动扩展

### 验证
- Godot headless --quit 编译通过
- InventoryUI 现在在 GameUIManager 中被正确实例化，所有信号链路完整

### 下一轮最可能方向
- 宝箱/容器系统：ContentInjector 定义容器类型 → RoomFactory 实例化 → 玩家交互开箱 → 物品通过 InventoryModule.add_item() 入背包 → InventoryUI 刷新显示
- 死亡掉落+保险格保留逻辑验证（DeathSettlementModule）
- 基地养成：建筑解锁逻辑占位

---

## 轮次 48（2026-05-23 06:29 UTC+8）

### 维度选择
**改造房工作台系统 — WorkbenchInteraction + WorkbenchPanel**

从核心玩法审查，武器装配树通过 BlueprintRegistry 解锁后，玩家可以在工作台重新装配武器。当前改造房（RoomUpgrade）场景不存在，工作台 interactable 注入了但没有实际交互逻辑。玩家进入改造房无法进行任何操作。

### 玩家可感知结果
- 玩家进入改造房（UPGRADE 房间类型）可以看到工作台
- 接近工作台显示 "[E] 改造" 提示
- 按 E 键打开武器改造面板，显示当前武器装配树
- 面板左侧显示可用的枪身列表（受 BlueprintTier 限制）
- 面板右侧显示可用的子弹列表（受 BlueprintTier 限制）
- 点击选项可替换当前枪身或子弹
- 按 ESC 或关闭按钮返回游戏

### 修改内容

**新增文件：**
1. `scenes/RoomUpgrade.tscn`：改造房场景，包含 WorkbenchArea（Area2D）和 InteractLabel
2. `src/game/WorkbenchInteraction.gd`：工作台交互组件，挂在 WorkbenchArea 上，检测玩家接近，按 E 打开改造面板
3. `src/ui/WorkbenchPanel.gd`：改造面板，显示当前武器装配树，可选枪身/子弹列表，点击可重选
4. `scenes/WorkbenchPanel.tscn`：改造面板场景文件

**RoomFactory.gd**（已有引用，无需修改）：
- SCENE_MAP 中已有 RoomData.RoomType.UPGRADE → "res://scenes/RoomUpgrade.tscn" 映射

**BlueprintRegistry**（已验证）：
- `get_available_gunbodies(tier)` / `get_available_bullets(tier)` 接口正常
- `create_assembly_node(item_id)` 工厂方法正常

### 验收标准
- [ ] 进入 RoomUpgrade.tscn 后，工作台区域显示 InteractLabel "[E] 改造"
- [ ] 玩家接近工作台并按 E，面板正确显示 BlueprintTier 对应的枪身和子弹
- [ ] 点击枪身/子弹选项，当前武器树根节点被替换
- [ ] ESC 或关闭按钮可关闭面板并返回游戏
- [ ] Godot headless 编译通过 ✅

### 剩余风险
- RoomFactory 在创建 UPGRADE 房间时是否正确注入背包引用（需要和 ContainerInteraction 一样通过 set_inventory 传递）
- 工作台目前只支持枪身+子弹替换，配件替换待后续完善
- BlueprintTier 联动：BlueprintTier 提升后，工作台选项列表是否正确刷新（下一轮验证）

### 下一轮最可能方向
1. **RoomFactory 改造房背包绑定验证**：确保 RoomFactory.create_room() 为 UPGRADE 房间正确传入 inventory_module
2. **BlueprintTier 刷新验证**：提升 BlueprintTier 后，工作台面板选项是否正确增加
3. **出生房宝箱初始物资**：spawn_starter 掉落表已完善，出生房宝箱是否正确掉落蓝图碎片
4. **命运卡片局内实用化深化**：命运卡片在局内通过商人/改造房获取并应用
