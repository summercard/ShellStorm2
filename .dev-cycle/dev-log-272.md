# 开发日志 — 2026-05-27

## 轮次 272 — 2026-05-27 08:06 UTC+8

### 维度
撤离成功界面显示本局获得资源点数（polish/PH10 经济系统收束）

### 问题
撤离成功面板（ExtractionSuccessPanel）的 ExtractedCountLabel 当前显示"撤离成功  波次 X  击杀 X  魂 X  积分 X"，其中"积分 X"是**当前总积分**（BaseManager.get_extraction_points()），但玩家看不到**本局获得了多少积分**。根据 PH10 经济系统设计，魂币/2=积分，但撤离面板没有告诉玩家"本局获得 +X"的增量，削弱了撤离的奖励反馈感。

### 玩家可感知结果
- 撤离成功后，ExtractionSuccessPanel 的物品列表最上方新增一行绿色显示："▶ 本局获得资源: +X"（X = 魂/2）
- 玩家明确知道这局从灵魂中兑换出了多少资源点数
- 显示最终得分和风险层级

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/game/CoreCombatMode.gd` | `_complete_extraction()` 中提取 `points` 变量前移到 currency 声明后；`show_run_extraction_success` 的 stats 字典新增 `"points": points` 键值 |
| `src/ui/GameUIManager.gd` | `show_run_extraction_success()` 的 extracted_items_vbox 段新增 points_earned 标签（绿色，"▶ 本局获得资源: +X"），原有 score/risk 标签迁移到其下方 |

### 验证
- Godot --headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- points=0 时不显示（无增量则不喧宾夺主），符合预期
- 大量物品时 ScrollContainer 滚动正常，需人类试玩确认

### 下轮最可能方向
1. **PH07精英怪档案池持久化实际验证**：数据已写入elite_archive.dat，验证eliteId跨局持久化+逃脱成长生效
2. **PH12门框三维化**：给门框加厚度感/光晕边缘
3. **精英击杀→bounty结算链路**：击杀精英怪后 currency_value 入背包或直接加魂币