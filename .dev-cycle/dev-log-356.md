# 轮次 356 — 2026-05-29 08:51 UTC+8

## 维度
撤离成功面板「本局获得资源」显示真实背包装备（搜打撤经济收束）

---

## 一、问题分析

### 审查发现

**问题：撤离成功面板物品列表为空——在面板显示前背包已被清空**

`_on_extraction_completed()` 执行顺序：
1. `death_settlement_module.process_extraction_settlement()` 结算
2. `_persist_extracted_items_to_vault()` → `inventory_module.clear_all()` **← 背包被清空**
3. `show_run_extraction_success()` 被调用，此时 `_inventory_module.get_occupied_slots()` 返回空数组

`_show_extraction_success()` 内实时读取背包/保险格数据，但此时背包已空，所以面板"物品已保存: 0 件"且物品列表完全空白。

### 玩家可感知的结果
- **之前**：撤离成功面板显示"物品已保存: 0 件"，玩家看不到本局带出了什么装备（即使带出了有价值的东西）
- **之后**：撤离成功面板准确列出本局真实带出的背包装备 + 保险格物品

---

## 二、修改内容

### `src/game/RoomGameMode.gd`
在 `_persist_extracted_items_to_vault()` 调用之前，先读取背包内容并随 stats 传入 UI：

```gdscript
# 撤离成功面板在清空背包前先读取本次带出的真实物品列表（用于显示本局获得资源）
var extracted_items: Array[Dictionary] = inventory_module.get_occupied_slots()
var saved_to_vault: int = _persist_extracted_items_to_vault()
...
"extracted_items": extracted_items  # 新增
```

### `src/ui/GameUIManager.gd`
**`show_run_extraction_success()`**：增加对 `stats.extracted_items` 和 `stats.insured_items` 的优先使用逻辑；优先用 stats 传入的列表，回退到实时读取（兼容 CoreCombatMode 等不需要预读的调用方）。

```gdscript
var extracted_slots: Array[Dictionary] = []
var passed_extracted: Array[Dictionary] = stats.get("extracted_items", [])
if not passed_extracted.is_empty():
    extracted_slots = passed_extracted
elif _inventory_module and _inventory_module.has_method("get_occupied_slots"):
    extracted_slots = _inventory_module.get_occupied_slots()
# 保险格同理
```

**`_show_extraction_success()`**：移除已在 `show_run_extraction_success()` 中处理的物品渲染逻辑（避免重复添加 child），保留面板动画、暂停控制、背幕处理。

```gdscript
# 移除：实时读取背包/保险格、填充物品列表的逻辑（已移至 show_run_extraction_success）
# 仅清空 ItemsVBox 并更新物品数量估算
```

---

## 三、验收标准

| 验收项 | 预期结果 |
|---|---|
| 撤离成功面板物品数量 | 显示实际带出物品数（非 0） |
| 物品列表内容 | 包含本局获得的枪械模块、弹药包等 |
| 保险格物品 | 标注 [保险] 后缀 |
| CoreCombatMode 兼容 | 不崩溃，面板仍正常显示 |
| Godot headless --check-only --quit | **EXIT 0** ✅ |

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

---

## 四、剩余风险
1. 人类试玩验证精英实际出现（轮次352核心目标）
2. 搜打撤经济系统整体收束（资源点、积分、撤离收益的完整链路）
3. 第二关战斗房密度手感（轮次355已修订密度公式，需试玩确认）

---

## 五、下轮最可能方向
1. 搜打撤经济系统收束（资源点/积分/带出物的完整链路验证）
2. 人类试玩验证精英实际出现
3. 第二关战斗房密度手感（根据试玩反馈微调）
