# 开发日志 — 2026-05-28

## 轮次 274 — 2026-05-28 01:17 UTC+8

### 维度
命运卡片引擎缺失处理器补全（polish/PH04）

### 问题
FateCardEngine.gd 的 match 语句缺少 6 个已定义 EffectAction 的处理器，导致以下 6 张命运卡片虽已注册（playable_presets）但无法实际应用：

- **弹跳弹**（bounce_bullet）→ `MUTATE_TO_BOUNCE`
- **连锁闪电**（chain_lightning）→ `MUTATE_TO_CHAIN`
- **落地炮台**（turret_on_land）→ `MUTATE_TO_TURRET_ON_LAND`（与living_bullet混用同一处理器，本轮拆分）
- **弹幕模式**（barrage_copy）→ `COPY_NODE`
- **火焰/冰霜/剧毒子弹**（fuse_fire/fuse_frost/fuse_poison）→ `FUSE_DAMAGE`
- **换弹爆炸**（explode_on_reload）→ `EXPLODE_ON_RELOAD`

playable_presets 已包含全部 27 张卡，但 engine 只处理了 21 个 action handler，余下 6 个走 `_: unsupported effect action` 分支，卡片应用静默失败。

### 玩家可感知结果
- 弹跳弹：子弹在墙壁/障碍物间弹跳最多 3 次（`bounce_count`）
- 连锁闪电：命中后在敌人间跳跃最多 3 次，每次伤害递减 30%（`chain_count`/`chain_range`）
- 落地炮台：子弹落地后生成炮台，持续 8s，每 0.5s 自动射击（参数从 card.effect 读取）
- 弹幕模式：每次射击分两波，第二波延迟 0.1s，伤害缩放 60%
- 火焰/冰霜/剧毒子弹：对应 DOT、冰冻、毒层叠加效果写入 AssemblyNode stats，Bullet.gd 负责渲染
- 换弹爆炸：换弹时对 150 范围内敌人造成 80% 伤害爆炸

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/weapons/FateCardEngine.gd` | match 新增 6 个 case：`MUTATE_TO_BOUNCE`→`_apply_mutate_to_bounce`、`MUTATE_TO_CHAIN`→`_apply_mutate_to_chain`、`MUTATE_TO_TURRET_ON_LAND`→`_apply_mutate_to_turret`、`COPY_NODE`→`_apply_copy_node`、`FUSE_DAMAGE`→`_apply_fuse_damage`、`EXPLODE_ON_RELOAD`→`_apply_explode_on_reload`；`_apply_mutate_to_living` 原本混用落地炮台参数，本轮拆分为独立 `_apply_mutate_to_turret` |

### 验收
- Godot --headless --quit-after 1: EXIT 0 ✅
- 6 个新 handler 均通过 match 编译，静态类型安全
- 行为参数通过 AssemblyNode.set_base_stats 写入，Bullet.gd 可通过 get_base_stats 读取（由其他 handler 验证路径正确）

### 剩余风险
- **Bullet.gd 尚未读取并执行** bounce/chain/fuse/explode_on_reload 的运行时逻辑（写在 stats 里，待 Bullet.gd 下轮接入）；当前阶段卡片应用不报错，但效果尚未在游戏运行时体现
- `fuse_damage` 的 `damage_type` 字段依赖 Bullet.gd 的 `_on_body_entered` 判决，需配合 Bullet.gd 修改
- `explode_on_reload` 的换弹爆炸依赖 WeaponController 的 reload 信号

### 下轮最可能方向
1. **Bullet.gd 接入弹跳/连锁逻辑**：读取 bounce/chain stats，在 _process/_on_body_entered 执行弹跳碰撞和闪电跳跃
2. **Bullet.gd 接入元素融合逻辑**：读取 fuse_damage_type，执行 DOT tick/冰冻/scale poison visual
3. **WeaponController 接入换弹爆炸**：监听 reload 结束信号，触发范围爆炸