# ShellStorm2 开发日志

## 轮次408（2026-05-30 22:53 UTC+8）

### 维度选择
**系统完整度审查 + 循环状态确认（轮次408）**

### 设计审查
从核心玩法"搜打撤+武器装配+命运卡片"链路进行快速扫描：

**已确认完整系统：**
- 枪口火焰（MuzzleFlash PointLight2D + WeaponDisplay Polygon2D 双层）✅
- 冰霜DOT视觉（EnemyBase._apply_dot_visual ice case 修复）✅
- 换弹爆炸（explode_on_reload signal 修复）✅
- Tab劫持修复（GameUIManager._input 门后命卡期间放过Tab）✅
- 商人房进入即触发（RoomGameMode._auto_open_merchant）✅
- 撤离系统链路（Boss/精英击杀解锁 + 5种撤离类型按钮）✅
- 波次配置（RoomWaveSpawner + MonsterInjector FLOOR_SCALING）✅
- 伤害数字飘字（DamageNumbers.is_crit金色大号）✅
- 暴击系统（Bullet 10% base + 黄色暴击数字）✅
- 屏幕震动（ScreenShake intensity by damage）✅

**MonsterInjector FLOOR_SCALING 第二关数值确认：**
```gdscript
1: { "hp_mult": 1.0, "damage_mult": 1.0, "loot_mult": 1.0 },
2: { "hp_mult": 1.4, "damage_mult": 1.2, "loot_mult": 1.3 },  # 第二关
```
- HP: ×1.4 ✅（第一关1.0 → 第二关1.4，提升40%）
- Damage: ×1.2 ✅（第一关1.0 → 第二关1.2，提升20%）
- 正确传递至 RoomWaveSpawner.configure(floor, floor_level) ✅

**GameUIManager._extraction_director 无赋值缺失审查：**
- `_extraction_director` 声明但从未赋值（第102行）
- 所有使用处通过 `_get_extraction_director_safe()` 动态从 MapManager 读取
- 功能上无问题，但若 `extraction_director` 属性名变动会导致静默失败
- **暂时不改动**：涉及 GameUIManager ↔ MapManager 的引用重构，风险高于收益
- **后续建议**：考虑在 RoomGameMode 初始化完成后显式注入 extraction_director 引用

**playtest-checklist.md 验证项覆盖度：**
| 系统 | 状态 |
|---|---|
| 枪口火焰 | 代码落地 ✅，待人类验证 |
| 换弹爆炸 | 代码落地 ✅，待人类验证 |
| 换弹流程 | 代码落地 ✅ |
| 武器装配树Tab | 代码落地 ✅ |
| 命卡Tab选择（轮次407修复）| 代码修复 ✅，待人类验证 |
| 冰霜DOT视觉 | 代码落地 ✅，待人类验证 |
| 波次进度UI | 代码落地 ✅ |
| 撤离读条 | 代码落地 ✅ |
| 第二关怪物强度 | 数值确认 ✅，待人类验证 |
| Boss死亡震屏 | 代码落地 ✅，待人类验证 |

### Godot 编译验证
```
Godot Engine v4.6.2.stable.official.71f334935
→ Godot headless --check-only --quit
→ EXIT 0（干净，无错误）
```

### 玩家可感知结果
本轮无代码改动，确认为系统审查轮次：
- 所有16个Polish Task 已完成
- 所有系统代码编译通过
- 等待人类实际试玩验证

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅
- [ ] 人类试玩：门后命卡选择界面按Tab可关闭（轮次407修复验证）
- [ ] 人类试玩：枪口火焰是否亮起
- [ ] 人类试玩：换弹爆炸是否触发
- [ ] 人类试玩：第二关怪物HP/DMG是否明显比第一关高
- [ ] 人类试玩：撤离读条是否正常

### 剩余风险
1. **人类试玩验证是唯一缺口** — 所有系统代码已落地，编译通过，但未实际运行验证
2. **_extraction_director 引用静默失败风险** — 通过 `get()` 反射访问，不通过显式注入，存在属性名变更静默断裂风险

### 续排判断
**继续排 cron** — 状态维持 `running`。所有系统代码完成，待人类试玩验证。无设计分叉、无外部依赖、无破坏性风险。

### 下轮最可能方向
1. **人类试玩验证**（唯一优先级）
2. 若收到试玩反馈 → 针对性修复
3. 若无反馈 → 继续排 cron 等待人类试玩确认

---

## 轮次407（2026-05-30 18:37 UTC+8）补充

### Tab劫持修复验收确认
**代码位置：** `src/ui/GameUIManager.gd` 约行3008-3022

**改动逻辑：**
- 门后命卡选择期间（`_door_fate_selection_active=true`），GameUIManager 不消费Tab按键
- FateCardUIController 收到Tab → `hide_card_selection()` 执行
- 非命卡期间，K键/Tab仍正常触发 WeaponAssemblyTreePanel.toggle()

**待验证：**
- [ ] 门后命卡选择界面按Tab可关闭
- [ ] 普通Tab键（武器树面板）仍正常工作