# 轮次 361 — 2026-05-29 12:04 UTC+8

### 维度
编译错误修复：MobileControls autoload 命名冲突 + 类型推断缺失

### 问题分析
上一轮（轮次360）完成 BaseMenu 建筑升级面板接入后，Godot headless 编译出现以下错误：

```
SCRIPT ERROR: Parse Error: Class "MobileControls" hides an autoload singleton.
SCRIPT ERROR: Parse Error: Cannot infer the type of "touch_pos" variable...
SCRIPT ERROR: Parse Error: Cannot infer the type of "touch_index" variable...
SCRIPT ERROR: Parse Error: Function "draw_arc()" not found in base self.
```

**根本原因：** project.godot 中 `MobileControls` 被注册为 `[autoload]` 单例，但脚本中 `class_name MobileControls` 使其成为全局类。两个命名冲突导致编译器拒绝加载该脚本。

**次要问题：** `draw_circle`/`draw_arc` 等 CanvasLayer 的 2D 渲染 API 在 Control 基类下不存在，因为原本脚本 `extends CanvasLayer` 但被注册为 autoload 后 Godot 无法正确识别 CanvasLayer 的绘图 API。

### 代码改动

**文件 1：** `project.godot` — 重命名 autoload 别名
```ini
# 改前
MobileControls="*res://src/ui/MobileControls.gd"
# 改后
MobileInput="*res://src/ui/MobileInput.gd"
```

**文件 2：** `src/ui/MobileControls.gd` → `src/ui/MobileInput.gd`（物理拆分）
1. 移除 `class_name MobileControls`（消除全局类冲突）
2. `extends CanvasLayer` → `extends Control`（CanvasLayer 已有 draw_* API，Control 也有）

**文件 3：** `src/ui/MobileInput.gd` — 显式类型标注
```gdscript
# 改前
var touch_pos := event.position
var touch_index := event.index
# 改后
var touch_pos: Vector2 = event.position
var touch_index: int = event.index
```

### 验收标准
| 验收项 | 预期结果 |
|---|---|
| Godot headless --check-only --quit | EXIT 0（无 parse error） |
| MobileInput autoload | 正常加载，不与全局类名冲突 |
| 移动端触控 | 摇杆/射击/闪避/技能按钮功能正常（需真机测试） |

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅
- 编译错误全部消除

### 系统完整性（六维度）
| 系统 | 状态 | 备注 |
|---|---|---|
| 搜打撤全链路 | ✅ | 不受影响 |
| 命卡系统 | ✅ | 不受影响 |
| 精英成长档案池 | ✅ | 不受影响 |
| Boss框架 | ✅ | 不受影响 |
| 武器装配树 | ✅ | 不受影响 |
| 元素子弹视觉 | ✅ | 不受影响 |

### 剩余人类试玩验证项（全部停驻）
1. 冰霜子弹命中冻结效果（0.5s/0.25s for elite）
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）
3. 剧毒子弹叠加 5 层视觉（绿色加深）
4. 精英名字+🔫挂枪+活子弹追踪+落地炮台+crit×2.5暴击实际体验
5. FateCardEngine._apply_grant_random_card() 随机命卡实际效果
6. 开门命运选卡后通知显示
7. 撤离成功面板楼层显示
8. 基地 VaultMenu 正确显示 vault_items
9. 超频命卡（overheat_penalty）受击惩罚实际表现
10. 撤离成功后台保险柜物品是否正确带入下局
11. 精英怪掉落 rifle/machinegun/launcher/charge 的实际概率
12. 撤离守点实际敌潮强度（精英出现频率、波次数量）
13. **新增：MobileInput 移动端触控在真机上实际运行**

### 续排判断
**继续排 cron** — 状态维持 `running`，本轮修复了编译错误（MobileControls autoload 命名冲突 + 类型推断缺失）。

### 续排条件检查
- ✅ 状态 running
- ✅ 无设计分叉
- ✅ 无外部依赖
- ✅ 无破坏性风险
- ✅ 用户未要求停止

→ 创建下一轮 isolated cron

### 下轮最可能方向
1. 人类试玩验证（最高且唯一优先级）
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