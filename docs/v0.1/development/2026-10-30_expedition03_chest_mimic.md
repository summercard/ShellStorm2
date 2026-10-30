# 远征03 宝箱拟态：开箱变成怪，物资在它肚子里

**日期**：2026-10-30
**范围**：`treasure_chests.mimic` 配置、`FloorPlanGenerator._chest_placements_for()`、
`TreasureChest3D` 拟态形态、`Dungeon3D._reveal_chest_mimic()` / `_deliver_chest_mimic_loot()`
**起因**：业主「继续做宝箱房」，在「拟态接回 / 品质池拆分 / 房间陈设」三选一里选了**拟态接回**

## 1. 为什么这一层排第一

2026-10-30 摘掉 `egt_mimic` 时留了理由：**宝箱本体还没有正式设计，先做拟态等于把
「箱子会咬人」这条规则钉在一个还要改的箱子上**。现在宝箱的钥匙 / 掉落 / 命运卡 / 品质
四段都过了验收，前置条件成立。

而且它对手感的影响最大：在此之前，开箱是**纯收益**——没有任何理由犹豫。
接回之后，「这箱子会不会咬我」才成为一个真实的问题。

## 2. 新旧两版拟态不是同一件事

旧的 `box_egt_mimic_trap` 是**刷怪盒里的一只怪**，靠 `PROFILES.egt_mimic.disguise`
（`reveal_radius_m = 3.4`）自己蹲着装箱子，玩家靠近 3.4m 才现形。

新版是**宝箱本体在按下 E 的那一帧变成怪**。区别不只是"更真实"：

| | 旧 | 新 |
|---|---|---|
| 玩家能不能分辨 | 靠近 3.4m 就知道 | **数据层才知道** |
| 现形时机 | 距离触发 | 开箱那一帧 |
| 钥匙 | 不涉及 | **照扣** |

⇒ 新版必须**出生即解除伪装态**（`Enemy3D.reveal_disguise_now()`）。
不解除的话，伪装态的语义「静止、不攻击、**不吃伤害**」会原样套在一只刚从箱子里
咬出来的怪身上 —— 玩家看到的是"怪卡住了，而且打不动"。

## 3. 五段链路

```
level_plan.json → treasure_chests.mimic {chance, monster_kind}      ① 配置
  → FloorPlanGenerator._chest_placements_for()  掷骰写进每箱         ② 生成期
  → room_from_source() 白名单（整段 duplicate）                      ③ 透传
  → DungeonRoom3D._build_treasure_chests() → chest.mimic             ④ 实例
  → Dungeon3D._on_chest_open_requested() → _reveal_chest_mimic()     ⑤ 开箱变怪
  → _on_enemy_killed() → _deliver_chest_mimic_loot()                 ⑥ 击杀掉回
```

### 3.1 掷骰：确定性哈希，不用 RNG

```gdscript
var chest_salt := "%s#%d" % [salt, index]                       # 房间id + 层种子 + 箱序号
"quality": _chest_quality_for_salt(qualities, chest_salt),
"mimic":   _roll_ratio(chest_salt + ":mimic") < mimic_chance,
```

- 用 **FNV-1a 纯函数**而不是 `RandomNumberGenerator`：后者要被 seed 与复位，
  调用顺序一变结果就变；纯函数谁调都一样，探针能复算，流送重建/读档也不会变。
- 盐里带**层种子**：否则同一张骨架的 `reward_01` 局局同品质、局局是拟态，会被背下来。
- 品质与拟态**各用各的盐**：共用一个盐会造出「品质越高越可能是拟态」这种隐性相关。

### 3.2 开箱顺序里插入的一段

```
扣钥匙（原有） → 拟态？ → commit_mimic_reveal()（抖动 0.4s → 弹盖 → 消失）
                        → 刷 egt_mimic（推开玩家 3m、注入房间矩形、解除伪装）
                        → 把「开箱时抽好的物资」挂到怪身上
             → 否则 commit_opened()（原有）
```

**抽奖放在开箱时、发放在击杀时**。这样「拟态箱」的实际收益与普通箱完全一致
（同样的 `drop_count`、同样的品质加成），区别只是兑现时间。击杀时不再抽第二次。

## 4. 四个"不拦住就静默错"的点

| 点 | 不拦会怎样 | 拦在哪 |
|---|---|---|
| 清房语义 | 宝箱房被 `_mark_room_cleared()` 记成「已清内容房」：白送一次清房结算，且「已清内容房数」+1 ⇒ **提前满足撤离门与传送支线的解锁条件** | `_resolve_room_enemy_departure()` 按 `chest_mimic` 标记提前 return |
| 贴脸刷怪 | 怪与玩家重叠，**接触伤害在生成那一帧就结算** | `_chest_mimic_spawn_position()` 少于 3m 就推开 |
| 箱子不消失 | 房间中央留一块**看不见的挡路石头**（只藏视觉不关碰撞） | `_vanish_for_mimic()` 视觉与 `CollisionShape3D.disabled` 一起收 |
| 伪装态没解除 | 静止 / 不攻击 / **不吃伤害** | `reveal_disguise_now()` |

第一条最隐蔽：它不报错、不改任何画面，只是把
`_count_cleared_content_rooms()` 从 0 变成 1 —— 而那正是撤离门解锁率的分子。

## 5. 顺带修掉的死配置：全层每只箱子都是 common

读 `_chest_placements_for()` 时发现：

```gdscript
"quality": _chest_quality_for_index(qualities, index)   # ordered[index % ordered.size()]
```

本意是「一房里多只箱子按权重轮流拿品质」。但 `chest_per_room = 1` ⇒ `index` **恒为 0**
⇒ `ordered[0]` 是权重最高那档 ⇒ **全层每只箱子都是 common**，
`rare`(10) / `epic`(2) 永远抽不到，`quality_weights` 整段是死配置。

症状极隐蔽：箱子开了、掉了东西、给了命运卡，只是「抽到史诗」这件事**从未发生过**。
改成按盐掷骰后实测 4000 个虚拟房间：

| 档 | 期望 | 实测 |
|---|---|---|
| common | 62.0% | 62.3% |
| uncommon | 26.0% | 25.9% |
| rare | 10.0% | 10.0% |
| epic | 2.0% | 1.9% |
| 拟态 | 20.0% | 19.7% |

## 6. 验证

`tools/_egt_mimic_chest_probe.gd`，三层各验一件事：

| 层 | 覆盖 |
|---|---|
| A 生成器掷骰（4000 虚拟房，不建地牢） | 品质分布 / 拟态率 / 同盐幂等 |
| B 字段透传 | `mimic` / `mimic_monster_kind` 穿过白名单后与实例逐值一致 |
| C 运行时全链路 | 扣钥匙 / 开箱不掉物 / 刷怪不贴脸 / 出生即现形 / 进入战斗 / 现形后箱子消失 / **流送重建后仍是消失态** / 击杀掉回 / **不算清房** / 不重复结算 |

C 层实测输出：

```
透传：数据 mimic=false kind=egt_mimic → 实例 mimic=false kind=egt_mimic
刷怪：egt_mimic @ (30.0, 0.0, 107.0)，离玩家 3.00m，伪装=false
2.4s 内状态：["alert", "telegraph", "recovery", "chase"]
现形后：箱子视觉=false 碰撞已关=true
流送重建：已开=true 视觉=false 碰撞已关=true
击杀后：物资 +3 件（箱内 2 + 拟态自身击杀掉落），命运卡 +1 张
        status=拟态击破 · 2 件物资 · 命运卡「圣杯·二」
EGT_MIMIC_CHEST_PROBE_OK
```

> `2.4s 内状态` 那一行是「它真的在打」的证据：`alert → chase → telegraph → recovery`
> 是完整的「发现 → 接近 → 预警 → 出手」链。这一点单独验，是因为上一轮那只瞬移怪
> 「双向都打不中」时，状态机上看也完全正常 —— 只有把状态序列打出来才知道它接没接入战斗。

### 6.1 反向验证（四条，全中）

延续 §T10.6 定的规矩：**新门禁必须先故意撤掉约束、确认它报错、再恢复**。

