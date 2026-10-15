# 2026-10-15 玩家主界面血条：延迟扣血白段（与 Boss 屏条 / 小怪头顶条同源）

> 业主口径：「这个血条表现效果，角色的血条主界面的也要找个表现」。
> 「这个」= 2026-10-14 落地的**延迟扣血白段**（见
> [2026-10-14_health_bar_visual.md](2026-10-14_health_bar_visual.md) §2）。

## 1. 需求与口径

| # | 需求 | 落地口径 |
|---|---|---|
| ① | 玩家主界面血条也要延迟扣血表现 | `HUD/ReferenceCombatHUD/PlayerStatusBlock` 的生命条改为**两层叠放**：白色延迟层在下、红色真实条在上 |

**只动表现层。** 玩家真实 HP（`player.current_hp`）、伤害判定、格挡结算、死亡流程、
存档格式**一个字节没动** —— 白段只活在 `Dungeon3D._player_delayed_ratio` 里。

## 2. 玩家条与 Boss 条是同一套做法，与小怪头顶条不同

| | 小怪头顶条 | Boss 屏幕条（10-14） | 玩家主界面条（本次） |
|---|---|---|---|
| 载体 | 单张 `200×24` 纹理里的像素（Sprite3D billboard） | 两层 `ProgressBar` 叠放 | **两层 `ProgressBar` 叠放** |
| 白段画法 | `_redraw_overhead_health_bar()`：先铺白段、再铺红条 | 下层 `BossHealthBarDelayed`（白 fill）＋ 上层 `BossHealthBar`（红 fill，背景 alpha 0） | 下层 `PlayerHealthBarDelayed`（白 fill）＋ 上层 `HPBar`（红 fill，背景 alpha 0） |
| 面板/块高度 | 不变 | 不变（`bar_stack` 定高） | **不变**（`PlayerHealthBarStack` 取原条的最小尺寸 `220×22`） |
| 追赶函数 | `Enemy3D._tick_overhead_health_bar_delay(delta)` | `Dungeon3D._tick_boss_health_bar_delay(delta)` | `Dungeon3D._tick_player_health_bar_delay(delta)` |

速度与配色仍然**只有一个真源**：`Enemy3D.HEALTH_BAR_DELAY_SPEED = 1.8` /
`HEALTH_BAR_DELAY_COLOR = (1, 1, 1, 0.96)`。

本次把 `Dungeon3D` 那两个引用常量从 `BOSS_HEALTH_BAR_DELAY_SPEED/_COLOR` **改名为
`HUD_HEALTH_BAR_DELAY_SPEED/_COLOR`** —— 它们现在同时喂 Boss 屏条与玩家条，
名字里再只有 Boss 就是误导。（旧名仅存在于 `docs/v0.1/development/**` 的历史记录里，
按「历史记录不改写」的口径原样保留。）

## 3. 公式

```
H = current_hp / max_hp                      # 真实比例，受伤当帧立即生效
L ← move_toward(L, H, Δt × 1.8)              # 白段追赶，1.8 = 每秒 1.8 个"满格比例"

红条宽 = 全宽 × H
白段宽 = 全宽 × L − 红条宽                    # L > H 时才有像素
```

**只有受伤才留白**，`_sync_player_health_bar_delay(hp_ratio, took_damage)`：

```gdscript
if not _player_health_bar_initialized or not took_damage or hp_ratio >= _player_delayed_ratio:
    _player_delayed_ratio = hp_ratio
```

少了这一条，**开局第一帧就会挂一条满格白段**（初始 `_player_delayed_ratio = 1.0`，
而读档/受伤后 `hp_ratio < 1.0`），玩家看到的是「我掉了一截血」，是一句假信息。
治疗、复活、读档同理 —— 都必须在同一帧对齐，不能留残影。

## 4. 为什么把 hp_bar 包进一个 stack 而不是改布局

