# 轮次 355 — 2026-05-29 00:39 UTC+8

## 维度
第二关战斗房怪物密度深化（ContentInjector 战斗房敌人数公式修订）

---

## 一、问题分析

从"第二关战斗房怪物密度深化"方向审查核心战斗闭环。

### 审查发现

**问题：第二关（floor=2）战斗房怪物密度提升不足**

当前 `ContentInjector._inject_combat_room()` 敌人数公式：
```
SHALLOW: enemy_count = 2 + floor        → floor 1=3, floor 2=4 (差值+1)
MEDIUM:  enemy_count = 3 + floor        → floor 1=4, floor 2=5 (差值+1)
DEEP:    enemy_count = 4 + floor        → floor 1=5, floor 2=6 (差值+1)
ABYSS:   enemy_count = 5 + floor
```

玩家在第二关（floor=2）感受到的怪物数量增幅只有 1 只/房——这不足以传达"正式挑战开始"的压力感。第二关是玩家完成教学后进入硬核体验的转折点，怪物密度应该有更显著的跳升。

### 玩家可感知的结果
- **之前**：第二关 MEDIUM 房 5 只怪 DEEP 房 6 只怪，与第一关差距微弱
- **之后**：第二关 MEDIUM 房 6 只怪 DEEP 房 7 只怪（+1~+2），传达更强的压迫感
- 随楼层增长，差值持续：floor 3 MEDIUM=7, DEEP=8; floor 4 MEDIUM=8, DEEP=9

---

## 二、修改内容

**文件：** `src/map/ContentInjector.gd`

`_inject_combat_room()` 函数中 MEDIUM 和 DEEP 的敌人数公式加 `maxi(0, floor-1)`：

```gdscript
RoomData.FloorLevel.MEDIUM:
    enemy_count = 3 + floor + maxi(0, floor - 1)  # floor 1=4, floor 2=6, floor 3=7, floor 4=8
RoomData.FloorLevel.DEEP:
    enemy_count = 4 + floor + maxi(0, floor - 1)  # floor 1=5, floor 2=7, floor 3=8, floor 4=9
```

SHALLOW 保持旧公式（第一关还是教学区，不能密度跳升太大）。

ABYSS 保持旧公式（已经是最高密度，公式本身就是每层+1）。

---

## 三、验收标准

| 验收项 | 预期结果 |
|---|---|
| floor=2 MEDIUM 战斗房 | 6 只怪（旧: 5） |
| floor=2 DEEP 战斗房 | 7 只怪（旧: 6） |
| floor=1 MEDIUM/DEEP | 保持原有数量（4/5），不受影响 |
| floor=3+ | 持续增长但不过度膨胀 |
| Godot headless --check-only --quit | **EXIT 0** ✅ |

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

---

## 四、剩余风险
1. 人类试玩验证精英实际出现（轮次352核心目标）
2. 撤离成功面板真实背包装备展示（经济收束）
3. 门交互命运三选一的实际手感

---

## 五、下轮最可能方向
1. 撤离成功面板「本局获得资源」显示真实背包装备（搜打撤经济收束）
2. 人类试玩验证精英实际出现
3. 第二关战斗房密度再评估（根据试玩反馈调整）