| 撤掉的约束 | 探针反应 |
|---|---|
| `_resolve_room_enemy_departure` 的拦截 | FAIL：`房间被标成已清（false → true）` + `已清内容房数 0 → 1` |
| 推离玩家的 3m | FAIL：`刷怪：离玩家 0.00m` |
| 品质盐固定成常量（等价于旧轮转） | FAIL：`common 100.0% / rare 0.0% / epic 0.0%` |
| `_vanish_for_mimic()` 清视觉与碰撞 | FAIL：`箱子视觉=true 碰撞已关=false` |
| `reveal_disguise_now()` 那一行 | FAIL：`拟态出生仍是伪装态` |
| `_restore_treasure_chests()` 的拟态分支 | FAIL：`流送重建：已开=false 视觉=true 碰撞已关=false` —— 更糟的是连「已开」都丢了，等于**可以再开一次**（刷钥匙 / 刷怪） |

### 6.2 回归

`_egt_chest_probe`（已同步：**显式清掉拟态标记**再测掉落分支，否则 20% 的种子会随机红）、
`_egt_drop_probe`、`_egt_clear_rewards_wiring_probe`、`_egt_mechanic_probe`、
`_egt_roster_probe`、`_egt_merchant_probe`、`verify_3d_enemy_behavior_flow`、
`verify_3d_combat_progression_flow`、`verify_reward_ground_handoff`、
`verify_strong_variant_monsters` —— 全绿。

## 7. 踩坑记录

**① `_egt_chest_probe` 差点变成"随种子红绿"的探针。**
它挑第一只宝箱测「开箱给 2 件掉落」。而每箱 20% 是拟态，拟态开箱**不掉东西** ——
换一个种子这条断言就会红，而代码是对的。修法是在那条分支里显式 `chest.mimic = false`
并写清"本探针只测普通箱，拟态由 `_egt_mimic_chest_probe` 专测"。
**同一个命令跑两次结论不同的探针，比没有探针更糟。**

**② 击杀拟态地上出 3 件，不是 2 件。**
因为拟态**同时也是一只普通怪**，击杀还要走一次怪物掉落表。第一版断言写成
`== drop_count` 当场红。判据改成 `>= drop_count` 并注明理由 ——
要求 `==` 等于要求"拟态不许掉自己的东西"，那会让它比同族怪凭空少一档收益。

**③ 第五条反向验证抓到了探针自己的假绿。**
第一版是 `await` 两帧之后才读 `mimicked._disguised`。而 `egt_mimic` 的
`reveal_radius_m = 3.4`，我们刷在 **3.0m** 处 —— 下一帧 `_tick_egt_disguise` 就自己
解除了伪装，于是删掉 `reveal_disguise_now()` 那行**仍然全绿**。
修法：把取怪与读伪装位都挪到**同一帧**（`_spawn_enemy_batch` 是同步 `add_child`）。

这也顺带说明：`reveal_disguise_now()` 目前**是冗余的**（3.0 < 3.4 兜住了），
但只要有人把 `CHEST_MIMIC_MIN_SPAWN_DISTANCE_M` 调过 3.4，它立刻变成唯一保险。
保留它并把它钉住，比"反正现在不需要"更划算。

**④ C 层显式置 `chest.mimic = true` 是有意的，不是绕过数据。**
本 seed 那只箱子未必是拟态，依赖种子撞上会让结论随种子飘。A 层已证明掷骰按 20% 出拟态、
B 层已证明字段确实落到实例上（含 `placement.has("mimic")` 这条防"数据里根本没这字段"的断言），
所以 C 层要测的是「标记为真之后那条分支对不对」。

## 8. 没做到的

| 项 | 说明 |
|---|---|
| 拟态没有"可疑感" | 原作拟态靠近时有细微异样。我们运行时**刻意不透露**任何视觉线索，因为箱子目前是程序化几何，做不出"呼吸的箱子" |
| 房间不封门 | 宝箱房是和平房，门常开，玩家可以跑（与 Gungeon 一致）。代价是"跑了就没了"完全由玩家自己承担 |
| 拟态不响应命运卡 | 无「宝箱品质被命运卡改写」联动 |
| 品质池仍是共用的 | 四档品质仍共用 `loot_floor_1_2`，只靠 `quality_tier()` 加成 —— 这是下一层「品质池拆分」的事 |
