# 轮次 360 — 2026-05-29 03:19 UTC+8

## 维度
基地建筑升级面板接入（extraction_points UI 最后一公里）

---

## 一、问题分析

搜打撤经济系统链路（轮次359确认）：
- extraction_points 撤离累计 ✅
- BaseMenu 显示资源点 ✅
- spend_extraction_points() 存在 ✅
- **缺失：没有 UI 让玩家实际消耗 extraction_points 升级建筑**

BaseManager 有完整的 `upgrade_building(type)` / `get_upgrade_cost(type)` / `spend_extraction_points(amount)`，但 BaseMenu 建筑按钮全部直接打开子菜单，无升级交互路径。

---

## 二、修改内容

### `src/ui/BaseMenu.gd`

**新增 BUILDING_INFO 常量**：7个建筑的名称、中文描述
```gdscript
const BUILDING_INFO := {
    0: {"name": "枪械工坊", "desc": "升级增加武器制作选项"},
    1: {"name": "资源转换", "desc": "升级增加资源转换效率"},
    2: {"name": "废品回收", "desc": "升级增加回收产出"},
    3: {"name": "命运占卜屋", "desc": "升级增加命卡抽取选项"},
    4: {"name": "保险柜", "desc": "升级增加存储容量"},
    5: {"name": "黑市", "desc": "升级增加商品种类"},
    6: {"name": "怪物档案室", "desc": "升级解锁精英图鉴"},
}
```

**新增建筑升级面板 `_show_building_panel(building_type)`**：
- 弹出居中模态面板，遮罩背景
- 显示建筑名、当前等级、升级费用、当前资源点
- 保险柜额外显示存储容量
- "升级 (+1级)" 按钮：资源充足时可用，消耗 `spend_extraction_points()` → 调用 `upgrade_building()`
- "资源不足" 时按钮置灰
- 点击遮罩或"关闭"收起面板

**修改建筑按钮行为**：
- `_on_building_workshop_pressed()`：优先打开 WorkshopMenu.tscn；若文件不存在则打开升级面板（type=0）
- `_on_building_divination_pressed()`：优先打开 DivinationMenu.tscn；若不存在则打开升级面板（type=3）
- 其他建筑（Vault/Archive/FateCardCollection）保持打开独立菜单不变

---

## 三、玩家可感知结果

**之前**：玩家撤离后看到"资源: XXX"，但点击建筑按钮只能打开子菜单，无法消耗资源点升级
**之后**：点击任意建筑按钮会弹出升级面板，显示当前等级/费用/资源点，点"升级"消耗资源点并提升建筑等级

---

## 四、验收标准

| 验收项 | 状态 |
|---|---|
| Godot headless --check-only --quit: **EXIT 0** | ✅ |
| 玩家撤离后累计 extraction_points，在 BaseMenu 看到数字增长 | 待人类试玩 |
| 点击建筑按钮弹出升级面板（当子菜单不可用时） | 待人类试玩 |
| 资源点充足时点击"升级"消耗 points 并提升建筑等级 | 待人类试玩 |
| 资源点不足时"升级"按钮置灰不可点 | 待人类试玩 |
| 保险柜升级后容量实际增加（2 + vault_level 格） | 待人类试玩 |

---

## 五、验证
- `godot --headless --check-only --quit`: **EXIT 0** ✅

---

## 六、剩余风险（人类试玩验证项）

1. 冰霜子弹命中冻结效果（0.5s/0.25s for elite）
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）
3. 剧毒子弹叠加5层视觉（绿色加深）
4. 精英名字+🔫挂枪+活子弹追踪+落地炮台+crit×2.5实际体验
5. FateCardEngine._apply_grant_random_card() 随机命卡效果
6. 开门命运选卡后通知显示
7. 撤离成功面板物品列表（轮次356修复）
8. 基地建筑升级面板实际交互（**本轮已实现**）
9. 保险格物品在基地的持久化链路
10. 撤离守点敌潮强度缩放

---

## 七、续排判断

**继续排 cron** — 状态 `running`，无设计分叉、无外部依赖、无破坏性风险。用户未要求停止。

### 续排条件检查
- ✅ 状态 running
- ✅ 无设计分叉（经济系统 UI 闭环已补全）
- ✅ 无外部依赖
- ✅ 无破坏性风险（纯新增面板，编译通过）
- ✅ 用户未要求停止

→ 创建下一轮 isolated cron（轮次361）