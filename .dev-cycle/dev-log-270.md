# 开发日志 — 2026-05-27

## 轮次 270 — 2026-05-27 07:56 UTC+8

### 维度
PH10基地养成：BaseMenu 显示资源点数（extraction_points）

### 问题
基地主界面 StatsPanel 显示"总局数/成功撤离/总击杀"，但缺少资源点数显示。extraction_points 是局后持久化资源（撤离后积累，用于枪械工坊蓝图解锁），玩家无法在基地直接看到当前资源余额，只能进了游戏才能在 WorkshopMenu 中看到。

### 玩家可感知结果
- 基地主界面 StatsPanel 新增一行"资源: X"，实时显示当前 extraction_points
- 玩家在基地即可评估蓝图解锁进度（当前资源够不够解锁 Tier1/Tier2）

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/ui/BaseMenu.gd` | 新增 `@onready var points_label`；`_refresh_stats()` 新增 points_label 更新逻辑 |
| `scenes/BaseMenu.tscn` | StatsPanel/VBox 新增 `PointsLabel` 节点 |

### 验证
- Godot --headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- 资源点数达到较大数值时的显示格式（千分位分隔符）尚未处理
- BaseMenu 初始加载时 BaseManager.data 可能尚未就绪（但 _refresh_stats 已有 null 检查）

### 下轮最可能方向
1. **PH12门视觉深化**：门框光效/开启动画/门类型颜色区分（当前门只有ColorRect标记）
2. **PH07精英怪装备偷取实际验证**：死亡掉落→精英捡走→下一局名字变化
3. **基地资源获取提示**：在撤离成功界面显示本局获得资源点数（而非只在控制台可见）