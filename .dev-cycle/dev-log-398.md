# 轮次 398（2026-05-30 12:00 UTC+8）

## 维度选择
**PH06 文档补全 — `FLOOR_SCALING`（第二关强度曲线）长期未录入文档**

## 核心问题
从核心玩法"第二关怪物强度曲线"链路审查：代码级事实 `FLOOR_SCALING`（`MonsterInjector.gd` 40-46行）长期存在于代码中，但 PH06 文档自 v3 以来从未录入。第二关 `hp_mult: 1.4 / damage_mult: 1.2 / loot_mult: 1.3` 这个核心数值在文档中完全空白。

**影响**：设计真相失真。当其他人通过 PH06 了解游戏怪物系统时，无法知道第二关怪物实际变强了多少。

## 解决方案
在 PH06 文档开头新增"🏔️ 楼层强度曲线（Floor Scaling）"章节：
1. 完整录入 `FLOOR_SCALING` 字典（1-5层每层 HP/Damage/Loot 倍率）
2. 明确注明两个生效位置：`MonsterInjector._generate_basic_enemy()` 和 `EliteSpawnDirector._build_elite_spawn_data()`
3. 提供第二关数值感受示例（基础怪 HP 25×1.4=35，Damage 5×1.2=6）
4. 修正精英专属主动技能注入链路（EliteSpawnDirector → RoomWaveSpawner.call_deferred → EnemyBase._inject_elite_active_skills）
5. 版本从 v3 递增至 v4

## 修改内容

### `docs/PH06_怪物系统.md`
- 文档版本 v3 → v4
- 开头新增"🏔️ 楼层强度曲线（Floor Scaling）"章节（表格 + 生效位置 + 第二关数值感受）
- 修正精英主动技能注入链路描述（EliteSpawnDirector → RoomWaveSpawner.call_deferred → EnemyBase）

## 玩家可感知的变化
无直接玩家变化（文档层）。但设计真相对齐后，后续迭代决策更可靠。

## 验收标准
- [x] Godot headless --script-check --quit 编译通过 ✅（EXIT 0，输出干净）
- [x] PH06 文档 v4 版本确认
- [ ] 人类试玩：第二关怪物 HP/Damage 是否明显比第一关强（HP +40%，Damage +20%）
- [ ] 人类试玩：精英怪冲锋/护盾反射/召集令等主动技能是否可感知

## 系统完整度确认
本轮补全后，PH06 文档与代码事实的对齐度：
| 内容 | 状态 |
|---|---|
| `FLOOR_SCALING` 字典 | ✅ 本轮录入 |
| 第二关数值 | ✅ 本轮录入 |
| 普通怪物 HP/Damage 缩放 | ✅ 本轮注明 |
| 精英怪物 HP/Damage 缩放 | ✅ 本轮注明 |
| 精英专属主动技能注入链路 | ✅ 本轮修正 |
| tier 计算规则 | ✅ 文档已有 |
| 6种精英专属主动技能 | ✅ 文档已有 |

## 剩余风险
1. 人类试玩验证 — 第二关强度曲线感受
2. 人类试玩验证 — 精英怪主动技能实际表现
3. 精英怪装备挂载（`挂载装备（用于视觉渲染）`）在 spawn_data 中的落地

## 续排判断
**继续排 cron** — 状态维持 `running`。文档层已对齐，核心系统代码无已知断点。最高且唯一优先级：**人类试玩验证**。

## 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈深化
