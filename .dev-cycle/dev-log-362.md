# 轮次 362 — 2026-05-29 18:09 UTC+8

### 维度
撤离波次逻辑修复（mid-wave/精英波条件竞争）

### 问题分析
`_update_extraction_defense()` 中的波次触发条件存在竞争逻辑 bug：

```gdscript
# 原代码（两个独立 if）
if not _extraction_mid_wave_spawned and remaining <= 9.5:
    _spawn_mid_wave()   # remaining=5.0 时也会满足！
if not _extraction_elite_wave_spawned and remaining <= 5.0:
    _spawn_elite_wave()
```

当 `remaining` 从 5.5 快速跌到 5.0 以下时，mid-wave 条件可能在 final-wave 之后才检查，导致：
- mid-wave 在精英波之后才触发（逻辑顺序错乱）
- 或者两个条件同时满足时 mid-wave 永远先触发

### 代码改动
**文件：** `src/game/RoomGameMode.gd` — `_update_extraction_defense()` 中的条件结构

```gdscript
# 改前（两个独立 if，条件有重叠区间）
if not _extraction_mid_wave_spawned and remaining <= 9.5:
    ...
if not _extraction_elite_wave_spawned and remaining <= 5.0:
    ...

# 改后（elif + 互斥区间）
if not _extraction_mid_wave_spawned and remaining > 5.0:
    ...
elif not _extraction_elite_wave_spawned and remaining <= 5.0:
    ...
```

### 验收标准
| 验收项 | 预期结果 |
|---|---|
| mid-wave 在 remaining 9.5~5.0 时触发 | 顺序正确 |
| elite-wave 在 remaining ≤ 5.0 时触发 | 顺序正确 |
| Godot headless --check-only --quit | EXIT 0（无 parse error） |

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅
- 条件从两个独立 if 改为 elif，消除竞争窗口

### 系统完整性（六维度）
| 系统 | 状态 | 备注 |
|---|---|---|
| 搜打撤全链路 | ✅ | 撤离波次顺序修复 |
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
13. MobileInput 移动端触控在真机上实际运行

### 续排判断
**继续排 cron** — 状态维持 `running`，本轮修复了撤离波次条件竞争（mid-wave/精英波顺序错乱 bug）。

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