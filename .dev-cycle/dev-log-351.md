## 轮次 351 — 2026-05-29 04:42 UTC+8

### 维度
Tier-1/2 配件模块 combat_floor 权重补全

### 问题分析
继续轮次349~350对 ItemRegistry.gd 的 combat_floor 全面补全工作。上轮（350）为 bp_machinegun 蓝图补全了 combat_floor，本轮审查发现 Tier-1/2 配件（attach_scope/attach_big_mag/attach_fan/attach_copy_sticker）的 floor_loot_weights 全部缺失 combat_floor_* 条目，与子弹模块和武器蓝图体系不一致。

### 代码改动
**文件：** `src/base/ItemRegistry.gd`

为以下4个配件模块新增 combat_floor 掉落权重：

| 模块 | 新增 combat_floor 条目 |
|---|---|
| attach_scope（放大镜瞄具，rare） | combat_floor_2: 1.5, combat_floor_3: 2.5 |
| attach_big_mag（肉质弹匣，uncommon） | combat_floor_1: 2.5, combat_floor_2: 3.0 |
| attach_fan（小风扇，epic） | combat_floor_3: 1.5, combat_floor_4: 2.0, combat_floor_5: 2.5 |
| attach_copy_sticker（复制贴纸，epic） | combat_floor_3: 1.0, combat_floor_4: 1.5, combat_floor_5: 2.0 |

权重设计原则：
- rarity 越高，combat_floor 覆盖关卡越高（epic 配件从第3关开始，rare 从第2关开始，uncommon 从第1关开始）
- 数值与 scavenge_floor 权重水平对齐
- 保持与小风扇/复制贴纸稀有度一致的掉落体验

### 验收标准
| 验收项 | 预期结果 |
|---|---|
| attach_scope | 拥有 combat_floor_2/3 |
| attach_big_mag | 拥有 combat_floor_1/2 |
| attach_fan | 拥有 combat_floor_3/4/5 |
| attach_copy_sticker | 拥有 combat_floor_3/4/5 |
| 第二/三关战斗房 | 可掉落放大镜瞄具、肉质弹匣 |
| 第三~五关战斗房 | 可掉落小风扇、复制贴纸 |
| Godot headless --check-only --quit | EXIT 0 ✅ |

### 验证
- Python 扫描：确认 attach_scope/attach_big_mag/attach_fan/attach_copy_sticker 均已写入 combat_floor 字段 ✅
- Godot headless --check-only --quit: **EXIT 0** ✅

### 剩余风险
1. **人类试玩验证**：进入各关卡战斗房并击杀怪物，确认配件掉落出现
2. combat_floor 权重合理性：当前数值是按 rarity 经验设定，需要人类试玩后调整相对权重
3. 其余所有风险项仍为人类试玩验证项

### 续排判断
**继续排 cron** — 状态维持 `running`。从轮次345起连续7轮将 combat_floor 覆盖到所有主要物品类型（Tier-0/1/2 子弹模块 + 武器蓝图6个 + 消耗品2个 + 配件6个），combat_floor 补全工作已基本完成。下轮可转向人类试玩验证，或第二/三关战斗房怪物密度深化，或搜打撤经济系统收束。