```gdscript
var hp_stack := Control.new()
hp_stack.name = "PlayerHealthBarStack"
hp_stack.custom_minimum_size = _hud_size(Vector2(220, 22))   # ← 原 hp_bar 的最小尺寸
stat_vbox.add_child(hp_stack)          # VBox 只认 stack 的尺寸
... 两层都是 PRESET_FULL_RECT
```

`VBoxContainer` 只读**直接子节点**的最小尺寸，所以把原来那条 `220×22` 换成同尺寸的
`Control`、两层条用 `FULL_RECT` 跟随之后，**块内内边距、上下邻居（血量数值 / 手电刻度 /
金币读数）的位置一字不动**。这也是 Boss 屏条 `bar_stack` 的现成做法，两处同构。

顺带把代码建的这条条**命名**了（原来匿名、只能靠 `tower.hp_bar` 属性访问）：
`HPBar` + `PlayerHealthBarDelayed`，验收可以直接 `find_child` 而不靠私有变量名。

红条的 `background` 改为 **alpha 0**：深色底改由下层白条的 `background` 提供，
否则红条的深底会把白段整个盖掉（白段就永远看不见）。

## 5. 改动清单

| 文件 | 关键位置 |
|---|---|
| `src/world3d/Dungeon3D.gd` | `HUD_HEALTH_BAR_DELAY_SPEED/_COLOR`(107-113，改名)、`_player_delayed_bar`/`_player_delayed_ratio`/`_player_health_bar_initialized`、`_build_reference_main_hud` 的 `PlayerHealthBarStack`(约 1555)、`_process` 里 `_tick_player_health_bar_delay`(1146)、`_on_player_hp_changed` 调 `_sync_player_health_bar_delay`(约 8167)、新增 `_sync_/ _tick_` 与 `get_player_vitals_bar_snapshot()` |
| `tests/verification/verify_reference_hud_fate_visual.gd` | 新增一段玩家条断言：层被动 / 受伤留白 / 只朝真实值收且不越过 / 回满不留残影 / 两层几何重合；截图前留一次可见白段 |
| `docs/v0.1/04_技术施工_战斗与局内成长.md` | §20 主 HUD 条目补玩家条白段口径 |
| `docs/v0.1/06_技术施工_怪物精英与Boss.md` | Boss 条条目里的常量名同步改名并注明「玩家条共用」 |

## 6. 验收

见 §6；本页只记口径与实现，**数值结论以验收日志为准**。

## 7. 未做 / 可选加强（等主人挑）

这几条是**玩家条上还缺的表现**，本次都没做，列出来是为了不在"已做"里混入"想做"：

1. **治疗没有对应表现**：玩家条现在只有"白段消失"这一个信号。补一管**青色回血段**
   （从当前值往右长、同样按时长收）才能让"我被治了"和"我在掉血"在余光里也分得开。
2. **受击瞬间的短白闪**（约 0.08 s）落在整条上：现在只有全屏暗角与数字变红，
   血量条本身在被击中那一帧没有动作。
3. **低血量脉动**：`hp_ratio <= 0.30` 时只有数字变红 + 暗角，条本身恒定。
4. **背包/装备页的 `InventoryUI.equipment_hp_bar`** 是否也要同一套（它是另一条独立实现）。

## 8. 可复用教训

- **叠层做法的可复制模板**：`Control` stack（取原最小尺寸）＋ 两层 `PRESET_FULL_RECT` ＋
  上层 `background` alpha 0。放在 `VBoxContainer` 里也不会挪动任何邻居。
- **常量改名要 grep 的不止代码**：本次 3 处文档引用，1 处是现行文档（必须改）、
  2 处是 `development/**` 历史记录（不能改）。
- **凡有"初始化态"的延迟层，都必须显式写「初始化即对齐」** —— 默认值（满格）与
  首次数据（不满）之间的差值，会在开局第一帧被当成一次"受伤"显示出来。
