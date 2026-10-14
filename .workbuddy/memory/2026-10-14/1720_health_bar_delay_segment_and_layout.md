# 17:20 血条表现：延迟扣血白段 + 小怪条 ×0.80 + Boss 条上移

## 业主原话
「按照这个进行修改血条表现，还有现在的小怪血条整体缩小到80%，boss血条放在画面的在上面一些，现在还是会遮挡」
（「这个」= 抖音那条「打 Boss 时血条为什么有一截白的，过一会儿才……」的延迟扣血条机制）

## 三条需求与落地

### ① 延迟扣血白段（小怪头顶条 + Boss 屏幕条，两套都做）
公式（**只动表现层，不碰伤害判定**）：

```
H = current_hp / max_hp              # 真实比例，立即生效
L ← move_toward(L, H, Δt × 1.8)      # 白段追赶；速度唯一真源
红条宽 = H × 内宽 ;  白段 = [H×内宽, L×内宽]   # 白段画在红条右侧
```

- **只有受伤才留白**：`next_ratio >= L` 时（初始化 / 治疗 / 满血重置）立即 `L = next_ratio`，
  否则开局就会有一条假白段。判据变量 `_overhead_health_bar_initialized`。
- 速度常量只在 `Enemy3D.HEALTH_BAR_DELAY_SPEED = 1.8` 一处定义，
  `Dungeon3D.BOSS_HEALTH_BAR_DELAY_SPEED := Enemy3D.HEALTH_BAR_DELAY_SPEED` 引它 ——
  **两条白段的追赶手感必须同源**，否则同一场战斗里 Boss 条与小怪条节奏不一致。
- 白段是**同一张条纹理里的像素**：小怪条走 `_redraw_overhead_health_bar()`（先铺白段、再铺红条），
  Boss 条走**两层 ProgressBar 叠放**（下层 `BossHealthBarDelayed` 白、上层 `BossHealthBar` 红，
  同高同宽、不增加面板高度）。白段**永不写入 `current_hp`**。
- 追赶写成独立函数 `_tick_overhead_health_bar_delay(delta)` / `_tick_boss_health_bar_delay(delta)`，
  **不是为了好看**：验收要能用固定 delta 手动步进；靠 `await process_frame` 采样会随机器帧时间浮动，
  把「白段确实在缩且没越过真实血量」变成飘忽用例。

### ② 小怪条整体 ×0.80
`Enemy3D.NORMAL_HEALTH_BAR_SCALE = 0.80`，在 `_ensure_overhead_health_bar()` 里乘进 `wanted_size`。

**只缩普通小怪，Boss 与精英不缩** —— 这是本次最容易踩错的一处：
- 精英条靠 **2.05 m 宽**表达「这只不一样」（`verify_first_elite_deployment_flow` 断言 `>= 2.0`），
  乘 0.8 → 1.64 直接毁掉这个区分度（先乘后测必红）。
- `HEALTH_BAR_SIZE_BY_KIND`（体型表）**一行未改**，仍是唯一体型真源；
  实际生效倍率由**新快照字段 `overhead_health_bar_scale`** 暴露，验收读字段而不是在测试里
  重写一遍「谁该缩」的判断。
- 连带影响：吼叫图标尺寸 = 条宽 × 0.42（`MonsterStartupProfile.icon_edge_m`），
  而 `_fire_roar_icon()` **读的是 `_overhead_health_size`（缩放后）而不是体型表** ⇒
  图标自动跟随缩到 0.8。若哪天改成读体型表，图标会与条宽脱钩。

### ③ Boss 条上移，不再遮挡
`_anchor_control(_boss_panel, ...)` 设计 y `106..160` → **`80..134`**（canvas 84.8 → **64.0**，静上移 20.8 px）。

新下界不是拍的：**由关卡标题带反推** ——
房间行 canvas 11.2..30.4（设计 14..38）、波次行 32.0..49.6（设计 40..62），
标题带实底 ≈49.6；Boss 面板顶边 64.0 ⇒ **净空约 14.4 px**。
`verify_expedition_monitor_boss_flow` 的重叠阈值同步 `80.0 → 63.0`
（旧阈值只是「设计 100」的口径，比标题带实底还低 30 px，等于没在守东西）。

## 改了哪些文件（5 个，全部就地修改）

| 文件 | 关键位置 |
|---|---|
| `src/enemy3d/Enemy3D.gd` | `NORMAL_HEALTH_BAR_SCALE`(95) / `HEALTH_BAR_DELAY_*`(97-98)、`_overhead_health_bar_scale`(197)、`_ensure_overhead_health_bar` 缩放(451-456)、`_redraw_overhead_health_bar`(557)、`_tick_overhead_health_bar_delay`(598)、`_process` 调用(786)、快照字段(1775-1776) |
| `src/world3d/Dungeon3D.gd` | `BOSS_HEALTH_BAR_DELAY_*`(110-111，引 Enemy3D 常量)、`_boss_delayed_bar/_boss_delayed_value`、`_on_enemy_health_changed`(4259)、`_tick_boss_health_bar_delay`(4273)、`bar_stack`(4319)、Boss 面板锚(4301) |
| `tests/verification/verify_3d_enemy_behavior_flow.gd` | 期望条宽 ×`NORMAL_HEALTH_BAR_SCALE`(82)；新增延迟白段双向断言（受伤后有白段 + 步进后只能朝真实值收） |
| `tests/verification/verify_expedition_monitor_boss_flow.gd` | Boss 面板重叠阈值 `>= 80.0 → >= 63.0` |
| `docs/v0.1/06_技术施工_怪物精英与Boss.md` | §2「血条表现」新增 2026-10-14 条目；§6 Boss 条目补两层叠放与上移口径 |

改动前备份：`.workbuddy/backup/20261014_health_bar_visual/before_edits/`（Enemy3D.gd / Dungeon3D.gd）。

## 验收结果（直接跑场景，非套件）

| 场景 | 结果 | 说明 |
|---|---|---|
| `verify_3d_enemy_behavior_flow` | **rc=0 PASS** | 含新增白段断言（7 个怪种全覆盖）、期望条宽 ×0.80、体型层级未破 |
| `verify_monster_startup_roar` | **rc=0 PASS** | 条宽表逐项比对 + 它与吼叫图标尺寸的耦合（自动跟随缩放） |
| `verify_first_elite_deployment_flow` | **rc=0 PASS** | 精英条仍 `>= 2.0` 宽 ⇒ 0.80 没有误伤精英 |
| `verify_expedition_monitor_boss_flow` | **rc=1，44 项中 3 项失败** | **3 项全部与血条无关**，见下 |

### 那 3 项失败的归因（已取证，不是本改动造成）
失败项：`使用房间设计源三波 encounter` / `正式刷怪生命为52000` / `Boss出生在房间中心`。
Boss 条自身的 4 条断言（透明外壳、`≤10 px` 细条、`y >= 63`、醒目红填充）**全部通过**。

归因证据：
1. 工作区里 `data/level_plans/expedition_01/level_plan.json` 处于**未提交修改**状态（并发会话的
   远征01 `monster_rules` 在途工作），其中新增
   `monster_rules.stats.per_kind.boss.hp = 32000` ⇒ 直接解释「生命 52000」失败；
   同文件还改了 encounter / spawn 口径 ⇒ 解释另外两条。
2. `python3 scripts/sync_runtime_design_data.py --check` 同期报
   `projection drift: .../boss_50x40.json` + `projection manifest drift` ⇒ 设计源与运行时投影不同步。
3. 本次只动 `Enemy3D` / `Dungeon3D` 的血条与锚点，与 AI 决策、波次规划、刷怪位置无交集。
4. 同一时刻并发会话还在改 `src/map/MonsterInjector.gd`（death_explosion 挂载）、
   `src/rewards/*`、`data/narrative/*` 等大量文件 —— 该场景本就处在中间态。

**结论：该项要在并发会话把远征01 设计源提交/收敛后复跑，不应计入本次改动。**

## 复用教训
- **「同一份表现分两套实现」时，速度/配色这类手感常量必须同源引用，不要各写一份字面量。**
  本项目里小怪条是纹理像素、Boss 条是两层 ProgressBar —— 实现不同，手感必须相同。
- **验收要能把「帧率」这个变量摘出去**：凡是「随时间收敛」的表现，生产代码要留一个
  「可传 delta 的步进函数」，否则断言只能靠 `await process_frame` 赌帧时间。
- **改倍率前先 grep 依赖这条倍率的下游**：本次 0.80 差点打到精英条（靠 2.05 m 宽做区分）
  与吼叫图标（= 条宽 × 0.42）。先查断言再动手，比改完看红再回滚便宜。
- **上移/下移 HUD 元素时，阈值要由「邻居的实底」反推，不要跟着旧数字等比挪** ——
  旧阈值 80.0 其实是「设计 100 × 0.8」的口径，它从没真正守过标题带。
