## 轮次 353 — 2026-05-29 08:26 UTC+8

### 维度
撤离成功面板「本局获得资源」显示空白修复

### 问题分析
撤离成功面板（show_run_extraction_success）里「本局获得资源: +N」显示空白。审查代码发现：

- RoomGameMode._on_extraction_completed 传递的是 `points_earned`
- 但 GameUIManager.show_run_extraction_success 读取的是 `stats.get("points", 0)` — key 不匹配

key 错位导致读不到值，整行 Label 不创建。上一轮次352的 notes 里已经记录了这个 bug，但代码修复时 key 填错了。

### 代码改动

**文件：** `src/ui/GameUIManager.gd`
- 第1787行：`stats.get("points", 0)` → `stats.get("points_earned", 0)`

### 验收标准
| 验收项 | 预期结果 |
|---|---|
| 撤离成功后面板 | 显示「▶ 本局获得资源: +N」（N为本局挣得积分）|
| key 匹配 | RoomGameMode 传 `points_earned`，GameUIManager 读 `points_earned` |
| Godot headless --check-only --quit | EXIT 0 ✅ |

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

### 剩余风险
1. 人类试玩确认撤离成功面板积分显示实际有数字（非0时）
2. 上一轮次352已排，但注意这个 key 修复不是那一轮的工作——是本轮发现的新问题

### 下轮最可能方向
1. 人类试玩验证精英实际出现（轮次352核心目标）
2. 第二关战斗房怪物密度深化
3. 搜打撤经济系统收束