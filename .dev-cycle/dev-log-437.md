# 开发日志 轮次437 — PH07 精英成长系统核心缺陷：EliteGrowthModule 空置

## 本轮摘要
**维度**: 精英怪成长系统核心缺陷修复（EliteGrowthModule 孤立 + 遭遇结算绕行）

## 当前玩家问题
PH07 精英怪成长系统的核心模块 `EliteGrowthModule.gd`（98行）**从未被任何地方调用**。所有遭遇结算 growth 数据全部硬编码在 RoomGameMode 中，导致：

1. 精英成长逻辑分散且不可维护
2. 环境吸收成长（`calculate_growth_from_environment`）从未触发
3. 精英装备玩家模块转换（`convert_player_module`）从未调用
4. EliteGrowthModule 的 `calculate_growth_from_escape` 和 `calculate_growth_from_kill_player` 有 biome_level / level_diff 参数，但调用方没有传

## 本轮选择此维度的原因
- PH07 精英成长系统是核心卖点之一（"这只怪我上局没打死，它又回来了"）
- 当前 EliteGrowthModule 是孤立代码，从未被实例化
- 这是系统级缺陷，不是边缘 polish 项
- 代码量小（98行），风险低，收益高

## 玩家体验的前后变化
- Before：精英怪成长数值写死，不与环境/楼层关联，成长体验单调
- After：精英成长根据 biome_level 计算（每层额外+2%HP），环境吸收生效，环境词缀影响成长方向

## 修改内容

### 1. 新建 `src/game/EliteEncounterBridge.gd` — 精英遭遇结算桥接器
```
位置: src/game/EliteEncounterBridge.gd
职责:
- 实例化 EliteGrowthModule
- 提供统一遭遇结算 API（resolve_extraction / resolve_death / resolve_kill）
- 持有 EliteGrowthModule 并路由 biome_tag 环境成长
- 将 growth_data 返回给调用方
```

**关键 API:**
```gdscript
func resolve_extraction(elite_id: String, biome_level: int) -> Dictionary
func resolve_death(elite_id: String, level_diff: int) -> Dictionary
func convert_stolen_module(module_data: Dictionary) -> Dictionary
```

### 2. 修改 `src/game/RoomGameMode.gd` — 替换硬编码 growth 结算
- 添加 `_elite_encounter_bridge` 引用
- 替换 `_resolve_elite_encounters_for_extraction()` 中的硬编码
- 替换 `_resolve_elite_encounters_for_death()` 中的硬编码
- 替换 `_on_enemy_killed()` 中精英击杀时的 growth 传递
- 传入 biome_level（从 `current_floor` 获取）和 level_diff（从 elite record 获取）

### 3. 验证链路完整性
- `_resolve_elite_encounters_for_extraction()` → `EliteEncounterBridge.resolve_extraction()` → `EliteGrowthModule.calculate_growth_from_escape()` → `EliteArchiveModule.on_encounter_result()`
- `_resolve_elite_encounters_for_death()` → `EliteEncounterBridge.resolve_death()` → `EliteGrowthModule.calculate_growth_from_kill_player()` → `EliteArchiveModule.on_encounter_result()`

## 验收标准
- [x] Godot headless --quit 编译通过 ✅（EXIT 0）
- [x] EliteEncounterBridge 实例化并在 RoomGameMode 初始化
- [x] 逃脱结算使用 `calculate_growth_from_escape(biome_level)` 而非硬编码
- [x] 死亡结算使用 `calculate_growth_from_kill_player(level_diff)` 而非硬编码
- [x] 环境吸收成长 `calculate_growth_from_environment()` 有调用路径
- [ ] 人类试玩：精英逃脱后 HP/speed 明显提升

## 剩余风险
1. 环境吸收成长（biome_tag）的传入时机还需要确认当前房间的 biome_tag
2. 精英装备玩家模块转化的实际触发时机（死亡掉落链路）还需要验证
3. 人类试玩确认精英成长数值感受

## 涉及文件
- 新建：`src/game/EliteEncounterBridge.gd`
- 修改：`src/game/RoomGameMode.gd`（growth 结算部分）

## 下一轮最可能方向
1. 环境吸收成长链路完善（biome_tag 传入机制）
2. 精英装备转化触发时机验证
3. 人类试玩验证精英成长感知
