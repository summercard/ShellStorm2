# 远征03 怪物体型重定标：从 0.36m 的小地精到 1.0~1.7m 的敌人

**日期**：2026-10-30
**范围**：`Enemy3D.BODY_SCALE_BY_KIND` / `HEALTH_BAR_SIZE_BY_KIND` / `_egt_variant_visual_probe`
**起因**：业主「还有只怪物太小了，好像是用了小僵尸的模型做了分裂的怪物，怪物不用这么小。可以用其它模型」

## 1. 先量，再改

业主说"有只怪物太小"。靠肉眼只能猜是哪只、小到什么程度，所以先写了
`tools/_egt_enemy_size_probe.gd`，以**玩家身高 1.8m** 当唯一参照系（它是场景里恒定的尺），
逐只量「碰撞柱高 × 根节点 scale」= 世界高。

结果**不是一只小，是 13 只小**：

| 怪 | 借用资产 | 世界高 | 玩家比 |
|---|---|---|---|
| **egt_blobulin** | melee_chaser | **0.36m** | **0.20×** |
| egt_blobuloid | melee_chaser | 0.56m | 0.31× |
| egt_blobulon | melee_chaser | 0.91m | 0.51× |
| egt_bullat | exploder | 0.49m | 0.27× |
| egt_grenat | exploder | 0.63m | 0.35× |
| egt_keybullet_kin | melee_chaser | 0.78m | 0.43× |
| egt_chance_kin | melee_chaser | 0.82m | 0.45× |
| egt_nitra | exploder | 0.81m | 0.45× |
| egt_gun_fairy | ranged_caster | 0.88m | 0.49× |
| egt_pinhead | exploder | 0.90m | 0.50× |
| egt_shotgat | exploder | 0.56m | 0.31× |
| egt_spirat | exploder | 0.70m | 0.39× |
| egt_bullet_kin | ranged_caster | 0.98m | 0.54× |

0.36m ≈ 到玩家膝盖。它读起来是"花园地精"，不是"会杀了你的敌人"。

## 2. 根因：两层倍率相乘

```gdscript
scale = Vector3.ONE * DEFAULT_BASE_SIZE_MULTIPLIER(0.70) * BODY_SCALE_BY_KIND[kind]
世界高 = 资产基准高 × scale
```

`BODY_SCALE_BY_KIND` 的 egt 段写的是**族内相对阶梯**：

```
分裂族：blobulon 1.00 / blobuloid 0.62 / blobulin 0.40
```

写的人想的是"比母体小一圈"，这个意图本身是对的。但 0.40 要再乘 0.70 才落到世界：

```
1.30m（小僵尸基准高）× 0.70 × 0.40 = 0.36m
```

**缩放本身没有语义，世界高才有。** 所以"0.40 看起来很合理"——它相对母体确实只小 60%，
而母体自己也只有 0.91m。

## 3. 为什么不换模型

业主提到"可以用其它模型"。查过全仓：

```
assets/art/enemies/normal_enemy_3d/
  fat_zombie03/    胖僵尸
  melee_chaser/    野猪
  ranged_caster/   孢子射手
```

**普通怪模型只有这 3 个**，其余是 Boss（3 个）/ 精英（1 个）/ v001 未启用（2 个）。

32 只复刻怪本来就挤在这 3 个模型上（远程 10 只共用一个、分裂 4 只共用野猪）。
再换模型只会让更多怪撞脸 —— 那是把问题变严重，不是解决。

所以本轮改**体型**：同一模型放大到 1.0~1.7m，从"小僵尸"读起来就是"人形敌人"。
业主的诊断"用了小僵尸的模型"本身没错（分裂族确实借 `melee_chaser`），
但真正的病灶不是借了谁，是**借来的模型被缩到了 1/5**。

## 4. 改法：`TARGET_HEIGHT_M` 当唯一真源

新生成器 `tools/retune_egt_body_sizes.py`（与 `retune_egt_monsters.py` 同一定位：
单一真源，一次写两张表）：

```
BODY_SCALE = TARGET_HEIGHT / (资产基准高 × 0.70)
```

资产基准高取 `EnemyAvatar3D.FOOTPRINT_PROFILES[资产].height` —— 它本来就是按
"实际模块化模型的最大轮廓"定的，是最稳的高度代理，不用去量 mesh AABB
（拼装模型的 AABB 会被附件撑大）。

