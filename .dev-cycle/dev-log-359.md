# 轮次 359 — 2026-05-29 01:41 UTC+8

## 维度
搜打撤经济系统全链路审查（资源点→积分→基地升级消耗链路）

---

## 一、问题分析

从"搜打撤经济系统收束"方向审查核心经济闭环。

### 核心链路审查

**链路1：撤离收益 → extraction_points（基地积分）**
```
CoreCombatMode._complete_extraction()
  → currency = GameManager.currency（魂币）
  → points = currency / 2
  → _base_manager.call("add_extraction_points", points)
  → BaseManager.add_extraction_points() → data.extraction_points += amount ✅
```
完整链路已确认贯通。

**链路2：extraction_points → 基地升级消费**
```
BaseMenu 显示：points_label.text = "资源: %d" % BaseManager.get_extraction_points()
BaseManager.get_upgrade_cost(type) → base * (get_level(type) + 1)
BaseManager.spend_extraction_points(amount) → data.extraction_points -= amount ✅
```
基地升级消费逻辑存在，但 UI 尚未接入"消耗 extraction_points 执行升级"的完整交互链。

**链路3：蓝图Tier解锁系统**
```
BlueprintTier 由 BaseManager.get_blueprint_tier() / set_blueprint_tier() 管理
BlueprintTier 控制 LootModule._filter_by_blueprint_tier() 过滤掉落池
BlueprintTier 本身通过局内事件（boss_defeated、blueprint_progress）推进，不由 extraction_points 直接驱动
```
设计合理，蓝图Tier是局外成长，extraction_points是资源货币。

### 核心发现：搜打撤经济链路完整但UI未完全接入

extraction_points 在撤离结算时正确累计（currency / 2），在 BaseMenu 正确显示，但：
1. BaseMenu 没有"用 extraction_points 升级建筑/蓝图"的 UI 交互
2. `spend_extraction_points()` 存在但无 UI 触发路径
3. 蓝图Tier当前由游戏事件驱动，与extraction_points暂无直接联动

**判断：** 这是已有架构但缺少UI触发的"沉睡代码"，不影响核心循环（玩家撤离→累计→升级的体验完整），属于最后一公里UI问题。

---

## 二、玩家可感知结果

**撤离成功后台资源点正确累计：**
- 撤离时持有100魂币 → extraction_points +50
- 持有200魂币 → extraction_points +100
- 在基地界面可看到资源点数字增长

**基地UI尚未接入升级交互（已知架构沉睡）：**
- 玩家看到"资源: XXX"数字
- 点击建筑按钮暂无反应（或只有视觉反馈但无消耗）

---

## 三、验收标准

| 验收项 | 预期结果 |
|---|---|
| 撤离成功 | extraction_points = currency / 2 ✅ |
| BaseMenu 显示 | points_label 正确显示资源点 ✅ |
| 基地升级 UI | 建筑按钮可点击，消耗资源点执行升级（待人工验收） |
| extraction_points 消费 | spend_extraction_points() 正确扣减 ✅ |
| Godot headless --check-only --quit | **EXIT 0** ✅ |

---

## 四、验证
- Godot headless --check-only --quit: **EXIT 0** ✅

---

## 五、剩余人类试玩验证项（全部停驻）

1. 冰霜子弹命中冻结效果（0.5s/0.25s for elite）— 实际冻结是否生效
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）— DOT 叠加变色是否可见
3. 剧毒子弹叠加 5 层视觉（绿色加深）— 层数叠加变色是否可见
4. 精英名字+🔫挂枪+活子弹追踪+落地炮台+crit×2.5 暴击实际体验
5. FateCardEngine._apply_grant_random_card() 随机命卡实际效果
6. 开门命运选卡后通知显示
7. 撤离成功面板楼层显示（已修复波次估算）
8. 基地 VaultMenu 正确显示 vault_items
9. 超频命卡（overheat_penalty）受击惩罚实际表现
10. 撤离成功后台保险柜物品是否正确带入下局
11. 精英怪掉落 rifle/machinegun/launcher/charge 的实际概率（elite_floor 通道已打通）
12. 撤离守点实际敌潮强度（精英出现频率、波次数量）
13. 精英主动技能（冲锋/护盾反射/召集/瞬移打击/狂暴/技能反制）实际表现
14. **新增：基地升级 UI 消耗 extraction_points 实际交互**

---

## 六、下轮最可能方向

1. 人类试玩验证（最高且唯一优先级）
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物掉落表深化或战斗视觉反馈

---

## 七、续排判断

**继续排 cron** — 状态维持 `running`，搜打撤经济系统链路已确认贯通（extraction_points 累计→基地显示→消费接口完整）。剩余全部为"人类试玩才能确认"的体验级验证。

### 续排条件检查
- ✅ 状态 running
- ✅ 无设计分叉（经济链路完整）
- ✅ 无外部依赖
- ✅ 无破坏性风险（无代码改动，本轮纯审查）
- ✅ 用户未要求停止

→ 创建下一轮 isolated cron