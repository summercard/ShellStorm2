# 2026-10-14 血条表现：延迟扣血白段 ＋ 小怪条 ×0.80 ＋ Boss 条上移

> 业主口径：「按照这个进行修改血条表现，还有现在的小怪血条整体缩小到80%，
> boss血条放在画面的在上面一些，现在还是会遮挡」。
> 「这个」指抖音那条讲「打 Boss 时血条为什么有一截白的、过一会儿才……」的延迟扣血条机制。

## 1. 三条需求与口径

| # | 需求 | 落地口径 |
|---|---|---|
| ① | 加延迟扣血白段 | 真实比例立即生效，白段按固定速度追赶；**只有受伤才留白** |
| ② | 小怪血条整体缩小到 80% | 只缩**普通小怪**头顶条；Boss 与精英不缩 |
| ③ | Boss 血条上移、不再遮挡 | 锚点设计 y `106 → 80`，下界由**关卡标题带实底**反推 |

三条全部落在**表现层**：真实生命值、伤害判定、AI、存档格式**一个字节没动**。

## 2. 延迟扣血白段

### 2.1 公式

```
H = current_hp / max_hp                      # 真实比例，收到伤害当帧立即生效
L ← move_toward(L, H, Δt × 1.8)              # 白段追赶，1.8 = 每秒 1.8 个"满格比例"

红条宽 = round(内宽 × H)
白段宽 = round(内宽 × L) − 红条宽            # 画在红条右侧，L > H 时才有像素
```

**白段不是第二管血。** 它不写进 `current_hp`、不参与伤害判定、不进存档。
它唯一的信息是「刚才这一下打掉了多少」。

### 2.2 只有受伤才留白

`_on_self_health_changed()` 里：

```gdscript
if not _overhead_health_bar_initialized or next_ratio >= _overhead_delayed_health_ratio:
    _overhead_delayed_health_ratio = next_ratio
```

少了这一条，怪一生成（或治疗、或满血重置）就会挂一条「满格白段」——
玩家看到的是「这只怪开局就掉了一截血」，是一句假信息。

### 2.3 两套血条、一个手感真源

| | 小怪头顶条 | Boss 屏幕条 |
|---|---|---|
| 载体 | 单张 `200×24` 纹理里的像素（Sprite3D billboard） | 两层 `ProgressBar` 叠放 |
| 白段画法 | `_redraw_overhead_health_bar()`：先铺白段、再铺红条 | 下层 `BossHealthBarDelayed`（白 fill）＋ 上层 `BossHealthBar`（红 fill，背景 alpha 0） |
| 面板高度 | 不变（纹理尺寸不变，只改填充像素） | 不变（`bar_stack` 定高，两层同高同宽） |
| 追赶函数 | `Enemy3D._tick_overhead_health_bar_delay(delta)` | `Dungeon3D._tick_boss_health_bar_delay(delta)` |

速度常量只在 `Enemy3D.HEALTH_BAR_DELAY_SPEED = 1.8` 定义一次，
`Dungeon3D.BOSS_HEALTH_BAR_DELAY_SPEED := Enemy3D.HEALTH_BAR_DELAY_SPEED` 引它。
**实现不同，手感必须相同** —— 同一场战斗里 Boss 条和小怪条的追赶节奏不一致，玩家一眼能看出。

### 2.4 为什么追赶要抽成可传 delta 的函数

不是为了好看。验收要断言「白段确实在缩，且没有越过真实血量」——
靠 `await get_tree().process_frame` 采样，帧时间随机器浮动，这条用例会变成飘忽用例。
抽成 `_tick_*(delta)` 后验收直接传固定 delta 步进，取样点与帧率解耦。

## 3. 小怪条 ×0.80

`Enemy3D.NORMAL_HEALTH_BAR_SCALE = 0.80`，在 `_ensure_overhead_health_bar()` 里乘进 `wanted_size`。

### 3.1 为什么 Boss 与精英不缩

```gdscript
_overhead_health_bar_scale = (
    NORMAL_HEALTH_BAR_SCALE
    if enemy_kind != "boss" and _elite_health_bar_profile.is_empty()
    else 1.0
)
```

- **精英**靠 **2.05 m 宽**表达「这只不一样」。乘 0.8 → 1.64，
  `verify_first_elite_deployment_flow` 的 `overhead_health_bar_size.x >= 2.0` 当场红，
  而且逻辑上这个区分度就没了。
- **Boss** 另有屏幕总血条契约（`≤10 px` 细条 + `y >= 63`），头顶条也不该跟着缩。

### 3.2 体型表没动，倍率走快照

`HEALTH_BAR_SIZE_BY_KIND` **一行未改**，仍是唯一体型真源。
实际生效倍率由**新快照字段 `overhead_health_bar_scale`** 暴露，
验收读字段，而不是在测试里把「谁该缩」的判断再抄一遍 —— 判断抄两份必然漂。

### 3.3 连带：吼叫图标自动跟随

吼叫图标世界边长 = 头顶条宽 × 0.42（`MonsterStartupProfile.icon_edge_m`），
而 `_fire_roar_icon()` 读的是**缩放后的** `_overhead_health_size` 而不是体型表
⇒ 图标自动跟着缩到 0.8，不需要额外改动。
**若哪天有人把它改成读体型表，图标会与条宽脱钩** —— 这条耦合由
`verify_monster_startup_roar` 的「尺寸表逐项一致」看着。

## 4. Boss 条上移

锚点：`_anchor_control(_boss_panel, 0.5, 0.0, 0.5, 0.0, -340, 80, 340, 134)`（原 `82..136`）。

| 量 | 设计 y | canvas y（× `HUD_UI_SCALE` 0.80） |
|---|---|---|
| 房间行 | 14..38 | 11.2..30.4 |
| 波次行 | 40..62 | 32.0..49.6 |
| **标题带实底** | — | **≈49.6** |
| Boss 面板顶边（改前） | 106 | 84.8 |
| **Boss 面板顶边（改后）** | **80** | **64.0** |

净空 = `64.0 − 49.6 ≈ 14.4 px`。

**新下界不是把旧数字等比往上挪。** 旧阈值 `80.0` 是「设计 100 × 0.8」的口径，
比标题带实底还低 30 px —— 它从没真正守过「不重叠」这件事。
本次改成由**邻居（标题带）的实底**反推，`verify_expedition_monitor_boss_flow`
的重叠阈值同步 `80.0 → 63.0`。

## 5. 改动清单

| 文件 | 关键位置 |
|---|---|
| `src/enemy3d/Enemy3D.gd` | `NORMAL_HEALTH_BAR_SCALE`(95)、`HEALTH_BAR_DELAY_SPEED/_COLOR`(97-98)、`_overhead_health_bar_scale`(197)、`_ensure_overhead_health_bar` 缩放判定(451-456)、`_redraw_overhead_health_bar`(557)、`_tick_overhead_health_bar_delay`(598)、`_process` 调用(786)、快照字段(1775-1776) |
| `src/world3d/Dungeon3D.gd` | `BOSS_HEALTH_BAR_DELAY_SPEED/_COLOR`(110-111)、`_boss_delayed_bar`/`_boss_delayed_value`、`_on_enemy_health_changed`(4259)、`_tick_boss_health_bar_delay`(4273)、`bar_stack`(4319)、Boss 面板锚(4301) |
| `tests/verification/verify_3d_enemy_behavior_flow.gd` | 期望条宽 ×`NORMAL_HEALTH_BAR_SCALE`(82)；新增白段双向断言（受伤后有白段 ＋ 步进后只能朝真实值收，且零伤害格挡时不误判） |
| `tests/verification/verify_expedition_monitor_boss_flow.gd` | Boss 面板重叠阈值 `>= 80.0 → >= 63.0` |
| `docs/v0.1/06_技术施工_怪物精英与Boss.md` | §2 新增 2026-10-14 血条表现条目；§6 Boss 条目补两层叠放与上移口径 |

改动前备份：`.workbuddy/backup/20261014_health_bar_visual/before_edits/`
（`Enemy3D.gd` / `Dungeon3D.gd`）。

## 6. 验收

| 场景 | 结果 |
|---|---|
| `verify_3d_enemy_behavior_flow` | **rc=0 PASS**（含新增白段断言，7 怪种全覆盖；期望条宽 ×0.80；体型层级未破） |
| `verify_monster_startup_roar` | **rc=0 PASS**（条宽表逐项比对 + 图标尺寸耦合） |
| `verify_first_elite_deployment_flow` | **rc=0 PASS**（精英条仍 `>= 2.0` 宽 ⇒ 0.80 未误伤精英） |
| `verify_expedition_monitor_boss_flow` | rc=1，44 项中 3 项红，**均与血条无关**（见 §6.1） |

### 6.1 那 3 项红的归因（已取证）

失败项：`使用房间设计源三波 encounter` / `正式刷怪生命为52000` / `Boss出生在房间中心`。
Boss 条自身的 4 条断言（透明外壳、`≤10 px` 细条、`y >= 63`、醒目红填充）**全部通过**。

证据：

1. 工作区 `data/level_plans/expedition_01/level_plan.json` 处于**未提交修改**状态，
   其中新增 `monster_rules.stats.per_kind.boss.hp = 32000` ⇒ 直接解释「生命 52000」失败；
   同文件还改了 encounter / spawn 口径 ⇒ 解释另外两条。
2. `python3 scripts/sync_runtime_design_data.py --check` 同期报
   `projection drift: .../boss_50x40.json` + `projection manifest drift`。
3. 本次只动 `Enemy3D` 的血条纹素与 `Dungeon3D` 的 Boss 条锚点，
   与 AI 决策、波次规划、刷怪位置**无交集**。

⇒ 该项需在并发会话把远征01 设计源收敛/提交后复跑。

### 6.2 未做的事

套件 `run_verification_suite.sh` 仍在入场检查 `sync_runtime_design_data.py --check`
处 `exit 2`（既有阻塞，非本次引入），故 **`batch` 未跑**，改为直接跑场景。
渲染截图未产出：Boss 屏条只在真实 Boss 战里出现，没有同量级的现成渲染场景；
位置正确性由 `verify_expedition_monitor_boss_flow` 的 `y >= 63` 数值断言守住。
如需实拍，可在真实远征 Boss 战中截一张对照。

## 7. 可复用教训

- **同一份表现分两套实现时，手感常量（速度/配色）必须同源引用，不要各写一份字面量。**
- **凡「随时间收敛」的表现，生产代码要留一个可传 delta 的步进函数**，
  否则验收只能赌帧时间。
- **改倍率前先 grep 这条倍率的下游依赖**：本次 0.80 差点打到精英条（2.05 m 宽做区分）
  与吼叫图标（= 条宽 × 0.42）。先查断言再动手，比改完看红再回滚便宜。
- **挪 HUD 元素时，阈值要由「邻居的实底」反推，不要跟着旧数字等比挪** ——
  旧阈值可能从来就没在守它名字里写的那件事。
