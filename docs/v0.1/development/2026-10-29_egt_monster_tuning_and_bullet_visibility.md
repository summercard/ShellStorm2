# 远征03 怪物数值重定标 + 子弹可见性修复（2026-10-29 第二轮）

## 1. 业主的三条要求

> 「血量按照我的子弹伤害的血量进行比例调整。伤害也是一样。按照普通小怪击中玩家去 1/6 血进行
> 其它比例的调整。速度冷却，射程弹速很关键。要去找数据，然后补完。然后还有很多小怪没有通过
> 检验，子弹特效都飞不出来。」

拆成四件事：① 血量按子弹伤害定标 ② 伤害按 1/6 血 ③ 速度/冷却/射程/弹速补数据
④ 修"子弹飞不出来"。

## 2. 血量：×10，不是 ×1.7

**反推过程**（这是这一轮最关键的一步，不是拍数字）：

| | EGT | 本工程 |
|---|---|---|
| 基准怪 | Bullet Kin 15 血 | 同 |
| 玩家初始武器伤害 | 手枪约 6 / 发 | 初始步枪 **50** / 发 |
| 击杀发数 | 15 ÷ 6 ≈ **2.5~3 发** | 目标同样 3 发 |
| ⇒ 该怪血量 | 15 | **150** |
| ⇒ 系数 | — | **150 ÷ 15 = 10** |

因为是线性关系，血量与原作**严格等比**：EGT 里枪坚果是子弹小子的 6.67 倍，
这里也是 6.67 倍（150 → 1000）。

**旧口径为什么必须废**：`clamp(round(42 × (egt/15)^0.72), 6, 200)` 指数 0.72 把高端压平，
6.67 倍只剩 3.93 倍。后果是同一只怪的手感直接变短 —— 枪坚果从"打 4 秒"变成"打 1.6 秒"，
而且**血量与威胁脱钩**（原作里血最多的怪，可能比次一级的还脆）。

净值对照：

| 怪 | EGT | 旧进场 | 新进场 | 初始步枪发数 |
|---|---|---|---|---|
| 子弹小子 | 15 | 42 | **150** | 3 |
| 红霰弹 | 30 | 69 | **300** | 6 |
| 蓝霰弹 | 40 | 85 | **400** | 8 |
| 枪坚果 | 100 | 165 | **1000** | 20 |

## 3. 伤害：17 = 玩家 1/6 血

玩家 `max_hp = 100`，`100 ÷ 6 ≈ 17`。这**正好**是原作的「半颗心」——
Gungeoneer 有 3 颗红心，半颗心 = 6 格里的 1 格。

| 档位 | 值 | 范围 |
|---|---|---|
| 普通子弹 / 接触 | **17** | 29 只 |
| 爆炸 | **26**（1.5×） | pinhead 自爆 / nitra / grenat |
| 死亡弹幕单发 | ≈ **5**（17 × 0.30） | 红/蓝/老兵霰弹的死后全向喷 |
| 无伤害 | **0** | gunsinger / gripmaster |

**死亡弹幕必须折减**：原作靠翻滚与 Blank 的无敌帧穿弹幕，我们没有那套系统。
12 发 × 17 = 204 是"必死"，不是"惩罚"；折到 5 点后 12 发全中 60 —— 仍然致命，
但站对位置能活。

## 4. 速度 / 冷却 / 射程 / 弹速：查过了，原作没有这些数

业主说"要去找数据"。找了三类来源，结论必须如实记：

| 来源 | 拿到什么 | 拿不到什么 |
|---|---|---|
| `enterthegungeon.wiki.gg`（总表 + 各怪页） | 血量逐层表、行为描述、**连发数**、预判有无 | 速度/射速/弹速的**任何数字** |
| `EnemyAPI`（ModTheGungeon 开源） | 字段名与语义：`actor.MovementSpeed`、`ShootGunBehavior.LeadAmount = 0.62f`、`new Speed(6f, SpeedType.Absolute)`、`Wait(20)`=20 帧@60fps | `Speed(6)` 到底是多少米/秒（无权威换算） |
| `etg-xd.wikidot.com` 等中文库 | 模板里有 `{$shotspeed}` / `{$firerate}` 槽位 | 模板未渲染，取到的全是占位符 |