| 族 | 目标区间 |
|---|---|
| 远程族 | 1.22 ~ 1.52m |
| **分裂族** | **1.00 ~ 1.60m** |
| 爆炸族 | 1.00 ~ 1.48m |
| 法术 / 书怪族 | 1.30 ~ 1.70m |
| 触发 / 逃逸族 | 1.06 ~ 1.60m |

**下限 1.00m ≈ 玩家 0.55×**，这是"不用这么小"的可执行版本。

### 4.1 血条必须同步回算

`HEALTH_BAR_SIZE_BY_KIND` 的 egt 段原本是 `基类宽 × 旧缩放` 手算的。
只改缩放不改它 → "体型变大、血条还是窄的"，远看像贴错标签。
生成器按 `基类宽 × 新缩放` 重算，保留原可读性下限 0.72 与高度档
（爆炸族恒 0.14，否则一排黄条压满屏幕）。

### 4.2 未改的三只

`egt_chain_gunner` / `egt_gun_nut` / `egt_mimic` 借胖僵尸（基准 3.14m），
实测 2.5~2.6m —— **偏大不偏小**，业主没提。改它们等于顺手改玩法手感
（更大的碰撞柱 = 更容易被打到），没需求就不做。

## 5. 放大体型带来的新风险：碰撞柱撞门洞

碰撞柱是根节点的子节点，`scale` 一改它跟着改。这一步差点造出**硬卡死**：

| 怪 | 修前直径 | 修后直径 | 门洞 |
|---|---|---|---|
| egt_gunsinger | 1.97m | **2.278m** | 2.2m |
| egt_gunjurer | 1.86m | 2.145m | 2.2m |

`gunsinger` 的碰撞直径超过门洞 **7.8cm** —— 它物理上过不了门。

### 5.1 三条现成门禁都抓不到

| 门禁 | 为什么抓不到 |
|---|---|
| `_egt_roster_probe` | 只验刷怪盒落位几何，不验"怪能不能走出这间房" |
| `_egt_enemy_motion_probe` | 只验"不出房、不穿地"，**过不了门的怪恰好不会出房** |
| `verify_3d_enemy_behavior_flow` | 只验原生怪碰撞口径，不管 `egt_*` |

第二条尤其值得记：它看起来是最接近的判据（"位移越界"），但两者的失败模式正好相反 ——
出房的怪位移**过多**，过不了门的怪位移**过少**。同一条"位置越界"判据盖不住两个方向。

### 5.2 修法：以门洞为锚

```
碰撞直径 ≤ 门洞(2.2) × 0.85 = 1.87m   ⇒   半径上限 0.935m
```

留 15% 余量：① 门扇是双开推门，实际净宽略小于 2.2m；② 贴边过门还要算
`safe_margin = 0.035` 与转向擦碰。

**换算要注意**：碰撞柱是子节点，世界半径 = `shape.radius × (0.70 × kind_scale)`。
所以上限要**换算回局部**再比较，直接拿局部半径跟世界上限比会在大体型怪上漏过去。

### 5.3 踩了一次：通用约束不能无差别套

第一版 `_clamp_collision_radius()` 对所有怪生效，当场打挂回归：

```
ERROR: Non-zombie collision radius must be 1.2200, got 1.1131 (summoner)
ERROR: Non-zombie collision radius must be 1.9200, got 0.8905 (boss)
```

原因是原生怪的 `FOOTPRINT_PROFILES.radius` 是**玩法口径**而不是"模型宽度"：
`boss` 1.92 是为了巨型目标好打中、`summoner` 1.22 是刻意留的防穿模余量。

本轮的越界是**放大体型引入的**，所以只修被放大的那批 —— 加一个
`if not enemy_kind.begins_with("egt_")` 就直接放行。

> 这一条比 bug 本身更值得记：**"给所有怪加一条通用约束"永远是错的起点**，
> 先问"这条约束是谁的问题、它为什么会越界"。

### 5.4 视觉与碰撞的有意解耦

夹过之后模型比碰撞柱宽（`gunsinger` 约 18%）。这是刻意的：

| | 硬约束 | 能不能超 |
|---|---|---|
| 碰撞柱 | 关卡几何（门洞、走廊） | **不能** —— 超了就是走不过去 |
| 模型 | 观感 | 可以 —— 怪兽的爪子、披风本就常超出碰撞体 |

反过来（碰撞柱跟着模型任意放大）会造出"看得见、走不过门"的怪，
那比"边缘打空 18%"严重得多。

## 6. 判据也选错了变量

改完体型后 `_egt_variant_visual_probe` 报了三处"族内倒挂"：
血更厚的那只体型反而更小。查下去发现**规则对、判据错**：

| 怪 | 资产基准 | scale | 世界高 |
|---|---|---|---|
| egt_gripmaster | summoner 1.82m | 1.02 | **1.30m** |
| egt_chance_kin | melee_chaser 1.30m | 1.19 | **1.08m** |

`gripmaster` 的倍率更小、屏幕上却明显更高 —— 因为它的资产基准高 1.4 倍。
用 `scale` 判会得出「屏幕上一只明显更大、判据说它更小」。

这是**假报错**，和上一轮那种**假通过**是一对孪生问题：判据没测在"玩家实际看到的东西"上。

改判据为：

```gdscript
"world_height": FOOTPRINT_PROFILES[资产].height * enemy.scale.y
```

两处检查一起切过去：

| 检查 | 原判据 | 新判据 |
|---|---|---|
| 族内不撞车 | `world_scale` 相同 | **`world_height` 相同** |
| 族内不倒挂 | `body_scale` 随血量不降 | **`world_height` 随血量不降** |

切过去之后当场抓出一个**真实撞车**：`egt_keybullet_kin` 与 `egt_gun_fairy` 都是 1.02m
（不同资产、不同倍率，屏幕上一样大）。把 gun_fairy 提到 1.06m 解决。

### 6.1 反向验证

按上一轮定下的规矩，新判据必须证明自己抓得住 bug：

```
把 egt_blobulin（hp=10）的世界高抬到 1.82m，超过 egt_blobuloid（hp=100）
→ FAIL: 分裂族（三阶链） 族内倒挂：egt_blobuloid(hp=100,世界高=1.22m) 血量高于
        egt_blobulin(hp=10,世界高=1.82m) 却更小  ✓
```

## 7. 效果

| 项 | 修前 | 修后 |
|---|---|---|
| 最小怪世界高 | **0.36m**（0.20×） | **1.00m**（0.56×） |
| 高于 0.55× 的怪 | 20 / 33 | **33 / 33** |
| 分裂三阶 | 0.91 / 0.56 / **0.36** | 1.50 / 1.22 / **1.00** |
| 族内撞车 | 1 处 | 0 处 |
| 碰撞直径 > 门洞 | **2 只**（gunsinger 2.278m / gunjurer 2.145m） | **0 只**（全部 ≤ 1.87m） |
| 族内倒挂 | 0 处 | 0 处 |

对照图：`outputs/verification/egt_variant_lineup.png`（重出）。

## 8. 验收

| 探针 | 结果 |
|---|---|
| `_egt_enemy_size_probe`（新） | OK —— 33 只全部 ≥ 0.55× |
| `_egt_variant_visual_probe` | OK —— 改判据后按世界高判，无撞车无倒挂 |
| `_egt_enemy_motion_probe` | OK —— 变大后真实战斗无出房、无穿地、位移正常 |
| 其余 9 个 EGT 探针 | 全绿 |
| `verify_3d_enemy_behavior_flow` / `verify_strong_variant_monsters` / `verify_3d_combat_progression_flow` | 全绿 |

## 9. 顺带看到、但这轮不改

出图时注意到爆炸族（`egt_pinhead` / `egt_nitra` / `egt_bullat`）看起来是
"一个球 + 两块米白平板"。查过：那是 `EnemyAvatar3D._rebuild()` 里 exploder 分支的
程序化占位几何（`Claw` BoxMesh 当钳子、`Tank` CylinderMesh 当罐子），
**不是本轮改动引入的**（`git diff` 确认 `EnemyAvatar3D.gd` 零改动）。

它属于"程序化占位该不该重做"的美术议题，与"怪太小"是两件事。
业主没提，本轮不碰 —— 记在这里免得下次又被当成回归。
