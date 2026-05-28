## 轮次309 — 2026-05-28 08:21 UTC+8

### 维度选择
**VaultMenu 保险柜品质边框 UI polish（Cosmetic Polish）**

从轮次304发现的 cosmetic 问题出发：保险柜物品行（`_make_vault_item_row`）只显示名称和数量，没有品质边框颜色，无法让玩家快速区分物品稀有度。这是一个让玩家"能感到"的纵向 UI 切片。

### 问题分析
轮次304确认：
- `_complete_extraction()` 链路完整（背包→基地保险柜，保险格→基地保险柜）
- VaultMenu 渲染正确（名称+数量）
- 缺失：品质边框颜色（cosmetic polish）

其他模块参考：
- FateCardCollectionMenu、FateCardUIController、DivinationMenu、WorkbenchPanel 都用 `FateCard.rarity_color()` 给命卡渲染边框
- 命卡用 `FateCard.CardRarity` 枚举，颜色从 `FateCard.rarity_color()` 获取
- 武器/子弹/配件用固定推断颜色

### 本轮修复
**VaultMenu.gd `_make_vault_item_row()` 新增品质边框**：
- 根据 `item_dict["type"]` 推断物品类型：
  - `FateCard` → 用 `FateCard.rarity_color()` + `FateCard.CardRarity.get()` 映射 rarity 字符串
  - `Weapon/GunBody` → 金色 `#F59E0B`
  - `Bullet` → 蓝色 `#4A9EFF`
  - 其他 → 灰色 `#888888`
- 用 `StyleBoxFlat` 创建 3px 边框，圆角 4px，深色背景
- `add_theme_stylebox_override("panel", ...)` 注入到 PanelContainer

### 玩家可感知结果
保险柜界面存入的命卡/武器/子弹现在有品质边框颜色，玩家可以快速用颜色判断存入物品的稀有度。命卡（金=传说，紫=史诗，蓝=稀有，白=普通）、武器（金色边框）、子弹（蓝色边框）。

### 验收标准
- [x] Godot headless --quit-after 3 编译通过 ✅ EXIT 0
- [ ] 人类试玩：撤离成功 → 回基地 → VaultMenu 看到存入物品的彩色边框
- [ ] 人类试玩：不同稀有度（普通/稀有/史诗/传说）的命卡边框颜色正确

### 状态
**running**（轮次309完成，DemoBoss残留引用清理已收尾）

### 下轮最可能方向
1. **人类试玩验证**（最高且唯一优先级）：撤离物品保存+Boss战+命运卡片+精英怪物链路全部需要实际试玩确认
2. 精英击杀信号连接（EliteArchiveModule → ExtractionDirector）
3. Boss 战完整流程（RoomBoss.tscn + BossRoomDirector）
4. 基地 VaultMenu 取出后物品进入背包 loadout 链路审查