⇒ 处理分三级：

1. **照抄**（有精确值）：血量、**连发数**、扇形角度、死亡效果、预判有无。
2. **等比换算**（有约定）：伤害 = 1/6 玩家血。
3. **按定性排序近似**（无数据）：移动速度分 5 档（慢 2.0 / 中 2.4 / 快 3.4 / 浮空 1.8 /
   停留 0.6 m/s）、冷却分 3 档（occasionally 2.2 / rapidly 1.05 / periodically 2.6）、
   弹速以**玩家移速 4.5 m/s** 为锚取 3.5 倍 = 16（fast-moving 的 18~20）、射程 = `range × 1.4`。

**第 3 级只能保证序关系**：枪坚果比链枪手慢、布洛布微体比布洛布快、老兵比普通小子快、
"停留"的真的不动。绝对 m/s 没有原作依据，**引用时不要写成"原作 2.0 m/s"**。

## 5. 顺手修掉三处"原作写明了、我们做错了"

查 wiki 时对出来的，不是取舍，是错误：

| 怪 | 原作原文 | 修正前 | 修正后 |
|---|---|---|---|
| 老兵小子 | "They fire **4 bullets in a row**" | 单发 + 预判 | **4 连发**（interval 0.12）+ 预判 |
| 子弹榴弹王 | 只有"周期性向全向发射弹跳弹"，**没有 walks towards** | speed 1.43 会绕圈追人 | `immobile`，原地漂浮炮台 |
| 枪歌者 | "cancel their spell and **run away if the player is too close or they take too much damage**" | 站着把 buff 刷满，无中断 | 靠近 6m 或 2.5s 内受伤 → 中断并逃跑 2.5s |

枪歌者的中断是新机制（`_egt_interrupt_flee` / `_egt_hurt_window`），与既有的 `flee`
刻意分开：`flee` 是"整局只逃不回头"，这里的语义是"打断 → 逃几秒 → 回来继续施法"。

## 6. "子弹飞不出来"的真因：不是视觉，是射程

这是本轮最值得记的一条 —— 因为**所有既有探针都是绿的**。

排查方式：写 `_egt_bullet_visual_probe` 直接读 `Projectile3D._visual`。结果：

```
egt_bullet_kin  visual(ok/null/hidden)=1/0/0  speed=7.0  range=0.0  寿命上限=1.00s
```

视觉一直是好的（`_visual` 挂载正常、`visible=true`）。死因在另外两个字段：

```
range_m = 0  ⇒  max_lifetime = 1.0 s
弹速 7 m/s   ⇒  飞 7 米就自毁
```

而远程怪的 `attack_range` 是 8.8~9.8 m。也就是说：**怪站在射程边缘开火，子弹在离玩家
还有 2 米的地方凭空消失**。玩家看到的是"对面抬手了，但没有东西飞过来"。

修法：逐怪下发 `projectile_speed`（16~20）与 `projectile_range`（12~13.7），
`Projectile3D` 按 `range / speed × 1.5` 反推寿命。

**为什么以前没发现**：九个注册点的探针全部只验"有没有**排队射击事件**"
（`_pending_volleys.size()`）。"排队 8 发但一发都看不见"能一路绿灯。
这是探针的断言选错了层 —— 数了意图，没数结果。

## 7. 数值只有一处真源

`tools/retune_egt_monsters.py` 的 `SPEC` 是 33 只唯一的数值定义，写入三处：

| # | 位置 | 谁读它 | 覆盖关系 |
|---|---|---|---|
| ① | `Enemy3D.PROFILES` | `apply_profile()` / 攻击规格 | 最低 |
| ② | `MonsterInjector.BASE_ENEMY_TYPES` | 生成敌人数据 | 中 |
| ③ | `level_plan.json` 的 `stats.per_kind` | `override_max_hp/_damage/_speed` | **最高，最终值** |

漏改任何一处都会出现"设计文档写 150、游戏里打出来是 42"。
`_egt_tuning_runtime_probe.gd` 逐只比对 ③ 与实际生成结果，专门守这条。

## 8. 验收

| 项 | 命令 | 结果 |
|---|---|---|
| 注册一致性（9 点 × 33 只） | `--scene res://tools/_egt_monster_registry_probe.tscn` | `EGT_MONSTER_REGISTRY_PROBE_OK` |
| 数值/行为键/别名/关卡规则 | `--scene res://tools/_egt_monster_probe.tscn` | `EGT_MONSTER_PROBE_OK`（33 只） |
| **进场血量伤害逐只核对** | `--scene res://tools/_egt_tuning_runtime_probe.tscn` | `EGT_TUNING_RUNTIME_OK`（150/17、1000/17… 全对） |
| **子弹存在 + 可见 + 有射程** | `--scene res://tools/_egt_bullet_visual_probe.tscn` | `EGT_BULLET_VISUAL_PROBE_OK`（33 只） |
| 族内可区分 | `--scene res://tools/_egt_variant_visual_probe.tscn` | `EGT_VARIANT_VISUAL_PROBE_OK` |
| 编成与几何 | `--scene res://tools/_egt_roster_probe.tscn` | `EGT_ROSTER_PROBE_OK`（6 种子） |
| 真实进房 | `--scene res://tools/_egt_runtime_probe.tscn` | `EGT_RUNTIME_PROBE_OK` |
| 敌人行为回归 | `tests/verification/verify_3d_enemy_behavior_flow.tscn` | exit 0 |
| 强化怪回归 | `tests/verification/verify_strong_variant_monsters.tscn` | `STRONG_VARIANT_OK`（4261） |
| 资产结构门禁 | `check_asset_registry.py --scope structure` | `OK assets=1374` |
| 无损基线 | `verify_ledger_split.py` | 敌人域零问题（33 行指纹按白名单刷新） |

## 9. 这一轮**没有**解决的

1. **绝对手感仍未验**。倍数对齐了，但我们的玩家没有 EGT 的翻滚无敌帧，武器成长曲线也不同 ——
   打起来的绝对时长仍与原作不同。要真对齐，下一批得做闪避/无敌帧。
2. **同房间远程开火限流 2 只**（`MAX_RANGED_TOKENS_PER_TARGET`）没动。这是弹幕密度只有原作
   ~40% 的主因，但它影响**所有关卡**，不是远征03 专属，改动要单独决策。
3. **硝酸怪的线状爆炸**仍是圆形（§T6 #4）。
4. **速度/冷却/弹速的绝对值是自拟的**，只有序关系可信（§T2.5）。

## 10. 踩到的坑

**① 用错 group 下标把 `MonsterInjector` 的 33 行写坏了。**
一次批量替换里把 `m.group(2)` 当成"分隔符"，实际那是中文名 —— 结果写成了
`"hp_base": 150子弹小子17`。**这种破坏不会报错，只会在加载时静默错位**。
教训：批量改代码前先 `--dry-run` 打印，且替换模板只用**捕获组序号连续**的写法。

**② 探针自己的统计方式产生了 3 个假失败。**

- 用"场上子弹总数差"统计，上一只的子弹还没回收 ⇒ 计数变 -1、弹速取到别家的 4.2 → 6 个假红。
  改成按 `proj.shooter == enemy` 过滤。
- `chance`（骰子布洛布）随机选到 `contact` 招式本来就不出弹，打一次就判失败是拿随机性当缺陷。
  改成多打 6 轮，任一出一弹即通过。
- "单发弹速 < 12 判飘"把「吐蛋 4.2 m/s」「链球 6.4 m/s」判成 bug —— 那两个是**刻意慢**的。
  改成只校验**配置层** `projectile_speed`。

**③ `--script` 模式不加载 autoload。**
`godot --check-only --script src/enemy3d/Enemy3D.gd` 会报 `Identifier not found: MonsterAIManager`，
那不是语法错。语法检查要走 `--scene`。
