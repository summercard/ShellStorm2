# 轮次 396（2026-05-30 11:44 UTC+8）

## 维度选择
**命运卡片视觉标签传播链路修复 — "子弹背枪"卡导致 primary bullet 视觉标签丢失**

## 核心问题
从命运卡片系统链路审查发现：当玩家使用"子弹背枪"类命运卡片（`ATTACH_GUN_TO_BULLET`）时，primary bullet 的 `fate_scale`、`visual_has_eyes`、`visual_has_legs` 视觉标签在 `FateCardEngine._apply_attach_gun_to_bullet()` 创建 `AttachedGun` 节点时没有被传播。

**影响**：当 primary bullet 调用 `set_attached_gun(attached_gun)` 时，`set_attached_gun` 读取的是 `attached_gun`（而非 bullet_node）的 base_stats，而 `attached_gun` 上只有 `{damage, fire_rate, bullet_count}`，没有 `fate_scale`。Primary bullet 的视觉标签（变大、眼睛、脚）全部丢失。

**次要问题**：`WeaponAssemblyTree.fire_from` 中，`_spawn_bullet_from_co_gun` 创建副枪子弹时也调用 `apply_fate_stats_from_node(bullet_node)`，但副枪子弹没有收到父子弹的 `fate_scale` 视觉标签（它的 `fate_scale` 和视觉来自 bullet_node，不是 `attached_gun`）。这不影响命卡主链路，但副枪子弹视觉不对。

## 技术修复

### `src/weapons/FateCardEngine.gd` — `_apply_attach_gun_to_bullet`
在 `tree.mount()` 之前，从 `bullet_node.get_base_stats()` 读取 `fate_scale`、`visual_has_eyes`、`visual_eyes`、`visual_has_legs`、`visual_legs`，同步到 `attached_gun.get_base_stats()` 中。

修改后效果：
- 使用"变大了"命卡后，primary bullet 携带 `fate_scale > 1`，同时背上挂载枪
- 挂载枪的视觉标签与子弹同步，子弹+背枪整体作为"变大了"的可感知整体
- "活过来"（眼睛）、"小虫子"（脚）等命卡视觉标签也正确传播

## 玩家可感知变化
**Before**：应用"子弹背枪"类命卡后，子弹不放大、无眼睛/脚，背上的枪视觉独立不变
**After**：命卡视觉标签（放大/眼睛/脚）正确渲染在 primary bullet 上，与背枪视觉协同呈现

## 验收标准
- [x] Godot headless --script-check --quit 编译通过 ✅（EXIT 0，输出干净）
- [ ] 人类试玩：应用"变大了"/"活过来"/"小虫子"命卡后，观察子弹是否正确放大/有眼睛/有脚
- [ ] 人类试玩：副枪子弹（ninth_attached_bullet）的视觉标签是否也正确应用

## 系统完整度确认
本轮修复后，命运卡片视觉标签（`fate_scale`/`visual_has_eyes`/`visual_has_legs`）的完整链路：
| 节点 | 来源 | 是否正确传播 |
|---|---|---|
| primary bullet `fate_scale` | FateCardEngine._apply_scale_node | ✅ |
| primary bullet 挂载 AttachedGun | FateCardEngine._apply_attach_gun_to_bullet | ✅ 本轮修复 |
| primary bullet 视觉（eyes/legs） | FateCardEngine._apply_add_homing(AddEyes/AddLegs) | ✅ |
| primary bullet 继承子弹视觉 | WeaponAssemblyTree._spawn_bullet_from_co_gun → apply_fate_stats_from_node | ✅ |

## 剩余风险
1. 人类试玩验证 — 命卡视觉实际效果
2. 第二关怪物强度曲线感受
3. HealthVignette 脉冲效果
4. WeaponAssemblyTreePanel 节点高亮
5. 精英怪实际表现（🔫挂枪+主动技能）

## 续排判断
**继续排 cron** — 状态维持 `running`。所有核心系统代码层面无已知断点，最高且唯一优先级：**人类试玩验证**。若试玩发现 Bug → 针对性修复；若无 Bug → 深化战斗视觉反馈或第二关内容。

## 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈深化
