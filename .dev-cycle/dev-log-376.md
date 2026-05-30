## 轮次 376 — 2026-05-29 20:45 UTC+8

### 维度
WeaponController 换弹爆炸逻辑连接修复 — `weapon_reloaded` 信号从绑定 `_on_reload_finished`(空实现) 改为绑定 `_on_reload_finished_impl`（含爆炸触发）

### 问题分析
从 WeaponController.gd 代码审查中发现：

1. `_on_reload_finished()` 是空函数 `pass`（占位）
2. `_on_reload_finished_impl()` 才是真正实现，包含：
   - 播放换弹音效
   - 检测子弹节点是否有 `explode_on_reload` 标记
   - 有标记则在玩家位置触发范围爆炸
   - 爆炸对范围内敌人造成伤害
3. **Bug**：`weapon_reloaded` 信号连接的回调是 `_on_reload_finished`（空函数），而不是 `_on_reload_finished_impl`（真实逻辑）

结果：**换弹爆炸命运卡片效果**（explode_on_reload 标记的子弹）**无法被触发**，玩家无法体验这个战斗反馈机制。

### 玩家可感知的变化
- **Before**：reload 爆炸命卡存在但永不触发，爆炸特效和范围伤害不工作
- **After**：装备了 reload 爆炸子弹后，换弹时在玩家位置触发爆炸特效，对周围敌人造成基于子弹伤害的爆炸伤害

### 代码改动
**文件：** `src/weapon/WeaponController.gd`

```gdscript
# 修改前（信号连接到了空函数）
if not weapon_tree.weapon_reloaded.is_connected(_on_reload_finished):
    weapon_tree.weapon_reloaded.connect(_on_reload_finished)

# 修改后（信号连接到真实逻辑函数）
if not weapon_tree.weapon_reloaded.is_connected(_on_reload_finished_impl):
    weapon_tree.weapon_reloaded.connect(_on_reload_finished_impl)
```

同时将 `_on_reload_finished()` 的注释从 `"占位，实际实现在下方"` 改为 `"已迁移到 _on_reload_finished_impl()"`，防止未来误解。

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：装备带 `explode_on_reload` 标记的子弹，换弹时观察爆炸特效和伤害

### 爆炸特效现状（临时实现）
当前爆炸特效使用 ColorRect 模拟（橙色闪烁，0.25s淡出）。这是已知的临时实现，后续应替换为专业特效场景。临时特效不影响逻辑验证。

### 系统完整度确认
| 系统 | 落地状态 | 关键证据 |
|---|---|---|
| 搜打撤全链路 | ✅ | DemoRoomChain 8房间线性链，门交互/淡入淡出/撤离读条 |
| 命卡21×21 apply | ✅ | FateCardEngine + FateCardGameBridge + MapFateTriggers |
| 精英成长档案池 | ✅ | EliteArchiveModule + 主动技能注入 |
| Boss框架 | ✅ | BossPhaseDirector + BossSkillNode + BossRoomLogic脉冲 |
| 武器装配树 | ✅ | WeaponAssemblyTree + Panel详情弹窗 + 高亮修复 |
| Room视觉化 | ✅ | RoomTileMapInitializer(243行) + RoomTileSetBuilder(4F×14T配色) |
| 战斗反馈 | ✅ | HitEffects + ScreenShake + AudioManager + MuzzleFlash + **reload爆炸（本轮）** |
| 保险柜 | ✅ | VaultMenu + stage_vault_item_for_loadout |
| 基础怪物技能注入 | ✅ | RoomWaveSpawner._inject_base_skill() + 6×EnemyTypes注入 |
| BOSS房激活链路 | ✅ | _on_boss_spawn_triggered()调用BossActor.activate()（轮次375） |

### 剩余风险（全部为人类试玩验证项）
1. **元素子弹**（冰冻/火焰DOT/剧毒叠加）视觉反馈
2. **精英怪**（🔫挂枪+活子弹+炮台+主动技能）实际表现
3. **撤离守点敌潮强度**（精英出现频率）
4. **开门/开箱命卡效果应用**
5. **第二关怪物类型分化**（6种是否正确出现）
6. **地下室开箱产出**
7. **WeaponAssemblyTreePanel 节点高亮**（轮次371已修复递归bug）
8. **BOSS房BossActor激活**（轮次375已修复）
9. **换弹爆炸特效**（本轮修复，需人类试玩确认）

### 续排判断
**继续排 cron** — 状态维持 `running`。reload爆炸链路已修复（信号连接修正），所有系统无已知代码断点。最高且唯一优先级：**人类试玩验证**。

### 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